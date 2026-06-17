= Risks and Technical Debt

== Risk List

#warning[
  This chapter describes known risks and technical debt that could impact the project.
]

=== Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Event Store Growth | High | Medium | Snapshotting, archiving |
| Concurrency Conflicts | Medium | High | Optimistic locking, retry |
| PostgreSQL Single Point of Failure | Low | High | Replication, backup strategy |
| Rust Ecosystem Maturity | Low | Low | Stick to stable crates |
| Team Rust Experience | Medium | Medium | Training, pair programming |

== Technical Debt

=== Debt Item 1: No Authentication/Authorization

*Description*: Currently no auth implemented (development phase)

*Impact*:
- Cannot deploy to production
- Security vulnerability

*Remediation*:
- Implement JWT or session-based auth
- Add RBAC (Role-Based Access Control)
- *Priority*: High
- *Effort*: 2-3 days

=== Debt Item 2: Missing Projections

*Description*: Some read models not yet implemented

*Impact*:
- Limited query capabilities
- May need to query aggregates directly (anti-pattern)

*Remediation*:
- Implement missing projectors
- Add integration tests for projections
- *Priority*: Medium
- *Effort*: 1-2 days per projection

=== Debt Item 3: No Integration Tests

*Description*: Only unit tests for domain logic

*Impact*:
- May miss infrastructure bugs
- Hard to refactor with confidence

*Remediation*:
- Add `testcontainers` for PostgreSQL tests
- Add API integration tests
- *Priority*: Medium
- *Effort*: 3-5 days

== Known Issues

=== Issue 1: UUIDv7 Collision Risk

*Description*: Theoretically possible but extremely unlikely

*Mitigation*: UUIDv7 uses 48-bit timestamp + 74 random bits

=== Issue 2: Event Schema Evolution

*Description*: Changing event structure breaks event replay

*Mitigation*:
- Use versioned events
- Upcasting pattern for migrations
- Never delete old event types

// TODO: Add more risks and debt items
// TODO: Add regular review process for risks
// TODO: Add debt repayment roadmap
