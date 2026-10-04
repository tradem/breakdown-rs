// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)

use chrono::{TimeZone, Utc};
use uuid::Uuid;

use crate::scene::views::SceneView;
use crate::shared::{AggregateVersion, EpisodeId};

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
        costume_beats: Vec::new(),
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
    let merged = merge_schedule_to_scenes(&schedule, &[scene(1), scene(2)]);
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
            costume_decisions: Vec::new(),
        }],
        EpisodeId::new(),
        None,
        AiImportJobId(Uuid::now_v7()),
        &[],
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
        ensure_script_applyable(&script),
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
            &[]
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
        &[],
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
            costume_decisions: Vec::new(),
        })
        .collect()
}

#[test]
fn planner_plans_the_figures_a_row_names() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec!["BEN".into(), "Leyla".into()],
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
            },
            CharacterApplyPlan {
                ordinal: 1,
                name: "Leyla".into(),
                identity: "leyla".into(),
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
            characters: vec!["   ".into()],
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
    assert!(plan.scenes[0].costumes.is_empty());
}

#[test]
fn planner_plans_one_figure_per_name_even_when_a_row_names_it_twice() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec!["BEN".into(), "Ben ".into()],
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
            characters: vec![" RENEE SANDERS ".into()],
            costumes: vec![costume(
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
        plan.scenes[0].costumes[0].character_identity,
        "renee sanders"
    );
}

#[test]
fn planner_plans_a_costume_bound_to_the_figure_of_the_same_row() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec!["BEN".into()],
            costumes: vec![costume("Ben", "Marineblau", "BEN in Marineblau")],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    assert_eq!(
        plan.scenes[0].costumes,
        vec![CostumeApplyPlan {
            ordinal: 0,
            character_identity: "ben".into(),
            character_name: "BEN".into(),
            description: "Marineblau".into(),
            source_quote: "BEN in Marineblau".into(),
        }]
    );
}

#[test]
fn two_costumes_of_one_figure_in_one_row_keep_distinct_ordinals() {
    // Design D4: without the ordinal both rows would resolve to one mapping row
    // and the second costume would silently never be created.
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec!["BEN".into()],
            costumes: vec![
                costume("Ben", "Marineblau", "BEN in Marineblau"),
                costume("Ben", "Silberkette", "Schmuck: Silberkette"),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    let ordinals: Vec<usize> = plan.scenes[0].costumes.iter().map(|c| c.ordinal).collect();
    assert_eq!(ordinals, vec![0, 1]);
}

#[test]
fn planner_reports_a_costume_whose_figure_the_row_does_not_plan() {
    // `verify_draft_costumes` normally rejects this at extraction; a preview that
    // skipped that step must still not produce an ownerless costume.
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec!["BEN".into()],
            costumes: vec![costume("Anna", "Mantel", "im Mantel")],
            ..Default::default()
        }],
        ..Default::default()
    };
    let plan = plan_of(&preview, &create_decisions(&["1. INT. OP"]));
    assert!(plan.scenes[0].costumes.is_empty());
    assert_eq!(plan.unapplied_costumes.len(), 1);
    assert_eq!(
        plan.unapplied_costumes[0].reason,
        UnappliedCostumeReason::CharacterNotPlanned
    );
    assert_eq!(plan.unapplied_costumes[0].description, "Mantel");
}

#[test]
fn planner_skips_only_the_costume_rows_the_reviewer_rejected() {
    let preview = ScriptContext {
        scenes: vec![DraftScene {
            draft_ref: "1. INT. OP".into(),
            characters: vec!["BEN".into()],
            costumes: vec![
                costume("Ben", "Marineblau", "BEN in Marineblau"),
                costume("Ben", "Silberkette", "Schmuck: Silberkette"),
            ],
            ..Default::default()
        }],
        ..Default::default()
    };
    let mut decisions = create_decisions(&["1. INT. OP"]);
    decisions[0].costume_decisions = vec![CostumeDecision {
        ordinal: 1,
        accepted: false,
    }];
    let plan = plan_of(&preview, &decisions);
    assert_eq!(plan.scenes[0].costumes.len(), 1);
    assert_eq!(plan.scenes[0].costumes[0].ordinal, 0);
    // Rejecting one costume is not a failure, so nothing is reported as
    // unapplied — the reviewer chose that outcome.
    assert!(plan.unapplied_costumes.is_empty());
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
// verify_draft_costumes — grounding + attribution (server-side)
// ===========================================================================

fn costume(char_name: &str, description: &str, quote: &str) -> DraftCostume {
    DraftCostume {
        character_name: char_name.to_owned(),
        description: description.to_owned(),
        source_quote: quote.to_owned(),
    }
}

const CHUNK: &str = "Renee Sanders (39) steigt aus dem Auto, trägt einen leicht \
ölverschmierten Mechaniker-Overall. BEN wartet im Mantel.";

#[test]
fn grounded_costume_for_a_listed_character_is_kept() {
    let mut scene = DraftScene {
        characters: vec!["Renee Sanders".to_owned()],
        costumes: vec![costume(
            "Renee Sanders",
            "ölverschmierter Mechaniker-Overall",
            "ölverschmierten Mechaniker-Overall",
        )],
        ..DraftScene::default()
    };
    scene.costumes[0].source_quote = "ölverschmierten Mechaniker-Overall".to_owned();
    let rejected = verify_draft_costumes(&mut scene, CHUNK);
    assert!(rejected.is_empty(), "expected no rejects, got {rejected:?}");
    assert_eq!(scene.costumes.len(), 1, "the grounded costume must survive");
}

#[test]
fn costume_whose_quote_is_absent_from_the_chunk_is_dropped() {
    let mut scene = DraftScene {
        characters: vec!["Renee Sanders".to_owned()],
        costumes: vec![costume(
            "Renee Sanders",
            "Seidenkleid",
            "trägt ein langes Seidenkleid aus Seide",
        )],
        ..DraftScene::default()
    };
    let rejected = verify_draft_costumes(&mut scene, CHUNK);
    assert!(
        scene.costumes.is_empty(),
        "ungrounded costume must not survive"
    );
    assert_eq!(rejected.len(), 1);
    assert!(matches!(
        rejected[0].reason,
        RejectedCostumeReason::UngroundedQuote
    ));
}

#[test]
fn costume_for_an_unlisted_character_is_dropped() {
    let mut scene = DraftScene {
        characters: vec!["Renee Sanders".to_owned()],
        costumes: vec![costume("Unbekannt", "Mantel", "im Mantel")],
        ..DraftScene::default()
    };
    let rejected = verify_draft_costumes(&mut scene, CHUNK);
    assert!(
        scene.costumes.is_empty(),
        "costume without its figure must not survive"
    );
    assert_eq!(rejected.len(), 1);
    assert!(matches!(
        rejected[0].reason,
        RejectedCostumeReason::UnlistedCharacter
    ));
}

#[test]
fn costume_with_an_empty_quote_is_dropped() {
    let mut scene = DraftScene {
        characters: vec!["Renee Sanders".to_owned()],
        costumes: vec![costume("Renee Sanders", "Mantel", "   ")],
        ..DraftScene::default()
    };
    let rejected = verify_draft_costumes(&mut scene, CHUNK);
    assert!(scene.costumes.is_empty());
    assert_eq!(rejected.len(), 1);
}

#[test]
fn character_matching_ignores_case_and_surrounding_space() {
    // Models are inconsistent about casing ("BEN" vs "Ben"); the script's own
    // name is kept in the costume, only the MATCH is normalised.
    let mut scene = DraftScene {
        characters: vec!["BEN".to_owned()],
        costumes: vec![costume(" ben ", "Mantel", "im Mantel")],
        ..DraftScene::default()
    };
    let rejected = verify_draft_costumes(&mut scene, CHUNK);
    assert!(rejected.is_empty(), "casing must not reject a costume");
    assert_eq!(scene.costumes.len(), 1);
    assert_eq!(scene.costumes[0].character_name, " ben ");
}

#[test]
fn a_quote_that_only_differs_in_line_wrapping_is_still_grounded() {
    // A screenplay wraps action over lines; the model quotes it reflowed. The
    // words are the document's, so this is grounded — and treating it as a
    // hallucination would reject legitimate costumes on every typeset script.
    let wrapped = "Renee steigt aus.\n  einem\n\nAuto, trägt einen leicht ölverschmierten\nMechaniker-Overall.";
    let mut scene = DraftScene {
        characters: vec!["Renee".into()],
        costumes: vec![costume(
            "RENEE",
            "Overall",
            "trägt einen  leicht ölverschmierten Mechaniker-Overall",
        )],
        ..Default::default()
    };
    let rejected = verify_draft_costumes(&mut scene, wrapped);
    assert!(
        rejected.is_empty(),
        "line breaks must not make a real quote ungrounded: {rejected:?}"
    );
    // A word the text does not contain is still rejected.
    scene.costumes = vec![costume("RENEE", "Kleid", "trägt ein langes Seidenkleid")];
    assert_eq!(
        verify_draft_costumes(&mut scene, wrapped).len(),
        1,
        "grounding must not become fuzzy matching"
    );
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
    assert!(ensure_script_applyable(&dropped).is_ok());

    let mut blocking = dropped.clone();
    blocking.uncertainties.push(Uncertainty {
        scene_index: 1,
        field: "location".into(),
        note: "illegible".into(),
        suggested_value: None,
        kind: UncertaintyKind::FieldAmbiguity,
    });
    assert!(matches!(
        ensure_script_applyable(&blocking),
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
        costumes: vec![],
        ..DraftScene::default()
    };
    assert!(verify_draft_costumes(&mut scene, CHUNK).is_empty());
    assert!(scene.costumes.is_empty());
}

#[test]
fn costumes_field_defaults_for_previews_stored_before_it_existed() {
    // Wire compatibility: a stored preview JSON without `costumes` must still
    // deserialise (the field is `#[serde(default)]`).
    let json = r#"{"draft_ref":"1. INT. KITCHEN","characters":["ANNA"]}"#;
    let scene: DraftScene = serde_json::from_str(json).expect("old preview must parse");
    assert!(scene.costumes.is_empty());
    assert_eq!(scene.characters, vec!["ANNA".to_owned()]);
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
    let merged = merge_schedule_to_scenes(&schedule, &[scene(1), scene(2)]);
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
    let merged = merge_schedule_to_scenes(&schedule, &[scene(1), scene(1), scene(2)]);
    assert_eq!(merged.scenes[0].schedule_rows.len(), 1);
    assert_eq!(merged.scenes[1].schedule_rows.len(), 1);
    assert_eq!(merged.scenes[2].schedule_rows.len(), 0);
}

#[test]
fn merge_counts_unmatched_scenes_correctly() {
    let schedule = ShootingSchedule::default();
    let merged = merge_schedule_to_scenes(&schedule, &[scene(1), scene(2), scene(3)]);
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
        costume_decisions: Vec::new(),
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
        &[EpisodeGroupPlan {
            episode_ref: "ep:3".into(),
            target: EpisodeTarget::Create {
                number: 3,
                name: Some("Der Unfall".into()),
            },
        }],
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
        &[EpisodeGroupPlan {
            episode_ref: "ep:3".into(),
            target: EpisodeTarget::Existing {
                episode_id: existing,
            },
        }],
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
        &[],
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
        &[],
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
        &[],
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
