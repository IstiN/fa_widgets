import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fa_widgets_tool/src/catalog_builder.dart';
import 'package:fa_widgets_tool/src/pin_fetcher.dart';
import 'package:fa_widgets_tool/src/validator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// EXTERNAL (user-repo pinned) widgets: `widgets/<id>/overlay.json` with a
/// `source: {repo, commit}` block; the code is materialized into
/// `vendor/external/<id>/` by `fa_widgets fetch` from the pinned codeload
/// tarball (per-widget git submodules are RETIRED,
/// flutter_agent_harness#232).
///
/// Fixtures write the materialized files plus the `.jsr-pin.json` marker
/// directly — no git machinery needed anymore (the validator compares the
/// marker against the overlay pin).

/// The sha used by default for both the overlay pin and the marker.
final _defaultSha = 'a' * 40;

/// The pieces of an external-widget fixture.
typedef ExternalFixture = ({
  Directory repoRoot,
  Directory widgetsRoot,
  Directory submoduleDir,
  String head,
});

/// Builds an external-widget fixture: a fake catalog repo root holding
/// `widgets/<id>/overlay.json` + local icon and, unless [materialize] is
/// false, the fetched tree at `vendor/external/<id>/` (files + a
/// `.jsr-pin.json` marker recording [pinRepo]@[pinCommit]). The root
/// `.gitmodules` carries ONLY the frozen runtime section.
Future<ExternalFixture> writeExternalWidget(
  String id, {
  Map<String, Object?>? overlay,
  Map<String, Object?>? manifest,
  String? pinRepo,
  String? pinCommit,
  bool materialize = true,
  bool withMarker = true,
  bool withEntry = true,
  bool withGitmodules = true,
}) async {
  final repoRoot = await Directory.systemTemp.createTemp('faw_ext_repo');
  final widgetsRoot = Directory(p.join(repoRoot.path, 'widgets'))
    ..createSync();
  final widgetDir = Directory(p.join(widgetsRoot.path, id))..createSync();
  File(p.join(widgetDir.path, 'icon.svg')).writeAsStringSync('<svg>ext</svg>');

  final repo = pinRepo ?? 'octocat/fa-widget-$id';
  final commit = pinCommit ?? _defaultSha;
  final submoduleDir = Directory(
    p.join(repoRoot.path, 'vendor', 'external', id),
  );
  if (materialize) {
    submoduleDir.createSync(recursive: true);
    File(p.join(submoduleDir.path, 'manifest.json')).writeAsStringSync(
      jsonEncode({
        'id': id,
        'name': 'External $id',
        'description': 'From my own repo',
        'version': '3.1.4',
        'network': false,
        'allowedCommands': <String>[],
        ...?manifest,
      }),
    );
    if (withEntry) {
      File(p.join(submoduleDir.path, 'widget.js')).writeAsStringSync(
        '(function(){ jsr.render({type:"text",data:"external"}); })();',
      );
    }
    if (withMarker) {
      File(
        p.join(submoduleDir.path, pinMarkerFileName),
      ).writeAsStringSync(jsonEncode({'repo': repo, 'commit': commit}));
    }
  }

  if (withGitmodules) {
    // The frozen contract: only the runtime submodule is registered.
    File(p.join(repoRoot.path, '.gitmodules')).writeAsStringSync(
      '[submodule "vendor/js_widget_runtime"]\n'
      '\tpath = vendor/js_widget_runtime\n'
      '\turl = https://github.com/IstiN/flutter_js_widget_runtime.git\n',
    );
  }

  File(p.join(widgetDir.path, 'overlay.json')).writeAsStringSync(
    jsonEncode({
      'icon': 'icon.svg',
      'tags': ['demo'],
      'author': 'Octocat',
      'minRuntime': '0.4.89',
      'source': {'repo': repo, 'commit': commit},
      ...?overlay,
    }),
  );
  return (
    repoRoot: repoRoot,
    widgetsRoot: widgetsRoot,
    submoduleDir: submoduleDir,
    head: commit,
  );
}

void main() {
  group('external (user-repo pinned) widgets', () {
    test(
      'a valid external widget validates; version comes from its own repo',
      () async {
        final fixture = await writeExternalWidget('ext-demo');
        try {
          final result =
              validateWidgetsRoot(fixture.widgetsRoot).single;
          expect(result.errors, isEmpty, reason: result.errors.join('\n'));
          final manifest = result.manifest!;
          // Version/id/name from the SUBMODULE manifest, meta from overlay.
          expect(manifest.id, 'ext-demo');
          expect(manifest.version, '3.1.4');
          expect(manifest.name, 'External ext-demo');
          expect(manifest.tags, ['demo']);
          expect(manifest.author, 'Octocat');
          expect(manifest.minRuntime, '0.4.89');
          expect(
            result.externalSource!.repo,
            'octocat/fa-widget-ext-demo',
          );
          expect(result.externalSource!.commit, fixture.head);
        } finally {
          await fixture.repoRoot.delete(recursive: true);
        }
      },
    );

    test('drift (overlay pin != materialized marker) fails', () async {
      final fixture = await writeExternalWidget(
        'ext-demo',
        overlay: {
          'source': {
            'repo': 'octocat/fa-widget-ext-demo',
            'commit': '1' * 40,
          },
        },
      );
      try {
        final result = validateWidgetsRoot(fixture.widgetsRoot).single;
        expect(result.isValid, isFalse);
        expect(result.errors.join('\n'), contains('(stale)'));
        expect(result.errors.join('\n'), contains(fixture.head));
      } finally {
        await fixture.repoRoot.delete(recursive: true);
      }
    });

    test(
      'an unmaterialized pin errors with the fetch hint',
      () async {
        final fixture = await writeExternalWidget(
          'ext-demo',
          materialize: false,
        );
        try {
          final result = validateWidgetsRoot(fixture.widgetsRoot).single;
          expect(result.isValid, isFalse);
          expect(
            result.errors.join('\n'),
            contains('external source not materialized'),
          );
          expect(
            result.errors.join('\n'),
            contains('dart run bin/fa_widgets.dart fetch'),
          );
        } finally {
          await fixture.repoRoot.delete(recursive: true);
        }
      },
    );

    test(
      'a hand-placed directory without a pin marker errors with the hint',
      () async {
        final fixture = await writeExternalWidget(
          'ext-demo',
          withMarker: false,
        );
        try {
          final result = validateWidgetsRoot(fixture.widgetsRoot).single;
          expect(result.isValid, isFalse);
          expect(
            result.errors.join('\n'),
            contains('has no $pinMarkerFileName'),
          );
          expect(
            result.errors.join('\n'),
            contains('dart run bin/fa_widgets.dart fetch'),
          );
        } finally {
          await fixture.repoRoot.delete(recursive: true);
        }
      },
    );

    test('a malformed source.commit fails', () async {
      final fixture = await writeExternalWidget(
        'ext-demo',
        overlay: {
          'source': {'repo': 'octocat/fa-widget-ext-demo', 'commit': 'abc123'},
        },
      );
      try {
        final result = validateWidgetsRoot(fixture.widgetsRoot).single;
        expect(result.isValid, isFalse);
        expect(result.errors.join('\n'), contains('source.commit'));
      } finally {
        await fixture.repoRoot.delete(recursive: true);
      }
    });

    test('an overlay with forbidden keys still fails (source or not)',
        () async {
      final fixture = await writeExternalWidget(
        'ext-demo',
        overlay: {'version': '9.9.9'},
      );
      try {
        final result = validateWidgetsRoot(fixture.widgetsRoot).single;
        expect(result.isValid, isFalse);
        expect(result.errors.join('\n'), contains('not allowed'));
        expect(result.errors.join('\n'), contains('version'));
      } finally {
        await fixture.repoRoot.delete(recursive: true);
      }
    });

    test('a missing .gitmodules file is fine (pins-only catalog)', () async {
      final fixture = await writeExternalWidget(
        'ext-demo',
        withGitmodules: false,
      );
      try {
        final result = validateWidgetsRoot(fixture.widgetsRoot).single;
        expect(result.errors, isEmpty, reason: result.errors.join('\n'));
      } finally {
        await fixture.repoRoot.delete(recursive: true);
      }
    });

    test('a foreign .gitmodules section fails (frozen contract)', () async {
      final fixture = await writeExternalWidget('ext-demo');
      try {
        final gitmodules = File(
          p.join(fixture.repoRoot.path, '.gitmodules'),
        );
        gitmodules.writeAsStringSync(
          '${gitmodules.readAsStringSync()}\n'
          '[submodule "vendor/external/legacy-widget"]\n'
          '\tpath = vendor/external/legacy-widget\n'
          '\turl = https://github.com/octocat/legacy-widget.git\n',
        );
        final results = validateWidgetsRoot(fixture.widgetsRoot);
        expect(
          [for (final r in results) ...r.errors].join('\n'),
          contains('per-widget git submodules are RETIRED'),
        );
      } finally {
        await fixture.repoRoot.delete(recursive: true);
      }
    });

    test(
      'the manifest-declared widget entry substitutes a missing widget.js',
      () async {
        final fixture = await writeExternalWidget(
          'ext-demo',
          withEntry: false,
          manifest: {
            'widget': {'entry': 'tile.js', 'size': '2x2'},
          },
        );
        try {
          File(p.join(fixture.submoduleDir.path, 'tile.js'))
              .writeAsStringSync(
            '(function(){ jsr.render({type:"text",data:"tile"}); })();',
          );
          // Adding the entry does not move the pin: the marker already
          // matches the fixture overlay's default pin.
          final result = validateWidgetsRoot(fixture.widgetsRoot).single;
          expect(result.errors, isEmpty, reason: result.errors.join('\n'));
        } finally {
          await fixture.repoRoot.delete(recursive: true);
        }
      },
    );

    test('no widget.js and no declared entry fails', () async {
      final fixture = await writeExternalWidget('ext-demo', withEntry: false);
      try {
        final result = validateWidgetsRoot(fixture.widgetsRoot).single;
        expect(result.isValid, isFalse);
        expect(result.errors.join('\n'), contains('no entry'));
      } finally {
        await fixture.repoRoot.delete(recursive: true);
      }
    });

    test(
      'build packs the zip from the submodule and carries source through',
      () async {
        final fixture = await writeExternalWidget('ext-demo');
        final out = await Directory.systemTemp.createTemp('faw_ext_out');
        try {
          final result = CatalogBuilder(
            widgetsRoot: fixture.widgetsRoot,
          ).build(outDir: out);

          expect(result.zipFiles, hasLength(1));
          expect(
            p.basename(result.zipFiles.single.path),
            'ext-demo-3.1.4.zip',
          );
          final archive =
              ZipDecoder().decodeBytes(result.zipFiles.single.readAsBytesSync());
          final names = archive.files.map((f) => f.name).toList();
          expect(names, contains('ext-demo/widget.js'));
          expect(names, contains('ext-demo/manifest.json'));
          expect(names, contains('ext-demo/icon.svg'));
          // Git internals never leak into the zip.
          expect(names.any((n) => n.contains('.git')), isFalse);

          String entry(String name) => utf8.decode(
                archive.files.firstWhere((f) => f.name == name).content
                    as List<int>,
              );
          expect(entry('ext-demo/widget.js'), contains('external'));
          final manifest = jsonDecode(entry('ext-demo/manifest.json'))
              as Map<String, dynamic>;
          expect(manifest['version'], '3.1.4');
          expect(manifest['minRuntime'], '0.4.89');
          expect(entry('ext-demo/icon.svg'), '<svg>ext</svg>');

          // The catalog entry carries source through and preview URLs point
          // at the user repo pinned at the exact commit.
          final catalog = jsonDecode(result.catalogFile.readAsStringSync())
              as Map<String, dynamic>;
          final widgetEntry =
              (catalog['widgets'] as List).single as Map<String, dynamic>;
          expect(widgetEntry['version'], '3.1.4');
          expect(widgetEntry['source'], {
            'repo': 'octocat/fa-widget-ext-demo',
            'commit': fixture.head,
          });
          final preview = widgetEntry['preview'] as Map<String, dynamic>;
          expect(
            preview['manifest'],
            'https://raw.githubusercontent.com/octocat/fa-widget-ext-demo/'
            '${fixture.head}/manifest.json',
          );
          expect(
            preview['js'],
            'https://raw.githubusercontent.com/octocat/fa-widget-ext-demo/'
            '${fixture.head}/widget.js',
          );
        } finally {
          await fixture.repoRoot.delete(recursive: true);
          await out.delete(recursive: true);
        }
      },
    );
  });

  test(
    'an overlay without minRuntime reports a readable error (no crash)',
    () async {
      // Regression: WidgetManifest.fromJson threw ManifestException outside
      // the validator's try/catch — CI failed with a stack trace (exit 255)
      // instead of a reviewable ERROR. The overlay omits `minRuntime` and
      // the submodule manifest does not supply one either, so the merged
      // manifest cannot satisfy the hard-required field.
      final fixture = await writeExternalWidget(
        'ext-demo',
        overlay: {'minRuntime': null},
      );
      try {
        final result = validateWidgetsRoot(fixture.widgetsRoot).single;
        expect(result.isValid, isFalse);
        expect(result.errors.join('\n'), contains('minRuntime'));
      } finally {
        await fixture.repoRoot.delete(recursive: true);
      }
    },
  );

  test(
    'a foreign .gitmodules section is an ERROR, runtime section is fine',
    () async {
      final fixture = await writeExternalWidget('ext-demo');
      try {
        final gitmodules = File(
          p.join(fixture.repoRoot.path, '.gitmodules'),
        );
        gitmodules.writeAsStringSync(
          '${gitmodules.readAsStringSync()}\n'
          '[submodule "vendor/external/e2e-scratch"]\n'
          '\tpath = vendor/external/e2e-scratch\n'
          '\turl = https://github.com/octocat/fa-widget-e2e-scratch.git\n',
        );

        final results = validateWidgetsRoot(fixture.widgetsRoot);
        expect(
          [for (final r in results) ...r.errors].join('\n'),
          allOf(
            contains('RETIRED'),
            contains('vendor/external/e2e-scratch'),
          ),
        );
        // The real widget itself stays valid.
        expect(
          results
              .where((r) => r.directory.path.endsWith('ext-demo'))
              .single
              .errors,
          isEmpty,
        );
      } finally {
        await fixture.repoRoot.delete(recursive: true);
      }
    },
  );
}
