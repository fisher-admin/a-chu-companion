from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, sys, time
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path.startswith('/gemini/'):
            if self.headers.get('X-goog-api-key') != 'dummy-gemini-key' or self.headers.get('Authorization') or 'systemInstruction' not in body:
                self.send_response(400); self.end_headers(); return
            text = body['contents'][0]['parts'][0]['text']
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
