module main

import compress.szip
import crypto.sha256
import json
import os
import time

// save_files writes a zip archive and appends its snapshot index entry.
fn save_files(files []SnapshotFile, kind SnapshotKind, message string) !SnapshotIndex {
	ensure_store()!
	mut total := u64(0)
	mut manifest_files := []ManifestFile{}

	for file in files {
		total += file.size
		manifest_files << ManifestFile{
			path: file.path
			size: file.size
			hash: file.hash
		}
	}

	created := time.now().format_ss()
	id := make_snapshot_id(created, kind, message, files.len, total)
	archive := os.join_path(snapshot_dir, '${id}.zip')
	zip_path := os.join_path(store_path(), archive)
	tmp_zip_path := '${zip_path}.tmp'

	if os.exists(zip_path) {
		return error('snapshot archive already exists: ${archive}')
	}

	if os.exists(tmp_zip_path) {
		os.rm(tmp_zip_path)!
	}

	manifest := SnapshotManifest{
		id:      id
		kind:    kind
		created: created
		message: message
		root:    os.getwd()
		files:   manifest_files
	}

	defer {
		os.rm(tmp_zip_path) or {}
	}

	write_zip(tmp_zip_path, manifest, files)!
	archive_hash := file_hash(tmp_zip_path)!
	os.rename(tmp_zip_path, zip_path)!

	snap := SnapshotIndex{
		id:           id
		kind:         kind
		created:      created
		message:      message
		root:         os.getwd()
		archive:      archive
		archive_hash: archive_hash
		files:        files.len
		bytes:        total
	}

	append_index(snap)!
	return snap
}

// create_restore_safety_snapshot saves current versions of files restore would overwrite.
fn create_restore_safety_snapshot(target SnapshotIndex, overwritten []ManifestFile) !SnapshotIndex {
	mut files := []SnapshotFile{}

	for file in overwritten {
		full := os.join_path(os.getwd(), file.path)

		if os.exists(full) {
			files << snapshot_file(file.path, full)!
		}
	}

	return save_files(files, .safety, 'before restoring ${target.id}')!
}

// ensure_store creates the .vsnap directory, snapshots directory, and index file.
fn ensure_store() ! {
	ensure_store_root()!
	os.mkdir_all(os.join_path(store_path(), snapshot_dir))!
	index_path := os.join_path(store_path(), index_name)

	if !os.exists(index_path) {
		os.write_file(index_path, '')!
	}
}

// store_path returns the project-local .vsnap path.
fn store_path() string {
	return os.join_path(os.getwd(), store_dir)
}

// write_zip writes the snapshot manifest and file entries into a zip archive.
fn write_zip(zip_path string, manifest SnapshotManifest, files []SnapshotFile) ! {
	mut zip := szip.open(zip_path, .default_compression, .write)!

	defer {
		zip.close()
	}

	zip.open_entry(manifest_name)!
	zip.write_entry(json.encode_pretty(manifest).bytes())!
	zip.close_entry()

	for file in files {
		zip.open_entry(file.path)!
		zip.create_entry(file.full)!
		zip.close_entry()
	}
}

// read_index reads all valid snapshot index lines from .vsnap/index.jsonl.
fn read_index() ![]SnapshotIndex {
	index_path := os.join_path(store_path(), index_name)

	if !os.exists(index_path) {
		return []SnapshotIndex{}
	}

	content := os.read_file(index_path)!
	mut snaps := []SnapshotIndex{}

	for line in content.split_into_lines() {
		trimmed := line.trim_space()

		if trimmed == '' {
			continue
		}

		snaps << json.decode(SnapshotIndex, trimmed)!
	}

	return snaps
}

// append_index appends one snapshot record to index.jsonl.
fn append_index(snap SnapshotIndex) ! {
	ensure_store()!
	index_path := os.join_path(store_path(), index_name)
	mut file := os.open_append(index_path)!

	defer {
		file.close()
	}

	file.write_string(json.encode(snap) + '\n')!
}

// write_index rewrites index.jsonl via a temporary file.
fn write_index(snaps []SnapshotIndex) ! {
	ensure_store()!
	mut content := ''

	for snap in snaps {
		content += json.encode(snap) + '\n'
	}

	index_path := os.join_path(store_path(), index_name)
	tmp_path := '${index_path}.tmp-${os.getpid()}'

	if os.exists(tmp_path) {
		os.rm(tmp_path)!
	}

	defer {
		os.rm(tmp_path) or {}
	}

	os.write_file(tmp_path, content)!
	os.mv(tmp_path, index_path, overwrite: true)!
}

// listed_snapshots returns snapshots in newest-first display order.
fn listed_snapshots(show_all bool) ![]SnapshotIndex {
	snaps := newest_first(read_index()!)

	if show_all {
		return snaps
	}

	return snaps.filter(it.kind != .safety)
}

// resolve_snapshot resolves a list number or snapshot id prefix to one snapshot.
fn resolve_snapshot(selector string) !SnapshotIndex {
	all := newest_first(read_index()!)

	if all.len == 0 {
		return error('no snapshots yet')
	}

	if selector.int() > 0 {
		visible := all.filter(it.kind != .safety)
		n := selector.int()

		if n > visible.len {
			return error('snapshot number out of range')
		}

		return visible[n - 1]
	}

	mut matches := []SnapshotIndex{}

	for snap in all {
		if snap.id.starts_with(selector) {
			matches << snap
		}
	}

	if matches.len == 0 {
		return error('no snapshot matches ${selector}')
	}

	if matches.len > 1 {
		return error('snapshot selector is ambiguous: ${selector}')
	}

	return matches[0]
}

// latest_safety_snapshot returns the newest restore safety snapshot.
fn latest_safety_snapshot() !SnapshotIndex {
	for snap in newest_first(read_index()!) {
		if snap.kind == .safety {
			return snap
		}
	}

	return error('no safety snapshot to undo')
}

// verify_snapshot_archive checks that an archive exists and matches its recorded hash.
fn verify_snapshot_archive(snap SnapshotIndex) ! {
	zip_path := os.join_path(store_path(), snap.archive)

	if !os.exists(zip_path) {
		return error('snapshot archive is missing: ${zip_path}')
	}

	if snap.archive_hash == '' {
		eprintln('${c_warn('warning:')} ${snap.id} has no archive hash; restore integrity check skipped')
		return
	}

	current_hash := file_hash(zip_path)!

	if current_hash != snap.archive_hash {
		return error('snapshot archive hash mismatch: ${snap.id}')
	}
}

// extract_snapshot verifies and extracts a snapshot into a temporary directory.
fn extract_snapshot(snap SnapshotIndex) !(SnapshotManifest, string) {
	verify_snapshot_archive(snap)!
	zip_path := os.join_path(store_path(), snap.archive)
	temp := os.join_path(store_path(), 'tmp-${snap.id}-${os.getpid()}')

	if os.exists(temp) {
		os.rmdir_all(temp)!
	}

	os.mkdir_all(temp)!
	mut keep_temp := false

	defer {
		if !keep_temp {
			os.rmdir_all(temp) or {}
		}
	}

	szip.extract_zip_to_dir(zip_path, temp)!
	manifest_path := os.join_path(temp, manifest_name)

	if !os.exists(manifest_path) {
		return error('snapshot manifest is missing: ${snap.id}')
	}

	manifest := json.decode(SnapshotManifest, os.read_file(manifest_path)!)!
	keep_temp = true
	return manifest, temp
}

// read_manifest_from_archive reads only the manifest entry from a snapshot archive.
fn read_manifest_from_archive(snap SnapshotIndex) !SnapshotManifest {
	zip_path := os.join_path(store_path(), snap.archive)

	if !os.exists(zip_path) {
		return error('snapshot archive is missing: ${zip_path}')
	}

	mut zip := szip.open(zip_path, .default_compression, .read_only)!

	defer {
		zip.close()
	}

	total := zip.total()!

	for i in 0 .. total {
		zip.open_entry_by_index(i)!
		name := zip.name()

		if name == manifest_name {
			size := int(zip.size())
			mut buf := []u8{len: size}

			if size > 0 {
				zip.read_entry_buf(buf.data, size)!
			}

			zip.close_entry()
			return json.decode(SnapshotManifest, buf.bytestr())!
		}

		zip.close_entry()
	}

	return error('snapshot manifest is missing: ${snap.id}')
}

// make_snapshot_id creates a timestamped id with a short deterministic suffix.
fn make_snapshot_id(created string, kind SnapshotKind, message string, files int, bytes u64) string {
	stamp := created.replace('-', '').replace(':', '').replace(' ', '-')
	suffix := sha256.hexhash('${created}|${kind.label()}|${message}|${files}|${bytes}')[..6]
	return '${stamp}-${suffix}'
}

// newest_first returns a reversed copy of snapshots for display.
fn newest_first(snaps []SnapshotIndex) []SnapshotIndex {
	mut out := snaps.clone()
	out.reverse_in_place()
	return out
}
