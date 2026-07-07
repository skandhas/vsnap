module main

import os

enum RestoreAction {
	overwrite
	recreate
	unchanged
}

struct RestoreImpact {
pub mut:
	// overwrite lists existing files that differ from the snapshot.
	overwrite []ManifestFile

	// recreate lists files missing locally but present in the snapshot.
	recreate []ManifestFile

	// unchanged lists files already matching the snapshot.
	unchanged []ManifestFile
}

struct RestoreTableWidths {
mut:
	// action is the display width for restore action labels.
	action int

	// size is the display width for file sizes.
	size int
}

struct CmdRestore {
	// selector is the snapshot id prefix or list number.
	selector string

	// dry_run previews restore without changing files.
	dry_run bool

	// no_safety disables automatic safety snapshot creation.
	no_safety bool
}

struct CmdUndo {
}

// execute executes a restore command after handwritten argument parsing.
fn (cmd CmdRestore) execute() ! {
	op_lock := acquire_lock('restore')!

	defer {
		op_lock.release()
	}

	snap := resolve_snapshot(cmd.selector)!
	manifest, extracted_dir := extract_snapshot(snap)!

	defer {
		os.rmdir_all(extracted_dir) or {}
	}

	impact := plan_restore(manifest)!
	print_restore_preview(snap, impact)

	if cmd.dry_run {
		println('')
		println('${c_warn('dry-run:')} no files changed')
		return
	}

	if impact.changed_count() == 0 {
		println('')
		println(c_ok('nothing to restore'))
		return
	}

	mut safety := SnapshotIndex{}

	if !cmd.no_safety && impact.overwrite.len > 0 {
		safety = create_restore_safety_snapshot(snap, impact.overwrite)!
		println('')
		println('${c_ok('safety snapshot created:')} ${c_info(safety.id)}')
	}

	apply_restore(manifest, extracted_dir)!
	println('')
	println('${c_ok('restored')} ${impact.changed_count()} files from ${c_info(snap.id)}')
	println(c_muted('files created after the snapshot were left in place'))

	if safety.id != '' {
		println('${c_warn('undo with:')} vsnap undo')
	}
}

// cmd_undo restores the newest safety snapshot.
fn cmd_undo() ! {
	cmd := CmdUndo{}
	cmd.execute()!
}

// execute executes an undo command.
fn (cmd CmdUndo) execute() ! {
	op_lock := acquire_lock('undo')!

	defer {
		op_lock.release()
	}

	snap := latest_safety_snapshot()!
	manifest, extracted_dir := extract_snapshot(snap)!

	defer {
		os.rmdir_all(extracted_dir) or {}
	}

	impact := plan_restore(manifest)!
	print_restore_preview(snap, impact)

	if impact.changed_count() == 0 {
		println('')
		println(c_ok('nothing to undo'))
		return
	}

	apply_restore(manifest, extracted_dir)!
	println('')
	println('${c_ok('undone')} by restoring ${c_info(snap.id)}')
}

// changed_count returns how many files restore would create or overwrite.
fn (impact RestoreImpact) changed_count() int {
	return impact.overwrite.len + impact.recreate.len
}

// label returns the display label for a restore action.
fn (action RestoreAction) label() string {
	return match action {
		.overwrite { 'overwrite' }
		.recreate { 'recreate' }
		.unchanged { 'unchanged' }
	}
}

// plan_restore classifies snapshot files as overwrite, recreate, or unchanged.
fn plan_restore(manifest SnapshotManifest) !RestoreImpact {
	mut impact := RestoreImpact{}

	for file in manifest.files {
		dst := os.join_path(os.getwd(), file.path)

		if !os.exists(dst) {
			impact.recreate << file
			continue
		}

		current_hash := file_hash(dst)!

		if current_hash == file.hash {
			impact.unchanged << file
		} else {
			impact.overwrite << file
		}
	}

	return impact
}

// apply_restore copies extracted snapshot files back into the working tree.
fn apply_restore(manifest SnapshotManifest, extracted_dir string) ! {
	for file in manifest.files {
		src := os.join_path(extracted_dir, file.path)
		dst := os.join_path(os.getwd(), file.path)
		parent := os.dir(dst)

		if parent != '' {
			os.mkdir_all(parent)!
		}

		os.cp(src, dst)!
	}
}

// print_restore_preview renders the restore impact summary and file table.
fn print_restore_preview(snap SnapshotIndex, impact RestoreImpact) {
	println('${c_title('Restore preview')} for ${c_info(snap.id)}')
	println('  ${c_danger('${RestoreAction.overwrite.label()}:')} ${impact.overwrite.len}')
	println('  ${c_info('${RestoreAction.recreate.label()}:')}  ${impact.recreate.len}')
	println('  ${c_ok('${RestoreAction.unchanged.label()}:')} ${impact.unchanged.len}')
	print_restore_files(impact)
}

// print_restore_files prints all restore impact groups.
fn print_restore_files(impact RestoreImpact) {
	total := impact.overwrite.len + impact.recreate.len + impact.unchanged.len

	if total == 0 {
		return
	}

	mut widths := RestoreTableWidths{
		action: 'ACTION'.len
		size:   'SIZE'.len
	}

	widths = update_restore_widths(widths, impact.overwrite, .overwrite)
	widths = update_restore_widths(widths, impact.recreate, .recreate)
	widths = update_restore_widths(widths, impact.unchanged, .unchanged)
	action_header := pad_right('ACTION', widths.action)
	size_header := pad_left('SIZE', widths.size)
	println('')
	println('  ${c_muted(action_header)}  ${c_muted(size_header)}  ${c_muted('HASH        ')}  ${c_muted('PATH')}')
	print_restore_group(impact.overwrite, .overwrite, widths)
	print_restore_group(impact.recreate, .recreate, widths)
	print_restore_group(impact.unchanged, .unchanged, widths)
}

// update_restore_widths updates table widths from one restore impact group.
fn update_restore_widths(widths RestoreTableWidths, files []ManifestFile, action RestoreAction) RestoreTableWidths {
	mut next := widths
	action_len := action.label().len

	if action_len > next.action {
		next.action = action_len
	}

	for file in files {
		size_len := human_bytes(file.size).len

		if size_len > next.size {
			next.size = size_len
		}
	}

	return next
}

// print_restore_group renders one group of restore preview rows.
fn print_restore_group(files []ManifestFile, action RestoreAction, widths RestoreTableWidths) {
	for file in files {
		action_label := format_restore_action(action, widths.action)
		size := c_info(pad_left(human_bytes(file.size), widths.size))
		hash := c_muted(pad_right(file.hash[..12], 12))
		println('  ${action_label}  ${size}  ${hash}  ${file.path}')
	}
}
