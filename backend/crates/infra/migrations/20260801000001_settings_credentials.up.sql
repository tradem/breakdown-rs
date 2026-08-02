-- Reference-only settings projection for ADR-027.
-- No credential bytes, DEKs, or ciphertext are stored in Postgres.
CREATE TABLE projection_settings (
    id UUID PRIMARY KEY,
    provider TEXT NOT NULL,
    vault_key_id TEXT NOT NULL,
    vault_version BIGINT NOT NULL,
    binding_state TEXT NOT NULL CHECK (binding_state IN ('active', 'revoked')),
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_projection_settings_provider
    ON projection_settings (provider);
