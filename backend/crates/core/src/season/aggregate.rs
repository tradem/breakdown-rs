// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Season aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeriesId};

use super::commands::{CreateSeason, RenameSeason};
use super::error::SeasonError;
use super::events::SeasonEvent;

/// State persisted by the Season aggregate.
///
/// A Season is scoped to exactly one `SeriesId`. It does NOT own per-Block or
/// per-Episode containment; that is derived from events in the read model.
#[derive(Debug, Clone, Default)]
pub struct SeasonAggregate {
    pub id: Uuid,
    pub series_id: SeriesId,
    pub number: i32,
    pub title: Option<String>,
    pub version: AggregateVersion,
}

impl Entity for SeasonAggregate {
    type ID = Uuid;
    type Event = SeasonEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "season"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for SeasonAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            SeasonEvent::SeasonCreated {
                id,
                series_id,
                number,
                title,
                version,
            } => {
                self.id = id;
                self.series_id = series_id;
                self.number = number;
                self.title = title;
                self.version = version;
            }
            SeasonEvent::SeasonRenamed { title, version, .. } => {
                self.title = title;
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateSeason> for SeasonAggregate {
    type Error = SeasonError;
    fn handle(
        &self,
        cmd: CreateSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // Series-global numbering uniqueness is enforced by a Postgres unique
        // index on (series_id, number) in the projection, NOT here (CQRS
        // write/read split — the aggregate cannot read its siblings).
        Ok(vec![SeasonEvent::SeasonCreated {
            id: cmd.id,
            series_id: cmd.series_id,
            number: cmd.number,
            title: cmd.title,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RenameSeason> for SeasonAggregate {
    type Error = SeasonError;
    fn handle(
        &self,
        cmd: RenameSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SeasonError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if cmd.title == self.title {
            return Err(SeasonError::ValidationError(
                "Season title unchanged".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![SeasonEvent::SeasonRenamed {
            id: self.id,
            title: cmd.title,
            version: new_version,
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use test_support::make_ctx;

    fn create_season() -> SeasonAggregate {
        let cmd = CreateSeason {
            id: Uuid::now_v7(),
            series_id: SeriesId::new(),
            number: 1,
            title: Some("Spring Run".into()),
        };
        let events = SeasonAggregate::default().handle(cmd, make_ctx()).unwrap();
        let mut agg = SeasonAggregate::default();
        test_support::replay_events(&mut agg, events);
        agg
    }

    #[test]
    fn test_create_season_success() {
        let series_id = SeriesId::new();
        let cmd = CreateSeason {
            id: Uuid::now_v7(),
            series_id,
            number: 2,
            title: Some("Autumn Run".into()),
        };
        let result = SeasonAggregate::default().handle(cmd, make_ctx());
        assert!(result.is_ok());
        match result.unwrap().into_iter().next().unwrap() {
            SeasonEvent::SeasonCreated {
                id,
                series_id: sid,
                number,
                title,
                version,
            } => {
                assert_ne!(id, Uuid::nil());
                assert_eq!(sid, series_id);
                assert_eq!(number, 2);
                assert_eq!(title, Some("Autumn Run".into()));
                assert_eq!(version, AggregateVersion::INITIAL);
            }
            _ => panic!("Expected SeasonCreated"),
        }
    }

    #[test]
    fn test_create_season_without_title() {
        let cmd = CreateSeason {
            id: Uuid::now_v7(),
            series_id: SeriesId::new(),
            number: 3,
            title: None,
        };
        let events = SeasonAggregate::default().handle(cmd, make_ctx()).unwrap();
        match events.into_iter().next().unwrap() {
            SeasonEvent::SeasonCreated { title, .. } => assert_eq!(title, None),
            _ => panic!("Expected SeasonCreated"),
        }
    }

    #[test]
    fn test_rename_season_success() {
        let mut agg = create_season();
        let event = agg
            .handle(
                RenameSeason {
                    id: agg.id,
                    title: Some("Renamed".into()),
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, event);
        assert_eq!(agg.title, Some("Renamed".into()));
        assert_eq!(agg.version, AggregateVersion(2));
    }

    #[test]
    fn test_rename_season_idempotency() {
        let agg = create_season();
        let result = agg.handle(
            RenameSeason {
                id: agg.id,
                title: agg.title.clone(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SeasonError::ValidationError(ref m) if m.contains("unchanged")
        ));
    }

    #[test]
    fn test_rename_season_wrong_version() {
        let agg = create_season();
        let result = agg.handle(
            RenameSeason {
                id: agg.id,
                title: Some("X".into()),
                version: AggregateVersion(99),
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SeasonError::ValidationError(ref m) if m.contains("version mismatch")
        ));
    }

    /// Verify that apply() actually mutates aggregate state — catches mutants
    /// that replace the `apply` body with `()`.
    #[test]
    fn test_apply_updates_state() {
        use kameo_es::Metadata;
        let mut agg = SeasonAggregate::default();
        let id = Uuid::now_v7();
        let series_id = SeriesId::new();
        agg.apply(
            SeasonEvent::SeasonCreated {
                id,
                series_id,
                number: 7,
                title: Some("Liese".into()),
                version: AggregateVersion::INITIAL,
            },
            Metadata::default(),
        );
        assert_eq!(
            agg.title,
            Some("Liese".into()),
            "apply() should set the title"
        );
        assert_eq!(agg.id, id, "apply() should set the id");
        assert_eq!(agg.number, 7);
        assert_eq!(agg.series_id, series_id);
        assert_eq!(agg.version, AggregateVersion::INITIAL);
    }

    /// Verify that RenameSeason checks `!=` (not `==`) so passing the same
    /// title correctly returns an idempotency error.
    #[test]
    fn test_rename_uses_not_equal() {
        use kameo_es::Metadata;
        let mut agg = SeasonAggregate::default();
        let id = Uuid::now_v7();
        agg.apply(
            SeasonEvent::SeasonCreated {
                id,
                series_id: SeriesId::new(),
                number: 1,
                title: Some("A".into()),
                version: AggregateVersion::INITIAL,
            },
            Metadata::default(),
        );
        agg.apply(
            SeasonEvent::SeasonRenamed {
                id,
                title: Some("B".into()),
                version: AggregateVersion(2),
            },
            Metadata::default(),
        );
        let result = agg.handle(
            RenameSeason {
                id,
                title: Some("B".into()),
                version: AggregateVersion(2),
            },
            make_ctx(),
        );
        assert!(
            result.is_err(),
            "identical title should be rejected (idempotency check)"
        );
    }
} // mod tests
