"""Synthetic messages sent only to the test coordinator's private socket."""
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location('bridge', Path(__file__).resolve().parents[1] / 'Bridge' / 'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
for binding in ('cli-routing-one', 'cli-routing-two'):
    value = {'version': 1, 'kind': 'usage', 'binding': binding, 'epoch': 'synthetic-routing',
             'sequence': 0, 'usage': {'rate_limits': {}},
             'source': {'workspace': 'Synthetic One' if binding.endswith('one') else 'Synthetic Two', 'model': 'Synthetic model'},
             'account': {'fingerprint': 'a' * 64, 'displayName': 'Synthetic routing'}}
    assert bridge.send(sys.argv[1], value)['ok'] is True
