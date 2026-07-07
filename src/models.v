module main

const app_version = '0.1.0'

const store_dir = '.vsnap'
const snapshot_dir = 'snapshots'
const index_name = 'index.jsonl'
const manifest_name = '__vsnap_manifest.json'
const lock_dir = 'lock'
const lock_owner_name = 'owner.json'
const ignore_name = '.vsnapignore'
const config_name = 'config.json'
const last_save_name = 'last-save.json'

const default_max_file_bytes = u64(25 * 1024 * 1024)
const default_max_snapshot_files = 200

enum SnapshotKind {
	manual
	safety
}

struct ManifestFile {
pub:
	// path is the normalized path stored in the manifest.
	path string

	// size is the file size in bytes recorded at save time.
	size u64

	// hash is the SHA-256 hash recorded at save time.
	hash string
}

struct SnapshotManifest {
pub:
	// id is the snapshot identifier.
	id string

	// kind distinguishes manual snapshots from restore safety snapshots.
	kind SnapshotKind

	// created is the local timestamp when the snapshot was created.
	created string

	// message is the user-facing snapshot message.
	message string

	// root is the working directory where the snapshot was created.
	root string

	// files is the manifest entry list stored inside the archive.
	files []ManifestFile
}

struct SnapshotIndex {
pub:
	// id is the snapshot identifier shown to users.
	id string

	// kind records whether this is a manual or safety snapshot.
	kind SnapshotKind

	// created is the local timestamp used for sorting and display.
	created string

	// message is the user-facing snapshot message.
	message string

	// root is the working directory where the snapshot was created.
	root string

	// archive is the relative path to the zip archive under .vsnap.
	archive string

	// archive_hash is the SHA-256 hash of the complete archive.
	archive_hash string

	// files is the number of files captured in the archive.
	files int

	// bytes is the total size of captured file contents.
	bytes u64
}

struct LockOwner {
pub:
	// pid is the process id that acquired the lock.
	pid int

	// command is the operation holding the lock.
	command string

	// created is the local timestamp when the lock was acquired.
	created string
}

struct VSnapConfig {
pub mut:
	// limits groups safety limits used by save.
	limits ConfigLimits
}

struct ConfigLimits {
pub mut:
	// file contains per-file and per-snapshot file limits.
	file ConfigFileLimits
}

struct ConfigFileLimits {
pub mut:
	// size is the optional configured single-file limit, such as 100MB.
	size ?string @[omitempty]

	// count is the optional configured maximum number of files per save.
	count ?int @[omitempty]
}

struct LastSaveIntent {
pub mut:
	// paths are the original explicit paths requested by the last successful save.
	paths []string

	// message is the snapshot message from the last successful save.
	message string

	// max_file_bytes is the explicit max-file override in bytes.
	max_file_bytes u64

	// max_file_bytes_set records whether the last save had --max-file.
	max_file_bytes_set bool

	// force records whether the last save bypassed the file-count guard.
	force bool
}

// label returns the display label for a snapshot kind.
fn (kind SnapshotKind) label() string {
	return match kind {
		.manual { 'manual' }
		.safety { 'safety' }
	}
}
