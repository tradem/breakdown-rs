## Context

The core domain of Breakdown RS is being designed around Hexagonal Architecture principles to encapsulate pure domain logic from infrastructural concerns. Utilizing CQRS and Event Sourcing via `kameo_es`, the domain models the interactions between Characters, Scenes, Costumes, and Calculations. The initial design handles relationships loosely through identifier (`Uuid`) references across boundaries instead of complex nested structures or inter-aggregate calls.

## Goals / Non-Goals

**Goals:**
- Completely encapsulate robust Event Sourced Actor Logic inside `crates/core`.
- Maintain correct types safely without relying on infrastructure (e.g. `rust_decimal` for currency).
- Support Optimistic Locking for UI data consistency using an `AggregateVersion` wrapper during `apply` flows.
- Structure event creation to decouple God-Command structures (full payload replacements) from behavioral fine-grained commands (e.g., resource allocations).

**Non-Goals:**
- Handling database persistence architectures (Projectors / Read-Models are infrastructure details out of scope).
- Orchestration logic between differing aggregates directly in the domain code (Saga/Process Managers are deferred to API/infrastructure levels).
- Modeling a complete `ProjectAggregate` handling statuses (Script parsing disposition) is out of scope for v1. Projects act purely as UUIDs right now.

## Decisions

1. **Typing & Numeric Safety**
   - **Decision**: Eradicate Floating Point Usage (`f32`/`f64`) in favor of `rust_decimal::Decimal`.
   - **Rationale**: Floating-point behavior causes unpredictable issues inside typified structs due to lack of standard `Eq` trait formatting for deterministic event tracking. This also strictly guarantees currency behavior for `CalculationItem` prices.
   
2. **Actor Lifecycle Handling and Locking Options**
   - **Decision**: Integrate `AggregateVersion` as a manual value object instead of solely relying on the DB to fail for optimistic locking.
   - **Rationale**: Validations must occur within the single thread of a `kameo_es` mailbox before infrastructure executes the event logging.

3. **Domain References & Bound Context Data**
   - **Decision**: Defer deep relationship graphs (`Project` entities parsing) to external infrastructure or API boundaries holding foreign ID values as references.
   - **Rationale**: Prevents cyclic dependencies, simplifies initial implementation efforts, and adheres tightly to CQRS island aggregate rules.

4. **Event Updates (Data vs Behavior)**
   - **Decision**: Update forms for entities like `Scene` and `Character` map to "God-Commands", updating the entire DTO block on the actor in one event. A contextual action like Assignation stays its own Command/Event.
   - **Rationale**: Granular tracking on character body measurements emits huge, unusable event streams for simple UI CRUD submits, leading to boilerplate bloat.

## Risks / Trade-offs

- Risk: Lack of a `RemoveCostumeFromProject` enforcement rule due to missing `Project` aggregate logic in the scope of Costume bounds.
  - Mitigation: API/Infrastructure boundaries enforce logic querying projection tables before dispatching events.
- Risk: "God-Commands" can bloat Event Streams if user hits "Save" 50 times in a row without modification.
  - Mitigation: Actors should validate diffs and ignore the persistence write if the states haven't changed.
