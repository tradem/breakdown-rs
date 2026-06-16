# ADR-001: Use Hexagonal Architecture (Ports and Adapters)

**Status**: Accepted  
**Date**: 2024-01-16  
**Author**: Initial Architecture Decision

---

## Context

Breakdown RS is a collaborative costume scheduling application that needs to be:
- **Testable**: Domain logic should be testable without infrastructure
- **Flexible**: Ability to swap database, web framework, or external services
- **Maintainable**: Clear boundaries between domain logic and technical details
- **Independent**: Core domain should not depend on frameworks or external libraries

Traditional layered architectures often lead to tight coupling between business logic and infrastructure, making the application hard to test and evolve.

## Decision

We will use **Hexagonal Architecture** (also known as Ports and Adapters) with the following structure:

```
crates/core        → Domain logic (pure, no dependencies on infra/api)
  - Commands, Events, Aggregates
  - Port traits (interfaces for external dependencies)
  - Read-model DTOs

crates/infra       → Infrastructure implementations
  - EventStore implementations
  - Projectors (read-model updaters)
  - SQLx queries

crates/api         → HTTP layer (Axum)
  - Routes, handlers
  - Translates HTTP → Commands / Queries

crates/architecture → Architecture tests
  - Enforces dependency rules
```

### Key Principles:
1. **Dependency Inversion**: Core defines interfaces (ports), infra implements them (adapters)
2. **No DI Framework**: Use "Poor Man's DI" - manual dependency injection in `main.rs`
3. **Core is Pure**: `crates/core` has zero dependencies on `sqlx`, `axum`, or any infra concerns

## Consequences

### Positive
- ✅ **Testability**: Domain logic can be unit-tested without mocks or database
- ✅ **Flexibility**: Can swap PostgreSQL for EventStore, or Axum for Actix without touching core
- ✅ **Clarity**: Clear boundaries - developers know where to put code
- ✅ **Event Sourcing Ready**: Natural fit for CQRS/ES pattern (see ADR-002)

### Negative
- ⚠️ **Initial Complexity**: More boilerplate (traits, DTOs, adapters)
- ⚠️ **Learning Curve**: Team must understand hexagonal architecture
- ⚠️ **Indirection**: More files to navigate (trait → implementation)

### Mitigation
- Use code generation or macros where appropriate
- Document patterns clearly in `AGENTS.md`
- Pair programming for onboarding

## Alternatives Considered

1. **Clean Architecture**: Similar but more layers (Entities → Use Cases → Controllers). Chose Hexagonal for simplicity.
2. **Layered Architecture**: Too coupled, harder to test.
3. **No Architecture**: Fast start but becomes unmaintainable quickly.

## Notes

- See `AGENTS.md` for detailed coding patterns
- Architecture tests in `crates/architecture` enforce the rules
- Inspired by: [Hexagonal Architecture by Alistair Cockburn](https://alistair.cockburn.us/hexagonal-architecture/)

---

**Related ADRs**:
- [ADR-002: Use Event Sourcing and CQRS](./ADR-002-event-sourcing-cqrs.md)
