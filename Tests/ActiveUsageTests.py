import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('active_bridge', Path(__file__).resolve().parents[1]/'Bridge/bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

class ActiveUsageTests(unittest.TestCase):
    def test_request_runs_owned_command_and_uninstall_restores_user(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = {'statusLine':{'type':'command','command':'printf KEEP','padding':3},'alwaysThinkingEnabled':True}
            (root/'settings.json').write_text(json.dumps(original))
            bridge.install_cli(root, root/'connection.json')
            installed = json.loads((root/'settings.json').read_text())
            self.assertEqual(installed['statusLine']['refreshInterval'], 30)
            bridge.request_cli(root)
            requested = json.loads((root/'settings.json').read_text())
            self.assertNotEqual(requested['statusLine']['command'], installed['statusLine']['command'])
            self.assertTrue(requested['alwaysThinkingEnabled'])
            bridge.uninstall_cli(root)
            self.assertEqual(json.loads((root/'settings.json').read_text()), original)

    def test_request_never_overwrites_changed_or_missing_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            with self.assertRaises(ValueError): bridge.request_cli(root)
            bridge.install_cli(root, root/'connection.json')
            settings=json.loads((root/'settings.json').read_text())
            settings['statusLine']={'type':'command','command':'printf USER'}
            (root/'settings.json').write_text(json.dumps(settings))
            before=(root/'settings.json').read_bytes()
            with self.assertRaises(ValueError): bridge.request_cli(root)
            self.assertEqual((root/'settings.json').read_bytes(),before)

if __name__=='__main__': unittest.main()
