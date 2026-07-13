# Stakeholder-Briefing: Anbindung angemeldeter Benutzer

**Change-Proposal:** `openspec/changes/add-oidc-auth-and-membership/`
**Bezugs-ADR:** ADR-010 (Authentication with OpenID Connect)
**Stand:** 2026-07-13 — Skizze, vor Implementierung

---

## Worum es geht, in einem Satz

Damit mehrere Personen (Kostümbildner\*innen, Garderobier\*innen) sicher am selben
Produktions-Projekt arbeiten können, brauchen wir eine Anbindung angemeldeter
Benutzer\*innen an das Backend — und ein domänen-seitiges Modell dafür, wer an
welchem Projekt mit welcher Rolle mitwirkt.

## Architektur in einem Bild

```
   ┌────────────────────────────┐
   │  IdP (Logto Cloud, später  │
   │  Zitadel) — verwaltet      │
   │  Konten, Passwörter, MFA   │
   └─────────────┬──────────────┘
                 │ signiertes OIDC-Token
                 ▼
   ┌──────────────────────────────────────┐
   │  Backend (Axum) — prüft nur Signatur  │
   │  und leitetCurrentUser weiter.        │
   │  Keine Passwörter im Backend.         │
   └─────────────┬────────────────────────┘
                 │
                 ▼
   ┌──────────────────────────────────────┐
   │  Membership (neuer Bounded Context): │
   │  Wer ist in welchem Projekt, mit     │
   │  welcher Rolle?                     │
   └──────────────────────────────────────┘
```

**Wichtig:** *Konten* (Registrierung, Passwörter, Login) verwaltet der IdP.
*Rollen* (wer ist Kostümbildner\*in in Projekt X) verwaltet unsere Domäne —
weil sie produktionsbezogen sind: Anna kann im Frühlingsprojekt Kostümbildnerin
und im Sommerprojekt Garderobierin sein.

## Was wir von Ihnen brauchen

Vier Fragen müssen beantwortet werden, bevor die Implementierung beginnt.
Ohne diese Antworten können wir das Modell nicht verlässlich festlegen.

---

### Frage 1 — Welche Rollen für v1?

Wir gehen von zwei produktionsbezogenen Rollen aus:

- **Kostümbildner\*in**
- **Garderobier\*in**

**Offen:** Soll v1 weitere Rollen umfassen, z.B. `Regie`, `Maske`,
`Produktionsleitung`?

**Warum wir fragen:** Rollen werden als feste Aufzählung (`enum`) modelliert.
Hinzufügen ist später unkompliziert; Entfernen oder Umbenennen ist ein
Breaking Change. Wir möchten die v1-Rollen daher bewusst klein halten und
nur das committen, was tatsächlich gewollt ist.

---

### Frage 2 — Was ist ein „Theater"?

Im Theateralltag gibt es zwei Ebenen:

```
   Theater (Stadttheater X)
     ├── Produktion „Frühling 26"  ← Projekt
     │      ├─ Kostümbildner\*in: Anna
     │      └─ Garderobier\*in: Ben
     └── Produktion „Sommer 26"   ← Projekt
            ├─ Kostümbildner\*in: Carla
            └─ Garderobier\*in: Anna (ja, Dieselbe!)
```

**Offen:** Ist ein „Theater" eine Organisation im IdP, die mehrere Projekte
zusammenfasst? Und: soll das Backend in v1演出-enübergreifende Isolation
erzwingen („Ben aus Theater A darf Projekt in Theater B nicht sehen")?

**Warum wir fragen:** Das entscheidet, ob dasMembership-Modell in v1 eine
`organization_id` benötigt und ob pro-Theater-Isolation Teil dieses Changes
ist oder in den Folge-Change zum `Project`-Aggregate gehört.

---

### Frage 3 — Audit: reicht „wer hat gewann wann was gemacht" als Metadaten?

Jede Änderung an einem Aggregat (Szene erstellen, Notiz aktualisieren, …)
soll nachvollziehbar sein — wer hat das gemacht, und wann.

**Offen:** Reicht es, die handelnde Person als unsichtbare Metadaten im
Ereignis-Strom zu speichern (technisch, für Logs/Traces)? Oder brauchen Sie
eine eigene, abfragbare Audit-Ansicht (z.B. „Zeige mir alle Änderungen an
Projekt X im letzten Monat, wer hat was gemacht")?

**Warum wir fragen:** Eine abfragbare Audit-Projektion ist deutlich teurer
(zusätzliche Tabelle, zusätzlicher Projector, mehr Tests) als reine
Metadaten im Ereignis-Strom. Wir möchten den Aufwand am Bedarf orientieren.

---

### Frage 4 — IdP-Entscheidung jetzt treffen: Logto Cloud oder doch früher Zitadel?

ADR-010 empfiehlt: **zuerst Logto Cloud (managed, gratis Tier), später
Migration auf Zitadel** (selbst gehostet, Go). Backend bleibt IdP-agnostisch.

**Offen:** Bestätigen Sie, dass wir zur Implementierung mit Logto Cloud
starten? Oder soll die Stellungnahme jetzt direkt auf selbst gehostetes
Zitadel schwenken?

**Warum wir fragen:** Logto Cloud erfordert keine Container-Vorarbeit und
keine IdP-Operations. Selbst gehostetes Zitadel ist sicherheitstechnisch
besser kontrollierbar, bedeutet aber Operats-Aufwand ab Tag 1. Wir möchten
die CI-/Dev-Laufzeit an Ihrer Empfängerung ausrichten.

---

## Was parallel bereits vorbereitet wird (technisch)

Unabhängig von den obigen Antworten können wir bereits die lokale
IdP-Container-Vorarbeit starten — siehe Begleitdiskussion in der
Change (`design.md`, Open Questions 3 + 4). Das betrifft ausschließlich
die Entwickler\*innen-Laufzeit, nicht die Domäne und nicht die Produktion.

## Wichtige ausdrückliche Nicht-Ziele (für Transparenz)

- **Das `Project`-Aggregate** (Stammdaten wie Name, Zeitraum, Status) ist
  *nicht* Teil dieses Changes — es bleibt ein eigener, Stakeholder-getriebener
  Folge-Change. Heute bleibt `ProjectId` eine unveränderliche UUID.
- **Registrierung, Passwörter, MFA** bleiben im IdP; das Backend never berührt
  diese.
- **Eine rollenbasierte RBAC-Engine** wird nicht eingeführt; die
  Berechtigungsprüfung in v1 ist eine schlanke Projekt-Mitgliedschafts-Prüfung.
  Rollen-spezifische Regeln („nur Kostümbildner\*innen dürfen …") werden
  später einzeln und explizit hinzugefügt.

## Wie Sie antworten können

- Punkt-für-Punkt zu den vier Fragen — kurze Antwort reicht.
- Wenn eine Frage unklar formuliert ist: nachfragen, wir formulieren um.
- Antworten werden in `tasks.md` (Abschnitt 9) als erledigte Häkchen
  festgehalten, so dass die Implementierung erst nachvollziehbar freigegeben
  wird.
