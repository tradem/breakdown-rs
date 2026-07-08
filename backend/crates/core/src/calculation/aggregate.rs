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
    use test_support::make_ctx;
    use rust_decimal::Decimal;
    use std::str::FromStr;

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
        for evt in events {
            applied.apply(evt, Default::default());
        }
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
        for evt in agg
            .handle(
                UpdateHeaderInfo {
                    id: agg.id,
                    header: h.clone(),
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
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
        for evt in agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item: item.clone(),
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
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
        for evt in agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item: item1,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        let item2 = CalculationItem {
            id: item_id,
            name: "Y".into(),
            quantity: Decimal::from_str("3").unwrap(),
            unit_price: Decimal::from_str("10").unwrap(),
            is_paid: false,
        };
        for evt in agg
            .handle(
                UpdateCalculationItem {
                    id: agg.id,
                    item: item2,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
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
        for evt in agg
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
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        for evt in agg
            .handle(
                RemoveCalculationItem {
                    id: agg.id,
                    item_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
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
        for evt in agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        for evt in agg
            .handle(
                MarkItemAsPaid {
                    id: agg.id,
                    item_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
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
        for evt in agg
            .handle(
                AddCalculationItem {
                    id: agg.id,
                    item,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        for evt in agg
            .handle(
                MarkItemAsUnpaid {
                    id: agg.id,
                    item_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
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
} // mod tests
