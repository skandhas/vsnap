# vsnap

Tiny snapshots before bold edits.

`vsnap` is a tiny local snapshot tool for saving and restoring files before risky edits. It is lighter than Git, requires explicit paths, and gives you a simple way to keep safety snapshots, apply ignore rules, inspect snapshot health, and recover files from the terminal.

## Build

```sh
make build
```

The binary is written to `build/vsnap` or `build/vsnap.exe`, depending on the platform.

Clean build outputs:

```sh
make clean
```

## Test

```sh
make test
```

Use `--keep` to preserve the temporary smoke-test project for debugging:

```sh
v run scripts/smoke.vsh --keep
v run scripts/edge.vsh --keep
v run scripts/corruption.vsh --keep
```

## Usage

```sh
vsnap <command> [options]
```

Run `vsnap help` to show the command list, or `vsnap help <command>` for detailed command help. Command-local help is also available with `vsnap <command> --help`.

Core commands:

```sh
vsnap save
vsnap s
vsnap again
vsnap list
vsnap show
vsnap restore
vsnap rs
vsnap undo
vsnap clean
vsnap lock
vsnap doctor
vsnap config
vsnap version
```

## Common Examples

Preview a directory snapshot before writing anything:

```sh
vsnap save . -m "before refactor" --dry-run
```

Save selected files and directories:

```sh
vsnap save src README.md -m "before parser rewrite"
vsnap s src README.md -m "quick checkpoint"
```

Repeat the last successful save without retyping paths:

```sh
vsnap again -m "second pass"
```

Show recent snapshots and inspect the newest one:

```sh
vsnap list
vsnap show 1
vsnap show 1 --tree
```

Preview and then restore a snapshot:

```sh
vsnap restore 1 --dry-run
vsnap restore 1
vsnap rs 1
```

Undo the latest restore safety snapshot:

```sh
vsnap undo
```

Save a large explicit file by raising the per-file limit:

```sh
vsnap save data.sqlite -m "before migration" --max-file 200MB
```

Bypass the broad-save file-count guard when the large save is intentional:

```sh
vsnap save . -m "whole project, intentional" --force
```

Configure project defaults:

```sh
vsnap config limits.file.size 100MB
vsnap config limits.file.count 500
vsnap config --list
```

Check and clean the local snapshot store:

```sh
vsnap doctor
vsnap clean --keep 10
```

`save` requires explicit paths. Use `.` when you really want to snapshot the current directory. Add `--dry-run` to preview the files, size, limits, and skipped large files without creating `.vsnap`, an archive, or an index entry.

`save` flags may appear before or after normal paths. Use `--` before paths that start with `-`, for example `vsnap save --dry-run -- -dash.txt`.

After a successful manual save, `vsnap` stores the original save intent in `.vsnap/last-save.json`. Use `vsnap again` to repeat that save without retyping all paths. `again` reuses the previous paths, message, `--max-file` override, and `--force`; it does not reuse `--dry-run`. Pass `-m`, `--max-file`, `--force`, or `--dry-run` to override the repeated save.

Snapshots are stored in the current directory under `.vsnap/snapshots`. Directory saves recursively capture files while skipping built-in heavy or generated directories:

```txt
.vsnap
.git
.hg
.svn
node_modules
.venv
venv
dist
build
target
.cache
```

These built-in skips apply to recursive directory scans. Explicit file paths still represent user intent, so `vsnap save node_modules/pkg/file.js -m "explicit"` can save that file when it exists and passes the size limit.

Add `.vsnapignore` to skip project-specific files during directory scans:

```txt
# .vsnapignore
*.log
.env
tmp/
```

Files are stored as bytes, so text and binary files are both supported. To avoid accidental huge snapshots, a single file is limited to `25MB` by default. Large files found during directory scans are skipped and reported. A large file passed explicitly causes an error unless you raise the limit with `--max-file`.

To catch accidental broad saves such as an unintended `vsnap save .`, `save` stops when more than `200` files would be captured. Narrow the path, update `.vsnapignore`, or rerun with `--force` when the large snapshot is intentional.

Project settings live in `.vsnap/config.json` only when you create or set them. Use `vsnap config --list` to show effective settings, `vsnap config limits.file.size 100MB` to set the default single-file limit, and `vsnap config limits.file.count 500` to set the file-count guard. Command-line `--max-file` still overrides the configured file-size limit for one save.

`restore 1` restores files from the newest manual snapshot. Files created after the snapshot are intentionally left in place. Before extracting a snapshot, `restore` verifies the archive hash when available. Before overwriting current files, `restore` automatically creates a safety snapshot so `vsnap undo` can return to the pre-restore state.

Terminal output uses color when the terminal supports ANSI colors. Redirected output stays plain.

Write operations use an exclusive `.vsnap/lock` directory so two terminals do not update the snapshot store at the same time. If a previous process crashed and left a stale lock, inspect it with `vsnap lock status` and clear it with `vsnap lock clear`.

`clean --keep <n>` keeps the newest N manual snapshots and does not remove safety snapshots. Use `clean --keep 0` to remove all manual snapshots while leaving safety snapshots available for `undo`.

Run `vsnap doctor` to check the local snapshot store for parse errors, missing archives, incomplete temp archives, orphan archives, archive hash mismatches, unreadable manifests, and stale locks. Use `vsnap doctor --fast` to skip archive hash checks while still reading each archive manifest.

See [doc/DESIGN.md](doc/DESIGN.md) for the product and storage design.

## License

MIT. See [LICENSE](LICENSE).
