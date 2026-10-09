"""Authenticated synthetic reports for CLI input tests, no real CLI invocation."""
import importlib.util
import hashlib
import sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('bridge69',Path(__file__).resolve().parents[1]/'Bridge/bridge.py')
bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
for index, letter in enumerate(('a','b')):
    binding='cli-'+letter*64
    mode=sys.argv[2] if len(sys.argv)>2 else 'report'
    if len(sys.argv)>2 and sys.argv[2]=='delta':
        if letter!='a': continue
        value={'version':1,'kind':'delta','binding':binding,'epoch':'synthetic-delivery','sequence':0,
               'messageID':'first','turnID':'synthetic-turn','text':'Complete synthetic reply.','final':True}
    else:
        started='Mon Oct 5 11:59:00 2026'
        value={'version':1,'kind':'usage','binding':binding,'epoch':'synthetic-delivery','sequence':index+(20 if mode=='read-only' else 30 if mode=='refresh' else 0),
               'usage':{'rate_limits':{}},'source':{'workspace':'Synthetic '+letter,'model':'Synthetic model'},
               'delivery':{'pid':40,'tty':'ttys003','started':started,
                           'tag':hashlib.sha256((binding+'\0'+'40'+'\0'+started).encode()).hexdigest()[:20]}}
        if mode=='read-only': value.pop('delivery')
    assert bridge.send(sys.argv[1],value)['ok'] is True
