module main

import os

// main builds the CLI command tree and starts parsing os.args.
fn main() {
	mut app := build_cli_app()
	app.setup()
	app.parse(os.args)
}

// fail prints a CLI error and exits with status 1.
@[noreturn]
fn fail(message string) {
	eprintln('${c_err('vsnap:')} ${message}')
	exit(1)
}

// print_version prints the current application version.
fn print_version() {
	println('vsnap ${app_version}')
}

// print_usage prints the compact top-level command index.
fn print_usage() {
	println(c_title('vsnap') + ' - tiny snapshots before bold edits')
	println('')
	println('Usage:')
	println('  vsnap <command> [options]')
	println('')
	println('Commands:')
	println('  save, s      Save explicit files or directories')
	println('  again        Repeat the last successful save')
	println('  list, ls     Show snapshots')
	println('  show         Show files in a snapshot')
	println('  restore, rs  Restore a snapshot')
	println('  undo         Restore latest safety snapshot')
	println('  clean        Remove old manual snapshots')
	println('  lock         Inspect or clear operation lock')
	println('  doctor       Check snapshot store health')
	println('  config       Read or write project config')
	println('  version      Show version')
	println('')
	println('Help:')
	println('  vsnap help <command>')
}

// print_command_usage prints detailed help for one command name or alias.
fn print_command_usage(command string) bool {
	topic := normalize_help_topic(command)

	match topic {
		'save' {
			print_save_usage()
		}
		'again' {
			print_again_usage()
		}
		'list' {
			print_list_usage()
		}
		'show' {
			print_show_usage()
		}
		'restore' {
			print_restore_usage()
		}
		'undo' {
			print_undo_usage()
		}
		'clean' {
			print_clean_usage()
		}
		'lock' {
			print_lock_usage()
		}
		'doctor' {
			print_doctor_usage()
		}
		'config' {
			print_config_usage()
		}
		'version' {
			print_version_usage()
		}
		else {
			return false
		}
	}

	return true
}

// normalize_help_topic maps command aliases to their canonical help topic.
fn normalize_help_topic(command string) string {
	return match command {
		's' { 'save' }
		'ls' { 'list' }
		'rs', 'rollback' { 'restore' }
		'-V', '--version' { 'version' }
		else { command }
	}
}

// print_save_usage prints detailed help for the save command.
fn print_save_usage() {
	println(c_title('vsnap save') + ' - save explicit files or directories')
	println('')
	println('Usage:')
	println('  vsnap save <path...> -m "message"')
	println('  vsnap save <path...> [options]')
	println('  vsnap save -- <path...>')
	println('  vsnap s <path...> [options]')
	println('')
	println('Options:')
	println('  -m, --message <text>    Snapshot message')
	println('  --dry-run               Preview without creating a snapshot')
	println('  --max-file <size>       Override per-file size limit')
	println('  --force                 Bypass broad-save file-count guard')
	println('  --                      Treat following values as paths')
	println('')
	println('Examples:')
	println('  vsnap save . -m "before refactor"')
	println('  vsnap s . -m "quick checkpoint"')
	println('  vsnap save src README.md -m "before parser rewrite"')
	println('  vsnap save -- -draft.txt -m "path starts with dash"')
}

// print_again_usage prints detailed help for the again command.
fn print_again_usage() {
	println(c_title('vsnap again') + ' - repeat the last successful save')
	println('')
	println('Usage:')
	println('  vsnap again [options]')
	println('')
	println('Options:')
	println('  -m, --message <text>    Override the previous message')
	println('  --dry-run               Preview without creating a snapshot')
	println('  --max-file <size>       Override previous per-file size limit')
	println('  --force                 Bypass broad-save file-count guard')
	println('')
	println('Examples:')
	println('  vsnap again')
	println('  vsnap again -m "second pass" --dry-run')
}

// print_list_usage prints detailed help for the list command.
fn print_list_usage() {
	println(c_title('vsnap list') + ' - show snapshots')
	println('')
	println('Usage:')
	println('  vsnap list [--all]')
	println('  vsnap ls [--all]')
	println('')
	println('Options:')
	println('  --all                   Include safety snapshots')
}

// print_show_usage prints detailed help for the show command.
fn print_show_usage() {
	println(c_title('vsnap show') + ' - show files in a snapshot')
	println('')
	println('Usage:')
	println('  vsnap show <id|number> [--tree]')
	println('')
	println('Options:')
	println('  --tree                  Show snapshot files as a tree')
}

// print_restore_usage prints detailed help for the restore command.
fn print_restore_usage() {
	println(c_title('vsnap restore') + ' - restore a snapshot')
	println('')
	println('Usage:')
	println('  vsnap restore <id|number> [options]')
	println('  vsnap rs <id|number> [options]')
	println('  vsnap rollback <id|number> [options]')
	println('')
	println('Options:')
	println('  --dry-run               Preview without changing files')
	println('  --no-safety             Do not create a safety snapshot first')
}

// print_undo_usage prints detailed help for the undo command.
fn print_undo_usage() {
	println(c_title('vsnap undo') + ' - restore latest safety snapshot')
	println('')
	println('Usage:')
	println('  vsnap undo')
}

// print_clean_usage prints detailed help for the clean command.
fn print_clean_usage() {
	println(c_title('vsnap clean') + ' - remove old manual snapshots')
	println('')
	println('Usage:')
	println('  vsnap clean --keep <n>')
	println('')
	println('Examples:')
	println('  vsnap clean --keep 10')
	println('  vsnap clean --keep 0')
}

// print_lock_usage prints detailed help for the lock command.
fn print_lock_usage() {
	println(c_title('vsnap lock') + ' - inspect or clear operation lock')
	println('')
	println('Usage:')
	println('  vsnap lock status')
	println('  vsnap lock clear')
}

// print_doctor_usage prints detailed help for the doctor command.
fn print_doctor_usage() {
	println(c_title('vsnap doctor') + ' - check snapshot store health')
	println('')
	println('Usage:')
	println('  vsnap doctor [--fast]')
	println('')
	println('Options:')
	println('  --fast                  Skip archive hash checks')
}

// print_config_usage prints detailed help for the config command.
fn print_config_usage() {
	println(c_title('vsnap config') + ' - read or write project config')
	println('')
	println('Usage:')
	println('  vsnap config --list')
	println('  vsnap config <key>')
	println('  vsnap config <key> <value>')
	println('  vsnap config --unset <key>')
	println('')
	println('Examples:')
	println('  vsnap config limits.file.size 100MB')
	println('  vsnap config limits.file.count 200')
	println('  vsnap config limits.file')
	println('  vsnap config --unset limits.file.size')
}

// print_version_usage prints detailed help for the version command.
fn print_version_usage() {
	println(c_title('vsnap version') + ' - show version')
	println('')
	println('Usage:')
	println('  vsnap version')
	println('  vsnap -V')
	println('  vsnap --version')
}
