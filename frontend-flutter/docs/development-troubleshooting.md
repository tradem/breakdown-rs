<!--
SPDX-License-Identifier: AGPL-3.0
Copyright (C) 2024-2026 Breakdown RS Contributors
Co-authored-by: glm-5.3-flash-flex (neuralwatt)
-->

# Development Troubleshooting

> Collected failure modes from local development (frontend-flutter focus),
> each with symptom → root cause → fix. New entries: newest first, keep the
> three-part structure.

## Troubleshooting

### `flutter`: "mkdir: … `.cache/flutter_sdk` … Socket ist nicht verbunden / unionfs failed"

**Symptom.** Every `flutter` invocation (build, test, `--version`) fails
immediately with:

```
mkdir: der Aufruf von stat für „/home/<you>/.cache/flutter_sdk“ ist nicht möglich:
Der Socket ist nicht verbunden
unionfs failed
```

The same breakage silently degrades tooling that shells out to the SDK —
most visibly the **Dart analysis server (dart LSP) fails to start** in
IDEs and agent harnesses ("unavailable server (dart)"), because the
analysis server binary lives on the same mount.

**Root cause.** On CachyOS, `/usr/bin/flutter` is the AUR wrapper
(`/opt/flutter/bin/aur_flutter`). It overlays the system SDK with a
user-writable copy-only-on-write unionfs:

```
~/.cache/flutter_local (RW)  ∪  /opt/flutter (RO)   →   ~/.cache/flutter_sdk
```

If the FUSE daemon behind `~/.cache/flutter_sdk` **dies** (e.g. killed at
session logout, OOM), the kernel keeps the mountpoint registered while the
filesystem backing it is gone. Every access then returns `ENOTCONN`
("Transport endpoint is not connected" / "Der Socket ist nicht verbunden"),
and the wrapper's re-mount check (`[ ! -e "$MOUNT_DIR/bin/flutter" ]`)
itself fails on the dead mount, so it can never self-heal.

**Diagnose.**

```bash
ls ~/.cache/flutter_sdk          # → "Transport endpoint is not connected" = dead FUSE mount
mount | grep flutter_sdk         # mount still registered
pgrep -af unionfs                # → no unionfs process = daemon is gone
```

**Fix.** Unmount the stale mount, then invoke `flutter` once — the wrapper
re-mounts on demand:

```bash
fusermount3 -u ~/.cache/flutter_sdk   # or: fusermount -u / umount -l
flutter --version                     # wrapper mounts ~/.cache/flutter_sdk again
```

Manual re-mount (equivalent to the wrapper's logic), if you need it without
running flutter:

```bash
unionfs -o cow -o umask=000 \
  "$HOME/.cache/flutter_local=RW:/opt/flutter=RO" "$HOME/.cache/flutter_sdk"
```

Afterwards restart the dart LSP in your IDE/agent session — it does not
recover on its own once its SDK path became unreachable.

**Prevention.** None built-in (the wrapper has no watchdog). If this
recurs regularly, wrap the unmount-remount in a small script or a systemd
user unit; `unionfsctl` exists but is not wired into the wrapper.

---

### Flutter test/build: "Can't load Kernel binary: Invalid SDK hash"

**Symptom.** After the unionfs mount above is repaired (or after a Flutter
SDK upgrade), `flutter test` / `flutter build` fails during native-asset
preparation:

```
Can't load Kernel binary: Invalid SDK hash.
  Building assets for package:<some_plugin> failed.
  build.dart returned with exit code: 253.
```

**Root cause.** Stale native-assets build cache: the `hook.dill` under
`.dart_tool/hooks_runner/<package>/<hash>/` was compiled by a different
Dart SDK than the one now running (SDK hash changed after a wrapper-SDK
swap or upgrade), and the cached kernel refuses to load.

**Fix.** Drop the native-assets cache only (keeps the rest of `.dart_tool`):

```bash
rm -rf .dart_tool/hooks_runner
flutter test   # or flutter build … — recompiles the hooks
```

---

### Related backend symptom (for context)

An app-side `ai_import.dto_invalid` during AI-import processing was traced
to a decode bug fixed in 0.4.0-alpha.36+87 (SSE job frames must decode via
`standardSerializers`); see the backend issue analysis and
`test/data/ai_import_sse_frame_decode_test.dart`. If you see that code on a
build **older** than `alpha.36`, redeploy — do not debug the backend first.
