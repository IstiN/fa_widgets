import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fa_widgets_tool/fa_widgets_tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('zip bytes are deterministic across rebuilds (stable sha256)', () async {
    final tree = await FixtureTree.create({'alpha': null});
    final out1 = Directory('${tree.root.parent.path}/catalog-det1');
    final out2 = Directory('${tree.root.parent.path}/catalog-det2');
    try {
      CatalogBuilder(widgetsRoot: tree.root).build(outDir: out1);
      CatalogBuilder(widgetsRoot: tree.root).build(outDir: out2);
      final zip1 = File(p.join(out1.path, 'alpha-1.0.0.zip')).readAsBytesSync();
      final zip2 = File(p.join(out2.path, 'alpha-1.0.0.zip')).readAsBytesSync();
      expect(hexSha256(zip1), hexSha256(zip2));
      // And the catalogs agree (same sha for the same sources).
      final cat1 = jsonDecode(
        File(p.join(out1.path, 'catalog.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      final cat2 = jsonDecode(
        File(p.join(out2.path, 'catalog.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        (cat1['widgets'] as List).first['zip']['sha256'],
        (cat2['widgets'] as List).first['zip']['sha256'],
      );
    } finally {
      tree.dispose();
      out1.deleteSync(recursive: true);
      out2.deleteSync(recursive: true);
    }
  });

  test('builds catalog.json + zips per the release contract', () async {
    final tree = await FixtureTree.create({
      'zeta': {'version': '1.1.0'},
      'alpha': null,
    });
    final out = Directory('${tree.root.parent.path}/catalog-out');
    try {
      final result = CatalogBuilder(
        widgetsRoot: tree.root,
        now: () => DateTime.utc(2026, 8, 26, 10),
      ).build(outDir: out);

      // catalog.json
      final catalog = jsonDecode(result.catalogFile.readAsStringSync())
          as Map<String, dynamic>;
      expect(catalog['schemaVersion'], 1);
      expect(catalog['generatedAt'], '2026-08-26T10:00:00.000Z');
      expect(catalog['sourceRepo'], contains('IstiN/fa_widgets'));
      final widgets = (catalog['widgets'] as List).cast<Map<String, dynamic>>();
      expect(widgets.map((w) => w['id']).toList(), ['alpha', 'zeta']);

      // Entry shape: flat asset name, sha256 over real bytes, size honest.
      final alpha = widgets.first;
      expect(alpha['zip']['file'], 'alpha-1.0.0.zip');
      expect((alpha['zip']['file'] as String).contains('/'), isFalse);
      final bytes = File(p.join(out.path, 'alpha-1.0.0.zip')).readAsBytesSync();
      expect(alpha['zip']['sha256'], hexSha256(bytes));
      expect(alpha['zip']['sizeBytes'], bytes.length);
      expect(alpha['permissions'], {
        'network': false,
        'allowedCommands': isEmpty,
      });
      expect(alpha['minRuntime'], '0.4.79');

      // Zip layout: one root folder named after the id.
      expect(firstEntryRoot(bytes), 'alpha');
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(
        archive.files.map((ArchiveFile f) => f.name),
        containsAll([
          'alpha/manifest.json',
          'alpha/widget.js',
          'alpha/icon.svg',
        ]),
      );

      // Sorted file entries inside the zip.
      final names = archive.files.map((f) => f.name).toList();
      expect(names, equals([...names]..sort()));

      // Artifacts listed.
      expect(result.zipFiles.map((File f) => p.basename(f.path)).toSet(),
          {'alpha-1.0.0.zip', 'zeta-1.1.0.zip'});
    } finally {
      await out.delete(recursive: true);
      await tree.dispose();
    }
  });

  test('declared platforms flow into the catalog entry after tags', () async {
    final tree = await FixtureTree.create({
      'mobile-only': {
        'tags': ['demo'],
        'platforms': ['ios', 'macos'],
      },
    });
    final out = Directory('${tree.root.parent.path}/catalog-out');
    try {
      final result = CatalogBuilder(widgetsRoot: tree.root).build(outDir: out);
      final catalog = jsonDecode(result.catalogFile.readAsStringSync())
          as Map<String, dynamic>;
      final entry =
          ((catalog['widgets'] as List).single) as Map<String, dynamic>;
      expect(entry['platforms'], ['ios', 'macos']);
      // Sits right after 'tags' in the encoded entry.
      final keys = entry.keys.toList();
      expect(keys.indexOf('platforms'), keys.indexOf('tags') + 1);
    } finally {
      await out.delete(recursive: true);
      await tree.dispose();
    }
  });

  test('no platforms key when the manifest does not declare it', () async {
    final tree = await FixtureTree.create({
      'universal': null,
      'empty-platforms': {'platforms': <String>[]},
      'bad-platforms': {
        'platforms': ['ios', 42, ' '],
      },
    });
    final out = Directory('${tree.root.parent.path}/catalog-out');
    try {
      final result = CatalogBuilder(widgetsRoot: tree.root).build(outDir: out);
      final catalog = jsonDecode(result.catalogFile.readAsStringSync())
          as Map<String, dynamic>;
      final entries = {
        for (final entry
            in (catalog['widgets'] as List).cast<Map<String, dynamic>>())
          entry['id'] as String: entry,
      };
      expect(entries['universal']!.containsKey('platforms'), isFalse);
      expect(entries['empty-platforms']!.containsKey('platforms'), isFalse);
      // Defensive: non-string / blank items are dropped, not propagated.
      expect(entries['bad-platforms']!['platforms'], ['ios']);
    } finally {
      await out.delete(recursive: true);
      await tree.dispose();
    }
  });

  test('any invalid widget aborts the whole build', () async {
    final tree = await FixtureTree.create({
      'good': null,
      'bad': {'version': 'banana'},
    });
    // Unique per run: an aborted build must leave NOTHING behind, and a
    // sibling of the fixtures root could otherwise carry leftovers from
    // older runs into the assertion.
    final out = Directory(
      '${tree.root.parent.path}/should-not-exist-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await expectLater(
        () => CatalogBuilder(widgetsRoot: tree.root).build(outDir: out),
        throwsA(
          isA<CatalogBuildException>().having(
            (e) => e.errors.join(' '),
            'errors',
            contains('semver'),
          ),
        ),
      );
      expect(out.existsSync(), isFalse);
    } finally {
      await tree.dispose();
    }
  });

  test('warnings surface but do not block', () async {
    final t2 = await FixtureTree.create({
      'app': {'description': null},
    });
    Directory? outDir;
    try {
      // Rewrite the manifest without the description key entirely.
      File('${t2.root.path}/app/manifest.json').writeAsStringSync(
        '{"id":"app","name":"App","version":"1.0.0","minRuntime":"0.4.79","network":false,"allowedCommands":[]}',
      );
      outDir = Directory('${t2.root.parent.path}${p.separator}warned');
      final result = CatalogBuilder(
        widgetsRoot: t2.root,
      ).build(outDir: outDir);
      expect(result.warnings.join(' '), contains('description'));
    } finally {
      if (outDir != null && outDir.existsSync()) {
        await outDir.delete(recursive: true);
      }
      await t2.dispose();
    }
  });
}
