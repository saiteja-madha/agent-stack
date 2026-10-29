#!/usr/bin/env python3
"""Launch an app with bwenv; install this file in ADMIN_USER's ~/.local/bin."""
import os
from pathlib import Path
import sys

REQUIRED = {
    "opencode": ("OPENCODE_PASSWORD",),
    "hermes": ("HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
               "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD",
               "HERMES_DASHBOARD_BASIC_AUTH_SECRET", "HERMES_DASHBOARD_PUBLIC_URL"),
    "hindsight": ("HINDSIGHT_DB_PASSWORD",),
    "cloudflared": ("TUNNEL_TOKEN",),
}


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def main():
    args = sys.argv[1:]
    injected = bool(args and args[0] == "--injected")
    if injected:
        args.pop(0)
    if len(args) < 2 or args[0] not in REQUIRED:
        fail("Usage: vps-bwenv-exec.py APP COMMAND [ARG ...]")
    app, command = args[0], args[1:]
    if injected:
        # Validate after fetching, before starting any service or Compose operation.
        missing = [key for key in REQUIRED[app] if not os.environ.get(key)]
        if missing:
            fail("Missing required variables: " + ", ".join(missing))
        if any(key.upper() == "BWS_ACCESS_TOKEN" for key in os.environ):
            fail("Refusing to pass the Bitwarden access token to the application")
        if app == "hermes":
            from urllib.parse import urlsplit
            url = urlsplit(os.environ["HERMES_DASHBOARD_PUBLIC_URL"])
            if url.scheme != "https" or not url.hostname or url.username or url.password:
                fail("Hermes requires a valid Tailscale HTTPS public URL")
            if len(os.environ["HERMES_DASHBOARD_BASIC_AUTH_SECRET"]) < 32:
                fail("Hermes session-signing secret must contain at least 32 characters")
        if app == "hindsight":
            import re
            if not re.fullmatch(r"[A-Za-z0-9_-]+", os.environ["HINDSIGHT_DB_PASSWORD"]):
                fail("Hindsight database password must be URI-safe; use generated hex")
        # No need to expose the bootstrap credential's location to the application.
        os.environ.pop("CREDENTIALS_DIRECTORY", None)
        if command == ["--check-only"]:
            print(app + ": required configuration available (values hidden)")
            return
        os.execvpe(command[0], command, os.environ)

    if not os.environ.get("BWS_PROJECT_ID"):
        fail("BWS_PROJECT_ID must select the local Bitwarden project's UUID")
    if not os.environ.get("BWS_ACCESS_TOKEN"):
        directory = os.environ.get("CREDENTIALS_DIRECTORY")
        if not directory:
            fail("Provide BWS_ACCESS_TOKEN securely or a systemd bws-token credential")
        try:
            token = (Path(directory) / "bws-token").read_text().strip()
        except OSError:
            fail("Cannot read the systemd bws-token credential")
        if not token:
            fail("The systemd bws-token credential is empty")
        os.environ["BWS_ACCESS_TOKEN"] = token
    # Multiple arguments are quoted by bwenv; no secret is put in command arguments.
    launch = ["bwenv", "run", app, "--", sys.executable,
              str(Path(__file__).resolve()), "--injected", app, *command]
    os.execvpe(launch[0], launch, os.environ)


if __name__ == "__main__":
    try:
        main()
    except OSError:
        fail("Cannot launch the requested executable; check installation and PATH")
