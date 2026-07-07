module main

struct CmdList {
	// show_all includes safety snapshots in list output.
	show_all bool
}

// execute executes a list command after handwritten argument parsing.
fn (cmd CmdList) execute() ! {
	snaps := listed_snapshots(cmd.show_all)!

	if snaps.len == 0 {
		println(if cmd.show_all { 'no snapshots yet' } else { 'no manual snapshots yet' })
		return
	}

	print_snapshot_list(snaps)
}

// print_snapshot_list renders the snapshot index as an aligned table.
fn print_snapshot_list(snaps []SnapshotIndex) {
	mut no_width := 'NO'.len
	mut kind_width := 'KIND'.len
	mut files_width := 'FILES'.len
	mut size_width := 'SIZE'.len
	mut id_width := 'ID'.len

	for i, snap in snaps {
		no_len := '${i + 1}.'.len

		if no_len > no_width {
			no_width = no_len
		}

		kind_len := snap.kind.label().len

		if kind_len > kind_width {
			kind_width = kind_len
		}

		files_len := '${snap.files}'.len

		if files_len > files_width {
			files_width = files_len
		}

		size_len := human_bytes(snap.bytes).len

		if size_len > size_width {
			size_width = size_len
		}

		if snap.id.len > id_width {
			id_width = snap.id.len
		}
	}

	no_header := pad_left('NO', no_width)
	kind_header := pad_right('KIND', kind_width)
	files_header := pad_left('FILES', files_width)
	size_header := pad_left('SIZE', size_width)
	id_header := pad_right('ID', id_width)
	println('${c_muted(no_header)}  ${c_muted('CREATED            ')}  ${c_muted(kind_header)}  ${c_muted(files_header)}  ${c_muted(size_header)}  ${c_muted(id_header)}  ${c_muted('MESSAGE')}')

	for i, snap in snaps {
		no_label := c_muted(pad_left('${i + 1}.', no_width))
		kind_label := format_snapshot_kind(snap.kind, kind_width)
		files := pad_left('${snap.files}', files_width)
		size := pad_left(human_bytes(snap.bytes), size_width)
		id := pad_right(snap.id, id_width)
		println('${no_label}  ${c_muted(snap.created)}  ${kind_label}  ${c_info(files)}  ${c_info(size)}  ${c_info(id)}  ${snap.message}')
	}
}
