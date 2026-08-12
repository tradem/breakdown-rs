// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::collections::HashMap;
use std::sync::Arc;

use breakdown_core::ai::AiImportBounds;
use breakdown_core::error::DomainError;
use tokio::sync::{Mutex, OwnedSemaphorePermit, Semaphore};

/// Bounded in-flight concurrency guard. The permit must be held for the full
/// job lifetime; dropping it releases both global and per-user capacity.
pub struct AiConcurrencyLimiter {
    global: Arc<Semaphore>,
    per_user: Arc<Mutex<HashMap<String, Arc<Semaphore>>>>,
    per_user_limit: usize,
}

impl AiConcurrencyLimiter {
    pub fn new(bounds: AiImportBounds) -> Result<Self, DomainError> {
        bounds
            .validate()
            .map_err(|error| DomainError::validation(error.to_owned()))?;
        Ok(Self {
            global: Arc::new(Semaphore::new(bounds.max_concurrent_jobs_global as usize)),
            per_user: Arc::new(Mutex::new(HashMap::new())),
            per_user_limit: bounds.max_concurrent_jobs_per_user as usize,
        })
    }

    pub async fn try_acquire(
        &self,
        user_id: impl Into<String>,
    ) -> Result<Option<AiConcurrencyPermit>, DomainError> {
        let global = match Arc::clone(&self.global).try_acquire_owned() {
            Ok(permit) => permit,
            Err(_) => return Ok(None),
        };
        let user_id = user_id.into();
        let user_semaphore = {
            let mut users = self.per_user.lock().await;
            // Prune idle per-user entries while the lock is held: an entry is
            // idle when the map holds the only Arc and all permits are
            // available. Without this, the map grows with the number of users
            // that ever started an import, not the number of in-flight jobs.
            users.retain(|_, semaphore| {
                Arc::strong_count(semaphore) > 1
                    || semaphore.available_permits() < self.per_user_limit
            });
            Arc::clone(
                users
                    .entry(user_id)
                    .or_insert_with(|| Arc::new(Semaphore::new(self.per_user_limit))),
            )
        };
        match user_semaphore.try_acquire_owned() {
            Ok(user) => Ok(Some(AiConcurrencyPermit { global, user })),
            Err(_) => Ok(None),
        }
    }
}

pub struct AiConcurrencyPermit {
    global: OwnedSemaphorePermit,
    user: OwnedSemaphorePermit,
}

impl AiConcurrencyPermit {
    /// Borrow the held permits for diagnostics without releasing capacity.
    pub fn permits(&self) -> (&OwnedSemaphorePermit, &OwnedSemaphorePermit) {
        (&self.global, &self.user)
    }
}
