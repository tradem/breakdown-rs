# ADR-004: Use UUIDv7 for all Entities and Events

**Status**: Accepted  
**Date**: 2024-01-16  
**Author**: Initial Architecture Decision

---

## Context

Breakdown RS needs unique identifiers for:
- **Entities**: Scenes, Costumes, Actors, Users, etc.
- **Events**: Every domain event must have a unique ID
- **Aggregates**: Must be uniquely identifiable

Requirements:
- **Globally unique**: Distributed system, no central ID generator
- **Time-ordered**: Events should be sortable by creation time
- **URL-safe**: IDs appear in API endpoints (`/api/scenes/{id}`)
- **Database-friendly**: Sequential IDs reduce index fragmentation
- **Collision-free**: No duplicates even under high concurrency

### Problems with alternatives:
- **UUIDv4**: Random, not time-ordered → index fragmentation in databases
- **Auto-increment**: Not distributed, reveals business volume (security risk)
- **Snowflake**: Requires coordinated timestamp, complex
- **ULID**: Similar to UUIDv7 but less standard

## Decision

We will use **UUIDv7** for ALL entities and events in the system.

### What is UUIDv7?

UUIDv7 is a **time-ordered UUID** defined in RFC 9562 (draft at time of decision):
- **48 bits**: Unix timestamp in milliseconds
- **74 bits**: Random data (for uniqueness)
- **6 bits**: Version (7) and variant (RFC 4122)
- **Format**: `018ebc23-9a0a-7f8a-9b2c-4d5e6f7a8b9c`

### Implementation in Rust

```rust
use uuid::Uuid;

// Generate UUIDv7
let id = Uuid::now_v7();  // Creates time-ordered UUID

// In domain models
pub struct Scene {
    pub id: Uuid,  // Always UUIDv7
    // ...
}

// When creating events
pub enum SceneEvent {
    SceneCreated {
        id: Uuid,  // UUIDv7 for the event
        scene_id: Uuid,  // UUIDv7 for the aggregate
        // ...
    }
}
```

### Configuration

Ensure `uuid` crate is configured with v7 support:

```toml
# Cargo.toml
[dependencies]
uuid = { version = "1.7", features = ["v7", "serde", "std"] }
```

## Consequences

### Positive
- ✅ **Time-ordered**: Events naturally sorted by creation time (no separate `created_at` needed)
- ✅ **Database performance**: Sequential inserts reduce B-tree fragmentation
- ✅ **Distributed-safe**: No coordination needed, no central ID generator
- ✅ **Standard**: RFC 9562, widely supported (PostgreSQL `uuid-ossp`, JavaScript `uuid`)
- ✅ **Debuggable**: Timestamp embedded (can extract creation time from ID)
- ✅ **URL-safe**: 36 characters, no special chars

### Negative
- ⚠️ **Larger than integer**: 36 chars vs 8 bytes for `i64` (but necessary for distribution)
- ⚠️ **Not completely sequential**: Random bits can cause slight fragmentation (minimal)
- ⚠️ **Newer standard**: UUIDv7 is relatively new (but widely implemented)

### Database Indexing

With UUIDv7, these indexes work efficiently:

```sql
-- Events table: naturally ordered by event_id (UUIDv7)
CREATE INDEX idx_events_by_time ON events(event_id);

-- Fetch events in order (no separate timestamp column needed)
SELECT * FROM events 
WHERE aggregate_id = $1 
ORDER BY event_id ASC;  -- Time-ordered!
```

## Alternatives Considered

### 1. UUIDv4
- **Pros**: Widely supported, random
- **Cons**: Not time-ordered, index fragmentation, no embedded timestamp
- **Why not**: Database performance issues at scale

### 2. Auto-increment Integers
- **Pros**: Small, fast, sequential
- **Cons**: Not distributed, reveals volume (security), hard to merge data
- **Why not**: Breaks when scaling to multiple services

### 3. ULID (Universally Unique Lexicographically Sortable Identifier)
- **Pros**: Time-ordered, 128-bit, case-insensitive
- **Cons**: Not a standard, less ecosystem support
- **Why not**: UUIDv7 achieves same goal with standardization

### 4. Snowflake IDs (Twitter)
- **Pros**: Time-ordered, smaller (64-bit)
- **Cons**: Requires coordinated timestamp, complex implementation
- **Why not**: Overkill for our use case, UUIDv7 is simpler

## Rules and Enforcement

1. **NEVER use UUIDv4**: Always use `Uuid::now_v7()`
2. **All entities**: Scenes, Costumes, Actors, Users, etc. → UUIDv7
3. **All events**: Every domain event must have UUIDv7 as event ID
4. **API responses**: Always return UUIDv7 as string
5. **Database**: Store as `UUID` type (PostgreSQL), not as string

### Architecture Test

Add to `crates/architecture` to enforce:

```rust
#[test]
fn entities_must_use_uuidv7() {
    // Static analysis: ensure no Uuid::new_v4() in domain code
}
```

## Migration and Compatibility

- **PostgreSQL**: `uuid-ossp` extension supports UUIDv7 generation
- **JavaScript/TypeScript**: `uuid` package v9+ supports UUIDv7
- **Other languages**: Most have UUIDv7 libraries

### Generating UUIDv7 in PostgreSQL

```sql
-- Install extension (if not already available)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Generate UUIDv7 (custom function, as pgcrypto doesn't have v7 yet)
CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS uuid AS $$
BEGIN
    -- Implementation depends on PostgreSQL version
    -- For now, generate in application layer (Rust)
    RETURN uuid_generate_v4();  -- Placeholder
END;
$$ LANGUAGE plpgsql;
```

**Recommendation**: Generate UUIDv7 in application layer (Rust), not in database.

## Notes

- **Timestamp extraction**: You can extract creation time from UUIDv7:
  ```rust
  let uuid = Uuid::now_v7();
  let timestamp_ms = extract_timestamp_from_uuidv7(&uuid);
  ```
- **Debugging tip**: When you see a UUIDv7, you can roughly tell when it was created
- **Performance**: UUIDv7 has minimal fragmentation (unlike v4), but still not as good as auto-increment

---

**Related ADRs**:
- [ADR-001: Use Hexagonal Architecture](./ADR-001-hexagonal-architecture.md)
- [ADR-003: Use PostgreSQL as Primary Database](./ADR-003-use-postgresql.md)

**References**:
- [UUIDv7 Specification (RFC 9562)](https://datatracker.ietf.org/doc/rfc9562/)
- [uuid crate documentation](https://docs.rs/uuid/latest/uuid/)
