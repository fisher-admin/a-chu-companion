import importlib.util
import io
import json
import struct
import tempfile
import unittest
import hashlib
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('achu_bridge', ROOT / 'Bridge' / 'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

class TinyReads(io.BytesIO):
    def read(self, size=-1):
        return super().read(min(size, 1) if size > 0 else size)

class BridgeTests(unittest.TestCase):
    def test_binding_tracks_session_not_terminal_or_working_directory(self):
        first = {'session_id':'one-session', 'cwd':'/synthetic/project', 'terminal':'Carrier A'}
        moved = dict(first, cwd='/synthetic/project/subdirectory', terminal='Carrier B')
        self.assertEqual(bridge.binding(first), bridge.binding(moved), 'one session must not become extra choices when cwd changes')
        self.assertNotEqual(bridge.binding(first), bridge.binding(dict(first, session_id='second-session')))

    def test_source_summary_excludes_full_paths_and_arbitrary_metadata(self):
        payload = {'session_id':'summary', 'cwd':'/private/synthetic/project', 'workspace':{'current_dir':'/private/synthetic/project'},
                   'model':{'display_name':'Opus'}, 'transcript_path':'private-transcript', 'unrelated':'do-not-relay', 'rate_limits':{}}
        result = bridge.status_envelope(payload)
        self.assertEqual(result.get('source'), {'workspace':'project','model':'Opus'})
        self.assertNotIn('/private/synthetic', json.dumps(result)); self.assertNotIn('private-transcript', json.dumps(result))
        self.assertNotIn('do-not-relay', json.dumps(result))

    def test_source_summary_sanitizes_terminal_controls_and_bounds_names(self):
        value = bridge.status_envelope({'session_id':'clean','cwd':'/private/\x1b[31mProject\nName', 'model':{'display_name':'\x1b[2J'+'m'*200},'rate_limits':{}})
        source = value.get('source', {})
        self.assertTrue(source.get('workspace'), 'safe source labels are needed')
        self.assertNotIn('\x1b', str(source)); self.assertNotIn('\n', str(source))
        self.assertLessEqual(len(source.get('workspace','')),80); self.assertLessEqual(len(source.get('model','')),80)
        self.assertEqual(bridge.source_summary({'cwd':'/synthetic/project\\name'})['workspace'], 'projectname')

    def legacy_state(self, directory, session, cwd, identity, invalidated=False, sequence=10):
        stem = 'cli-' + hashlib.sha256((session+'\0'+cwd).encode()).hexdigest()
        path=Path(directory)/(stem+'.json')
        path.write_text(json.dumps({'epoch':'legacy-epoch','sequence':sequence,'identity':identity,'invalidated':invalidated}))
        os.chmod(path,0o600)

    def test_exact_legacy_account_state_migrates_across_directory_change(self):
        with tempfile.TemporaryDirectory() as directory:
            login={'loggedIn':True,'authMethod':'claude.ai','apiProvider':'firstParty','email':'first@example.test'}
            tracker=bridge.CLIAccountTracker(Path(directory)/'state',lambda:login)
            identity=bridge.account_identity(login)
            self.legacy_state(tracker.directory,'existing','/synthetic/project',identity)
            value={'session_id':'existing','cwd':'/synthetic/project/subdir','workspace':{'project_dir':'/synthetic/project'}}
            self.assertEqual(tracker.report(value).get('account'),identity,'upgrade must use only the exactly matched original session state')
            self.assertEqual(tracker.report(dict(value,cwd='/elsewhere')).get('account'),identity)
            self.assertNotIn('account',tracker.report(dict(value,session_id='unrelated')))

    def test_legacy_invalidated_and_conflicting_accounts_remain_quarantined(self):
        with tempfile.TemporaryDirectory() as directory:
            login={'loggedIn':True,'authMethod':'claude.ai','apiProvider':'firstParty','email':'first@example.test'}
            tracker=bridge.CLIAccountTracker(Path(directory)/'state',lambda:login); identity=bridge.account_identity(login)
            self.legacy_state(tracker.directory,'invalid','/synthetic/project',identity,True)
            value={'session_id':'invalid','cwd':'/synthetic/project/subdir','workspace':{'project_dir':'/synthetic/project'}}
            self.assertNotIn('account',tracker.report(value))
            second=bridge.account_identity(dict(login,email='second@example.test'))
            self.legacy_state(tracker.directory,'conflict','/synthetic/project',identity)
            self.legacy_state(tracker.directory,'conflict','/synthetic/project/subdir',second)
            self.assertNotIn('account',tracker.report(dict(value,session_id='conflict')))

    def test_statusline_exposes_matching_identifier_and_preserves_user_output(self):
        payload={'session_id':'visible','cwd':'/private/synthetic/project','model':{'display_name':'Opus'},'rate_limits':{}}
        with tempfile.TemporaryDirectory() as directory:
            command=[sys.executable,str(ROOT/'Bridge/bridge.py'),'--statusline','--connection',str(Path(directory)/'missing.json'),
                     '--original-status',json.dumps({'type':'command','command':'printf USER-STATUS'})]
            result=subprocess.run(command,input=json.dumps(payload),capture_output=True,text=True,check=True)
            self.assertIn('USER-STATUS',result.stdout)
            self.assertIn(bridge.binding(payload)[-6:],result.stdout,'terminal and companion need the same recognizable session identifier')
            self.assertIn('project',result.stdout); self.assertNotIn('/private/synthetic',result.stdout)

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
