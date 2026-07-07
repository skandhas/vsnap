module main

import cli
import strconv

// parse_save_cli builds a save command while preserving path-first parsing rules.
fn parse_save_cli(cmd cli.Command) !CmdSave {
	return parse_save_args(cmd.args)!
}

// parse_again_cli builds an again command from raw cli.Command arguments.
fn parse_again_cli(cmd cli.Command) !CmdAgain {
	mut message := ''
	mut message_set := false
	mut max_file_bytes := u64(0)
	mut max_file_bytes_set := false
	mut force := false
	mut dry_run := false
	mut i := 0

	for i < cmd.args.len {
		arg := cmd.args[i]

		if arg == '-m' || arg == '--message' {
			if i + 1 >= cmd.args.len {
				return error('${arg} needs a message')
			}

			message = cmd.args[i + 1]
			message_set = true
			i += 2
			continue
		}

		if arg == '--max-file' {
			if i + 1 >= cmd.args.len {
				return error('--max-file needs a size, for example 100MB')
			}

			max_file_bytes = parse_size(cmd.args[i + 1])!
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
			return error('unknown again option: ${arg}')
		}

		return error('again does not accept paths: ${arg}')
	}

	return CmdAgain{
		message:            message
		message_set:        message_set
		max_file_bytes:     max_file_bytes
		max_file_bytes_set: max_file_bytes_set
		force:              force
		dry_run:            dry_run
	}
}

// parse_list_cli builds a list command from raw cli.Command arguments.
fn parse_list_cli(cmd cli.Command) !CmdList {
	mut show_all := false

	for arg in cmd.args {
		if arg == '--all' {
			show_all = true
			continue
		}

		if arg.starts_with('-') {
			return error('unknown list option: ${arg}')
		}

		return error('list does not accept arguments: ${arg}')
	}

	return CmdList{
		show_all: show_all
	}
}

// parse_show_cli builds a show command from raw cli.Command arguments.
fn parse_show_cli(cmd cli.Command) !CmdShow {
	mut selector := ''
	mut tree := false

	for arg in cmd.args {
		if arg == '--tree' {
			tree = true
			continue
		}

		if arg.starts_with('-') {
			return error('unknown show option: ${arg}')
		}

		if selector != '' {
			return error('show accepts one snapshot id or list number')
		}

		selector = arg
	}

	if selector == '' {
		return error('show needs a snapshot id or list number')
	}

	return CmdShow{
		selector: selector
		tree:     tree
	}
}

// parse_restore_cli builds a restore command from raw cli.Command arguments.
fn parse_restore_cli(cmd cli.Command) !CmdRestore {
	mut selector := ''
	mut dry_run := false
	mut no_safety := false

	for arg in cmd.args {
		if arg == '--dry-run' {
			dry_run = true
			continue
		}

		if arg == '--no-safety' {
			no_safety = true
			continue
		}

		if arg.starts_with('-') {
			return error('unknown restore option: ${arg}')
		}

		if selector != '' {
			return error('restore accepts one snapshot id or list number')
		}

		selector = arg
	}

	if selector == '' {
		return error('restore needs a snapshot id or list number')
	}

	return CmdRestore{
		selector:  selector
		dry_run:   dry_run
		no_safety: no_safety
	}
}

// parse_clean_cli builds a clean command from raw cli.Command arguments.
fn parse_clean_cli(cmd cli.Command) !CmdClean {
	mut keep := -1
	mut i := 0

	for i < cmd.args.len {
		arg := cmd.args[i]

		if arg == '--keep' {
			if i + 1 >= cmd.args.len {
				return error('--keep needs a number')
			}

			keep = parse_keep_count(cmd.args[i + 1])!
			i += 2
			continue
		}

		if arg.starts_with('-') {
			return error('unknown clean option: ${arg}')
		}

		if keep >= 0 {
			return error('clean accepts one keep value')
		}

		keep = parse_keep_count(arg)!
		i++
	}

	if keep < 0 {
		return error('clean needs --keep <n>')
	}

	return CmdClean{
		keep: keep
	}
}

// parse_doctor_cli builds a doctor command from raw cli.Command arguments.
fn parse_doctor_cli(cmd cli.Command) !CmdDoctor {
	mut fast := false

	for arg in cmd.args {
		if arg == '--fast' {
			fast = true
			continue
		}

		return error('unknown doctor option: ${arg}')
	}

	return CmdDoctor{
		fast: fast
	}
}

// parse_keep_count parses a non-negative clean keep count.
fn parse_keep_count(raw string) !int {
	keep := strconv.atoi(raw) or { return error('keep must be a number') }

	if keep < 0 {
		return error('keep must be zero or greater')
	}

	return keep
}

// parse_size parses human-readable byte sizes such as 100MB.
fn parse_size(raw string) !u64 {
	text := raw.trim_space().to_upper()

	if text == '' {
		return error('size cannot be empty')
	}

	mut number := text
	mut multiplier := u64(1)

	if text.ends_with('KB') {
		number = text[..text.len - 2]
		multiplier = 1024
	} else if text.ends_with('MB') {
		number = text[..text.len - 2]
		multiplier = 1024 * 1024
	} else if text.ends_with('GB') {
		number = text[..text.len - 2]
		multiplier = 1024 * 1024 * 1024
	} else if text.ends_with('B') {
		number = text[..text.len - 1]
	}

	value := strconv.parse_uint(number.trim_space(), 10, 64) or {
		return error('invalid size: ${raw}')
	}

	if value == 0 {
		return error('size must be greater than zero')
	}

	return value * multiplier
}
