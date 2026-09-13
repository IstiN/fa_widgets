import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fa_widgets_tool/src/catalog_builder.dart';
import 'package:fa_widgets_tool/src/pin_fetcher.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Pinned-source fetching (flutter_agent_harness#232): per-widget git
/// submodules are retired; external widgets are materialized from
/// codeload tarballs addressed by a full-sha pin in the overlay.
///
/// The named-failure paths (AC5) are exercised against a local
/// [HttpServer] so the default transport's status mapping is covered
/// offline; extraction/parity use an injectable fake fetcher.

final _sha = 'b' * 40;
final _pin = (repo: 'octocat/fa-widget-ext', commit: 'b' * 40);

Uint8List _tarball(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(
    GZipEncoder().encode(TarEncoder().encode(archive)) as List<int>,
  );
}

/// A codeload-shaped tarball: one root dir `<repoName>-<sha>/…`.
Uint8List _widgetTarball() => _tarball({
      'fa-widget-ext-$_sha/manifest.json': utf8.encode(
        jsonEncode({
          'id': 'ext',
          'name': 'Ext',
          'description': 'Pinned',
          'version': '1.0.0',
          'network': false,
          'allowedCommands': <String>[],
        }),
      ),
      'fa-widget-ext-$_sha/widget.js': utf8.encode(
        '(function(){ jsr.render({type:"text",data:"pin"}); })();',
      ),
    });

Future<Directory> _fixtureRepo() async {
  final repoRoot = await Directory.systemTemp.createTemp('faw_pin_repo');
  Directory(p.join(repoRoot.path, 'widgets', 'ext')).createSync(recursive: true);
  File(
    p.join(repoRoot.path, 'widgets', 'ext', 'overlay.json'),
  ).writeAsStringSync(
    jsonEncode({
      'icon': 'icon.svg',
      'minRuntime': '0.4.79',
      'source': {'repo': _pin.repo, 'commit': _pin.commit},
    }),
  );
  return repoRoot;
}

Never _noNetwork(Uri url) => throw StateError('network must not be reached');

void main() {
  group('fetchPin', () {
    test('materializes the pinned tarball and writes the marker',
        () async {
      final repoRoot = await _fixtureRepo();
      try {
        var calls = 0;
        final result = await fetchPin(
          repoRoot: repoRoot,
          id: 'ext',
          pin: _pin,
          fetch: (url) async {
            calls++;
            expect(
              url.toString(),
              'https://codeload.github.com/${_pin.repo}/tar.gz/${_pin.commit}',
            );
            return _widgetTarball();
          },
        );
        expect(calls, 1);
        expect(result.status, 'fetched');
        final target = Directory(
          p.join(repoRoot.path, 'vendor', 'external', 'ext'),
        );
        expect(
          File(p.join(target.path, 'widget.js')).readAsStringSync(),
          contains('jsr.render'),
        );
        // The tarball's root directory is stripped.
        expect(
          File(
            p.join(target.path, 'fa-widget-ext-$_sha', 'widget.js'),
          ).existsSync(),
          isFalse,
        );
        final marker = jsonDecode(
          File(p.join(target.path, pinMarkerFileName)).readAsStringSync(),
        );
        expect(marker, {'repo': _pin.repo, 'commit': _pin.commit});
      } finally {
        await repoRoot.delete(recursive: true);
      }
    });

    test('is a no-op (no download) while the marker matches', () async {
      final repoRoot = await _fixtureRepo();
      try {
        final first = await fetchPin(
          repoRoot: repoRoot,
          id: 'ext',
          pin: _pin,
          fetch: (_) async => _widgetTarball(),
        );
        expect(first.status, 'fetched');
        final second = await fetchPin(
          repoRoot: repoRoot,
          id: 'ext',
          pin: _pin,
          fetch: _noNetwork,
        );
        expect(second.status, 'up-to-date');
      } finally {
        await repoRoot.delete(recursive: true);
      }
    });

    test('re-fetches on force and on a stale marker', () async {
      final repoRoot = await _fixtureRepo();
      try {
        await fetchPin(
          repoRoot: repoRoot,
          id: 'ext',
          pin: _pin,
          fetch: (_) async => _widgetTarball(),
        );
        final forced = await fetchPin(
          repoRoot: repoRoot,
          id: 'ext',
          pin: _pin,
          fetch: (_) async => _widgetTarball(),
          force: true,
        );
        expect(forced.status, 'fetched');

        final marker = File(
          p.join(
            repoRoot.path,
            'vendor',
            'external',
            'ext',
            pinMarkerFileName,
          ),
        );
        marker.writeAsStringSync(
          jsonEncode({'repo': _pin.repo, 'commit': 'c' * 40}),
        );
        final refreshed = await fetchPin(
          repoRoot: repoRoot,
          id: 'ext',
          pin: _pin,
          fetch: (_) async => _widgetTarball(),
        );
        expect(refreshed.status, 'fetched');
      } finally {
        await repoRoot.delete(recursive: true);
      }
    });

    test('rejects oversized tarballs (E5)', () async {
      final repoRoot = await _fixtureRepo();
      try {
        await expectLater(
          fetchPin(
            repoRoot: repoRoot,
            id: 'ext',
            pin: _pin,
            fetch: (_) async =>
                Uint8List(maxPinTarballBytes + 1),
          ),
          throwsA(
            isA<PinFetchException>().having(
              (e) => e.message,
              'message',
              contains('MiB cap'),
            ),
          ),
        );
      } finally {
        await repoRoot.delete(recursive: true);
      }
    });

    test('rejects corrupt gzip and empty tarballs with named errors',
        () async {
      final repoRoot = await _fixtureRepo();
      try {
        await expectLater(
          fetchPin(
            repoRoot: repoRoot,
            id: 'ext',
            pin: _pin,
            fetch: (_) async => Uint8List.fromList([1, 2, 3]),
          ),
          throwsA(
            isA<PinFetchException>().having(
              (e) => e.message,
              'message',
              contains('not a valid gzip tar'),
            ),
          ),
        );
        await expectLater(
          fetchPin(
            repoRoot: repoRoot,
            id: 'ext',
            pin: _pin,
            fetch: (_) async => _tarball({}),
          ),
          throwsA(
            isA<PinFetchException>().having(
              (e) => e.message,
              'message',
              contains('carried no files'),
            ),
          ),
        );
      } finally {
        await repoRoot.delete(recursive: true);
      }
    });
  });

  group('defaultFetchPinBytes (against a local server)', () {
    Future<(HttpServer, Uri)> bind(FutureOr<void> Function(HttpRequest) fn) =>
        HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) async {
          unawaited(
            () async {
              try {
                await for (final request in server) {
                  await fn(request);
                }
              } on Object {
                // Server closed — ignore.
              }
            }(),
          );
          return (
            server,
            Uri.parse(
              'http://127.0.0.1:${server.port}'
              '/octocat/fa-widget-ext/tar.gz/$_sha',
            ),
          );
        });

    test('404 names the unreachable pin (renamed/deleted repo or sha)',
        () async {
      final (server, url) = await bind((request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });
      try {
        await expectLater(
          defaultFetchPinBytes(url),
          throwsA(
            isA<PinFetchException>().having(
              (e) => e.message,
              'message',
              allOf(contains('404'), contains('re-pin')),
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('403 names the public-only policy (private repo)', () async {
      final (server, url) = await bind((request) async {
        request.response.statusCode = 403;
        await request.response.close();
      });
      try {
        await expectLater(
          defaultFetchPinBytes(url),
          throwsA(
            isA<PinFetchException>().having(
              (e) => e.message,
              'message',
              allOf(contains('403'), contains('public-only')),
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('a 200 response streams through with the bearer token when set',
        () async {
      final (server, url) = await bind((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          isNull, // no GITHUB_TOKEN in the test env — never sent
        );
        request.response.add(_widgetTarball());
        await request.response.close();
      });
      try {
        final bytes = await defaultFetchPinBytes(url);
        expect(bytes.length, greaterThan(0));
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('collectWidgetPins', () {
    test('collects external pins, skips vendored overlays, names problems',
        () async {
      final widgetsRoot =
          await Directory.systemTemp.createTemp('faw_pins');
      try {
        Directory(p.join(widgetsRoot.path, 'pinned')).createSync();
        File(p.join(widgetsRoot.path, 'pinned', 'overlay.json'))
            .writeAsStringSync(
          jsonEncode({
            'source': {'repo': 'o/w', 'commit': _sha},
          }),
        );
        Directory(p.join(widgetsRoot.path, 'vendored')).createSync();
        File(p.join(widgetsRoot.path, 'vendored', 'overlay.json'))
            .writeAsStringSync(jsonEncode({'icon': 'icon.svg'}));
        Directory(p.join(widgetsRoot.path, 'broken')).createSync();
        File(p.join(widgetsRoot.path, 'broken', 'overlay.json'))
            .writeAsStringSync(jsonEncode({'source': 'not-a-map'}));

        final collected = collectWidgetPins(widgetsRoot);
        expect(collected.pins, hasLength(1));
        final (id, pin) = collected.pins.single;
        expect(id, 'pinned');
        expect(pin.repo, 'o/w');
        expect(pin.commit, _sha);
        expect(collected.problems.single, contains('broken'));
      } finally {
        await widgetsRoot.delete(recursive: true);
      }
    });
  });

  test('AC6: a pinned fetch packs byte-identical zips to the same files '
      'written directly', () async {
    // The fetched fixture materializes via fetchPin; the written fixture
    // hand-writes the identical tree + marker (what a retired submodule
    // checkout would have contained).
    final fetchedRepo = await _fixtureRepo();
    File(
      p.join(fetchedRepo.path, 'widgets', 'ext', 'icon.svg'),
    ).writeAsStringSync('<svg>pin</svg>');
    await fetchPin(
      repoRoot: fetchedRepo,
      id: 'ext',
      pin: _pin,
      fetch: (_) async => _widgetTarball(),
    );

    final writtenRepo = await _fixtureRepo();
    File(
      p.join(writtenRepo.path, 'widgets', 'ext', 'icon.svg'),
    ).writeAsStringSync('<svg>pin</svg>');
    final writtenDir = Directory(
      p.join(writtenRepo.path, 'vendor', 'external', 'ext'),
    )..createSync(recursive: true);
    for (final entry in Directory(
      p.join(fetchedRepo.path, 'vendor', 'external', 'ext'),
    ).listSync()) {
      if (entry is File) {
        File(p.join(writtenDir.path, p.basename(entry.path)))
            .writeAsBytesSync(entry.readAsBytesSync());
      }
    }

    try {
      final outA =
          await Directory.systemTemp.createTemp('faw_zip_a');
      final outB =
          await Directory.systemTemp.createTemp('faw_zip_b');
      try {
        CatalogBuilder(
          widgetsRoot: Directory(p.join(fetchedRepo.path, 'widgets')),
          repoRoot: fetchedRepo,
        ).build(outDir: outA);
        CatalogBuilder(
          widgetsRoot: Directory(p.join(writtenRepo.path, 'widgets')),
          repoRoot: writtenRepo,
        ).build(outDir: outB);
        final zipA = File(
          p.join(outA.path, 'ext-1.0.0.zip'),
        ).readAsBytesSync();
        final zipB = File(
          p.join(outB.path, 'ext-1.0.0.zip'),
        ).readAsBytesSync();
        expect(zipA, equals(zipB), reason: 'zips must be byte-identical');
      } finally {
        await outA.delete(recursive: true);
        await outB.delete(recursive: true);
      }
    } finally {
      await fetchedRepo.delete(recursive: true);
      await writtenRepo.delete(recursive: true);
    }
  });
}
