import os
import time

struct CmdResult {
	code int
	out  string
}

fn main() {
	keep := '--keep' in os.args
	project_dir := os.real_path(os.join_path(os.dir(@FILE), '..'))
	build_dir := os.join_path(project_dir, 'build')
	exe_path := os.join_path(build_dir, exe_name())
	smoke_dir := os.join_path(os.temp_dir(), 'vsnap-smoke-${time.now().unix()}-${os.getpid()}')

	println('vsnap smoke test')
	println('project: ${project_dir}')
	println('workdir: ${smoke_dir}')
	println('')

	os.mkdir_all(smoke_dir) or { fail('create smoke directory', err.msg()) }
	defer {
		if keep {
			println('')
			println('kept smoke directory: ${smoke_dir}')
		} else {
			os.rmdir_all(smoke_dir) or {
				eprintln('warning: failed to remove ${smoke_dir}: ${err}')
			}
		}
	}
	setup_v_environment(smoke_dir)
	os.mkdir_all(build_dir) or { fail('create build directory', err.msg()) }

	run_ok('build vsnap', 'v -o ${quote(exe_path)} src', project_dir)

	write_file(os.join_path(smoke_dir, 'README.md'), 'alpha\n')
	os.mkdir_all(os.join_path(smoke_dir, 'src')) or { fail('create src directory', err.msg()) }
	write_file(os.join_path(smoke_dir, 'src', 'main.v'), 'fn main() {\n\tprintln("hello")\n}\n')
	write_file(os.join_path(smoke_dir, 'notes.txt'), 'remember this\n')

	version := run_ok('version', '${quote(exe_path)} version', smoke_dir)
	assert_contains(version.out, 'vsnap ', 'version output')

	binary_dir := os.join_path(smoke_dir, 'binary-project')
	os.mkdir_all(binary_dir) or { fail('create binary test directory', err.msg()) }
	binary_path := os.join_path(binary_dir, 'asset.bin')
	original_binary := binary_fixture(17)
	changed_binary := binary_fixture(91)
	write_bytes(binary_path, original_binary)

	binary_save := run_ok('save binary snapshot', '${quote(exe_path)} save asset.bin -m "binary baseline"',
		binary_dir)
	assert_contains(binary_save.out, 'saved', 'binary save output')

	write_bytes(binary_path, changed_binary)
	assert_file_bytes(binary_path, changed_binary, 'binary file should be changed before restore')

	binary_restore := run_ok('restore binary snapshot', '${quote(exe_path)} restore 1',
		binary_dir)
	assert_contains(binary_restore.out, 'restored', 'binary restore output')
	assert_file_bytes(binary_path, original_binary, 'restore should recover binary bytes exactly')

	alias_dir := os.join_path(smoke_dir, 'alias-project')
	os.mkdir_all(alias_dir) or { fail('create alias test directory', err.msg()) }
	alias_path := os.join_path(alias_dir, 'note.txt')
	write_file(alias_path, 'alias original\n')

	alias_save_help := run_ok('save alias help', '${quote(exe_path)} help s', alias_dir)
	assert_contains(alias_save_help.out, 'vsnap save <path...>', 'save alias help output')

	alias_restore_help := run_ok('restore alias help', '${quote(exe_path)} rs --help',
		alias_dir)
	assert_contains(alias_restore_help.out, 'vsnap restore <id|number>', 'restore alias help output')

	alias_save := run_ok('save alias snapshot', '${quote(exe_path)} s note.txt -m "alias save"',
		alias_dir)
	assert_contains(alias_save.out, 'saved', 'save alias output')

	write_file(alias_path, 'alias changed\n')
	alias_restore_preview := run_ok('restore alias dry-run', '${quote(exe_path)} rs 1 --dry-run',
		alias_dir)
	assert_contains(alias_restore_preview.out, 'dry-run: no files changed', 'restore alias dry-run output')
	assert_file_content(alias_path, 'alias changed\n', 'restore alias dry-run should not change file')

	alias_restore := run_ok('restore alias snapshot', '${quote(exe_path)} rs 1', alias_dir)
	assert_contains(alias_restore.out, 'restored', 'restore alias output')
	assert_file_content(alias_path, 'alias original\n', 'restore alias should recover file')

	config_again_dir := os.join_path(smoke_dir, 'config-again-project')
	os.mkdir_all(config_again_dir) or { fail('create config again test directory', err.msg()) }
	write_file(os.join_path(config_again_dir, 'one.txt'), 'one\n')
	write_file(os.join_path(config_again_dir, 'two.txt'), 'two\n')

	config_again_save := run_ok('save config again baseline', '${quote(exe_path)} save . -m "config again baseline"',
		config_again_dir)
	assert_contains(config_again_save.out, 'saved', 'config again save output')

	run_ok('set config again file-count guard', '${quote(exe_path)} config limits.file.count 1',
		config_again_dir)
	config_again_guard := run_expect('again obeys config file-count guard', '${quote(exe_path)} again --dry-run',
		config_again_dir, 1)
	assert_contains(config_again_guard.out, 'would stop', 'config again guard output')

	config_again_force := run_ok('again force bypasses config guard', '${quote(exe_path)} again --dry-run --force',
		config_again_dir)
	assert_contains(config_again_force.out, 'would save', 'config again force output')

	help := run_ok('top-level help', '${quote(exe_path)} help', smoke_dir)
	assert_contains(help.out, 'Commands:', 'top-level help output')
	assert_contains(help.out, 'vsnap help <command>', 'top-level help output')
	assert_not_contains(help.out, '--max-file', 'top-level help should stay compact')

	save_help := run_ok('save help', '${quote(exe_path)} help save', smoke_dir)
	assert_contains(save_help.out, 'vsnap save <path...>', 'save help output')
	assert_contains(save_help.out, '--max-file', 'save help output')

	save_flag_help := run_ok('save flag help', '${quote(exe_path)} save --help', smoke_dir)
	assert_contains(save_flag_help.out, 'vsnap save <path...>', 'save --help output')

	preview := run_ok('save dry-run', '${quote(exe_path)} save . -m "preview" --dry-run',
		smoke_dir)
	assert_contains(preview.out, 'dry-run: no snapshot created', 'save dry-run output')
	assert_not_exists(os.join_path(smoke_dir, '.vsnap'), 'dry-run should not create .vsnap')

	first := run_ok('save first snapshot', '${quote(exe_path)} save . -m "first snapshot"',
		smoke_dir)
	assert_contains(first.out, 'saved', 'save output')
	assert_exists(os.join_path(smoke_dir, '.vsnap'), 'save should create .vsnap')
	assert_exists(os.join_path(smoke_dir, '.vsnap', 'last-save.json'), 'save should record last save intent')

	list := run_ok('list snapshots', '${quote(exe_path)} list', smoke_dir)
	assert_contains(list.out, 'first snapshot', 'list output')

	show := run_ok('show snapshot', '${quote(exe_path)} show 1', smoke_dir)
	assert_contains(show.out, 'README.md', 'show output')
	assert_contains(show.out, 'src/main.v', 'show output')

	show_tree := run_ok('show snapshot tree', '${quote(exe_path)} show 1 --tree', smoke_dir)
	assert_contains(show_tree.out, 'src/', 'show --tree output')
	assert_contains(show_tree.out, 'main.v', 'show --tree output')

	again_preview := run_ok('again dry-run with message override', '${quote(exe_path)} again --dry-run -m "again preview"',
		smoke_dir)
	assert_contains(again_preview.out, 'again preview', 'again dry-run output')
	assert_contains(again_preview.out, 'dry-run: no snapshot created', 'again dry-run output')

	again_save := run_ok('again save with message override', '${quote(exe_path)} again -m "second snapshot"',
		smoke_dir)
	assert_contains(again_save.out, 'saved', 'again save output')
	assert_contains(again_save.out, 'second snapshot', 'again save output')

	doctor := run_ok('doctor', '${quote(exe_path)} doctor', smoke_dir)
	assert_contains(doctor.out, '0 error', 'doctor output')

	write_file(os.join_path(smoke_dir, 'README.md'), 'changed\n')
	os.rm(os.join_path(smoke_dir, 'notes.txt')) or { fail('remove notes.txt', err.msg()) }

	restore_preview := run_ok('restore dry-run', '${quote(exe_path)} restore 1 --dry-run',
		smoke_dir)
	assert_contains(restore_preview.out, 'dry-run: no files changed', 'restore dry-run output')
	assert_file_content(os.join_path(smoke_dir, 'README.md'), 'changed\n', 'restore dry-run should not change README.md')
	assert_not_exists(os.join_path(smoke_dir, 'notes.txt'), 'restore dry-run should not recreate notes.txt')

	restore := run_ok('restore snapshot', '${quote(exe_path)} restore 1', smoke_dir)
	assert_contains(restore.out, 'restored', 'restore output')
	assert_file_content(os.join_path(smoke_dir, 'README.md'), 'alpha\n', 'restore should recover README.md')
	assert_file_content(os.join_path(smoke_dir, 'notes.txt'), 'remember this\n', 'restore should recreate notes.txt')

	all := run_ok('list all snapshots', '${quote(exe_path)} list --all', smoke_dir)
	assert_contains(all.out, 'safety', 'list --all output')

	clean_zero := run_ok('clean keeps zero manual snapshots', '${quote(exe_path)} clean --keep 0',
		smoke_dir)
	assert_contains(clean_zero.out, 'kept 0 manual snapshots', 'clean --keep 0 output')

	manual_after_clean := run_ok('list manual after clean zero', '${quote(exe_path)} list',
		smoke_dir)
	assert_contains(manual_after_clean.out, 'no manual snapshots yet', 'list manual after clean zero output')

	all_after_clean := run_ok('list all after clean zero', '${quote(exe_path)} list --all',
		smoke_dir)
	assert_contains(all_after_clean.out, 'safety', 'list all after clean zero output')

	undo := run_ok('undo safety snapshot', '${quote(exe_path)} undo', smoke_dir)
	assert_contains(undo.out, 'undone', 'undo output')
	assert_file_content(os.join_path(smoke_dir, 'README.md'), 'changed\n', 'undo should restore README.md to pre-restore content')
	assert_file_content(os.join_path(smoke_dir, 'notes.txt'), 'remember this\n', 'undo should leave recreated notes.txt in place')

	run_ok('set file-count guard', '${quote(exe_path)} config limits.file.count 1', smoke_dir)
	guard := run_expect('guard rejects broad save', '${quote(exe_path)} save . -m "too broad" --dry-run',
		smoke_dir, 1)
	assert_contains(guard.out, 'would stop', 'guard output')

	forced := run_ok('force bypasses guard in dry-run', '${quote(exe_path)} save . -m "intentional" --dry-run --force',
		smoke_dir)
	assert_contains(forced.out, 'would save', 'force dry-run output')
	run_ok('unset file-count guard', '${quote(exe_path)} config --unset limits.file.count',
		smoke_dir)

	final_doctor := run_ok('doctor after smoke test', '${quote(exe_path)} doctor', smoke_dir)
	assert_contains(final_doctor.out, '0 error', 'final doctor output')

	println('')
	println('ok: smoke test passed')
}

fn exe_name() string {
	$if windows {
		return 'vsnap.exe'
	} $else {
		return 'vsnap'
	}
}

fn setup_v_environment(smoke_dir string) {
	vmodules_dir := os.join_path(smoke_dir, 'vmodules')
	tmp_dir := os.join_path(smoke_dir, 'tmp')
	os.mkdir_all(vmodules_dir) or { fail('create vmodules directory', err.msg()) }
	os.mkdir_all(tmp_dir) or { fail('create tmp directory', err.msg()) }
	os.setenv('VMODULES', vmodules_dir, true)
	os.setenv('TMPDIR', tmp_dir, true)
}

fn quote(value string) string {
	return '"' + value.replace('"', '\\"') + '"'
}

fn run_ok(label string, command string, workdir string) CmdResult {
	return run_expect(label, command, workdir, 0)
}

fn run_expect(label string, command string, workdir string, expected int) CmdResult {
	result := run(command, workdir)
	if result.code != expected {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('command: ${command}')
		eprintln('workdir: ${workdir}')
		eprintln('expected exit: ${expected}')
		eprintln('actual exit: ${result.code}')
		eprintln(result.out)
		exit(1)
	}
	println('ok: ${label}')
	return result
}

fn run(command string, workdir string) CmdResult {
	old_dir := os.getwd()
	os.chdir(workdir) or { fail('chdir ${workdir}', err.msg()) }
	result := os.execute(command)
	os.chdir(old_dir) or { fail('chdir ${old_dir}', err.msg()) }
	return CmdResult{
		code: result.exit_code
		out:  result.output
	}
}

fn write_file(path string, content string) {
	os.write_file(path, content) or { fail('write ${path}', err.msg()) }
}

fn write_bytes(path string, content []u8) {
	os.write_bytes(path, content) or { fail('write bytes ${path}', err.msg()) }
}

fn binary_fixture(seed int) []u8 {
	mut content := []u8{len: 512}

	for i in 0 .. content.len {
		content[i] = u8((i * 31 + seed) % 256)
	}

	return content
}

fn assert_contains(text string, needle string, label string) {
	if !text.contains(needle) {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('expected output to contain: ${needle}')
		eprintln(text)
		exit(1)
	}
}

fn assert_not_contains(text string, needle string, label string) {
	if text.contains(needle) {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('expected output not to contain: ${needle}')
		eprintln(text)
		exit(1)
	}
}

fn assert_exists(path string, label string) {
	if !os.exists(path) {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('missing path: ${path}')
		exit(1)
	}
}

fn assert_not_exists(path string, label string) {
	if os.exists(path) {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('unexpected path: ${path}')
		exit(1)
	}
}

fn assert_file_content(path string, expected string, label string) {
	actual := os.read_file(path) or {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('read failed: ${path}')
		eprintln(err)
		exit(1)
	}
	if actual != expected {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('path: ${path}')
		eprintln('expected:')
		eprintln(expected)
		eprintln('actual:')
		eprintln(actual)
		exit(1)
	}
}

fn assert_file_bytes(path string, expected []u8, label string) {
	actual := os.read_bytes(path) or {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('read bytes failed: ${path}')
		eprintln(err)
		exit(1)
	}

	if actual != expected {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('path: ${path}')
		eprintln('expected bytes: ${expected.len}')
		eprintln('actual bytes: ${actual.len}')
		exit(1)
	}
}

@[noreturn]
fn fail(label string, message string) {
	eprintln('')
	eprintln('FAIL: ${label}')
	eprintln(message)
	exit(1)
}
