<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: ox-alpha-free (opencode-go) -->

# Host hardening runbook — Arch Linux VPS & LUKS2 at-rest encryption

Operational companion to [ADR-023](../architecture/adrs/ADR-023-database-encryption-at-rest.md)
(database encryption at rest) and
[ADR-026](../architecture/adrs/ADR-026-arch-linux-vps-hardening-baseline.md)
(host hardening baseline), plus the host-side complements of ADR-024 (in-transit
TLS), ADR-025 (HTTPS edge) and ADR-027 (secrets vault).

This runbook covers the **host-level controls that cannot be docker-compose
services**: block-device encryption, firewall, sshd, auditd, Docker daemon
hardening, and the patching/restore SLAs. Every section ends with a **Verify**
block — the acceptance test for that control.

> **Honest caveats up front** (ADR-023 / ADR-026, restated here so no operator
> is surprised):
>
> 1. **Arch rolling release has no unattended-upgrades.** Patching is manual,
>    governed by the weekly SLA in §7. There *is* a bounded exposure window for
>    critical CVEs; this is accepted as the cost of rolling-release on a small
>    ops team.
> 2. **LUKS is scoped to data volumes only, rootfs stays unencrypted.** Most
>    cheap VPS hosters (Netcup-class, ADR-009) expose no initramfs/rescue
>    console suitable for remote unlock, so full-disk encryption would mean an
>    unattended reboot bricks the box until a human types a passphrase — if a
>    console exists at all. The data volumes are the asset; the OS image is
>    re-provisionable. Revisit if the hoster confirms a rescue/initramfs
>    unlock path (open question in issue #158).
> 3. **LUKS does not protect against live compromise.** A root process on the
>    running host reads the unlocked volume and keys in RAM. At-rest crypto
>    defends against disk theft/cloning/decommissioning only. Live-host defence
>    is §4–§6 plus ADR-027.

---

## 1. Threat model summary

| Threat | Control |
|---|---|
| Stolen/cloned/decommissioned disk or volume image | LUKS2 on data volumes (§3) |
| Plaintext backup dumps escaping the host | `pg_dump \| age` streaming, vault-held key (§5) |
| Internet-exposed admin services | nftables default-deny (§4.1) + unpublished internal ports (§4.2) |
| SSH brute force / credential theft | key-only sshd + fail2ban (§4.3) |
| Container escape to host root | `userns-remap`, cap-drop, resource limits (§6) |
| Silent tampering | auditd exec/file/sudo rules (§8) |
| Stale packages / stale kernel | weekly patching SLA with owner (§7) |
| Lost LUKS header = lost data | offline header + key backup (§3.3) |

## 2. Layout assumptions

Throughout, substitute real values:

| Placeholder | Meaning |
|---|---|
| `/dev/vdb` | The partition/LV backing all persistent stack storage |
| `/srv/breakdown/data` | Mount point of the unlocked LUKS device |
| `deploy` | The non-root SSH user |

All persistent container state lives under **one** location: the **Docker data
root**, relocated onto the LUKS mount (`/srv/breakdown/data/docker` via
`data-root`, §6) → named volumes such as `postgres_data`, `sierradb_data`,
`garage_data`, `caddy_data`, `vault_data`, `step_ca_data`, `tls_data`. Any
bind-mounted host directories also go under `/srv/breakdown/data`.

> ⚠️ Do **not** leave Docker at the default `/var/lib/docker`: that path sits on
> the unencrypted rootfs and every named volume would silently escape LUKS.
> Set `data-root` **before creating the first volume** (fresh host), or migrate
> an existing data root per §6.

Because both sit on the same LUKS device, one key and one unlock procedure
covers every tier (Postgres, SierraDB, Garage, Caddy ACME state, Vault,
step-ca). See `docker-compose.prod.yml` for the current volume list.

## 3. LUKS2 provisioning (ADR-023)

### 3.1 Create the encrypted volume

```bash
# 1. Identify the target device — VERIFY TWICE; luksFormat is destructive.
lsblk -f

# 2. Format with LUKS2 + Argon2id (the LUKS2 default KDF; explicit for clarity).
sudo cryptsetup luksFormat --type luks2 --pbkdf argon2id /dev/vdb

# 3. Unlock and create the filesystem.
sudo cryptsetup open /dev/vdb breakdown-data
sudo mkfs.ext4 -L breakdown-data /dev/mapper/breakdown-data

# 4. Mount point + permissions.
sudo mkdir -p /srv/breakdown/data
sudo mount /dev/mapper/breakdown-data /srv/breakdown/data
```

### 3.2 Unlock at boot

Without a remote-unlock-capable initramfs, boot-time unlock is **manual**:
after each reboot, open the hoster's rescue/VNC console and run:

```bash
sudo cryptsetup open /dev/vdb breakdown-data && \
  sudo mount /srv/breakdown/data && sudo systemctl start docker
```

(`mount -a` would skip the fstab entry below because it is `noauto`; the mount
must be explicit so Docker never starts against the unmounted, unencrypted
path.)

Optionally add a second keyslot backed by a keyfile stored on the (unencrypted)
rootfs for semi-automatic unlock — but understand that this weakens the model:
a stolen disk image *of the data volume alone* stays protected, while a stolen
whole-machine image would not be. The default posture is **manual passphrase
unlock**, with the passphrase held in the Vault KV-v2 (`kv/host/luks-passphrase`,
ADR-027) as disaster recovery — never on the same disk.

If `/etc/fstab` references the mount, use `noauto` so a reboot does not wedge
the boot process waiting for a locked device:

```
/dev/mapper/breakdown-data  /srv/breakdown/data  ext4  rw,noauto,nofail  0  2
```

### 3.3 Offline header + key material backup

A destroyed/corrupted LUKS header makes the volume permanently unreadable.

```bash
# Header backup — store OFFLINE (USB stick / hoster-independent location),
# never on the same disk it describes.
sudo cryptsetup luksHeaderBackup /dev/vdb \
  --header-backup-file /run/media/usb/breakdown-luks-header.img
sudo chmod 600 /run/media/usb/breakdown-luks-header.img
```

Also store offline:

- the Argon2id **passphrase** (printed once during provisioning; copy into
  Vault `kv/host/luks-passphrase` per ADR-027),
- the printed recovery instructions from this section.

**Verify** (quarterly, see §9). Two separate operations:

```bash
# (a) Non-destructive validation of the offline header backup — parses the
# backup file itself; touches no live device.
sudo cryptsetup luksDump /run/media/usb/breakdown-luks-header.img   # must parse cleanly

# (b) Actual restore drill — DESTRUCTIVE by design: luksHeaderRestore has NO
# dry-run mode; it overwrites the target's LUKS metadata AND all keyslots.
# Only ever run it against a disposable loop device, never /dev/vdb:
truncate -s 64M /tmp/header-test.img
LOOP_DEV=$(sudo losetup --find --show /tmp/header-test.img)   # e.g. /dev/loop0
sudo cryptsetup luksHeaderRestore "$LOOP_DEV" \
  --header-backup-file /run/media/usb/breakdown-luks-header.img   # prompts for confirmation
sudo cryptsetup luksDump "$LOOP_DEV"                          # restored layout visible
sudo losetup -d "$LOOP_DEV" && rm /tmp/header-test.img
```

## 4. Network & SSH hardening (ADR-026 §1–§4)

### 4.1 nftables default-deny inbound

The checked-in ruleset is [`host/nftables.conf`](host/nftables.conf):

```bash
sudo pacman -S nftables
sudo install -m 600 docs/operations/host/nftables.conf /etc/nftables.conf
sudo nft -c -f /etc/nftables.conf        # syntax check before applying
sudo systemctl enable --now nftables
```

Only `:22` (rate-limited SSH), `:80`/`:443` (Caddy edge, ADR-025) are public.
The ruleset owns a dedicated `breakdown_filter` table only (no top-level
`flush ruleset`) so a reload can never wipe Docker's DNAT/port-publish rules;
its forward chain accepts established flows, Docker-DNAT traffic, and local
bridge routing, and drops anything else leaving via the WAN interface.

> **Why the firewall alone is not enough:** published container ports bypass
> the `input` chain entirely — Docker installs DNAT + FORWARD accepts. That is
> why §4.2 (no published internal ports) is the primary control and nftables
> the second layer.

**Verify:**

```bash
sudo nft list ruleset | grep -E 'policy (drop|accept)'
nft -c -f /etc/nftables.conf             # exits 0
ss -tlnp                                  # nothing unexpected on 0.0.0.0/[::]
```

From an **external** machine:

```bash
nc -zv <vps-ip> 5432   # must fail/refuse
nc -zv <vps-ip> 9090   # must fail/refuse (SierraDB)
curl -sI http://<vps-ip>/ ; curl -skI https://<vps-ip>/   # Caddy answers
```

### 4.2 No DB / SierraDB / vault / step-ca port published

Internal services bind only inside the compose network. Postgres keeps a
**loopback-only** publish (`127.0.0.1:…`) for admin sessions on the VPS itself;
everything else publishes no host port at all.

**Verify:**

```bash
docker compose -f docker-compose.prod.yml config \
  | yq '.services | to_entries[] | select(.value.ports) | .key' 
# Expected output: exactly ["postgres", "caddy"] — postgres bound to 127.0.0.1.

grep -A3 'ports:' docker-compose.prod.yml
# Every mapping must start with "127.0.0.1:" or be 80/443.
```

### 4.3 SSH hardening

Prerequisite: create the deploy user with an ed25519 key **before** locking
out password auth, and keep a hoster-console session open as fallback.

```bash
sudo useradd -m -s /bin/bash -G wheel deploy
sudo mkdir -p ~deploy/.ssh && echo '<ed25519 pubkey>' | sudo tee ~deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy ~deploy/.ssh && sudo chmod 700 ~deploy/.ssh && sudo chmod 600 ~deploy/.ssh/authorized_keys
```

Install the checked-in drop-in [`host/sshd/10-breakdown-hardening.conf`](host/sshd/10-breakdown-hardening.conf)
(key-only, `PermitRootLogin no`, hardened MACs/KEX/ciphers, `MaxAuthTries 3`,
`LoginGraceTime 20`):

```bash
sudo install -D -m 600 docs/operations/host/sshd/10-breakdown-hardening.conf \
     /etc/ssh/sshd_config.d/10-breakdown-hardening.conf
sudo sshd -t && sudo systemctl reload sshd
```

Brute-force protection with fail2ban:

```bash
sudo pacman -S fail2ban
sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null <<'EOF'
[sshd]
enabled = true
maxretry = 5
bantime = 1h
findtime = 10m
EOF
sudo systemctl enable --now fail2ban
```

**Verify:**

```bash
sudo sshd -T | grep -E '^(passwordauthentication|permitrootlogin|maxauthtries|logingracetime)'
# passwordauthentication no
# permitrootlogin no
# maxauthtries 3
sudo fail2ban-client status sshd          # jail running
ssh root@<vps-ip>                         # from outside: must be refused
```

### 4.4 Out-of-band / rescue console

- Confirm with the hoster that a VNC/rescue console exists and works **before**
  it is needed (this also answers whether full-disk encryption could replace
  the data-volume scoping — see caveat №2).
- Store the hoster account URL + credentials in Vault KV-v2
  (`kv/host/hoster-console`, ADR-027), never in `.env` or a repo file.

**Verify:** log into the console once after provisioning; record the date in
the ops journal.

## 5. Backup/dump bypass mitigation (ADR-023)

`pg_dump` output is treated as a first-class exfiltration vector: it is
streamed through `age` and never touches disk in plaintext. The recipient key
is wrapped by the Vault Transit engine (ADR-027), not stored beside the backups.

One-time setup:

```bash
age-keygen -o age.key                      # on a trusted machine
AGE_RECIPIENT=$(grep 'public key' age.key | cut -d' ' -f4)
vault kv put kv/backup-age recipient="$AGE_RECIPIENT"
vault write transit/keys/backup-age type=ed25519   # wrapping key, ADR-027
# Store the private age.key OFFLINE (same medium class as the LUKS header).
```

Encrypted logical backup (`POSTGRES_USER`/`POSTGRES_DB` are expanded *inside*
the container where Compose sets them — not in the host shell, where they may
be unset):

```bash
set -euo pipefail
AGE_RECIPIENT="$(vault kv get -field=recipient kv/backup-age)"
docker compose -f docker-compose.prod.yml exec -T postgres sh -c \
  'pg_dump -U "$POSTGRES_USER" --format=custom "$POSTGRES_DB"' \
  | age -r "$AGE_RECIPIENT" > "/backups/breakdown-$(date -u +%Y%m%dT%H%M%SZ).dump.age"
```

Rules:

- **Never** redirect unencrypted dump output to a file path. Only the final
  `.age` ciphertext may land on disk.
- Volume-level snapshots (LVM snapshots, `borgbackup` of the mounted tree) are
  taken while the volume is unlocked/mounted and stay **inside** the encrypted
  volume, or are themselves encrypted (`borgbackup --encrypt`) when copied off-host.
- SierraDB data copies follow the same rule: copy the directory only from
  inside the LUKS mount, or encrypt the archive.

**Verify:**

```bash
file /backups/*.dump.age            # "age file", not "PostgreSQL custom dump"
head -c 200 /backups/<latest>.age   # binary ciphertext, no readable SQL
```

## 6. Docker daemon hardening (ADR-026 §5–§6)

`/etc/docker/daemon.json` — note `data-root` relocates ALL named volumes onto
the LUKS mount (§2); apply it before creating the first volume, or migrate:

```json
{
  "data-root": "/srv/breakdown/data/docker",
  "userns-remap": "default",
  "live-restore": true,
  "no-new-privileges": true,
  "log-driver": "journald"
}
```

> The `journald` log driver supports neither `max-size` nor `max-file` — those
> options belong to the `json-file`/`local` drivers. Journal retention is
> enforced centrally by `journald.conf` (§8).

Migrate an existing data root (once, with the stack down):

```bash
sudo systemctl stop docker.socket docker.service
sudo rsync -aHAX /var/lib/docker/ /srv/breakdown/data/docker/
sudo mv /var/lib/docker /var/lib/docker.old   # keep until verified, then delete
sudo systemctl start docker.service           # now uses the LUKS-backed root
docker volume ls && docker compose ps          # volumes intact?
```

Make Docker depend on the unlocked mount so it can never start first:

```bash
sudo systemctl edit docker.service   # enter:
# [Unit]
# Requires=srv-breakdown-data.mount
# After=srv-breakdown-data.mount
```

Notes and caveats:

- `userns-remap` remaps existing named-volume ownership — migrate data dirs
  (`chown` to the remapped subuid) **once**, then verify the services start.
  Do this during initial provisioning, not later under load.
- `no-new-privileges` applies daemon-wide via the flag above; additionally add
  `security_opt: ["no-new-privileges:true"]` per service in future compose work.
- Prefer read-only rootfs (`read_only: true`) + `cap_drop: ["ALL"]` with minimal
  `cap_add` per service where practical — stateless services first; Garage and
  step-ca need writable data paths but can still drop capabilities. Apply
  case-by-case and document deviations in the compose comments.
- Per-service memory/CPU limits limit blast radius on the small host
  (`mem_limit`, `cpus` in compose).

**Verify:**

```bash
docker info | grep -E 'Rootless|userns|Security'   # shows userns remap settings
docker inspect <container> --format '{{.HostConfig.CapDrop}} {{.HostConfig.Memory}}'
```

## 7. Patching SLA (ADR-026 §7) — manual, Arch rolling release

There is **no unattended-upgrades on Arch by design**. Instead:

| Control | Value |
|---|---|
| Owner | **@tradem** (release/ops owner) |
| Cadence | Weekly review, calendar reminder recurring every Monday |
| SLA | Security-relevant updates applied within **7 days** of review |
| Kernel reboots | Only after verifying the LUKS unlock path (console reachable, passphrase available in Vault `kv/host/luks-passphrase`) |

Weekly procedure (~30 min, Monday reminder):

```bash
sudo pacman -Syu                       # review the update list BEFORE confirming
pacman -Qtdq                           # remove orphaned packages
arch-audit --upgradable                # security-relevant? (pacman -S arch-audit)
```

If the kernel or systemd was updated:

1. Verify rescue console access works (log in once).
2. Verify the LUKS passphrase opens the volume (from the console, `cryptsetup open --test-passphrase /dev/vdb`).
3. Reboot, unlock manually per §3.2, confirm `docker compose ps` healthy.

Honest limitation (accepted risk): between reviews there is a window of up to
~7 days where a critical Arch package CVE is unfixed. Measure it, don't hide it.

**Verify:** the ops journal records each weekly review with date + decision;
`last reboot` shows reboots followed the unlock-path check.

## 8. Auditd (ADR-026 §9)

Install the checked-in ruleset [`host/audit.rules`](host/audit.rules)
(exec tracing incl. sudo, tamper watches on sshd/nftables/crypttab/docker
config and the data/volume subtrees) plus the retention config
[`host/auditd.conf`](host/auditd.conf):

```bash
sudo pacman -S audit
sudo install -D -m 640 docs/operations/host/audit.rules /etc/audit/rules.d/50-breakdown.rules
# Adjust the DATA_ROOT watch paths to the real mounts first.
sudo augenrules --load
sudo install -D -m 640 docs/operations/host/auditd.conf /etc/audit/auditd.conf
sudo systemctl enable --now auditd
```

Log storage & retention: `auditd` writes natively to
**`/var/log/audit/audit.log`** — journald retention settings do **not** apply
to that file. Rotation/retention is enforced by `auditd.conf`
(`max_log_file = 64` MiB, `num_logs = 10`, `max_log_file_action = keep_logs`).
For OpenTelemetry shipping (ADR-011), either run the audisp syslog plugin
(`/etc/audit/plugins.d/syslog.conf`, `active = yes`) to mirror events into
journald, or ship `audit.log` directly from the collector.

**Verify:**

```bash
sudo auditctl -l | wc -l                # > 0 rules loaded
sudo ausearch -k sudo-exec --recent     # returns entries after using sudo
logger test && sudo ausearch -m USER -ts recent | grep test
```

## 9. Quarterly restore drill

At least quarterly (owner @tradem, same calendar cadence as §7), prove the
encrypted form restores end-to-end — you cannot just `cat` a dump:

1. Pick the newest `/backups/*.dump.age`.
2. Unwrap the age identity (offline copy or vault-assisted recovery) and
   restore into a **scratch database** on the VPS:

   ```bash
   AGE_IDENTITY_FILE=/secure/path/age.key
   docker compose -f docker-compose.prod.yml exec -T postgres sh -c \
     'createdb -U "$POSTGRES_USER" restore_drill'
   age -d -i "$AGE_IDENTITY_FILE" < /backups/<latest>.dump.age \
     | docker compose -f docker-compose.prod.yml exec -T postgres sh -c \
         'pg_restore -U "$POSTGRES_USER" -d restore_drill --no-owner'
   ```

3. Sanity-check row counts against expectations (e.g. `projection_audit`,
   `projection_costume`).
4. Drop the scratch DB, record date + result in the ops journal.

Additionally once per year: restore the LUKS header from the offline backup
onto a loop device (§3.3 verify block).

**Verify:** dated entry in the ops journal; drill succeeded without touching
live data.

## 10. Host-side complements (ADR-024 / ADR-025 / ADR-027)

- **step-ca root read-only into containers (ADR-024):** the internal CA root
  reaches `api`/migrator/projector containers through the shared `tls_data`
  volume mounted `:ro`. Verify no service holds `tls_data` read-write unless it
  is `tls-provision` itself:

  ```bash
  grep -B2 'tls_data:/tls' docker-compose.prod.yml | grep ':ro'
  ```

- **Caddy ACME state & Vault data on LUKS (ADR-025/027):** both are named
  Docker volumes (`caddy_data`, `vault_data`) under the Docker data root,
  which is relocated onto the LUKS mount (`data-root`, §6) — covered
  automatically by §3. If either is ever moved to a bind-mount, it MUST go
  under `/srv/breakdown/data`.
- **DNS-01 provider token (ADR-025):** if DNS-01 issuance is used, the provider
  API token comes from Vault KV-v2 at container start — never from `.env`.
  `gitleaks` guards the repo side; this runbook guards the runtime side.

## 11. Acceptance checklist

| # | Control | Verified by |
|---|---|---|
| 1 | LUKS2 (Argon2id) on the data root; rootfs honestly excluded | §3.1 + caveat №2 |
| 2 | LUKS header + passphrase backed up offline | §3.3 |
| 3 | Dumps streamed through `age`, never plaintext on disk | §5 |
| 4 | nftables default-deny; only :22/:80/:443 public | §4.1 external probe |
| 5 | No internal port published (postgres loopback-only) | §4.2 |
| 6 | sshd key-only, hardened; fail2ban active | §4.3 |
| 7 | Docker userns-remap + cap/resource hygiene; data-root on LUKS | §6 |
| 8 | auditd exec/tamper/sudo rules loaded | §8 |
| 9 | Image digests pinned in prod compose | `grep -cE 'image:.*@sha256:' docker-compose.prod.yml` ≥ number of services |
| 10 | Weekly patching SLA, owner @tradem, Monday reminder | §7 ops journal |
| 11 | Rescue console verified; creds in vault | §4.4 |
| 12 | Quarterly encrypted-restore drill executed | §9 ops journal |
