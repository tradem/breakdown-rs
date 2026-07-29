# Handoff: Integration Tests Überprüfung

## Kontext

PR #134 hat die Test-Migration abgeschlossen. Dabei wurden die Integration Tests in `crates/integration-tests/` repariert:
- YAML-Syntaxfehler in `.github/workflows/integration-tests.yml` behoben
- `secrets`-Kontext aus `if:`-Bedingungen entfernt (nicht erlaubt auf Step-Ebene)
- `push` + `pull_request` Trigger hinzugefügt

**Aktueller Stand**: Die Tests laufen, aber ein Tier-4 Test (`audit_projector_is_idempotent_under_redelivery`) ist flaky wegen Docker Image Pull-Fehler (`tqwewe/sierradb:0.3.1`).

## Ziel

1. **Keine flaky Tests**: Alle Integration Tests müssen zuverlässig grün sein
2. **Überall laufen**: Tests sollen auf jedem CI-Runner mit Docker/Testcontainer-Support funktionieren (GitHub Actions `ubuntu-latest`, lokale Entwicklung, etc.)

## Aufgaben

### 1. Flaky Tests identifizieren und fixen

Prüfe die Tier-4 Tests in `crates/integration-tests/tests/`:
- Welche Tests sind von Network/Timeout-Problemen betroffen?
- Gibt es retries/backoff-Mechanismen für Docker Image Pulls?
- Sind die Testcontainer-Konfigurationen robust genug?

### 2. Testcontainer-Konfiguration prüfen

- `tqwewe/sierradb:0.3.1` Image: Gibt es eine neuere/stabilere Version?
- Timeouts für Container-Startup angemessen?
- Retry-Logik für Image Pulls vorhanden?

### 3. CI-Workflow optimieren

Prüfe `.github/workflows/integration-tests.yml`:
- Sollte `needs: [ci]` hinzugefügt werden (erst CI, dann Integration Tests)?
- Gibt es bessere Caching-Strategien für Docker Images?
- Sollte der GDrive-Test-Step entfernt/vereinfacht werden?

### 4. Dokumentation

Aktualisiere `AGENTS.md` § Integration tests mit:
- Bekannten Limitationen
- Troubleshooting-Schritte für flaky Tests
- Lokale Ausführungsanleitung

## Relevante Dateien

- `.github/workflows/integration-tests.yml` - CI Workflow
- `crates/integration-tests/` - Test Crate
- `crates/integration-tests/tests/` - Test Dateien
- `backend/AGENTS.md` § Integration tests
- `docker-compose.dev.yml` - Lokale Development Compose

## Tech Stack

- **Event Store**: SierraDB (RESP3, `tqwewe/sierradb:0.3.1`)
- **Read Model**: PostgreSQL
- **Testcontainers**: Rust `testcontainers` Crate
- **CI**: GitHub Actions `ubuntu-latest` mit Docker

## Hinweise

- Die `secrets`-Restriktion in `if:`-Bedingungen ist eine GitHub Actions Einschränkung, kein Bug
- `env:` + `if: env.VAR != ''` ist der korrekte Workaround
- PyYAML 6.0.3 hat einen Bug mit `:` in Anführungszeichen (betrifft nur lokale Validierung, nicht GitHub Actions)
