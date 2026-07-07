module main

import json
import os

enum DoctorLevel {
	ok
	warn
	error
}

struct DoctorReport {
mut:
	// ok is the number of healthy checks.
	ok int

	// warn is the number of non-fatal findings.
	warn int

	// error is the number of fatal findings.
	error int

	// entries stores findings in display order.
	entries []DoctorEntry
}

struct CmdDoctor {
	// fast skips archive hash verification.
	fast bool
}

struct DoctorEntry {
	// level is the severity of this doctor finding.
	level DoctorLevel

	// message is the user-facing finding text.
	message string
}

// label returns the display label for a doctor severity.
fn (level DoctorLevel) label() string {
	return match level {
		.ok { 'ok' }
		.warn { 'warn' }
		.error { 'error' }
	}
}

// execute executes a doctor command after handwritten argument parsing.
fn (cmd CmdDoctor) execute() ! {
	mut report := DoctorReport{}
	check_store(mut report)
	check_lock(mut report)
	check_index_and_archives(mut report, cmd)
	print_doctor_report(report)

	if report.error > 0 {
		return error('doctor found ${report.error} errors')
	}
}

// check_store verifies the .vsnap directory and snapshots directory.
fn check_store(mut report DoctorReport) {
	if !os.exists(store_path()) {
		report.add_warn('no .vsnap directory in current folder')
		return
	}

	if !os.is_dir(store_path()) {
		report.add_error('.vsnap exists but is not a directory')
		return
	}

	report.add_ok('.vsnap directory exists')
	snapshots := os.join_path(store_path(), snapshot_dir)

	if os.exists(snapshots) && os.is_dir(snapshots) {
		report.add_ok('snapshots directory exists')
	} else {
		report.add_error('snapshots directory is missing')
	}
}

// check_lock reports active or unreadable operation locks.
fn check_lock(mut report DoctorReport) {
	if !os.exists(lock_path()) {
		report.add_ok('no active lock')
		return
	}

	owner := read_lock_owner() or {
		report.add_warn('lock directory exists, but owner metadata is unreadable')
		return
	}

	report.add_warn('active lock: ${owner.command} pid=${owner.pid} since ${owner.created}')
}

// check_index_and_archives reads index.jsonl and checks all referenced archives.
fn check_index_and_archives(mut report DoctorReport, cmd CmdDoctor) {
	index_path := os.join_path(store_path(), index_name)

	if !os.exists(index_path) {
		report.add_warn('index.jsonl is missing')
		return
	}

	report.add_ok('index.jsonl exists')
	content := os.read_file(index_path) or {
		report.add_error('cannot read index.jsonl: ${err}')
		check_snapshot_directory_artifacts(mut report, map[string]bool{})
		return
	}

	mut seen := map[string]bool{}
	mut indexed_archives := map[string]bool{}
	mut count := 0

	for line_no, line in content.split_into_lines() {
		trimmed := line.trim_space()

		if trimmed == '' {
			continue
		}

		count++
		snap := json.decode(SnapshotIndex, trimmed) or {
			report.add_error('index line ${line_no + 1} is invalid JSON: ${err}')
			continue
		}

		if snap.id == '' {
			report.add_error('index line ${line_no + 1} has empty snapshot id')
			continue
		}

		if seen[snap.id] {
			report.add_warn('duplicate snapshot id in index: ${snap.id}')
		}

		seen[snap.id] = true

		if snap.archive != '' {
			indexed_archives[normalize_entry(snap.archive)] = true
		}

		check_snapshot_archive(mut report, snap, cmd)
	}

	check_snapshot_directory_artifacts(mut report, indexed_archives)

	if count == 0 {
		report.add_warn('index.jsonl contains no snapshots')
	} else {
		report.add_ok('checked ${count} index entries')
	}
}

// check_snapshot_archive validates one indexed snapshot archive and manifest.
fn check_snapshot_archive(mut report DoctorReport, snap SnapshotIndex, cmd CmdDoctor) {
	archive_path := os.join_path(store_path(), snap.archive)

	if snap.archive == '' {
		report.add_error('${snap.id}: archive path is empty')
		return
	}

	if !os.exists(archive_path) {
		report.add_error('${snap.id}: archive missing: ${snap.archive}')
		return
	}

	if cmd.fast {
		report.add_warn('${snap.id}: archive hash skipped in fast mode')
	} else if snap.archive_hash == '' {
		report.add_warn('${snap.id}: archive hash is missing in index')
	} else {
		current_hash := file_hash(archive_path) or {
			report.add_error('${snap.id}: cannot hash archive: ${err}')
			return
		}

		if current_hash != snap.archive_hash {
			report.add_error('${snap.id}: archive hash mismatch')
		} else {
			report.add_ok('${snap.id}: archive hash ok')
		}
	}

	manifest := read_manifest_from_archive(snap) or {
		report.add_error('${snap.id}: cannot read archive manifest: ${err}')
		return
	}

	if manifest.id != snap.id {
		report.add_error('${snap.id}: manifest id mismatch: ${manifest.id}')
	}

	if manifest.files.len != snap.files {
		report.add_warn('${snap.id}: index files=${snap.files}, manifest files=${manifest.files.len}')
	}

	mut manifest_bytes := u64(0)

	for file in manifest.files {
		manifest_bytes += file.size
	}

	if manifest_bytes != snap.bytes {
		report.add_warn('${snap.id}: index bytes=${snap.bytes}, manifest bytes=${manifest_bytes}')
	}

	report.add_ok('${snap.id}: archive readable')
}

// check_snapshot_directory_artifacts reports temp archives and orphan zip files.
fn check_snapshot_directory_artifacts(mut report DoctorReport, indexed_archives map[string]bool) {
	snapshots := os.join_path(store_path(), snapshot_dir)

	if !os.exists(snapshots) || !os.is_dir(snapshots) {
		return
	}

	names := os.ls(snapshots) or {
		report.add_warn('cannot inspect snapshots directory: ${err}')
		return
	}

	for name in names {
		full := os.join_path(snapshots, name)

		if os.is_dir(full) {
			continue
		}

		archive := normalize_entry(os.join_path(snapshot_dir, name))

		if name.ends_with('.zip.tmp') {
			report.add_warn('${archive}: incomplete archive temp file')
			continue
		}

		if name.ends_with('.zip') && !indexed_archives[archive] {
			report.add_warn('${archive}: archive is not referenced by index')
		}
	}
}

// add_ok appends a healthy doctor finding.
fn (mut report DoctorReport) add_ok(message string) {
	report.ok++
	report.entries << DoctorEntry{
		level:   .ok
		message: message
	}
}

// add_warn appends a non-fatal doctor finding.
fn (mut report DoctorReport) add_warn(message string) {
	report.warn++
	report.entries << DoctorEntry{
		level:   .warn
		message: message
	}
}

// add_error appends a fatal doctor finding.
fn (mut report DoctorReport) add_error(message string) {
	report.error++
	report.entries << DoctorEntry{
		level:   .error
		message: message
	}
}

// print_doctor_report renders all doctor findings and totals.
fn print_doctor_report(report DoctorReport) {
	println(c_title('vsnap doctor'))

	for entry in report.entries {
		println('  ${format_doctor_level(entry.level, 5)} ${entry.message}')
	}

	println('')
	println('${c_ok('${report.ok} ok')}  ${c_warn('${report.warn} warn')}  ${c_danger('${report.error} error')}')
}
