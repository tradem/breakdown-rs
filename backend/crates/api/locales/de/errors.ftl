# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: kimi-k3 (neuralwatt)

# Problem-detail messages (ADR-031 D5). One message per registered
# problem code; the key is derived 1:1 from the code
# ({code} -> problem-{code with dashes}). Standard Fluent syntax only
# (Pontoon/Weblate-importable verbatim).

problem-ai-config-already-revoked =
    Die KI-Konfiguration wurde bereits widerrufen.

problem-ai-config-empty-model =
    Das KI-Modell darf nicht leer sein.

problem-ai-config-empty-prompt =
    Der KI-Prompt darf nicht leer sein.

problem-ai-config-empty-provider =
    Es muss ein KI-Anbieter ausgewählt werden.

problem-ai-config-empty-vault-key =
    Der KI-Vault-Schlüsselverweis darf nicht leer sein.

problem-ai-config-not-found =
    KI-Konfiguration nicht gefunden.

problem-ai-config-provider-mismatch =
    Der KI-Anbieter kann nicht geändert werden.

problem-auth-idp-unavailable =
    Der Identitätsanbieter ist derzeit nicht erreichbar.

problem-auth-invalid-active-block =
    Der X-Active-Block-Header ist ungültig.

problem-auth-missing-active-block =
    Der X-Active-Block-Header fehlt.

problem-auth-unauthenticated =
    Authentifizierung erforderlich. Bitte melden Sie sich an.

problem-block-not-found =
    Block nicht gefunden.

problem-block-validation =
    Die Block-Anfrage ist nicht gültig.

problem-character-not-found =
    Charakter nicht gefunden.

problem-character-validation =
    Die Charakter-Anfrage ist nicht gültig.

problem-concurrency-version-mismatch =
    Die Daten wurden zwischenzeitlich geändert. Bitte neu laden und erneut versuchen (erwartet: { $expected_version }, aktuell: { $current_version }).

problem-costume-category-archived =
    Die Kostümkategorie ist archiviert und kann nicht mehr geändert werden.

problem-costume-category-not-found =
    Kostümkategorie nicht gefunden.

problem-costume-category-validation =
    Die Kostümkategorie-Anfrage ist nicht gültig.

problem-costume-already-assigned =
    Das Kostüm ist bereits einem Charakter zugeordnet (Charakter { $assigned_character_id }).

problem-costume-not-found =
    Kostüm nicht gefunden.

problem-costume-validation =
    Die Kostüm-Anfrage ist nicht gültig.

problem-domain-conflict =
    Der Vorgang steht im Konflikt mit dem aktuellen Zustand.

problem-domain-forbidden =
    Sie sind nicht berechtigt, diese Aktion auszuführen.

problem-domain-not-found =
    Die angeforderte Ressource wurde nicht gefunden.

problem-domain-service-unavailable =
    Der Dienst ist derzeit nicht verfügbar.

problem-domain-validation =
    Die Anfrage ist nicht gültig.

problem-episode-not-found =
    Episode nicht gefunden.

problem-episode-validation =
    Die Episode-Anfrage ist nicht gültig.

problem-http-bad-json-body =
    Der Anforderungstext ist kein gültiges JSON.

problem-http-bad-path-param =
    Ungültiger Pfadparameter.

problem-http-bad-query-param =
    Ungültiger oder fehlender Query-Parameter.

problem-http-bad-request =
    Ungültige Anfrage.

problem-http-internal-error =
    Interner Serverfehler.

problem-http-payload-too-large =
    Die Anfrage überschreitet das zulässige Größenlimit.

problem-http-request-timeout =
    Die Anfrage hat das Zeitlimit überschritten.

problem-http-route-not-found =
    Die angeforderte Route existiert nicht.

problem-http-unsupported-media-type =
    Nicht unterstützter Medientyp.

problem-membership-already-invited =
    Für diese Person besteht bereits eine Einladung.

problem-membership-bootstrap-not-allowed =
    Das Bootstrap ist nur für einen leeren Block zulässig.

problem-membership-missing-actor =
    Für diesen Vorgang ist ein angemeldeter Benutzer erforderlich.

problem-membership-no-pending-invitation =
    Es liegt keine offene Einladung vor.

problem-membership-not-active-member =
    Sie sind kein aktives Mitglied dieses Blocks.

problem-membership-not-found =
    Mitgliedschaft nicht gefunden.

problem-membership-validation =
    Die Mitgliedschafts-Anfrage ist nicht gültig.

problem-photo-already-deleted =
    Das Foto wurde bereits gelöscht.

problem-photo-not-found =
    Foto nicht gefunden.

problem-photo-validation =
    Die Foto-Anfrage ist nicht gültig.

problem-scene-shoot-already-linked =
    Das Kontinuitätsfoto ist bereits mit dieser Aufnahme verknüpft.

problem-scene-shoot-already-started =
    Die Aufnahme wurde bereits gestartet.

problem-scene-shoot-not-found =
    Aufnahme nicht gefunden.

problem-scene-shoot-note-not-found =
    Notiz nicht gefunden.

problem-scene-shoot-pair-already-exists =
    Für dieses Szenen-Drehtag-Paar existiert bereits eine Aufnahme.

problem-scene-shoot-planned-order-frozen =
    Die geplante Reihenfolge ist eingefroren, nachdem Ausführungsdaten erfasst wurden.

problem-scene-shoot-terminal-state =
    Die Aufnahme befindet sich in einem Endzustand.

problem-scene-shoot-validation =
    Die Aufnahme-Anfrage ist nicht gültig.

problem-scene-already-scheduled =
    Die Szene ist bereits auf einem anderen Drehtag eingeplant (Drehtag { $offending_shooting_day_id }).

problem-scene-character-already-assigned =
    Der Charakter ist dieser Szene bereits zugeordnet.

problem-scene-character-not-found =
    Charakter nicht gefunden.

problem-scene-not-found =
    Szene nicht gefunden.

problem-scene-not-scheduled =
    Die Szene ist an diesem Drehtag nicht eingeplant.

problem-scene-validation =
    Die Szenen-Anfrage ist nicht gültig.

problem-season-not-found =
    Staffel nicht gefunden.

problem-season-validation =
    Die Staffel-Anfrage ist nicht gültig.

problem-settings-already-revoked =
    Die Anmeldedaten wurden bereits widerrufen.

problem-settings-empty-provider =
    Der Anbieter darf nicht leer sein.

problem-settings-empty-vault-key =
    Der Vault-Schlüsselverweis darf nicht leer sein.

problem-settings-not-found =
    Anmeldedaten nicht gefunden.

problem-settings-provider-mismatch =
    Der Anbieter kann während der Rotation nicht gewechselt werden.

problem-shooting-day-archived =
    Der Drehtag ist archiviert und kann nicht mehr geändert werden.

problem-shooting-day-duplicate-order-key =
    Dieser Sortierschlüssel existiert bereits für die Episode.

problem-shooting-day-not-found =
    Drehtag nicht gefunden.

problem-shooting-day-validation =
    Die Drehtag-Anfrage ist nicht gültig.
