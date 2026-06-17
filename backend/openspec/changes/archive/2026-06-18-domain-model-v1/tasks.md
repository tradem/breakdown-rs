## 1. Domain Primitive Setup

- [x] 1.1 Include `rust_decimal` dependency in `crates/core/Cargo.toml`.
- [x] 1.2 Define globally shared Value Objects (`AggregateVersion` Tuple-Struct, `ProjectId` Type Alias mapped to `Uuid`) in a `shared` module inside `crates/core`.

## 2. Character Domain Model

- [x] 2.1 Create the `CharacterError` Enum mapping validation errors via `thiserror`.
- [x] 2.2 Model the `CharacterAggregate` state Struct, `CharacterEvent` Enums, and the Command Structs.
- [x] 2.3 Implement the `kameo_es` Aggregate lifecycle Trait methods (`execute`, `apply`) for Character Commands (Handling `MeasurementsUpdated` and `ContactInfoUpdated` as God-Command data payloads).

## 3. Scene Domain Model

- [x] 3.1 Create the `SceneError` Enum mapping validation errors mapping assigning bounds.
- [x] 3.2 Model the `SceneAggregate` state Struct, `SceneEvent` Enums, and Command Structs.
- [x] 3.3 Implement `execute` and `apply` for Scene Commands distinguishing relation bindings (Characters) against content metadata overwrites (SceneDetails).

## 4. Costume Domain Model

- [x] 4.1 Create the `CostumeError` Enum with specific variants for `AlreadyAssigned` states.
- [x] 4.2 Model the `CostumeAggregate` handling Fundus-Behavior (using `Option<Uuid>` character IDs).
- [x] 4.3 Structure commands regarding Photo linking and descriptive Detail additions.
- [x] 4.4 Implement core lifecycle rules to emit relationship events when costumes are assigned vs general note updates.

## 5. Calculation Domain Model

- [x] 5.1 Create `CalculationError` Error Enums.
- [x] 5.2 Build the `CalculationAggregate` state and Command definitions utilizing `rust_decimal::Decimal` bindings for calculation variables (quantities, values).
- [x] 5.3 Implement the discrete Item lifecycle functions adding compensating actions (`RemoveCalculationItem`, `UpdateCalculationItem`, `MarkItemAsUnpaid`).
