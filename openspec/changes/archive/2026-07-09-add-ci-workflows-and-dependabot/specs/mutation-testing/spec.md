## ADDED Requirements

### Requirement: Mutation testing runs on a weekly schedule
A mutation testing workflow SHALL execute automatically on a weekly schedule (e.g., Sunday night) to assess test quality.

#### Scenario: Weekly mutation testing executes
- **WHEN** the scheduled time arrives (weekly)
- **THEN** the workflow SHALL run `cargo mutants` against the workspace

### Requirement: Mutation testing can be triggered manually
The mutation testing workflow SHALL support `workflow_dispatch` for manual execution.

#### Scenario: Manual mutation testing trigger
- **WHEN** a developer manually triggers the mutation testing workflow from the GitHub Actions UI
- **THEN** the workflow SHALL execute `cargo mutants`

### Requirement: Mutation testing does not block PRs
The mutation testing workflow SHALL NOT be triggered on pull requests or push events. It SHALL only run on schedule or manual dispatch.

#### Scenario: PR does not trigger mutation testing
- **WHEN** a pull request is opened or updated
- **THEN** the mutation testing workflow SHALL NOT execute

### Requirement: Mutation testing uses build caching
The mutation testing workflow SHALL use `Swatinem/rust-cache@v2` for build caching.

#### Scenario: Cache restores for mutation testing
- **WHEN** mutation testing runs after the first execution
- **THEN** the `rust-cache` action SHALL restore cached dependencies
