# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors

# Multi-stage build for the Breakdown RS API binary.
# Used by docker-compose.prod.yml (ADR-016). Builds the `api` crate from the
# backend workspace and ships a minimal runtime image.

# syntax=docker/dockerfile:1.7

FROM rust:1.91-bookworm AS builder

WORKDIR /build

# Pre-copy manifests for better layer caching.
COPY Cargo.toml Cargo.lock ./
COPY crates/core/Cargo.toml crates/core/Cargo.toml
COPY crates/infra/Cargo.toml crates/infra/Cargo.toml
COPY crates/api/Cargo.toml crates/api/Cargo.toml
COPY crates/integration-tests/Cargo.toml crates/integration-tests/Cargo.toml

# Copy the full source tree (workspace build).
COPY crates ./crates
COPY scripts ./scripts

# Build the release binary.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/build/target \
    cargo build --release -p api && \
    cp target/release/api /usr/local/bin/breakdown-api

FROM debian:bookworm-slim AS runtime

# Minimal runtime deps + tini for proper signal handling.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates tini && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/breakdown-api /usr/local/bin/breakdown-api

# Non-root user.
RUN useradd -r -m -s /bin/false breakdown
USER breakdown

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/breakdown-api"]
