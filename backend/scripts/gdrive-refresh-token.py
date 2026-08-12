#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: kimi-k3 (neuralwatt)

"""Refresh Google Drive OAuth refresh token for the breakdown-rs GDrive test.

Automates the OAuth 2.0 flow against the local machine so you never have to
touch the OAuth Playground again:

    python3 scripts/gdrive-refresh-token.py --client-id <ID> --client-secret <SECRET>

What it does:
  1. Starts a throwaway HTTP listener on http://localhost:8080/
  2. Opens the Google consent screen in your default browser
     (one manual login is unavoidable — it is Google's anti-bot gate)
  3. Catches the redirect, exchanges the code, prints the fresh refresh token
  4. With `--update-secret`: writes it into the GitHub Actions secret
     `GDRIVE_REFRESH_TOKEN` via the `gh` CLI (same value for all consumers)

Requirements: Python 3.8+, `gh` CLI (only for --update-secret), and the OAuth
client must list `http://localhost:8080/` under Authorized redirect URIs
(Console -> APIs & Services -> Credentials -> your client). Desktop-app
clients accept the loopback URI without extra configuration.

Exit codes: 0 = success, 1 = user error, 2 = flow/network error.
"""

from __future__ import annotations

import argparse
import http.server
import sys
import urllib.parse
import urllib.request
import webbrowser
from typing import NoReturn

AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
DEFAULT_PORT = 8080
DEFAULT_SCOPE = "https://www.googleapis.com/auth/drive"


def fail(message: str, code: int) -> NoReturn:
    print(f"❌ {message}", file=sys.stderr)
    sys.exit(code)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Refresh the Google Drive OAuth refresh token for CI."
    )
    parser.add_argument("--client-id", default=None, help="OAuth client ID")
    parser.add_argument(
        "--client-secret", default=None, help="OAuth client secret (not logged)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help=f"loopback port (default {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--scope",
        default=DEFAULT_SCOPE,
        help=f"OAuth scope (default {DEFAULT_SCOPE})",
    )
    parser.add_argument(
        "--update-secret",
        action="store_true",
        help="write the token into GDRIVE_REFRESH_TOKEN via `gh secret set`",
    )
    args = parser.parse_args()
    args.client_id = args.client_id or __import__("os").environ.get("GDRIVE_CLIENT_ID")
    args.client_secret = args.client_secret or __import__("os").environ.get(
        "GDRIVE_CLIENT_SECRET"
    )
    if not args.client_id or not args.client_secret:
        parser.error(
            "client_id and client_secret are required "
            "(pass --client-id/--client-secret or set GDRIVE_CLIENT_ID/_SECRET)"
        )
    return args


def build_auth_url(args: argparse.Namespace) -> str:
    params = {
        "client_id": args.client_id,
        "redirect_uri": f"http://localhost:{args.port}/",
        "response_type": "code",
        "scope": args.scope,
        "access_type": "offline",
        "prompt": "consent",
    }
    return f"{AUTH_ENDPOINT}?{urllib.parse.urlencode(params)}"


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    """Serves exactly one callback and stashes the query params on the class."""

    received = None  # type: dict | None

    def do_GET(self) -> None:  # noqa: N802 (http.server API)
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)
        code = params.get("code", [None])[0]
        error = params.get("error", [None])[0]

        if error:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(
                f"OAuth error: {error} - {params.get('error_description', [''])[0]}".encode()
            )
            CallbackHandler.received = {"error": error}
            return

        if not code:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"No code received - close this tab and try again.")
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(
            b"<html><body><h1>Token exchange successful.</h1>"
            b"<p>You can close this tab.</p></body></html>"
        )
        CallbackHandler.received = {"code": code}

    def log_message(self, *_) -> None:  # silence stderr noise
        pass


def explain_oauth_error(err: str, desc: str) -> str:
    """Human-readable hints for the most common Google OAuth errors."""
    hints = {
        "invalid_grant": (
            "the authorization code is stale (valid ~1-2 min) or was already "
            "used; or the consent did not include access_type=offline"
        ),
        "invalid_client": (
            "the client_id does not exist in the selected Google project — "
            "check Console -> APIs & Services -> Credentials (IDs end in "
            ".apps.googleusercontent.com)"
        ),
        "unauthorized_client": (
            "the refresh token was issued for a DIFFERENT client (e.g. the "
            "Playground's own client) or the client is a public type — "
            "regenerate with 'Use your own OAuth credentials'"
        ),
        "redirect_uri_mismatch": (
            "http://localhost:<port>/ is not listed under Authorized redirect "
            "URIs for this client"
        ),
        "access_denied": (
            "the account you logged in with is not in OAuth consent screen -> "
            "Test users (list resets when switching back to Testing)"
        ),
    }
    hint = hints.get(err)
    return f"error: {err} — {desc}" + (f"\n   hint: {hint}" if hint else "")


def exchange_code(client_id: str, client_secret: str, port: int, code: str) -> dict:
    body = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": f"http://localhost:{port}/",
        }
    ).encode()
    request = urllib.request.Request(
        TOKEN_ENDPOINT, data=body, headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
            return __import__("json").loads(response.read().decode())
    except urllib.error.HTTPError as exc:  # noqa: S310 (local dev tool)
        payload = exc.read().decode()
        try:
            detail = __import__("json").loads(payload)
            fail(explain_oauth_error(detail.get("error", ""), detail.get("error_description", "")), 2)
        except __import__("json").JSONDecodeError:
            fail(f"token exchange failed ({exc.code}): {payload}", 2)
    except urllib.error.URLError as exc:
        fail(f"token exchange network error: {exc}", 2)


def update_secret(token: str) -> None:
    import subprocess

    result = subprocess.run(
        ["gh", "secret", "set", "GDRIVE_REFRESH_TOKEN", "--body", token],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        fail(
            f"could not update GDRIVE_REFRESH_TOKEN: {result.stderr.strip() or result.stdout.strip()}",
            1,
        )
    print("✅ GitHub secret GDRIVE_REFRESH_TOKEN updated.")


def main() -> NoReturn:
    args = parse_args()

    # start the loopback server first so the redirect target exists
    server = http.server.HTTPServer(("127.0.0.1", args.port), CallbackHandler)
    CallbackHandler.received = None

    url = build_auth_url(args)
    print("👉 Opening the Google consent screen in your browser…")
    print(f"   (redirect target: http://localhost:{args.port}/ — keep this script running)")
    if not webbrowser.open(url):
        print(f"   If no browser opened, visit manually:\n   {url}")

    try:
        server.handle_request()
    except KeyboardInterrupt:
        fail("aborted by user", 1)
    finally:
        server.server_close()

    result = CallbackHandler.received
    if not result or "error" in result:
        fail(f"authorization failed: {result}", 1)
    assert result is not None

    print("📡 Exchanging authorization code for tokens…")
    tokens = exchange_code(args.client_id, args.client_secret, args.port, result["code"])

    refresh_token = tokens.get("refresh_token")
    if not refresh_token:
        fail(
            "no refresh_token in the response — the client is a public type "
            "or the scope is not offline-capable. "
            f"response keys: {sorted(tokens)}",
            2,
        )

    print("✅ Fresh refresh token obtained:")
    print(refresh_token)
    if args.update_secret:
        update_secret(refresh_token)
    print("🎉 Done. You can now re-run the CI.")


if __name__ == "__main__":
    main()
