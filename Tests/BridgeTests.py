import importlib.util
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('achu_bridge', ROOT / 'Bridge' / 'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

class TinyReads(io.BytesIO):
    def read(self, size=-1):
        return super().read(min(size, 1) if size > 0 else size)

class BridgeTests(unittest.TestCase):
    def test_native_fragmented_unicode_and_eof(self):
        value = {'text': '中文😀'}
        data = json.dumps(value, ensure_ascii=False).encode()
        self.assertEqual(bridge.read_native(TinyReads(struct.pack('=I', len(data)) + data)), value)
        self.assertIsNone(bridge.read_native(io.BytesIO()))
        with self.assertRaises(ValueError):
            bridge.read_native(io.BytesIO(struct.pack('=I', 9_000_000)))
        with self.assertRaises(ValueError):
            bridge.read_native(io.BytesIO(b'\x02'))

    def test_hook_drops_private_metadata_and_accepts_empty_final(self):
        payload = {'session_id':'test-session', 'cwd':'/private/synthetic', 'transcript_path':'do-not-relay', 'turn_id':'turn', 'message_id':'msg', 'index':1, 'final':True, 'delta':''}
        value = bridge.hook_envelope(payload)
        self.assertEqual(value['kind'], 'delta')
        self.assertTrue(value['final'])
        self.assertNotIn('cwd', value)
        self.assertNotIn('transcript_path', value)
        self.assertNotIn('/private/synthetic', json.dumps(value))

    def test_unverified_statusline_uses_increasing_capture_order(self):
        first = bridge.status_envelope({'session_id':'test', 'rate_limits':{}})
        second = bridge.status_envelope({'session_id':'test', 'rate_limits':{}})
        self.assertGreater(second['sequence'], first['sequence'], 'status reports must not all have sequence zero')

    def test_sessionstart_account_binding_and_switch_quarantine(self):
        self.assertTrue(hasattr(bridge, 'CLIAccountTracker'), 'CLI identity needs a session-bound tracker')
        with tempfile.TemporaryDirectory() as directory:
            current = {'loggedIn':True, 'authMethod':'claude.ai', 'apiProvider':'firstParty', 'email':'first@example.test'}
            tracker = bridge.CLIAccountTracker(Path(directory)/'state', lambda: dict(current))
            start = {'session_id':'one', 'cwd':'/synthetic', 'source':'startup'}
            tracker.start(start)
            one = tracker.report(start)
            self.assertIn('fingerprint', one['account'])
            self.assertNotIn('first@example.test', json.dumps(one))
            self.assertGreater(tracker.report(start)['sequence'], one['sequence'])
            current['email'] = 'second@example.test'
            old = tracker.report(start)
            self.assertNotIn('account', old, 'a new global login must not relabel old-process usage')
            tracker.start(dict(start, source='resume'))
            self.assertNotIn('account', tracker.report(start), 'resuming an old session cannot bless the new global account')
            current['email'] = 'first@example.test'
            self.assertNotIn('account', tracker.report(start), 'the old session stays invalidated until restart')
            current['email'] = 'second@example.test'
            new = dict(start, session_id='two')
            tracker.start(new)
            self.assertNotEqual(tracker.report(new)['account']['fingerprint'], one['account']['fingerprint'])
            self.assertNotIn('account', tracker.report(dict(start, session_id='unknown-old-session')))
            current.clear()
            self.assertNotIn('account', tracker.report(new))

    def test_install_accounts_hook_and_preserve_user_hook(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            user = {'matcher':'startup', 'hooks':[{'type':'command','command':'printf KEEP'}]}
            (root/'settings.json').write_text(json.dumps({'hooks':{'SessionStart':[user]}}))
            bridge.install_cli(root, root/'connection.json')
            installed = json.loads((root/'settings.json').read_text())
            self.assertEqual(len(installed['hooks']['SessionStart']), 2)
            bridge.uninstall_cli(root)
            self.assertEqual(json.loads((root/'settings.json').read_text())['hooks']['SessionStart'], [user])

    def test_statusline_excludes_spend(self):
        value = bridge.status_envelope({'session_id':'test', 'rate_limits':{'seven_day':{'used_percentage':50},'spend_limit':{'used_usd':20}}, 'api_key':'never-forward'})
        self.assertEqual(set(value['usage']['rate_limits']), {'seven_day'})
        self.assertNotIn('api_key', json.dumps(value))

    def test_install_uninstall_three_way(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = root / 'settings.json'
            original = {'statusLine':{'type':'command','command':'printf ORIGINAL'},'hooks':{'Stop':[{'hooks':[{'type':'command','command':'printf keep'}]}]}}
            settings.write_text(json.dumps(original))
            bridge.install_cli(root, root / 'connection.json', message_display=True)
            installed = json.loads(settings.read_text())
            self.assertEqual(installed['hooks']['Stop'], original['hooks']['Stop'])
            bridge.install_cli(root, root / 'connection.json', message_display=True)
            self.assertEqual(json.loads(settings.read_text()), installed)
            installed['newPreference'] = True
            settings.write_text(json.dumps(installed))
            bridge.uninstall_cli(root)
            result = json.loads(settings.read_text())
            self.assertEqual(result['statusLine'], original['statusLine'])
            self.assertTrue(result['newPreference'])
            self.assertNotIn('MessageDisplay', result['hooks'])

    def test_install_statusline_only_until_capability_confirmed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bridge.install_cli(root, root/'connection.json')
            settings = json.loads((root/'settings.json').read_text())
            self.assertNotIn('MessageDisplay', settings['hooks'])
            bridge.uninstall_cli(root)

    def test_interrupted_install_resumes_without_duplicate_hook(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bridge.install_cli(root, root/'connection.json', True)
            state_path = root/'achu-bridge-install.json'
            state = json.loads(state_path.read_text()); state['complete'] = False
            state_path.write_text(json.dumps(state))
            bridge.install_cli(root, root/'connection.json', True)
            self.assertEqual(len(json.loads((root/'settings.json').read_text())['hooks']['MessageDisplay']), 1)
            bridge.uninstall_cli(root)
            self.assertNotIn('statusLine', json.loads((root/'settings.json').read_text()))

    def test_uninstall_preserves_user_changed_statusline(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'settings.json').write_text('{}')
            bridge.install_cli(root, root/'connection.json')
            settings = json.loads((root/'settings.json').read_text())
            settings['statusLine'] = {'type':'command','command':'printf USER_CHANGED'}
            (root/'settings.json').write_text(json.dumps(settings))
            bridge.uninstall_cli(root)
            self.assertEqual(json.loads((root/'settings.json').read_text())['statusLine']['command'], 'printf USER_CHANGED')

    def test_malformed_settings_are_rejected_without_changes(self):
        for value in [[], {'hooks':[]}, {'hooks':{'MessageDisplay':{}}}]:
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root/'settings.json'
                path.write_text(json.dumps(value))
                before = path.read_bytes()
                with self.assertRaises(ValueError):
                    bridge.install_cli(root, root/'connection.json', True)
                self.assertEqual(path.read_bytes(), before)
                self.assertFalse((root/'achu-bridge-install.json').exists())

if __name__ == '__main__':
    unittest.main()
