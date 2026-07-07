module main

import crypto.sha256
import os

const skipped_dirs = ['.vsnap', '.git', '.hg', '.svn', 'node_modules', '.venv', 'venv', 'dist',
	'build', 'target', '.cache']

const hash_chunk_size = 1024 * 1024

struct SnapshotFile {
	// path is the normalized path stored inside the snapshot archive.
	path string

	// full is the absolute local filesystem path read during save.
	full string

	// size is the file size in bytes.
	size u64

	// hash is the SHA-256 hash of the file bytes.
	hash string
}

struct SkippedFile {
	// path is the normalized path skipped during directory scanning.
	path string

	// size is the skipped file size in bytes.
	size u64

	// reason explains why the file was not included.
	reason string
}

struct ScanOptions {
	// max_file_bytes is the single-file size limit for this scan.
	max_file_bytes u64 = default_max_file_bytes
}

struct IgnoreRule {
	// pattern is the normalized ignore pattern.
	pattern string

	// dir_only means the rule only applies to directories.
	dir_only bool

	// rooted means the rule is anchored at the project root.
	rooted bool

	// has_slash means the rule should match against the full relative path.
	has_slash bool
}

struct ScanResult {
	// files contains files selected for the snapshot.
	files []SnapshotFile

	// skipped contains large files skipped during directory scans.
	skipped []SkippedFile
}

// scan_targets scans explicit files and directories into a deduplicated snapshot plan.
fn scan_targets(root string, targets []string, options ScanOptions) !ScanResult {
	mut files := []SnapshotFile{}
	mut skipped := []SkippedFile{}
	ignore_rules := load_ignore_rules(root)!

	for target in targets {
		collect_target(root, target, options, ignore_rules, mut files, mut skipped)!
	}

	files = unique_files(files)

	if files.len == 0 {
		return error('nothing to snapshot')
	}

	return ScanResult{
		files:   files
		skipped: skipped
	}
}

// collect_target validates one user path and dispatches file or directory scanning.
fn collect_target(root string, target string, options ScanOptions, ignore_rules []IgnoreRule, mut files []SnapshotFile, mut skipped []SkippedFile) ! {
	full := if os.is_abs_path(target) { target } else { os.join_path(root, target) }

	if !os.exists(full) {
		return error('path does not exist: ${target}')
	}

	if !is_inside_root(root, full) {
		return error('path is outside current directory: ${target}')
	}

	rel := relative_to_root(root, full)

	if os.is_dir(full) {
		collect_dir(root, rel, options, ignore_rules, mut files, mut skipped)!
		return
	}

	size := os.file_size(full)

	if size > options.max_file_bytes {
		return error('${normalize_entry(rel)} is ${human_bytes(size)}, above max file size ${human_bytes(options.max_file_bytes)}. Use --max-file to include it.')
	}

	files << snapshot_file(rel, full)!
}

// collect_dir recursively scans a directory while applying ignore and size rules.
fn collect_dir(root string, rel string, options ScanOptions, ignore_rules []IgnoreRule, mut files []SnapshotFile, mut skipped []SkippedFile) ! {
	dir := if rel == '' || rel == '.' { root } else { os.join_path(root, rel) }

	for name in os.ls(dir)! {
		if name in skipped_dirs {
			continue
		}

		child_rel := if rel == '' || rel == '.' { name } else { os.join_path(rel, name) }
		child_entry := normalize_entry(child_rel)
		full := os.join_path(dir, name)

		if os.is_dir(full) {
			if is_ignored(child_entry, true, ignore_rules) {
				continue
			}

			collect_dir(root, child_rel, options, ignore_rules, mut files, mut skipped)!
		} else {
			if is_ignored(child_entry, false, ignore_rules) {
				continue
			}

			size := os.file_size(full)

			if size > options.max_file_bytes {
				skipped << SkippedFile{
					path:   child_entry
					size:   size
					reason: 'above max file size ${human_bytes(options.max_file_bytes)}'
				}

				continue
			}

			files << snapshot_file(child_rel, full)!
		}
	}
}

// snapshot_file creates a snapshot file record including size and streaming hash.
fn snapshot_file(rel string, full string) !SnapshotFile {
	return SnapshotFile{
		path: normalize_entry(rel)
		full: full
		size: os.file_size(full)
		hash: file_hash(full)!
	}
}

// unique_files removes duplicate paths while preserving first-seen order.
fn unique_files(files []SnapshotFile) []SnapshotFile {
	mut seen := map[string]bool{}
	mut out := []SnapshotFile{}

	for file in files {
		if file.path == '' || seen[file.path] {
			continue
		}

		seen[file.path] = true
		out << file
	}

	return out
}

// is_inside_root reports whether a resolved path stays inside the current root.
fn is_inside_root(root string, full string) bool {
	root_real := normalized_real(root).trim_right('/')
	full_real := normalized_real(full)
	return full_real == root_real || full_real.starts_with(root_real + '/')
}

// relative_to_root returns a normalized path relative to the project root.
fn relative_to_root(root string, full string) string {
	root_real := normalized_real(root).trim_right('/')
	full_real := normalized_real(full)
	prefix := root_real + '/'

	if full_real.starts_with(prefix) {
		return full_real[prefix.len..]
	}

	return os.base(full)
}

// normalized_real resolves a path and normalizes separators to forward slashes.
fn normalized_real(path string) string {
	return os.real_path(path).replace('\\', '/')
}

// normalize_entry normalizes an archive entry path.
fn normalize_entry(path string) string {
	mut out := path.replace('\\', '/')

	for out.starts_with('./') {
		out = out[2..]
	}

	return out.trim_left('/')
}

// file_hash computes a SHA-256 hash without loading the whole file into memory.
fn file_hash(path string) !string {
	mut file := os.open(path)!

	defer {
		file.close()
	}

	mut digest := sha256.new()
	mut buffer := []u8{len: hash_chunk_size}

	for {
		n := file.read(mut buffer) or {
			if err is os.Eof {
				break
			}

			return err
		}

		if n <= 0 {
			break
		}

		digest.write(buffer[..n])!
	}

	return digest.sum([]).hex()
}

// load_ignore_rules reads project .vsnapignore rules if present.
fn load_ignore_rules(root string) ![]IgnoreRule {
	path := os.join_path(root, ignore_name)

	if !os.exists(path) {
		return []IgnoreRule{}
	}

	mut rules := []IgnoreRule{}

	for line in os.read_file(path)!.split_into_lines() {
		rule := parse_ignore_rule(line)

		if rule.pattern != '' {
			rules << rule
		}
	}

	return rules
}

// parse_ignore_rule parses one .vsnapignore line into an ignore rule.
fn parse_ignore_rule(line string) IgnoreRule {
	mut raw := line.trim_space()

	if raw == '' || raw.starts_with('#') {
		return IgnoreRule{}
	}

	mut dir_only := false

	if raw.ends_with('/') || raw.ends_with('\\') {
		dir_only = true
		raw = raw.trim_right('/\\')
	}

	mut rooted := false

	if raw.starts_with('/') || raw.starts_with('\\') {
		rooted = true
		raw = raw.trim_left('/\\')
	}

	pattern := normalize_entry(raw)
	return IgnoreRule{
		pattern:   pattern
		dir_only:  dir_only
		rooted:    rooted
		has_slash: pattern.contains('/')
	}
}

// is_ignored reports whether an entry matches any ignore rule.
fn is_ignored(entry string, is_dir bool, rules []IgnoreRule) bool {
	for rule in rules {
		if rule.dir_only && !is_dir {
			continue
		}

		if ignore_rule_matches(rule, entry, is_dir) {
			return true
		}
	}

	return false
}

// ignore_rule_matches checks one parsed ignore rule against one entry.
fn ignore_rule_matches(rule IgnoreRule, entry string, is_dir bool) bool {
	if rule.pattern == '' {
		return false
	}

	if rule.rooted || rule.has_slash {
		if wildcard_match(rule.pattern, entry) {
			return true
		}

		return is_dir && entry.starts_with(rule.pattern.trim_right('/') + '/')
	}

	base := entry_base(entry)

	if wildcard_match(rule.pattern, base) {
		return true
	}

	if is_dir && wildcard_match(rule.pattern, entry) {
		return true
	}

	return false
}

// entry_base returns the final path component of a normalized entry.
fn entry_base(entry string) string {
	parts := entry.split('/')

	if parts.len == 0 {
		return entry
	}

	return parts[parts.len - 1]
}

// wildcard_match matches a simple pattern with '*' wildcards.
fn wildcard_match(pattern string, text string) bool {
	if !pattern.contains('*') {
		return pattern == text
	}

	parts := pattern.split('*')
	mut pos := 0

	if parts.len > 0 && parts[0] != '' {
		if !text.starts_with(parts[0]) {
			return false
		}

		pos = parts[0].len
	}

	for i := 1; i < parts.len; i++ {
		part := parts[i]

		if part == '' {
			continue
		}

		found := text[pos..].index(part) or { return false }
		pos += found + part.len
	}

	last := parts[parts.len - 1]

	if last != '' && !text.ends_with(last) {
		return false
	}

	return true
}
