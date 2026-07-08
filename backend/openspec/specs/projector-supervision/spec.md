# Purpose

Define the supervised lifecycle for projector subscription loops — backoff restart on error/panic, bounded retry budget, and restart/health observability.

# Requirements

### Requirement: Projector subscription loops are supervised and restart on failure
Each projector's SierraDB subscription stream spawned by `crates/infra` SHALL be wrapped in a supervisor that, when the `stream.run()` task returns `Err` or panics, restarts the subscription (rebuilding the `subscription_manager` and `event_handler_stream`) from the projector's SierraDB checkpoint without restarting the API process. The supervisor SHALL keep the existing `kameo::ActorRef<PostgresProcessor>` valid across restarts.

#### Scenario: Transient stream error triggers in-process restart
- **WHEN** `stream.run()` returns `Err` for the scene projector's subscription
- **THEN** the supervisor rebuilds the scene projector's subscription and resumes catching up from its checkpoint
- **AND** the API process is not restarted
- **AND** the `CharacterProjector`, `CostumeProjector`, and `CalculationProjector` subscription loops are unaffected

#### Scenario: Task panic does not kill the supervisor
- **WHEN** the scene projector's `stream.run()` future panics during event handling
- **THEN** the panic is caught by the supervisor and treated as a failure
- **AND** the supervisor records the panic payload in a `tracing` event
- **AND** the subscription is restarted on the next backoff cycle without terminating the supervisor task

#### Scenario: ActorRef remains valid across restarts
- **WHEN** the supervisor restarts a projector's subscription loop after a failure
- **THEN** the `kameo::ActorRef<PostgresProcessor>` returned by the original `spawn_*_projector` call continues to be usable and is not re-spawned

### Requirement: Restarts use bounded exponential backoff with jitter
The supervisor SHALL delay between consecutive failed-epoch restart attempts using exponential backoff with a cap and random jitter. The supervisor SHALL maintain a consecutive-failure attempt counter that is reset to zero after a subscription epoch that runs longer than a configured reset window without failing. After a configured maximum number of consecutive failures the supervisor SHALL stop restarting and emit a terminal `tracing::error!` identifying the projector category and the last error.

#### Scenario: Backoff increases between consecutive failures
- **WHEN** the costume projector's subscription fails twice in quick succession
- **THEN** the delay before the second restart attempt is greater than or equal to the delay before the first restart attempt
- **AND** no restart attempt is made with a delay exceeding the configured maximum delay

#### Scenario: Long successful epoch resets the failure counter
- **WHEN** a projector's subscription runs successfully for longer than the reset window and then fails
- **THEN** the consecutive-failure attempt counter restarts at one
- **AND** the backoff delay returns to the base value

#### Scenario: Budget exhaustion is a loud terminal state
- **WHEN** a projector's subscription fails the configured maximum number of consecutive attempts without exceeding the reset window
- **THEN** the supervisor stops retrying
- **AND** emits a `tracing::error!` containing the projector category and the last error
- **AND** the other three projectors continue running unaffected

### Requirement: Per-projector restart and health events are emitted via tracing
The supervisor SHALL emit structured `tracing` events keyed by `projector.category` for every restart attempt (warn), budget exhaustion (error), and successful (re)start (info), including the attempt count and, for restarts, the applied backoff delay. These fields SHALL be compatible with the existing OpenTelemetry tracing pipeline.

#### Scenario: Restart emits a structured warn event
- **WHEN** the supervisor schedules a restart attempt for the `character` projector
- **THEN** a `tracing::warn!` event is emitted containing `projector.category = "character"`, the attempt count, and the backoff delay in milliseconds

#### Scenario: Successful start emits an info event
- **WHEN** a projector's subscription stream starts or restarts successfully
- **THEN** a `tracing::info!` event is emitted containing the `projector.category`

### Requirement: Supervisor stays within the infra crate boundary
The supervisor, restart loop, backoff constants, and health-emission logic SHALL live entirely within `crates/infra`. `crates/core` SHALL NOT define any projector, supervisor, or restart trait. `crates/api` SHALL NOT change its projector wiring; the `spawn_scene_projector`, `spawn_character_projector`, `spawn_costume_projector`, and `spawn_calculation_projector` function signatures and return types SHALL remain unchanged.

#### Scenario: No core or api changes
- **WHEN** `crates/core` is built
- **THEN** no `Supervisor`, `Projector`, or restart-related trait is exported
- **WHEN** `crates/api` is built
- **THEN** its calls to the `spawn_*_projector` functions compile without modification and use the same signatures as before this change
