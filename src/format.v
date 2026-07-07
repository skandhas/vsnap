module main

import term

// human_bytes formats byte counts using compact binary units.
fn human_bytes(value u64) string {
	units := ['B', 'KB', 'MB', 'GB']
	mut size := f64(value)
	mut unit := 0

	for size >= 1024 && unit < units.len - 1 {
		size /= 1024
		unit++
	}

	if unit == 0 {
		return '${value} B'
	}

	return '${size:.1f} ${units[unit]}'
}

// pad_left left-pads a string to a target display width.
fn pad_left(value string, width int) string {
	if value.len >= width {
		return value
	}

	return ' '.repeat(width - value.len) + value
}

// pad_right right-pads a string to a target display width.
fn pad_right(value string, width int) string {
	if value.len >= width {
		return value
	}

	return value + ' '.repeat(width - value.len)
}

// c_ok colors successful or healthy text.
fn c_ok(s string) string {
	return term.colorize(term.bright_green, s)
}

// c_warn colors warning text.
fn c_warn(s string) string {
	return term.colorize(term.bright_yellow, s)
}

// c_danger colors dangerous or error text.
fn c_danger(s string) string {
	return term.colorize(term.bright_red, s)
}

// c_info colors informational emphasis.
fn c_info(s string) string {
	return term.colorize(term.bright_cyan, s)
}

// c_muted colors secondary text.
fn c_muted(s string) string {
	return term.colorize(term.gray, s)
}

// c_title styles section titles.
fn c_title(s string) string {
	return term.colorize(term.bold, s)
}

// c_err colors error text written to stderr.
fn c_err(s string) string {
	return term.ecolorize(term.bright_red, s)
}

// format_snapshot_kind renders a snapshot kind with color and padding.
fn format_snapshot_kind(kind SnapshotKind, width int) string {
	label := pad_right(kind.label(), width)
	return match kind {
		.manual { c_ok(label) }
		.safety { c_warn(label) }
	}
}

// format_doctor_level renders a doctor severity with color and padding.
fn format_doctor_level(level DoctorLevel, width int) string {
	label := pad_right(level.label(), width)
	return match level {
		.ok { c_ok(label) }
		.warn { c_warn(label) }
		.error { c_danger(label) }
	}
}

// format_restore_action renders a restore action with color and padding.
fn format_restore_action(action RestoreAction, width int) string {
	label := pad_right(action.label(), width)
	return match action {
		.overwrite { c_danger(label) }
		.recreate { c_info(label) }
		.unchanged { c_ok(label) }
	}
}
