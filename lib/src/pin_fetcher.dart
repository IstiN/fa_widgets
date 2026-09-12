library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Fetches the pinned source tarball of EXTERNAL widget overlays.
///
/// Per-widget git submodules are RETIRED (flutter_agent_harness#232): a
/// widget's provenance is pure data — `overlay.json` carries
/// `source: {repo, commit}` (a full-sha pin) and this fetcher materializes
/// `https://codeload.github.com/<repo>/tar.gz/<commit>` into
/// `vendor/external/<id>/` — the same layout the retired submodules used,
/// so validation and packaging downstream are unchanged. A marker file
/// records what was fetched; re-running the fetch is a no-op while the
/// marker matches the pin.

/// sha-addressed codeload URL — immutable for a public repo (E2: a
/// force-push over a branch never moves a full-sha pin).
String pinTarballUrl({required String repo, required String commit}) =>
    'https://codeload.github.com/$repo/tar.gz/$commit';

/// Hard cap on fetched tarballs (E5: keep enormous widget repos out of
/// validation and release builds).
const maxPinTarballBytes = 16 * 1024 * 1024;

/// Marker written into the materialized directory; records which pin the
/// content came from so stale checkouts are detectable.
const pinMarkerFileName = '.jsr-pin.json';

/// The pin a materialized directory was fetched for.
typedef Pin = ({String repo, String commit});

/// Downloads the pinned tarball bytes. Injectable for tests and for
/// offline/alternative transports.
typedef PinBytesFetcher = Future<Uint8List> Function(Uri url);

/// A named fetch failure — always rendered as a readable single-line
/// message (never a stack dump; AC5).
class PinFetchException implements Exception {
  PinFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One widget's fetch outcome.
class PinFetchResult {
  PinFetchResult({required this.id, required this.status, required this.pin});

  /// `fetched` (tarball downloaded + extracted) or `up-to-date`
  /// (marker already matches the pin).
  final String status;
  final String id;
  final Pin pin;
}

/// Default transport: codeload over https. `GITHUB_TOKEN` (or
/// `JSR_GITHUB_TOKEN`) is sent as a bearer token when present — public
/// tarballs need no auth, but CI rate limits (E3) are friendlier with one.
Future<Uint8List> defaultFetchPinBytes(Uri url) async {
  final client = HttpClient()..autoUncompress = false;
  try {
    final token = Platform.environment['GITHUB_TOKEN'] ??
        Platform.environment['JSR_GITHUB_TOKEN'];
    final request = await client.getUrl(url);
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    final status = response.statusCode;
    if (status == 404) {
      throw PinFetchException(
        'pinned source unreachable (404): $url — repo renamed/deleted or '
        'the pinned commit no longer exists; re-pin the widget and update '
        'the overlay',
      );
    }
    if (status == 401 || status == 403) {
      throw PinFetchException(
        'pinned source rejected ($status): $url — private repos are not '
        'supported (publishing is public-only)',
      );
    }
    if (status != 200) {
      throw PinFetchException(
        'pinned source fetch failed (HTTP $status): $url',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > maxPinTarballBytes) {
        throw PinFetchException(
          'pinned tarball exceeds the '
          '${maxPinTarballBytes ~/ (1024 * 1024)} MiB cap: $url',
        );
      }
    }
    return builder.toBytes();
  } on SocketException catch (e) {
    throw PinFetchException('pinned source unreachable: $url ($e)');
  } finally {
    client.close(force: true);
  }
}

/// Materializes the pinned tarball into `vendor/external/<id>/` unless the
/// pin marker already matches (or [force]).
Future<PinFetchResult> fetchPin({
  required Directory repoRoot,
  required String id,
  required Pin pin,
  PinBytesFetcher fetch = defaultFetchPinBytes,
  bool force = false,
}) async {
  final target = Directory(p.join(repoRoot.path, 'vendor', 'external', id));
  final marker = File(p.join(target.path, pinMarkerFileName));
  if (!force && marker.existsSync()) {
    final recorded = decodePinMarker(marker);
    if (recorded != null && recorded == pin) {
      return PinFetchResult(id: id, status: 'up-to-date', pin: pin);
    }
  }

  final url = pinTarballUrl(repo: pin.repo, commit: pin.commit);
  final bytes = await fetch(Uri.parse(url));
  if (bytes.length > maxPinTarballBytes) {
    throw PinFetchException(
      'pinned tarball exceeds the '
      '${maxPinTarballBytes ~/ (1024 * 1024)} MiB cap: $url',
    );
  }
  _extractTarball(bytes, target, url);
  marker.parent.createSync(recursive: true);
  marker.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'repo': pin.repo, 'commit': pin.commit}),
  );
  return PinFetchResult(id: id, status: 'fetched', pin: pin);
}

/// Extracts a codeload tarball ([gzip] + tar, single root directory
/// `<repoName>-<sha>/`) into [target], replacing any previous content.
void _extractTarball(Uint8List bytes, Directory target, String url) {
  final Archive archive;
  try {
    archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  } on FormatException catch (e) {
    throw PinFetchException('pinned tarball is not a valid gzip tar: $url ($e)');
  }

  var files = 0;
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final segments = p.split(entry.name);
    // Strip the tarball's single root directory; skip stray git/pax noise.
    if (segments.length <= 1) continue;
    final relative = segments.sublist(1);
    if (relative.any((s) => s == '.git' || s.startsWith('PaxHeader'))) {
      continue;
    }
    final file = File(p.join(target.path, p.joinAll(relative)));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.content as List<int>);
    files++;
  }
  if (files == 0) {
    throw PinFetchException(
      'pinned tarball carried no files: $url — refusing to materialize '
      'an empty widget source',
    );
  }
}

/// Reads a marker file; null when absent/malformed (a hand-placed
/// directory without a marker is treated as NOT materialized).
Pin? decodePinMarker(File marker) {
  final decoded = jsonDecode(marker.readAsStringSync());
  if (decoded is! Map) return null;
  final repo = decoded['repo'];
  final commit = decoded['commit'];
  if (repo is! String || commit is! String) return null;
  return (repo: repo, commit: commit);
}

/// Scans a widgets root for overlays carrying a `source` pin. Vendored
/// overlays (no `source`) are skipped. Malformed pins come back as
/// problems with widget ids so the CLI can fail with named errors.
({List<(String, Pin)> pins, List<String> problems}) collectWidgetPins(
  Directory widgetsRoot,
) {
  final pins = <(String, Pin)>[];
  final problems = <String>[];
  for (final dir in widgetsRoot.listSync().whereType<Directory>()) {
    final overlayFile = File(p.join(dir.path, 'overlay.json'));
    if (!overlayFile.existsSync()) continue;
    final id = p.basename(dir.path);
    final Object? decoded;
    try {
      decoded = jsonDecode(overlayFile.readAsStringSync());
    } on FormatException catch (e) {
      problems.add('$id: overlay.json is not valid JSON (${e.message})');
      continue;
    }
    if (decoded is! Map) {
      problems.add('$id: overlay.json must be a JSON object');
      continue;
    }
    final source = decoded['source'];
    if (source == null) continue; // vendored widget — nothing to fetch
    if (source is! Map) {
      problems.add(
        "$id: overlay 'source' must be an object: "
        '{"repo": "owner/name", "commit": "<40-hex sha>"}',
      );
      continue;
    }
    final repo = source['repo'];
    final commit = source['commit'];
    if (repo is! String || repo.isEmpty || commit is! String || commit.isEmpty) {
      problems.add(
        "$id: overlay 'source' needs string 'repo' and 'commit' fields",
      );
      continue;
    }
    pins.add((id, (repo: repo, commit: commit)));
  }
  return (pins: pins, problems: problems);
}
