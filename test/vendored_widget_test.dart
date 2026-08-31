import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fa_widgets_tool/src/catalog_builder.dart';
import 'package:fa_widgets_tool/src/validator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures.dart';

/// Writes a vendored (CORE) widget: `widgets/<id>/overlay.json` + local
/// icon, with the CODE + base manifest living under [vendorRoot]
/// (`example/widgets/<id>/`). Returns the overlay directory.
Directory writeVendoredWidget(
  FixtureTree tree,
  Directory vendorRoot,
  String id, {
  Map<String, Object?>? overlay,
  Map<String, Object?>? base,
  bool withOverlay = true,
  bool withLocalManifest = false,
}) {
  final vendorDir = Directory(
    p.join(vendorRoot.path, 'example', 'widgets', id),
  )..createSync(recursive: true);
  File(p.join(vendorDir.path, 'widget.js')).writeAsStringSync(
    '(function(){ jsr.render({type:"text",data:"vendored"}); })();',
  );
  File(p.join(vendorDir.path, 'manifest.json')).writeAsStringSync(
    jsonEncode({
      'id': id,
      'name': 'Vendored $id',
      'description': 'Base description',
      'version': '2.3.4',
      'network': false,
      'allowedCommands': <String>[],
      ...?base,
    }),
  );

  final dir = Directory(p.join(tree.root.path, id))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'icon.svg')).writeAsStringSync('<svg>local</svg>');
  if (withOverlay) {
    File(p.join(dir.path, 'overlay.json')).writeAsStringSync(
      jsonEncode({
        'icon': 'icon.svg',
        'tags': ['demo'],
        'author': 'Fa',
        'minRuntime': '0.4.89',
        ...?overlay,
      }),
    );
  }
  if (withLocalManifest) {
    File(p.join(dir.path, 'manifest.json')).writeAsStringSync(
      jsonEncode({'id': id, 'name': 'x', 'version': '1.0.0'}),
    );
  }
  return dir;
}

void main() {
  group('vendored (submodule-sourced) widgets', () {
    test(
      'validate merges the vendor base manifest with the overlay meta',
      () async {
        final tree = await FixtureTree.create({});
        final vendor = await Directory.systemTemp.createTemp('faw_vendor');
        writeVendoredWidget(tree, vendor, 'core-demo');

        final results = validateWidgetsRoot(
          tree.root,
          vendorRoot: vendor,
        );
        expect(results, hasLength(1));
        final result = results.single;
        expect(result.errors, isEmpty, reason: result.errors.join('\n'));
        final manifest = result.manifest!;
        // Version/id/name come from the BASE; meta from the OVERLAY.
        expect(manifest.id, 'core-demo');
        expect(manifest.version, '2.3.4');
        expect(manifest.name, 'Vendored core-demo');
        expect(manifest.tags, ['demo']);
        expect(manifest.author, 'Fa');
        expect(manifest.minRuntime, '0.4.89');
        expect(manifest.icon, 'icon.svg');
      },
    );

    test('overlay may not pin version or id (drift guard)', () async {
      final tree = await FixtureTree.create({});
      final vendor = await Directory.systemTemp.createTemp('faw_vendor');
      writeVendoredWidget(
        tree,
        vendor,
        'core-demo',
        overlay: {'version': '9.9.9'},
      );

      final result = validateWidgetsRoot(
        tree.root,
        vendorRoot: vendor,
      ).single;
      expect(result.isValid, isFalse);
      expect(
        result.errors.join('\n'),
        contains('version'),
      );
    });

    test('a vendored widget without the submodule checkout errors', () async {
      final tree = await FixtureTree.create({});
      final vendor = await Directory.systemTemp.createTemp('faw_vendor');
      writeVendoredWidget(tree, vendor, 'core-demo');
      // Point at an EMPTY vendor root.
      final empty = await Directory.systemTemp.createTemp('faw_empty');

      final result = validateWidgetsRoot(
        tree.root,
        vendorRoot: empty,
      ).single;
      expect(result.isValid, isFalse);
      expect(result.errors.join('\n'), contains('vendor'));
    });

    test('overlay.json and manifest.json together are an error', () async {
      final tree = await FixtureTree.create({});
      final vendor = await Directory.systemTemp.createTemp('faw_vendor');
      writeVendoredWidget(tree, vendor, 'core-demo', withLocalManifest: true);

      final result = validateWidgetsRoot(
        tree.root,
        vendorRoot: vendor,
      ).single;
      expect(result.isValid, isFalse);
    });

    test('build zips vendor code + merged manifest + local icon', () async {
      final tree = await FixtureTree.create({});
      final vendor = await Directory.systemTemp.createTemp('faw_vendor');
      writeVendoredWidget(tree, vendor, 'core-demo');
      final out = await Directory.systemTemp.createTemp('faw_out');

      final result = CatalogBuilder(
        widgetsRoot: tree.root,
        vendorRoot: vendor,
      ).build(outDir: out);

      expect(result.zipFiles, hasLength(1));
      final zipBytes = result.zipFiles.single.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final names = archive.files.map((f) => f.name).toList();
      expect(names, contains('core-demo/widget.js'));
      expect(names, contains('core-demo/manifest.json'));
      expect(names, contains('core-demo/icon.svg'));

      String entry(String name) => utf8.decode(
            archive.files.firstWhere((f) => f.name == name).content
                as List<int>,
          );
      // Code comes from the VENDOR tree…
      expect(entry('core-demo/widget.js'), contains('vendored'));
      // …the manifest is the MERGE (base version, overlay meta)…
      final manifest =
          jsonDecode(entry('core-demo/manifest.json')) as Map<String, dynamic>;
      expect(manifest['version'], '2.3.4');
      expect(manifest['tags'], ['demo']);
      expect(manifest['minRuntime'], '0.4.89');
      // …and the icon is the LOCAL one.
      expect(entry('core-demo/icon.svg'), '<svg>local</svg>');

      // The catalog entry mirrors the merged manifest.
      final catalog = jsonDecode(result.catalogFile.readAsStringSync())
          as Map<String, dynamic>;
      final widgetEntry =
          (catalog['widgets'] as List).single as Map<String, dynamic>;
      expect(widgetEntry['version'], '2.3.4');
      expect(widgetEntry['tags'], ['demo']);
      expect(widgetEntry['zip']['file'], 'core-demo-2.3.4.zip');
    });

    test('local widgets keep validating without a vendor root', () async {
      final tree = await FixtureTree.create({'local-demo': null});
      final results = validateWidgetsRoot(tree.root);
      expect(results.single.isValid, isTrue);
    });
  });
  group('catalog preview URLs', () {
    test(
      'vendored entries point at the runtime repo raw URLs (pinned ref)',
      () async {
        final tree = await FixtureTree.create({});
        final vendor = await Directory.systemTemp.createTemp('faw_vendor');
        writeVendoredWidget(tree, vendor, 'core-demo');
        final out = await Directory.systemTemp.createTemp('faw_out');

        final result = CatalogBuilder(
          widgetsRoot: tree.root,
          vendorRoot: vendor,
          vendorRef: 'abc1234',
        ).build(outDir: out);

        final catalog = jsonDecode(result.catalogFile.readAsStringSync())
            as Map<String, dynamic>;
        final entry =
            (catalog['widgets'] as List).single as Map<String, dynamic>;
        final preview = entry['preview'] as Map<String, dynamic>;
        expect(
          preview['manifest'],
          'https://raw.githubusercontent.com/IstiN/flutter_js_widget_runtime/'
          'abc1234/example/widgets/core-demo/manifest.json',
        );
        expect(
          preview['js'],
          'https://raw.githubusercontent.com/IstiN/flutter_js_widget_runtime/'
          'abc1234/example/widgets/core-demo/widget.js',
        );
      },
    );

    test('local entries point at the fa_widgets repo raw URLs', () async {
      final tree = await FixtureTree.create({'local-demo': null});
      final out = await Directory.systemTemp.createTemp('faw_out');

      final result = CatalogBuilder(
        widgetsRoot: tree.root,
      ).build(outDir: out);

      final catalog = jsonDecode(result.catalogFile.readAsStringSync())
          as Map<String, dynamic>;
      final entry = (catalog['widgets'] as List).single as Map<String, dynamic>;
      final preview = entry['preview'] as Map<String, dynamic>;
      expect(
        preview['manifest'],
        'https://raw.githubusercontent.com/IstiN/fa_widgets/main/'
        'widgets/local-demo/manifest.json',
      );
      expect(
        preview['js'],
        'https://raw.githubusercontent.com/IstiN/fa_widgets/main/'
        'widgets/local-demo/widget.js',
      );
    });
  });
}
