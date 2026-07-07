module main

import os

struct CmdSave {
	// paths are the explicit files or directories requested by the user.
	paths []string

	// message is the snapshot message.
	message string

	// max_file_bytes is the per-command file-size limit.
	max_file_bytes u64

	// max_file_bytes_set records whether --max-file was provided.
	max_file_bytes_set bool

	// force bypasses the file-count guard.
	force bool

	// dry_run previews save without writing a snapshot.
	dry_run bool
}

// execute executes a save command after handwritten argument parsing.
fn (cmd CmdSave) execute() ! {
	config := effective_config()!
	max_file_bytes := if cmd.max_file_bytes_set {
		cmd.max_file_bytes
	} else {
		config.max_file_bytes
	}

	scan := scan_targets(os.getwd(), cmd.paths, ScanOptions{
		max_file_bytes: max_file_bytes
	})!

	if cmd.dry_run {
		print_save_preview(scan, cmd, config, max_file_bytes)

		if snapshot_file_count_exceeded(scan, cmd.force, config.max_file_count) {
			return error('snapshot would be stopped by file-count protection')
		}

		return
	}

	check_snapshot_file_count(scan, cmd.force, config.max_file_count)!
	op_lock := acquire_lock('save')!

	defer {
		op_lock.release()
	}

	snap := save_files(scan.files, .manual, cmd.message)!
	write_last_save_intent(cmd.save_intent()) or {
		eprintln('${c_warn('warning:')} failed to update ${last_save_name}: ${err}')
	}
	println('${c_ok('saved')} ${snap.files} files (${c_info(human_bytes(snap.bytes))}) as ${c_info(snap.id)}')
	println('${c_muted('message:')} ${snap.message}')
	print_skipped_files(scan.skipped)
}

// parse_save_args parses save paths and options.
fn parse_save_args(args []string) !CmdSave {
	mut paths := []string{}
	mut message := 'snapshot'
	mut max_file_bytes := default_max_file_bytes
	mut max_file_bytes_set := false
	mut force := false
	mut dry_run := false
	mut paths_only := false
	mut i := 0

	for i < args.len {
		arg := args[i]

		if paths_only {
			paths << arg
			i++
			continue
		}

		if arg == '--' {
			paths_only = true
			i++
			continue
		}

		if arg == '-m' || arg == '--message' {
			if i + 1 >= args.len {
				return error('${arg} needs a message')
			}

			message = args[i + 1]
			i += 2
			continue
		}

		if arg == '--max-file' {
			if i + 1 >= args.len {
				return error('--max-file needs a size, for example 100MB')
			}

			max_file_bytes = parse_size(args[i + 1])!
			max_file_bytes_set = true
			i += 2
			continue
		}

		if arg == '--force' {
			force = true
			i++
			continue
		}

		if arg == '--dry-run' {
			dry_run = true
			i++
			continue
		}

		if arg.starts_with('-') {
			return error('unknown save option: ${arg}; use -- before paths that start with -')
		}

		paths << arg
		i++
	}

	if paths.len == 0 {
		return error('save needs at least one explicit path, for example: vsnap save . -m "before refactor"')
	}

	return CmdSave{
		paths:              paths
		message:            message
		max_file_bytes:     max_file_bytes
		max_file_bytes_set: max_file_bytes_set
		force:              force
		dry_run:            dry_run
	}
}

// print_save_preview renders what save would capture without writing a snapshot.
fn print_save_preview(scan ScanResult, cmd CmdSave, config EffectiveConfig, max_file_bytes u64) {
	total := scan_total_bytes(scan)
	exceeded := snapshot_file_count_exceeded(scan, cmd.force, config.max_file_count)
	println(c_title('save preview'))
	println('')
	println('  ${c_muted('message:')} ${cmd.message}')
	println('  ${c_muted('files:')}   ${c_info('${scan.files.len}')} (${c_info(human_bytes(total))})')
	println('  ${c_muted('limit:')}   ${c_info('${config.max_file_count} files')}  ${c_muted('file-count guard')}')
	println('  ${c_muted('max:')}     ${c_info(human_bytes(max_file_bytes))}  ${c_muted('single-file limit')}')

	if exceeded {
		println('  ${c_muted('status:')}  ${c_warn('would stop')}  ${c_muted('rerun with --force when intentional')}')
	} else if cmd.force && scan.files.len > config.max_file_count {
		println('  ${c_muted('status:')}  ${c_warn('would save')}  ${c_muted('--force bypasses file-count guard')}')
	} else {
		println('  ${c_muted('status:')}  ${c_ok('would save')}')
	}

	println('')
	print_scanned_files(scan.files)
	print_skipped_files(scan.skipped)
	println('')
	println('${c_warn('dry-run:')} no snapshot created')
}

// print_scanned_files renders scanned files in the same compact table style as show.
fn print_scanned_files(files []SnapshotFile) {
	if files.len == 0 {
		println(c_muted('  no files'))
		return
	}

	mut size_width := 'SIZE'.len

	for file in files {
		file_size_width := human_bytes(file.size).len

		if file_size_width > size_width {
			size_width = file_size_width
		}
	}

	size_header := pad_left('SIZE', size_width)
	println('  ${c_muted(size_header)}  ${c_muted('HASH        ')}  ${c_muted('PATH')}')

	for file in files {
		size := pad_left(human_bytes(file.size), size_width)
		hash := pad_right(file.hash[..12], 12)
		println('  ${c_info(size)}  ${c_muted(hash)}  ${file.path}')
	}
}

// scan_total_bytes sums the byte size of scanned snapshot files.
fn scan_total_bytes(scan ScanResult) u64 {
	mut total := u64(0)

	for file in scan.files {
		total += file.size
	}

	return total
}

// snapshot_file_count_exceeded reports whether save would exceed the file-count guard.
fn snapshot_file_count_exceeded(scan ScanResult, force bool, max_file_count int) bool {
	return !force && scan.files.len > max_file_count
}

// check_snapshot_file_count stops broad saves unless --force was provided.
fn check_snapshot_file_count(scan ScanResult, force bool, max_file_count int) ! {
	if !snapshot_file_count_exceeded(scan, force, max_file_count) {
		return
	}

	eprintln(c_warn('snapshot contains many files'))
	eprintln('')
	eprintln('  files: ${c_info('${scan.files.len}')}')
	eprintln('  limit: ${c_info('${max_file_count}')}')
	eprintln('')
	eprintln(c_muted('This may be an accidental broad save.'))
	eprintln(c_muted('Narrow the path, update .vsnapignore, or rerun with --force.'))
	return error('snapshot stopped by file-count protection')
}

// print_skipped_files prints large files skipped during directory scans.
fn print_skipped_files(skipped []SkippedFile) {
	if skipped.len == 0 {
		return
	}

	println('')
	println('${c_warn('skipped')} ${skipped.len} large files:')

	for file in skipped {
		println('  ${file.path}  ${c_info(human_bytes(file.size))}  ${c_muted(file.reason)}')
	}

	println(c_muted('use --max-file <size> to include larger files'))
}
