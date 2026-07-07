module main

import os

struct CmdClean {
	// keep is the number of newest manual snapshots to retain.
	keep int
}

// execute executes a clean command after handwritten argument parsing.
fn (cmd CmdClean) execute() ! {
	op_lock := acquire_lock('clean')!

	defer {
		op_lock.release()
	}

	snaps := read_index()!
	manual_newest := newest_first(snaps.filter(it.kind != .safety))
	mut keep_ids := map[string]bool{}

	for i, snap in manual_newest {
		if i < cmd.keep {
			keep_ids[snap.id] = true
		}
	}

	mut kept := []SnapshotIndex{}
	mut remove_archives := []string{}

	for snap in snaps {
		if snap.kind == .safety {
			kept << snap
			continue
		}

		if !keep_ids[snap.id] {
			if snap.archive != '' {
				remove_archives << snap.archive
			}

			continue
		}

		kept << snap
	}

	write_index(kept)!
	mut deleted_archives := 0

	for archive in remove_archives {
		archive_path := os.join_path(store_path(), archive)

		if !os.exists(archive_path) {
			continue
		}

		os.rm(archive_path) or {
			eprintln('${c_warn('warning:')} failed to delete ${archive}: ${err}')
			continue
		}

		deleted_archives++
	}

	println('${c_warn('removed')} ${remove_archives.len} manual snapshots, kept ${cmd.keep} manual snapshots')

	if deleted_archives < remove_archives.len {
		eprintln(c_muted('some archive files remain; run vsnap doctor to inspect orphan archives'))
	}
}
