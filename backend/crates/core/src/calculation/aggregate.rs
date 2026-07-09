// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Calculation aggregate.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

use super::commands::*;
use super::error::CalculationError;
use super::events::*;

/// State persisted by the Calculation aggregate.
#[derive(Debug, Clone, Default)]
pub struct CalculationAggregate {
    pub id: Uuid,
    pub project_id: ProjectId,
    pub header: CalculationHeader,
    pub items: Vec<CalculationItem>,
    pub version: AggregateVersion,
}

impl Entity for CalculationAggregate {
    type ID = Uuid;
    type Event = CalculationEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "calculation"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for CalculationAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            CalculationEvent::CalculationCreated {
                id,
                project_id,
                header,
                items,
                version,
            } => {
                self.id = id;
                self.project_id = project_id;
                self.header = header;
                self.items = items;
                self.version = version;
            }
            CalculationEvent::HeaderInfoUpdated {
                header, version, ..
            } => {
                self.header = header;
                self.version = version;
            }
            CalculationEvent::CalculationItemAdded { item, version, .. } => {
                self.items.push(item);
                self.version = version;
            }
            CalculationEvent::CalculationItemUpdated { item, version, .. } => {
                if let Some(i) = self.items.iter_mut().position(|x| x.id == item.id) {
                    self.items[i] = item;
                }
                self.version = version;
            }
            CalculationEvent::CalculationItemRemoved {
                item_id, version, ..
            } => {
                self.items.retain(|x| x.id != item_id);
                self.version = version;
            }
            CalculationEvent::ItemMarkedAsPaid {
                item_id, version, ..
            } => {
                if let Some(it) = self.items.iter_mut().find(|x| x.id == item_id) {
                    it.is_paid = true;
                }
                self.version = version;
            }
            CalculationEvent::ItemMarkedAsUnpaid {
                item_id, version, ..
            } => {
                if let Some(it) = self.items.iter_mut().find(|x| x.id == item_id) {
                    it.is_paid = false;
                }
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateCalculation> for CalculationAggregate {
    type Error = CalculationError;
    fn handle(
        &self,
        cmd: CreateCalculation,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![CalculationEvent::CalculationCreated {
            id: cmd.id,
            project_id: cmd.project_id,
            header: CalculationHeader::default(),
            items: Vec::new(),
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<UpdateHeaderInfo> for CalculationAggregate {
    type Error = CalculationError;
    fn handle(
        &self,
        cmd: UpdateHeaderInfo,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CalculationError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        Ok(vec![CalculationEvent::HeaderInfoUpdated {
            id: self.id,
            header: cmd.header,
            version: self.version.next(),
        }])
    }
}

impl Command<AddCalculationItem> for CalculationAggregate {
    type Error = CalculationError;
    fn handle(
        &self,
        cmd: AddCalculationItem,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CalculationError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if cmd.item.quantity.is_sign_negative() || cmd.item.unit_price.is_sign_negative() {
            return Err(CalculationError::ValidationError(
                "Quantity and unit price must be non-negative".into(),
            ));
        }
        Ok(vec![CalculationEvent::CalculationItemAdded {
            id: self.id,
            item: cmd.item,
            version: self.version.next(),
        }])
    }
}

impl Command<UpdateCalculationItem> for CalculationAggregate {
    type Error = CalculationError;
    fn handle(
        &self,
        cmd: UpdateCalculationItem,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CalculationError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.items.iter().any(|x| x.id == cmd.item.id) {
            return Err(CalculationError::ValidationError("Item not found".into()));
        }
        Ok(vec![CalculationEvent::CalculationItemUpdated {
            id: self.id,
            item: cmd.item,
            version: self.version.next(),
        }])
    }
}

impl Command<RemoveCalculationItem> for CalculationAggregate {
    type Error = CalculationError;
    fn handle(
        &self,
        cmd: RemoveCalculationItem,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CalculationError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.items.iter().any(|x| x.id == cmd.item_id) {
            return Err(CalculationError::ValidationError("Item not found".into()));
        }
        Ok(vec![CalculationEvent::CalculationItemRemoved {
            id: self.id,
            item_id: cmd.item_id,
            version: self.version.next(),
        }])
    }
}

impl Command<MarkItemAsPaid> for CalculationAggregate {
    type Error = CalculationError;
    fn handle(
        &self,
        cmd: MarkItemAsPaid,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CalculationError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.items.iter().any(|x| x.id == cmd.item_id) {
            return Err(CalculationError::ValidationError("Item not found".into()));
        }
        Ok(vec![CalculationEvent::ItemMarkedAsPaid {
            id: self.id,
            item_id: cmd.item_id,
            version: self.version.next(),
        }])
    }
}

impl Command<MarkItemAsUnpaid> for CalculationAggregate {
    type Error = CalculationError;
    fn handle(
        &self,
        cmd: MarkItemAsUnpaid,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CalculationError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.items.iter().any(|x| x.id == cmd.item_id) {
            return Err(CalculationError::ValidationError("Item not found".into()));
        }
        Ok(vec![CalculationEvent::ItemMarkedAsUnpaid {
            id: self.id,
            item_id: cmd.item_id,
            version: self.version.next(),
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal::Decimal;
    use std::str::FromStr;
    use test_support::make_ctx;

    fn make_calc() -> CalculationAggregate {
        let pid = ProjectId::new();
        let agg = CalculationAggregate::default();
        let events = agg
            .handle(
                CreateCalculation {
                    id: Uuid::now_v7(),
                    project_id: pid,
                },
                make_ctx(),
            )
            .unwrap();
        let mut applied = CalculationAggregate::default();
        test_support::replay_events(&mut applied, events);
        applied
    }

    #[test]
    fn test_create_calculation_success() {
        let result = CalculationAggregate::default().handle(
            CreateCalculation {
                id: Uuid::now_v7(),
                project_id: ProjectId::new(),
            },
            make_ctx(),
        );
        assert!(result.is_ok());
        match result.unwrap().into_iter().next().unwrap() {
            CalculationEvent::CalculationCreated {
                id, version, items, ..
            } => {
                assert_ne!(id, Uuid::nil());
                assert_eq!(version, AggregateVersion::INITIAL);
                assert!(items.is_empty());
            }
            _ => panic!("Expected CalculationCreated"),
        }
    }

    #[test]
    fn test_update_header_info_success() {
        let mut agg = make_calc();
        let h = CalculationHeader {
            subjects: Some("Budget".into()),
            ..Default::default()
        };
        let events = agg
            .handle(
                UpdateHeaderInfo {
                    id: agg.id,
                    header: h.clone(),
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        assert_eq!(agg.header.subjects, h.subjects);
    }

    #[test]
    fn test_add_item_success() {
        let mut agg = make_calc();
        let item = CalculationItem {
            id: Uuid::now_v7(),
            name: "Fabric".into(),
            quantity: Decimal::from_str("2").unwrap(),
            unit_price: Decimal::from_str("10.00").unwrap(),
            is_paid: false,
        };
        let events = agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item: item.clone(),
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        assert_eq!(agg.items.len(), 1);
        assert_eq!(agg.items[0].name, "Fabric");
    }

    #[test]
    fn test_add_item_negative_quantity() {
        let agg = make_calc();
        let item = CalculationItem {
            id: Uuid::now_v7(),
            name: "Bad".into(),
            quantity: Decimal::from_str("-1").unwrap(),
            unit_price: Decimal::from_str("5.00").unwrap(),
            is_paid: false,
        };
        let result = agg.handle(
            AddCalculationItem {
                id: agg.id,
                item,
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CalculationError::ValidationError(ref m) if m.contains("non-negative")
        ));
    }

    #[test]
    fn test_update_item_success() {
        let mut agg = make_calc();
        let item_id = Uuid::now_v7();
        let item1 = CalculationItem {
            id: item_id,
            name: "X".into(),
            quantity: Decimal::from_str("1").unwrap(),
            unit_price: Decimal::from_str("5").unwrap(),
            is_paid: false,
        };
        let events = agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item: item1,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        let item2 = CalculationItem {
            id: item_id,
            name: "Y".into(),
            quantity: Decimal::from_str("3").unwrap(),
            unit_price: Decimal::from_str("10").unwrap(),
            is_paid: false,
        };
        let events = agg
            .handle(
                UpdateCalculationItem {
                    id: agg.id,
                    item: item2,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        assert_eq!(agg.items[0].name, "Y");
    }

    #[test]
    fn test_update_item_not_found() {
        let agg = make_calc();
        let item = CalculationItem {
            id: Uuid::now_v7(),
            name: "Z".into(),
            quantity: Decimal::ONE,
            unit_price: Decimal::ONE,
            is_paid: false,
        };
        let result = agg.handle(
            UpdateCalculationItem {
                id: agg.id,
                item,
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CalculationError::ValidationError(ref m) if m.contains("not found")
        ));
    }

    #[test]
    fn test_remove_item_success() {
        let mut agg = make_calc();
        let item_id = Uuid::now_v7();
        let events = agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item: CalculationItem {
                        id: item_id,
                        name: "ToRemove".into(),
                        quantity: Decimal::ONE,
                        unit_price: Decimal::ZERO,
                        is_paid: false,
                    },
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        let events = agg
            .handle(
                RemoveCalculationItem {
                    id: agg.id,
                    item_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        assert!(agg.items.is_empty());
    }

    #[test]
    fn test_remove_item_not_found() {
        let agg = make_calc();
        let result = agg.handle(
            RemoveCalculationItem {
                id: agg.id,
                item_id: Uuid::now_v7(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CalculationError::ValidationError(ref m) if m.contains("not found")
        ));
    }

    #[test]
    fn test_mark_paid_success() {
        let mut agg = make_calc();
        let item_id = Uuid::now_v7();
        let item = CalculationItem {
            id: item_id,
            name: "Buttons".into(),
            quantity: Decimal::ONE,
            unit_price: Decimal::from_str("5").unwrap(),
            is_paid: false,
        };
        let events = agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        let events = agg
            .handle(
                MarkItemAsPaid {
                    id: agg.id,
                    item_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        assert!(agg.items[0].is_paid);
    }

    #[test]
    fn test_mark_paid_not_found() {
        let agg = make_calc();
        let result = agg.handle(
            MarkItemAsPaid {
                id: agg.id,
                item_id: Uuid::now_v7(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CalculationError::ValidationError(ref m) if m.contains("Item not found")
        ));
    }

    #[test]
    fn test_mark_unpaid_success() {
        let mut agg = make_calc();
        let item_id = Uuid::now_v7();
        let item = CalculationItem {
            id: item_id,
            name: "Curtains".into(),
            quantity: Decimal::ONE,
            unit_price: Decimal::ONE,
            is_paid: true,
        };
        let events = agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        let events = agg
            .handle(
                MarkItemAsUnpaid {
                    id: agg.id,
                    item_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        assert!(!agg.items[0].is_paid);
    }

    #[test]
    fn test_mark_unpaid_not_found() {
        let agg = make_calc();
        let result = agg.handle(
            MarkItemAsUnpaid {
                id: agg.id,
                item_id: Uuid::now_v7(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CalculationError::ValidationError(ref m) if m.contains("Item not found")
        ));
    }

    /// Verify that apply() actually mutates aggregate state.
    ///
    /// Catches mutants that replace the `apply` body with `()` — if apply is a
    /// no-op the assertion below fails because the header stays at its default.
    #[test]
    fn test_apply_updates_state() {
        use kameo_es::Metadata;
        let mut agg = make_calc();
        let original_subjects = agg.header.subjects.clone();
        let h = CalculationHeader {
            subjects: Some("Costume Budget".into()),
            ..Default::default()
        };
        agg.apply(
            CalculationEvent::HeaderInfoUpdated {
                id: agg.id,
                header: h.clone(),
                version: AggregateVersion(2),
            },
            Metadata::default(),
        );
        assert_eq!(
            agg.header.subjects, h.subjects,
            "apply() should mutate aggregate state"
        );
        assert_ne!(
            agg.header.subjects, original_subjects,
            "apply() should change the header"
        );
    }

    /// Update one item among many — verifies the `==` match in `apply()` is not
    /// flipped to `!=`, which would cause the update to target a wrong item.
    #[test]
    fn test_apply_updates_correct_item_among_many() {
        use kameo_es::Metadata;
        let mut agg = make_calc();
        let id_a = Uuid::now_v7();
        let id_b = Uuid::now_v7();

        // Add two items.
        agg.apply(
            CalculationEvent::CalculationItemAdded {
                id: agg.id,
                item: CalculationItem {
                    id: id_a,
                    name: "A".into(),
                    quantity: Decimal::ONE,
                    unit_price: Decimal::ONE,
                    is_paid: false,
                },
                version: AggregateVersion(2),
            },
            Metadata::default(),
        );
        agg.apply(
            CalculationEvent::CalculationItemAdded {
                id: agg.id,
                item: CalculationItem {
                    id: id_b,
                    name: "B".into(),
                    quantity: Decimal::ONE,
                    unit_price: Decimal::ONE,
                    is_paid: false,
                },
                version: AggregateVersion(3),
            },
            Metadata::default(),
        );

        // Update item A — name should change, B should stay unchanged.
        agg.apply(
            CalculationEvent::CalculationItemUpdated {
                id: agg.id,
                item: CalculationItem {
                    id: id_a,
                    name: "A-updated".into(),
                    quantity: Decimal::ONE,
                    unit_price: Decimal::ONE,
                    is_paid: false,
                },
                version: AggregateVersion(4),
            },
            Metadata::default(),
        );
        assert_eq!(agg.items.len(), 2, "should still have two items");
        let names: Vec<&str> = agg.items.iter().map(|i| i.name.as_str()).collect();
        assert!(
            names.contains(&"A-updated"),
            "item A should be updated, got {names:?}"
        );
        assert!(
            names.contains(&"B"),
            "item B should be unchanged, got {names:?}"
        );
    }

    /// Remove one item among many — verifies the `!=` match in `apply()` for
    /// `retain` is not flipped to `==`, which would delete the wrong item.
    #[test]
    fn test_apply_removes_correct_item_among_many() {
        use kameo_es::Metadata;
        let mut agg = make_calc();
        let id_a = Uuid::now_v7();
        let id_b = Uuid::now_v7();

        // Add two items.
        agg.apply(
            CalculationEvent::CalculationItemAdded {
                id: agg.id,
                item: CalculationItem {
                    id: id_a,
                    name: "A".into(),
                    quantity: Decimal::ONE,
                    unit_price: Decimal::ONE,
                    is_paid: false,
                },
                version: AggregateVersion(2),
            },
            Metadata::default(),
        );
        agg.apply(
            CalculationEvent::CalculationItemAdded {
                id: agg.id,
                item: CalculationItem {
                    id: id_b,
                    name: "B".into(),
                    quantity: Decimal::ONE,
                    unit_price: Decimal::ONE,
                    is_paid: false,
                },
                version: AggregateVersion(3),
            },
            Metadata::default(),
        );

        // Remove item A only.
        agg.apply(
            CalculationEvent::CalculationItemRemoved {
                id: agg.id,
                item_id: id_a,
                version: AggregateVersion(4),
            },
            Metadata::default(),
        );
        assert_eq!(agg.items.len(), 1, "only item A should be removed");
        assert_eq!(
            agg.items[0].id, id_b,
            "item B should remain after removing A"
        );
    }
} // mod tests
