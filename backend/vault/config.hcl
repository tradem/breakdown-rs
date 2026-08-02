# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: gpt-5.6-luna (opencode-go)
# Co-authored-by: glm-5.2 (neuralwatt)

ui = false
disable_mlock = false

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = false
  tls_cert_file   = "/tls/vault.crt"
  tls_key_file    = "/tls/vault.key"
  tls_min_version = "tls13"
}

api_addr     = "https://vault:8200"
cluster_addr = "https://vault:8201"
