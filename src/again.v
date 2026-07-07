module main

import json
import os

struct CmdAgain {
	// message is the optional replacement snapshot message.
	message string

	// message_set records whether -m or --message was provided.
	message_set bool

	// max_file_bytes is the optional replacement per-command file-size limit.
	max_file_bytes u64

	// max_file_bytes_set records whether --max-file was provided.
	max_file_bytes_set bool

	// force bypasses the file-count guard for this repeated save.
	force bool

	// dry_run previews the repeated save without writing a snapshot.
	dry_run bool
}

// execute repeats the last successful save intent with optional overrides.
fn (cmd CmdAgain) execute() ! {
	intent := read_last_save_intent()!
	save_cmd := cmd.to_save_command(intent)!
	save_cmd.execute()!
}

// to_save_command combines the stored save intent with again command overrides.
fn (cmd CmdAgain) to_save_command(intent LastSaveIntent) !CmdSave {
	if intent.paths.len == 0 {
		return error('last save intent has no paths')
	}

	message := if cmd.message_set { cmd.message } else { intent.message }
	max_file_bytes := if cmd.max_file_bytes_set { cmd.max_file_bytes } else { intent.max_file_bytes }
	max_file_bytes_set := cmd.max_file_bytes_set || intent.max_file_bytes_set

	return CmdSave{
		paths:              intent.paths.clone()
		message:            message
		max_file_bytes:     max_file_bytes
		max_file_bytes_set: max_file_bytes_set
		force:              intent.force || cmd.force
		dry_run:            cmd.dry_run
	}
}

// save_intent returns the persistent intent represented by a save command.
fn (cmd CmdSave) save_intent() LastSaveIntent {
	return LastSaveIntent{
		paths:              cmd.paths.clone()
		message:            cmd.message
		max_file_bytes:     cmd.max_file_bytes
		max_file_bytes_set: cmd.max_file_bytes_set
		force:              cmd.force
	}
}

// write_last_save_intent stores the most recent successful manual save intent.
fn write_last_save_intent(intent LastSaveIntent) ! {
	ensure_store_root()!
	path := last_save_path()
	tmp_path := '${path}.tmp-${os.getpid()}'

	if os.exists(tmp_path) {
		os.rm(tmp_path)!
	}

	defer {
		os.rm(tmp_path) or {}
	}

	os.write_file(tmp_path, json.encode_pretty(intent))!
	os.mv(tmp_path, path, overwrite: true)!
}

// read_last_save_intent reads the most recent successful manual save intent.
fn read_last_save_intent() !LastSaveIntent {
	path := last_save_path()

	if !os.exists(path) {
		return error('no previous save to repeat')
	}

	return json.decode(LastSaveIntent, os.read_file(path)!)!
}

// last_save_path returns the path to .vsnap/last-save.json.
fn last_save_path() string {
	return os.join_path(store_path(), last_save_name)
}
