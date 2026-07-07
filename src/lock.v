module main

import json
import os
import time

struct OperationLock {
	// path is the lock directory path.
	path string

	// owner is the metadata written when the lock was acquired.
	owner LockOwner
}

// acquire_lock creates the project-local operation lock.
fn acquire_lock(command string) !OperationLock {
	ensure_store_root()!
	path := lock_path()
	owner := LockOwner{
		pid:     os.getpid()
		command: command
		created: time.now().format_ss()
	}

	os.mkdir(path) or {
		current := read_lock_owner() or {
			return error('another operation is running; lock exists at ${path}')
		}

		return error('another operation is running: ${current.command} pid=${current.pid} since ${current.created}')
	}

	os.write_file(os.join_path(path, lock_owner_name), json.encode_pretty(owner)) or {
		os.rmdir_all(path) or {}
		return err
	}

	return OperationLock{
		path:  path
		owner: owner
	}
}

// release removes the held operation lock.
fn (held OperationLock) release() {
	if held.path != '' {
		os.rmdir_all(held.path) or {}
	}
}

enum CmdLockAction {
	status
	clear
}

struct CmdLock {
	// action is the lock subcommand selected by handwritten parsing.
	action CmdLockAction
}

// cmd_lock handles lock status and clear subcommands.
fn cmd_lock(args []string) ! {
	cmd := parse_lock_args(args)!
	cmd.execute()!
}

// execute executes a lock command after handwritten argument parsing.
fn (cmd CmdLock) execute() ! {
	match cmd.action {
		.status {
			cmd_lock_status()!
		}
		.clear {
			cmd_lock_clear()!
		}
	}
}

// parse_lock_args parses lock status and clear subcommands.
fn parse_lock_args(args []string) !CmdLock {
	if args.len == 0 {
		return error('lock needs a subcommand: status or clear')
	}

	action := match args[0] {
		'status' {
			CmdLockAction.status
		}
		'clear' {
			CmdLockAction.clear
		}
		else {
			return error('unknown lock subcommand: ${args[0]}')
		}
	}

	return CmdLock{
		action: action
	}
}

// cmd_lock_status prints whether a lock is currently active.
fn cmd_lock_status() ! {
	if !os.exists(lock_path()) {
		println(c_ok('no active lock'))
		return
	}

	owner := read_lock_owner() or {
		println('${c_warn('lock exists')} but owner metadata is unreadable')
		println(c_muted(lock_path()))
		return
	}

	println(c_warn('active lock'))
	println('  command: ${owner.command}')
	println('  pid:     ${owner.pid}')
	println('  since:   ${owner.created}')
	println('  path:    ${c_muted(lock_path())}')
}

// cmd_lock_clear removes a stale operation lock.
fn cmd_lock_clear() ! {
	path := lock_path()

	if !os.exists(path) {
		println(c_ok('no active lock'))
		return
	}

	os.rmdir_all(path)!
	println('${c_warn('cleared lock:')} ${c_muted(path)}')
}

// read_lock_owner reads lock owner metadata.
fn read_lock_owner() !LockOwner {
	owner_path := os.join_path(lock_path(), lock_owner_name)

	if !os.exists(owner_path) {
		return error('lock owner metadata is missing')
	}

	return json.decode(LockOwner, os.read_file(owner_path)!)!
}

// lock_path returns the path to the project lock directory.
fn lock_path() string {
	return os.join_path(store_path(), lock_dir)
}

// ensure_store_root creates the root .vsnap directory.
fn ensure_store_root() ! {
	os.mkdir_all(store_path())!
}
