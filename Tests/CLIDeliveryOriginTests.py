"""Synthetic process trees only; never controls or reads a real terminal."""
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('bridge69', Path(__file__).resolve().parents[1] / 'Bridge/bridge.py')
bridge = importlib.util.module_from_spec(spec); spec.loader.exec_module(bridge)

class OriginTests(unittest.TestCase):
    def test_native_cli_capitalized_process_title_requires_foreground_tty(self):
        item={'pid':40,'parent':20,'group':40,'foreground':40,'tty':'ttys003','started':'Wed Oct 7 20:05:43 2026','uid':501,'command':'Claude'}
        origin=bridge.delivery_origin({'session_id':'native-title'},reader=lambda _:item,parent=40,uid=501)
        self.assertIsNotNone(origin)
        self.assertEqual(origin['pid'],40)
        for changes in [{'tty':'??'},{'foreground':0},{'command':'Claude Helper'}]:
            changed=dict(item,**changes)
            self.assertIsNone(bridge.delivery_origin({'session_id':'native-title'},reader=lambda _:changed if _==40 else None,parent=40,uid=501))
    def test_origin_comes_from_live_claude_ancestor_not_payload(self):
        self.assertTrue(hasattr(bridge, 'delivery_origin'), 'missing live CLI origin prevents automatic input binding')
        tree = {
            50: {'pid':50,'parent':40,'group':30,'foreground':30,'tty':'ttys003','started':'Mon Oct  5 12:00:00 2026','uid':501,'command':'/bin/sh'},
            40: {'pid':40,'parent':20,'group':30,'foreground':30,'tty':'ttys003','started':'Mon Oct  5 11:59:00 2026','uid':501,'command':'/synthetic/.local/share/claude/versions/2.1.0'},
        }
        origin = bridge.delivery_origin({'session_id':'one','delivery':{'pid':666}}, reader=tree.get, parent=50, uid=501)
        self.assertEqual(set(origin), {'pid','tty','started','tag'})
        self.assertEqual(origin['pid'],40); self.assertEqual(origin['tty'],'ttys003')
        self.assertEqual(len(origin['tag']),20)
        self.assertEqual(origin,bridge.delivery_origin({'session_id':'one'},reader=tree.get,parent=50,uid=501))
        self.assertNotEqual(origin['tag'],bridge.delivery_origin({'session_id':'two'},reader=tree.get,parent=50,uid=501)['tag'])
        for key, value in [('foreground',20),('tty','??'),('uid',502),('command','/bin/zsh')]:
            modified={k:dict(v) for k,v in tree.items()}; modified[40][key]=value
            self.assertIsNone(bridge.delivery_origin({'session_id':'one'},reader=modified.get,parent=50,uid=501),key)
        modified={k:dict(v) for k,v in tree.items()}; modified[40]['started']='Mon Oct  5 12:01:00 2026'
        self.assertNotEqual(origin['tag'],bridge.delivery_origin({'session_id':'one'},reader=modified.get,parent=50,uid=501)['tag'])
    def test_no_tty_or_cycles_provide_no_sending_target(self):
        self.assertTrue(hasattr(bridge,'delivery_origin'),'missing conservative origin discovery')
        loop={'pid':5,'parent':5,'group':5,'foreground':5,'tty':'ttys003','started':'Mon Oct  5 12:00:00 2026','uid':501,'command':'/bin/sh'}
        self.assertIsNone(bridge.delivery_origin({'session_id':'one'},reader=lambda _:loop,parent=5,uid=501))
        self.assertIsNone(bridge.delivery_origin({'session_id':'one'},reader=lambda _:None,parent=5,uid=501))
    def test_footer_carries_process_bound_input_marker_and_keeps_read_identifier(self):
        self.assertTrue(hasattr(bridge,'delivery_origin'),'missing process-bound footer marker')
        origin={'pid':40,'tty':'ttys003','started':'Mon Oct  5 11:59:00 2026','tag':'abcdef123456abcdef12'}
        self.assertIn('输入 abcdef123456abcdef12',bridge.status_label({'session_id':'one','cwd':'/synthetic/project'},origin))
        self.assertIn(bridge.binding({'session_id':'one'})[-6:],bridge.status_label({'session_id':'one'},origin))
        self.assertNotIn('输入 ',bridge.status_label({'session_id':'one'}))

if __name__=='__main__': unittest.main()
