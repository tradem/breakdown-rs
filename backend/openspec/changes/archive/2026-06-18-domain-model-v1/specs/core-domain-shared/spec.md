## ADDED Requirements

### Requirement: Shared Domain Primitives
The core logic SHALL utilize specific Domain Primitives and Value Objects universally to maintain consistency and eliminate floating-point inaccuracies.

#### Scenario: Identifiers and Optimistic Locking initialization
- **WHEN** any aggregate is instantiated
- **THEN** it must assign Uuidv7 variables generated via the bounded context rules and hold an initial struct property of `AggregateVersion(1)`.

#### Scenario: Monetary or measurement value input
- **WHEN** calculations, item prices, or physical measurements require decimals
- **THEN** they MUST be represented strictly via the `rust_decimal::Decimal` type instead of `f32` or `f64`.