#!/usr/bin/env python3
"""Read-only auth probes, apart from one temporary in-memory Hermes login session."""
import base64
import http.cookiejar
import json
import os
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def request(opener, url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with opener.open(req, timeout=10) as response:
            return response.status, response.read(65536)
    except urllib.error.HTTPError as error:
        return error.code, b""  # Never echo response/error bodies or credentials.


def verify(app):
    opener = urllib.request.build_opener(NoRedirect())
    if app == "opencode":
        password = os.environ.get("OPENCODE_PASSWORD")
        if not password:
            raise ValueError("OPENCODE_PASSWORD is missing")
        url = "http://127.0.0.1:4096/api/info"
        status, _ = request(opener, url)
        if status not in (401, 403):
            raise ValueError("OpenCode did not reject unauthenticated API access")
        auth = base64.b64encode(("opencode:" + password).encode()).decode()
        status, _ = request(opener, url, headers={"Authorization": "Basic " + auth})
        if status != 200:
            raise ValueError("OpenCode authenticated API check failed")
    elif app == "hermes":
        base = "http://127.0.0.1:9119"
        status, body = request(opener, base + "/api/status")
        info = json.loads(body) if status == 200 else {}
        if not info.get("auth_required") or "basic" not in info.get("auth_providers", []):
            raise ValueError("Hermes basic authentication gate is not enabled")
        status, _ = request(opener, base + "/api/auth/me")
        if status not in (401, 403, 302, 303, 307):
            raise ValueError("Hermes did not reject unauthenticated session access")
        user = os.environ.get("HERMES_DASHBOARD_BASIC_AUTH_USERNAME")
        password = os.environ.get("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD")
        if not user or not password:
            raise ValueError("Hermes login variables are missing")
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPCookieProcessor(jar))
        payload = json.dumps({"provider": "basic", "username": user,
                              "password": password}).encode()
        status, body = request(opener, base + "/auth/password-login", payload,
                               {"Content-Type": "application/json"})
        if status != 200 or not json.loads(body).get("ok"):
            raise ValueError("Hermes password login failed")
        status, body = request(opener, base + "/api/auth/me")
        if status != 200 or json.loads(body).get("provider") != "basic":
            raise ValueError("Hermes authenticated session check failed")
    else:
        raise ValueError("Choose opencode or hermes")
    print(app + ": unauthenticated rejection and authenticated access passed")


if __name__ == "__main__":
    try:
        verify(sys.argv[1] if len(sys.argv) == 2 else "")
    except (ValueError, OSError, urllib.error.URLError):
        print("Authentication check failed; verify service readiness, configuration and pinned API compatibility. No values printed.", file=sys.stderr)
        raise SystemExit(1)
