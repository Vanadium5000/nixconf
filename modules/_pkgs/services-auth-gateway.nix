{
  lib,
  python3,
  makeWrapper,
}:

python3.pkgs.buildPythonApplication {
  pname = "services-auth-gateway";
  version = "0.1.0";
  format = "other";
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
        runHook preInstall

        mkdir -p "$out/libexec" "$out/bin"

        cat > "$out/libexec/services-auth-gateway.py" <<'PYTHON'
    import argparse
    import base64
    import hashlib
    import hmac
    import html
    import json
    import time
    import urllib.parse
    from http import cookies
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


    def b64url_encode(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


    def b64url_decode(data: str) -> bytes:
        padding = "=" * (-len(data) % 4)
        return base64.urlsafe_b64decode(data + padding)


    class AuthApp:
        def __init__(self, config: dict[str, object]):
            self.password = str(config["password"])
            self.signing_key = str(config["signingKey"]).encode()
            self.cookie_name = str(config["cookieName"])
            self.return_cookie_name = str(config["returnCookieName"])
            self.cookie_domain = str(config["cookieDomain"])
            self.public_domain = str(config["publicDomain"])
            self.default_redirect = str(config["defaultRedirect"])
            self.session_ttl = int(config["sessionTtlSeconds"])

        def sign_session(self, now: int | None = None) -> str:
            issued_at = int(time.time() if now is None else now)
            payload = json.dumps(
                {
                    "exp": issued_at + self.session_ttl,
                    "iat": issued_at,
                    "sub": "services",
                },
                separators=(",", ":"),
                sort_keys=True,
            ).encode()
            payload_b64 = b64url_encode(payload)
            signature = hmac.new(self.signing_key, payload_b64.encode(), hashlib.sha256).digest()
            return f"{payload_b64}.{b64url_encode(signature)}"

        def verify_session(self, token: str | None) -> bool:
            if not token or "." not in token:
                return False
            payload_b64, signature_b64 = token.split(".", 1)
            expected = hmac.new(self.signing_key, payload_b64.encode(), hashlib.sha256).digest()
            try:
                signature = b64url_decode(signature_b64)
            except Exception:
                return False
            if not hmac.compare_digest(expected, signature):
                return False
            try:
                payload = json.loads(b64url_decode(payload_b64))
            except Exception:
                return False
            return int(payload.get("exp", 0)) >= int(time.time())

        def validate_redirect(self, candidate: str | None) -> str:
            if not candidate:
                return self.default_redirect
            parsed = urllib.parse.urlparse(candidate)
            if parsed.scheme != "https":
                return self.default_redirect
            if parsed.hostname is None:
                return self.default_redirect
            host = parsed.hostname.lower()
            if host != self.public_domain and not host.endswith("." + self.public_domain):
                return self.default_redirect
            cleaned = parsed._replace(fragment="")
            return urllib.parse.urlunparse(cleaned)

        def render_login_page(self, next_url: str, error_message: str = "") -> str:
            escaped_next = html.escape(next_url, quote=True)
            escaped_error = html.escape(error_message)
            error_block = f'<p class="error">{escaped_error}</p>' if escaped_error else ""
            return f"""<!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Service Login</title>
        <style>
          :root {{ color-scheme: dark; }}
          body {{
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            background: #000;
            color: #d4d4d4;
            font: 16px/1.5 "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
          }}
          .card {{
            width: min(28rem, calc(100vw - 2rem));
            padding: 1.5rem;
            border: 1px solid rgba(84, 84, 252, 0.35);
            border-radius: 22px;
            background: rgba(8, 8, 12, 0.75);
            backdrop-filter: blur(8px);
            box-shadow: 0 24px 80px rgba(0, 0, 0, 0.55);
          }}
          h1 {{ margin: 0 0 0.5rem; font-size: 1.4rem; color: #54fcfc; }}
          p {{ margin: 0 0 1rem; color: #a8a8a8; }}
          label {{ display: block; margin-bottom: 0.5rem; }}
          input {{
            width: 100%;
            box-sizing: border-box;
            margin-bottom: 1rem;
            padding: 0.8rem 0.9rem;
            border-radius: 12px;
            border: 1px solid rgba(84, 84, 252, 0.35);
            background: rgba(20, 20, 32, 0.9);
            color: inherit;
          }}
          button {{
            width: 100%;
            padding: 0.8rem 0.9rem;
            border: 0;
            border-radius: 12px;
            background: #5454fc;
            color: white;
            font: inherit;
            cursor: pointer;
          }}
          .error {{ color: #fc5454; }}
          .small {{ margin-top: 1rem; font-size: 0.85rem; color: #7c7c7c; word-break: break-all; }}
        </style>
      </head>
      <body>
        <main class="card">
          <h1>Service Login</h1>
          <p>One shared cookie protects the internal dashboards without prompting on every subdomain.</p>
          {error_block}
          <form method="post" action="/login">
            <input type="hidden" name="next" value="{escaped_next}" />
            <label for="password">Password</label>
            <input id="password" name="password" type="password" autocomplete="current-password" required autofocus />
            <button type="submit">Sign in</button>
          </form>
          <p class="small">Redirect target: {escaped_next}</p>
        </main>
      </body>
    </html>"""


    class Handler(BaseHTTPRequestHandler):
        server_version = "services-auth-gateway/0.1.0"

        @property
        def app(self) -> AuthApp:
            return self.server.app  # type: ignore[attr-defined]

        def do_GET(self):
            self.route()

        def do_HEAD(self):
            self.route(head_only=True)

        def do_POST(self):
            self.route()

        def route(self, head_only: bool = False):
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path
            if path == "/health":
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.end_headers()
                if not head_only:
                    self.wfile.write(b"ok")
                return
            if path == "/api/check":
                if self.app.verify_session(self.get_cookie(self.app.cookie_name)):
                    self.send_response(204)
                    self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                else:
                    self.send_response(401)
                    self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                return
            if path == "/login" and self.command == "GET":
                next_url = self.resolve_next_url(parsed)
                page = self.app.render_login_page(next_url)
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                if not head_only:
                    self.wfile.write(page.encode())
                return
            if path == "/login" and self.command == "POST":
                form = self.parse_form()
                next_url = self.app.validate_redirect(form.get("next"))
                if form.get("password") != self.app.password:
                    page = self.app.render_login_page(next_url, "Incorrect password.")
                    self.send_response(401)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                    self.wfile.write(page.encode())
                    return
                self.send_response(303)
                self.set_cookie(self.app.cookie_name, self.app.sign_session(), max_age=self.app.session_ttl)
                self.set_cookie(self.app.return_cookie_name, "", max_age=0)
                self.send_header("Location", next_url)
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return
            if path == "/logout":
                self.send_response(303)
                self.set_cookie(self.app.cookie_name, "", max_age=0)
                self.set_cookie(self.app.return_cookie_name, "", max_age=0)
                self.send_header("Location", self.app.default_redirect)
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return
            self.send_response(404)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            if not head_only:
                self.wfile.write(b"not found")

        def parse_form(self) -> dict[str, str]:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length).decode("utf-8")
            parsed = urllib.parse.parse_qs(body, keep_blank_values=True)
            return {key: values[-1] for key, values in parsed.items()}

        def resolve_next_url(self, parsed: urllib.parse.ParseResult) -> str:
            query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
            candidate = query.get("next", [None])[-1]
            if not candidate:
                candidate = self.get_cookie(self.app.return_cookie_name)
            return self.app.validate_redirect(candidate)

        def get_cookie(self, name: str) -> str | None:
            raw = self.headers.get("Cookie")
            if not raw:
                return None
            jar = cookies.SimpleCookie()
            try:
                jar.load(raw)
            except cookies.CookieError:
                return None
            morsel = jar.get(name)
            return morsel.value if morsel is not None else None

        def set_cookie(self, name: str, value: str, max_age: int):
            morsel = cookies.Morsel()
            morsel.set(name, value, value)
            morsel["path"] = "/"
            morsel["domain"] = self.app.cookie_domain
            morsel["secure"] = True
            morsel["httponly"] = True
            morsel["samesite"] = "Lax"
            morsel["max-age"] = str(max_age)
            self.send_header("Set-Cookie", morsel.OutputString())

        def log_message(self, format: str, *args):
            return


    def main() -> None:
        parser = argparse.ArgumentParser()
        parser.add_argument("--config", required=True)
        args = parser.parse_args()

        with open(args.config, "r", encoding="utf-8") as handle:
            config = json.load(handle)

        app = AuthApp(config)
        server = ThreadingHTTPServer((str(config["bindAddress"]), int(config["port"])), Handler)
        server.app = app  # type: ignore[attr-defined]
        server.serve_forever()


    if __name__ == "__main__":
        main()
    PYTHON

        chmod 0555 "$out/libexec/services-auth-gateway.py"
        makeWrapper ${python3}/bin/python3 "$out/bin/services-auth-gateway" \
          --add-flags "$out/libexec/services-auth-gateway.py"

        runHook postInstall
  '';

  meta = with lib; {
    description = "Minimal shared-cookie auth gateway for nginx auth_request";
    license = licenses.mit;
    mainProgram = "services-auth-gateway";
    platforms = platforms.unix;
  };
}
