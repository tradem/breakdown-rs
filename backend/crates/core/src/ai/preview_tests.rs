// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use chrono::{TimeZone, Utc};
use uuid::Uuid;

use crate::scene::views::SceneView;
use crate::shared::{AggregateVersion, CostumeCategoryId, EpisodeId};

use super::*;

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
        shooting_day_ids: Vec::new(),
        assigned_characters: Vec::new(),
        outfit_beats: Vec::new(),
        version: AggregateVersion::INITIAL,
        updated_at: Utc.timestamp_opt(0, 0).single().unwrap(),
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
        title: None,
        scenes: vec![DraftScene {
            draft_ref: "scene-1".into(),
            scene_number: Some(1),
            summary: Some("revised".into()),
            ..Default::default()
        }],
        uncertainties: Vec::new(),
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
        uncertainties: vec![Uncertainty {
            scene_index: 0,
            field: "location".into(),
            note: "illegible".into(),
            suggested_value: Some("Kitchen".into()),
            kind: UncertaintyKind::FieldAmbiguity,
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
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![DraftOutfit {
                character_name: "BEN".into(),
                name: "OP".into(),
                notes: None,
                source_quote: "in OP".into(),
                origin: DraftOutfitOrigin::ExplicitQuote,
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
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![DraftOutfit {
                character_name: "BEN".into(),
                name: "OP".into(),
                notes: None,
                source_quote: "in OP".into(),
                origin: DraftOutfitOrigin::ExplicitQuote,
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
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec![DraftCharacter::from("BEN")],
            outfits: vec![DraftOutfit {
                character_name: "BEN".into(),
                name: "OP".into(),
                notes: None,
                source_quote: "in OP".into(),
                origin: DraftOutfitOrigin::ExplicitQuote,
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
        uncertainties: vec![
            Uncertainty {
                scene_index: 1,
                field: "location".into(),
                note: "illegible".into(),
                suggested_value: None,
                kind: UncertaintyKind::FieldAmbiguity,
            },
            Uncertainty {
                scene_index: 2,
                field: "mood".into(),
                note: "two readings".into(),
                suggested_value: None,
                kind: UncertaintyKind::FieldAmbiguity,
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
        uncertainties: vec![Uncertainty {
            scene_index: 3,
            field: "costumes".into(),
            note: "ungrounded quote".into(),
            suggested_value: None,
            kind: UncertaintyKind::DroppedRow,
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
    assert_eq!(uncertainty.field, "category");
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
        field: "category".to_owned(),
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
    assert_eq!(parse_schedule_scene_ref("294.10"), (Some(294), Some(10)));
    assert_eq!(parse_schedule_scene_ref("03.05"), (Some(3), Some(5)));
    // Plain references carry no episode.
    assert_eq!(parse_schedule_scene_ref("10"), (None, Some(10)));
    assert_eq!(parse_schedule_scene_ref("12A"), (None, Some(12)));
    assert_eq!(parse_schedule_scene_ref(" 7 "), (None, Some(7)));
    // Unparseable references degrade to unmatched, never half-match.
    assert_eq!(parse_schedule_scene_ref(""), (None, None));
    assert_eq!(parse_schedule_scene_ref("ABC"), (None, None));
    assert_eq!(parse_schedule_scene_ref("294."), (None, None));
    assert_eq!(parse_schedule_scene_ref(".10"), (None, None));
    assert_eq!(parse_schedule_scene_ref("294.10.5"), (None, None));
    assert_eq!(parse_schedule_scene_ref("99999999999.10"), (None, None));
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
    };
    // The scene's episode is NOT in the map: it is invisible to the
    // episode-bearing row (a pair match against an unknown episode would be
    // a guess, not a join).
    let merged =
        merge_schedule_to_scenes(&schedule, &[episode_scene(EpisodeId::new(), 1)], &episodes);
    assert_eq!(merged.unmatched_schedule_rows.len(), 1);
}
