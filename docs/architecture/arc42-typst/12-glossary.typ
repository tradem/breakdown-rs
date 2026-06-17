= Glossary

== Domain Terms

#note[
  This chapter defines important domain and technical terms for consistent understanding.
]

=== Domain Glossary

| Term | Definition |
|------|------------|
| *Breakdown* | List of all costumes needed for a show, organized by scene |
| *Scene* | A segment of the production where costumes are tracked |
| *Costume* | An outfit worn by an actor in one or more scenes |
| *Continuity* | Ensuring costume consistency across scenes and performances |
| *Fitting* | Session where actor tries on costume |
| *Actor* | Person who wears costumes (in domain, not Rust actor) |
| *Show* | The production (e.g., "Hamlet", "The Lion King") |
| *Wardrobe* | Collection of all costumes for a production |

=== Technical Glossary

| Term | Definition |
|------|------------|
| *Aggregate* | Cluster of domain objects treated as a unit (DDD) |
| *Command* | Imperative request to change state (e.g., `CreateScene`) |
| *Event* | Fact that happened in the past (e.g., `SceneCreated`) |
| *Event Sourcing* | Storing state as sequence of events |
| *CQRS* | Command Query Responsibility Segregation |
| *Projection* | Read-optimized view of events |
| *Projector* | Component that updates projections from events |
| *Port* | Interface definition (Hexagonal Architecture) |
| *Adapter* | Implementation of a port (Hexagonal Architecture) |
| *UUIDv7* | Time-ordered UUID (128-bit, with timestamp) |
| *kameo* | Actor framework for Rust |
| *kameo_es* | Event Sourcing extension for kameo |
| *Axum* | Web framework for Rust (based on Tower) |
| *utoipa* | OpenAPI documentation generator for Axum |
| *sqlx* | Async SQL toolkit for Rust |
| *Typst* | Modern typesetting system (like LaTeX but simpler) |
| *arc42* | Template for architecture documentation |
| *Diátaxis* | Framework for documentation organization |
| *ADR* | Architecture Decision Record |
| *OpenAPI* | Standard for REST API documentation |
| *gitleaks* | Tool to detect secrets in git repos |
| *cargo mutants* | Mutation testing for Rust |
| *arch_test* | Architecture testing for Rust |

== Abbreviations

| Abbreviation | Meaning |
|--------------|---------|
| *API* | Application Programming Interface |
| *CI/CD* | Continuous Integration / Continuous Deployment |
| *CRUD* | Create, Read, Update, Delete |
| *DDD* | Domain-Driven Design |
| *DTO* | Data Transfer Object |
| *HTTP* | HyperText Transfer Protocol |
| *JSON* | JavaScript Object Notation |
| *JWT* | JSON Web Token |
| *PDF* | Portable Document Format |
| *RBAC* | Role-Based Access Control |
| *REST* | Representational State Transfer |
| *SQL* | Structured Query Language |
| *TLS* | Transport Layer Security |
| *UI* | User Interface |
| *URL* | Uniform Resource Locator |
| *UUID* | Universally Unique Identifier |

// TODO: Add more terms as domain evolves
// TODO: Link to external references for standard terms
// TODO: Add diagrams explaining domain concepts
