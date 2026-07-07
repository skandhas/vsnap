# vsnap Design

`vsnap` is a tiny local insurance tool for bold edits. It is intentionally not a miniature Git. Its job is to let a user say, "I am about to try something risky; preserve these files or directories so I can get back."

## Product Direction

The chosen direction is **one-click insurance before bold edits**.

This means:

- `save` always requires explicit paths.
- `save` supports both files and directories.
- `restore` is conservative by default.
- `restore` does not delete files created after a snapshot.
- `restore` creates a safety snapshot before overwriting current files.
- `diff` and history management are secondary to impact previews and safe recovery.

## Command Shape

```sh
vsnap save <path...> -m "message"
vsnap save <path...> -m "message" --dry-run
vsnap save <path...> -m "message" --force
vsnap s <path...> -m "message"
vsnap again
vsnap again -m "message" --dry-run
vsnap list
vsnap list --all
vsnap show <id|number>
vsnap show <id|number> --tree
vsnap restore <id|number>
vsnap restore <id|number> --dry-run
vsnap restore <id|number> --no-safety
vsnap rs <id|number>
vsnap undo
vsnap clean --keep <n>
vsnap doctor
vsnap doctor --fast
vsnap config --list
vsnap config limits
vsnap config limits.file
vsnap config limits.file.size 100MB
vsnap config limits.file.count 500
vsnap config --unset limits.file.size
vsnap version
vsnap help <command>
```

`s` is kept as a short alias for `save`. `rs` and `rollback` are kept as aliases for `restore`, but `restore` is the primary term because the default behavior is not an exact reset.

Top-level help is intentionally compact. It lists commands only; detailed options and examples live under `vsnap help <command>` and `vsnap <command> --help`.

## Save Semantics

`save` accepts one or more explicit paths:

```sh
vsnap save . -m "whole project"
vsnap save . -m "whole project" --dry-run
vsnap save README.md -m "docs"
vsnap save src config.toml -m "parser work"
vsnap save --dry-run -m "dash path" -- -dash.txt
```

Directories are scanned recursively. Files are included directly. Mixed paths are deduplicated. Paths outside the current working directory are rejected in the first version because restoring external paths from a project-local `.vsnap` folder is easy to misunderstand.

Save flags may appear before or after normal paths. A literal `--` ends option parsing for `save`; everything after it is treated as a path. This keeps paths that start with `-` unambiguous, such as `vsnap save -- -dash.txt`.

Each successful manual save writes `.vsnap/last-save.json`, which records the save intent: original paths, message, explicit `--max-file` bytes if present, and `--force`. `vsnap again` reads that intent and repeats the save. It rescans directories instead of reusing the previous file list, so newly created files under a saved directory can be captured. `again --dry-run` previews the repeated save and does not update `last-save.json`.

The scanner skips common heavy or generated directories during recursive directory scans:

```txt
.vsnap .git .hg .svn node_modules .venv venv dist build target .cache
```

Projects can add `.vsnapignore` for project-specific directory-scan exclusions:

```txt
# comments and blank lines are ignored
*.log
.env
tmp/
/root-only.out
docs/generated/
```

The first version intentionally supports a small subset:

- blank lines
- `#` comments
- exact file or directory names, such as `.env`
- directory rules ending in `/`, such as `tmp/`
- simple `*` wildcards, such as `*.log`
- rooted rules starting with `/`

Ignore rules apply to recursive directory scans. Explicitly passed files are treated as user intent and are not blocked by `.vsnapignore`.

The built-in skipped directories and `.vsnapignore` rules are additive during directory scans. `.vsnapignore` does not provide negation rules and cannot re-include built-in skipped directories.

After scanning, `save` applies a file-count guard. If more than `200` files would be captured, the command stops before writing a snapshot. This catches accidental broad saves such as `vsnap save .` in a large project. Users can narrow the path, update `.vsnapignore`, or pass `--force` when the large snapshot is intentional.

The file-count guard can be configured with `limits.file.count` in `.vsnap/config.json`.

`save --dry-run` uses the same scanner, ignore rules, size limit, and file-count guard as a real save. It prints the files that would be captured, the total size, skipped large files, and whether the file-count guard would stop the operation. It does not create `.vsnap`, acquire the write lock, write an archive, or append the index.

## Large Files and Binary Files

Files are saved as bytes, so binary files are supported by default. Hashes are computed from bytes as well.

To avoid accidental huge snapshots, `save` applies a default single-file limit of `25MB`.

Rules:

- Text files and small binary files are saved normally.
- Large files discovered while scanning a directory are skipped and reported.
- Large files passed explicitly are treated as user intent, so `vsnap` fails with a clear message instead of silently skipping them.
- Users can raise the limit with `--max-file`.

Examples:

```sh
vsnap save . -m "before refactor"
vsnap save data.sqlite -m "before migration" --max-file 200MB
vsnap save assets -m "before asset pass" --max-file 1GB
vsnap save . -m "whole project, intentional" --force
```

Supported size suffixes are `B`, `KB`, `MB`, and `GB`. A bare number is interpreted as bytes.

This keeps the default workflow fast and honest: `vsnap save .` should not quietly capture hundreds of files, but `vsnap` should still be able to protect a broad tree or binary file when the user explicitly asks for it.

The single-file limit can be configured with `limits.file.size`. A one-off `--max-file` command-line option takes precedence over configuration.

## Configuration

Project configuration is optional and lives at `.vsnap/config.json`. It is not created by normal commands. Users can create it explicitly:

```sh
vsnap config --init
```

The first version supports:

```json
{
  "limits": {
    "file": {
      "size": "25MB",
      "count": 200
    }
  }
}
```

Configuration uses dot-path commands:

```sh
vsnap config --list
vsnap config limits
vsnap config limits.file
vsnap config limits.file.size
vsnap config limits.file.size 100MB
vsnap config limits.file.count 500
vsnap config --unset limits.file.size
vsnap config --unset limits.file.count
```

Query commands support groups and prefixes. Set and unset commands only support leaf keys. `--unset limits` and `--unset limits.file` are intentionally rejected.

Effective precedence:

```txt
--max-file > limits.file.size > 25MB
limits.file.count > 200
--force skips limits.file.count for that save
```

## Restore Semantics

`restore` computes an impact preview before writing:

```txt
overwrite: files that exist and differ from the snapshot
recreate:  files missing locally but present in the snapshot
unchanged: files already identical to the snapshot
```

Default restore behavior:

- Verify the archive hash before extraction when `archive_hash` is available.
- Overwrite changed files recorded in the snapshot.
- Recreate missing files recorded in the snapshot.
- Leave files not recorded in the snapshot untouched.
- Create a safety snapshot before overwriting current files.

Older snapshots without `archive_hash` remain restorable. `restore` prints a warning and skips the archive integrity check for those snapshots.

`--dry-run` prints the impact preview and writes nothing.

`--no-safety` skips the automatic restore-before snapshot. It is mainly for scripts or cases where the user is certain.

`undo` restores the newest safety snapshot.

## Storage

Snapshots live in the current directory:

```txt
.vsnap/
  index.jsonl
  lock/
    owner.json
  snapshots/
    20260702-103012-a3f2.zip
```

`index.jsonl` is append-friendly and human-readable. Each line is one `SnapshotIndex` record:

```json
{"id":"20260702-103012-a3f2","kind":"manual","created":"2026-07-02 10:30:12","message":"before refactor","root":"C:/project","archive":"snapshots/20260702-103012-a3f2.zip","archive_hash":"...","files":12,"bytes":8421}
```

Each zip contains `__vsnap_manifest.json` plus the captured files. The manifest records path, size, and SHA-256 hash for every file:

```json
{
  "id": "20260702-103012-a3f2",
  "kind": "manual",
  "created": "2026-07-02 10:30:12",
  "message": "before refactor",
  "root": "C:/project",
  "files": [
    {"path": "src/main.v", "size": 1200, "hash": "..."}
  ]
}
```

Hashes are used for restore impact previews. They are not meant to turn `vsnap` into a full version-control system.

Saves are ordered to avoid indexing partial archives:

```txt
write snapshots/<id>.zip.tmp
close archive
compute archive hash
rename to snapshots/<id>.zip
append one JSON line to index.jsonl
```

If a process is interrupted before the rename, `doctor` can report the leftover `.zip.tmp` as an incomplete archive. If interruption happens after the rename but before the index append, `doctor` can report the `.zip` as an orphan archive.

Index rewrites, such as `clean`, are written to a temporary index file before replacing `index.jsonl`. `clean` updates the index before deleting archives that are no longer referenced. If the process is interrupted after the index rewrite but before archive deletion finishes, the remaining archive files are harmless orphans and `doctor` reports them.

## Locking

`vsnap` uses a project-local exclusive lock for operations that mutate `.vsnap` or the working tree:

```txt
.vsnap/lock/
  owner.json
```

The lock is acquired by creating the `lock` directory. Directory creation is used because it is atomic on normal local filesystems: one process succeeds, concurrent processes fail.

Locked commands:

- `save`
- `restore`
- `undo`
- `clean`
- `config` writes

Unlocked commands:

- `list`
- `show`
- `config` reads
- `lock status`
- `lock clear`

`owner.json` records:

```json
{"pid":12345,"command":"restore","created":"2026-07-03 10:15:00"}
```

If a command cannot acquire the lock, it reports the command, pid, and creation time of the active lock. If a process crashes and leaves a stale lock, the user can run:

```sh
vsnap lock status
vsnap lock clear
```

`restore` extraction directories include the current pid, for example `tmp-<snapshot-id>-<pid>`, so read-only commands and concurrent processes do not share the same temporary folder.

## Doctor

`vsnap doctor` is a read-only store health check. It verifies:

- `.vsnap` exists and is a directory
- `snapshots/` exists
- `index.jsonl` can be read
- every non-empty index line is valid JSON
- snapshot ids are not duplicated
- every indexed archive exists
- incomplete archive temp files are reported
- archive files not referenced by the index are reported
- archive SHA-256 matches the `archive_hash` recorded in the index
- every archive contains a readable `__vsnap_manifest.json`
- manifest id matches the index id
- index file count and byte count match the manifest
- lock status is visible

Findings are printed as `ok`, `warn`, or `error`. Warnings are informational; errors make `doctor` exit non-zero.

Older snapshots created before `archive_hash` existed remain readable. `doctor` reports them with a warning instead of treating them as corrupt.

`vsnap doctor --fast` skips archive SHA-256 verification but still checks that each archive exists, opens, contains a readable manifest, and matches the index counts. Fast mode prints a warning for each skipped archive hash so the output is not mistaken for a full integrity check.

## Snapshot Kinds

`manual` snapshots are created by explicit `save` commands.

`safety` snapshots are created automatically before `restore` overwrites current files. `list` hides safety snapshots by default; `list --all` shows them.

`clean --keep <n>` keeps the newest N manual snapshots and removes older manual snapshots. It does not remove safety snapshots. `clean --keep 0` removes all manual snapshots while leaving safety snapshots available for `undo`.

## Non-Goals

The first design intentionally avoids:

- Branches
- Merges
- Parent commit chains
- Exact directory reset by default
- Line-level diff as a core workflow
- Remote sync
- Staging or partial commit semantics

Those features belong to Git's world. `vsnap` stays focused on fast, explicit, local safety.
