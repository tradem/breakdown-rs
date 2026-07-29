<!--
  HANDOFF PROMPT — implement OpenSpec tasks 2.1–2.4 of change
  "add-cross-cutting-audit-history". The mechanical signature threading
  (actor: UserId on all 10 non-membership trait methods + 11 adapter impls)
  is already done. This document specifies the remaining substantive work so it
  can be completed with little effort. Execute the <tasks> in order.
-->
<handoff_prompt>

  <meta>
    <change>add-cross-cutting-audit-history</change>
    <scope>tasks 2.1, 2.2, 2.3, 2.4 only (do NOT touch tasks 1.x, 3.x–8.x)</scope>
    <co_author>hy3 (opencode-go)</co_author>
  </meta>

  <spdx_convention>
    Every Rust (`.rs`) file you CREATE or MODIFY in this work must carry the
    SPDX header with the co-author line. If the file already has:
        // SPDX-License-Identifier: AGPL-3.0
        // Copyright (C) 2024 Breakdown RS Contributors
    then ADD this third line (preserve order):
        // Co-authored by: hy3 (opencode-go)
    If the file has no SPDX header yet, prepend all three lines.
    Do NOT modify headers of files you do not otherwise change.
  </spdx_convention>

  <already_done>
    - `actor: UserId` first parameter threaded into all 10 non-membership
      `Commands` trait methods (crates/core/src/{season,block,episode,scene,
      scene_shoot,shooting_day,character,costume,costume_category,photo}/ports.rs)
      and all 11 adapter impls (crates/infra/src/event_store/command_adapters.rs).
      `MembershipCommands` already took `actor: UserId`, left as-is.
    - `UserId` import added to all 10 non-membership port files.
    - A multiline-corruption bug in `accept_invitation` was found and fixed
      (no duplicate `actor: UserId` param remains).
    - Repo is currently NON-COMPILING: adapters do not yet inject `EventMetadata`,
      handlers/constructors still call the old arity, and sagas still call the
      trait adapters (which now require `UserId`). Completing <tasks> fixes it.
  </already_done>

  <conventions>
    - Metadata type: `breakdown_core::shared::{EventMetadata, Provenance, SeriesId}`.
    - The `execute(...)` builder supports `.metadata(EventMetadata { .. })` (see
      existing `BlockMembership` usage in command_adapters.rs).
    - Repository impl types live in `crates/infra/src/queries/` (e.g.
      `SeasonRepositoryImpl`, `BlockRepositoryImpl`, `EpisodeRepositoryImpl`,
      `SceneRepositoryImpl`, `ShootingDayRepositoryImpl`, `CharacterRepositoryImpl`,
      `CostumeRepositoryImpl`, `CostumeCategoryRepositoryImpl`, `SceneShootRepositoryImpl`,
      `PhotoRepositoryImpl`). Their traits live in `breakdown_core::<m>::ports`
      (or `::repository`). Import both to call `find_by_id`.
    - NO string-interpolated SQL anywhere (static `&str` + `.bind()` only).
    - Keep the `provenance` discriminator honest: `Human` for authenticated users,
      `Saga(&'static str)` for named sagas, `System` for internal system paths.
  </conventions>

  <task id="2.1" title="MembershipCommandsImpl injects EventMetadata">
    File: crates/infra/src/event_store/command_adapters.rs
    - Remove `use breakdown_core::membership::MembershipMetadata;` (keep
      `use breakdown_core::membership::aggregate::BlockMembership;` and the
      commands/ports imports). Add
      `use breakdown_core::shared::{EventMetadata, Provenance, SeriesId};`
      (and keep the existing `use breakdown_core::shared::{AggregateVersion, ...}`).
    - Add a `block_repo: BlockRepositoryImpl` field to `MembershipCommandsImpl`,
      thread it through `new(cmd_service, block_repo)`.
    - In ALL six methods (invite, accept_invitation, grant_role, remove_member,
      leave_block, bootstrap_owner), replace:
        `.metadata(MembershipMetadata { actor: Some(actor) })`
      with:
        `.metadata(EventMetadata {
            actor: Some(actor),
            provenance: Provenance::Human,
            series_id: Some(self.block_repo.find_by_id(cmd.block_id.0).await?.series_id),
        })`
      Compute `series_id` once per method (hoist it into a `let series_id = ...;`
      line above the `let result = ...` for readability).
    - The `actor: UserId` param is already present; do NOT change signatures.
  </task>

  <task id="2.2" title="Non-membership adapters inject actor + Human + series_id">
    File: crates/infra/src/event_store/command_adapters.rs
    For each of the 10 non-membership adapters (Season, Block, Episode, Scene,
    ShootingDay, Character, Costume, CostumeCategory, Photo, SceneShoot):
    1. Add the repository impl field(s) listed in <per_adapter_resolution>.
    2. Thread them through `new(cmd_service, <repos>)`.
    3. In EVERY method, compute `let series_id = <resolution>;` (see table)
       and append `.metadata(EventMetadata { actor: Some(actor), provenance:
       Provenance::Human, series_id: Some(series_id) })` immediately BEFORE
       the existing `.await;` of the `Aggregate::execute(...)` builder.
       Preserve the existing `.expected_version(...)` call and the
       `map_executed`/`map_version_only` return.
    Note: `actor: UserId` is already the first param — do NOT add it again.
  </task>

  <per_adapter_resolution>
    <!-- series_id resolution per adapter; repo fields to add to the struct -->
    <adapter name="SeasonCommandsImpl">
      repos: SeasonRepositoryImpl
      create:  series_id = cmd.series_id;                                  // CreateSeason carries series_id
      rename:  series_id = self.season_repo.find_by_id(cmd.id).await?.series_id;
    </adapter>
    <adapter name="BlockCommandsImpl">
      repos: BlockRepositoryImpl
      create:  series_id = cmd.series_id;                                  // CreateBlock carries series_id
      update_time_span: series_id = self.block_repo.find_by_id(cmd.id).await?.series_id;
    </adapter>
    <adapter name="EpisodeCommandsImpl">
      repos: EpisodeRepositoryImpl
      create:  series_id = cmd.series_id;                                  // CreateEpisode carries series_id
      rename:  series_id = self.episode_repo.find_by_id(cmd.id).await?.series_id;
    </adapter>
    <adapter name="SceneCommandsImpl">
      repos: SceneRepositoryImpl, EpisodeRepositoryImpl
      create / schedule_on_shooting_day / unschedule_from_shooting_day:
              series_id = self.episode_repo.find_by_id(cmd.episode_id).await?.series_id;
      update_details / assign_character / remove_character:
              let scene = self.scene_repo.find_by_id(cmd.id).await?;
              series_id = self.episode_repo.find_by_id(scene.episode_id).await?.series_id;
    </adapter>
    <adapter name="ShootingDayCommandsImpl">
      repos: ShootingDayRepositoryImpl, EpisodeRepositoryImpl
      create:  series_id = self.episode_repo.find_by_id(cmd.episode_id).await?.series_id;
      rename/reschedule/reorder/archive/wrap:
              let sd = self.shooting_day_repo.find_by_id(cmd.id).await?;
              series_id = self.episode_repo.find_by_id(sd.episode_id).await?.series_id;
    </adapter>
    <adapter name="CharacterCommandsImpl">
      repos: CharacterRepositoryImpl, SeasonRepositoryImpl
      create:  series_id = self.season_repo.find_by_id(cmd.season_id).await?.series_id;
      update_measurements / update_contact_info:
              let ch = self.character_repo.find_by_id(cmd.id).await?;
              series_id = self.season_repo.find_by_id(ch.season_id).await?.series_id;
    </adapter>
    <adapter name="CostumeCommandsImpl">
      repos: CostumeRepositoryImpl, CharacterRepositoryImpl, SeasonRepositoryImpl
      create / assign_to_character / link_photo / unlink_photo:
              let ch = self.character_repo.find_by_id(cmd.character_id).await?;
              series_id = self.season_repo.find_by_id(ch.season_id).await?.series_id;
      update_notes / unassign / add_detail / remove_detail:
              let co = self.costume_repo.find_by_id(cmd.id).await?;
              let ch = self.character_repo.find_by_id(co.character_id).await?;
              series_id = self.season_repo.find_by_id(ch.season_id).await?.series_id;
    </adapter>
    <adapter name="CostumeCategoryCommandsImpl">
      repos: CostumeCategoryRepositoryImpl, SeasonRepositoryImpl
      create:  series_id = self.season_repo.find_by_id(cmd.season_id).await?.series_id;
      rename/reorder/archive:
              let cc = self.costume_category_repo.find_by_id(cmd.id).await?;
              series_id = self.season_repo.find_by_id(cc.season_id).await?.series_id;
    </adapter>
    <adapter name="PhotoCommandsImpl">
      repos: PhotoRepositoryImpl, CostumeRepositoryImpl, CharacterRepositoryImpl,
             SeasonRepositoryImpl, SceneShootRepositoryImpl, SceneRepositoryImpl,
             EpisodeRepositoryImpl
      ALL methods (upload / normalize_original / generate_variant /
      mark_variant_failed / delete): resolve from the command's binding:
          let binding = &cmd.binding;   // for upload; for others use the photo's
                                        // existing binding via photo_repo.find_by_id(cmd.id).await?.binding
          series_id = match binding {
              PhotoBinding::Costume(costume_id) => {
                  let ch = self.character_repo.find_by_id(
                      self.costume_repo.find_by_id(*costume_id).await?.character_id).await?;
                  self.season_repo.find_by_id(ch.season_id).await?.series_id
              }
              PhotoBinding::Continuity(scene_shoot_id) => {
                  let ss = self.scene_shoot_repo.find_by_id(*scene_shoot_id).await?;
                  let sc = self.scene_repo.find_by_id(ss.scene_id).await?;
                  self.episode_repo.find_by_id(sc.episode_id).await?.series_id
              }
          };
      NOTE: For normalize_original/generate_variant/mark_variant_failed/delete the
      saga refactor (task 2.3) moves their dispatch out of this adapter, but the
      trait still requires these methods to be implemented — keep them implemented
      with the resolution above (they will simply be unused by sagas).
      Consider extracting an async helper `resolve_series_id_for_binding(&self,
      &PhotoBinding) -> Result<SeriesId, DomainError>` on the adapter to avoid
      duplicating the match in all five methods.
    </adapter>
    <adapter name="SceneShootCommandsImpl">
      repos: SceneShootRepositoryImpl, SceneRepositoryImpl, EpisodeRepositoryImpl
      plan:    series_id = self.episode_repo.find_by_id(
                   self.scene_repo.find_by_id(cmd.scene_id).await?.episode_id).await?.series_id;
      replan/start/set_actual_order/finish/skip/add_note/update_note/remove_note/
      link_continuity_photo/unlink_continuity_photo:
              let ss = self.scene_shoot_repo.find_by_id(cmd.id).await?;
              series_id = self.episode_repo.find_by_id(
                   self.scene_repo.find_by_id(ss.scene_id).await?.episode_id).await?.series_id;
    </adapter>
  </per_adapter_resolution>

  <task id="2.3" title="Saga dispatch paths inject Provenance::Saga">
    Sagas currently call the `*CommandsImpl` trait adapters, which now require
    `actor: UserId` (a saga has none). Refactor each saga to dispatch via
    `Aggregate::execute(...)` DIRECTLY with `EventMetadata { actor: None,
    provenance: Provenance::Saga("<StableName>"), series_id: Some(series_id) }`.

    <saga name="season_seeding" file="crates/infra/src/sagas/season_seeding.rs">
      - Remove `use crate::event_store::CostumeCategoryCommandsImpl;` and the
        `commands: CostumeCategoryCommandsImpl` field / `CostumeCategoryCommandsImpl::new`.
      - Add a `season_repo: SeasonRepositoryImpl` to `SeasonSeedingSaga` /
        `seed_season` generic bound, and resolve `series_id =
        self.season_repo.find_by_id(season_id).await?.series_id;` (season_id is
        already in scope).
      - Replace `commands.create(cmd)` with:
          let id = cmd.id;
          let series_id = self.season_repo.find_by_id(season_id).await?.series_id;
          let result = CostumeCategoryAggregate::execute(&self.cmd_service, id, cmd)
              .expected_version(ExpectedVersion::Empty)
              .metadata(EventMetadata {
                  actor: None,
                  provenance: Provenance::Saga("SeasonSeedingSaga"),
                  series_id: Some(series_id),
              })
              .await;
          map_executed(id, result)?;   // propagate any error
      - Import `CostumeCategoryAggregate`, `EventMetadata`, `Provenance`,
        `SeriesId`, `SeasonRepository`/`SeasonRepositoryImpl`, and
        `map_executed` as needed.
    </saga>

    <saga name="photo_thumbnail" file="crates/infra/src/photo/sagas/thumbnail.rs">
      - Remove `use crate::event_store::PhotoCommandsImpl;` and the
        `commands: PhotoCommandsImpl` field.
      - Add the repos needed to resolve a photo's series_id from its binding
        (PhotoRepositoryImpl + Costume/Character/Season/SceneShoot/Scene/Episode
        repository impls), and a helper
        `async fn resolve_series_id(&self, photo_id: PhotoId) -> Result<SeriesId, DomainError>`
        that does `photo_repo.find_by_id(photo_id).await?.binding` then the same
        Costume/Continuity match as PhotoCommandsImpl.
      - Replace `self.commands.normalize_original(NormalizeOriginal { id, version, .. })`
        and `self.commands.generate_variant(GenerateVariant { id, variant, size_bytes, version })`
        with direct `PhotoAggregate::execute(&self.cmd_service, id, cmd)
        .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
        .metadata(EventMetadata { actor: None, provenance: Provenance::Saga("PhotoThumbnailSaga"), series_id: Some(self.resolve_series_id(id).await?) })
        .await;` then map the result (use `map_version_only(result)?` semantics /
        propagate the error).
    </saga>

    <saga name="photo_deletion" file="crates/infra/src/photo/sagas/deletion.rs">
      - Same refactor: remove `PhotoCommandsImpl`, add repos + `resolve_series_id`
        helper, replace `self.commands.delete(DeletePhoto { id, version })`
        with direct `PhotoAggregate::execute(...).metadata(EventMetadata {
        actor: None, provenance: Provenance::Saga("PhotoDeletionSaga"),
        series_id: Some(series_id) }).await`.
    </saga>

    <saga name="continuity_deletion" file="crates/infra/src/photo/sagas/continuity_deletion.rs">
      - Same refactor with `Provenance::Saga("ContinuityDeletionSaga")`.
    </saga>

    Verification: after this task, grep for `CommandsImpl` usage inside
    `crates/infra/src/**/sagas/` must return NOTHING (sagas no longer use the
    human trait adapters).
  </task>

  <task id="2.4" title="System-initiated dispatches use Provenance::System">
    Audit the codebase for any NON-saga, NON-human command dispatch that goes
    through `Aggregate::execute(...)` directly (not via the `*CommandsImpl`
    adapters and not via a saga). If any exist (e.g. a bootstrap/system path),
    ensure they inject `EventMetadata { actor: None, provenance: Provenance::System,
    series_id: <resolved or None> }`. In the current code the only direct
    `::execute` calls are inside command_adapters.rs (Human) and the refactored
    sagas (Saga); if no other direct dispatch exists, document that 2.4 is
    satisfied by absence and add a code comment near the supervisor/composition
    root stating system paths must use `Provenance::System`.
  </task>

  <call_site_updates title="API handlers pass current_user.sub">
    File: crates/api/src/handlers/mod.rs (and any other handler files)
    For every NON-membership command call of the form
        state.xxx_commands().method(cmd)
    or `ports.xxx_commands().method(cmd)` change it to
        state.xxx_commands().method(current_user.sub.clone(), cmd)
    - `current_user` is already in scope in handlers that use it; for handlers
      that currently don't take `current_user`, add it as a parameter (mirror how
      membership handlers already receive `current_user: CurrentUser`).
    - Membership handlers already pass `current_user.sub.clone()` as the first
      arg and need NO change.
    - Do NOT change the `actor` arg on membership calls.
    There are ~47 such call sites; use ast-grep or careful edits. Pattern:
        ast-grep run -p '$C($M).xxx_commands().$FN($CMD)' ...  (verify manually)
    is risky — prefer targeted edits and rely on `cargo check` to list every
    remaining arity mismatch.
  </call_site_updates>

  <constructor_wiring title="Wire repos into adapter constructors">
    Two construction sites must pass the new repo fields:
    1. crates/api/src/state.rs — `ProductionPorts::new` (and `AppState::new`)
       constructs each `*CommandsImpl::new(cmd_service, ...)`. Add the repos from
       <per_adapter_resolution> (they are already available as `PgPool`-backed
       `*RepositoryImpl::new(pool.clone())` or equivalent in that file).
    2. crates/test_support/src/lib.rs (or wherever test adapters are built) —
       update every `*CommandsImpl::new(cmd_service)` to include the repos. If
       the test harness builds repos separately, reuse them; otherwise construct
       the needed `*RepositoryImpl` there.
    Also update any other constructor call sites (grep for `CommandsImpl::new`).
  </constructor_wiring>

  <verification>
    1. `cargo check -p breakdown_core -p infra -p api -p test_support`
       must succeed with no arity / missing-field errors.
    2. `cargo test -p architecture_tests` — confirms no core→infra boundary
       violation was introduced by the metadata refactor.
    3. Confirm no saga still references `CommandsImpl` (grep above in 2.3).
    4. `cargo clippy ...` clean for changed crates (no unused imports after
       removing `MembershipMetadata`).
    5. Spot-check one handler + one saga path compiles and that `projection_audit`
       will receive `actor`/`provenance`/`series_id` (the projector work is a
       later task; just ensure the metadata is produced correctly here).
  </verification>

  <acceptance>
    - All 10 non-membership adapters + MembershipCommandsImpl inject
      `EventMetadata { actor: Some(actor), provenance: Human, series_id }`.
    - All 4 sagas dispatch via `Aggregate::execute` with `Provenance::Saga("<name>")`
      and `actor: None`.
    - `cargo check` + `cargo test -p architecture_tests` pass.
    - Every modified `.rs` file carries the `// Co-authored by: hy3 (opencode-go)`
      SPDX line.
  </acceptance>

</handoff_prompt>
