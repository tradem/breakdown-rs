# Issue #162 – Implementierungsplan und Umsetzung

## Ziel

Die Google-Drive-Reportarchivierung verwendet ausschließlich die Settings-/Vault-
Infrastruktur aus Issue #157. Google-Drive-Material wird nur als kurzlebiges,
nicht debuggbares Bundle an der API-/Vault-Grenze verarbeitet. SierraDB-Events,
PostgreSQL-Projektionen, Auditdaten, OpenAPI-Response-Schemas und Logs enthalten
nur `vault_key_id`, Version, Provider und Binding-Status.

## Umgesetzte Arbeitspakete

- [x] **Typed secret boundary** – `GDriveCredentialBundle` in `core` besitzt
      keine `Debug`-, `Serialize`- oder Response-Schema-Implementierung. Der
      API-Request wird unmittelbar in dieses Bundle überführt.
- [x] **Vault storage/fetch** – Bundle wird als ein verschlüsseltes Vault-
      Dokument durch den bestehenden Transit-DEK/AES-256-GCM-Fluss gespeichert
      und beim Fetch validiert/zeroisiert. GDrive-Rotationen erhalten einen
      neuen opaken Binding-Key, sodass der alte Key bis zum erfolgreichen
      Reference-Event erhalten bleibt.
- [x] **Settings rotation** – `CredentialRotated` sowie das referenz-only
      `RotateCredentialBinding` wurden in Aggregate, EventStore-Adapter,
      Projektor und Audit-Projektor ergänzt.
- [x] **GDrive API** – `POST /settings/gdrive` und
      `PATCH /settings/{id}/gdrive` akzeptieren write-only Bundles, behalten die
      bestehende handler-interne Rollenprüfung und kompensieren Vault-Writes bei
      fehlgeschlagenem EventStore-Schreiben.
- [x] **Report adapter** – `OpenDalReportArchiveStorage::external_from_vault`
      lädt den Bundle über den Vault-Port. Der GDrive-Zweig liest keine
      Credential-Environment-Variablen.
- [x] **Fail closed** – bei fehlender Settings-Referenz oder Vault-Ausfall wird
      ein unavailable Storage injiziert. Der Backup-Worker kann dadurch normal
      retry/dead-letter anwenden; es gibt keinen Memory- oder Plaintext-Fallback
      für GDrive. Der laufende Worker verwendet einen Vault-backed Resolver,
      der die aktuelle Settings-Referenz pro Operation prüft und Rotation bzw.
      Revocation ohne API-Neustart übernimmt.
- [x] **Composition root** – bei `REPORT_BACKUP_PROVIDER=gdrive` wird nur die
      opake `REPORT_BACKUP_SETTINGS_ID`-Referenz verwendet. S3 bleibt für den
      nicht-GDrive-Zweig unverändert.
- [x] **One-time migration** – `cargo run -p api --bin
      migrate_gdrive_credentials -- --confirm-legacy-env --settings-id <UUID>
      --actor <SUB> [--rotate]` liest die Legacy-Variablen nur in diesem
      expliziten Kommando, validiert das Vault-/OpenDAL-Binding vor dem Event,
      ist bei identischem Material idempotent und überschreibt aktive Bindings
      nur mit `--rotate`.
- [x] **Documentation and tests** – Bundle-Roundtrip, secret-free Events,
      Rotation, fail-closed storage und API-route authorization inventory sind
      abgedeckt. Nach erfolgreicher Migration müssen die vier Legacy-Variablen
      aus `.env`, Compose, CI und Deployment-Secrets entfernt werden.

## Sicherheits- und Betriebsentscheidungen

1. Ein GDrive-Bundle wird als Ganzes verwaltet; dadurch entstehen keine
   Teilreferenzen für Client-ID, Secret, Refresh-Token oder Root-Ordner.
2. Rotation schreibt zunächst einen neuen Vault-Key und prüft die Konstruktion
   des GDrive-Operators. Erst danach wird das reference-only Rotation-Event
   geschrieben; Cleanup des alten Keys erfolgt best-effort anschließend.
3. Vault-Fehler verhindern den API-Boot nicht. Nur GDrive-Archivjobs sind
   unavailable und folgen der vorhandenen Worker-Retry-Policy. Die aktuelle
   GDrive-Operator-Konfiguration wird im laufenden Worker bei einem Binding-
   Wechsel ersetzt; ein Neustart ist für Credential-Rotation nicht erforderlich.
4. Das generische `/settings/credentials`-Endpoint bleibt für zukünftige
   Provider rückwärtskompatibel. Der produktive GDrive-Reportpfad verwendet es
   nicht und liest keine Legacy-Credentials.

## Verifikation

Auszuführen bzw. im CI zu prüfen:

```text
cargo test --workspace --exclude integration-tests
cargo clippy --workspace --all-targets -- -D warnings
cargo test -p architecture_tests
cargo deny check bans
gitleaks detect

docker compose -f docker-compose.dev.yml config
docker compose -f docker-compose.prod.yml config
```

Die ungetrackte Ablage `backend/prompts/` wurde bei der Umsetzung nicht
verändert.
