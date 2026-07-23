// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Fuzz targets for serde deserialization of command request bodies.
//!
//! This crate is **not** a library — it exists only to host the `fuzz_targets/`
//! binaries built by `cargo-fuzz`.  The empty `lib.rs` satisfies Cargo's
//! requirement that every workspace member has at least one target.

// The fuzz targets live in `fuzz_targets/*.rs` and are compiled by:
//   cargo fuzz run --fuzz-dir crates/fuzz-targets <target_name>
