import os
import time

struct CmdResult {
	code int
	out  string
}

struct SnapshotRef {
	id           string
	archive      string
	archive_hash string
}

fn main() {
	keep := '--keep' in os.args
	project_dir := os.real_path(os.join_path(os.dir(@FILE), '..'))
	build_dir := os.join_path(project_dir, 'build')
	exe_path := os.join_path(build_dir, exe_name())
	root_dir := os.join_path(os.temp_dir(), 'vsnap-corruption-${time.now().unix()}-${os.getpid()}')

	println('vsnap corruption test')
	println('project: ${project_dir}')
	println('workdir: ${root_dir}')
	println('')

	os.mkdir_all(root_dir) or { fail('create corruption directory', err.msg()) }
	defer {
		if keep {
			println('')
			println('kept corruption directory: ${root_dir}')
		} else {
			os.rmdir_all(root_dir) or { eprintln('warning: failed to remove ${root_dir}: ${err}') }
		}
	}
	setup_v_environment(root_dir)
	os.mkdir_all(build_dir) or { fail('create build directory', err.msg()) }

	run_ok('build vsnap', 'v -o ${quote(exe_path)} src', project_dir)

	check_missing_archive(exe_path, root_dir)
	check_archive_hash_mismatch(exe_path, root_dir)
	check_orphan_archive(exe_path, root_dir)
	check_incomplete_temp_archive(exe_path, root_dir)
	check_invalid_index_json(exe_path, root_dir)
	check_missing_archive_hash(exe_path, root_dir)

	println('')
	println('ok: corruption test passed')
}

fn check_missing_archive(exe_path string, root_dir string) {
	work_dir := create_snapshot_project(exe_path, root_dir, 'missing-archive')
	snap := read_first_snapshot(work_dir)
	os.rm(os.join_path(work_dir, '.vsnap', snap.archive)) or {
		fail('remove archive for missing archive case', err.msg())
	}
	doctor := run_expect('doctor reports missing archive', '${quote(exe_path)} doctor',
		work_dir, 1)
	assert_contains(doctor.out, 'archive missing', 'missing archive doctor output')
}

fn check_archive_hash_mismatch(exe_path string, root_dir string) {
	work_dir := create_snapshot_project(exe_path, root_dir, 'hash-mismatch')
	snap := read_first_snapshot(work_dir)
	mut file := os.open_append(os.join_path(work_dir, '.vsnap', snap.archive)) or {
		fail('open archive for corruption', err.msg())
	}
	file.write_string('corruption') or { fail('append archive corruption', err.msg()) }
	file.close()
	doctor := run_expect('doctor reports archive hash mismatch', '${quote(exe_path)} doctor',
		work_dir, 1)
	assert_contains(doctor.out, 'archive hash mismatch', 'hash mismatch doctor output')
}

fn check_orphan_archive(exe_path string, root_dir string) {
	work_dir := create_snapshot_project(exe_path, root_dir, 'orphan-archive')
	snap := read_first_snapshot(work_dir)
	src := os.join_path(work_dir, '.vsnap', snap.archive)
	dst := os.join_path(work_dir, '.vsnap', 'snapshots', 'orphan.zip')
	os.cp(src, dst) or { fail('copy orphan archive', err.msg()) }
	doctor := run_ok('doctor warns about orphan archive', '${quote(exe_path)} doctor',
		work_dir)
	assert_contains(doctor.out, 'archive is not referenced by index', 'orphan archive doctor output')
	assert_contains(doctor.out, '1 warn', 'orphan archive doctor warning count')
}

fn check_incomplete_temp_archive(exe_path string, root_dir string) {
	work_dir := create_snapshot_project(exe_path, root_dir, 'incomplete-temp')
	write_file(os.join_path(work_dir, '.vsnap', 'snapshots', 'leftover.zip.tmp'), 'partial\n')
	doctor := run_ok('doctor warns about incomplete temp archive', '${quote(exe_path)} doctor',
		work_dir)
	assert_contains(doctor.out, 'incomplete archive temp file', 'incomplete temp doctor output')
	assert_contains(doctor.out, '1 warn', 'incomplete temp doctor warning count')
}

fn check_invalid_index_json(exe_path string, root_dir string) {
	work_dir := os.join_path(root_dir, 'invalid-index')
	os.mkdir_all(os.join_path(work_dir, '.vsnap', 'snapshots')) or {
		fail('create invalid index fixture', err.msg())
	}
	write_file(os.join_path(work_dir, '.vsnap', 'index.jsonl'), '{not valid json}\n')
	doctor := run_expect('doctor reports invalid index JSON', '${quote(exe_path)} doctor',
		work_dir, 1)
	assert_contains(doctor.out, 'invalid JSON', 'invalid index doctor output')
}

fn check_missing_archive_hash(exe_path string, root_dir string) {
	work_dir := create_snapshot_project(exe_path, root_dir, 'missing-hash')
	snap := read_first_snapshot(work_dir)
	index_path := os.join_path(work_dir, '.vsnap', 'index.jsonl')
	index := os.read_file(index_path) or { fail('read index for missing hash case', err.msg()) }
	updated := index.replace('"archive_hash":"${snap.archive_hash}"', '"archive_hash":""')
	write_file(index_path, updated)
	doctor := run_ok('doctor warns about missing archive hash', '${quote(exe_path)} doctor',
		work_dir)
	assert_contains(doctor.out, 'archive hash is missing in index', 'missing hash doctor output')
	assert_contains(doctor.out, '1 warn', 'missing hash doctor warning count')
}

fn create_snapshot_project(exe_path string, root_dir string, name string) string {
	work_dir := os.join_path(root_dir, name)
	os.mkdir_all(work_dir) or { fail('create ${name} fixture', err.msg()) }
	write_file(os.join_path(work_dir, 'file.txt'), '${name}\n')
	run_ok('save fixture ${name}', '${quote(exe_path)} save . -m "${name}"', work_dir)
	return work_dir
}

fn read_first_snapshot(work_dir string) SnapshotRef {
	index_path := os.join_path(work_dir, '.vsnap', 'index.jsonl')
	content := os.read_file(index_path) or { fail('read index ${index_path}', err.msg()) }
	line := content.split_into_lines()[0]
	return SnapshotRef{
		id:           json_string_field(line, 'id')
		archive:      json_string_field(line, 'archive')
		archive_hash: json_string_field(line, 'archive_hash')
	}
}

fn json_string_field(line string, key string) string {
	needle := '"${key}":"'
	start := line.index(needle) or { fail('find JSON field ${key}', line) }
	value_start := start + needle.len
	rest := line[value_start..]
	end := rest.index('"') or { fail('find JSON field end ${key}', line) }
	return rest[..end]
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

@[noreturn]
fn fail(label string, message string) {
	eprintln('')
	eprintln('FAIL: ${label}')
	eprintln(message)
	exit(1)
}
