## ADDED Requirements

### Requirement: Budget Core Logic
The Calculation Aggregate SHALL track exact costs mapping financial operations safely.

#### Scenario: Submitting metadata headers
- **WHEN** users process `CreateCalculation` and later `UpdateHeaderInfo` (Subjects, sender headers).
- **THEN** matching `CalculationCreated` and `HeaderInfoUpdated` stream elements populate.

### Requirement: Granular Pricing Operations
The Aggregate SHALL enforce discrete numeric safety using the rust_decimal package upon child records acting as budget lists.

#### Scenario: Line Item adjustments
- **WHEN** items fire an `AddCalculationItem`, `UpdateCalculationItem`, or `RemoveCalculationItem` operation.
- **THEN** the internal lists validate safe `rust_decimal::Decimal` bindings mapping into `CalculationItemAdded`, `CalculationItemUpdated` or `CalculationItemRemoved` state loops.
 
#### Scenario: Payout flagging
- **WHEN** boolean commands like `MarkItemAsPaid` and `MarkItemAsUnpaid` are pushed.
- **THEN** the flags flip correctly enforcing sequential payment history mapping into corresponding `ItemMarkedAsPaid` / `ItemMarkedAsUnpaid` streams.