// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

//! Verifies that the Testcontainers Vault fixture exposes the same Transit/KV
//! contract used by the production `VaultClient`.

mod fixtures;

use breakdown_core::settings::ports::{CredentialVault, GDriveCredentialBundle};
use uuid::Uuid;

#[tokio::test]
async fn vault_fixture_stores_and_fetches_gdrive_binding() -> anyhow::Result<()> {
    let fixture = fixtures::spawn_vault().await?;
    let client = fixture.client();
    let settings_id = Uuid::now_v7();
    let bundle = GDriveCredentialBundle::try_new(
        "test-client-id".to_owned(),
        "test-client-secret".to_owned(),
        "test-refresh-token".to_owned(),
        Some("test-folder".to_owned()),
    )?;
    let binding = client.store_gdrive(settings_id, bundle).await?;
    let fetched = client
        .fetch_gdrive(settings_id, &binding.vault_key_id)
        .await?;
    assert_eq!(fetched.client_id(), "test-client-id");
    assert_eq!(fetched.client_secret(), "test-client-secret");
    assert_eq!(fetched.refresh_token(), "test-refresh-token");
    assert_eq!(fetched.root_folder_id(), Some("test-folder"));

    client.destroy(settings_id, &binding.vault_key_id).await?;
    Ok(())
}
