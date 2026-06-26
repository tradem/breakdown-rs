# Feedback: Verbesserung der AST-Tool-Nutzung in `pi-ast-bro`

**Status:** Beobachtung aus produktiver Nutzung  
**Datum:** 2026-06-19  
**Quelle:** Agent-Reflexion nach einer Architektur-Anfrage im `breakdown-rs`-Projekt  

---

## Zusammenfassung

Bei der Anfrage, die Zusammenhänge zwischen Entitäten und Aggregaten im Core Bounded Context zu skizzieren, hat der Agent (`pi`) zuerst mehrere Quellcodedateien mit `read` geladen, anstatt die verfügbaren AST-Features (`analyze_ast_map`, `analyze_ast_search`, `analyze_ast_impact`) als ersten Anlauf zu verwenden.

Das Feedback dokumentiert, **warum** dies geschah und **welche Änderungen** an Prompting, Tool-API und Agenten-Verhalten das künftig vermeiden könnten.

---

## Auslöser: Konkretes Szenario

**User-Anfrage:**

> „Kannst du mir die Zusammenhänge zwischen den Entitäten und Aggregaten des Core Bound Context skizzieren?“

**Tatsächliches Verhalten des Agenten:**

1. `read` von `shared.rs`
2. `read` von `character/aggregate.rs`
3. `read` von `costume/aggregate.rs`
4. `read` von `scene/aggregate.rs`
5. `read` von `calculation/aggregate.rs`
6. `read` aller vier `events.rs`-Dateien

**Erwartetes Verhalten (_AST-first_):**

1. `analyze_ast_map` auf `backend/crates/core` für den groben Aufbau
2. `analyze_ast_search` für referenzielle Schlüssel (`ProjectId`, `character_id`, `assigned_characters`)
3. Nur bei Bedarf gezieltes `read` für Geschäftsregeln und Semantik

---

## Diagnose: Warum `read` zuerst?

### 1. Prompting-Ebene: Keine klare „AST-first“-Entscheidungsregel

Die Tool-Beschreibungen im System-Prompt sind funktional korrekt, aber sie definieren nicht, **in welcher Reihenfolge** sie für bestimmte Fragetypen zu verwenden sind.

Der Agent hat daher intuitiv `read` gewählt, weil die Anfrage nach „Verständnis“ klang. Das Problem ist nicht die Verfügbarkeit der Tools, sondern die **fehlende Rangfolge** im Workflow.

**Beobachtung:** Sobald ein User Wörter wie „skizziere“, „erkläre“ oder „wie hängt das zusammen“ verwendet, verfällt der Agent in einen Lesemodus.

### 2. Tool-Ebene: AST-Tools liefern Struktur, aber noch keine Domain-Semantik

Die existierenden AST-Tools sind stark auf **Code-Struktur** ausgerichtet:

- `analyze_ast_map` → Module, Funktionen, Felder
- `analyze_ast_search` → Text- und Symbol-Treffer mit Snippets
- `analyze_ast_impact` → Caller/Callee-Beziehungen

Für **Domain-Driven Design** (Aggregates, Events, Commands, implizite ID-Referenzen) fehlt eine höherwertige Abstraktion. Der Agent muss selbst erkennen, dass `character_id: Option<Uuid>` im `CostumeAggregate` eine Beziehung zum `CharacterAggregate` darstellt.

### 3. Verhaltensebene: Fehlende Reflexion über den eigenen Ansatz

Der Agent hat nicht aktiv geprüft, ob eine AST-Variante geeigneter wäre. Es fehlt eine eingebaute Mini-Reflexion:

> „Der User fragt nach Architektur. Dies ist ein typischer Fall für AST-Strukturmapping, nicht für sequenzielles Lesen.“

---

## Konkrete Verbesserungsvorschläge

### Kurzfristig: Bessere Prompting-Regeln

1. **Einen „Wann-welches-Tool“-Entscheidungsbaum** in den System-Prompt oder in einen Skill aufnehmen:

   | Fragetyp | Erstes Tool | Zweites Tool | Drittes Tool |
   |----------|-------------|--------------|--------------|
   | Architektur / Zusammenhänge zwischen Modulen | `analyze_ast_map` auf Crate/Modul | `analyze_ast_search` für Referenzfelder | `read` für Semantik |
   | Wo wird ein Symbol verwendet? | `analyze_ast_impact` | `analyze_ast_search` | `read` bei Bedarf |
   | Implementierungen eines Traits? | `find_implementations` | – | `read` bei Bedarf |
   | Konkrete Geschäftslogik verstehen | `read` (direkt) | – | – |

2. **Explizite Reflexionsanweisung** einbauen:

   > „Bevor du mehr als zwei Dateien mit `read` lädst, überprüfe, ob `analyze_ast_map` oder `analyze_ast_search` eine effizientere Alternative wäre. Bedenke: Für Strukturfragen ist AST-first die bevorzugte Strategie.“

3. **Beispiel-Workflows** im Skill oder Prompt hinterlegen.

### Mittelfristig: Tool-API erweitern

#### Vorschlag A: `analyze_domain_map`-Tool

Ein neues, domänen-spezifisches Tool, das über reine AST-Struktur hinausgeht:

```json
{
  "tool": "analyze_domain_map",
  "path": "backend/crates/core"
}
```

Rückgabe-Beispiel:

```json
{
  "aggregates": [
    {
      "name": "CostumeAggregate",
      "root_id": "Uuid",
      "module": "costume::aggregate",
      "commands": [
        "CreateCostume",
        "AssignCostumeToCharacter",
        "UnassignCostume",
        "AddDetail",
        "RemoveDetail",
        "LinkPhoto",
        "UnlinkPhoto"
      ],
      "events": [
        "CostumeCreated",
        "CostumeAssignedToCharacter",
        "CostumeUnassigned",
        "DetailAdded",
        "DetailRemoved",
        "PhotoLinked",
        "PhotoUnlinked"
      ],
      "references": [
        { "field": "project_id", "type": "ProjectId", "kind": "scope" },
        { "field": "character_id", "type": "Option<Uuid>", "kind": "optional_reference", "suggested_target": "CharacterAggregate" }
      ]
    }
  ]
}
```

Dieses Tool würde bei der Anfrage nach Aggregate-Beziehungen **sofort** die erste Wahl sein.

#### Vorschlag B: ID-Referenz-Heuristik in bestehenden Tools

`analyze_ast_search` oder ein Ableger sollte erkennen können, dass ein Feld `<name>_id: Uuid` oder `<name>_ids: Vec<Uuid>` eine Referenz auf ein Aggregate mit dem Namen `<name>` ist.

Beispiel:

- `character_id: Option<Uuid>` im `CostumeAggregate` → Referenz zu `CharacterAggregate`
- `assigned_characters: Vec<Uuid>` im `SceneAggregate` → Referenz zu mehreren `CharacterAggregate`

#### Vorschlag C: Zusammenfassungsmodus für `analyze_ast_search`

Statt 50 rohe Snippets zurückzugeben, könnte ein Modus wie `summary=true` eine strukturierte Übersicht liefern:

- Welche Aggregate wurden gefunden?
- Welche gemeinsamen Value Objects?
- Welche Event-Typen?
- Welche potenziellen Beziehungen?

### Langfristig: Skill-basierte Workflows automatisch laden

Der Skill `ast-bro-refactor` existiert bereits, aber er scheint auf Refactorings fokussiert zu sein. Ein ergänzender Skill wie `ast-bro-architecture` könnte automatisch geladen werden, wenn der User nach:

- Architektur,
- Zusammenhängen,
- Aggregaten,
- Bounded Contexts oder
- Domain-Diagrammen

fragt. Der Skill würde dann den AST-first-Workflow hardcodieren.

---

## Empfohlene Tool-Reihenfolge für Architekturfragen

Für zukünftige Versionen sollte ein Agent bei Architekturfragen folgende Reihenfolge einhalten:

1. **`analyze_ast_map` auf Crate-Ebene**
   - Zeigt alle Module, Aggregate, Felder und Events
2. **`analyze_ast_search` für gemeinsame Value Objects**
   - `ProjectId`, `AggregateVersion` → zeigt projektübergreifende Scopes
3. **`analyze_ast_search` für referenzielle IDs**
   - `character_id`, `assigned_characters`, `photos` → zeigt Aggregate-übergreifende Beziehungen
4. **`find_implementations` für Traits**
   - z. B. `Command`, `Apply`, `Entity` → sammelt alle Aggregate-Handler
5. **`read` gezielt für Geschäftsregeln**
   - Nur bei Bedarf, z. B. für Idempotenzprüfungen oder Fehlerfälle

---

## Anhang: Beispiel einer künftigen Interaktion

**User:** „Skizziere die Beziehungen zwischen den Aggregaten.“

**Agent (gedachte Tool-Kette):**

1. `analyze_ast_map("backend/crates/core")` → Übersicht über Aggregate
2. `analyze_ast_search("ProjectId", top_k=20)` → Gemeinsamer Scope
3. `analyze_ast_search("character_id OR assigned_characters", top_k=20)` → Aggregate-Referenzen
4. `read` gezielt auf `costume/aggregate.rs`, um `CostumeError::AlreadyAssigned` zu verstehen
5. Antwort mit Diagramm und Erklärung

---

## Fazit

Die AST-Tools sind vorhanden und funktionsfähig, aber sie werden nicht automatisch als erste Wahl verwendet. Die größten Hebel liegen in:

1. **Prompting:** Klare Workflow-Regeln („AST-first bei Architekturfragen“)
2. **Tool-API:** Ein domänenorientiertes Mapping-Tool (`analyze_domain_map`)
3. **Heuristiken:** Automatische Erkennung von ID-basierten Aggregate-Beziehungen

Die Investition in Punkt 2 und 3 würde den größten Nutzen bringen, weil sie die **Lücke zwischen Syntax und Domain-Semantik** schließen.
