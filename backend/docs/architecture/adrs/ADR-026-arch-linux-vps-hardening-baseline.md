# ADR-026: Hosting-Hardening Baseline for the Arch Linux VPS

**Status**: Proposed
**Date**: 2026-08-01
**Author**: Tobias Rademacher (@tradem); glm-5.2 (neuralwatt)
**Related**: ADR-009 (deployment target: small VPS), ADR-023 (at-rest crypto),
ADR-024 (in-transit TLS), ADR-027 (vault), ADR-028 (settings authz)

---

## Context

The host is a **self-managed VPS on Arch Linux (rolling release)**, running the
whole stack in Docker (`postgres`, `sierradb`, `garage`, the proposed `vault`
and `step-ca`, plus the `api`/`caddy` front services). Operations capacity is
small. The threat model includes: host compromise via exposed services, supply-
chain attacks through rolling-release packages, credential theft from
process/RAM, and unauthorised access to secrets at rest.

Arch's rolling-release model is a genuine operating risk: there is no
distributions-provided unattended-upgrades track comparable to Debian/Ubuntu's
`unattended-upgrades`/`dnf-automatic`. Kernel and package updates require
**manual operation** (including reboots). This ADR must state honestly where
that makes a control impractical.

## Decision

Adopt a documented **host-hardening baseline** maintained as a checked-in
runbook (`docs/operations/host-hardening.md`) plus, where automatable, tested
config (nftables rules, sshd config, audit rules). The baseline:

### Network exposure
1. **nftables** default-deny inbound; only `:80`/`:443` (Caddy) and `:22` (SSH,
   see below) are public. Docker is bound to internal networks; no DB/SierraDB/
   vault/step-ca port is ever published to the host (`ports:` absent in
   `docker-compose.prod.yml`).
2. Prefer a **loopback-only** bind for any control-plane service that does not
   need cross-container access from outside the compose network.

### SSH & remote access
3. SSH: **key-only auth** (`PasswordAuthentication no`), separate non-root
   deploy user, root login disabled, hardened `sshd_config` (modern MACs,
   `MaxAuthTries`, loginGraceTime). `fail2ban` for SSH brute-force.
4. Out-of-band/rescue console access verified with the hoster; credentials kept
   in the vault (ADR-027).

### Container & process isolation
5. Run Docker with **`userns-remap`** (user namespaces) so container root ≠
   host root. Prefer `--read-only` rootfs for stateless services where
   practical; cap capabilities (`--cap-drop=ALL` + minimal `--cap-add`).
6. Resource limits (memory/CPU) per service to limit blast radius of a
   runaway container on the small host.

### Supply chain / patching (Arch rolling)
7. **No unattended-upgrades.** Established instead a *manual patching SLA*:
   operator reviews `pacman -Syu` output at least weekly, applies security-
   relevant updates within the SLA, and reboots for kernel updates after
   verifying the LUKS unlock path works. Honest caveat: a 7-day review cadence
   means there is a bounded exposure window for critical Arch package CVEs;
   this is accepted as the cost of rolling-release on a small ops team.
8. Pin Docker images by digest in `docker-compose.prod.yml` (the dev compose
   may use tags). `cargo-deny` (ADR-017) and `gitleaks` (AGENTS §3) already
   cover Rust-side supply chain.

### Auditing, logging, observability
9. **`auditd`** rules for exec, file tamper under the data/vault volumes, and
   sudo usage; logs shipped to `journald` with retention limits; alerting via
   OpenTelemetry (ADR-011) where available.
10. Tracing/log hygiene: structured logs must never include secrets, vault
    unwrap responses, or full auth tokens (see ADR-027 §log hygiene and the
    edge-case below).

### Backups & key custody
11. LUKS2 header + key material backed up offline separately from the data
    volume (ADR-023). Backup/restore drill documented and executed at least
    quarterly.

## Consequences

### Positive
- Small, auditable surface; the only public services are Caddy + SSH.
- Compartmentalises container escapes via user-namespace remapping and
  capability dropping.
- Explicit patching cadence beats silent drift and makes the exposure window
  measurable.

### Negative
- Arch rolling release means the maintainer must stay engaged; a stalled owner
  = stale kernel = real CVE exposure. This is the honest, irreducible risk of
  the chosen host OS.
- Some hardening (read-only rootfs, fine-grained caps) costs effort per
  service and may have to be relaxed case-by-case (e.g. Garage needs write
  access to its data dir).
- Manual unlock after reboot (ADR-023) ties the patching cadence to
  uptime/operational pain.

## Alternatives Considered

1. **Switch to a stable distro (Debian/Alma) for the host** — viable and would
   restore unattended-upgrades; listed as alternative, not chosen, because it
   diverges from the stated deployment target. A future flip is a low-friction
   ops decision and does not affect the application code.
2. **Flatcar / Talos Linux (immutable, auto-updating container host)** — strong
   fit for container-host duty and largely removes the rolling-release risk;
   listed as alternative because it requires the hoster to offer a custom
   image, which the current target VPS class may not.
3. **SELinux/AppArmor MAC enforcement** — AppArmor on Arch is usable but
   fragile; we prefer user-namespace remapping + capability dropping as the
   primary isolation, with AppArmor as future hardening.

## Security / Compliance Notes
- Patching SLA + quarterly restore drill are the two controls most likely to
  silently lapse; they should have an owner and a calendar reminder.
- This ADR is a baseline, not a finished posture; each service (vault,
  step-ca, garage) adds its own hardening notes via the respective ADR.
- Edge case (log capture of credentials): enforced both by code-level
  sanitisation in tracing layers and by vault APIs that do not echo unwrapped
  secret bytes back to callers (ADR-027).
