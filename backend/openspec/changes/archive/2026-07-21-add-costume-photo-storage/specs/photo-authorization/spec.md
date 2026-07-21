## ADDED Requirements

### Requirement: v1 derived Season-scoped costume-photo authorisation
The system SHALL authorise costume-photo access (upload, download, unlink) via a `SeasonPhotoAccessPolicy` that derives access from active costume-department block membership. A user SHALL be authorised to access costume photos in Season S if and only if they hold any of the roles `costume_designer`, `wardrobe_supervisor`, or `costume_assistant` in an `active`-state block whose season is S. The policy SHALL be an impl of the existing `AuthorizationPolicy` trait, consistent with the `MembershipAuthorizationPolicy` used for block-scoped access.

#### Scenario: Active costume-dept member is authorised
- **WHEN** a user holds a `costume_designer` role in an `active` block of Season S
- **THEN** the `SeasonPhotoAccessPolicy` authorises the user to access costume photos in Season S

#### Scenario: All three costume-dept roles are authorised
- **WHEN** a user holds any of `costume_designer`, `wardrobe_supervisor`, or `costume_assistant` in an `active` block of Season S
- **THEN** the policy authorises the user

#### Scenario: Non-costume role is rejected
- **WHEN** a user holds only a non-costume role (e.g. a generic block member without a costume-dept role) in an `active` block of Season S
- **THEN** the policy rejects the user with `403 Forbidden`

#### Scenario: Inactive membership is rejected
- **WHEN** a user's only block membership in Season S has a state other than `active` (e.g. `pending` invitation, `revoked`)
- **THEN** the policy rejects the user

#### Scenario: Cross-season access is rejected
- **WHEN** a user holds a costume-dept role in an `active` block of Season S1 and attempts to access costume photos in Season S2 (≠ S1)
- **THEN** the policy rejects the user

#### Scenario: Authorisation is checked on every byte transfer
- **WHEN** a client GETs `/costumes/{cid}/photos/{pid}/bytes`
- **THEN** the API validates the caller's JWT and invokes `SeasonPhotoAccessPolicy` on every such request before fetching any bytes from Garage
- **AND** a previously-authorised user whose membership has since lapsed is rejected on the next request

### Requirement: Between-blocks gap is a documented v1 limitation
The v1 derived authorisation SHALL revoke costume-photo access when a user's last active costume-dept block membership in a season ends. This means a costumer between contracts (left Block 3, not yet in Block 5 of the same season) loses photo access. This is an accepted v1 limitation: when a user is not on the production, they do not get confidential photos. The v2 `SeasonCrew` aggregate (see the evolution requirement below) is the explicit upgrade path for users who need persistent access (freelance designers, pre-production staff).

#### Scenario: Costumer between blocks loses access
- **WHEN** a user's only active costume-dept block membership in Season S ends (e.g. their block's membership state transitions away from `active`)
- **THEN** the next costume-photo access request in Season S is rejected with `403 Forbidden`

#### Scenario: Re-joining a block restores access
- **WHEN** the same user later joins an `active` block in Season S with a costume-dept role
- **THEN** subsequent costume-photo access requests in Season S are authorised again

### Requirement: v2 evolution path to a SeasonCrew aggregate (documented Non-Goal)
The system SHALL document (in `design.md` and ADR-019) the non-breaking v2 upgrade path from v1 derived authorisation to an additive `SeasonCrew` aggregate. The v2 rule SHALL be: `authorized = derived-from-active-block OR season-crew-grant`. The `SeasonPhotoAccessPolicy` trait method signature SHALL remain unchanged across the upgrade — only the impl changes. v1 SHALL NOT implement `SeasonCrew`; it is an explicit Non-Goal captured here. Triggers for the v2 upgrade SHALL include: users hitting the between-blocks gap (costumers doing pre-production outside a block; freelance designers), or an audit finding that long-term costume staff need persistent access.

#### Scenario: v2 upgrade is additive and non-breaking
- **WHEN** the v2 `SeasonCrew` aggregate is introduced
- **THEN** the v1 derived path still works (no data backfill required)
- **AND** the `SeasonPhotoAccessPolicy` gains an `OR season-crew-grant` branch
- **AND** the trait method signature is unchanged

#### Scenario: v2 does not block v1 rollout
- **WHEN** v1 ships without `SeasonCrew`
- **THEN** all v1 authorisation behaviour is fully functional via the derived path
- **AND** `SeasonCrew` is documented as a future evolution, not a v1 dependency
