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
	edge_dir := os.join_path(os.temp_dir(), 'vsnap-edge-${time.now().unix()}-${os.getpid()}')
	work_dir := os.join_path(edge_dir, 'project')

	println('vsnap edge test')
	println('project: ${project_dir}')
	println('workdir: ${work_dir}')
	println('')

	os.mkdir_all(work_dir) or { fail('create edge directory', err.msg()) }
	defer {
		if keep {
			println('')
			println('kept edge directory: ${edge_dir}')
		} else {
			os.rmdir_all(edge_dir) or { eprintln('warning: failed to remove ${edge_dir}: ${err}') }
		}
	}
	setup_v_environment(edge_dir)
	os.mkdir_all(build_dir) or { fail('create build directory', err.msg()) }

	run_ok('build vsnap', 'v -o ${quote(exe_path)} src', project_dir)

	write_file(os.join_path(work_dir, 'small.txt'), 'small\n')
	write_file(os.join_path(work_dir, 'ignored.log'), 'ignore me\n')
	write_file(os.join_path(work_dir, '.vsnapignore'), '*.log\n')
	write_file(os.join_path(edge_dir, 'outside.txt'), 'outside\n')
	write_file(os.join_path(work_dir, 'large.bin'), 'x'.repeat(2048))
	write_file(os.join_path(work_dir, '-dash.txt'), 'dash\n')

	again_without_save := run_expect('again without previous save fails', '${quote(exe_path)} again --dry-run',
		work_dir, 1)
	assert_contains(again_without_save.out, 'no previous save to repeat', 'again without previous save output')
	assert_not_exists(os.join_path(work_dir, '.vsnap'), 'again without previous save should not create .vsnap')

	no_path := run_expect('save without explicit path fails', '${quote(exe_path)} save -m "missing path"',
		work_dir, 1)
	assert_contains(no_path.out, 'save needs at least one explicit path', 'missing path output')

	outside := run_expect('save outside path fails', '${quote(exe_path)} save ${quote(os.join_path(edge_dir,
		'outside.txt'))} -m "outside"', work_dir, 1)
	assert_contains(outside.out, 'path is outside current directory', 'outside path output')

	explicit_large := run_expect('explicit oversized file fails', '${quote(exe_path)} save large.bin -m "large" --max-file 1KB',
		work_dir, 1)
	assert_contains(explicit_large.out, 'above max file size', 'explicit large file output')

	directory_large := run_ok('directory oversized file is skipped', '${quote(exe_path)} save . -m "skip large" --max-file 1KB',
		work_dir)
	assert_contains(directory_large.out, 'skipped', 'directory large skip output')
	assert_contains(directory_large.out, 'large.bin', 'directory large skip output')

	ignore_preview := run_ok('vsnapignore applies to directory dry-run', '${quote(exe_path)} save . -m "ignore preview" --dry-run --max-file 1KB',
		work_dir)
	assert_contains(ignore_preview.out, 'small.txt', 'ignore preview output')
	assert_not_contains(ignore_preview.out, 'ignored.log', 'ignore preview output')

	dash_without_separator := run_expect('dash path without separator fails', '${quote(exe_path)} save -dash.txt -m "dash path" --dry-run',
		work_dir, 1)
	assert_contains(dash_without_separator.out, 'unknown save option: -dash.txt', 'dash path without separator output')

	dash_with_separator := run_ok('dash path with separator dry-run', '${quote(exe_path)} save --dry-run -m "dash path" -- -dash.txt',
		work_dir)
	assert_contains(dash_with_separator.out, '-dash.txt', 'dash path with separator output')
	assert_contains(dash_with_separator.out, 'dry-run: no snapshot created', 'dash path with separator output')

	show_missing := run_expect('show missing selector fails', '${quote(exe_path)} show no-such-snapshot',
		work_dir, 1)
	assert_contains(show_missing.out, 'no snapshot matches', 'show missing output')

	show_unknown_flag := run_expect('show unknown flag has vsnap prefix', '${quote(exe_path)} show --bad 1',
		work_dir, 1)
	assert_contains(show_unknown_flag.out, 'vsnap:', 'show unknown flag output')
	assert_contains(show_unknown_flag.out, 'unknown show option: --bad', 'show unknown flag output')

	restore_missing := run_expect('restore missing selector fails', '${quote(exe_path)} restore no-such-snapshot',
		work_dir, 1)
	assert_contains(restore_missing.out, 'no snapshot matches', 'restore missing output')

	restore_unknown_flag := run_expect('restore unknown flag has vsnap prefix', '${quote(exe_path)} restore --bad 1',
		work_dir, 1)
	assert_contains(restore_unknown_flag.out, 'vsnap:', 'restore unknown flag output')
	assert_contains(restore_unknown_flag.out, 'unknown restore option: --bad', 'restore unknown flag output')

	doctor_unknown_flag := run_expect('doctor unknown flag has vsnap prefix', '${quote(exe_path)} doctor --bad',
		work_dir, 1)
	assert_contains(doctor_unknown_flag.out, 'vsnap:', 'doctor unknown flag output')
	assert_contains(doctor_unknown_flag.out, 'unknown doctor option: --bad', 'doctor unknown flag output')

	unknown_config := run_expect('unknown config key fails', '${quote(exe_path)} config limits.unknown 1',
		work_dir, 1)
	assert_contains(unknown_config.out, 'unknown config key', 'unknown config output')

	make_fake_lock(work_dir)
	locked := run_expect('active lock blocks save', '${quote(exe_path)} save small.txt -m "locked"',
		work_dir, 1)
	assert_contains(locked.out, 'another operation is running', 'lock conflict output')
	run_ok('lock clear works after fake lock', '${quote(exe_path)} lock clear', work_dir)

	final_doctor := run_ok('doctor after edge test', '${quote(exe_path)} doctor', work_dir)
	assert_contains(final_doctor.out, '0 error', 'final doctor output')

	println('')
	println('ok: edge test passed')
}

fn exe_name() string {
	$if windows {
		return 'vsnap.exe'
	} $else {
		return 'vsnap'
	}
}

fn setup_v_environment(root string) {
	vmodules_dir := os.join_path(root, 'vmodules')
	tmp_dir := os.join_path(root, 'tmp')
	os.mkdir_all(vmodules_dir) or { fail('create vmodules directory', err.msg()) }
	os.mkdir_all(tmp_dir) or { fail('create tmp directory', err.msg()) }
	os.setenv('VMODULES', vmodules_dir, true)
	os.setenv('TMPDIR', tmp_dir, true)
}

fn make_fake_lock(work_dir string) {
	lock_dir := os.join_path(work_dir, '.vsnap', 'lock')
	os.mkdir_all(lock_dir) or { fail('create fake lock', err.msg()) }
	write_file(os.join_path(lock_dir, 'owner.json'), '{\n  "pid": 999999,\n  "command": "edge-test",\n  "created": "2026-07-05 00:00:00"\n}\n')
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

fn assert_not_exists(path string, label string) {
	if os.exists(path) {
		eprintln('')
		eprintln('FAIL: ${label}')
		eprintln('unexpected path: ${path}')
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
