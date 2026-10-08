#!/usr/bin/env python3
"""Real loopback transport tests; no browser credentials or external requests."""
import hashlib
import hmac
import http.client
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('managed_web', ROOT / 'Bridge/web/service.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ManagedWebUsageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.events = []
        self.now = 100.0
        self.session = module.WebSession(Path(self.temp.name), ROOT / 'Bridge', self.events.append, clock=lambda: self.now)
        self.server = module.create_server(self.session, port=0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_port
        self.install = '1' * 32
        self.key = '2' * 64
        self.tab = '3' * 32
        self.doc = '4' * 32
        self.url = 'https://claude.ai/chat/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        self.seq = 0

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.temp.cleanup()

    def request(self, path, body=None, headers=None, method='POST'):
        raw = json.dumps(body, separators=(',', ':')).encode() if body is not None else b''
        headers = {'Content-Type': 'application/json', **(headers or {})}
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=2)
        connection.request(method, path, body=raw, headers=headers)
        response = connection.getresponse()
        data = response.read()
        result = (response.status, dict(response.getheaders()), data)
        connection.close()
        return result

    def packet(self, **extra):
        self.seq += 1
        return dict(installID=self.install, tabID=self.tab, documentID=self.doc, url=self.url,
                    focused=True, visible=True, epoch=self.session.epoch, sequence=self.seq, **extra)

    def signed(self, path, body):
        raw = json.dumps(body, separators=(',', ':')).encode()
        signature = hmac.new(bytes.fromhex(self.key), path.encode() + b'\n' + raw, hashlib.sha256).hexdigest()
        return self.request(path, body, {'X-AChu-Signature': signature})

    def pair(self):
        self.session.setup('com.google.Chrome')
        self.session.bind(self.url, 'com.google.Chrome')
        challenge = self.session.challenge
        body = self.packet(key=self.key, challenge=challenge)
        status, _, _ = self.request('/pair', body, {'X-AChu-Capability': self.session.capability})
        self.assertEqual(status, 202)
        self.now += .25
        self.session.tick()
        self.assertIsNotNone(self.session.bound)
        return self.session.bound

    def test_setup_is_private_and_installer_has_no_long_term_key(self):
        self.session.setup('com.google.Chrome')
        status, headers, script = self.request('/install/' + self.session.capability + '/usage.user.js', method='GET')
        self.assertEqual(status, 200)
        self.assertIn(b'@match        https://claude.ai/*', script)
        self.assertNotIn(self.key.encode(), script)
        self.assertNotIn('Access-Control-Allow-Origin', headers)

    def test_unique_focused_page_pairs_and_persists_private_authorization(self):
        self.pair()
        state = Path(self.temp.name) / 'authorization.json'
        self.assertEqual(state.stat().st_mode & 0o777, 0o600)
        restored = module.WebSession(Path(self.temp.name), ROOT / 'Bridge', lambda _: None)
        self.assertIn(self.install, restored.installations)
        self.assertNotEqual(restored.epoch, self.session.epoch)

    def test_background_page_cannot_claim_authorization(self):
        self.session.setup('com.google.Chrome')
        self.session.bind(self.url, 'com.google.Chrome')
        body = self.packet(key=self.key, challenge=self.session.challenge)
        body['focused'] = False
        status, _, _ = self.request('/pair', body, {'X-AChu-Capability': self.session.capability})
        self.assertEqual(status, 403)
        self.assertFalse(self.session.installations)

    def test_same_url_multiple_focused_candidates_do_not_guess(self):
        self.session.setup('com.google.Chrome')
        self.session.bind(self.url, 'com.google.Chrome')
        capability = self.session.capability
        challenge = self.session.challenge
        for tab in ['3' * 32, '5' * 32]:
            body = self.packet(key=self.key, challenge=challenge)
            body['tabID'] = tab
            self.assertEqual(self.request('/pair', body, {'X-AChu-Capability': capability})[0], 202)
        self.now += .25
        self.session.tick()
        self.assertIsNone(self.session.bound)
        self.assertFalse(self.session.installations)

    def test_late_pair_and_expired_capability_are_rejected(self):
        self.session.setup('com.google.Chrome')
        self.session.bind(self.url, 'com.google.Chrome')
        body = self.packet(key=self.key, challenge=self.session.challenge)
        self.now += 2
        self.session.tick()
        self.assertEqual(self.request('/pair', body, {'X-AChu-Capability': self.session.capability})[0], 403)
        self.now += 300
        self.assertEqual(self.request('/hello', self.packet(), {'X-AChu-Capability': self.session.capability})[0], 403)

    def test_wrong_host_origin_and_simple_form_requests_are_rejected(self):
        for headers in [{'Host': 'evil.example'}, {'Origin': 'https://evil.example'}, {'Content-Type': 'text/plain'}]:
            self.assertIn(self.request('/poll', self.packet(), headers)[0], [400, 403, 415])

    def test_invalid_signature_old_epoch_and_replay_are_rejected(self):
        self.pair()
        body = self.packet()
        self.assertEqual(self.request('/poll', body, {'X-AChu-Signature': '0' * 64})[0], 403)
        self.assertEqual(self.signed('/poll', body)[0], 200)
        self.assertEqual(self.signed('/poll', body)[0], 409)
        body = self.packet()
        body['epoch'] = 'old-application-epoch'
        self.assertEqual(self.signed('/poll', body)[0], 409)

    def test_bound_tab_only_and_secret_payload_fields_rejected(self):
        self.pair()
        body = self.packet(status='ok', account={'fingerprint': 'a' * 64, 'displayName': 'a***@example.test'},
                           usage={'rate_limits': {'five_hour': {'used_percentage': 12, 'resets_at': 1900000000}}})
        self.assertEqual(self.signed('/report', body)[0], 200)
        self.assertEqual(self.events[-1]['kind'], 'usage')
        other = self.packet(status='ok', account=body['account'], usage=body['usage'])
        other['tabID'] = '9' * 32
        self.assertEqual(self.signed('/report', other)[0], 403)
        leaked = self.packet(status='ok', account=body['account'], usage=body['usage'], cookie='must-never-pass')
        self.assertEqual(self.signed('/report', leaked)[0], 400)

    def test_failed_read_and_heartbeat_timeout_withdraw_old_quota(self):
        self.pair()
        self.assertEqual(self.signed('/report', self.packet(status='unavailable'))[0], 200)
        self.assertEqual(self.events[-1]['kind'], 'invalid')
        self.now += 16
        self.session.tick()
        self.assertIsNone(self.session.bound)
        self.assertEqual(self.events[-1]['kind'], 'disconnected')

    def test_navigation_refresh_preserves_tab_and_retires_old_document(self):
        self.pair()
        self.doc = '6' * 32
        self.url = 'https://claude.ai/code/session_test123'
        self.assertEqual(self.signed('/poll', self.packet())[0], 200)
        self.assertEqual(self.session.bound['documentID'], self.doc)
        body = self.packet()
        body['documentID'] = '4' * 32
        self.assertEqual(self.signed('/poll', body)[0], 409)

    def test_wrong_address_and_oversized_requests_are_rejected(self):
        self.pair()
        body = self.packet()
        body['url'] = 'https://claude.ai.evil.example/chat/test'
        self.assertEqual(self.signed('/poll', body)[0], 400)
        self.assertEqual(self.request('/poll', {'padding': 'x' * 20000})[0], 413)

    def test_revoke_clears_authorizations_and_rejects_previous_client(self):
        self.pair()
        self.session.revoke()
        self.assertFalse(self.session.installations)
        self.assertIsNone(self.session.bound)
        self.assertEqual(self.signed('/poll', self.packet())[0], 403)

    def test_temporarily_suspended_bound_tab_recovers_without_another_authorization(self):
        previous = self.pair()['binding']
        self.now += 16
        self.session.tick()
        self.assertIsNone(self.session.bound)
        self.assertEqual(self.signed('/poll', self.packet())[0], 200)
        self.assertEqual(self.session.bound['binding'], previous)

    def test_quota_epochs_allow_returning_account_and_sequence_survives_refresh(self):
        self.pair()
        reports = []
        for fingerprint in ['a', 'b', 'a']:
            body = self.packet(status='ok', account={'fingerprint': fingerprint * 64, 'displayName': fingerprint + '***@example.test'},
                               usage={'rate_limits': {'seven_day': {'used_percentage': 30}}})
            self.assertEqual(self.signed('/report', body)[0], 200)
            reports.append(self.events[-1])
        self.assertEqual(len({report['epoch'] for report in reports}), 3)
        self.doc = '8' * 32
        self.seq = 0
        self.assertEqual(self.signed('/poll', self.packet())[0], 200)
        body = self.packet(status='unavailable')
        self.assertEqual(self.signed('/report', body)[0], 200)
        self.assertGreater(self.events[-1]['sequence'], reports[-1]['sequence'])

    def test_quota_boolean_full_email_and_extra_fields_are_rejected(self):
        self.pair()
        for change in ['boolean', 'email', 'secret']:
            account = {'fingerprint': 'a' * 64, 'displayName': 'a***@example.test'}
            usage = {'rate_limits': {'five_hour': {'used_percentage': 20}}}
            if change == 'boolean':
                usage['rate_limits']['five_hour']['used_percentage'] = True
            if change == 'email':
                account['displayName'] = 'alpha@example.test'
            if change == 'secret':
                usage['token'] = 'forbidden'
            self.assertEqual(self.signed('/report', self.packet(status='ok', account=account, usage=usage))[0], 400)


if __name__ == '__main__':
    unittest.main(verbosity=2)
