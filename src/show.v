module main

struct CmdShow {
	// selector is the snapshot id prefix or list number.
	selector string

	// tree chooses tree output instead of table output.
	tree bool
}

// execute executes a show command after handwritten argument parsing.
fn (cmd CmdShow) execute() ! {
	snap := resolve_snapshot(cmd.selector)!
	manifest := read_manifest_from_archive(snap)!
	kind_label := format_snapshot_kind(snap.kind, snap.kind.label().len)
	println('${c_info(snap.id)}  ${kind_label}  ${c_muted(snap.created)}  ${snap.message}')

	if cmd.tree {
		print_show_tree(manifest.files)
	} else {
		print_show_files(manifest.files)
	}
}

// print_show_files renders manifest files as an aligned table.
fn print_show_files(files []ManifestFile) {
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

// print_show_tree renders manifest files as a directory tree.
fn print_show_tree(files []ManifestFile) {
	if files.len == 0 {
		println(c_muted('  no files'))
		return
	}

	mut ordered := files.clone()
	ordered.sort(a.path < b.path)
	mut printed_dirs := map[string]bool{}
	mut size_width := 'SIZE'.len

	for file in ordered {
		file_size_width := human_bytes(file.size).len

		if file_size_width > size_width {
			size_width = file_size_width
		}
	}

	for file in ordered {
		parts := file.path.split('/')

		if parts.len == 0 {
			continue
		}

		mut dir_key := ''

		for i := 0; i < parts.len - 1; i++ {
			part := parts[i]
			dir_key = if dir_key == '' { part } else { '${dir_key}/${part}' }

			if printed_dirs[dir_key] {
				continue
			}

			printed_dirs[dir_key] = true
			indent := '  ' + '  '.repeat(i)
			println('${indent}${c_info(part + '/')}')
		}

		name := parts[parts.len - 1]
		indent := '  ' + '  '.repeat(parts.len - 1)
		size := pad_left(human_bytes(file.size), size_width)
		hash := pad_right(file.hash[..12], 12)
		println('${indent}${name}  ${c_info(size)}  ${c_muted(hash)}')
	}
}
