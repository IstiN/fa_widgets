import 'dart:io';

import 'package:fa_widgets_tool/fa_widgets_tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  Map<String, dynamic> catalog(List<Map<String, String>> widgets) => {
    'schemaVersion': 1,
    'generatedAt': '2026-08-26T10:00:00.000Z',
    'widgets': [
      for (final w in widgets) {'id': w['id'], 'version': w['version']},
    ],
  };

  test('first publish (no previous) marks everything new, sorted', () {
    final changes = diffTagChanges(null, catalog([
      {'id': 'zeta', 'version': '1.0.0'},
      {'id': 'alpha', 'version': '2.3.4'},
    ]));
    expect(changes.map((TagChange c) => c.toString()), [
      'alpha 2.3.4',
      'zeta 1.0.0',
    ]);
    expect(changes.first.tagName, 'alpha-v2.3.4');
  });

  test('bumps detected; unchanged skipped; removals silent', () {
    final previous = catalog([
      {'id': 'alpha', 'version': '1.0.0'},
      {'id': 'gone', 'version': '1.0.0'},
      {'id': 'same', 'version': '0.9.9'},
    ]);
    final current = catalog([
      {'id': 'alpha', 'version': '1.1.0'},
      {'id': 'same', 'version': '0.9.9'},
      {'id': 'fresh', 'version': '1.0.0'},
    ]);
    final changes = diffTagChanges(previous, current);
    expect(changes.map((TagChange c) => c.id), ['alpha', 'fresh']);
  });

  test('malformed previous catalog behaves like first publish', () {
    // A torn/invalid JSON payload decodes to null upstream — the helper
    // receives an empty map here as the library-visible equivalent.
    final changes = diffTagChanges(
      const <String, dynamic>{},
      catalog([
        {'id': 'alpha', 'version': '1.0.0'},
      ]),
    );
    expect(changes.map((TagChange c) => c.id), ['alpha']);
  });

  test('CLI diff-tags prints lines and exits 0 (workflow contract)',
      () async {
    final tree = await FixtureTree.create({'good': null});
    try {
      CatalogBuilder(
        widgetsRoot: tree.root,
        now: () => DateTime.utc(2026, 8, 26, 10),
      ).build(outDir: Directory('${tree.root.parent.path}/out-a'));
      final resultA = File(
        '${tree.root.parent.path}/out-a/catalog.json',
      );

      // Bump and rebuild into a second dir.
      tree.widgetDir('good', {'version': '1.1.0'});
      CatalogBuilder(
        widgetsRoot: tree.root,
        now: () => DateTime.utc(2026, 8, 26, 11),
      ).build(outDir: Directory('${tree.root.parent.path}/out-b'));

      final cli = Process.run(Platform.resolvedExecutable, [
        'run',
        p.normalize(p.join(p.current, 'bin', 'fa_widgets.dart')),
        'diff-tags',
        '-p',
        resultA.path,
        '-c',
        '${tree.root.parent.path}/out-b/catalog.json',
      ]);
      final process = await cli;
      expect(process.exitCode, 0);
      expect(process.stdout.trim(), 'good 1.1.0');

      Directory? out;
      for (final dir in ['out-a', 'out-b']) {
        out = Directory('${tree.root.parent.path}/$dir');
        if (await out.exists()) await out.delete(recursive: true);
      }
    } finally {
      await tree.dispose();
    }
  });
}
