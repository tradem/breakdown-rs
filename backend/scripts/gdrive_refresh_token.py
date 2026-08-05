#!/usr/bin/env python3
"""GDrive OAuth: tauscht einen Autorisierungs-Code gegen einen Refresh-Token.

Liest GDRIVE_CLIENT_ID / GDRIVE_CLIENT_SECRET aus der Env-Datei, fragt den
Autorisierungs-Code (und den OAuth-Client-Typ) interaktiv ab, tauscht den Code
gegen Token und verifiziert den neuen Refresh-Token per Refresh-Call.

Das Skript speichert NICHTS ausser:
  - Werten, die es aus der Env-Datei liest (client_id/secret/root),
  - Werten, die du eingibst (Auth-Code, Client-Typ, optionales Write-Back),
  - dem vom Google-Token-Endpoint zurückgegebenen Refresh-Token (der wird nur
    auf stdout ausgegeben bzw. optional in die Env-Datei zurückgeschrieben,
    wenn du das ausdruecklich bestaetigst).

Keine Secrets im Code, keine Temp-Dateien, keine Logs.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"

REDIRECT_DESKTOP = "urn:ietf:wg:oauth:2.0:oob"
REDIRECT_WEB = "http://localhost"


def parse_env_file(path: pathlib.Path) -> dict[str, str]:
    """Liest KEY=VALUE-Zeilen (unquoted, Kommentare/leere Zeilen ignoriert)."""
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        # Einfache Anfuehrungszeichen entfernen, falls die Datei sie nutzt
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key] = value
    return values


def post_form(url: str, fields: dict[str, str]) -> tuple[int | None, str]:
    """Form-encoded POST; liefert (HTTP-Status, Antwort-Body)."""
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:  # HTTP 4xx/5xx -> Body ist Fehler-JSON
        return exc.code, exc.read().decode()
    except urllib.error.URLError as exc:
        return None, str(exc)


def show_error(status: int | None, body: str) -> None:
    print(f"\nFEHLER (HTTP {status}): {body}")
    try:
        detail = json.loads(body)
        err = detail.get("error", "?")
        desc = detail.get("error_description", "")
        print(f"error: {err} — {desc}")
        if err == "invalid_grant":
            print("Tipp: Auth-Code abgelaufen/einmalig verwendet (Code ist nur")
            print("      ~1-2 Minuten gueltig) oder Consent ohne access_type=offline.")
        elif err == "redirect_uri_mismatch":
            print("Tipp: Falscher Client-Typ gewaehlt — starte neu und waehle die")
            print("      andere Option (Desktop-App vs. Web-Client).")
        elif err == "unauthorized_client":
            print("Tipp: Client-Paar oder Token passt nicht zusammen — pruefe, dass")
            print("      die Env-Datei die richtigen client_id/client_secret hat.")
    except json.JSONDecodeError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Tauscht einen GDrive-OAuth-Code gegen einen Refresh-Token "
                    "und verifiziert ihn. Alle Werte kommen aus der Env-Datei "
                    "oder aus deiner Eingabe — nichts wird hartkodiert.",
    )
    parser.add_argument(
        "--env",
        default=".env.gdrive-bootstrap.local",
        help="Pfad zur Env-Datei (Default: .env.gdrive-bootstrap.local)",
    )
    args = parser.parse_args()

    env_path = pathlib.Path(args.env)
    if not env_path.is_file():
        print(f"FEHLER: Env-Datei nicht gefunden: {env_path}")
        return 1

    env = parse_env_file(env_path)
    client_id = env.get("GDRIVE_CLIENT_ID", "").strip()
    client_secret = env.get("GDRIVE_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        print("FEHLER: GDRIVE_CLIENT_ID und/oder GDRIVE_CLIENT_SECRET fehlen "
              "in der Env-Datei.")
        return 1

    print("Lese GDRIVE_CLIENT_ID/GDRIVE_CLIENT_SECRET aus:", env_path)

    print("\nWelcher OAuth-Client-Typ steckt hinter deiner Client-ID?")
    print("  1) Desktop-App  -> redirect_uri = urn:ietf:wg:oauth:2.0:oob")
    print("  2) Web-Client   -> redirect_uri = http://localhost")
    choice = input("Auswahl (1/2) [1]: ").strip() or "1"
    if choice == "2":
        redirect_uri = REDIRECT_WEB
    else:
        redirect_uri = REDIRECT_DESKTOP

    code = input("Autorisierungs-Code (aus dem Consent-Flow): ").strip()
    if not code:
        print("FEHLER: kein Autorisierungs-Code eingegeben.")
        return 1

    print("\nTausche Code gegen Token ...")
    status, body = post_form(TOKEN_ENDPOINT, {
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    })
    if status != 200:
        show_error(status, body)
        return 1

    tokens = json.loads(body)
    if "refresh_token" not in tokens:
        print("FEHLER: Antwort enthaelt keinen refresh_token.")
        print("Haeufige Ursache: Consent lief ohne access_type=offline oder ein")
        print("refresh_token wurde fuer diesen Client bereits ausgegeben")
        print("(Google liefert ihn nur beim allerersten Consent).")
        print("Antwort (ohne access_token):",
              {k: v for k, v in tokens.items() if k != "access_token"})
        return 1

    refresh_token = tokens["refresh_token"]

    print("\nVerifiziere neuen Refresh-Token gegen den Token-Endpoint ...")
    status, body = post_form(TOKEN_ENDPOINT, {
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    })
    if status != 200:
        print("Verifizierung fehlgeschlagen:")
        show_error(status, body)
        return 1
    verified = json.loads(body)
    print(f"OK - Token verifiziert (HTTP 200), scope: {verified.get('scope', '?')}")

    print("\n=== Neuer Refresh-Token (fuer GitHub-Secret GDRIVE_REFRESH_TOKEN) ===")
    print(refresh_token)
    print("=========================================================================")

    write_back = input(
        f"\nNeuen Token in {env_path} zurueckschreiben (ersetzt "
        "GDRIVE_REFRESH_TOKEN)? (j/N): "
    ).strip().lower()
    if write_back in ("j", "ja", "y", "yes"):
        content = env_path.read_text()
        # Backslashes in der Ersatz-Zeichenkette fuer re.escape absichern
        escaped = refresh_token.replace("\\", "\\\\")
        new_content, n = re.subn(
            r"^(GDRIVE_REFRESH_TOKEN=).*$",
            r"\g<1>" + escaped,
            content,
            count=1,
            flags=re.MULTILINE,
        )
        if n == 0:
            print(f"WARNUNG: Keine GDRIVE_REFRESH_TOKEN-Zeile in {env_path} gefunden "
                  "- Datei unveraendert. Trage den Token manuell ein.")
            return 1
        env_path.write_text(new_content)
        print(f"Aktualisiert: {env_path}")
    else:
        print("Nicht zurueckgeschrieben. Token oben kopieren.")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nAbgebrochen.")
        sys.exit(130)
