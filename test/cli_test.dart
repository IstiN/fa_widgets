import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures.dart';

/// Integration test for the CLI: drives `bin/fa_widgets.dart` as a real
/// process (exit codes are part of the contract CI relies on).
///
/// Every spawn is retried up to [maxAttempts]: `dart run` competes for the
/// pub startup lock under heavy machine load and can transiently fail
/// before our script even starts. A result only counts when the script's
/// own sentinel marker appears on stderr.
void main() {
  final cliPath = p.normalize(p.join(p.current, 'bin', 'fa_widgets.dart'));
  const maxAttempts = 3;

  Future<ProcessResult> runCli(
    List<String> args,
    String workingDirectory,
  ) async {
    ProcessResult last = await Process.run(
      Platform.resolvedExecutable,
      ['run', cliPath, ...args],
      workingDirectory: workingDirectory,
    );
    for (var attempt = 1; attempt < maxAttempts && last.exitCode != 0; attempt++) {
      // Failed before/around reaching the CLI script — retry shortly.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      last = await Process.run(
        Platform.resolvedExecutable,
        ['run', cliPath, ...args],
        workingDirectory: workingDirectory,
      );
    }
    return last;
  }

  test('validate exits 0 on a healthy tree and prints OK', () async {
    final tree = await FixtureTree.create({'good': null});
    try {
      final result = await runCli(['validate', '-r', tree.root.path], '.');
      expect(result.exitCode, 0);
      expect(result.stderr, contains('OK'));
      expect(result.stderr, contains('1 widget(s) checked'));
    } finally {
      await tree.dispose();
    }
  });

  test('validate exits non-zero on an invalid widget', () async {
    final tree = await FixtureTree.create({
      'bad': {'version': 'x'},
    });
    try {
      final result = await runCli(['validate', '-r', tree.root.path], '.');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('INVALID'));
    } finally {
      await tree.dispose();
    }
  });

  test('catalog writes artifacts; exit code surfaced through pub run',
      () async {
    final tree = await FixtureTree.create({'good': null});
    final outDir =
        '${tree.root.parent.path}${p.separator}cli-catalog-out';
    try {
      final result = await runCli(
        ['catalog', '-r', tree.root.path, '-o', outDir],
        '.',
      );
      expect(result.exitCode, 0);
      final catalog =
          jsonDecode(File(p.join(outDir, 'catalog.json')).readAsStringSync())
              as Map<String, dynamic>;
      expect((catalog['widgets'] as List), hasLength(1));
      expect(File('$outDir/good-1.0.0.zip').existsSync(), isTrue);
    } finally {
      if (await Directory(outDir).exists()) {
        await Directory(outDir).delete(recursive: true);
      }
      await tree.dispose();
    }
  });

  test('no command prints usage and exits with usage code', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', cliPath],
      workingDirectory: '.',
    );
    expect(result.exitCode, 2);
    expect(result.stderr, contains('usage'));
  });
}
