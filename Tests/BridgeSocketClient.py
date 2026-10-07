import importlib.util
import sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('bridge', Path(__file__).resolve().parents[1]/'Bridge'/'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
value = {'version':1,'kind':'snapshot','binding':'web-socketfixture','epoch':'one','sequence':0,'url':'https://claude.ai/chat/synthetic','messages':[{'ordinal':2,'segment':0,'author':'assistant','text':'synthetic reply','completed':False}],'final':False}
response=bridge.send(sys.argv[1], value)
assert isinstance(response.get('requestUsage'),str) and len(response['requestUsage'])==36
unrelated={'version':1,'kind':'usage','binding':'web-other','epoch':'quota','sequence':0,'url':value['url'],'usage':{'rate_limits':{}}}
assert 'requestUsage' not in bridge.send(sys.argv[1],unrelated)
unrelated.update(binding=value['binding'],url='https://claude.ai/chat/another')
assert 'requestUsage' not in bridge.send(sys.argv[1],unrelated)
value['sequence'] = 1
value['readKey'] = True
try:
    bridge.send(sys.argv[1], value)
    raise RuntimeError('High privilege message was accepted')
except ValueError:
    pass
print('PASS: authenticated socket targets usage acquisition only at its exact binding/URL and rejects privileged commands')
