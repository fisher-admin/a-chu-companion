from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, sys, time
class Handler(BaseHTTPRequestHandler):
    recovery_calls = 0
    auth_counts = {}
    def log_message(self, *args): pass
    def do_GET(self):
        # Request counts for /auth/... so tests can prove which calls reached the network.
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(json.dumps(Handler.auth_counts).encode())
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path.startswith('/auth/'):
            # /auth/<tag>/<status>: synthetic keys containing "accepted-" succeed; others get <status>.
            gemini = self.path.startswith('/auth/gemini/')
            credential = self.headers.get('X-goog-api-key' if gemini else 'Authorization', '')
            accepted = 'accepted-' in credential
            key = self.path + ('#accepted' if accepted else '#rejected')
            Handler.auth_counts[key] = Handler.auth_counts.get(key, 0) + 1
            if not accepted:
                status = next(int(part) for part in self.path.split('/') if part.isdigit())
                self.send_response(status); self.end_headers()
                self.wfile.write(b'{"error":{"message":"Synthetic authorization rejection"}}'); return
            if gemini:
                payload = {'candidates':[{'content':{'parts':[{'text':'Hello'}]},'finishReason':'STOP'}]}
            else:
                messages = body.get('messages') or []
                content = '已译:' + messages[-1]['content'] if messages else 'Hello'
                payload = {'choices':[{'message':{'content':content},'finish_reason':'stop'}]}
            self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
            self.wfile.write(json.dumps(payload).encode()); return
        if self.path.startswith('/gemini/'):
            if self.headers.get('X-goog-api-key') != 'dummy-gemini-key' or self.headers.get('Authorization') or 'systemInstruction' not in body:
                self.send_response(400); self.end_headers(); return
            text = json.loads(body['contents'][0]['parts'][0]['text'])['source_text']
            if self.path.endswith('/redirect'):
                self.send_response(307); self.send_header('Location', '/gemini/ok'); self.end_headers(); return
            if self.path.endswith('/quota'):
                self.send_response(429); self.end_headers(); self.wfile.write(b'{"error":{"status":"RESOURCE_EXHAUSTED"}}'); return
            if self.path.endswith('/slow'): time.sleep(3)
            truncated = self.path.endswith('/truncated') or (self.path.endswith('/adaptive') and len(text) > 128)
            output = text if self.path.endswith(('/echo', '/adaptive')) else 'Hello'
            payload = {'candidates':[{'content':{'parts':[{'text':'Do not show this thought','thought':True},{'text':output}]},'finishReason':'MAX_TOKENS' if truncated else 'STOP'}]}
            self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
            try: self.wfile.write(json.dumps(payload).encode())
            except BrokenPipeError: pass
            return
        if self.path.startswith('/redirect'):
            self.send_response(307); self.send_header('Location', '/ok/chat/completions'); self.end_headers(); return
        if self.path.startswith('/unauthorized'):
            self.send_response(401); self.end_headers(); self.wfile.write(b'{"error":"test"}'); return
        if self.path.startswith('/recover'):
            Handler.recovery_calls += 1
            if Handler.recovery_calls == 1:
                self.send_response(503); self.end_headers(); return
        if self.path.startswith('/quota'):
            self.send_response(429); self.send_header('Retry-After', '2'); self.end_headers(); return
        if self.path.startswith('/slow'): time.sleep(3)
        if self.path.startswith('/echo') or self.path.startswith('/adaptive'):
            text = body['messages'][1]['content']
            if self.path.startswith('/adaptive') and len(text) > 128:
                self.send_response(413); self.end_headers(); return
            payload = {'choices':[{'message':{'content':text},'finish_reason':'stop'}]}
            self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
            self.wfile.write(json.dumps(payload).encode()); return
        if body['messages'][1]['content'] != '你好':
            self.send_response(400); self.end_headers(); return
        payload = {'choices':[{'message':{'content':'Hello'},'finish_reason':'length' if self.path.startswith('/truncated') else 'stop'}]}
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        try: self.wfile.write(json.dumps(payload).encode())
        except BrokenPipeError: pass
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
with open(sys.argv[1], 'w') as f: f.write(str(server.server_address[1]))
server.serve_forever()
