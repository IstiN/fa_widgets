import 'dart:io';

import 'package:fa_widgets_tool/fa_widgets_tool.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('isValidSemver', () {
    test('accepts strict X.Y.Z', () {
      expect(isValidSemver('1.0.0'), isTrue);
      expect(isValidSemver('0.4.79'), isTrue);
      expect(isValidSemver('12.3.44'), isTrue);
    });

    test('rejects loose forms', () {
      expect(isValidSemver('v1.0.0'), isFalse);
      expect(isValidSemver('1.0'), isFalse);
      expect(isValidSemver('1.0.0-beta'), isFalse);
      expect(isValidSemver('01.0.0'), isFalse);
      expect(isValidSemver(''), isFalse);
    });
  });

  group('WidgetManifest decoding', () {
    test('parses all supported fields', () {
      final manifest = WidgetManifest.decode('''
{
  "id": "calc", "name": "Calc", "version": "2.1.3",
  "description": "d", "author": "Fa",
  "tags": ["Tools", " math "],
  "minRuntime": "0.4.79", "icon": "icon.svg", "license": "MIT",
  "network": true, "allowedCommands": ["ls"],
  "unknownFutureKey": {"nested": true}
}
''');
      expect(manifest.id, 'calc');
      expect(manifest.version, '2.1.3');
      expect(manifest.tags, ['tools', 'math']);
      expect(manifest.network, isTrue);
      expect(manifest.allowedCommands, ['ls']);
      expect(manifest.minRuntime, '0.4.79');
    });

    test('non-object JSON throws ManifestException', () {
      expect(
        () => WidgetManifest.fromJson(<String>['nope']),
        throwsA(isA<ManifestException>()),
      );
      expect(() => WidgetManifest.decode('42'),
          throwsA(isA<ManifestException>()));
    });

    test('missing hard-required strings collect errors', () {
      try {
        WidgetManifest.decode('{"description": "only this"}');
        fail('should have thrown');
      } on ManifestException catch (e) {
        expect(e.errors.join(' '), contains("'id'"));
        expect(e.errors.join(' '), contains("'name'"));
        expect(e.errors.join(' '), contains("'version'"));
      }
    });
  });

  group('validateWidgetDirectory', () {
    test('a healthy widget has no errors', () async {
      final t = await FixtureTree.create({
        'good-app': null,
      });
      try {
        final result = validateWidgetDirectory(
          Directory('${t.root.path}/good-app'),
        );
        expect(result.isValid, isTrue, reason: '${result.issues}');
        expect(result.warnings, isEmpty);
      } finally {
        await t.dispose();
      }
    });

    test('id mismatch with folder name fails', () async {
      final t = await FixtureTree.create({});
      try {
        t.widgetDir('folder-name', null);
        // Manifest claims a different id than the folder name.
        File('${t.root.path}/folder-name/manifest.json').writeAsStringSync(
          '{"id":"other-id","name":"X","version":"1.0.0","minRuntime":"0.4.79","network":false,"allowedCommands":[]}',
        );
        final result = validateWidgetDirectory(
          Directory('${t.root.path}/folder-name'),
        );
        expect(result.isValid, isFalse);
        expect(result.errors.join(' '), contains('folder name'));
      } finally {
        await t.dispose();
      }
    });

    test('bad semver version fails', () async {
      final t = await FixtureTree.create({
        'app': {'version': '1.0'},
      });
      try {
        final result = validateWidgetDirectory(Directory('${t.root.path}/app'));
        expect(result.isValid, isFalse);
        expect(result.errors.join(' '), contains('semver'));
      } finally {
        await t.dispose();
      }
    });

    test('missing minRuntime fails', () async {
      final t = await FixtureTree.create({});
      try {
        final dir = t.widgetDir('app', {'minRuntime': null});
        dir; // created
        File('${t.root.path}/app/manifest.json').writeAsStringSync(
          '{"id":"app","name":"App","version":"1.0.0"}',
        );
        final result = validateWidgetDirectory(Directory('${t.root.path}/app'));
        expect(result.errors.join(' '), contains('minRuntime'));
      } finally {
        await t.dispose();
      }
    });

    test('missing widget.js entry fails', () async {
      final t = await FixtureTree.create({});
      try {
        t.widgetDir('app', null);
        File('${t.root.path}/app/widget.js').deleteSync();
        final result = validateWidgetDirectory(Directory('${t.root.path}/app'));
        expect(result.errors.join(' '), contains('widget.js'));
      } finally {
        await t.dispose();
      }
    });

    test('broken JSON collects a parse error', () async {
      final t = await FixtureTree.create({});
      try {
        t.writeBrokenManifest('app', '{not json');
        final result = validateWidgetDirectory(Directory('${t.root.path}/app'));
        expect(result.manifest, isNull);
        expect(result.errors.join(' '), contains('not valid JSON'));
      } finally {
        await t.dispose();
      }
    });

    test('missing icon file errors; absent icon warns', () async {
      final t = await FixtureTree.create({
        'app': {'icon': 'missing.svg'},
      });
      try {
        var result = validateWidgetDirectory(Directory('${t.root.path}/app'));
        expect(result.errors.join(' '), contains("icon 'missing.svg' not found"));

        final t2 = await FixtureTree.create({
          'app': {'icon': null},
        });
        try {
          // Remove icon key entirely.
          File('${t2.root.path}/app/manifest.json').writeAsStringSync(
            '{"id":"app","name":"App","version":"1.0.0","minRuntime":"0.4.79","network":false,"allowedCommands":[]}',
          );
          result = validateWidgetDirectory(Directory('${t2.root.path}/app'));
          expect(result.isValid, isTrue);
          expect(result.warnings.join(' '), contains('placeholder'));
        } finally {
          await t2.dispose();
        }
      } finally {
        await t.dispose();
      }
    });

    test('path-traversal icon is an error', () async {
      final t = await FixtureTree.create({
        'app': {'icon': '../evil.svg'},
      });
      try {
        final result = validateWidgetDirectory(Directory('${t.root.path}/app'));
        expect(result.errors.join(' '), contains('relative path inside'));
      } finally {
        await t.dispose();
      }
    });

    test('oversized widget warns but passes', () async {
      final t = await FixtureTree.create({});
      try {
        t.widgetDir('big', null);
        File(
          '${t.root.path}/big/blob.bin',
        ).writeAsBytesSync(List.filled(5 * 1024 * 1024 + 1, 120));
        final result = validateWidgetDirectory(Directory('${t.root.path}/big'));
        expect(result.isValid, isTrue);
        expect(result.warnings.join(' '), contains('weighs'));
      } finally {
        await t.dispose();
      }
    });

    test('unknown manifest key warns', () async {
      final t = await FixtureTree.create({
        'app': {'brandNewField': true},
      });
      try {
        final result = validateWidgetDirectory(Directory('${t.root.path}/app'));
        expect(result.isValid, isTrue);
        expect(result.warnings.join(' '), contains('brandNewField'));
      } finally {
        await t.dispose();
      }
    });
  });

  group('validateWidgetsRoot', () {
    test('sorts results and skips files at the root', () async {
      final t = await FixtureTree.create({'zeta': null, 'alpha': null});
      try {
        File('${t.root.path}/README.txt').writeAsStringSync('not a widget');
        final results = validateWidgetsRoot(t.root);
        expect(results, hasLength(2));
        expect(results.first.directory.path, endsWith('alpha'));
      } finally {
        await t.dispose();
      }
    });
  });
}
