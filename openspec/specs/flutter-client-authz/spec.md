# flutter-client-authz Specification

## Purpose
TBD - created by archiving change add-flutter-app-foundation. Update Purpose after archive.
## Requirements
### Requirement: Client-Side AUTHZ-GATE Before Gated Calls
Every screen route SHALL be gated by auth state, and every call to a
handler-internal-authz-gated backend endpoint (photo upload, photo byte
fetch, photo delete, continuity-photo handlers) SHALL run a client-side
role/membership check via a `currentMembershipProvider` *before* any network
call is made. This is the client-side analog of the backend's
`// AUTHZ-GATE:` handler-internal authorization pattern. The login route,
the OIDC callback route, and the recovery route are the sole exceptions:
they SHALL remain publicly reachable before a session exists, so the user can
establish one.

#### Scenario: User lacks upload role
- **WHEN** a user without an active costume/continuity role taps the
  "Continuity Photo" capture action.
- **THEN** the action short-circuits client-side
  (`ref.read(currentMembershipProvider).valueOrNull` denies), shows a
  localized 403 narrative, and never issues the `POST .../continuity-photos`
  request.

#### Scenario: A new photo handler is added without a gate
- **WHEN** a PR adds a new endpoint call under an `Authenticated`-only route
  that performs a privileged action, without a `// AUTHZ-GATE:` comment and
  a `currentMembershipProvider` check.
- **THEN** review rejects it (mirrors the backend `grep AUTHZ-GATE`
  verification).

### Requirement: OIDC Token Storage and Cert Pinning
OIDC tokens SHALL be stored in `flutter_secure_storage` (never plaintext prefs);
the HTTP client SHALL pin TLS roots matching the backend's pinned-CA stance
(ADR-024), configured via `--dart-define`/flavor. No `danger_accept_invalid_certs`
equivalent is permitted in any client code path.

#### Scenario: A debug build is configured to bypass TLS verification
- **WHEN** a developer adds an "allow self-signed" convenience in any committed
  code path or flavor.
- **THEN** review rejects it; development trusts go into the dev flavor's
  pinned CA set, never into a disable-verification switch.

### Requirement: No Hardcoded Secrets
No secrets (OIDC client secrets, API keys, Garage credentials) SHALL be
committed to — or embedded in — the Flutter binary. `gitleaks` scans `.dart`,
`.yaml`, and `.arb` files. `--dart-define` carries only non-secret
configuration and public client identifiers (API base URL, OIDC issuer,
public client id, pinned-CA PEM); because Flutter embeds `--dart-define`
values in the compiled artifact where users can extract them, confidential
credentials (Garage keys, confidential-client secrets) stay server-side and
are never passed to the app.

#### Scenario: A developer passes a server-side credential via --dart-define
- **WHEN** a build embeds a Garage key or a confidential OIDC client secret
  through `--dart-define`.
- **THEN** review rejects it: `--dart-define` values are extractable from the
  compiled artifact, so those credentials must stay server-side; only public
  identifiers and non-secret configuration may be embedded.

#### Scenario: A developer hardcodes a client secret
- **WHEN** gitleaks finds a literal credential in a `.dart`/`.yaml` file.
- **THEN** CI fails (mirrors backend supply-chain posture).

### Requirement: currentMembershipProvider for AUTHZ-GATE Checks
A `currentMembershipProvider` SHALL expose the authenticated user's
membership/role state so that gated backend calls run a client-side role
check before any network call. A new gated handler call without a
`// AUTHZ-GATE:` comment and a `currentMembershipProvider` check is
rejected at review.

#### Scenario: User lacks upload role (resolved denial)
- **WHEN** a user whose `currentMembershipProvider(seasonId)` has resolved to
  a membership with `canUploadContinuityPhotos == false` taps the capture
  action.
- **THEN** the action short-circuits client-side via an explicit
  resolved-data check on `currentMembershipProvider(seasonId)` (matching only the
  `AsyncData` branch, never loading or error), shows a localized 403 narrative,
  and never issues the `POST .../continuity-photos` request. This is a
  *resolved-denial* state, distinct from loading/error (see the loading/error
  requirement).

### Requirement: Cert Pinning Matches Backend Pinned-CA Stance
The HTTP client SHALL pin TLS roots per flavor (ADR-024), sourced from
`--dart-define`. No `danger_accept_invalid_certs`-equivalent in any code
path.

#### Scenario: A debug build bypasses TLS verification
- **WHEN** a committed code path disables verification outside the dev
  flavor's pinned-CA set.
- **THEN** review rejects it; dev trusts go into the dev flavor's pinned CA
  set only.

### Requirement: Season-Scoped Membership Provider Mapped From Backend Roles

`currentMembershipProvider` SHALL be a family keyed by `seasonId`
(`currentMembershipProvider(SeasonId)`) that reads **one** endpoint,
`GET /v1/seasons/{seasonId}/membership`, returning a `SeasonMembershipDto`. The
"active continuity role" SHALL be derived from the backend-computed
`has_active_costume_role_in_season(season_id, sub)` boolean surfaced on that
DTO; the client SHALL NOT re-implement that predicate. Server authorization
remains authoritative; the client check is a gate only.

The `SeasonMembershipDto` contract (single wire source of truth) is:
- `seasonId: String`
- `hasActiveCostumeRoleInSeason: bool` (backend-computed)
- `capabilities: List<Capability>` enum (`uploadContinuityPhotos`,
  `assignCostumes`, …) derived server-side from the boolean roles
- error shape: non-2xx → `AsyncError`; forbidden/missing season → backend
  `application/problem+json` with a stable `code`, mapped to the localized
  narrative (never from `detail`)

#### Scenario: Membership resolves for the active season

- **WHEN** `currentMembershipProvider(activeSeasonId)` resolves to a
  membership whose DTO carries `has_active_costume_role_in_season == true`.
- **THEN** the provider exposes a `canUploadContinuityPhotos` capability
  derived from that boolean, and the gated capture action is enabled.

#### Scenario: Client never reconstructs roles from other projections

- **WHEN** the UI needs to gate a continuity action.
- **THEN** it reads the season-scoped membership DTO only; it does not derive
  `series_id` or role state from a different read-model call (CQRS-boundary
  rule), and it does not treat a client "allow" as server authorization.

### Requirement: Membership Loading/Error Is Not a Denial

When `currentMembershipProvider(seasonId)` is `AsyncLoading` or `AsyncError`,
the gated action SHALL be disabled (spinner / retry affordance) but SHALL NOT
be reported as forbidden. A 403 narrative SHALL appear only on a *resolved*
denial (value present, capability `false`). A membership error SHALL offer a
retry that refreshes the provider.

#### Scenario: Membership is still loading

- **WHEN** `currentMembershipProvider(seasonId)` is loading
  (`valueOrNull == null`, no error).
- **THEN** the capture action is disabled with a spinner and no 403 message
  is shown.

#### Scenario: Membership lookup errors

- **WHEN** `currentMembershipProvider(seasonId)` is in `AsyncError`.
- **THEN** the capture action is disabled with a retry affordance (which
  calls `ref.refresh`), and the user is shown a transient error — not a
  "forbidden" narrative.

### Requirement: Exclusive, Fail-Closed TLS Pinning

The HTTP client SHALL pin TLS roots exclusively: a `SecurityContext` with **no
default trust roots**, populated only with the per-flavor pinned CA PEM(s)
from `--dart-define`. Platform/OS trust store SHALL be excluded in **both**
flavors. If the required CA list is missing/empty or fails to parse as valid
PEM, client construction SHALL throw at the composition root so startup
aborts with a fatal TLS-configuration screen before any network call.

#### Scenario: CA configuration is missing or invalid at startup

- **WHEN** the required `--dart-define` pinned-CA list is empty or not valid
  PEM.
- **THEN** `lib/main.dart` aborts startup (before `runApp`) and shows a fatal
  "TLS configuration invalid" screen; no `HttpClient` is constructed and no
  network call is made with an unpinned context.

#### Scenario: Platform roots are not used as a fallback

- **WHEN** a dev or prod build constructs its pinned `SecurityContext`.
- **THEN** it adds only the flavor's pinned CA cert(s) and contains no
  default/system trust roots, so a public-CA-signed cert is rejected.

### Requirement: Dev IdP Transport Exception Is Dev-Flavor-Only

The dev IdP SHALL be reachable over HTTPS pinned to the dev CA set as the
primary transport. A documented HTTP port-forward exception SHALL be gated by
`--dart-define=DEV_IDP_INSECURE=1`, SHALL relax pinning only for the IdP host,
and SHALL be impossible in the `prod` flavor. Enforcement is an **explicit
flavor/startup guard, not a Dart assert**: the flag is read only inside
`if (!kReleaseMode)`, and `lib/main.dart` throws at startup if the flag is set
while `kReleaseMode` is true, so a release artifact can never relax pinning.

#### Scenario: Dev uses an HTTP port-forward IdP

- **WHEN** a dev build runs with `--dart-define=DEV_IDP_INSECURE=1` and the
  IdP is reached over `http://localhost:3301`.
- **THEN** pinning is relaxed only for the IdP host, the API host remains
  pinned, and a `prod` build with the same flag fails its build-time guard.

#### Scenario: Prod build cannot disable IdP pinning

- **WHEN** a `prod` flavor is compiled, or `DEV_IDP_INSECURE=1` is passed to a
  release build.
- **THEN** the flag is never consulted (`if (!kReleaseMode)` guard) and
  `lib/main.dart` throws at startup if it is set under `kReleaseMode`, so the
  IdP is always pinned; no unpinned transport is reachable.

