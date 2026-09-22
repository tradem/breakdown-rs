# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (neuralwatt)

# Dev Vault config (docker-compose.dev.vault.yml, issue #468): plaintext HTTP
# on the loopback-published :8200, file storage. Mirrors the prod config
# (vault/config.hcl) except TLS is disabled — dev-only; the in-transit TLS
# requirements of ADR-024 / ADR-027 apply to production, never to this file.

ui = false
disable_mlock = false

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

api_addr     = "http://vault:8200"
cluster_addr = "http://vault:8201"
