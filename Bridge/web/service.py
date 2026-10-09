#!/usr/bin/env python3
"""Companion-owned, quota-only loopback transport. Never accesses cookies."""
import argparse
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import re
import secrets
import sys
import threading
import time
from urllib.parse import urlsplit

MAX_BODY = 16384
BASE_FIELDS = {'installID', 'tabID', 'documentID', 'url', 'focused', 'visible', 'epoch', 'sequence'}


def identifier(value, length=32):
    return isinstance(value, str) and re.fullmatch('[a-f0-9]{' + str(length) + '}', value) is not None


def page_url(value):
    if not isinstance(value, str) or len(value) > 2048:
        return False
    url = urlsplit(value)
    return url.scheme == 'https' and url.netloc == 'claude.ai' and not url.query and not url.fragment


def json_bytes(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()


class WebSession:
    def __init__(self, directory, resources, emit, clock=time.monotonic):
        self.directory = directory
        self.resources = resources
        self.emit = emit
        self.clock = clock
        self.lock = threading.RLock()
        self.epoch = secrets.token_hex(16)
        self.port = 0
        self.installations = {}
        self.bound = None
        self.dormant = None
        self.challenge = ''
        self.capability = ''
        self.capability_deadline = 0
        self.capability_browser = ''
        self.pending = None
        self.candidates = {}
        self.sequences = {}
        self.retired_documents = set()
        self.read_pending = False
        self.last_seen = 0
        self.request_times = []
        self.quota_epoch = secrets.token_hex(16)
        self.quota_sequence = 0
        self.account_fingerprint = None
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        if directory.is_symlink():
            raise ValueError('private-directory-required')
        os.chmod(directory, 0o700)
        self.state_file = directory / 'authorization.json'
        if self.state_file.is_symlink():
            raise ValueError('private-file-required')
        if self.state_file.exists():
            if self.state_file.stat().st_size > 8192:
                raise ValueError('invalid-authorization')
            value = json.loads(self.state_file.read_text())
            if value.get('version') != 1 or len(value.get('installations', {})) > 8:
                raise ValueError('invalid-authorization')
            for key, entry in value.get('installations', {}).items():
                if not identifier(key) or set(entry) != {'key', 'browser'} or not identifier(entry['key'], 64) or not isinstance(entry['browser'], str):
                    raise ValueError('invalid-authorization')
            self.installations = value.get('installations', {})
            self.port = value.get('port', 0)

    def save(self):
        temporary = self.directory / ('.state-' + secrets.token_hex(8))
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(json_bytes({'version': 1, 'port': self.port, 'installations': self.installations}))
        os.replace(temporary, self.state_file)

    def setup(self, browser):
        with self.lock:
            self.capability = secrets.token_hex(32)
            self.capability_deadline = self.clock() + 300
            self.capability_browser = browser
            self.emit({'kind': 'install', 'url': f'http://127.0.0.1:{self.port}/install/{self.capability}/usage.user.js'})

    def bind(self, url, browser, request_id=''):
        with self.lock:
            self.unbind()
            if not page_url(url):
                self.emit({'kind': 'unavailable', 'reason': 'invalid-page'})
                return
            self.challenge = secrets.token_hex(32)
            self.epoch = secrets.token_hex(16)
            self.sequences = {}
            self.retired_documents = set()
            self.pending = {'url': url, 'browser': browser, 'deadline': self.clock() + 1.2, 'settle': None, 'requestID': request_id}
            self.candidates = {}

    def unbind(self):
        with self.lock:
            self.pending = None
            self.candidates = {}
            self.challenge = ''
            self.bound = None
            self.dormant = None
            self.read_pending = False
            self.account_fingerprint = None
            self.quota_epoch = secrets.token_hex(16)

    def revoke(self):
        with self.lock:
            self.unbind()
            self.installations = {}
            self.capability = ''
            self.save()
            self.emit({'kind': 'disconnected', 'reason': 'revoked'})

    def tick(self):
        with self.lock:
            now = self.clock()
            if self.pending and (now >= self.pending['deadline'] or (self.pending['settle'] is not None and now >= self.pending['settle'])):
                pending = self.pending
                candidates = list(self.candidates.values())
                self.pending = None
                self.challenge = ''
                self.candidates = {}
                if len(candidates) != 1:
                    self.emit({'kind': 'disconnected', 'reason': 'ambiguous' if candidates else 'no-focused-page', 'requestID': pending['requestID']})
                else:
                    candidate = candidates[0]
                    if candidate['installID'] not in self.installations:
                        if len(self.installations) >= 8:
                            self.emit({'kind': 'disconnected', 'reason': 'authorization-limit'})
                            return
                        self.installations[candidate['installID']] = {'key': candidate['key'], 'browser': pending['browser']}
                        self.capability = ''
                        self.save()
                    self.bound = {key: candidate[key] for key in ['installID', 'tabID', 'documentID', 'url']}
                    binding = hashlib.sha256((candidate['installID'] + ':' + candidate['tabID']).encode()).hexdigest()
                    self.bound['binding'] = 'web-' + binding
                    self.bound['requestID'] = pending['requestID']
                    self.last_seen = now
                    self.read_pending = True
                    self.emit({'kind': 'bound', 'binding': self.bound['binding'], 'url': self.bound['url'], 'requestID': pending['requestID']})
            if self.bound and now - self.last_seen > 15:
                dormant = dict(self.bound)
                self.unbind()
                self.dormant = dormant
                self.epoch = secrets.token_hex(16)
                self.sequences = {}
                self.retired_documents = set()
                self.emit({'kind': 'disconnected', 'reason': 'heartbeat-timeout'})

    def script(self, capability=''):
        template = (self.resources / 'web/usage.user.js').read_text()
        library = (self.resources / 'chrome/usage.js').read_text()
        return template.replace('__PORT__', str(self.port)).replace('__CAPABILITY__', capability).replace('/*__USAGE_READER__*/', library).encode()

    def handle(self, method, path, headers, raw):
        with self.lock:
            if headers.get('Host') != f'127.0.0.1:{self.port}':
                return 403, {'error': 'host'}
            now = self.clock()
            self.request_times = [stamp for stamp in self.request_times if now - stamp < 1]
            if len(self.request_times) >= 100:
                return 429, {'error': 'rate'}
            self.request_times.append(now)
            origin = headers.get('Origin')
            if origin and not re.fullmatch(r'(?:chrome|moz)-extension://[A-Za-z0-9_-]+', origin):
                return 403, {'error': 'origin'}
            if method == 'GET':
                if path == '/module/usage.user.js':
                    return 200, self.script()
                if self.capability and path == '/install/' + self.capability + '/usage.user.js' and self.clock() < self.capability_deadline:
                    return 200, self.script(self.capability)
                return 404, {'error': 'not-found'}
            if method != 'POST' or path not in ['/hello', '/pair', '/poll', '/report']:
                return 405, {'error': 'method'}
            if headers.get('Content-Type', '').split(';')[0].strip() != 'application/json':
                return 415, {'error': 'content-type'}
            if len(raw) > MAX_BODY:
                return 413, {'error': 'size'}
            try:
                def unique(items):
                    value = {}
                    for key, item in items:
                        if key in value:
                            raise ValueError('duplicate-field')
                        value[key] = item
                    return value
                body = json.loads(raw, object_pairs_hook=unique, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                extra = {'key', 'challenge'} if path == '/pair' else {'challenge'} if path == '/poll' else {'status', 'account', 'usage'} if path == '/report' else set()
                if not isinstance(body, dict) or not set(body).issubset(BASE_FIELDS | extra):
                    return 400, {'error': 'fields'}
                if any(not identifier(body.get(key)) for key in ['installID', 'tabID', 'documentID']) or not page_url(body.get('url')):
                    return 400, {'error': 'identity'}
                if type(body.get('focused')) is not bool or type(body.get('visible')) is not bool:
                    return 400, {'error': 'focus'}
                entry = self.installations.get(body['installID'])
                capability = headers.get('X-AChu-Capability', '')
                bootstrap = bool(self.capability and hmac.compare_digest(capability, self.capability) and self.clock() < self.capability_deadline)
                if not entry:
                    if not bootstrap or path not in ['/hello', '/pair']:
                        return 403, {'error': 'authorization'}
                else:
                    signature = headers.get('X-AChu-Signature', '')
                    expected = hmac.new(bytes.fromhex(entry['key']), path.encode() + b'\n' + raw, hashlib.sha256).hexdigest()
                    if not hmac.compare_digest(signature, expected):
                        return 403, {'error': 'signature'}
                if path == '/hello':
                    return 200, {'epoch': self.epoch, 'challenge': self.focus_challenge(body)}
                if body.get('epoch') != self.epoch or type(body.get('sequence')) is not int or not 0 <= body['sequence'] <= 1000000000:
                    return 409, {'error': 'epoch'}
                stream = (body['installID'], body['tabID'], body['documentID'])
                if stream in self.retired_documents or body['sequence'] <= self.sequences.get(stream, -1):
                    return 409, {'error': 'sequence'}
                if len(self.sequences) >= 256 and stream not in self.sequences:
                    return 409, {'error': 'stream-limit'}
                if path == '/pair':
                    if not bootstrap or entry or not identifier(body.get('key'), 64) or not self.focus_challenge(body) or body.get('challenge') != self.challenge:
                        return 403, {'error': 'pairing'}
                    self.sequences[stream] = body['sequence']
                    self.candidate(body)
                    return 202, {'epoch': self.epoch}
                self.sequences[stream] = body['sequence']
                if path == '/poll':
                    challenge = self.focus_challenge(body)
                    if challenge and body.get('challenge') == challenge and entry['browser'] == self.pending['browser']:
                        self.candidate({**body, 'key': entry['key']})
                    if not self.bound and not self.pending and self.dormant and all(self.dormant[key] == body[key] for key in ['installID', 'tabID']):
                        self.bound = self.dormant
                        self.dormant = None
                        self.read_pending = True
                        self.emit({'kind': 'bound', 'binding': self.bound['binding'], 'url': body['url'], 'requestID': self.bound['requestID']})
                    bound = self.matches(body)
                    if bound:
                        if self.bound['documentID'] != body['documentID']:
                            previous = (body['installID'], body['tabID'], self.bound['documentID'])
                            self.retired_documents.add(previous)
                            self.bound['documentID'] = body['documentID']
                        self.bound['url'] = body['url']
                        self.last_seen = self.clock()
                    read = bound and self.read_pending
                    if read:
                        self.read_pending = False
                    return 200, {'epoch': self.epoch, 'challenge': challenge, 'bound': bound, 'read': read}
                if not self.matches(body) or self.bound['documentID'] != body['documentID']:
                    return 403, {'error': 'binding'}
                if body.get('status') not in ['ok', 'unavailable', 'account-changed', 'unauthorized']:
                    return 400, {'error': 'status'}
                if body['status'] == 'ok':
                    account, usage = self.quota(body)
                    if self.account_fingerprint != account['fingerprint']:
                        self.quota_epoch = secrets.token_hex(16)
                        self.account_fingerprint = account['fingerprint']
                    self.quota_sequence += 1
                    self.emit({'kind': 'usage', 'binding': self.bound['binding'], 'url': body['url'], 'epoch': self.quota_epoch,
                               'sequence': self.quota_sequence, 'account': account, 'usage': usage})
                else:
                    if 'account' in body or 'usage' in body:
                        return 400, {'error': 'invalid-report'}
                    self.quota_sequence += 1
                    self.emit({'kind': 'invalid', 'binding': self.bound['binding'], 'epoch': self.quota_epoch, 'sequence': self.quota_sequence, 'reason': body['status']})
                self.last_seen = self.clock()
                return 200, {'ok': True}
            except (ValueError, TypeError, KeyError, UnicodeError):
                return 400, {'error': 'invalid'}

    def focus_challenge(self, body):
        if self.pending and self.clock() < self.pending['deadline'] and body['focused'] and body['visible'] and body['url'] == self.pending['url']:
            return self.challenge
        return ''

    def candidate(self, body):
        if len(self.candidates) >= 8:
            self.pending['settle'] = self.clock()
            return
        self.candidates[(body['installID'], body['tabID'], body['documentID'])] = body
        if self.pending['settle'] is None:
            self.pending['settle'] = min(self.clock() + .2, self.pending['deadline'])

    def matches(self, body):
        return bool(self.bound and all(self.bound[key] == body[key] for key in ['installID', 'tabID']))

    @staticmethod
    def quota(body):
        account = body['account']
        if not isinstance(account, dict) or set(account) != {'fingerprint', 'displayName'} or not identifier(account['fingerprint'], 64):
            raise ValueError('account')
        label = account['displayName']
        if not isinstance(label, str) or len(label) > 80 or not re.fullmatch(r'[^\s@]\*{3}@[^\s@]+', label):
            raise ValueError('masked-account')
        usage = body['usage']
        if not isinstance(usage, dict) or set(usage) != {'rate_limits'}:
            raise ValueError('quota')
        limits = usage['rate_limits']
        if not isinstance(limits, dict) or not limits or not set(limits).issubset({'five_hour', 'seven_day'}):
            raise ValueError('windows')
        for window in limits.values():
            if not isinstance(window, dict) or not set(window).issubset({'used_percentage', 'resets_at'}):
                raise ValueError('window')
            percent = window['used_percentage']
            if type(percent) not in [int, float] or not math.isfinite(percent) or not 0 <= percent <= 100:
                raise ValueError('percent')
            reset = window.get('resets_at')
            if reset is not None and (type(reset) not in [int, float] or not math.isfinite(reset) or not 0 <= reset <= 4102444800):
                raise ValueError('reset')
        return account, usage


def create_server(session, port=None):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.0'

        def setup(self):
            super().setup()
            self.connection.settimeout(2)

        def log_message(self, *_):
            pass

        def process(self):
            try:
                if any(len(self.headers.get_all(name, [])) > 1 for name in ['Host', 'Origin', 'Content-Length', 'X-AChu-Signature', 'X-AChu-Capability']):
                    self.send_error(400)
                    return
                length = int(self.headers.get('Content-Length', '0'))
                if length < 0 or length > MAX_BODY or self.headers.get('Transfer-Encoding'):
                    status, result = 413, {'error': 'size'}
                else:
                    raw = self.rfile.read(length)
                    if len(raw) != length:
                        return
                    status, result = session.handle(self.command, self.path, self.headers, raw)
                payload = result if isinstance(result, bytes) else json_bytes(result)
                self.send_response(status)
                self.send_header('Content-Type', 'application/javascript; charset=utf-8' if isinstance(result, bytes) else 'application/json')
                self.send_header('Content-Length', str(len(payload)))
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                self.wfile.write(payload)
            except (OSError, ValueError):
                pass

        do_GET = process
        do_POST = process
        do_OPTIONS = process

    class LimitedServer(ThreadingHTTPServer):
        slots = threading.BoundedSemaphore(16)

        def process_request(self, request, client_address):
            if not self.slots.acquire(blocking=False):
                self.shutdown_request(request)
                return
            try:
                super().process_request(request, client_address)
            except Exception:
                self.slots.release()
                raise

        def process_request_thread(self, request, client_address):
            try:
                super().process_request_thread(request, client_address)
            finally:
                self.slots.release()

    server = LimitedServer(('127.0.0.1', session.port if port is None else port), Handler)
    server.daemon_threads = True
    session.port = server.server_port
    session.save()
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-dir', required=True)
    parser.add_argument('--resources', required=True)
    args = parser.parse_args()
    output_lock = threading.Lock()

    def emit(value):
        with output_lock:
            sys.stdout.buffer.write(json_bytes(value) + b'\n')
            sys.stdout.buffer.flush()

    session = WebSession(Path(args.state_dir), Path(args.resources), emit)
    server = create_server(session)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    running = threading.Event()
    running.set()

    def commands():
        try:
            for line in sys.stdin.buffer:
                if len(line) > 4096:
                    break
                command = json.loads(line)
                with session.lock:
                    kind = command.get('kind')
                    if kind == 'setup':
                        session.setup(command.get('browser', ''))
                    elif kind == 'bind':
                        session.bind(command.get('url', ''), command.get('browser', ''), command.get('requestID', ''))
                    elif kind == 'read':
                        session.read_pending = True
                    elif kind == 'unbind':
                        session.unbind()
                    elif kind == 'revoke':
                        session.revoke()
        except (ValueError, OSError):
            pass
        finally:
            running.clear()

    threading.Thread(target=commands, daemon=True).start()
    emit({'kind': 'ready', 'authorized': bool(session.installations)})
    try:
        while running.wait(.025) and running.is_set():
            session.tick()
            time.sleep(.025)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
