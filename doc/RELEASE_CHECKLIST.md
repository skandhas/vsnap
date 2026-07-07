# vsnap Release Checklist

Use this checklist before sharing a `vsnap` build outside the development folder.

## Version

- Update `app_version` in `models.v`.
- Run `vsnap version` and confirm the printed version.
- Keep the version label clear, for example `0.1.0`.

## Build

Clean old build outputs:

```sh
make clean
```

Windows:

```sh
make prod
```

The binary is written to `build/vsnap` or `build/vsnap.exe`, depending on the platform.

## Smoke Test

Run the cross-platform V shell smoke test:

```sh
make test
```

Keep the temporary test project when debugging a failure:

```sh
v run scripts/smoke.vsh --keep
v run scripts/edge.vsh --keep
v run scripts/corruption.vsh --keep
```

The smoke test builds `vsnap`, creates a temporary project, and checks `version`, `save --dry-run`, `save`, `list`, `show`, `show --tree`, `restore --dry-run`, `restore`, safety snapshots, `undo`, config guardrails, and `doctor`.

The edge test covers CLI misuse and boundary cases such as missing paths, external paths, oversized files, `.vsnapignore`, unknown config keys, missing snapshots, and lock conflicts.

The corruption test checks `doctor` against missing archives, hash mismatches, orphan archives, incomplete temp archives, invalid index JSON, and old snapshots without `archive_hash`.

## Package

Include:

- `build/vsnap` or `build/vsnap.exe`
- `README.md`
- `doc/DESIGN.md`

Do not include:

- `.vsnap/`
- local test directories
- compiler cache files

## Release Notes

Mention:

- Supported platform and architecture.
- Current storage location: `.vsnap/`.
- Current safety behavior: restore creates a safety snapshot unless `--no-safety`.
- Current limitations: no branch model, no remote sync, no exact directory reset by default.
