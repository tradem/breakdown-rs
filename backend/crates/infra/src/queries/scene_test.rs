// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

use super::*;

impl SceneRepositoryImpl {
    /// Test-only access to the underlying pool (e.g. for Tier-4 round-trip
    /// tests that need to open transactions against the same pool the read
    /// adapter uses). Only compiled during test builds.
    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}
