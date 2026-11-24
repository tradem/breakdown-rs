// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy4-flash-free (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: gemini-4-argon (opencode-go)

use uuid::Uuid;

use super::*;
use crate::scene::views::SceneView;
use crate::shared::{AggregateVersion, CostumeCategoryId, EpisodeId};
fn scene(number: u32) -> SceneView {
    SceneView {
        id: Uuid::now_v7(),
        episode_id: EpisodeId::new(),
        scene_number: Some(number),
        location: None,
        mood: None,
        is_schedule_set: false,
        summary: None,
        script_day: None,
        scene_score: None,
        synopsis_score: None,
        shooting_day_ids: Vec::new(),
        assigned_characters: Vec::new(),
        outfit_beats: Vec::new(),
        version: AggregateVersion::INITIAL,
        updated_at: jiff::Timestamp::UNIX_EPOCH,
        source: Some(SceneSource::Manual),
    }
}

#[test]
fn chunker_handles_numbered_and_unumbered_fuzzy_headings() {
    let chunks = extract_scenes(
        "1. INT. KITCHEN - DAY\nAlice enters.\n\nEXT. PARK - NIGHT\nA car waits.\n\nI/E. HOUSE - DAY\nRain.",
    );
    assert_eq!(chunks.len(), 3);
    assert_eq!(chunks[0].scene_number, Some(1));
    assert_eq!(chunks[0].text, "Alice enters.");
    assert_eq!(chunks[1].scene_number, None);
    assert_eq!(chunks[2].heading, "I/E. HOUSE - DAY");
}

#[test]
fn merge_returns_matched_and_both_unmatched_sets() {
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![
            ShootingScheduleRow {
                row_ref: "row-2".into(),
                scene_number: Some(2),
                ..Default::default()
            },
            ShootingScheduleRow {
                row_ref: "row-9".into(),
                scene_number: Some(9),
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    let merged = merge_schedule_to_scenes(
        &schedule,
        &[scene(1), scene(2)],
        &std::collections::HashMap::new(),
    );
    assert_eq!(merged.scenes[1].schedule_rows.len(), 1);
    assert_eq!(merged.unmatched_schedule_rows[0].row_ref, "row-9");
    assert_eq!(merged.unmatched_script_scenes.len(), 1);
    assert_eq!(merged.unmatched_script_scenes[0].scene_number, Some(1));
}

#[test]
fn planner_uses_update_for_a_previously_mapped_row() {
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![DraftScene {
            draft_ref: "scene-1".into(),
            scene_number: Some(1),
            summary: Some("revised".into()),
            ..Default::default()
        }],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let existing_id = Uuid::now_v7();
    let plan = plan_scene_apply(
        &preview,
        &[ApplyMapping {
            draft_ref: "scene-1".into(),
            decision: ApplyMappingDecision::Update {
                aggregate_id: existing_id,
                version: AggregateVersion::INITIAL,
            },
            outfit_decisions: Vec::new(),
        }],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .unwrap();
    assert_eq!(plan.scenes.len(), 1);
    assert!(
        matches!(&plan.scenes[0].scene, SceneApplyCommand::Update(command) if command.id == existing_id)
    );
}

#[test]
fn open_uncertainties_and_unmatched_rows_block_apply() {
    let script = ScriptContext {
        block_number: None,
        uncertainties: vec![Uncertainty {
            scene_index: 0,
            field: "location".into(),
            note: "illegible".into(),
            suggested_value: Some("Kitchen".into()),
            kind: UncertaintyKind::FieldAmbiguity,
            candidates: Vec::new(),
        }],
        ..Default::default()
    };
    assert!(matches!(
        ensure_script_applyable(&script, &[]),
        Err(ApplyGateError::OpenUncertainties(1))
    ));

    let merged = MergedPreview {
        unmatched_schedule_rows: vec![ShootingScheduleRow::default()],
        ..Default::default()
    };
    assert!(matches!(
        ensure_merge_applyable(&merged),
        Err(ApplyGateError::UnmatchedScheduleRows(1))
    ));

    // Remaining apply-gate branches: unmatched script scenes and a missing
    // mapping must also block the mutation.
    let unmatched_scenes = MergedPreview {
        unmatched_script_scenes: vec![scene(1)],
        ..Default::default()
    };
    assert!(matches!(
        ensure_merge_applyable(&unmatched_scenes),
        Err(ApplyGateError::UnmatchedScriptScenes(1))
    ));

    let unmapped = ScriptContext {
        scenes: vec![DraftScene::default()],
        ..Default::default()
    };
    assert!(matches!(
        plan_scene_apply(
            &unmapped,
            &[],
            EpisodeId::new(),
            None,
            AiImportJobId(Uuid::now_v7()),
            &ReviewerDecisions {
                continuity_selections: &[],
                episode_groups: &[],
                shooting_days: &[],
                acknowledged_uncertainties: &[],
                categories: &[],
            },
        ),
        Err(ApplyGateError::MissingMapping(_))
    ));
}

// ===========================================================================
// plan_scene_apply — figures and costumes of a draft row (group 2)
// ===========================================================================

fn plan_of(preview: &ScriptContext, decisions: &[ApplyMapping]) -> ScriptApplyPlan {
    plan_scene_apply(
        preview,
        decisions,
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan")
}

/// A `Create` decision for every row named `draft_refs`.
fn create_decisions(draft_refs: &[&str]) -> Vec<ApplyMapping> {
    draft_refs
        .iter()
        .map(|draft_ref| ApplyMapping {
            draft_ref: (*draft_ref).to_owned(),
            decision: ApplyMappingDecision::Create,
            outfit_decisions: Vec::new(),
        })
        .collect()
}

#[test]
fn planner_plans_the_figures_a_row_names() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN"), DraftCharacter::from("Leyla")],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    assert_eq!(
        plan.scenes[0].characters,
        vec![
            CharacterApplyPlan {
                ordinal: 0,
                name: "BEN".into(),
                identity: "ben".into(),
                category: Default::default(),
            },
            CharacterApplyPlan {
                ordinal: 1,
                name: "Leyla".into(),
                identity: "leyla".into(),
                category: Default::default(),
            },
        ]
    );
}

#[test]
fn planner_plans_no_figures_for_an_outline_row() {
    // The "Block 100 / Tag 1" case: a heading with characters named nowhere must
    // not invent a figure, and must not fail the apply either.
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. A/T - VOR KLINIK".into(),
            characters: vec![DraftCharacter::from("   ")],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. A/T - VOR KLINIK"]));
    assert!(
        plan.scenes[0].characters.is_empty(),
        "whitespace is not a figure: {:#?}",
        plan.scenes[0].characters
    );
    assert!(plan.scenes[0].outfits.is_empty());
}

#[test]
fn planner_plans_one_figure_per_name_even_when_a_row_names_it_twice() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN"), DraftCharacter::from("Ben ")],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    assert_eq!(plan.scenes[0].characters.len(), 1);
    assert_eq!(
        plan.scenes[0].characters[0].name, "BEN",
        "the first mention keeps the draft's own wording"
    );
}

#[test]
fn planner_keeps_the_drafts_name_form_verbatim_while_matching_case_insensitively() {
    // The two things the previous session could not verify: figures arrived from
    // the model partly in CAPS, partly mixed-case. The identity is only a
    // matching key; the name handed to `CreateCharacter` is the draft's own
    // text, untouched — the aggregate stores what the script wrote.
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from(" RENEE SANDERS ")],
            outfits: vec![costume(
                "renee sanders",
                "ölverschmierter Mechaniker-Overall",
                "ölverschmierten Mechaniker-Overall",
            )],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    assert_eq!(plan.scenes[0].characters[0].name, " RENEE SANDERS ");
    assert_eq!(plan.scenes[0].characters[0].identity, "renee sanders");
    // The differently-cased costume name resolved to the CAPS figure.
    assert_eq!(
        plan.scenes[0].outfits[0].character_identity,
        "renee sanders"
    );
}

#[test]
fn planner_plans_a_costume_bound_to_the_figure_of_the_same_row() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![costume("Ben", "Marineblau", "BEN in Marineblau")],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    assert_eq!(
        plan.scenes[0].outfits,
        vec![OutfitApplyPlan {
            continuation: None,
            beat_ordinal: 0,
            from_continuity_selection: false,
            ordinal: 0,
            character_identity: "ben".into(),
            character_name: "BEN".into(),
            name: "Marineblau".into(),
            notes: Some("Marineblau".into()),
            source_quote: "BEN in Marineblau".into(),
            pieces: Vec::new(),
        }]
    );
}

#[test]
fn planner_numbers_pieces_row_flat_across_the_rows_outfits() {
    // Two figures may wear the same garment (`OP-Schuhe`), so the piece mapping
    // key is the row-flat position, never a per-outfit one.
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN"), DraftCharacter::from("Renee")],
            outfits: vec![
                outfit_with_pieces("BEN", "in OP", &["OP-Kasack", "OP-Hose"]),
                outfit_with_pieces("Renee", "in OP", &["OP-Schuhe"]),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    let pieces: Vec<(usize, usize, &str)> = plan.scenes[0]
        .outfits
        .iter()
        .flat_map(|outfit| {
            outfit
                .pieces
                .iter()
                .map(move |piece| (piece.ordinal, piece.outfit_ordinal, piece.name.as_str()))
        })
        .collect();
    assert_eq!(
        pieces,
        vec![(0, 0, "OP-Kasack"), (1, 0, "OP-Hose"), (2, 1, "OP-Schuhe"),]
    );
}

#[test]
fn piece_ordinals_do_not_depend_on_which_outfits_the_reviewer_accepts() {
    // CodeRabbit (PR #744): the ordinal IS the idempotency key
    // `(preview_id, draft_ref, 'piece', ordinal)` and `derive_id` hashes it, so
    // numbering only the ACCEPTED outfits would renumber every later outfit
    // when a later apply (or a decision-less retry) accepts a previously
    // rejected one. That apply would then find the next outfit's confirmed
    // mapping row and bind the wrong piece to the look.
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN"), DraftCharacter::from("Renee")],
            outfits: vec![
                outfit_with_pieces("BEN", "in OP", &["OP-Kasack", "OP-Hose"]),
                outfit_with_pieces("Renee", "in OP", &["OP-Schuhe"]),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };

    let all_accepted = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    let baseline: Vec<(usize, String)> = all_accepted.scenes[0]
        .outfits
        .iter()
        .flat_map(|outfit| {
            outfit
                .pieces
                .iter()
                .map(|piece| (piece.ordinal, piece.name.clone()))
        })
        .collect();
    assert_eq!(
        baseline,
        vec![
            (0, "OP-Kasack".to_owned()),
            (1, "OP-Hose".to_owned()),
            (2, "OP-Schuhe".to_owned()),
        ]
    );

    // Same preview, outfit 0 rejected: outfit 1's piece MUST keep ordinal 2.
    let mut decisions = create_decisions(&["1. INT. OP"]);
    decisions[0].outfit_decisions = vec![OutfitDecision {
        ordinal: 0,
        accepted: false,
    }];
    let first = plan_of(&preview, &decisions);
    assert_eq!(first.scenes[0].outfits.len(), 1);
    let kept: Vec<(usize, String)> = first.scenes[0].outfits[0]
        .pieces
        .iter()
        .map(|piece| (piece.ordinal, piece.name.clone()))
        .collect();
    assert_eq!(
        kept,
        vec![(2, "OP-Schuhe".to_owned())],
        "the accepted outfit keeps the ordinal the preview assigns it"
    );

    // And the other way round: accepting everything afterwards must assign
    // outfit 0 exactly the ordinals the rejected plan left free.
    assert_eq!(baseline[0].0, 0);
    assert_eq!(baseline[1].0, 1);
}

#[test]
fn planner_folds_umlauts_when_matching_a_category_hint() {
    // `eq_ignore_ascii_case` left German vocabulary entries containing umlauts
    // unmatched (`Hüte`/`hüte`), silently creating the piece uncategorized.
    let hats = CostumeCategoryId::new();
    let preview = ScriptContext {
        block_number: None,
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![DraftOutfit {
                character_name: "BEN".into(),
                name: "OP".into(),
                notes: None,
                source_quote: "in OP".into(),
                origin: DraftOutfitOrigin::ExplicitQuote,
                provenance: None,
                pieces: vec![DraftPiece {
                    name: "OP-Haube".into(),
                    category_hint: Some("HÜTE".into()),
                    description: None,
                }],
            }],
            ..Default::default()
        }],
        ..Default::default()
    };
    let categories = vec![CategoryVocabularyEntry {
        name: "Hüte".into(),
        id: hats,
    }];
    let plan = plan_scene_apply(
        &preview,
        &create_decisions(&["1. INT. OP"]),
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &categories,
        },
    )
    .expect("plan");
    assert_eq!(
        plan.scenes[0].outfits[0].pieces[0].category_id,
        Some(hats),
        "a German category name must match regardless of its case"
    );
}

#[test]
fn planner_resolves_a_category_hint_case_insensitively() {
    let top = CostumeCategoryId::new();
    let preview = ScriptContext {
        block_number: None,
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![DraftOutfit {
                character_name: "BEN".into(),
                name: "OP".into(),
                notes: None,
                source_quote: "in OP".into(),
                origin: DraftOutfitOrigin::ExplicitQuote,
                provenance: None,
                pieces: vec![DraftPiece {
                    name: "OP-Kasack".into(),
                    category_hint: Some(" oberteil ".into()),
                    description: None,
                }],
            }],
            ..Default::default()
        }],
        ..Default::default()
    };
    let categories = vec![CategoryVocabularyEntry {
        name: "Oberteil".into(),
        id: top,
    }];
    let plan = plan_scene_apply(
        &preview,
        &create_decisions(&["1. INT. OP"]),
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &categories,
        },
    )
    .expect("plan");
    assert_eq!(plan.scenes[0].outfits[0].pieces[0].category_id, Some(top));
}

#[test]
fn planner_leaves_an_unknown_category_hint_uncategorized() {
    // An unknown hint is not an error: the piece is still applied, just without
    // a category (spec `ai-costume-extraction`).
    let preview = ScriptContext {
        block_number: None,
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![DraftOutfit {
                character_name: "BEN".into(),
                name: "OP".into(),
                notes: None,
                source_quote: "in OP".into(),
                origin: DraftOutfitOrigin::ExplicitQuote,
                provenance: None,
                pieces: vec![DraftPiece {
                    name: "OP-Haube".into(),
                    category_hint: Some("Kopfbedeckung".into()),
                    description: None,
                }],
            }],
            ..Default::default()
        }],
        ..Default::default()
    };
    let categories = vec![CategoryVocabularyEntry {
        name: "Oberteil".into(),
        id: CostumeCategoryId::new(),
    }];
    let plan = plan_scene_apply(
        &preview,
        &create_decisions(&["1. INT. OP"]),
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &categories,
        },
    )
    .expect("plan");
    let piece = &plan.scenes[0].outfits[0].pieces[0];
    assert_eq!(piece.category_id, None);
    assert_eq!(piece.category_hint.as_deref(), Some("Kopfbedeckung"));
}

#[test]
fn planner_keeps_an_outfit_without_pieces() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![costume("Ben", "Marineblau", "BEN in Marineblau")],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    assert_eq!(plan.scenes[0].outfits.len(), 1);
    assert!(plan.scenes[0].outfits[0].pieces.is_empty());
}

#[test]
fn two_costumes_of_one_figure_in_one_row_keep_distinct_ordinals() {
    // Design D4: without the ordinal both rows would resolve to one mapping row
    // and the second costume would silently never be created.
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![
                costume("Ben", "Marineblau", "BEN in Marineblau"),
                costume("Ben", "Silberkette", "Schmuck: Silberkette"),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    let ordinals: Vec<usize> = plan.scenes[0].outfits.iter().map(|c| c.ordinal).collect();
    assert_eq!(ordinals, vec![0, 1]);
}

#[test]
fn planner_reports_a_costume_whose_figure_the_row_does_not_plan() {
    // `verify_draft_outfits` normally rejects this at extraction; a preview that
    // skipped that step must still not produce an ownerless costume.
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![costume("Anna", "Mantel", "im Mantel")],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    assert!(plan.scenes[0].outfits.is_empty());
    assert_eq!(plan.unapplied_outfits.len(), 1);
    assert_eq!(
        plan.unapplied_outfits[0].reason,
        UnappliedOutfitReason::CharacterNotPlanned
    );
    assert_eq!(plan.unapplied_outfits[0].name, "Mantel");
}

#[test]
fn planner_skips_only_the_costume_rows_the_reviewer_rejected() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![
                costume("Ben", "Marineblau", "BEN in Marineblau"),
                costume("Ben", "Silberkette", "Schmuck: Silberkette"),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let mut decisions = create_decisions(&["1. INT. OP"]);
    decisions[0].outfit_decisions = vec![OutfitDecision {
        ordinal: 1,
        accepted: false,
    }];
    let plan = plan_of(&preview, &decisions);
    assert_eq!(plan.scenes[0].outfits.len(), 1);
    assert_eq!(plan.scenes[0].outfits[0].ordinal, 0);
    // Rejecting one costume is not a failure, so nothing is reported as
    // unapplied — the reviewer chose that outcome.
    assert!(plan.unapplied_outfits.is_empty());
}

#[test]
fn a_pre_rename_client_decision_is_read_as_an_outfit_decision() {
    // The pre-change client sent the same item shape under the old key; reading
    // it as "no decisions" would apply the outfit the reviewer refused.
    let mapping: ApplyMapping = serde_json::from_str(
        r#"{"draft_ref":"1. INT. OP","decision":"Create","costume_decisions":[{"ordinal":0,"accepted":false}]}"#,
    )
    .expect("a pre-rename request must deserialize");
    assert_eq!(mapping.outfit_decisions.len(), 1);
    assert!(!mapping.outfit_accepted(0), "the rejection must survive");
}

#[test]
fn figure_mapping_refs_are_unique_per_identity_and_cannot_collide_with_a_scene_row() {
    // The identity key carries the prefix that keeps it out of the scene key
    // space, and two spellings of one figure collapse onto one row.
    assert_eq!(
        character_mapping_ref(&character_identity("BEN")),
        character_mapping_ref(&character_identity(" Ben "))
    );
    assert_eq!(
        character_mapping_ref("ben"),
        format!("{CHARACTER_REF_PREFIX}ben")
    );
    // A scene reference starts with its ordinal, never with the prefix.
    assert!(!stable_draft_ref(1, "BEN", 0).starts_with(CHARACTER_REF_PREFIX));
}

#[test]
fn character_identity_folds_case_and_inner_whitespace_only() {
    assert_eq!(character_identity("  ANNA\tMARIA "), "anna maria");
    assert_eq!(character_identity("Renée"), "renée");
    // Deliberately NOT a fuzzy match: one letter apart stays two figures.
    assert_ne!(
        character_identity("Ann Maria"),
        character_identity("Anna Maria")
    );
}

#[test]
fn merge_from_input_blocks_on_empty_scenes() {
    let input = MergeInput {
        schedule: ShootingSchedule::default(),
        scenes: Vec::new(),
        episode_numbers: std::collections::HashMap::new(),
    };
    assert!(matches!(
        merge_from_input(&input),
        Err(DomainError::Conflict { .. })
    ));
}

#[test]
fn merge_from_input_joins_schedule_to_scenes() {
    let input = MergeInput {
        schedule: ShootingSchedule {
            block_id: None,
            rows: vec![ShootingScheduleRow {
                row_ref: "row-1".into(),
                scene_number: Some(1),
                ..Default::default()
            }],
            ..Default::default()
        },
        scenes: vec![scene(1), scene(2)],
        episode_numbers: std::collections::HashMap::new(),
    };
    let merged = merge_from_input(&input).unwrap();
    assert_eq!(merged.scenes[0].schedule_rows.len(), 1);
    assert_eq!(merged.unmatched_schedule_rows.len(), 0);
    assert_eq!(merged.unmatched_script_scenes.len(), 1);
    assert_eq!(merged.unmatched_script_scenes[0].scene_number, Some(2));
}

// ===========================================================================
// P3.5 — SceneChunk::extract_scenes (kills return vec![])
// ===========================================================================

#[test]
fn extract_scenes_returns_non_empty_for_valid_script() {
    let chunks = extract_scenes("INT. ROOM - DAY\nHello.");
    assert!(!chunks.is_empty(), "extract_scenes should return chunks");
}

#[test]
fn extract_scenes_returns_empty_for_no_headings() {
    let chunks = extract_scenes("Just some text without headings.");
    assert!(chunks.is_empty(), "no headings means no chunks");
}

// ===========================================================================
// verify_draft_outfits — grounding + attribution (server-side)
// ===========================================================================

fn costume(char_name: &str, description: &str, quote: &str) -> DraftOutfit {
    DraftOutfit {
        character_name: char_name.to_owned(),
        name: description.to_owned(),
        notes: Some(description.to_owned()),
        source_quote: quote.to_owned(),
        origin: DraftOutfitOrigin::ExplicitQuote,
        provenance: None,
        pieces: Vec::new(),
    }
}

/// An outfit with constituent pieces, as the prompt derives them from a
/// shorthand (`in OP` -> `OP-Kasack`, `OP-Hose`).
fn outfit_with_pieces(char_name: &str, quote: &str, pieces: &[&str]) -> DraftOutfit {
    DraftOutfit {
        character_name: char_name.to_owned(),
        name: format!("{char_name} in OP"),
        notes: None,
        source_quote: quote.to_owned(),
        origin: DraftOutfitOrigin::ExplicitQuote,
        provenance: None,
        pieces: pieces
            .iter()
            .map(|name| DraftPiece {
                name: (*name).to_owned(),
                category_hint: None,
                description: None,
            })
            .collect(),
    }
}

const CHUNK: &str = "Renee Sanders (39) steigt aus dem Auto, trägt einen leicht \
ölverschmierten Mechaniker-Overall. BEN wartet im Mantel.";

#[test]
fn grounded_costume_for_a_listed_character_is_kept() {
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("Renee Sanders")],
        outfits: vec![costume(
            "Renee Sanders",
            "ölverschmierter Mechaniker-Overall",
            "ölverschmierten Mechaniker-Overall",
        )],
        ..DraftScene::default()
    };
    scene.outfits[0].source_quote = "ölverschmierten Mechaniker-Overall".to_owned();
    let rejected = verify_draft_outfits(&mut scene, CHUNK);
    assert!(rejected.is_empty(), "expected no rejects, got {rejected:?}");
    assert_eq!(scene.outfits.len(), 1, "the grounded costume must survive");
}

#[test]
fn costume_whose_quote_is_absent_from_the_chunk_is_dropped() {
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("Renee Sanders")],
        outfits: vec![costume(
            "Renee Sanders",
            "Seidenkleid",
            "trägt ein langes Seidenkleid aus Seide",
        )],
        ..DraftScene::default()
    };
    let rejected = verify_draft_outfits(&mut scene, CHUNK);
    assert!(
        scene.outfits.is_empty(),
        "ungrounded costume must not survive"
    );
    assert_eq!(rejected.len(), 1);
    assert!(matches!(
        rejected[0].reason,
        RejectedOutfitReason::UngroundedQuote
    ));
}

#[test]
fn grounded_outfit_keeps_context_derived_pieces() {
    // Design D1: the block names only the look (`in OP`), so its garments are
    // derived. Grounding the parent outfit is what keeps them.
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("Renee Sanders")],
        outfits: vec![outfit_with_pieces(
            "Renee Sanders",
            "ölverschmierten Mechaniker-Overall",
            &["Overall", "Gummistiefel"],
        )],
        ..DraftScene::default()
    };
    let rejected = verify_draft_outfits(&mut scene, CHUNK);
    assert!(rejected.is_empty(), "expected no rejects, got {rejected:?}");
    assert_eq!(scene.outfits.len(), 1);
    let pieces: Vec<&str> = scene.outfits[0]
        .pieces
        .iter()
        .map(|piece| piece.name.as_str())
        .collect();
    assert_eq!(pieces, vec!["Overall", "Gummistiefel"]);
}

#[test]
fn a_dropped_outfit_takes_its_derived_pieces_with_it() {
    // Pieces exist only as part of the look; an ungrounded look must not leave
    // orphan garments in the preview.
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("Renee Sanders")],
        outfits: vec![outfit_with_pieces(
            "Renee Sanders",
            "im gelben Overall",
            &["Overall", "Gummistiefel"],
        )],
        ..DraftScene::default()
    };
    let rejected = verify_draft_outfits(&mut scene, CHUNK);
    assert!(scene.outfits.is_empty());
    assert_eq!(rejected.len(), 1);
    assert_eq!(rejected[0].name, "Renee Sanders in OP");
}

#[test]
fn costume_for_an_unlisted_character_is_dropped() {
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("Renee Sanders")],
        outfits: vec![costume("Unbekannt", "Mantel", "im Mantel")],
        ..DraftScene::default()
    };
    let rejected = verify_draft_outfits(&mut scene, CHUNK);
    assert!(
        scene.outfits.is_empty(),
        "costume without its figure must not survive"
    );
    assert_eq!(rejected.len(), 1);
    assert!(matches!(
        rejected[0].reason,
        RejectedOutfitReason::UnlistedCharacter
    ));
}

#[test]
fn costume_with_an_empty_quote_is_dropped() {
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("Renee Sanders")],
        outfits: vec![costume("Renee Sanders", "Mantel", "   ")],
        ..DraftScene::default()
    };
    let rejected = verify_draft_outfits(&mut scene, CHUNK);
    assert!(scene.outfits.is_empty());
    assert_eq!(rejected.len(), 1);
}

#[test]
fn character_matching_ignores_case_and_surrounding_space() {
    // Models are inconsistent about casing ("BEN" vs "Ben"); the script's own
    // name is kept in the costume, only the MATCH is normalised.
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("BEN")],
        outfits: vec![costume(" ben ", "Mantel", "im Mantel")],
        ..DraftScene::default()
    };
    let rejected = verify_draft_outfits(&mut scene, CHUNK);
    assert!(rejected.is_empty(), "casing must not reject a costume");
    assert_eq!(scene.outfits.len(), 1);
    assert_eq!(scene.outfits[0].character_name, " ben ");
}

#[test]
fn a_quote_that_only_differs_in_line_wrapping_is_still_grounded() {
    // A screenplay wraps action over lines; the model quotes it reflowed. The
    // words are the document's, so this is grounded — and treating it as a
    // hallucination would reject legitimate costumes on every typeset script.
    let wrapped = "Renee steigt aus.\n  einem\n\nAuto, trägt einen leicht ölverschmierten\nMechaniker-Overall.";
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("Renee")],
        outfits: vec![costume(
            "RENEE",
            "Overall",
            "trägt einen  leicht ölverschmierten Mechaniker-Overall",
        )],
        ..Default::default()
    };
    let rejected = verify_draft_outfits(&mut scene, wrapped);
    assert!(
        rejected.is_empty(),
        "line breaks must not make a real quote ungrounded: {rejected:?}"
    );
    // A word the text does not contain is still rejected.
    scene.outfits = vec![costume("RENEE", "Kleid", "trägt ein langes Seidenkleid")];
    assert_eq!(
        verify_draft_outfits(&mut scene, wrapped).len(),
        1,
        "grounding must not become fuzzy matching"
    );
}

#[test]
fn an_acknowledged_blocking_uncertainty_resolves_the_gate() {
    // Issue #663: the reviewer acknowledges the ambiguity in the apply
    // request, so the gate counts only the *unacknowledged* blockers.
    let preview = ScriptContext {
        block_number: None,
        uncertainties: vec![
            Uncertainty {
                scene_index: 1,
                field: "location".into(),
                note: "illegible".into(),
                suggested_value: None,
                kind: UncertaintyKind::FieldAmbiguity,
                candidates: Vec::new(),
            },
            Uncertainty {
                scene_index: 2,
                field: "mood".into(),
                note: "two readings".into(),
                suggested_value: None,
                kind: UncertaintyKind::FieldAmbiguity,
                candidates: Vec::new(),
            },
        ],
        ..Default::default()
    };
    // Both acknowledged: the gate opens.
    assert!(
        ensure_script_applyable(
            &preview,
            &[
                UncertaintyAcknowledgement {
                    scene_index: 1,
                    field: "location".into(),
                },
                UncertaintyAcknowledgement {
                    scene_index: 2,
                    field: "mood".into(),
                },
            ]
        )
        .is_ok()
    );
    // One acknowledged: exactly the other one still blocks.
    assert!(matches!(
        ensure_script_applyable(
            &preview,
            &[UncertaintyAcknowledgement {
                scene_index: 1,
                field: "location".into(),
            }],
        ),
        Err(ApplyGateError::OpenUncertainties(1))
    ));
    // An acknowledgement that matches nothing (wrong scene or wrong field)
    // resolves nothing — the API edge rejects it, the gate must not honor it.
    assert!(matches!(
        ensure_script_applyable(
            &preview,
            &[
                UncertaintyAcknowledgement {
                    scene_index: 1,
                    field: "mood".into(),
                },
                UncertaintyAcknowledgement {
                    scene_index: 9,
                    field: "location".into(),
                },
            ],
        ),
        Err(ApplyGateError::OpenUncertainties(2))
    ));
}

#[test]
fn only_a_field_ambiguity_blocks_the_apply() {
    // Design D8: a server-dropped row is reported, but must not make the whole
    // preview unappliable — one unverifiable costume may not cost the reviewer a
    // paid re-import of an 85-chunk document.
    let dropped = ScriptContext {
        block_number: None,
        uncertainties: vec![Uncertainty {
            scene_index: 3,
            field: "costumes".into(),
            note: "ungrounded quote".into(),
            suggested_value: None,
            kind: UncertaintyKind::DroppedRow,
            candidates: Vec::new(),
        }],
        ..Default::default()
    };
    assert!(ensure_script_applyable(&dropped, &[]).is_ok());

    let mut blocking = dropped.clone();
    blocking.uncertainties.push(Uncertainty {
        scene_index: 1,
        field: "location".into(),
        note: "illegible".into(),
        suggested_value: None,
        kind: UncertaintyKind::FieldAmbiguity,
        candidates: Vec::new(),
    });
    assert!(matches!(
        ensure_script_applyable(&blocking, &[]),
        Err(ApplyGateError::OpenUncertainties(1))
    ));
}

#[test]
fn an_old_uncertainty_still_blocks_the_apply() {
    // Wire compatibility decides this: a preview stored before `kind` existed
    // deserialises to the blocking kind, so no import becomes newly appliable by
    // re-reading an old blob.
    let json = r#"{"scene_index":1,"field":"mood","note":"unclear","suggested_value":null}"#;
    let uncertainty: Uncertainty = serde_json::from_str(json).expect("old uncertainty parses");
    assert_eq!(uncertainty.kind, UncertaintyKind::FieldAmbiguity);
    assert!(uncertainty.kind.blocks_apply());
}

#[test]
fn a_scene_without_costumes_yields_no_rejects() {
    // The outline case ("Block 100 / Tag 1"): no costuming is a correct result.
    let mut scene = DraftScene {
        characters: vec![],
        outfits: vec![],
        ..DraftScene::default()
    };
    assert!(verify_draft_outfits(&mut scene, CHUNK).is_empty());
    assert!(scene.outfits.is_empty());
}

#[test]
fn costumes_field_defaults_for_previews_stored_before_it_existed() {
    // Wire compatibility: a stored preview JSON without `costumes` must still
    // deserialise (the field is `#[serde(default)]`).
    let json = r#"{"draft_ref":"1. INT. KITCHEN","characters":["ANNA"]}"#;
    let scene: DraftScene = serde_json::from_str(json).expect("old preview must parse");
    assert!(scene.outfits.is_empty());
    assert_eq!(scene.characters, vec![DraftCharacter::from("ANNA")]);
}

#[test]
fn a_typed_characters_list_roundtrips_the_extracted_category() {
    // Issue #677: the extraction's classification survives the serde
    // roundtrip, and the grounded default applies when the field is absent.
    let scene = DraftScene {
        draft_ref: "1. INT. OP".to_owned(),
        characters: vec![
            DraftCharacter {
                name: "BEN".to_owned(),
                category: CharacterCategory::Guest,
            },
            DraftCharacter {
                name: "STATIST".to_owned(),
                category: CharacterCategory::Extra,
            },
        ],
        ..Default::default()
    };
    let json = serde_json::to_string(&scene).expect("preview serializes");
    let roundtripped: DraftScene = serde_json::from_str(&json).expect("roundtrip parses");
    assert_eq!(roundtripped, scene);

    // A typed entry WITHOUT the category field keeps the grounded default —
    // the model omitting the field must never invent a classification.
    let json = r#"{"draft_ref":"x","characters":[{"name":"ANNA"}]}"#;
    let scene: DraftScene = serde_json::from_str(json).expect("typed entry without category");
    assert_eq!(scene.characters[0].category, CharacterCategory::MainCast);
}

#[test]
fn a_later_non_default_category_corrects_an_earlier_default() {
    // CodeRabbit #692: the cast section is document-global evidence. A row
    // that names the figure BEFORE the Gastrollen section carries only the
    // grounded default; the later typed signal must win — first-wins alone
    // would freeze `main_cast` for a guest.
    let preview = ScriptContext {
        scenes: vec![
            DraftScene {
                draft_ref: "1. INT. OP".to_owned(),
                characters: vec![DraftCharacter::from("BEN")],
                ..Default::default()
            },
            DraftScene {
                draft_ref: "2. INT. KELLER".to_owned(),
                characters: vec![DraftCharacter {
                    name: "Ben".to_owned(),
                    category: CharacterCategory::Guest,
                }],
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    let plan = plan_of(
        &preview,
        &create_decisions(&["1. INT. OP", "2. INT. KELLER"]),
    );
    let planed = &plan.scenes[0].characters[0];
    assert_eq!(planed.identity, "ben");
    assert_eq!(
        planed.category,
        CharacterCategory::Guest,
        "the later non-default classification must correct the earlier default"
    );
}

#[test]
fn differing_non_default_categories_keep_the_first_signal() {
    // Genuine conflict (guest vs extra): deterministic first-non-default
    // wins; the reviewer corrects it in the Cast screen (#678).
    let preview = ScriptContext {
        block_number: None,
        scenes: vec![
            DraftScene {
                draft_ref: "1. INT. OP".to_owned(),
                characters: vec![DraftCharacter {
                    name: "BEN".to_owned(),
                    category: CharacterCategory::Guest,
                }],
                ..Default::default()
            },
            DraftScene {
                draft_ref: "2. INT. KELLER".to_owned(),
                characters: vec![DraftCharacter {
                    name: "Ben".to_owned(),
                    category: CharacterCategory::Extra,
                }],
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    let plan = plan_of(
        &preview,
        &create_decisions(&["1. INT. OP", "2. INT. KELLER"]),
    );
    assert_eq!(
        plan.scenes[0].characters[0].category,
        CharacterCategory::Guest,
        "among non-default signals the first one wins"
    );
}

#[test]
fn the_apply_plan_carries_the_extracted_category() {
    let preview = ScriptContext {
        block_number: None,
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".to_owned(),
            characters: vec![
                DraftCharacter::from("BEN"),
                DraftCharacter {
                    name: "KELLNER".to_owned(),
                    category: CharacterCategory::Extra,
                },
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    let categories: Vec<_> = plan.scenes[0]
        .characters
        .iter()
        .map(|character| character.category)
        .collect();
    assert_eq!(
        categories,
        vec![CharacterCategory::MainCast, CharacterCategory::Extra],
        "the plan carries each figure's extracted classification verbatim"
    );
}

#[test]
fn a_document_global_category_conflict_surfaces_as_a_blocking_uncertainty() {
    // Issue #695: the same figure named under two cast sections with differing
    // non-default categories — the plan reconciles (first non-default wins);
    // the scan must surface the conflict instead of hiding it.
    let preview = ScriptContext {
        scenes: vec![
            DraftScene {
                draft_ref: "1. INT. OP".to_owned(),
                characters: vec![DraftCharacter::from("BEN")],
                ..Default::default()
            },
            DraftScene {
                draft_ref: "2. INT. KELLER".to_owned(),
                characters: vec![DraftCharacter {
                    name: "BEN".to_owned(),
                    category: CharacterCategory::Guest,
                }],
                ..Default::default()
            },
            DraftScene {
                draft_ref: "3. EXT. HOF".to_owned(),
                characters: vec![DraftCharacter {
                    name: "Ben".to_owned(),
                    category: CharacterCategory::Extra,
                }],
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    let uncertainties = category_conflict_uncertainties(&preview);
    assert_eq!(uncertainties.len(), 1, "one conflict per identity");
    let uncertainty = &uncertainties[0];
    assert_eq!(
        uncertainty.scene_index, 0,
        "attached to the first appearance"
    );
    assert_eq!(uncertainty.field, UNCERTAINTY_FIELD_CHARACTERS);
    assert_eq!(uncertainty.kind, UncertaintyKind::FieldAmbiguity);
    assert_eq!(
        uncertainty.suggested_value.as_deref(),
        Some("guest"),
        "display-only suggestion: the first non-default signal, what the plan picks"
    );
    assert!(
        uncertainty.note.contains("ben") && uncertainty.note.contains("guest vs extra"),
        "note names the identity and both signals, got: {}",
        uncertainty.note
    );
}

#[test]
fn agreeing_and_default_corrected_signals_do_not_surface_a_conflict() {
    // BEN: main_cast (default) then guest — the non-default signal corrects
    // the default, no conflict. LENA: guest twice — agreeing, no conflict.
    let preview = ScriptContext {
        block_number: None,
        scenes: vec![
            DraftScene {
                draft_ref: "1. INT. OP".to_owned(),
                characters: vec![
                    DraftCharacter::from("BEN"),
                    DraftCharacter {
                        name: "LENA".to_owned(),
                        category: CharacterCategory::Guest,
                    },
                ],
                ..Default::default()
            },
            DraftScene {
                draft_ref: "2. INT. KELLER".to_owned(),
                characters: vec![
                    DraftCharacter {
                        name: "Ben".to_owned(),
                        category: CharacterCategory::Guest,
                    },
                    DraftCharacter {
                        name: "Lena".to_owned(),
                        category: CharacterCategory::Guest,
                    },
                ],
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    assert!(
        category_conflict_uncertainties(&preview).is_empty(),
        "agreement and default-correction are not conflicts"
    );
}

#[test]
fn a_conflict_uncertainty_blocks_the_apply_until_acknowledged() {
    let mut preview = ScriptContext {
        block_number: None,
        scenes: vec![
            DraftScene {
                draft_ref: "1. INT. OP".to_owned(),
                characters: vec![DraftCharacter {
                    name: "BEN".to_owned(),
                    category: CharacterCategory::Guest,
                }],
                ..Default::default()
            },
            DraftScene {
                draft_ref: "2. INT. KELLER".to_owned(),
                characters: vec![DraftCharacter {
                    name: "Ben".to_owned(),
                    category: CharacterCategory::Extra,
                }],
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    preview.uncertainties = category_conflict_uncertainties(&preview);
    assert!(
        ensure_script_applyable(&preview, &[]).is_err(),
        "an unacknowledged conflict blocks the apply"
    );
    let acknowledged = [UncertaintyAcknowledgement {
        scene_index: 0,
        field: UNCERTAINTY_FIELD_CHARACTERS.to_owned(),
    }];
    assert!(
        ensure_script_applyable(&preview, &acknowledged).is_ok(),
        "the #663 acknowledgement resolves the conflict"
    );
}

// ===========================================================================
// stable_draft_ref — server-owned preview identity
// ===========================================================================

#[test]
fn draft_ref_is_built_from_the_document_heading() {
    assert_eq!(
        stable_draft_ref(7, "I/T - WOHNUNG ZOE", 0),
        "7. I/T - WOHNUNG ZOE"
    );
}

#[test]
fn draft_ref_trims_the_heading_and_numbers_split_scenes() {
    // A model that splits one chunk into several scenes must not produce
    // identical references — the apply lookup would then resolve every row to
    // the same decision.
    assert_eq!(stable_draft_ref(1, "  I/N - OP  ", 0), "1. I/N - OP");
    assert_eq!(stable_draft_ref(1, "  I/N - OP  ", 1), "1. I/N - OP (2)");
    assert_eq!(stable_draft_ref(1, "  I/N - OP  ", 2), "1. I/N - OP (3)");
}

#[test]
fn draft_refs_stay_unique_for_repeated_headings() {
    // The same heading occurs many times in a production script (e.g.
    // "A/T - VOR NOTAUFNAHME / ANKUNFT"); the global ordinal keeps the
    // references apart — which a heading-only reference could not.
    let refs: Vec<String> = (1..=4)
        .map(|n| stable_draft_ref(n, "A/T - VOR NOTAUFNAHME / ANKUNFT", 0))
        .collect();
    let unique: std::collections::HashSet<&String> = refs.iter().collect();
    assert_eq!(unique.len(), refs.len(), "references must be unique");
}

// ===========================================================================
// German (DFF / TV production) scene headings
// ===========================================================================

#[test]
fn extract_scenes_reads_german_short_form_headings() {
    // Real-world sample from a German series production script (ARD):
    // "I/T" = innen/Tag, "A/T" = außen/Tag, "I/N" = innen/Nacht.
    let document = "\
Block 100
A/T - VOR KLINIKUM / EINGANG / HAUPTEINGANG
Tag 1
ELIAS Baehr wartet.
I/T - WOHNUNG LEYLA UND BEN
Ein Dialog.
I/N - OP / KREISSSAAL
Nachtszene.
";
    let chunks = extract_scenes(document);
    assert_eq!(
        chunks.len(),
        3,
        "all three German headings must split the document, got {chunks:#?}"
    );
    assert_eq!(
        chunks[0].heading,
        "A/T - VOR KLINIKUM / EINGANG / HAUPTEINGANG"
    );
    assert_eq!(chunks[1].heading, "I/T - WOHNUNG LEYLA UND BEN");
    assert_eq!(chunks[2].heading, "I/N - OP / KREISSSAAL");
}

#[test]
fn german_headings_accept_number_prefix_and_case_variants() {
    for line in [
        "12 I/T - WOHNUNG",
        "12.I/T-WOHNUNG",
        "i/t - wohnung",
        "A/N. STRASSE",
        "INNENAUFNAHME WOHNUNG - TAG",
        "AUSSENAUFNAHME STRASSE - NACHT",
    ] {
        assert!(
            is_scene_heading(line),
            "expected {line:?} to be recognised as a German scene heading"
        );
    }
}

#[test]
fn german_headings_survive_word_pdf_export_artifacts() {
    // Issue #581 user report: a Word→PDF production script extracts via
    // `pdftotext` with invisible look-alikes — non-breaking/narrow spaces
    // after the leading scene number and en/em dashes instead of `-`. The
    // ASCII-strict detector rejected every heading and the whole import
    // died with "script did not contain an INT./EXT. scene heading". The
    // user's verbatim headings first, then the artifact variants.
    for line in [
        "1 I/T - KLINIKUM / OP / Waschraum",
        "2 I/T - NOTAUFNHAME  / SCHOCKBOX",
        "3 A/I/T - ERFURT / STRASSE + KLINIKUM / EINGANG + EMPFANG + FLUR VOR OP",
        // NBSP (U+00A0), narrow NBSP (U+202F) and figure space (U+2007)
        // after the number; tab as the separator.
        "1\u{00A0}I/T - KLINIKUM / OP",
        "12\u{202F}I/N - OP / KREISSAAL",
        "5\u{2007}A/T - STRASSE",
        "7\tI/T - WOHNUNG",
        // En dash (U+2013), em dash (U+2014), non-breaking hyphen (U+2011)
        // and minus sign (U+2212) as the time-token terminator.
        "4 I/T \u{2013} KÜCHE",
        "6 A/I/T \u{2014} ERFURT / STRASSE",
        "8 A/I/T \u{2011} KLINIKUM",
        "9 I/N \u{2212} LABOR",
    ] {
        assert!(
            is_scene_heading(line),
            "expected {line:?} to survive export artifacts as a German scene heading"
        );
    }
}

#[test]
fn extract_scenes_parses_scene_numbers_through_export_artifacts() {
    // The chunk must carry the document's leading number even when the line
    // arrives with NBSP/en-dash artifacts — the worker backfills
    // `DraftScene.scene_number` from it when the model omits the field.
    let document = "1\u{00A0}I/T \u{2013} KLINIKUM / OP\n\nOP-Saal,\nlautlose Heizung.\n\n2 I/T - NOTAUFNAHME / SCHOCKBOX\n\nEin Monitor pfeift.\n";
    let chunks = extract_scenes(document);
    assert_eq!(
        chunks.len(),
        2,
        "both artifact headings must split, got {chunks:?}"
    );
    assert_eq!(chunks[0].scene_number, Some(1));
    // The stored heading stays the document's verbatim bytes (grounding
    // identity) — normalization is detection-only.
    assert_eq!(chunks[0].heading, "1\u{00A0}I/T \u{2013} KLINIKUM / OP");
    assert_eq!(chunks[1].scene_number, Some(2));
}

#[test]
fn export_artifact_normalization_does_not_swallow_prose() {
    // The guard rails must hold on the normalized copy too: a number plus
    // NBSP in front of lowercase prose is still prose, and an en dash inside
    // a sentence does not make it a heading.
    for line in [
        "1\u{00A0}Innen brennt noch Licht.",
        "3\tAussen am Gang wartet Renke.",
        "I/TAXI \u{2013} FAHRT",
    ] {
        assert!(
            !is_scene_heading(line),
            "must NOT treat {line:?} as a scene heading"
        );
    }
}

#[test]
fn german_detection_does_not_swallow_ordinary_prose() {
    // The guard rails: a bare `I` or `A` is a character/dialogue line, a long
    // "time token" is a word that merely starts with T/N/AB, and a word glued to
    // the token is not a heading.
    for line in [
        "ICH",
        "A",
        "ANDERS",
        "INT",
        "I/TAXI FAHRT",
        "EIN TAG SPAETER",
        "Abend zu Hause",
        // The spelled-out form separated by a SPACE is the dangerous one: the
        // line is upper-cased before the prefixes are compared, so without the
        // place-name-caps requirement a sentence folds onto `INNEN ` / `AUSSEN `
        // and the document is split in the middle of prose.
        "Innen brennt noch Licht.",
        "Aussen am Gang wartet Renke.",
        "innen wohnung",
    ] {
        assert!(
            !is_scene_heading(line),
            "must NOT treat {line:?} as a scene heading"
        );
    }
}

#[test]
fn german_space_form_headings_are_still_detected() {
    // The other half of the same rule: a production script writes the slug line
    // with the place name in caps, and that must keep splitting.
    for line in [
        "INNEN WOHNUNG - TAG",
        "AUSSEN HOF - NACHT",
        "3 INNEN KUECHE - TAG",
    ] {
        assert!(
            is_scene_heading(line),
            "expected {line:?} to be recognised as a German scene heading"
        );
    }
}

#[test]
fn prose_that_starts_like_a_german_heading_does_not_split_the_document() {
    // Regression for the cost of a false split: one chunk boundary in the wrong
    // place means one extra PAID LLM call and shifts every later
    // `stable_draft_ref` ordinal.
    let document = "\
AUSSEN HOF - TAG
Tag 1
Innen brennt noch Licht.
ELIAS tritt ein.
AUSSEN STRASSE - NACHT
Tag 2
Aussen schläft die Stadt.
";
    let chunks = extract_scenes(document);
    assert_eq!(
        chunks.len(),
        2,
        "only the two capitalised slug lines are headings, got {chunks:#?}"
    );
    assert_eq!(chunks[0].heading, "AUSSEN HOF - TAG");
    assert_eq!(chunks[1].heading, "AUSSEN STRASSE - NACHT");
    // The prose lines stay inside their chunk.
    assert!(chunks[0].text.contains("Innen brennt noch Licht."));
    assert!(chunks[1].text.contains("Aussen schläft die Stadt."));
}

#[test]
fn extract_scenes_preserves_heading_text() {
    let chunks = extract_scenes("EXT. GARDEN - NIGHT\nCrickets chirp.");
    assert_eq!(chunks.len(), 1);
    assert_eq!(chunks[0].heading, "EXT. GARDEN - NIGHT");
    assert_eq!(chunks[0].text, "Crickets chirp.");
}

// ===========================================================================
// P3.5 — DraftScene::scene_details (kills return Default::default())
// ===========================================================================

#[test]
fn scene_details_maps_location() {
    let draft = DraftScene {
        location: Some("Kitchen".into()),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.location, Some("Kitchen".into()));
}

#[test]
fn scene_details_maps_mood() {
    let draft = DraftScene {
        mood: Some("Tense".into()),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.mood, Some("Tense".into()));
}

#[test]
fn scene_details_maps_summary() {
    let draft = DraftScene {
        summary: Some("Alice enters".into()),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.summary, Some("Alice enters".into()));
}

#[test]
fn scene_details_maps_script_day() {
    let draft = DraftScene {
        script_day: Some("Day 1".into()),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.script_day, Some("Day 1".into()));
}

#[test]
fn scene_details_maps_scene_number() {
    let draft = DraftScene {
        scene_number: Some(42),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.scene_number, Some(42));
}

#[test]
fn scene_details_sets_is_schedule_set_false() {
    let draft = DraftScene::default();
    let details = draft.scene_details();
    assert!(!details.is_schedule_set);
}

// ===========================================================================
// P3.5 — merge_schedule_to_scenes (kills % → /, += → *=)
// ===========================================================================

#[test]
fn merge_distributes_multiple_rows_to_same_scene_number() {
    // This tests the modulo distribution logic (cursor % indices.len())
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![
            ShootingScheduleRow {
                row_ref: "row-a".into(),
                scene_number: Some(1),
                ..Default::default()
            },
            ShootingScheduleRow {
                row_ref: "row-b".into(),
                scene_number: Some(1),
                ..Default::default()
            },
            ShootingScheduleRow {
                row_ref: "row-c".into(),
                scene_number: Some(1),
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    let merged = merge_schedule_to_scenes(
        &schedule,
        &[scene(1), scene(2)],
        &std::collections::HashMap::new(),
    );
    // All three rows go to scene 1
    assert_eq!(merged.scenes[0].schedule_rows.len(), 3);
    assert_eq!(merged.scenes[1].schedule_rows.len(), 0);
}

#[test]
fn merge_rotates_rows_across_same_numbered_scenes() {
    // Two scenes with scene_number=1, three rows → distribution via modulo
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![
            ShootingScheduleRow {
                row_ref: "row-1".into(),
                scene_number: Some(1),
                ..Default::default()
            },
            ShootingScheduleRow {
                row_ref: "row-2".into(),
                scene_number: Some(1),
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    // Two scene(1) entries: rows should distribute across both via modulo
    let merged = merge_schedule_to_scenes(
        &schedule,
        &[scene(1), scene(1), scene(2)],
        &std::collections::HashMap::new(),
    );
    assert_eq!(merged.scenes[0].schedule_rows.len(), 1);
    assert_eq!(merged.scenes[1].schedule_rows.len(), 1);
    assert_eq!(merged.scenes[2].schedule_rows.len(), 0);
}

#[test]
fn merge_counts_unmatched_scenes_correctly() {
    let schedule = ShootingSchedule::default();
    let merged = merge_schedule_to_scenes(
        &schedule,
        &[scene(1), scene(2), scene(3)],
        &std::collections::HashMap::new(),
    );
    assert_eq!(merged.unmatched_script_scenes.len(), 3);
    assert_eq!(merged.scenes.len(), 3);
}

// ===========================================================================
// Episode extraction (issue #581)
// ===========================================================================

fn episode_of(document: &str, chunk: usize) -> Option<DraftEpisode> {
    SceneChunk::extract_scenes(document)[chunk].episode.clone()
}

#[test]
fn episode_marker_reads_number_and_title() {
    let document = "\
Ep.: 3 (Der Unfall)

1. I/T - WOHNUNG ZOE
Aktion.
";
    let chunks = SceneChunk::extract_scenes(document);
    assert_eq!(chunks.len(), 1);
    let episode = chunks[0].episode.clone().expect("marker before heading");
    assert_eq!(episode.number, Some(3));
    assert_eq!(episode.title.as_deref(), Some("Der Unfall"));
}

#[test]
fn episode_marker_ignores_the_suffix_after_the_episode_number() {
    // Issue #826: real page headers glue further fields onto the marker —
    // `Ep.: 292/15` next to `Ep.: 292/16`, and `Block: 098/Ep.: 294`. Only the
    // leading number is the episode; everything after the `/` is a scene/page
    // index INSIDE it. The parser always read it this way (the preview does not
    // invent a second episode), and this test pins that so a future prompt rule
    // cannot drift from the deterministic scan it mirrors.
    let document = "\
Block: 098/Ep.: 292/15

1   A/T - BAUERNHOF
    LEYLA

Block: 098/Ep.: 292/16

2   I/T - KUECHE
    LEYLA
";
    let chunks = SceneChunk::extract_scenes(document);
    assert_eq!(chunks.len(), 2);
    for chunk in &chunks {
        let episode = chunk
            .episode
            .as_ref()
            .expect("every page header carries one");
        assert_eq!(
            episode.number,
            Some(292),
            "the `/15`, `/16` suffix is not part of the episode"
        );
        assert_eq!(episode.title, None);
        assert_eq!(episode.group_key().as_deref(), Some("ep:292"));
    }
    assert_eq!(
        chunks[0].episode, chunks[1].episode,
        "a dissenting suffix must not read as a second episode"
    );
}

#[test]
fn episode_marker_without_colon_or_title_still_groups() {
    let document = "Ep: 7\n\n1. I/T - OP\nAktion.\n";
    let episode = episode_of(document, 0).expect("marker");
    assert_eq!(episode.number, Some(7));
    assert_eq!(episode.title, None);
    assert_eq!(episode.group_key().as_deref(), Some("ep:7"));
}

#[test]
fn episode_marker_with_title_only_groups_by_title() {
    let document = "Ep. (Der Unfall)\n\n1. I/T - OP\nAktion.\n";
    let episode = episode_of(document, 0).expect("marker");
    assert_eq!(episode.number, None);
    assert_eq!(episode.group_key().as_deref(), Some("ep-t:Der Unfall"));
}

#[test]
fn episode_marker_survives_word_pdf_lookalikes() {
    // NBSP after `Ep.`, en dash in the title — the Word→PDF artifacts the
    // scene-heading detector already folds (issue #581 report).
    let document = "Ep.\u{00A0}:\u{00A0}2 (Fahrt\u{2014}Nacht)\n\n1. I/T - KLINIKUM\nAktion.\n";
    let episode = episode_of(document, 0).expect("marker");
    assert_eq!(episode.number, Some(2));
    assert_eq!(episode.title.as_deref(), Some("Fahrt—Nacht"));
}

#[test]
fn episode_markers_repeat_in_page_headers_without_flipping() {
    // The same episode repeats in page headers; a scene after the repeat must
    // still carry the same episode.
    let document = "\
Ep.: 3 (Der Unfall)

1. I/T - WOHNUNG
Aktion.

Block: 2   Ep.: 3 (Der Unfall)

2. I/T - KLINIKUM
Aktion.
";
    let chunks = SceneChunk::extract_scenes(document);
    assert_eq!(chunks.len(), 2);
    assert_eq!(chunks[0].episode, chunks[1].episode);
}

#[test]
fn episode_switches_at_a_new_marker() {
    let document = "\
Ep.: 3 (Der Unfall)

1. I/T - WOHNUNG
Aktion.

Ep.: 4 (Die Nacht)

2. I/T - KLINIKUM
Aktion.
";
    let chunks = SceneChunk::extract_scenes(document);
    assert_eq!(chunks[0].episode.clone().unwrap().number, Some(3));
    assert_eq!(chunks[1].episode.clone().unwrap().number, Some(4));
}

#[test]
fn episode_without_markers_is_none() {
    let chunks = SceneChunk::extract_scenes("1. INT. KITCHEN - DAY\nA\n");
    assert!(chunks[0].episode.is_none());
}

#[test]
fn lowercase_prose_mention_does_not_flip_the_episode() {
    let document = "\
Ep.: 3 (Der Unfall)

1. I/T - WOHNUNG
Sie fragte, ob ep. 3 die beste Folge war.
";
    let chunks = SceneChunk::extract_scenes(document);
    let episode = chunks[0].episode.clone().unwrap();
    assert_eq!(episode.number, Some(3));
}

#[test]
fn episode_marker_tolerates_a_block_prefix_on_the_header_line() {
    // Production page headers carry block and episode on one line.
    let document = "Block: 2 Ep.: 5 (Zwei V\u{00e4}ter)\n\n1. I/T - OP\nAktion.\n";
    let episode = episode_of(document, 0).expect("marker");
    assert_eq!(episode.number, Some(5));
    assert_eq!(episode.title.as_deref(), Some("Zwei Väter"));
}

#[test]
fn draft_episode_group_key_prefers_the_number() {
    let episode = DraftEpisode {
        number: Some(3),
        title: Some("Titel".into()),
    };
    assert_eq!(episode.group_key().as_deref(), Some("ep:3"));
    assert_eq!(DraftEpisode::default().group_key(), None);
}

// ===========================================================================
// Block extraction (issue #827)
// ===========================================================================

#[test]
fn block_marker_reads_both_header_shapes() {
    // The two shapes production page headers use: a colon after the field name
    // and a bare space. Both state the same block.
    assert_eq!(block_marker("Block: 2"), Some(2));
    assert_eq!(block_marker("Block 2"), Some(2));
}

#[test]
fn block_marker_reads_only_the_leading_digits_of_a_glued_header() {
    // Issue #826's glued page header: `Block: 098/Ep.: 294` names block 98.
    // Everything after the `/` belongs to the NEXT field, never to the number
    // — the same "leading digits only" rule the episode suffix follows.
    assert_eq!(block_marker("Block: 098/Ep.: 294"), Some(98));
    assert_eq!(block_marker("Block: 2   Ep.: 3 (Der Unfall)"), Some(2));
}

#[test]
fn block_marker_is_case_insensitive() {
    // Page headers also arrive in capitals; the field SHAPE, not the casing,
    // decides (`day_marker` reads `TAG 1` for the same reason).
    assert_eq!(block_marker("BLOCK: 2   EP.: 3"), Some(2));
    assert_eq!(block_marker("block: 2"), Some(2));
}

#[test]
fn block_marker_ignores_prose_and_scene_headings() {
    // `Block` is a German noun, so casing alone guards nothing — the field
    // SHAPE does. Prose continues with a lowercase word, a sentence
    // punctuation mark or a capitalized word that is no header field, and a
    // scene heading separates its labels with a hyphen; a page-header field
    // ends at the line, a separator or a KNOWN header field.
    for prose in [
        "Block 2 wurde am Montag gedreht.",
        "Der Block 2 war besser als der dritte.",
        "Wir drehen Block 2.",
        "Datenblock 2",
        "Block: 1000",
        "Block 2a war eine Szene",
        // CodeRabbit review: an uppercase letter glued to the digits is a
        // label, not a field boundary (`2A` is a set/scene reference).
        "Block 2A war eine Szene",
        "1. I/T - Block 2A - WOHNUNG",
        // … and a capitalized German word behind the number is prose, even
        // when it starts with a letter sequence that resembles nothing in the
        // header vocabulary.
        "Wir drehen Block 2 Anfang Mai.",
        "Block 2 Dreharbeiten beginnen.",
        "1. I/T - Block 2 - WOHNUNG",
    ] {
        assert_eq!(block_marker(prose), None, "`{prose}` is prose, not a field");
    }
}

#[test]
fn block_marker_accepts_a_known_header_field_behind_the_number() {
    // A page header states several fields on one line; the block field ends
    // where the NEXT FIELD starts. Only the known vocabulary counts (an
    // arbitrary capitalized word is prose — see the rejection test).
    for header in [
        "Block: 2   Ep.: 3 (Der Unfall)",
        "Block: 2   Tag 1",
        "Block 2   Seite 12",
    ] {
        assert_eq!(block_marker(header), Some(2), "`{header}` is a header");
    }
}

#[test]
fn extract_block_number_takes_the_first_page_header() {
    // Page headers repeat the marker on every page; the value is one fact, so
    // the FIRST occurrence wins instead of flipping per line.
    let document = "\
Block: 2   Ep.: 3 (Der Unfall)

1. I/T - WOHNUNG
Aktion.

Block: 2   Ep.: 3 (Der Unfall)

2. I/T - KLINIKUM
Aktion.
";
    assert_eq!(extract_block_number(document), Some(2));
}

#[test]
fn extract_block_number_keeps_the_first_of_two_differing_headers() {
    // A document that spans two blocks publishes the one it OPENS with — the
    // single published number must not become a per-line flip-flop.
    let document = "\
Block: 2

1. I/T - WOHNUNG
Aktion.

Block: 3

2. I/T - KLINIKUM
Aktion.
";
    assert_eq!(extract_block_number(document), Some(2));
}

#[test]
fn extract_block_number_is_absent_without_a_marker() {
    // An episode-only header states no block: honest absence, never a number
    // inferred from the episode or the scene numbering.
    let document = "Ep.: 3 (Der Unfall)\n\n1. I/T - WOHNUNG\nAktion.\n";
    assert_eq!(extract_block_number(document), None);
}

#[test]
fn extract_block_number_ignores_a_scene_heading_mention() {
    let document = "\
1. I/T - BLOCK 2 - WOHNUNG
Aktion.
";
    assert_eq!(extract_block_number(document), None);
}

// ===========================================================================
// DraftEpisode::display_label — progress label for episodes_seen (issue #664)
// ===========================================================================

#[test]
fn draft_episode_display_label_prefers_the_number() {
    let episode = DraftEpisode {
        number: Some(3),
        title: Some("Titel".into()),
    };
    assert_eq!(episode.display_label().as_deref(), Some("Ep. 3"));
}

#[test]
fn draft_episode_display_label_falls_back_to_the_trimmed_title() {
    let episode = DraftEpisode {
        number: None,
        title: Some("  Der Unfall  ".into()),
    };
    assert_eq!(episode.display_label().as_deref(), Some("Der Unfall"));
}

#[test]
fn draft_episode_display_label_is_none_without_number_or_title() {
    assert_eq!(DraftEpisode::default().display_label(), None);
    let blank = DraftEpisode {
        number: None,
        title: Some("   ".into()),
    };
    assert_eq!(blank.display_label(), None);
}

#[test]
fn episode_group_refs_lists_distinct_group_refs_in_order() {
    let preview = ScriptContext {
        block_number: None,
        scenes: vec![
            DraftScene {
                episode: Some(DraftEpisode {
                    number: Some(3),
                    title: None,
                }),
                ..Default::default()
            },
            DraftScene {
                episode: Some(DraftEpisode {
                    number: Some(3),
                    title: Some("same group".into()),
                }),
                ..Default::default()
            },
            DraftScene {
                episode: Some(DraftEpisode {
                    number: Some(4),
                    title: None,
                }),
                ..Default::default()
            },
            DraftScene::default(),
        ],
        ..Default::default()
    };
    assert_eq!(episode_group_refs(&preview), vec!["ep:3", "ep:4"]);
}

// ===========================================================================
// plan_scene_apply — episode groups (issue #581)
// ===========================================================================

fn preview_with_episode(episode: Option<DraftEpisode>) -> ScriptContext {
    ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "scene-1".into(),
            episode,
            ..Default::default()
        }],
        ..Default::default()
    }
}

fn create_mapping() -> ApplyMapping {
    ApplyMapping {
        draft_ref: "scene-1".into(),
        decision: ApplyMappingDecision::Create,
        outfit_decisions: Vec::new(),
    }
}

#[test]
fn plan_resolves_a_create_group_to_a_new_episode() {
    let preview = preview_with_episode(Some(DraftEpisode {
        number: Some(3),
        title: Some("Der Unfall".into()),
    }));
    let plan = plan_scene_apply(
        &preview,
        &[create_mapping()],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[EpisodeGroupPlan {
                episode_ref: "ep:3".into(),
                target: EpisodeTarget::Create {
                    number: 3,
                    name: Some("Der Unfall".into()),
                },
            }],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan");
    assert!(matches!(
        &plan.scenes[0].episode,
        PlannedEpisode::New { episode_ref, number, name }
            if episode_ref == "ep:3" && *number == 3 && name.as_deref() == Some("Der Unfall")
    ));
}

#[test]
fn plan_resolves_an_existing_group_target() {
    let preview = preview_with_episode(Some(DraftEpisode {
        number: Some(3),
        title: None,
    }));
    let existing = EpisodeId::new();
    let plan = plan_scene_apply(
        &preview,
        &[create_mapping()],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[EpisodeGroupPlan {
                episode_ref: "ep:3".into(),
                target: EpisodeTarget::Existing {
                    episode_id: existing,
                },
            }],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan");
    match &plan.scenes[0].episode {
        PlannedEpisode::Existing(episode_id) => assert_eq!(*episode_id, existing),
        other => panic!("expected Existing, got {other:?}"),
    }
}

/// Issue #763 review (CodeRabbit): updating a scene changes its details only, so
/// an `Update` row is planned against the picked episode even when the draft row
/// carries episode-group metadata — the scene keeps the episode it already has,
/// and the applied-episode summary must not name the group's target instead.
#[test]
fn plan_ignores_the_episode_group_for_an_update_row() {
    let preview = preview_with_episode(Some(DraftEpisode {
        number: Some(3),
        title: None,
    }));
    let picked = EpisodeId::new();
    let group_target = EpisodeId::new();
    assert_ne!(picked, group_target);
    let plan = plan_scene_apply(
        &preview,
        &[ApplyMapping {
            draft_ref: "scene-1".into(),
            decision: ApplyMappingDecision::Update {
                aggregate_id: Uuid::now_v7(),
                version: AggregateVersion::INITIAL,
            },
            outfit_decisions: Vec::new(),
        }],
        picked,
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[EpisodeGroupPlan {
                episode_ref: "ep:3".into(),
                target: EpisodeTarget::Existing {
                    episode_id: group_target,
                },
            }],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan");
    match &plan.scenes[0].episode {
        PlannedEpisode::Existing(episode_id) => assert_eq!(
            *episode_id, picked,
            "an Update row keeps the picked episode, not the group's target"
        ),
        other => panic!("expected Existing, got {other:?}"),
    }
}

#[test]
fn plan_defaults_rows_without_episode_metadata_to_the_picked_episode() {
    let default_episode = EpisodeId::new();
    let preview = preview_with_episode(None);
    let plan = plan_scene_apply(
        &preview,
        &[create_mapping()],
        default_episode,
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan");
    assert_eq!(
        plan.scenes[0].episode,
        PlannedEpisode::Existing(default_episode)
    );
}

#[test]
fn plan_ignores_groups_for_ungroupable_episode_metadata() {
    // An `episode` without number AND title cannot be grouped: it must fall
    // back to the default target, not demand a group plan.
    let default_episode = EpisodeId::new();
    let preview = preview_with_episode(Some(DraftEpisode::default()));
    let plan = plan_scene_apply(
        &preview,
        &[create_mapping()],
        default_episode,
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan");
    assert_eq!(
        plan.scenes[0].episode,
        PlannedEpisode::Existing(default_episode)
    );
}

#[test]
fn plan_rejects_a_group_the_request_forgot() {
    let preview = preview_with_episode(Some(DraftEpisode {
        number: Some(3),
        title: None,
    }));
    let error = plan_scene_apply(
        &preview,
        &[create_mapping()],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect_err("ungrouped episode must not silently apply to the default");
    assert!(matches!(error, ApplyGateError::MissingEpisodeGroup(ref key) if key == "ep:3"));
}

#[test]
fn episode_marker_survives_an_ep_word_before_the_marker() {
    // `Ep` also occurs inside capitalized words; only the occurrence that
    // actually parses as a marker may win (CodeRabbit review, issue #581).
    let document = "Epilog \u{2013} Ep.: 5 (Titel)\n\n1. I/T - OP\nAktion.\n";
    let episode = episode_of(document, 0).expect("marker");
    assert_eq!(episode.number, Some(5));
    assert_eq!(episode.title.as_deref(), Some("Titel"));
}

#[test]
fn episode_marker_ignores_an_ep_glued_to_a_word() {
    // A candidate preceded by an alphanumeric character is not a token start.
    let document = "DEp. 3 ist keine Episode\n\n1. I/T - OP\nAktion.\n";
    assert!(episode_of(document, 0).is_none());
}

#[test]
fn episode_word_alone_is_not_a_marker() {
    // `Episode 12` in prose: the `Ep` occurrence yields neither a number nor a
    // title, so the scan moves on — the line carries no marker.
    let chunks = SceneChunk::extract_scenes("Episode 12 beginnt hier.\n\n1. INT. OP\nA\n");
    assert!(chunks[0].episode.is_none());
}

// ── Meta-summary guard (issue #668) ─────────────────────────────────────

#[test]
fn meta_summary_guard_nulls_the_observed_live_variant() {
    // The exact shape the test session observed (45 of 95 scenes,
    // mistral-large-3 via eurouter): a meta-description of the block's
    // shape, not scene content.
    let mut scene = DraftScene {
        summary: Some(
            "Outline-style block with heading and day marker only. \
             No characters, costumes, or props described."
                .to_owned(),
        ),
        ..Default::default()
    };
    assert!(sanitize_meta_summary(&mut scene));
    assert_eq!(scene.summary, None);
}

#[test]
fn meta_summary_guard_covers_the_observed_textual_variants() {
    // The six variants were minor rewordings of the same meta-sentence;
    // the marker set must survive case, dash and whitespace drift.
    for variant in [
        "Outline-style block with heading and day marker only.",
        "This is an outline style block — heading and day marker only.",
        "Outline-style-block: heading and day marker only",
        "The block contains no characters, costumes or props.",
        "This block contains no content worth extracting.",
        "NOTHING HAPPENS IN THIS BLOCK — it only carries a heading.",
    ] {
        assert!(
            is_meta_summary(variant),
            "variant must be detected: {variant:?}"
        );
    }
}

#[test]
fn meta_summary_guard_covers_german_variants() {
    for variant in [
        "Outline-Style-Block nur mit Überschrift und Tagesmarkierung.",
        "In diesem Block passiert nichts. Keine Charaktere, Kostüme oder Requisiten.",
        "Kein Inhalt — nur eine Überschrift.",
        "Dieser Block enthält nur eine Zwischenüberschrift.",
        "Der Block hat keine Handlung.",
    ] {
        assert!(
            is_meta_summary(variant),
            "German variant must be detected: {variant:?}"
        );
    }
}

#[test]
fn meta_summary_guard_keeps_real_scene_summaries() {
    for content in [
        "Alice enters the kitchen and finds the broken vase.",
        "Ben verabschiedet sich von Clara und verlässt das Haus.",
        "The crew rehearses the costume change before the take.",
        "Outline of the heist shown as a flashback.",
    ] {
        assert!(
            !is_meta_summary(content),
            "legitimate summary must survive: {content:?}"
        );
    }
}

#[test]
fn meta_summary_guard_is_conservative_on_edge_cases() {
    // Empty and whitespace-only summaries are not meta-summaries — they
    // are already honest absences.
    assert!(!is_meta_summary(""));
    assert!(!is_meta_summary("   "));
    // A scene titled "This Block" quoting real dialogue must survive:
    // only the LEADING position triggers, and the marker set is closed.
    assert!(!is_meta_summary(
        "This block party turns chaotic when the power fails."
    ));
}

#[test]
fn meta_summary_guard_leaves_a_null_summary_alone() {
    let mut scene = DraftScene::default();
    assert!(!sanitize_meta_summary(&mut scene));
    assert_eq!(scene.summary, None);
}

#[test]
fn meta_summary_guard_preserves_content_with_marker_substring() {
    // CodeRabbit review (issue #668): "keine handlung" must not match as a
    // SUBSTRING of real scene content — "keine Handlungsmöglichkeit" names
    // what the figure does, not the block's emptiness. The marker must end
    // at a non-alphabetic boundary.
    let content = "Sie sieht keine Handlungsmöglichkeit und flieht.";
    assert!(!is_meta_summary(content));
    let mut scene = DraftScene {
        summary: Some(content.to_owned()),
        ..Default::default()
    };
    assert!(!sanitize_meta_summary(&mut scene));
    assert_eq!(scene.summary, Some(content.to_owned()));
}

#[test]
fn meta_summary_guard_boundary_still_matches_the_observed_variants() {
    // The observed meta-sentences end each marker at punctuation or end of
    // text — the boundary rule must not weaken the original detection.
    for variant in [
        "In diesem Block passiert nichts. Keine Charaktere, Kostüme oder Requisiten.",
        "Der Block hat keine Handlung.",
        "Outline-style block with heading and day marker only. No characters, costumes, or props described.",
        "Kein Inhalt",
        "Nur eine Überschrift",
    ] {
        assert!(
            is_meta_summary(variant),
            "boundary rule must keep detection: {variant:?}"
        );
    }
}

// ===========================================================================
// SCRIPT REPORT format (found via the 294.pdf user import): the document
// opens with a scene INDEX (every scene listed as `1    A/T - ORT` + `Tag 1`,
// per shooting day) BEFORE the scene bodies. With `pdftotext -layout` the
// number column stays on the heading line, so index stub and body heading
// carry the SAME scene number and must merge into one preview row — the
// index doubling every scene (94 rows / 34 unique) was the "always ?" bug.
// ===========================================================================

#[test]
fn extract_scenes_merges_index_and_body_occurrences_by_number() {
    let document = "\
PERSONEN

1    A/T - BAUERNHOF
     Tag 1
2    I/T - KLINIKUM
     Tag 1

1   A/T - BAUERNHOF
    Tag 1
    LEYLA
    Jannis? Jannis!
    Sie wuehlt im Heu.

2   I/T - KLINIKUM
    Tag 1
    MATTEO
    Da ist er ja.
";
    let chunks = extract_scenes(document);
    assert_eq!(
        chunks.len(),
        2,
        "index stub + body heading with the same number merge into ONE chunk"
    );
    assert_eq!(chunks[0].scene_number, Some(1));
    assert_eq!(chunks[1].scene_number, Some(2));
    // The body occurrence carries the dialogue; the stub only the day column.
    assert!(
        chunks[0].text.contains("Jannis? Jannis!"),
        "merged chunk keeps the longer body text, got: {:?}",
        chunks[0].text
    );
    assert!(chunks[0].text.contains("Tag 1"), "index day column is kept");
}

#[test]
fn extract_scenes_does_not_merge_unnumbered_headings() {
    // Headings without a document number are distinct scenes even when their
    // text is identical — only a PARSED number deduplicates.
    let document = "INT. ROOM - DAY\nAlice enters.\n\nINT. ROOM - DAY\nBob leaves.";
    let chunks = extract_scenes(document);
    assert_eq!(chunks.len(), 2);
}

#[test]
fn extract_scenes_backfills_episode_title_from_title_page() {
    // The `Ep.:` page-header markers carry a bare number; the title sits on
    // the title page as `(294) "Freundschaft"`. The preview row must carry
    // the heading so apply names the created episode after it.
    let document = "\
(294) \"Freundschaft\"

Regie: Dieter Laske

Block: 098/Ep.: 294

1   A/T - BAUERNHOF
    LEYLA
    Jannis?
";
    let chunks = extract_scenes(document);
    assert_eq!(chunks.len(), 1);
    let episode = chunks[0].episode.as_ref().expect("marker stamped");
    assert_eq!(episode.number, Some(294));
    assert_eq!(
        episode.title.as_deref(),
        Some("Freundschaft"),
        "title-page heading must fill the marker's missing title"
    );
}

#[test]
fn title_page_entry_rejects_prose_parentheses() {
    assert_eq!(title_page_entry("(vgl. 294)"), None);
    assert_eq!(title_page_entry("Szene (12) fehlt"), None);
    assert_eq!(title_page_entry("(294) ohne Anfuehrungszeichen"), None);
    assert_eq!(
        title_page_entry("(294) \"Freundschaft\""),
        Some((294, "Freundschaft".to_owned()))
    );
    assert_eq!(
        title_page_entry("(12) \u{201E}Titel\u{201C}"),
        Some((12, "Titel".to_owned()))
    );
}

#[test]
fn extract_scenes_does_not_merge_across_episodes() {
    // CodeRabbit review: two episodes can both contain a scene `1` — the
    // merge key is (document number, EPISODE number), so episode A's scene 1
    // and episode B's scene 1 stay two separate scenes.
    let document = "\
Ep.: 1 (A)
1   I/T - ORT A
    Text episode one.

Ep.: 2 (B)
1   I/T - ORT B
    Text episode two.
";
    let chunks = extract_scenes(document);
    assert_eq!(
        chunks.len(),
        2,
        "same number in different episodes never merges"
    );
    assert_eq!(chunks[0].scene_number, Some(1));
    assert!(
        chunks[0].text.contains("episode one"),
        "got: {:?}",
        chunks[0].text
    );
    assert_eq!(chunks[1].scene_number, Some(1));
    assert!(
        chunks[1].text.contains("episode two"),
        "got: {:?}",
        chunks[1].text
    );
}

#[test]
fn extract_scenes_does_not_merge_suffixed_scene_labels() {
    // CodeRabbit review: `leading_scene_number` reads only the leading
    // digits, so `12` and `12A` shared `scene_number == Some(12)` and the
    // merge folded the inserted scene `12A` into scene `12` — the suffix
    // scene lost its preview row. The merge key is the FULL label now.
    let document = "\
12  I/T - KÜCHE
    Koch schneidet Zwiebeln.

12A I/T - FLUR
    Boten laufen vorbei.
";
    let chunks = extract_scenes(document);
    assert_eq!(chunks.len(), 2, "`12` and `12A` are distinct scenes");
    assert_eq!(chunks[0].scene_number, Some(12));
    assert!(
        chunks[0].text.contains("Zwiebeln"),
        "got: {:?}",
        chunks[0].text
    );
    assert_eq!(chunks[1].scene_number, Some(12));
    assert!(
        chunks[1].text.contains("Boten laufen vorbei"),
        "suffix scene keeps its own body, got: {:?}",
        chunks[1].text
    );
}

#[test]
fn extract_scenes_glued_german_token_is_not_a_scene_suffix() {
    // CodeRabbit review round 3: `/` must not be a suffix separator — the
    // German short form glues its interior/exterior token to the number
    // (`12I/T - KÜCHE`). Reading the `I` as a scene suffix would mangle the
    // line into "/T - KÜCHE" and the scene would lose its chunk boundary.
    let document = "\
12I/T - KÜCHE
    Koch schneidet Zwiebeln.
";
    let chunks = extract_scenes(document);
    assert_eq!(chunks.len(), 1, "`12I/T` is scene 12 with a german token");
    assert_eq!(chunks[0].scene_number, Some(12));
    assert!(
        chunks[0].text.contains("Zwiebeln"),
        "heading body captured, got: {:?}",
        chunks[0].text
    );
}

#[test]
fn extract_scenes_does_not_merge_across_title_only_episodes() {
    // CodeRabbit review: the merge key used only `episode.number`, so two
    // TITLE-ONLY markers (`Ep (A)` / `Ep (B)` — number `None`) shared the
    // `None` episode key and scene `1` of both merged. The key is the
    // `DraftEpisode::group_key` now: a title-only episode is its own
    // identity, and an episode-less chunk merges only with another
    // episode-less chunk.
    let document = "\
Ep (A)
1   I/T - ORT A
    Text episode one.

Ep (B)
1   I/T - ORT B
    Text episode two.
";
    let chunks = extract_scenes(document);
    assert_eq!(
        chunks.len(),
        2,
        "same number under two title-only episodes never merges"
    );
    assert!(chunks[0].text.contains("episode one"));
    assert!(chunks[1].text.contains("episode two"));
}

#[test]
fn extract_scenes_merge_preserves_index_only_metadata() {
    // CodeRabbit review: the index entry may carry metadata (its `Tag 3`
    // day column) that the body occurrence lacks — the union keeps it so
    // the model can still extract the script day.
    let document = "\
3    I/T - KLINIKUM
     Tag 3

3   I/T - KLINIKUM
    LEYLA
    Nur Dialogue, kein Tag im Koerper.
";
    let chunks = extract_scenes(document);
    assert_eq!(chunks.len(), 1);
    assert!(
        chunks[0].text.contains("Tag 3"),
        "index-only metadata must survive the merge, got: {:?}",
        chunks[0].text
    );
    assert!(chunks[0].text.contains("Nur Dialogue"));
}
// temp debug

// ===========================================================================
// Shooting-day extraction (issue #706)
// ===========================================================================

fn day_of(document: &str, chunk: usize) -> Option<DraftShootingDay> {
    SceneChunk::extract_scenes(document)[chunk]
        .shooting_day
        .clone()
}

#[test]
fn day_marker_reads_tag_form() {
    assert_eq!(
        day_marker("1    I/T - KLINIKUM    Tag 1"),
        Some(DraftShootingDay {
            number: Some(1),
            label: Some("Tag 1".into()),
            score: None,
        })
    );
}

#[test]
fn day_marker_reads_spieltag_preceding_form() {
    assert_eq!(
        day_marker("1. Spieltag"),
        Some(DraftShootingDay {
            number: Some(1),
            label: Some("1. Spieltag".into()),
            score: None,
        })
    );
}

#[test]
fn day_marker_reads_compound_following_form() {
    assert_eq!(
        day_marker("Drehtag 12"),
        Some(DraftShootingDay {
            number: Some(12),
            label: Some("Drehtag 12".into()),
            score: None,
        })
    );
}

#[test]
fn day_marker_is_case_insensitive() {
    // Uppercase page headers read the same as scene-index columns.
    let day = day_marker("TAG 3").expect("uppercase marker");
    assert_eq!(day.number, Some(3));
}

#[test]
fn day_marker_ignores_weekdays() {
    // `Montag 12` is a date, never shooting day 12: the day word must be a
    // whole token.
    assert_eq!(day_marker("Montag 12"), None);
    assert_eq!(day_marker("Freitag"), None);
}

#[test]
fn day_marker_ignores_time_of_day() {
    // The German time-of-day `TAG` in a heading carries no digits.
    assert_eq!(day_marker("INNEN WOHNUNG - TAG"), None);
}

#[test]
fn day_marker_ignores_prose() {
    assert_eq!(day_marker("Am Tag danach war alles anders."), None);
    assert_eq!(day_marker("Spieltag war der Montag"), None);
}

#[test]
fn day_group_key_normalizes_to_the_number() {
    // `Tag 1` and `1. Spieltag` are the SAME day (decision: normalize).
    let tag = DraftShootingDay {
        number: Some(1),
        label: Some("Tag 1".into()),
        score: None,
    };
    let spieltag = DraftShootingDay {
        number: Some(1),
        label: Some("1. Spieltag".into()),
        score: None,
    };
    assert_eq!(tag.group_key(), Some("day:1".into()));
    assert_eq!(tag.group_key(), spieltag.group_key());
}

#[test]
fn day_group_key_falls_back_to_the_label() {
    let day = DraftShootingDay {
        number: None,
        label: Some("Drehwoche 2".into()),
        score: None,
    };
    assert_eq!(day.group_key(), Some("day-l:Drehwoche 2".into()));
    assert_eq!(
        DraftShootingDay::default().group_key(),
        None,
        "a day with neither number nor label cannot be grouped"
    );
}

#[test]
fn day_display_label_prefers_the_verbatim_marker() {
    let day = DraftShootingDay {
        number: Some(1),
        label: Some("1. Spieltag".into()),
        score: None,
    };
    assert_eq!(day.display_label().as_deref(), Some("1. Spieltag"));
    let bare = DraftShootingDay {
        number: Some(2),
        label: None,
        score: None,
    };
    assert_eq!(bare.display_label().as_deref(), Some("Tag 2"));
}

#[test]
fn parse_script_day_normalizes_the_model_label() {
    let day = parse_script_day("Tag 1").expect("parseable label");
    assert_eq!(day.group_key(), Some("day:1".into()));
    // An unparseable label still groups verbatim.
    let week = parse_script_day("Drehwoche 2").expect("label fallback");
    assert_eq!(week.group_key(), Some("day-l:Drehwoche 2".into()));
    // Blank stays unscheduled — never invented.
    assert_eq!(parse_script_day("   "), None);
}

#[test]
fn extract_scenes_stamps_the_day_in_effect() {
    let document = "\
1    I/T - KLINIKUM    Tag 1
Aktion.

2    I/T - FLUR
Aktion.

3    A/T - PARKPLATZ    Tag 2
Aktion.
";
    assert_eq!(day_of(document, 0).unwrap().number, Some(1));
    // Day columns repeat across a day's pages: the following chunk carries
    // the same day without its own marker.
    assert_eq!(day_of(document, 1).unwrap().number, Some(1));
    assert_eq!(day_of(document, 2).unwrap().number, Some(2));
}

#[test]
fn extract_scenes_keeps_the_first_occurrence_label() {
    let document = "\
1    I/T - KLINIKUM    1. Spieltag
Aktion.

2    I/T - FLUR    Tag 1
Aktion.
";
    // The first occurrence's verbatim label wins.
    assert_eq!(
        day_of(document, 1).unwrap().label.as_deref(),
        Some("1. Spieltag")
    );
}

#[test]
fn extract_scenes_without_day_markers_stays_unscheduled() {
    let document = "\
1. I/T - WOHNUNG ZOE
Aktion.
";
    assert_eq!(day_of(document, 0), None);
}

#[test]
fn dialogue_mentioning_a_day_never_changes_the_day_in_effect() {
    // CodeRabbit review (issue #706): a non-heading line only updates
    // `current_day` when the WHOLE line is the marker — short dialogue
    // mentioning a day must not re-group the following scenes.
    let document = "\
1    I/T - KLINIKUM    Tag 1
Aktion.

Tag 3 war schlimm.

2    I/T - FLUR
Aktion.
";
    // Scene 2 still carries day 1 — the dialogue line was not a marker.
    assert_eq!(day_of(document, 1).unwrap().number, Some(1));
}

#[test]
fn a_standalone_day_marker_line_updates_the_day_in_effect() {
    // The counterpart: a line that IS the marker (page header / day column)
    // does update `current_day` — case-insensitively, whitespace-normalized.
    let document = "\
1    I/T - KLINIKUM    Tag 1
Aktion.

TAG 2

2    I/T - FLUR
Aktion.
";
    assert_eq!(day_of(document, 1).unwrap().number, Some(2));
}

#[test]
fn a_day_column_below_the_heading_dates_that_scene() {
    // The observed broadcast layout prints the day column UNDER its slug. Read
    // as "the day of the FOLLOWING scenes", the first scene of the script stayed
    // undated and every scene after a day change was dated one day late.
    let document = "\
1 I/T - KLINIKUM
Tag 1
Aktion eins.

2 I/T - FLUR
Tag 1
Aktion zwei.

3 A/T - PARKPLATZ
Tag 2
Aktion drei.
";
    let chunks = SceneChunk::extract_scenes(document);
    assert_eq!(chunks.len(), 3);
    assert_eq!(day_number(&chunks[0]), Some(1));
    assert_eq!(day_number(&chunks[1]), Some(1));
    assert_eq!(day_number(&chunks[2]), Some(2));

    // A column that stands apart from every heading still labels the scenes
    // BELOW it (a group header), so both layouts are honoured.
    let grouped = "\
Tag 1

1 I/T - KLINIKUM
Aktion eins.

2 I/T - FLUR
Aktion zwei.
";
    let chunks = SceneChunk::extract_scenes(grouped);
    assert_eq!(day_number(&chunks[0]), Some(1));
    assert_eq!(day_number(&chunks[1]), Some(1));
}

fn day_number(chunk: &SceneChunk) -> Option<i32> {
    chunk.shooting_day.as_ref().and_then(|day| day.number)
}

#[test]
fn old_preview_without_shooting_day_still_loads() {
    // Additive wire convention: a preview stored before `shooting_day`
    // existed keeps deserializing (serde default), and an old-model
    // `script_day` string still deserializes verbatim.
    let stored = r#"{
        "title": null,
        "scenes": [
            {
                "draft_ref": "1. I/T - OP",
                "scene_number": 1,
                "location": null,
                "mood": null,
                "summary": null,
                "script_day": "Tag 1",
                "characters": ["RENEE"],
                "costumes": []
            }
        ],
        "uncertainties": []
    }"#;
    let preview: ScriptContext = serde_json::from_str(stored).expect("old preview loads");
    assert_eq!(preview.scenes[0].script_day.as_deref(), Some("Tag 1"));
    assert_eq!(preview.scenes[0].shooting_day, None);
}

#[test]
fn shooting_day_group_refs_are_first_seen_order() {
    let preview = ScriptContext {
        block_number: None,
        scenes: vec![
            DraftScene {
                draft_ref: "1. I/T - OP".into(),
                shooting_day: Some(DraftShootingDay {
                    number: Some(1),
                    label: None,
                    score: None,
                }),
                ..Default::default()
            },
            DraftScene {
                draft_ref: "2. I/T - OP".into(),
                shooting_day: Some(DraftShootingDay {
                    number: Some(2),
                    label: None,
                    score: None,
                }),
                ..Default::default()
            },
            DraftScene {
                draft_ref: "3. I/T - OP".into(),
                // Same group as row 1 — not repeated.
                shooting_day: Some(DraftShootingDay {
                    number: Some(1),
                    label: None,
                    score: None,
                }),
                ..Default::default()
            },
            DraftScene {
                draft_ref: "4. I/T - OP".into(),
                shooting_day: None,
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    assert_eq!(
        shooting_day_group_refs(&preview),
        vec!["day:1".to_owned(), "day:2".to_owned()]
    );
}

fn preview_with_day(day: Option<DraftShootingDay>) -> ScriptContext {
    ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "scene-1".into(),
            shooting_day: day,
            ..Default::default()
        }],
        ..Default::default()
    }
}

fn accept_day(day_ref: &str) -> ShootingDayPlan {
    ShootingDayPlan {
        day_ref: day_ref.to_owned(),
        accepted: true,
    }
}

#[test]
fn plan_carries_the_accepted_day_group() {
    let preview = preview_with_day(Some(DraftShootingDay {
        number: Some(1),
        label: Some("Tag 1".into()),
        score: None,
    }));
    let plan = plan_scene_apply(
        &preview,
        &[create_mapping()],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[accept_day("day:1")],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan");
    assert_eq!(
        plan.scenes[0].shooting_day,
        PlannedShootingDay::Group {
            day_ref: "day:1".into(),
            label: Some("Tag 1".into()),
            score: None,
        }
    );
}

#[test]
fn plan_leaves_a_rejected_day_group_unscheduled() {
    let preview = preview_with_day(Some(DraftShootingDay {
        number: Some(1),
        label: None,
        score: None,
    }));
    let plan = plan_scene_apply(
        &preview,
        &[create_mapping()],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[ShootingDayPlan {
                day_ref: "day:1".into(),
                accepted: false,
            }],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan");
    assert_eq!(plan.scenes[0].shooting_day, PlannedShootingDay::None);
}

#[test]
fn plan_rejects_a_day_group_the_request_forgot() {
    let preview = preview_with_day(Some(DraftShootingDay {
        number: Some(1),
        label: None,
        score: None,
    }));
    let error = plan_scene_apply(
        &preview,
        &[create_mapping()],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect_err("a referenced day group must not silently apply unscheduled");
    assert!(matches!(
        error,
        ApplyGateError::MissingShootingDayGroup(ref key) if key == "day:1"
    ));
}

#[test]
fn plan_defaults_rows_without_day_metadata_to_unscheduled() {
    let preview = preview_with_day(None);
    let plan = plan_scene_apply(
        &preview,
        &[create_mapping()],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: &[],
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
    .expect("plan");
    assert_eq!(plan.scenes[0].shooting_day, PlannedShootingDay::None);
}

// ===========================================================================
// Issue #721 — deterministic set-shorthand mood extraction
// ===========================================================================

#[test]
fn german_short_form_heading_yields_canonical_mood() {
    assert_eq!(
        SceneChunk::extract_scenes("12 I/T - WERKSTATT\nBodies.")
            .remove(0)
            .mood,
        Some("I/T".to_owned())
    );
    assert_eq!(
        SceneChunk::extract_scenes("8 A/N - STRASSE\nBody.")
            .remove(0)
            .mood,
        Some("A/N".to_owned())
    );
}

#[test]
fn german_and_english_long_form_headings_normalize() {
    for (heading, expected) in [
        ("INNEN WOHNUNG - NACHT", "I/N"),
        ("INNENAUFNAHME KUECHE - TAG", "I/T"),
        ("AUSSEN. HOF - DÄMMERUNG", "A/D"),
        ("INT. KITCHEN - DAY", "I/T"),
        ("EXT. STREET - NIGHT", "A/N"),
        ("INT. KINO - MORGEN", "I/M"),
        ("EXT. PARK - EVENING", "A/AB"),
        ("EXT. STRASSE - DUSK", "A/D"),
    ] {
        let chunks = SceneChunk::extract_scenes(&format!("{heading}\nBody."));
        assert_eq!(chunks.len(), 1, "{heading}");
        assert_eq!(chunks[0].mood, Some(expected.to_owned()), "{heading}");
    }
}

#[test]
fn combined_int_ext_heading_yields_three_component_mood() {
    let chunks = SceneChunk::extract_scenes("INT/EXT. WORKSHOP - DAY\nBody.");
    assert_eq!(chunks[0].mood, Some("I/A/T".to_owned()));
    let chunks = SceneChunk::extract_scenes("I/E. HOUSE - NIGHT\nBody.");
    assert_eq!(chunks[0].mood, Some("I/A/N".to_owned()));
}

#[test]
fn heading_without_canonical_time_token_leaves_mood_none() {
    // No time token at all.
    assert_eq!(
        SceneChunk::extract_scenes("INT. KITCHEN\nBody.")
            .remove(0)
            .mood,
        None
    );
    // A 1–2 char German token outside the canonical set is not canonicalized.
    assert_eq!(
        SceneChunk::extract_scenes("12 I/X - ORT\nBody.")
            .remove(0)
            .mood,
        None
    );
    // A word that merely CONTAINS a time spelling never matches: without a
    // canonical token the heading has no mood at all, and the ABENDBLATT
    // word itself never fires — only the REAL token ("- TAG") in the same
    // heading produces the shorthand (whole-token matching).
    assert_eq!(
        SceneChunk::extract_scenes("INT. ABENDBLATT REDAKTION\nBody.")
            .remove(0)
            .mood,
        None
    );
    assert_eq!(
        SceneChunk::extract_scenes("INT. ABENDBLATT REDAKTION - TAG\nBody.")
            .remove(0)
            .mood,
        Some("I/T".to_owned())
    );
}

#[test]
fn shooting_day_markers_in_headings_are_not_mood() {
    // A trailing day NUMBER makes TAG/DAY a shooting-day marker (script-report
    // day column, issue #706's territory) — never a time of day.
    assert_eq!(
        SceneChunk::extract_scenes("INT. KITCHEN - TAG 1\nBody.")
            .remove(0)
            .mood,
        None
    );
    assert_eq!(
        SceneChunk::extract_scenes("INNEN WOHNUNG - DAY 2\nBody.")
            .remove(0)
            .mood,
        None
    );
    // Without the trailing number the same words stay a time of day.
    assert_eq!(
        SceneChunk::extract_scenes("INT. KITCHEN - TAG\nBody.")
            .remove(0)
            .mood,
        Some("I/T".to_owned())
    );
    // Other recognized tokens keep their normal handling even before a digit.
    assert_eq!(
        SceneChunk::extract_scenes("EXT. STREET - NIGHT 3\nBody.")
            .remove(0)
            .mood,
        Some("A/N".to_owned())
    );
}

#[test]
fn mood_is_additive_on_stored_previews() {
    // A preview blob stored before the field existed still deserializes.
    let legacy =
        r#"{"index":0,"heading":"12 I/T - WERKSTATT","scene_number":12,"episode":null,"text":"b"}"#;
    let chunk: SceneChunk = serde_json::from_str(legacy).unwrap();
    assert_eq!(chunk.mood, None);
}

// ===========================================================================
// Issue #721 — lossless <Episode>.<Scene> schedule references
// ===========================================================================

#[test]
fn parse_schedule_scene_ref_splits_dot_notation_as_integers() {
    // The trailing zero is a scene number, never a decimal digit.
    assert_eq!(
        parse_schedule_scene_ref("294.10"),
        (Some(294), Some(10), None)
    );
    assert_eq!(parse_schedule_scene_ref("03.05"), (Some(3), Some(5), None));
    assert_eq!(
        parse_schedule_scene_ref("300.37N"),
        (Some(300), Some(37), Some("N".to_owned()))
    );
    // Plain references carry no episode.
    assert_eq!(parse_schedule_scene_ref("10"), (None, Some(10), None));
    assert_eq!(
        parse_schedule_scene_ref("12A"),
        (None, Some(12), Some("A".to_owned()))
    );
    assert_eq!(parse_schedule_scene_ref(" 7 "), (None, Some(7), None));
    // Non-episode units ("SB7.2", "T3") and unparseable references degrade to unmatched.
    assert_eq!(parse_schedule_scene_ref("SB7.2"), (None, None, None));
    assert_eq!(parse_schedule_scene_ref("T3"), (None, None, None));
    assert_eq!(parse_schedule_scene_ref(""), (None, None, None));
    assert_eq!(parse_schedule_scene_ref("ABC"), (None, None, None));
    assert_eq!(parse_schedule_scene_ref("294."), (None, None, None));
    assert_eq!(parse_schedule_scene_ref(".10"), (None, None, None));
    assert_eq!(parse_schedule_scene_ref("294.10.5"), (None, None, None));
    assert_eq!(
        parse_schedule_scene_ref("99999999999.10"),
        (None, None, None)
    );
}

// ===========================================================================
// Issue #721 — episode-aware schedule merge
// ===========================================================================

fn episode_scene(episode: EpisodeId, number: u32) -> SceneView {
    SceneView {
        episode_id: episode,
        scene_number: Some(number),
        ..scene(number)
    }
}

#[test]
fn merge_attaches_row_to_the_matching_episodes_scene() {
    let ep294 = EpisodeId::new();
    let ep295 = EpisodeId::new();
    let episodes = std::collections::HashMap::from([(ep294, 294), (ep295, 295)]);
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![ShootingScheduleRow {
            row_ref: "row-295-10".into(),
            scene_number: Some(10),
            episode_number: Some(295),
            ..Default::default()
        }],
        ..Default::default()
    };
    let merged = merge_schedule_to_scenes(
        &schedule,
        &[episode_scene(ep294, 10), episode_scene(ep295, 10)],
        &episodes,
    );
    // Scene 10 of episode 295 gets the row; episode 294's scene 10 stays empty.
    let ep295_scene = merged
        .scenes
        .iter()
        .find(|merged| merged.scene.episode_id == ep295)
        .unwrap();
    let ep294_scene = merged
        .scenes
        .iter()
        .find(|merged| merged.scene.episode_id == ep294)
        .unwrap();
    assert_eq!(ep295_scene.schedule_rows.len(), 1);
    assert_eq!(ep295_scene.schedule_rows[0].row_ref, "row-295-10");
    assert!(ep294_scene.schedule_rows.is_empty());
}

#[test]
fn merge_leaves_row_unmatched_when_episode_pair_misses() {
    let ep294 = EpisodeId::new();
    let ep295 = EpisodeId::new();
    let episodes = std::collections::HashMap::from([(ep294, 294), (ep295, 295)]);
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![ShootingScheduleRow {
            row_ref: "row-295-10".into(),
            scene_number: Some(10),
            episode_number: Some(295),
            ..Default::default()
        }],
        ..Default::default()
    };
    // Only episode 294 carries a Scene 10 — the pair matches NOTHING and the
    // row must NOT fall back onto the wrong episode's scene.
    let merged = merge_schedule_to_scenes(&schedule, &[episode_scene(ep294, 10)], &episodes);
    assert_eq!(merged.unmatched_schedule_rows.len(), 1);
    assert_eq!(merged.unmatched_schedule_rows[0].row_ref, "row-295-10");
    assert!(merged.scenes[0].schedule_rows.is_empty());
}

#[test]
fn merge_falls_back_to_scene_number_only_without_episode_context() {
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![ShootingScheduleRow {
            row_ref: "row-1".into(),
            scene_number: Some(1),
            ..Default::default()
        }],
        ..Default::default()
    };
    // Rows without an episode number (and rows when the map is absent) match
    // by scene number alone, as before #721.
    let merged =
        merge_schedule_to_scenes(&schedule, &[scene(1)], &std::collections::HashMap::new());
    assert!(merged.unmatched_schedule_rows.is_empty());
    assert_eq!(merged.scenes[0].schedule_rows.len(), 1);
}

#[test]
fn merge_ignores_scenes_with_unknown_episode_for_episode_rows() {
    let ep294 = EpisodeId::new();
    let episodes = std::collections::HashMap::from([(ep294, 294)]);
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![ShootingScheduleRow {
            row_ref: "row-1".into(),
            scene_number: Some(1),
            episode_number: Some(294),
            ..Default::default()
        }],
        ..Default::default()
    };
    // The scene's episode is NOT in the map: it is invisible to the
    // episode-bearing row (a pair match against an unknown episode would be
    // a guess, not a join).
    let merged =
        merge_schedule_to_scenes(&schedule, &[episode_scene(EpisodeId::new(), 1)], &episodes);
    assert_eq!(merged.unmatched_schedule_rows.len(), 1);
}

// ── Pass 2: outfit continuity planning
// (OpenSpec `ai-import-decision-outfit-continuity`, design D3/D4) ──

fn continuity_scene(draft_ref: &str, characters: &[&str], outfits: Vec<DraftOutfit>) -> DraftScene {
    DraftScene {
        draft_ref: draft_ref.to_owned(),
        scene_number: Some(draft_ref.len() as u32),
        location: Some(format!("ORT-{draft_ref}")),
        summary: Some(format!("action of {draft_ref}")),
        characters: characters
            .iter()
            .map(|name| DraftCharacter::from(*name))
            .collect(),
        outfits,
        ..Default::default()
    }
}

fn continued_outfit(character: &str, source_ref: &str) -> DraftOutfit {
    DraftOutfit {
        character_name: character.to_owned(),
        name: "Zivil-Look".to_owned(),
        notes: None,
        source_quote: String::new(),
        origin: DraftOutfitOrigin::ContinuedFromScene,
        provenance: Some(DraftOutfitProvenance {
            source_draft_ref: Some(source_ref.to_owned()),
            source_scene_number: Some(1),
            confidence: 0.9,
        }),
        pieces: Vec::new(),
    }
}

fn explicit_outfit(character: &str, name: &str) -> DraftOutfit {
    DraftOutfit {
        character_name: character.to_owned(),
        name: name.to_owned(),
        notes: None,
        source_quote: format!("{character} in {name}"),
        origin: DraftOutfitOrigin::ExplicitQuote,
        provenance: None,
        pieces: vec![DraftPiece {
            name: "Hemd".to_owned(),
            category_hint: None,
            description: None,
        }],
    }
}

fn plan_continuity(
    preview: &ScriptContext,
    selections: &[OutfitContinuitySelection],
) -> Result<ScriptApplyPlan, ApplyGateError> {
    let mappings: Vec<ApplyMapping> = preview
        .scenes
        .iter()
        .enumerate()
        .map(|(index, scene)| ApplyMapping {
            draft_ref: draft_row_ref(scene, index),
            decision: ApplyMappingDecision::Create,
            outfit_decisions: Vec::new(),
        })
        .collect();
    plan_scene_apply(
        preview,
        &mappings,
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &ReviewerDecisions {
            continuity_selections: selections,
            episode_groups: &[],
            shooting_days: &[],
            acknowledged_uncertainties: &[],
            categories: &[],
        },
    )
}

#[test]
fn a_continued_outfit_plans_the_beat_without_creating_a_look() {
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![
            continuity_scene(
                "source",
                &["BEN"],
                vec![explicit_outfit("BEN", "Zivil-Look")],
            ),
            continuity_scene("target", &["BEN"], vec![continued_outfit("BEN", "source")]),
        ],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let plan = plan_continuity(&preview, &[]).expect("plan");
    let continuation = plan.scenes[1].outfits[0]
        .continuation
        .as_ref()
        .expect("continuation planned");
    assert_eq!(continuation.source_draft_ref, "source");
    assert_eq!(continuation.source_outfit_ordinal, 0);
    assert_eq!(continuation.character_identity, "ben");
    assert!(
        plan.scenes[1].outfits[0].pieces.is_empty(),
        "a continued look owns no garments"
    );
    // The source row keeps its own create.
    assert!(plan.scenes[0].outfits[0].continuation.is_none());
    assert_eq!(plan.scenes[0].outfits[0].pieces.len(), 1);
}

#[test]
fn a_continuation_chain_resolves_to_the_row_that_creates_the_look() {
    // scene 3 continues scene 2, which continues scene 1: only scene 1 creates.
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![
            continuity_scene("s1", &["BEN"], vec![explicit_outfit("BEN", "Zivil-Look")]),
            continuity_scene("s2", &["BEN"], vec![continued_outfit("BEN", "s1")]),
            continuity_scene("s3", &["BEN"], vec![continued_outfit("BEN", "s2")]),
        ],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let plan = plan_continuity(&preview, &[]).expect("plan");
    let continuation = plan.scenes[2].outfits[0]
        .continuation
        .as_ref()
        .expect("continuation planned");
    assert_eq!(continuation.source_draft_ref, "s1");
}

#[test]
fn a_continuation_without_a_source_outfit_is_reported() {
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![
            continuity_scene("source", &["BEN"], Vec::new()),
            continuity_scene("target", &["BEN"], vec![continued_outfit("BEN", "source")]),
        ],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let plan = plan_continuity(&preview, &[]).expect("plan");
    assert!(plan.scenes[1].outfits.is_empty());
    assert_eq!(
        plan.unapplied_outfits[0].reason,
        UnappliedOutfitReason::ContinuityUnresolved
    );
}

#[test]
fn a_continued_selection_plans_the_source_look() {
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![
            continuity_scene(
                "source",
                &["BEN"],
                vec![explicit_outfit("BEN", "Zivil-Look")],
            ),
            continuity_scene("target", &["BEN"], Vec::new()),
        ],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let selections = [OutfitContinuitySelection {
        scene_index: 1,
        character_identity: "ben".to_owned(),
        candidate: OutfitContinuityCandidate::Continued,
    }];
    let plan = plan_continuity(&preview, &selections).expect("plan");
    let outfit = &plan.scenes[1].outfits[0];
    assert_eq!(outfit.name, "Zivil-Look");
    assert_eq!(outfit.ordinal, 0, "a gap row has no extracted outfits");
    assert_eq!(
        outfit
            .continuation
            .as_ref()
            .map(|plan| plan.source_draft_ref.as_str()),
        Some("source")
    );
    assert!(outfit.pieces.is_empty());
}

#[test]
fn an_inferred_selection_plans_a_context_look_with_no_pieces() {
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![continuity_scene("target", &["BEN"], Vec::new())],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    // An inferred candidate is only offered when the context moved away from a
    // prior appearance, so the preview needs one.
    let mut preview = preview;
    let mut source = continuity_scene(
        "source",
        &["BEN"],
        vec![explicit_outfit("BEN", "Zivil-Look")],
    );
    source.location = Some("WOHNUNG".to_owned());
    preview.scenes.insert(0, source);
    let selections = [OutfitContinuitySelection {
        scene_index: 1,
        character_identity: "ben".to_owned(),
        candidate: OutfitContinuityCandidate::Inferred,
    }];
    let plan = plan_continuity(&preview, &selections).expect("plan");
    let outfit = &plan.scenes[1].outfits[0];
    assert!(outfit.name.starts_with("Kontext-Look"));
    assert!(outfit.continuation.is_none(), "an inferred look is created");
    assert!(outfit.pieces.is_empty(), "the script named no garment");
}

#[test]
fn an_unoffered_selection_refuses_the_plan() {
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![continuity_scene("target", &["BEN"], Vec::new())],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let selections = [OutfitContinuitySelection {
        scene_index: 0,
        character_identity: "ben".to_owned(),
        candidate: OutfitContinuityCandidate::Continued,
    }];
    let error = plan_continuity(&preview, &selections).expect_err("no prior outfit, no candidate");
    assert!(matches!(
        error,
        ApplyGateError::UnknownContinuityCandidate(_)
    ));
}

#[test]
fn two_selections_for_one_gap_refuse_the_plan() {
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![
            continuity_scene(
                "source",
                &["BEN"],
                vec![explicit_outfit("BEN", "Zivil-Look")],
            ),
            continuity_scene("target", &["BEN"], Vec::new()),
        ],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let selections = [
        OutfitContinuitySelection {
            scene_index: 1,
            character_identity: "ben".to_owned(),
            candidate: OutfitContinuityCandidate::Continued,
        },
        OutfitContinuitySelection {
            scene_index: 1,
            character_identity: "ben".to_owned(),
            candidate: OutfitContinuityCandidate::Inferred,
        },
    ];
    let error = plan_continuity(&preview, &selections).expect_err("duplicate selection");
    assert!(matches!(
        error,
        ApplyGateError::UnknownContinuityCandidate(_)
    ));
}

#[test]
fn a_gap_without_a_selection_plans_no_outfit() {
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![
            continuity_scene(
                "source",
                &["BEN"],
                vec![explicit_outfit("BEN", "Zivil-Look")],
            ),
            continuity_scene("target", &["BEN"], Vec::new()),
        ],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let plan = plan_continuity(&preview, &[]).expect("plan");
    assert!(plan.scenes[1].outfits.is_empty(), "no invented look");
    assert!(plan.unapplied_outfits.is_empty(), "nothing failed either");
}

#[test]
fn an_old_preview_keeps_its_unit_origin_and_a_new_one_round_trips() {
    // OpenSpec `ai-import-decision-outfit-continuity`: the origin gained two
    // values, so a preview stored with the former unit form must keep loading
    // (`explicit_quote` / `derived`) while a Pass-2 row round-trips. The origin
    // is a plain wire STRING and the provenance rides alongside it — a mixed
    // enum made the generated client undecodable (review finding).
    let old = r#"{"character_name":"BEN","name":"Zivil-Look","source_quote":"in Zivil","origin":"derived"}"#;
    let parsed: DraftOutfit = serde_json::from_str(old).expect("old row parses");
    assert_eq!(parsed.origin, DraftOutfitOrigin::Derived);
    assert!(parsed.provenance.is_none());

    let continued = DraftOutfit {
        character_name: "BEN".to_owned(),
        name: "Zivil-Look".to_owned(),
        notes: None,
        source_quote: String::new(),
        origin: DraftOutfitOrigin::ContinuedFromScene,
        provenance: Some(DraftOutfitProvenance {
            source_draft_ref: Some("row-4".to_owned()),
            source_scene_number: Some(4),
            confidence: 0.82,
        }),
        pieces: Vec::new(),
    };
    let wire = serde_json::to_value(&continued).expect("serializes");
    assert_eq!(
        wire["origin"], "continued_from_scene",
        "the origin must stay a plain string: a mixed enum breaks the generated client"
    );
    assert_eq!(wire["provenance"]["source_draft_ref"], "row-4");
    let round_trip: DraftOutfit = serde_json::from_value(wire).expect("round-trips");
    assert_eq!(round_trip, continued);
    assert!(round_trip.origin.is_continuation());
    assert_eq!(
        round_trip
            .provenance
            .as_ref()
            .and_then(DraftOutfitProvenance::continuation_source),
        Some(("row-4", Some(4)))
    );
    assert_eq!(round_trip.origin.as_str(), "continued_from_scene");
}

#[test]
fn an_uncertainty_without_candidates_keeps_the_wire_shape() {
    // Additive by contract: the candidates field is skipped when empty, so a
    // client (and a stored preview) sees exactly the pre-change shape.
    let uncertainty = Uncertainty {
        scene_index: 1,
        field: "location".to_owned(),
        note: "unclear".to_owned(),
        suggested_value: None,
        kind: UncertaintyKind::FieldAmbiguity,
        candidates: Vec::new(),
    };
    let json = serde_json::to_string(&uncertainty).expect("serializes");
    assert!(!json.contains("candidates"), "{json}");
}

#[test]
fn a_beat_ordinal_comes_from_the_preview_not_the_review_decisions() {
    // Review finding: the beat mapping address must be the figure's position in
    // the IMMUTABLE preview. A plan-derived position would shift as soon as the
    // reviewer accepts an outfit they rejected before, and the shifted row would
    // then find the other row's confirmed mapping row and silently get no beat.
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![
            continuity_scene("s1", &["BEN"], vec![explicit_outfit("BEN", "Zivil-Look")]),
            continuity_scene("s2", &["BEN"], vec![explicit_outfit("BEN", "Overall")]),
        ],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let mappings = |reject_first: bool| {
        vec![
            ApplyMapping {
                draft_ref: "s1".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: if reject_first {
                    vec![OutfitDecision {
                        ordinal: 0,
                        accepted: false,
                    }]
                } else {
                    Vec::new()
                },
            },
            ApplyMapping {
                draft_ref: "s2".to_owned(),
                decision: ApplyMappingDecision::Create,
                outfit_decisions: Vec::new(),
            },
        ]
    };
    let plan = |reject_first: bool| {
        plan_scene_apply(
            &preview,
            &mappings(reject_first),
            EpisodeId::new(),
            None,
            AiImportJobId(Uuid::now_v7()),
            &ReviewerDecisions {
                continuity_selections: &[],
                episode_groups: &[],
                shooting_days: &[],
                acknowledged_uncertainties: &[],
                categories: &[],
            },
        )
        .expect("plan")
    };

    let all_accepted = plan(false);
    assert_eq!(all_accepted.scenes[0].outfits[0].beat_ordinal, 0);
    assert_eq!(all_accepted.scenes[1].outfits[0].beat_ordinal, 1);

    let first_rejected = plan(true);
    assert!(first_rejected.scenes[0].outfits.is_empty(), "row rejected");
    assert_eq!(
        first_rejected.scenes[1].outfits[0].beat_ordinal, 1,
        "the later row keeps its address even though the earlier one planned no beat"
    );
}

#[test]
fn a_continuity_selection_is_addressed_by_the_draft_figure_position() {
    // The selection is request-carried, so its address must come from something
    // immutable: the figure's position in the draft's own character list.
    let preview = ScriptContext {
        block_number: None,
        title: None,
        scenes: vec![
            continuity_scene("s1", &["BEN"], vec![explicit_outfit("BEN", "Zivil-Look")]),
            continuity_scene("s2", &["ANNA", "BEN"], Vec::new()),
        ],
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    };
    let selections = [OutfitContinuitySelection {
        scene_index: 1,
        character_identity: "ben".to_owned(),
        candidate: OutfitContinuityCandidate::Continued,
    }];
    let plan = plan_continuity(&preview, &selections).expect("plan");
    let outfit = &plan.scenes[1].outfits[0];
    assert!(
        outfit.from_continuity_selection,
        "a selected gap row is marked as synthesised"
    );
    assert_eq!(
        outfit.ordinal, 1,
        "BEN is the second figure of the row, so its address is 1"
    );
    assert_eq!(outfit.beat_ordinal, outfit.ordinal);
}

/// Issue #758: a preview stored before the scene reconciliation counters
/// existed still deserializes — the counters default to `0`, which a client
/// renders as "not recorded" instead of inventing a ratio.
#[test]
fn stored_script_context_without_reconciliation_counters_still_loads() {
    let stored = serde_json::json!({
        "title": "Erlösung",
        "scenes": [],
        "uncertainties": [],
    });
    let context: ScriptContext =
        serde_json::from_value(stored).expect("a pre-#758 preview payload must still load");
    assert_eq!(context.scenes_detected, 0);
    assert_eq!(context.scenes_extracted, 0);
    assert_eq!(context.scenes_synthesized, 0);
}

/// The counters are server-derived reconciliation data, so they must survive
/// the payload round trip — the preview header reads them off the stored blob.
#[test]
fn reconciliation_counters_round_trip_through_the_preview_payload() {
    let context = ScriptContext {
        block_number: None,
        title: None,
        scenes: Vec::new(),
        uncertainties: Vec::new(),
        scenes_detected: 57,
        scenes_extracted: 4,
        scenes_synthesized: 53,
    };
    let encoded = serde_json::to_string(&context).expect("preview payload is serializable");
    assert!(encoded.contains("\"scenes_detected\":57"));
    let decoded: ScriptContext = serde_json::from_str(&encoded).expect("payload round trips");
    assert_eq!(decoded, context);
}

// ===========================================================================
// Zone-aware segmentation (ADR-041 D3/D7, issue #959)
// ===========================================================================

use crate::ai::document::{BlockKind, NormalizedBBox, StructuredDocument, StructuredPage};

/// One page carrying `text` in the body band (left margin, no indentation).
fn zoning_page(number: u32, text: &str) -> StructuredPage {
    let mut page = StructuredPage::new(number, 595.0, 842.0);
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.12, 0.90, 0.85),
        text,
    );
    page
}

/// The `SCRIPT REPORT` index page: one heading per scene plus its day column.
fn index_page(number: u32, scenes: u32) -> StructuredPage {
    let mut text = String::from("SCRIPT REPORT\n");
    for scene in 1..=scenes {
        text.push_str(&format!("{scene} I/T - ORT {scene}\nTag 1\n"));
    }
    zoning_page(number, &text)
}

/// A script-body page: `scenes` headings, each with a full-length action line.
fn body_page(number: u32, scenes: impl Iterator<Item = u32>) -> StructuredPage {
    let mut text = String::new();
    for scene in scenes {
        text.push_str(&format!(
            "{scene} I/T - DREHORT {scene}\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.\n"
        ));
    }
    zoning_page(number, &text)
}

/// The observed broadcast layout, scaled down: cover, cast list, `SCRIPT REPORT`
/// index `1..=scene_count`, two `SYNOPSIS` pages, then body pages carrying the
/// same scenes plus a page-break continuation banner.
fn zoning_fixture(scene_count: u32, body_scene_count: u32) -> StructuredDocument {
    let title = zoning_page(1, "(294) \"Freundschaft\"\nBlock: 098/Ep.: 294");
    let cast = zoning_page(2, "PERSONEN/ HAUPTCAST\nDr. Koch\nLEYLA\nKOMPARSEN\nJonas");
    let index = index_page(3, scene_count);
    let synopsis_one = zoning_page(
        4,
        "SYNOPSIS\nLeyla kehrt nach zwanzig Jahren in die Klinik zurück und trifft dort auf den Mann, der ihr Leben zerstört hat.",
    );
    let synopsis_two = zoning_page(
        5,
        "MEDIZINISCHE FÄLLE\nDie junge Ärztin übernimmt die Station und gerät zwischen die Fronten der beiden Chefärzte.",
    );
    // The body: two scenes per page, with a continuation banner between them.
    let mut pages = vec![title, cast, index, synopsis_one, synopsis_two];
    let mut next_page = 6_u32;
    let mut scene = 1_u32;
    while scene <= body_scene_count {
        let upper = (scene + 1).min(body_scene_count);
        let mut text = String::new();
        for number in scene..=upper {
            text.push_str(&format!(
                "{number} I/T - DREHORT {number}\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.\n"
            ));
        }
        // A page-turn banner must never reach the chunk text.
        text.push_str(&format!("{upper} CONTINUED: (2)\n"));
        pages.push(zoning_page(next_page, &text));
        next_page += 1;
        scene = upper + 1;
    }
    StructuredDocument::new("poppler-spatial-v1", pages)
}

#[test]
fn a_multi_zone_screenplay_yields_one_chunk_per_body_scene_and_no_front_matter() {
    let document = zoning_fixture(42, 42);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(
        segmented.chunks.len(),
        42,
        "only `ScriptBody` scenes make chunks: the index lists the same 42"
    );
    for chunk in &segmented.chunks {
        for leaked in [
            "SYNOPSIS",
            "MEDIZINISCHE FÄLLE",
            "SCRIPT REPORT",
            "HAUPTCAST",
            "Block: 098",
            "CONTINUED",
            "zwanzig Jahren",
            "zwischen die Fronten",
        ] {
            assert!(
                !chunk.text.contains(leaked),
                "chunk {:?} leaked front matter {leaked:?}: {:?}",
                chunk.heading,
                chunk.text
            );
        }
        assert!(
            !chunk.text.contains("CONTINUED"),
            "the page-turn banner must be stripped: {:?}",
            chunk.text
        );
    }
    // The last scene must not swallow six pages of synopsis (the bug this change
    // exists for): its text is its own action line and nothing else.
    let last = segmented.chunks.last().expect("42 chunks");
    assert_eq!(last.scene_number, Some(42));
    assert!(
        last.text.lines().count() <= 2,
        "scene 42 carries its own prose only: {:?}",
        last.text
    );
    // Header harvest: the block number comes from a page that carries no scene.
    assert_eq!(segmented.block_number, Some(98));
    assert_eq!(
        segmented.chunks[0]
            .episode
            .as_ref()
            .and_then(|ep| ep.number),
        Some(294)
    );
    assert_eq!(
        segmented.chunks[0]
            .episode
            .as_ref()
            .and_then(|ep| ep.title.as_deref()),
        Some("Freundschaft")
    );
    // Index and body agree, so there is no structural uncertainty at all.
    assert!(segmented.uncertainties.is_empty());
}

#[test]
fn a_scene_missing_from_the_body_is_reported_against_the_index() {
    // The index lists 42 scenes, the body contains only 41: the old pipeline
    // silently produced a 41-row preview, leaving the reviewer to guess.
    let document = zoning_fixture(42, 41);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 41);
    assert_eq!(
        segmented.uncertainties.len(),
        1,
        "{:?}",
        segmented.uncertainties
    );
    let uncertainty = &segmented.uncertainties[0];
    assert_eq!(uncertainty.field, "scene_number");
    assert_eq!(uncertainty.suggested_value.as_deref(), Some("42"));
    assert_eq!(uncertainty.kind, UncertaintyKind::FieldAmbiguity);
    assert!(
        uncertainty.note.contains("missing from the script body"),
        "note must name the drift: {}",
        uncertainty.note
    );
    // The finding sits next to the last row, not on row 0.
    assert_eq!(uncertainty.scene_index, 40);
}

#[test]
fn a_body_scene_absent_from_the_index_is_reported_too() {
    // Same fixture, but the index stops at 41 while the body has 42.
    let document = zoning_fixture(41, 42);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 42);
    assert_eq!(
        segmented.uncertainties.len(),
        1,
        "{:?}",
        segmented.uncertainties
    );
    let uncertainty = &segmented.uncertainties[0];
    assert_eq!(uncertainty.field, "scene_number");
    assert_eq!(uncertainty.suggested_value.as_deref(), Some("42"));
    assert_eq!(uncertainty.scene_index, 41);
    assert!(uncertainty.note.contains("not in the scene index"));
}

/// A page whose first block is a running header, so an episode marker can sit
/// where the real documents print it.
fn page_with_header(number: u32, header: &str, text: &str) -> StructuredPage {
    let mut page = StructuredPage::new(number, 595.0, 842.0);
    page.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.10, 0.03, 0.60, 0.06),
        header,
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.12, 0.90, 0.85),
        text,
    );
    page
}

#[test]
fn a_body_scene_without_a_day_column_inherits_its_own_index_day() {
    // CodeRabbit review (data integrity): the index states `Tag 1` for scene 1
    // and `Tag 2` for scene 2, the body states no day at all. Harvesting the
    // index columns into ONE day-in-effect left the last index day on every body
    // scene, so scene 1 was planned on day 2.
    let index = zoning_page(
        1,
        "SCRIPT REPORT\n1 I/T - ORT 1\nTag 1\n2 I/T - ORT 2\nTag 2",
    );
    let body = zoning_page(
        2,
        "1 I/T - DREHORT 1\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.\n\
         2 I/T - DREHORT 2\nMatteo hebt den Rucksack auf und nickt ihr langsam zu.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![index, body]);
    let segmented = extract_scenes_from_structured(&document);
    let days: Vec<Option<i32>> = segmented
        .chunks
        .iter()
        .map(|chunk| chunk.shooting_day.as_ref().and_then(|day| day.number))
        .collect();
    assert_eq!(days, vec![Some(1), Some(2)], "{:?}", segmented.chunks);
    // The index and the body agree on both labels, so no uncertainty is raised.
    assert!(
        segmented.uncertainties.is_empty(),
        "{:?}",
        segmented.uncertainties
    );
}

#[test]
fn a_body_day_column_still_wins_over_the_index() {
    // The body is authoritative about its own day: a page header `Tag 3` must
    // keep beating the `Tag 1` the index lists for the same scene.
    let index = zoning_page(1, "SCRIPT REPORT\n1 I/T - ORT 1\nTag 1");
    let body = page_with_header(
        2,
        "Block 098 Ep.: 294/1",
        "Tag 3\n1 I/T - DREHORT 1\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![index, body]);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(
        segmented.chunks[0]
            .shooting_day
            .as_ref()
            .and_then(|day| day.number),
        Some(3),
        "{:?}",
        segmented.chunks
    );
}

#[test]
fn an_inherited_body_day_never_beats_the_index_day_of_its_own_scene() {
    // CodeRabbit review: scene 1 states `Tag 1` in the body, scene 2 states
    // nothing. Inheriting the day in effect dated scene 2 as `Tag 1` even though
    // the index lists `Tag 2` for it — an INHERITED day is not this scene's day.
    let index = zoning_page(
        1,
        "SCRIPT REPORT\n1 I/T - ORT 1\nTag 1\n2 I/T - ORT 2\nTag 2",
    );
    let body = zoning_page(
        2,
        "1 I/T - DREHORT 1\nTag 1\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.\n\
         2 I/T - DREHORT 2\nMatteo hebt den Rucksack auf und nickt ihr langsam zu.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![index, body]);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(
        segmented.chunks[0]
            .shooting_day
            .as_ref()
            .and_then(|day| day.number),
        Some(1)
    );
    assert_eq!(
        segmented.chunks[1]
            .shooting_day
            .as_ref()
            .and_then(|day| day.number),
        Some(2),
        "scene 2 inherits nothing: its index entry says Tag 2"
    );
}

#[test]
fn a_top_band_slug_the_spatial_adapter_tags_as_header_still_starts_a_scene() {
    // The spatial adapter tags EVERY top-band block `PageHeader`
    // (`crates/infra/src/ai/spatial_pdf.rs`), so the band alone cannot decide:
    // a slug printed at the very top of a page is scene content, a running header
    // is not. Without the promotion the whole first scene of such a page is lost.
    let mut page = StructuredPage::new(1, 595.0, 842.0);
    page.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.092, 0.033, 0.551, 0.046),
        "In aller Freundschaft - Die jungen Ärzte",
    );
    page.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.776, 0.033, 0.900, 0.058),
        "Block 098\nEp.: 294/1",
    );
    page.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.100, 0.070, 0.900, 0.088),
        "12 A/T - MALERISCHER BAUERNHOF",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.100, 0.120, 0.900, 0.400),
        "Leyla steigt aus dem Wagen und blickt über den Hof.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![page]);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 1, "{:?}", segmented.chunks);
    assert_eq!(
        segmented.chunks[0].heading,
        "12 A/T - MALERISCHER BAUERNHOF"
    );
    assert_eq!(segmented.chunks[0].scene_number, Some(12));
    assert_eq!(
        segmented.chunks[0].text,
        "Leyla steigt aus dem Wagen und blickt über den Hof."
    );
}

#[test]
fn a_page_header_day_never_redates_the_previous_pages_last_scene() {
    // CodeRabbit review: page 1 ends with a scene (still "freshly opened" when
    // page 2 starts), page 2 opens with a running header stating `Tag 2`. A
    // HEADER line dates the scenes that follow it, never the previous page's
    // last scene.
    let mut first = StructuredPage::new(1, 595.0, 842.0);
    first.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.12, 0.90, 0.85),
        "1 I/T - ORT\nTag 1\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.",
    );
    let mut second = StructuredPage::new(2, 595.0, 842.0);
    second.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.10, 0.030, 0.60, 0.058),
        "Block 098 Ep.: 294/2",
    );
    second.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.10, 0.062, 0.40, 0.080),
        "Tag 2",
    );
    second.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.12, 0.90, 0.85),
        "2 I/T - FLUR\nMatteo hebt den Rucksack auf und nickt ihr langsam zu.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![first, second]);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 2, "{:?}", segmented.chunks);
    assert_eq!(
        segmented.chunks[0]
            .shooting_day
            .as_ref()
            .and_then(|day| day.number),
        Some(1),
        "the page-2 header must not re-date the page-1 scene"
    );
    assert_eq!(
        segmented.chunks[1]
            .shooting_day
            .as_ref()
            .and_then(|day| day.number),
        Some(2),
        "the header still dates the scenes that follow it"
    );
}

#[test]
fn a_scene_label_is_reconciled_within_its_episode() {
    // CodeRabbit review: episodes 294 and 295 both contain a scene `1`. A
    // label-only comparison called the pair reconciled as soon as ONE of them
    // existed, so a scene missing from episode 295 was never reported.
    let index = zoning_page(1, "SCRIPT REPORT\nBlock 098 Ep.: 294/1\n1 I/T - ORT 1");
    let body_294 = zoning_page(
        2,
        "1 I/T - DREHORT 1\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.",
    );
    let body_295 = zoning_page(
        3,
        "Ep.: 295\n1 I/T - DREHORT 1\nMatteo hebt den Rucksack auf und nickt ihr langsam zu.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![index, body_294, body_295]);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 2);
    assert_eq!(
        segmented.uncertainties.len(),
        1,
        "episode 295's scene 1 is NOT the scene the index lists: {:?}",
        segmented.uncertainties
    );
    let uncertainty = &segmented.uncertainties[0];
    assert_eq!(uncertainty.field, "scene_number");
    assert_eq!(uncertainty.scene_index, 1);
    assert!(uncertainty.note.contains("not in the scene index"));
}

#[test]
fn an_unscoped_index_still_matches_on_the_label_alone() {
    // The counterpart: an index that states no episode is compared by label, so
    // an episode-scoped body does not drown the reviewer in false findings.
    let index = zoning_page(1, "SCRIPT REPORT\n1 I/T - ORT 1");
    let body = zoning_page(
        2,
        "Ep.: 295\n1 I/T - DREHORT 1\nMatteo hebt den Rucksack auf und nickt ihr langsam zu.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![index, body]);
    let segmented = extract_scenes_from_structured(&document);
    assert!(
        segmented.uncertainties.is_empty(),
        "{:?}",
        segmented.uncertainties
    );
}

#[test]
fn a_body_without_scene_numbers_reports_the_unreconciled_index_once() {
    // CodeRabbit review: the index lists numbered scenes, the body headings state
    // none (`INT. ROOM - DAY`). The old guard returned no finding at all, so a
    // scene listed by the index looked "present".
    let index = zoning_page(1, "SCRIPT REPORT\n1 I/T - ORT 1\n2 I/T - ORT 2");
    let body = zoning_page(
        2,
        "INT. KÜCHE - TAG\nLeyla geht langsam über den Hof und bleibt vor der Tür stehen.\n\
         EXT. HOF - NACHT\nMatteo hebt den Rucksack auf und nickt ihr langsam zu.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![index, body]);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 2);
    assert_eq!(
        segmented.uncertainties.len(),
        1,
        "one document-level finding, not one per index row: {:?}",
        segmented.uncertainties
    );
    let uncertainty = &segmented.uncertainties[0];
    assert_eq!(uncertainty.field, "scene_number");
    assert_eq!(uncertainty.scene_index, 0);
    assert_eq!(uncertainty.suggested_value, None);
    assert!(
        uncertainty.note.contains("could not be reconciled"),
        "{}",
        uncertainty.note
    );
}

#[test]
fn combined_plus_and_slash_headings_split_and_normalize_to_the_canonical_mood() {
    let mut body = zoning_page(
        1,
        "3 A+I/T - STRASSE + KLINIKUM\nLeyla steigt aus dem Wagen und blickt über den Hof.",
    );
    body.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.60, 0.90, 0.80),
        "42 I+A/T - HAUPTEINGANG\nSie geht langsam durch die Tür und schweigt.",
    );
    let document = StructuredDocument::new("poppler-spatial-v1", vec![body]);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(
        segmented.chunks.len(),
        2,
        "both combined headings are scene boundaries: {:?}",
        segmented
            .chunks
            .iter()
            .map(|chunk| chunk.heading.clone())
            .collect::<Vec<_>>()
    );
    assert_eq!(segmented.chunks[0].scene_number, Some(3));
    assert_eq!(segmented.chunks[0].mood.as_deref(), Some("I/A/T"));
    assert_eq!(segmented.chunks[1].scene_number, Some(42));
    assert_eq!(segmented.chunks[1].mood.as_deref(), Some("I/A/T"));
}

#[test]
fn an_abend_token_never_reads_as_a_second_location() {
    // CodeRabbit review: the combined-form grammar treated the `A` of `I/AB` as a
    // second location and then demanded another `/`, so every `I/AB` (Innen,
    // Abend) heading was silently merged into its predecessor.
    for (heading, mood) in [
        ("2 I/AB - KÜCHE", "I/AB"),
        ("2 A/AB - KÜCHE", "A/AB"),
        ("2 I/AB - KÜCHE/THEKE", "I/AB"),
        ("2 I/A/AB - KÜCHE", "I/A/AB"),
    ] {
        assert!(is_scene_heading(heading), "{heading:?} must stay a heading");
        assert_eq!(
            parse_mood_from_heading(heading).as_deref(),
            Some(mood),
            "mood of {heading:?}"
        );
    }
    // `A/I` names two locations and no time of day: no heading, no mood — that
    // rejection is deliberate, not an accident of the old branch.
    assert!(!is_scene_heading("2 A/I - STRASSE"));
    assert_eq!(parse_mood_from_heading("2 A/I - STRASSE"), None);
    // And a word that merely starts with the letters stays rejected.
    assert!(!is_scene_heading("2 I/TAXI - KÜCHE"));

    // End to end: the `I/AB` scene starts its own chunk instead of vanishing into
    // the previous scene's text.
    let chunks =
        SceneChunk::extract_scenes("1 I/T - BAUERNHOF\nAktion.\n\n2 I/AB - KÜCHE\nAktion.");
    assert_eq!(chunks.len(), 2, "{chunks:?}");
    assert_eq!(chunks[1].mood.as_deref(), Some("I/AB"));
}

#[test]
fn every_combined_heading_spelling_normalizes_to_the_same_mood() {
    for (heading, expected) in [
        ("3 A+I/T - STRASSE", Some("I/A/T")),
        ("3 I+A/T - STRASSE", Some("I/A/T")),
        ("3 A/I/T - STRASSE", Some("I/A/T")),
        ("3 I/A/T - STRASSE", Some("I/A/T")),
        ("3 A+I/N - STRASSE", Some("I/A/N")),
        ("3 I/T - STRASSE", Some("I/T")),
        ("3 A/N - STRASSE", Some("A/N")),
        // Not headings / not moods: a location pair without a time token, and a
        // heading without any parsable time token.
        ("3 A/I - STRASSE", None),
        ("3 I/TAGES - STRASSE", None),
    ] {
        assert_eq!(
            parse_mood_from_heading(heading),
            expected.map(str::to_owned),
            "mood of {heading:?}"
        );
    }
}

#[test]
fn a_page_break_never_fuses_the_last_line_with_the_next_heading() {
    // The spatial adapter's last block on a page carries no trailing newline; the
    // line-based scanner had to rewrite form feeds into newlines to avoid
    // `"Goodbye.2 EXT. PARK - DAY"`. Block slicing makes that structurally
    // impossible — assert it, because a regression here silently loses a scene.
    let first = zoning_page(1, "1 INT. KITCHEN - DAY\nGoodbye.");
    let second = zoning_page(2, "2 EXT. PARK - DAY\nAlice waits.");
    let document = StructuredDocument::new("poppler-spatial-v1", vec![first, second]);
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 2);
    assert_eq!(segmented.chunks[0].text, "Goodbye.");
    assert_eq!(segmented.chunks[1].heading, "2 EXT. PARK - DAY");
    assert_eq!(segmented.chunks[1].text, "Alice waits.");
}

#[test]
fn the_plan_records_the_accepted_zones_and_cut_anchors() {
    let document = zoning_fixture(4, 4);
    let segmented = extract_scenes_from_structured(&document);
    let canonical = segmented.plan_canonical_form();
    assert!(
        canonical.starts_with("P01|title_page|"),
        "plan: {canonical}"
    );
    assert!(canonical.contains("P03|scene_index|"), "plan: {canonical}");
    assert!(canonical.contains("P04|front_matter|"), "plan: {canonical}");
    assert!(
        canonical.contains("P06|script_body|P06.B00"),
        "plan: {canonical}"
    );
    // Deterministic: the same document segments to the same plan, which is why a
    // retry can resume its stored prefix.
    assert_eq!(
        segmented.plan_canonical_form(),
        extract_scenes_from_structured(&document).plan_canonical_form()
    );
    // And a different ZONING yields a different plan even when the scenes are
    // the same: that is exactly the invalidation the digest must catch.
    let unzoned = StructuredDocument::new("poppler-spatial-v1", vec![body_page(1, 1..=4)]);
    assert_ne!(
        segmented.plan_canonical_form(),
        extract_scenes_from_structured(&unzoned).plan_canonical_form()
    );
}

#[test]
fn the_flat_text_seam_reports_a_constant_anchorless_plan() {
    // The flat seam has no blocks, so its plan must not claim any: a constant
    // canonical form is the honest statement, and it keeps the pre-#959
    // string-level behaviour (the index merge test above relies on it).
    let flat = SegmentedScript::from_flat_text("1 I/T - ORT\nText.");
    assert_eq!(flat.chunks.len(), 1);
    assert_eq!(flat.plan_canonical_form(), "P01|script_body|\n");
    assert!(flat.uncertainties.is_empty());
    assert_eq!(flat.block_number, None);
}

#[test]
fn a_document_without_a_recognised_script_page_still_segments() {
    // Widened fallback: no `ScriptBody` verdict, so every page is scanned rather
    // than the whole import failing with "no scene heading".
    let document = StructuredDocument::new(
        "poppler-spatial-v1",
        vec![zoning_page(
            1,
            "SYNOPSIS\n1 I/T - ORT\nLeyla geht langsam über den Hof und bleibt stehen.",
        )],
    );
    let segmented = extract_scenes_from_structured(&document);
    assert_eq!(segmented.chunks.len(), 1);
    // Widened, but the cut anchor is still recorded: the plan states what the
    // segmentation actually did, not what the zone pass wished for.
    assert_eq!(segmented.plan_canonical_form(), "P01|script_body|P01.B00\n");
}

// Issue #961 — cast-directory precedence, kerning safety and continuity context.

fn p3_cast_directory() -> CastDirectory {
    parse_cast_directory_from_text(
        "PERSONEN/ HAUPTCAST\nDr. Leyla Sherbaz (44)\nMikko Rantala\n\
         EPISODENHAUPTROLLEN\nJonas Weber (8, OT)\nCROSS\nDr. Kai Hoffmann\n\
         KOMPARSEN\nHeiko Neubert\n",
        |_| false,
    )
}

#[test]
fn the_cast_directory_beats_inline_ot_and_unlisted_background_is_strictly_extra() {
    let directory = p3_cast_directory();
    let existing: Vec<ExistingSeasonCharacter> = Vec::new();
    let generic: Vec<String> = Vec::new();
    let (jonas, uncertainty) =
        resolve_character_category("JONAS WEBER (OT)", 0, &directory, &existing, &generic);
    assert_eq!(jonas, CharacterCategory::Guest);
    assert!(uncertainty.is_none(), "a declared section is never a doubt");

    let (heiko, uncertainty) =
        resolve_character_category("Heiko Neubert", 1, &directory, &existing, &generic);
    assert_eq!(heiko, CharacterCategory::Extra);
    assert!(uncertainty.is_none());

    let (kai, uncertainty) =
        resolve_character_category("Dr. Kai Hoffmann", 2, &directory, &existing, &generic);
    assert_eq!(kai, CharacterCategory::Guest);
    assert!(uncertainty.is_none());

    let (leyla, uncertainty) =
        resolve_character_category("LEYLA SHERBAZ", 3, &directory, &existing, &generic);
    assert_eq!(leyla, CharacterCategory::MainCast);
    assert!(
        uncertainty.is_none(),
        "a unique surname token is unambiguous"
    );

    let (passant, uncertainty) =
        resolve_character_category("PASSANT (OT)", 4, &directory, &existing, &generic);
    assert_eq!(passant, CharacterCategory::Extra);
    assert!(
        uncertainty.is_none(),
        "zero false-positive guest promotions"
    );

    let (unknown, uncertainty) =
        resolve_character_category("ANNA", 5, &directory, &existing, &generic);
    assert_eq!(unknown, CharacterCategory::MainCast);
    assert!(
        uncertainty.is_none(),
        "a missing signal is not an ambiguity"
    );
}

#[test]
fn an_existing_season_character_outweighs_inline_markers_but_not_the_cast_sheet() {
    let directory = p3_cast_directory();
    let existing = vec![ExistingSeasonCharacter {
        name: "Anna Schmidt".to_owned(),
        category: CharacterCategory::Guest,
    }];
    let generic: Vec<String> = Vec::new();
    let (anna, _) =
        resolve_character_category("ANNA SCHMIDT (OT)", 0, &directory, &existing, &generic);
    assert_eq!(anna, CharacterCategory::Guest);
    let (jonas, _) = resolve_character_category("JONAS", 1, &directory, &existing, &generic);
    assert_eq!(jonas, CharacterCategory::Guest);
}

#[test]
fn kerning_normalized_quotes_keep_grounded_outfits() {
    use crate::ai::normalize_kerning;

    let directory = p3_cast_directory();
    let raw = "Mik k o in OP";
    let normalized = normalize_kerning(raw, &directory);
    assert_eq!(normalized, "Mikko in OP");
    assert_eq!(
        normalize_kerning("Der Arzt geht in den OP.", &directory),
        "Der Arzt geht in den OP."
    );
    let mut scene = DraftScene {
        characters: vec![DraftCharacter::from("Mikko")],
        outfits: vec![DraftOutfit {
            character_name: "Mikko".to_owned(),
            name: "OP".to_owned(),
            source_quote: "Mikko in OP".to_owned(),
            ..DraftOutfit::default()
        }],
        ..DraftScene::default()
    };
    let rejected = verify_draft_outfits_with_normalized(&mut scene, raw, &normalized);
    assert!(rejected.is_empty(), "the normalized quote is grounded");
    assert_eq!(scene.outfits.len(), 1);
}

#[test]
fn zero_dialogue_generic_roles_are_extra_and_neighbors_carry_script_day_parity() {
    let chunks =
        SceneChunk::extract_scenes("3 I/T - WOHNUNG\nPFLEGER 2\nANNA (30): Hallo.\n    Ja.\n");
    let roles = zero_dialogue_generic_roles(&chunks);
    assert!(roles.contains(&character_identity("PFLEGER 2")));
    assert!(!roles.contains(&character_identity("ANNA")));

    let neighbors = neighbor_brackets(&chunks);
    assert_eq!(neighbors.len(), chunks.len());
    for bracket in neighbors {
        assert!(bracket.previous_scene.is_none());
        assert!(bracket.next_scene.is_none());
    }
    let context = render_document_context(&p3_cast_directory(), None);
    assert!(context.contains("Jonas Weber [guest]"));
    assert!(context.contains("<document-context>"));
}

#[test]
fn zero_dialogue_generic_roles_treat_inline_dialogue_as_speech() {
    let speaking = SceneChunk::extract_scenes("3 I/T - WOHNUNG\nPFLEGER 2: Hallo.\n");
    assert!(
        !zero_dialogue_generic_roles(&speaking).contains(&character_identity("PFLEGER 2")),
        "a cue with dialogue on its own line speaks"
    );

    let silent = SceneChunk::extract_scenes("3 I/T - WOHNUNG\nPFLEGER 2:\n");
    assert!(
        zero_dialogue_generic_roles(&silent).contains(&character_identity("PFLEGER 2")),
        "a cue with no dialogue keeps the Extra fallback"
    );

    let mixed = SceneChunk::extract_scenes(
        "3 I/T - WOHNUNG\nPFLEGER 2:\n\
         PFLEGER 2: Ich begleite Sie jetzt zurück auf Ihr Zimmer.\n",
    );
    assert!(
        !zero_dialogue_generic_roles(&mixed).contains(&character_identity("PFLEGER 2")),
        "the 40-char cap applies to the cue, not to inline dialogue"
    );
}

#[test]
fn a_parenthetical_cue_hits_duplicate_exact_directory_entries() {
    let entry = |section: &str, category: CharacterCategory| CastDirectoryEntry {
        canonical_name: "Jonas Weber".to_owned(),
        normalized_identity: "jonas weber".to_owned(),
        declared_category: category,
        raw_section: section.to_owned(),
        inline_ot: false,
    };
    let directory = CastDirectory::new(vec![
        entry("GASTROLLEN", CharacterCategory::Guest),
        entry("KOMPARSEN", CharacterCategory::Extra),
    ]);
    let (category, uncertainty) =
        resolve_character_category("JONAS WEBER (OT)", 0, &directory, &[], &[]);
    assert_eq!(category, CharacterCategory::Guest);
    let uncertainty = uncertainty.expect("two sections for one name are a real conflict");
    assert!(uncertainty.note.contains("guest vs extra"));
}

#[test]
fn neighbor_script_day_parity_uses_the_group_key_not_the_display_label() {
    let day = |number: i32, label: &str| DraftShootingDay {
        number: Some(number),
        label: Some(label.to_owned()),
        score: None,
    };
    let chunk = |index: usize, shooting_day: DraftShootingDay| SceneChunk {
        index,
        heading: format!("{index} I/T - OP"),
        scene_number: u32::try_from(index).ok(),
        episode: None,
        shooting_day: Some(shooting_day),
        mood: None,
        text: String::new(),
    };
    let chunks = vec![
        chunk(0, day(1, "Tag 1")),
        chunk(1, day(2, "Tag 2")),
        chunk(2, day(1, "Day 1")),
        chunk(3, day(1, "Tag 1")),
    ];
    let brackets = neighbor_brackets(&chunks);
    assert_eq!(
        brackets[0]
            .next_scene
            .as_ref()
            .and_then(|scene| scene.script_day.as_deref()),
        Some("Tag 2")
    );
    assert!(
        !brackets[0]
            .next_scene
            .as_ref()
            .is_some_and(|scene| scene.same_script_day),
        "day 1 and day 2 are different days"
    );
    let previous = brackets[3]
        .previous_scene
        .as_ref()
        .expect("a previous scene exists");
    assert_eq!(previous.script_day.as_deref(), Some("Day 1"));
    assert!(
        previous.same_script_day,
        "both scenes are day 1 regardless of their display label: {previous:?}"
    );
}

// ===========================================================================
// Issue #960 — [P4] Multimodal schedule carry-over, shot suffixes & cast legend
// ===========================================================================

#[test]
fn shot_suffixed_schedule_row_merges_onto_owning_scene_and_non_episode_units_stay_unmatched() {
    let ep300 = EpisodeId::new();
    let episodes = std::collections::HashMap::from([(ep300, 300)]);

    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![
                SchedulePageRow {
                    row_ref: "300.37".into(),
                    scene_ref: Some("300.37".into()),
                    shooting_day_label: Some("7. Drehtag: Mo. 25.10.2021".into()),
                    date: None,
                    location: Some("KLINIKUM / OP / OP".into()),
                    order: Some(1),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "300.37N".into(),
                    scene_ref: Some("300.37N".into()),
                    shooting_day_label: Some("6. Drehtag: Sa. 23.10.2021".into()),
                    date: None,
                    location: Some("KLINIKUM / OP / OP".into()),
                    order: Some(2),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "SB7.2".into(),
                    scene_ref: Some("SB7.2".into()),
                    shooting_day_label: Some("4. Drehtag: Do. 21.10.2021".into()),
                    date: None,
                    location: Some("KLINIKUM / OP / OP".into()),
                    order: Some(3),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "T3".into(),
                    scene_ref: Some("T3".into()),
                    shooting_day_label: Some("4. Drehtag: Do. 21.10.2021".into()),
                    date: None,
                    location: Some("KLINIKUM / STATIONSCOUNTER".into()),
                    order: Some(4),
                    cast_codes: Vec::new(),
                },
            ],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );

    assert_eq!(rows.len(), 4);
    assert_eq!(rows[1].episode_number, Some(300));
    assert_eq!(rows[1].scene_number, Some(37));
    assert_eq!(rows[1].shot_suffix.as_deref(), Some("N"));
    assert_eq!(rows[2].episode_number, None);
    assert_eq!(rows[2].scene_number, None);
    assert_eq!(rows[3].episode_number, None);
    assert_eq!(rows[3].scene_number, None);

    let schedule = ShootingSchedule {
        block_id: None,
        rows,
        cast_legend: carry_over.cast_legend,
    };
    let merged = merge_schedule_to_scenes(&schedule, &[episode_scene(ep300, 37)], &episodes);
    assert_eq!(
        merged.scenes[0].schedule_rows.len(),
        2,
        "both 300.37 and 300.37N attach to Episode 300 Scene 37 without creating a phantom scene"
    );
    assert_eq!(merged.unmatched_schedule_rows.len(), 2);
    let unmatched_refs: Vec<&str> = merged
        .unmatched_schedule_rows
        .iter()
        .map(|row| row.row_ref.as_str())
        .collect();
    assert!(unmatched_refs.contains(&"SB7.2"));
    assert!(unmatched_refs.contains(&"T3"));
}

#[test]
fn schedule_carry_over_preserves_active_day_across_page_breaks_and_skips_drehfrei_banners() {
    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();

    // Page 2 ends under "3. Drehtag: Mi. 20.10.2021".
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![SchedulePageRow {
                row_ref: "298.35".into(),
                scene_ref: Some("298.35".into()),
                shooting_day_label: Some("3. Drehtag: Mi. 20.10.2021 - Vorstopp: 9:05".into()),
                date: None,
                location: Some("WOHNUNG ELIAS".into()),
                order: Some(1),
                cast_codes: Vec::new(),
            }],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );

    // Page 3 begins with 3 rows BEFORE "4. Drehtag: Do. 21.10.2021" and
    // includes a "Drehfrei: So. 24.10.2021" rest-day banner.
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![
                SchedulePageRow {
                    row_ref: "298.42".into(),
                    scene_ref: Some("298.42".into()),
                    shooting_day_label: None,
                    date: None,
                    location: Some("WOHNUNG ELIAS".into()),
                    order: Some(1),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "298.21".into(),
                    scene_ref: Some("298.21".into()),
                    shooting_day_label: None,
                    date: None,
                    location: Some("WOHNUNG ELIAS".into()),
                    order: Some(2),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "300.19".into(),
                    scene_ref: Some("300.19".into()),
                    shooting_day_label: None,
                    date: None,
                    location: Some("WOHNUNG LEYLA + BEN".into()),
                    order: Some(3),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "Drehfrei: So. 24.10.2021".into(),
                    scene_ref: None,
                    shooting_day_label: Some("Drehfrei: So. 24.10.2021".into()),
                    date: Some("2021-10-24".into()),
                    location: None,
                    order: None,
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "300.42".into(),
                    scene_ref: Some("300.42".into()),
                    shooting_day_label: Some("4. Drehtag: Do. 21.10.2021".into()),
                    date: None,
                    location: Some("VOR KLINIKUM / BASKETBALLECKE".into()),
                    order: Some(4),
                    cast_codes: Vec::new(),
                },
            ],
            end_of_page_shooting_day_label: Some("11. Drehtag: Fr. 29.10.2021".into()),
            end_of_page_date: None,
        },
        &mut rows,
    );

    // Page 4 starts with a row that inherits the trailing "11. Drehtag" banner
    // from the bottom of the previous page.
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![SchedulePageRow {
                row_ref: "298.22".into(),
                scene_ref: Some("298.22".into()),
                shooting_day_label: None,
                date: None,
                location: Some("VOR KLINIKUM / PARK".into()),
                order: Some(1),
                cast_codes: Vec::new(),
            }],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );

    assert_eq!(rows.len(), 6, "Drehfrei banner must never emit a row");
    for inherited in &rows[0..4] {
        assert_eq!(
            inherited.shooting_day_label.as_deref(),
            Some("3. Drehtag: Mi. 20.10.2021")
        );
        assert_eq!(inherited.date, Date::new(2021, 10, 20).ok());
    }
    assert_eq!(
        rows[4].shooting_day_label.as_deref(),
        Some("4. Drehtag: Do. 21.10.2021")
    );
    assert_eq!(rows[4].date, Date::new(2021, 10, 21).ok());
    assert_eq!(
        rows[5].shooting_day_label.as_deref(),
        Some("11. Drehtag: Fr. 29.10.2021")
    );
    assert_eq!(rows[5].date, Date::new(2021, 10, 29).ok());
}

#[test]
fn rollen_cast_legend_resolves_modifiers_and_drops_unknown_codes_silently() {
    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: vec![
                ScheduleLegendEntry {
                    code: "2".into(),
                    character_name: "Ben Ahlbeck - Philipp Danne".into(),
                    modifier: ScheduleRoleModifier::None,
                },
                ScheduleLegendEntry {
                    code: "150".into(),
                    character_name: "Zoe (Dummy".into(),
                    modifier: ScheduleRoleModifier::None,
                },
                ScheduleLegendEntry {
                    code: "1040".into(),
                    character_name: "Rafael (Nur Stimme)".into(),
                    modifier: ScheduleRoleModifier::None,
                },
                ScheduleLegendEntry {
                    code: "33".into(),
                    character_name: "Physiotherapeutin (Ot".into(),
                    modifier: ScheduleRoleModifier::None,
                },
            ],
            rows: vec![SchedulePageRow {
                row_ref: "300.8".into(),
                scene_ref: Some("300.8".into()),
                shooting_day_label: Some("5. Drehtag: Fr. 22.10.2021".into()),
                date: None,
                location: Some("KLINIKUM / OP / KREISSSAAL".into()),
                order: Some(1),
                cast_codes: vec!["2, 150, 9999, 1040, 33".into()],
            }],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );

    assert_eq!(carry_over.cast_legend.len(), 4);
    assert_eq!(rows.len(), 1);
    let cast_refs = &rows[0].cast_refs;
    assert_eq!(
        cast_refs,
        &[
            ScheduleCastMember {
                code: "2".into(),
                character_name: "Ben Ahlbeck".into(),
                modifier: ScheduleRoleModifier::None,
            },
            ScheduleCastMember {
                code: "150".into(),
                character_name: "Zoe".into(),
                modifier: ScheduleRoleModifier::Dummy,
            },
            ScheduleCastMember {
                code: "1040".into(),
                character_name: "Rafael".into(),
                modifier: ScheduleRoleModifier::VoiceOnly,
            },
            ScheduleCastMember {
                code: "33".into(),
                character_name: "Physiotherapeutin".into(),
                modifier: ScheduleRoleModifier::ExtraOt,
            },
        ]
    );
}

#[test]
fn stacked_multi_row_cells_preserve_episode_scene_and_unwrapped_location() {
    let mut page = StructuredPage::new(4, 595.0, 842.0);
    // Running header in header band (excluded).
    page.push_block(
        BlockKind::PageHeader,
        NormalizedBBox::new(0.08, 0.03, 0.55, 0.05),
        "Block 100 - In aller Freundschaft",
    );
    // Day banner (just below the header band — a real schedule banner sits at
    // y ≈ 0.081–0.091 of the page, past HEADER_BAND_MAX_Y1).
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.27, 0.091, 0.56, 0.101),
        "6. Drehtag: Sa. 23.10.2021 - Vorstopp: 7:40",
    );
    // Stacked Column 1: "300.33" on line 1, script day "2" directly below on line 2.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.08, 0.12, 0.13, 0.15),
        "300.33\n2",
    );
    // Wrapped center set name + synopsis line.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.30, 0.12, 0.65, 0.16),
        "KLINIKUM / ITS / BEOBACHTUNGSRAUM + ZIM-\nMER ZOE\nOP trotz Risiko!",
    );
    // Cast codes on the right.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.67, 0.12, 0.73, 0.13),
        "2, 4, 50",
    );
    // Drehfrei rest-day banner below.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.40, 0.30, 0.60, 0.32),
        "Drehfrei: So. 24.10.2021",
    );

    let extracted = extract_schedule_page_from_structured(&page);
    assert_eq!(
        extracted.rows.len(),
        1,
        "script day '2' and 'Drehfrei' must not become separate rows"
    );
    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    carry_over.apply_page(extracted, &mut rows);
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].episode_number, Some(300));
    assert_eq!(rows[0].scene_number, Some(33));
    assert_eq!(
        rows[0].location.as_deref(),
        Some("KLINIKUM / ITS / BEOBACHTUNGSRAUM + ZIMMER ZOE")
    );
    assert_eq!(
        rows[0].shooting_day_label.as_deref(),
        Some("6. Drehtag: Sa. 23.10.2021")
    );
}

#[test]
fn pre_p4_stored_schedule_preview_deserializes_with_serde_defaults() {
    let legacy_json = r#"{
        "block_id": null,
        "rows": [
            {
                "row_ref": "row-0",
                "scene_number": 10,
                "episode_number": 294,
                "shooting_day_label": "1. Drehtag",
                "date": "2021-10-18",
                "location": "KLINIKUM",
                "order": 1
            }
        ]
    }"#;
    let decoded: ShootingSchedule =
        serde_json::from_str(legacy_json).expect("pre-P4 JSON schedule preview must deserialize");
    assert!(decoded.cast_legend.is_empty());
    assert_eq!(decoded.rows.len(), 1);
    assert_eq!(decoded.rows[0].episode_number, Some(294));
    assert_eq!(decoded.rows[0].scene_number, Some(10));
    assert_eq!(decoded.rows[0].shot_suffix, None);
    assert!(decoded.rows[0].cast_refs.is_empty());
}

// ===========================================================================
// CodeRabbit review, PR #967 — day-banner transition rule, late legends and
// mixed legend/scene pages
// ===========================================================================

#[test]
fn an_undated_new_day_banner_clears_the_carried_date() {
    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    // Day 1 with a date, one row beneath it.
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![
                SchedulePageRow {
                    row_ref: "300.33".into(),
                    scene_ref: Some("300.33".into()),
                    shooting_day_label: Some("1. Drehtag: Mo. 18.10.2021".into()),
                    date: None,
                    location: None,
                    order: Some(1),
                    cast_codes: Vec::new(),
                },
                // Undated day-2 banner row: the previous date must NOT leak
                // into day 2.
                SchedulePageRow {
                    row_ref: "2. Drehtag:".into(),
                    scene_ref: None,
                    shooting_day_label: None,
                    date: None,
                    location: None,
                    order: Some(2),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "300.40".into(),
                    scene_ref: Some("300.40".into()),
                    shooting_day_label: None,
                    date: None,
                    location: None,
                    order: Some(3),
                    cast_codes: Vec::new(),
                },
            ],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );
    assert_eq!(rows.len(), 2, "the banner row must not emit a scene row");
    assert_eq!(rows[0].date, Some(Date::new(2021, 10, 18).unwrap()));
    assert_eq!(
        rows[1].date, None,
        "day 2 without a stated date must not inherit day 1's date"
    );
}

#[test]
fn an_undated_end_of_page_banner_clears_the_carried_date() {
    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![SchedulePageRow {
                row_ref: "300.33".into(),
                scene_ref: Some("300.33".into()),
                shooting_day_label: Some("1. Drehtag: Mo. 18.10.2021".into()),
                date: None,
                location: None,
                order: Some(1),
                cast_codes: Vec::new(),
            }],
            end_of_page_shooting_day_label: Some("2. Drehtag".into()),
            end_of_page_date: None,
        },
        &mut rows,
    );
    // Next page: an undated row under the new day inherits NO date.
    let mut next_rows = Vec::new();
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![SchedulePageRow {
                row_ref: "300.41".into(),
                scene_ref: Some("300.41".into()),
                shooting_day_label: None,
                date: None,
                location: None,
                order: Some(1),
                cast_codes: Vec::new(),
            }],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut next_rows,
    );
    assert_eq!(
        next_rows[0].date, None,
        "an undated end-of-page day banner must clear the previous day's date"
    );
}

#[test]
fn a_same_day_continuation_banner_keeps_its_date() {
    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![
                SchedulePageRow {
                    row_ref: "300.33".into(),
                    scene_ref: Some("300.33".into()),
                    shooting_day_label: Some("1. Drehtag: Mo. 18.10.2021".into()),
                    date: None,
                    location: None,
                    order: Some(1),
                    cast_codes: Vec::new(),
                },
                // Continuation row reporting the SAME day by number without a
                // date: the date must be retained, not cleared.
                SchedulePageRow {
                    row_ref: "300.35".into(),
                    scene_ref: Some("300.35".into()),
                    shooting_day_label: Some("1. Drehtag".into()),
                    date: None,
                    location: None,
                    order: Some(2),
                    cast_codes: Vec::new(),
                },
            ],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );
    assert_eq!(rows[0].date, Some(Date::new(2021, 10, 18).unwrap()));
    assert_eq!(
        rows[1].date,
        Some(Date::new(2021, 10, 18).unwrap()),
        "the same day continuing without a date keeps its date"
    );
}

#[test]
fn cast_codes_resolve_against_a_legend_from_a_later_page() {
    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    // Page 1: a row casting code "2" before any legend exists, plus an
    // unknown code "99".
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![SchedulePageRow {
                row_ref: "300.33".into(),
                scene_ref: Some("300.33".into()),
                shooting_day_label: None,
                date: None,
                location: None,
                order: Some(1),
                cast_codes: vec!["2".into(), "99".into()],
            }],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );
    // Page 2: the legend finally defines code 2.
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: vec![ScheduleLegendEntry {
                code: "2".into(),
                character_name: "Ben".into(),
                modifier: ScheduleRoleModifier::None,
            }],
            rows: Vec::new(),
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );
    assert!(
        rows[0].cast_refs.is_empty(),
        "page-time resolution cannot know the late legend yet"
    );
    carry_over.finalize_cast_refs(&mut rows);
    assert_eq!(rows[0].cast_refs.len(), 1, "code 99 stays dropped");
    assert_eq!(rows[0].cast_refs[0].character_name, "Ben");
}

#[test]
fn a_page_with_scene_rows_and_a_rollen_legend_keeps_its_rows() {
    let mut page = StructuredPage::new(7, 595.0, 842.0);
    // Scene row at the top of the page.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.08, 0.12, 0.13, 0.15),
        "300.37N",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.30, 0.12, 0.65, 0.16),
        "KLINIKUM / ITS",
    );
    // ROLLEN legend section at the BOTTOM of the same page.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.80, 0.20, 0.82),
        "ROLLEN",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.83, 0.14, 0.90),
        "2\n4",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.16, 0.83, 0.40, 0.90),
        "Ben\nPhilipp",
    );

    let extracted = extract_schedule_page_from_structured(&page);
    assert_eq!(
        extracted.rows.len(),
        1,
        "scene rows above a ROLLEN section must survive the page"
    );
    assert_eq!(extracted.rows[0].row_ref, "300.37N");
    // The legend itself is still extracted from the full page.
    assert_eq!(extracted.legend_entries.len(), 2);
}

#[test]
fn a_legend_only_page_still_returns_no_scene_rows() {
    let mut page = StructuredPage::new(3, 595.0, 842.0);
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.20, 0.20, 0.22),
        "ROLLEN",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.23, 0.14, 0.30),
        "2\n4",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.16, 0.23, 0.40, 0.30),
        "Ben\nPhilipp",
    );
    let extracted = extract_schedule_page_from_structured(&page);
    assert!(
        extracted.rows.is_empty(),
        "a legend-only page must not invent scene rows"
    );
}

#[test]
fn inline_legend_entries_in_the_rollen_heading_block_are_read() {
    let mut page = StructuredPage::new(3, 595.0, 842.0);
    // ONE block containing the heading AND the first legend line.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.20, 0.40, 0.25),
        "ROLLEN\n2 = Ben",
    );
    let extracted = extract_schedule_page_from_structured(&page);
    assert_eq!(
        extracted.legend_entries.len(),
        1,
        "the inline entry inside the heading block must be found"
    );
    assert_eq!(extracted.legend_entries[0].character_name, "Ben");
}

#[test]
fn a_cast_cell_between_two_tight_rows_is_assigned_exactly_once() {
    let mut page = StructuredPage::new(4, 595.0, 842.0);
    // Two scene rows only 0.012 apart — both within the old ±0.015 filter of
    // a cell aligned anywhere between them.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.08, 0.200, 0.13, 0.210),
        "300.33",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.08, 0.212, 0.13, 0.222),
        "300.34",
    );
    // One cast cell aligned between the two rows.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.67, 0.209, 0.73, 0.212),
        "7",
    );

    let extracted = extract_schedule_page_from_structured(&page);
    assert_eq!(extracted.rows.len(), 2);
    let total: usize = extracted.rows.iter().map(|row| row.cast_codes.len()).sum();
    assert_eq!(
        total, 1,
        "one cell must land on exactly ONE row (the nearest), not both"
    );
    assert_eq!(extracted.rows[1].cast_codes, vec!["7".to_owned()]);
}

/// CodeRabbit's PR #967 follow-up: a MIXED legend layout — the heading block
/// merged with one inline entry while OTHER entries land in separate paired
/// blocks — must keep BOTH: the heading-block scan is not gated on
/// `entries.is_empty()` any more.
#[test]
fn mixed_legend_layout_keeps_the_heading_block_entry_and_the_paired_blocks() {
    let mut page = StructuredPage::new(3, 595.0, 842.0);
    // Heading block with an inline entry.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.20, 0.40, 0.25),
        "ROLLEN\n2 = Ben",
    );
    // Separate paired code/name blocks below.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.26, 0.14, 0.31),
        "3",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.16, 0.26, 0.40, 0.31),
        "Alice",
    );

    let extracted = extract_schedule_page_from_structured(&page);
    let mut names: Vec<&str> = extracted
        .legend_entries
        .iter()
        .map(|entry| entry.character_name.as_str())
        .collect();
    names.sort_unstable();
    assert_eq!(
        names,
        vec!["Alice", "Ben"],
        "the heading block entry and the paired block entry both survive: {:?}",
        extracted.legend_entries
    );
}

/// CodeRabbit's PR #967 round-3 follow-up: a BARE numbered German day banner
/// (`"2. Drehtag"`, no colon) is a day banner, not a scene row — otherwise it
/// emits an unmatched row and the previous day (with its date) stays active.
#[test]
fn a_bare_numbered_day_banner_without_a_colon_is_recognized() {
    assert!(is_shooting_day_banner("2. Drehtag"));
    assert!(is_shooting_day_banner("12. Drehtag"));
    assert!(is_shooting_day_banner("2. Drehtag: Mo. 18.10.2021"));
    assert!(is_shooting_day_banner("1. SHOOTING DAY"));
    // Ordinary scene references never match.
    assert!(!is_shooting_day_banner("300.33"));
    assert!(!is_shooting_day_banner("2"));
    assert!(!is_shooting_day_banner("T3"));
    assert!(!is_shooting_day_banner("SB7.2"));

    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![
                SchedulePageRow {
                    row_ref: "300.33".into(),
                    scene_ref: Some("300.33".into()),
                    shooting_day_label: Some("1. Drehtag: Mo. 18.10.2021".into()),
                    date: None,
                    location: None,
                    order: Some(1),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "2. Drehtag".into(),
                    scene_ref: None,
                    shooting_day_label: None,
                    date: None,
                    location: None,
                    order: Some(2),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "300.40".into(),
                    scene_ref: Some("300.40".into()),
                    shooting_day_label: None,
                    date: None,
                    location: None,
                    order: Some(3),
                    cast_codes: Vec::new(),
                },
            ],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );
    assert_eq!(
        rows.len(),
        2,
        "the bare banner row must not emit a scene row"
    );
    assert_eq!(
        rows[1].date, None,
        "day 2 starts without a date: the carried date must be cleared"
    );
}

/// CodeRabbit's PR #967 round-3 follow-up: a separate INLINE block below the
/// heading (`3 = Alice`) is found even when the two-column pairing already
/// produced entries — and paired entries are never duplicated.
#[test]
fn a_separate_inline_legend_block_is_found_alongside_paired_entries() {
    let mut page = StructuredPage::new(3, 595.0, 842.0);
    // Heading block with an inline entry.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.20, 0.40, 0.25),
        "ROLLEN\n2 = Ben",
    );
    // A separate INLINE (not two-column) block below.
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.26, 0.40, 0.31),
        "3 = Alice",
    );

    let extracted = extract_schedule_page_from_structured(&page);
    let mut names: Vec<&str> = extracted
        .legend_entries
        .iter()
        .map(|entry| entry.character_name.as_str())
        .collect();
    names.sort_unstable();
    assert_eq!(
        names,
        vec!["Alice", "Ben"],
        "the heading entry and the separate inline entry both survive: {:?}",
        extracted.legend_entries
    );
}

/// CodeRabbit's PR #967 round-4 follow-up: the period is REQUIRED in the bare
/// banner branch — `"2 Drehtag"` (no period) is not a banner, because
/// `shooting_day_identity` keys numbered days on the `N.` shape and a
/// period-less match would flip-flop the day identity.
#[test]
fn a_period_less_day_banner_text_is_not_a_banner() {
    assert!(!is_shooting_day_banner("2 Drehtag"));
    assert!(!is_shooting_day_banner("12 Drehtag"));
    assert!(is_shooting_day_banner("2. Drehtag"));
}

/// CodeRabbit's PR #967 round-5 follow-up: numbered-day identity is
/// consistent across both written shapes — a `"2 Drehtag:"` continuation
/// (no period, colon form) is the SAME day as `"2. Drehtag: …"` and keeps its
/// date, and a bare `"2 Drehtag:"` row is recognized as a day banner.
#[test]
fn the_period_less_colon_day_form_has_the_same_identity_as_the_numbered_form() {
    assert!(is_shooting_day_banner("2 Drehtag:"));

    let mut carry_over = ScheduleCarryOver::default();
    let mut rows = Vec::new();
    carry_over.apply_page(
        SchedulePageExtraction {
            legend_entries: Vec::new(),
            rows: vec![
                SchedulePageRow {
                    row_ref: "300.33".into(),
                    scene_ref: Some("300.33".into()),
                    shooting_day_label: Some("2. Drehtag: Mo. 19.10.2021".into()),
                    date: None,
                    location: None,
                    order: Some(1),
                    cast_codes: Vec::new(),
                },
                SchedulePageRow {
                    row_ref: "300.35".into(),
                    scene_ref: Some("300.35".into()),
                    shooting_day_label: Some("2 Drehtag:".into()),
                    date: None,
                    location: None,
                    order: Some(2),
                    cast_codes: Vec::new(),
                },
            ],
            end_of_page_shooting_day_label: None,
            end_of_page_date: None,
        },
        &mut rows,
    );
    assert_eq!(rows[0].date, Some(Date::new(2021, 10, 19).unwrap()));
    assert_eq!(
        rows[1].date,
        Some(Date::new(2021, 10, 19).unwrap()),
        "the same day in the period-less colon form keeps its date"
    );
}

/// CodeRabbit's PR #967 round-7 follow-up: a paired NAME block whose text
/// starts with a digit ("2 Polizisten" as the name of code 150) must NOT
/// re-parse as a phantom inline legend entry `2 = Polizisten`.
#[test]
fn paired_name_blocks_are_excluded_from_the_inline_scan() {
    let mut page = StructuredPage::new(3, 595.0, 842.0);
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.20, 0.20, 0.22),
        "ROLLEN",
    );
    // Two-column layout: code column "150", name column "2 Polizisten".
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.10, 0.23, 0.14, 0.30),
        "150",
    );
    page.push_block(
        BlockKind::Paragraph,
        NormalizedBBox::new(0.16, 0.23, 0.40, 0.30),
        "2 Polizisten",
    );

    let extracted = extract_schedule_page_from_structured(&page);
    assert_eq!(
        extracted.legend_entries.len(),
        1,
        "only the paired entry survives, no phantom code-2 entry: {:?}",
        extracted.legend_entries
    );
    assert_eq!(extracted.legend_entries[0].code, "150");
    assert_eq!(extracted.legend_entries[0].character_name, "2 Polizisten");
}
