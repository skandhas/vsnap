module main

import json
import os
import strconv

const config_key_limits = 'limits'
const config_key_limits_file = 'limits.file'
const config_key_file_size = 'limits.file.size'
const config_key_file_count = 'limits.file.count'

struct EffectiveConfig {
	// max_file_bytes is the resolved single-file limit in bytes.
	max_file_bytes u64

	// max_file_bytes_source describes where the file-size limit came from.
	max_file_bytes_source string

	// max_file_count is the resolved file-count guard.
	max_file_count int

	// max_file_count_source describes where the file-count guard came from.
	max_file_count_source string

	// config_exists records whether .vsnap/config.json exists.
	config_exists bool
}

struct ConfigEntry {
	// key is the dot-path config key.
	key string

	// value is the effective display value.
	value string

	// source describes whether the value came from defaults or config.
	source string
}

enum CmdConfigAction {
	list
	init
	unset
	get
	set_value
}

struct CmdConfig {
	// action is the config operation selected by handwritten parsing.
	action CmdConfigAction

	// key is the config dot-path used by get, set, and unset.
	key string

	// value is the raw config value used by set.
	value string
}

// cmd_config handles config reads, writes, initialization, and unsets.
fn cmd_config(args []string) ! {
	cmd := parse_config_args(args)!
	cmd.execute()!
}

// execute executes a config command after handwritten argument parsing.
fn (cmd CmdConfig) execute() ! {
	match cmd.action {
		.list {
			print_config_entries('')!
		}
		.init {
			cmd.execute_with_config_lock()!
		}
		.unset {
			cmd.execute_with_config_lock()!
		}
		.get {
			print_config_entries(cmd.key)!
		}
		.set_value {
			cmd.execute_with_config_lock()!
		}
	}
}

// execute_with_config_lock executes config mutations while holding the operation lock.
fn (cmd CmdConfig) execute_with_config_lock() ! {
	match cmd.action {
		.init, .unset, .set_value {
			// Mutating config operations share the same lock path as other writes.
		}
		else {
			return error('config action does not need a write lock')
		}
	}

	op_lock := acquire_lock('config')!

	defer {
		op_lock.release()
	}

	match cmd.action {
		.init {
			init_config()!
		}
		.unset {
			unset_config_key(cmd.key)!
		}
		.set_value {
			set_config_key(cmd.key, cmd.value)!
		}
		else {}
	}
}

// parse_config_args parses config arguments while preserving current command rules.
fn parse_config_args(args []string) !CmdConfig {
	if args.len == 0 || (args.len == 1 && args[0] == '--list') {
		return CmdConfig{
			action: .list
		}
	}

	if args.len == 1 && (args[0] == '--init' || args[0] == 'init') {
		return CmdConfig{
			action: .init
		}
	}

	if args[0] == '--unset' {
		if args.len != 2 {
			return error('config --unset needs a key')
		}

		return CmdConfig{
			action: .unset
			key:    args[1]
		}
	}

	if args.len == 1 {
		return CmdConfig{
			action: .get
			key:    args[0]
		}
	}

	if args.len == 2 {
		return CmdConfig{
			action: .set_value
			key:    args[0]
			value:  args[1]
		}
	}

	return error('invalid config command')
}

// init_config creates .vsnap/config.json with default values.
fn init_config() ! {
	ensure_store_root()!
	path := config_path()

	if os.exists(path) {
		return error('config already exists: ${config_display_path()}')
	}

	write_config(default_config_file())!
	println('${c_ok('created')} ${c_info(config_display_path())}')
}

// print_config_entries prints matching effective config entries.
fn print_config_entries(query string) ! {
	entries := config_entries()!
	mut selected := []ConfigEntry{}

	for entry in entries {
		if query == '' || entry.key == query || entry.key.starts_with(query + '.') {
			selected << entry
		}
	}

	if selected.len == 0 {
		return error('unknown config key: ${query}')
	}

	print_entries_table(selected)

	if !config_exists() {
		println(c_muted('config file: not created'))
	} else {
		println('${c_muted('config file:')} ${config_display_path()}')
	}
}

// print_entries_table renders config entries as an aligned table.
fn print_entries_table(entries []ConfigEntry) {
	mut key_width := 'KEY'.len
	mut value_width := 'VALUE'.len

	for entry in entries {
		if entry.key.len > key_width {
			key_width = entry.key.len
		}

		if entry.value.len > value_width {
			value_width = entry.value.len
		}
	}

	println('${c_muted(pad_right('KEY', key_width))}  ${c_muted(pad_right('VALUE', value_width))}  ${c_muted('SOURCE')}')

	for entry in entries {
		key := pad_right(entry.key, key_width)
		value := pad_right(entry.value, value_width)
		source := if entry.source == 'default' {
			c_muted(entry.source)
		} else {
			c_info(entry.source)
		}

		println('${key}  ${c_info(value)}  ${source}')
	}
}

// set_config_key validates and writes one supported config key.
fn set_config_key(key string, value string) ! {
	mut cfg := read_config()!

	match key {
		config_key_file_size {
			_ := parse_size(value)!
			cfg.limits.file.size = value.trim_space().to_upper()
		}
		config_key_file_count {
			count := strconv.atoi(value) or { return error('limits.file.count must be a number') }

			if count <= 0 {
				return error('limits.file.count must be greater than zero')
			}

			cfg.limits.file.count = count
		}
		else {
			return error('unknown config key: ${key}')
		}
	}

	write_config(cfg)!
	println('${c_ok('set')} ${key}')
}

// unset_config_key removes one supported leaf config key.
fn unset_config_key(key string) ! {
	mut cfg := read_config()!

	match key {
		config_key_file_size {
			cfg.limits.file.size = none
		}
		config_key_file_count {
			cfg.limits.file.count = none
		}
		config_key_limits, config_key_limits_file {
			return error('config --unset only supports leaf keys')
		}
		else {
			return error('unknown config key: ${key}')
		}
	}

	write_config(cfg)!
	println('${c_warn('unset')} ${key}')
}

// config_entries returns effective config entries for display.
fn config_entries() ![]ConfigEntry {
	effective := effective_config()!
	return [
		ConfigEntry{
			key:    config_key_file_size
			value:  human_bytes(effective.max_file_bytes)
			source: effective.max_file_bytes_source
		},
		ConfigEntry{
			key:    config_key_file_count
			value:  '${effective.max_file_count}'
			source: effective.max_file_count_source
		},
	]
}

// effective_config resolves config values with defaults.
fn effective_config() !EffectiveConfig {
	cfg := read_config()!
	mut max_file_bytes := default_max_file_bytes
	mut max_file_bytes_source := 'default'

	if raw_size := cfg.limits.file.size {
		max_file_bytes = parse_size(raw_size)!
		max_file_bytes_source = config_display_path()
	}

	mut max_file_count := default_max_snapshot_files
	mut max_file_count_source := 'default'

	if count := cfg.limits.file.count {
		if count <= 0 {
			return error('limits.file.count must be greater than zero')
		}

		max_file_count = count
		max_file_count_source = config_display_path()
	}

	return EffectiveConfig{
		max_file_bytes:        max_file_bytes
		max_file_bytes_source: max_file_bytes_source
		max_file_count:        max_file_count
		max_file_count_source: max_file_count_source
		config_exists:         config_exists()
	}
}

// read_config reads config.json or returns an empty config when absent.
fn read_config() !VSnapConfig {
	path := config_path()

	if !os.exists(path) {
		return VSnapConfig{}
	}

	return json.decode(VSnapConfig, os.read_file(path)!)!
}

// write_config writes config.json through a temporary file.
fn write_config(cfg VSnapConfig) ! {
	ensure_store_root()!
	path := config_path()
	tmp_path := '${path}.tmp-${os.getpid()}'

	if os.exists(tmp_path) {
		os.rm(tmp_path)!
	}

	defer {
		os.rm(tmp_path) or {}
	}

	os.write_file(tmp_path, json.encode_pretty(cfg))!
	os.mv(tmp_path, path, overwrite: true)!
}

// default_config_file returns the default config file contents.
fn default_config_file() VSnapConfig {
	return VSnapConfig{
		limits: ConfigLimits{
			file: ConfigFileLimits{
				size:  '25MB'
				count: default_max_snapshot_files
			}
		}
	}
}

// config_exists reports whether .vsnap/config.json exists.
fn config_exists() bool {
	return os.exists(config_path())
}

// config_path returns the absolute project config path.
fn config_path() string {
	return os.join_path(store_path(), config_name)
}

// config_display_path returns the user-facing relative config path.
fn config_display_path() string {
	return os.join_path(store_dir, config_name)
}
