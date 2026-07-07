module main

import cli

// build_cli_app returns the top-level cli.Command tree.
fn build_cli_app() cli.Command {
	return cli.Command{
		name:          'vsnap'
		description:   'tiny snapshots before bold edits'
		disable_flags: true
		posix_mode:    true
		execute:       execute_root_cli
		commands:      [
			cli.Command{
				name:          'save'
				description:   'Save explicit files or directories'
				disable_flags: true
				execute:       execute_save_cli
			},
			cli.Command{
				name:          's'
				description:   'Save explicit files or directories'
				disable_flags: true
				execute:       execute_save_cli
			},
			cli.Command{
				name:          'again'
				description:   'Repeat the last successful save'
				disable_flags: true
				execute:       execute_again_cli
			},
			cli.Command{
				name:          'list'
				description:   'Show snapshots'
				disable_flags: true
				execute:       execute_list_cli
			},
			cli.Command{
				name:          'ls'
				description:   'Show snapshots'
				disable_flags: true
				execute:       execute_list_cli
			},
			cli.Command{
				name:          'show'
				description:   'Show files in a snapshot'
				disable_flags: true
				execute:       execute_show_cli
			},
			cli.Command{
				name:          'restore'
				description:   'Restore a snapshot'
				disable_flags: true
				execute:       execute_restore_cli
			},
			cli.Command{
				name:          'rs'
				description:   'Restore a snapshot'
				disable_flags: true
				execute:       execute_restore_cli
			},
			cli.Command{
				name:          'rollback'
				description:   'Restore a snapshot'
				disable_flags: true
				execute:       execute_restore_cli
			},
			cli.Command{
				name:          'undo'
				description:   'Restore latest safety snapshot'
				disable_flags: true
				execute:       execute_undo_cli
			},
			cli.Command{
				name:          'clean'
				description:   'Remove old snapshots'
				disable_flags: true
				execute:       execute_clean_cli
			},
			cli.Command{
				name:          'lock'
				description:   'Inspect or clear operation lock'
				disable_flags: true
				execute:       execute_lock_cli
				commands:      [
					cli.Command{
						name:          'status'
						description:   'Inspect operation lock'
						disable_flags: true
						execute:       execute_lock_status_cli
					},
					cli.Command{
						name:          'clear'
						description:   'Clear operation lock'
						disable_flags: true
						execute:       execute_lock_clear_cli
					},
				]
			},
			cli.Command{
				name:          'doctor'
				description:   'Check snapshot store health'
				disable_flags: true
				execute:       execute_doctor_cli
			},
			cli.Command{
				name:          'config'
				description:   'Read or write project config'
				disable_flags: true
				execute:       execute_config_cli
			},
			cli.Command{
				name:          'version'
				description:   'Show version'
				disable_flags: true
				execute:       execute_version_cli
			},
			cli.Command{
				name:          '-V'
				description:   'Show version'
				disable_flags: true
				execute:       execute_version_cli
			},
			cli.Command{
				name:          '--version'
				description:   'Show version'
				disable_flags: true
				execute:       execute_version_cli
			},
			cli.Command{
				name:          'help'
				description:   'Show help'
				disable_flags: true
				execute:       execute_help_cli
			},
			cli.Command{
				name:          '-h'
				description:   'Show help'
				disable_flags: true
				execute:       execute_help_cli
			},
			cli.Command{
				name:          '--help'
				description:   'Show help'
				disable_flags: true
				execute:       execute_help_cli
			},
		]
	}
}

// execute_root_cli handles no command or an unknown top-level command.
fn execute_root_cli(cmd cli.Command) ! {
	if cmd.args.len == 0 {
		print_usage()
		return
	}

	fail('unknown command: ${cmd.args[0]}')
}

// execute_save_cli runs the save command from cli.Command arguments.
fn execute_save_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('save')
		return
	}

	parsed := parse_save_cli(cmd) or { fail(err.msg()) }
	parsed.execute() or { fail(err.msg()) }
}

// execute_again_cli runs the again command from cli.Command arguments.
fn execute_again_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('again')
		return
	}

	parsed := parse_again_cli(cmd) or { fail(err.msg()) }
	parsed.execute() or { fail(err.msg()) }
}

// execute_list_cli runs the list command from cli.Command arguments.
fn execute_list_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('list')
		return
	}

	parsed := parse_list_cli(cmd) or { fail(err.msg()) }
	parsed.execute() or { fail(err.msg()) }
}

// execute_show_cli runs the show command from cli.Command arguments.
fn execute_show_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('show')
		return
	}

	parsed := parse_show_cli(cmd) or { fail(err.msg()) }
	parsed.execute() or { fail(err.msg()) }
}

// execute_restore_cli runs the restore command from cli.Command arguments.
fn execute_restore_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('restore')
		return
	}

	parsed := parse_restore_cli(cmd) or { fail(err.msg()) }
	parsed.execute() or { fail(err.msg()) }
}

// execute_undo_cli runs the undo command from cli.Command arguments.
fn execute_undo_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('undo')
		return
	}

	if cmd.args.len > 0 {
		fail('undo does not accept arguments: ${cmd.args[0]}')
	}

	cmd_undo() or { fail(err.msg()) }
}

// execute_clean_cli runs the clean command from cli.Command arguments.
fn execute_clean_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('clean')
		return
	}

	parsed := parse_clean_cli(cmd) or { fail(err.msg()) }
	parsed.execute() or { fail(err.msg()) }
}

// execute_lock_cli runs the lock command from cli.Command arguments.
fn execute_lock_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('lock')
		return
	}

	cmd_lock(cmd.args) or { fail(err.msg()) }
}

// execute_lock_status_cli runs the lock status subcommand.
fn execute_lock_status_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('lock')
		return
	}

	if cmd.args.len > 0 {
		fail('lock status does not accept arguments: ${cmd.args[0]}')
	}

	parsed := CmdLock{
		action: .status
	}
	parsed.execute() or { fail(err.msg()) }
}

// execute_lock_clear_cli runs the lock clear subcommand.
fn execute_lock_clear_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('lock')
		return
	}

	if cmd.args.len > 0 {
		fail('lock clear does not accept arguments: ${cmd.args[0]}')
	}

	parsed := CmdLock{
		action: .clear
	}
	parsed.execute() or { fail(err.msg()) }
}

// execute_doctor_cli runs the doctor command from cli.Command arguments.
fn execute_doctor_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('doctor')
		return
	}

	parsed := parse_doctor_cli(cmd) or { fail(err.msg()) }
	parsed.execute() or { fail(err.msg()) }
}

// execute_config_cli runs the config command from cli.Command arguments.
fn execute_config_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('config')
		return
	}

	cmd_config(cmd.args) or { fail(err.msg()) }
}

// execute_version_cli prints the version command output.
fn execute_version_cli(cmd cli.Command) ! {
	if command_help_requested(cmd.args) {
		print_command_usage('version')
		return
	}

	if cmd.args.len > 0 {
		fail('version does not accept arguments: ${cmd.args[0]}')
	}

	print_version()
}

// execute_help_cli prints top-level help or detailed command help.
fn execute_help_cli(cmd cli.Command) ! {
	if cmd.args.len == 0 || command_help_requested(cmd.args) {
		print_usage()
		return
	}

	if cmd.args.len > 1 {
		fail('help accepts one command name')
	}

	if !print_command_usage(cmd.args[0]) {
		fail('unknown help topic: ${cmd.args[0]}')
	}
}

// command_help_requested checks for a command-local help flag.
fn command_help_requested(args []string) bool {
	return args.len == 1 && (args[0] == '-h' || args[0] == '--help')
}
