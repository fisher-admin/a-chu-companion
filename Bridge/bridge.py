#!/usr/bin/env python3
"""Read-only local bridge. Never opens Claude, reads OAuth, or stores chat text."""
import argparse
import hashlib
import fcntl
import json
import os
import shlex
import shutil
import socket
import stat
import struct
import subprocess
import sys
import uuid
from pathlib import Path

MAX_FRAME = 8 * 1024 * 1024
_capture_sequence = 0

def exact(stream, size):
    result = bytearray()
    while len(result) < size:
        part = stream.read(size - len(result))
        if not part:
            if not result:
                return None
            raise ValueError('Incomplete frame')
        result.extend(part)
    return bytes(result)

def read_native(stream):
    header = exact(stream, 4)
    if header is None:
        return None
    size = struct.unpack('=I', header)[0]
    if not 0 < size <= MAX_FRAME:
        raise ValueError('Frame size rejected')
    body = exact(stream, size)
    if body is None:
        raise ValueError('Incomplete frame')
    value = json.loads(body.decode('utf-8'))
    if not isinstance(value, dict):
        raise ValueError('Object required')
    return value

def write_native(stream, value):
    data = json.dumps(value, ensure_ascii=False).encode()
    if len(data) > 1024 * 1024:
        raise ValueError('Outbound frame exceeds Chrome limit')
    stream.write(struct.pack('=I', len(data)) + data)
    stream.flush()

def binding(value):
    session = value.get('session_id', '')
    if not isinstance(session, str) or not session:
        raise ValueError('Session required')
    return 'cli-' + hashlib.sha256((session + '\0' + str(value.get('cwd', ''))).encode()).hexdigest()

def hook_envelope(value):
    for key in ('message_id', 'turn_id', 'delta'):
        if not isinstance(value.get(key), str):
            raise ValueError('Invalid hook text')
    index = value.get('index')
    if type(index) is not int or index < 0 or type(value.get('final')) is not bool:
        raise ValueError('Invalid batch')
    return {'version':1, 'kind':'delta', 'binding':binding(value), 'epoch':value['session_id'],
            'sequence':index, 'messageID':value['message_id'], 'turnID':value['turn_id'],
            'text':value['delta'], 'final':value['final']}

def status_envelope(value, context=None):
    global _capture_sequence
    _capture_sequence += 1
    limits = value.get('rate_limits') or {}
    if not isinstance(limits, dict):
        raise ValueError('Invalid rate limit shape')
    selected = {k:{field:v for field,v in limits[k].items() if field in ('used_percentage','resets_at')}
                for k in ('five_hour','seven_day') if isinstance(limits.get(k), dict)}
    return {'version':1, 'kind':'usage', 'binding':binding(value), 'epoch':value['session_id'],
            'sequence':_capture_sequence, 'usage':{'rate_limits':selected}, **(context or {})}

def official_cli_identity():
    """Official metadata only. Never read an OAuth/keychain item or relay raw stdout."""
    executable = shutil.which('claude')
    if not executable:
        return {}
    try:
        result = subprocess.run([executable, 'auth', 'status'], capture_output=True, timeout=2, check=False)
        if result.returncode != 0 or len(result.stdout) > 65536:
            return {}
        value = json.loads(result.stdout)
        return value if isinstance(value, dict) else {}
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return {}

def account_identity(value):
    if value.get('loggedIn') is not True or value.get('authMethod') != 'claude.ai' or value.get('apiProvider') != 'firstParty':
        return None
    email = value.get('email')
    if not isinstance(email, str) or len(email) > 254 or email.count('@') != 1 or any(char.isspace() for char in email):
        return None
    normalized = email.strip().lower()
    fingerprint = hashlib.sha256(('claude-account-email\0' + normalized).encode()).hexdigest()
    # The local UI can distinguish accounts; raw email never leaves this function.
    local, domain = normalized.split('@')
    if not local or '.' not in domain:
        return None
    return {'fingerprint':fingerprint, 'displayName':(local[0] + '***@' + domain)[:80]}

class CLIAccountTracker:
    def __init__(self, directory, reader=official_cli_identity):
        self.directory = Path(directory)
        self.reader = reader
        if self.directory.is_symlink():
            raise ValueError('Private account state required')
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        metadata = self.directory.stat()
        if metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
            raise ValueError('Private account state required')

    def _locked(self, value, change):
        stem = binding(value)
        path = self.directory/(stem + '.json')
        lock_path = self.directory/(stem + '.lock')
        if not path.exists() and len(list(self.directory.glob('cli-*.json'))) >= 256:
            raise ValueError('Too many account states')
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            metadata = os.fstat(fd)
            if metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
                raise ValueError('Private lock required')
            fcntl.flock(fd, fcntl.LOCK_EX)
            state = None
            if path.exists():
                if path.is_symlink() or path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
                    raise ValueError('Private state required')
                state = json.loads(path.read_text())
            result, state = change(state)
            atomic(path, state)
            return result
        finally:
            os.close(fd)

    def start(self, value):
        # Clear/compact events cannot bless an old process with a new global login.
        if value.get('source') not in ('startup', 'resume'):
            return
        identity = account_identity(self.reader())
        def change(old):
            if old and (old.get('invalidated') or old.get('identity') != identity):
                old['invalidated'] = True
                return None, old
            state = {'epoch':str(uuid.uuid4()), 'sequence':0, 'identity':identity, 'invalidated':identity is None}
            return None, state
        return self._locked(value, change)

    def report(self, value):
        current = account_identity(self.reader())
        def change(state):
            state = state or {'epoch':str(uuid.uuid4()), 'sequence':0, 'identity':None, 'invalidated':True}
            state['sequence'] += 1
            if state['sequence'] > 1_000_000_000:
                raise ValueError('Capture order exhausted')
            if current is None or state['identity'] != current:
                state['invalidated'] = True
            result = {'epoch':state['epoch'], 'sequence':state['sequence']}
            if not state['invalidated']:
                result['account'] = state['identity']
            return result, state
        return self._locked(value, change)

def send(connection_file, value):
    path = Path(connection_file)
    metadata = path.stat()
    if metadata.st_uid != os.getuid() or metadata.st_mode & 0o077 or path.is_symlink():
        raise ValueError('Private connection file required')
    config = json.loads(path.read_text())
    packet = dict(value, token=config['token'])
    data = json.dumps(packet, ensure_ascii=False).encode()
    if len(data) > MAX_FRAME:
        raise ValueError('Packet too large')
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(0.25)
        client.connect(config['socket'])
        client.sendall(struct.pack('!I', len(data)) + data)
        with client.makefile('rb') as stream:
            header = exact(stream, 4)
            if header is None:
                raise ValueError('No acknowledgement')
            size = struct.unpack('!I', header)[0]
            if not 0 < size <= 4096:
                raise ValueError('Acknowledgement size rejected')
            body = exact(stream, size)
            response = json.loads(body or b'{}')
            if response.get('ok') is not True:
                raise ValueError('Local bridge rejected event')
    return response

def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.achu-tmp')
    with open(temporary, 'w', encoding='utf-8') as file:
        os.chmod(temporary, 0o600)
        json.dump(value, file, indent=2, ensure_ascii=False)
    os.replace(temporary, path)

def read_settings(path):
    settings = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(settings, dict):
        raise ValueError('CLI settings must be a JSON object; no files changed')
    hooks = settings.get('hooks', {})
    if not isinstance(hooks, dict) or any(name in hooks and not isinstance(hooks[name], list) for name in ('MessageDisplay', 'SessionStart')):
        raise ValueError('CLI hooks have an unsupported shape; no files changed')
    status_line = settings.get('statusLine')
    if status_line is not None and (not isinstance(status_line, dict) or status_line.get('type') != 'command' or not isinstance(status_line.get('command'), str)):
        raise ValueError('CLI status line has an unsupported shape; no files changed')
    return settings

def read_install_state(path):
    if not path.exists():
        return None
    state = json.loads(path.read_text())
    if not isinstance(state, dict) or not all(key in state for key in ('entry', 'originalStatus', 'installedStatus')):
        raise ValueError('Installation journal is invalid; no files changed')
    return state

def install_cli(directory, connection, message_display=False):
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    settings_path = directory/'settings.json'
    state_path = directory/'achu-bridge-install.json'
    state = read_install_state(state_path)
    if state and state.get('complete') and state.get('accountVersion') == 2:
        return
    if state and state.get('complete') and read_settings(settings_path).get('statusLine') != state['installedStatus']:
        raise ValueError('User changed status line; no upgrade applied')
    settings = read_settings(settings_path)
    original_status = state['originalStatus'] if state else settings.get('statusLine')
    command = shlex.join([sys.executable, str(Path(__file__).resolve()), '--hook', '--connection', str(Path(connection).resolve())])
    entry = {'hooks':[{'type':'command','command':command,'timeout':1}]}
    had_hooks = state.get('hadHooks', True) if state else 'hooks' in settings
    hooks = settings.setdefault('hooks', {})
    state_directory = directory/'achu-account-state'
    account_command = shlex.join([sys.executable, str(Path(__file__).resolve()), '--session-start', '--state-dir', str(state_directory)])
    account_entry = {'matcher':'startup|resume', 'hooks':[{'type':'command','command':account_command,'timeout':3}]}
    if account_entry not in hooks.setdefault('SessionStart', []):
        hooks['SessionStart'].append(account_entry)
    if message_display or (state and state.get('messageDisplay')):
        if entry not in hooks.setdefault('MessageDisplay', []):
            hooks['MessageDisplay'].append(entry)
    wrapper = shlex.join([sys.executable, str(Path(__file__).resolve()), '--statusline', '--connection', str(Path(connection).resolve()), '--original-status', json.dumps(original_status), '--state-dir', str(state_directory)])
    installed_status = dict(original_status or {}, type='command',command=wrapper,refreshInterval=30)
    settings['statusLine'] = installed_status
    journal = {'entry':entry,'originalStatus':original_status,'installedStatus':installed_status,'messageDisplay':message_display,'complete':False,'accountEntry':account_entry,'accountVersion':2,'hadHooks':had_hooks}
    atomic(state_path, journal)
    atomic(settings_path, settings)
    journal['complete'] = True
    atomic(state_path, journal)

def request_cli(directory):
    """Change only our owned command: the official CLI immediately re-runs it.
    This requests a report, not a new server observation or model message.
    """
    directory = Path(directory).resolve()
    state_path = directory/'achu-bridge-install.json'
    state = read_install_state(state_path)
    settings_path = directory/'settings.json'
    settings = read_settings(settings_path)
    if not state or not state.get('complete') or settings.get('statusLine') != state['installedStatus']:
        raise ValueError('Owned CLI status line required')
    command = shlex.split(state['installedStatus']['command'])
    if '--request-id' in command:
        position = command.index('--request-id'); command = command[:position]
    command += ['--request-id',str(uuid.uuid4())]
    updated = dict(state['installedStatus'], command=shlex.join(command))
    state['installedStatus'] = updated
    # Journal first, matching installation recovery ordering.
    atomic(state_path, state)
    settings['statusLine'] = updated
    atomic(settings_path, settings)

def uninstall_cli(directory):
    directory = Path(directory).resolve()
    state_path = directory/'achu-bridge-install.json'
    if not state_path.exists():
        return
    state = read_install_state(state_path)
    settings_path = directory/'settings.json'
    settings = read_settings(settings_path)
    hooks = settings.get('hooks', {})
    if 'MessageDisplay' in hooks:
        hooks['MessageDisplay'] = [entry for entry in hooks['MessageDisplay'] if entry != state['entry']]
        if not hooks['MessageDisplay']:
            hooks.pop('MessageDisplay')
    if 'SessionStart' in hooks and 'accountEntry' in state:
        hooks['SessionStart'] = [entry for entry in hooks['SessionStart'] if entry != state['accountEntry']]
        if not hooks['SessionStart']:
            hooks.pop('SessionStart')
    if settings.get('statusLine') == state['installedStatus']:

        if state['originalStatus'] is None:
            settings.pop('statusLine', None)
        else:
            settings['statusLine'] = state['originalStatus']
    if not hooks and state.get('hadHooks') is False:
        settings.pop('hooks', None)
    atomic(settings_path, settings)
    state_path.unlink()

def install_native(directory, extension_id, connection):
    if len(extension_id) != 32 or any(char not in 'abcdefghijklmnop' for char in extension_id):
        raise ValueError('Exact Chrome extension ID required')
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    origin = 'chrome-extension://' + extension_id + '/'
    launcher = directory/'achu-native-host'
    args = shlex.join([sys.executable, str(Path(__file__).resolve()), '--native', '--connection', str(Path(connection).resolve()), '--expected-origin', origin])
    launcher.write_text('#!/bin/sh\nexec ' + args + ' "$@"\n')
    launcher.chmod(0o700)
    atomic(directory/'local.achu.companion.json', {'name':'local.achu.companion','description':'A畜伴侣只读桥接','path':str(launcher),'type':'stdio','allowed_origins':[origin]})

def main():
    parser = argparse.ArgumentParser()
    for flag in ('hook','statusline','session-start','native','install-cli','uninstall-cli','install-native','request-cli'):
        parser.add_argument('--'+flag, action='store_true')
    parser.add_argument('--message-display-supported', action='store_true', help='Enable MessageDisplay only after verifying the installed CLI supports it')
    parser.add_argument('--connection', type=Path)
    parser.add_argument('--config-dir', type=Path)
    parser.add_argument('--state-dir', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--extension-id')
    parser.add_argument('--expected-origin')
    parser.add_argument('--original-status', default='null')
    parser.add_argument('--request-id')
    parser.add_argument('origin', nargs='?')
    args = parser.parse_args()
    if args.install_cli or args.uninstall_cli or args.request_cli:
        if not args.config_dir:
            parser.error('An explicit config directory is required')
        if args.install_cli:
            if not args.connection:
                parser.error('Connection file required')
            install_cli(args.config_dir, args.connection, args.message_display_supported)
        elif args.request_cli:
            request_cli(args.config_dir)
        else:
            uninstall_cli(args.config_dir)
        return
    if args.install_native:
        if not args.output_dir or not args.extension_id or not args.connection:
            parser.error('Explicit output directory, extension ID and connection required')
        install_native(args.output_dir, args.extension_id, args.connection)
        return
    if args.session_start:
        if not args.state_dir:
            parser.error('Private state directory required')
        data = sys.stdin.buffer.read(MAX_FRAME + 1)
        if len(data) <= MAX_FRAME:
            CLIAccountTracker(args.state_dir).start(json.loads(data))
        return
    if not args.connection:
        parser.error('Connection file required')
    if args.native:
        if not args.expected_origin or args.origin != args.expected_origin:
            raise ValueError('Unexpected extension origin')
        while True:
            value = read_native(sys.stdin.buffer)
            if value is None:
                break
            try:
                if value.get('kind') not in ('snapshot','usage') or not str(value.get('binding','')).startswith('web-'):
                    raise ValueError('Read-only browser event required')
                result = send(args.connection, value)
                if 'requestUsage' in result:
                    result['binding'] = value['binding']
            except (ValueError, OSError, KeyError):
                result = {'ok':False,'reason':'Local bridge unavailable or rejected; resynchronize'}
            write_native(sys.stdout.buffer, result)
        return
    data = sys.stdin.buffer.read(MAX_FRAME + 1)
    if len(data) > MAX_FRAME:
        return
    value = json.loads(data)
    if args.hook:
        try:
            send(args.connection, hook_envelope(value))
        except (ValueError, OSError, KeyError):
            pass
        # No replacement output: original CLI text and transcript stay intact.
    elif args.statusline:
        try:
            context = CLIAccountTracker(args.state_dir).report(value) if args.state_dir else None
            send(args.connection, status_envelope(value, context))
        except (ValueError, OSError, KeyError):
            pass
        original = json.loads(args.original_status)
        if isinstance(original, dict) and isinstance(original.get('command'), str):
            try:
                subprocess.run(original['command'], shell=True, input=data, timeout=1, check=False)
            except subprocess.TimeoutExpired:
                pass
        else:
            print('')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, json.JSONDecodeError):
        # Never echo source content, paths or credentials to a log.
        sys.exit(1)
