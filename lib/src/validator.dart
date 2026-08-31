import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'issues.dart';
import 'manifest.dart';

/// Upper bounds producing warnings (not errors) so oversized submissions
/// still pass local validation but get flagged in review.
const sizeWarnBytes = 5 * 1024 * 1024;
const fileCountWarn = 50;

/// Platforms the Fa app targets. Values outside this set warn (not error)
/// so new platforms can roll out additively.
const knownPlatforms = <String>{
  'ios',
  'macos',
  'android',
  'windows',
  'linux',
  'web',
};

/// Result of scanning one `widgets/<id>/` directory.
final class WidgetValidation {
  WidgetValidation._(
    this.directory,
    this.manifest,
    this.errors,
    this.warnings,
    this.sourceFiles,
  );

  /// The widget directory that was scanned.
  final Directory directory;

  /// Parsed manifest, or null when it could not be parsed at all. For
  /// vendored widgets this is the MERGE of the vendor base manifest and
  /// the local overlay meta.
  final WidgetManifest? manifest;

  final List<ValidationError> errors;
  final List<ValidationWarning> warnings;

  /// The files that make up the publishable widget (zip content), as
  /// `(path-in-widget, bytes)` pairs: the widget directory's own files for
  /// LOCAL widgets, or vendor code + synthesized merged manifest + local
  /// icon for VENDORED ones. Null when validation failed before source
  /// resolution.
  final List<({String path, List<int> bytes})>? sourceFiles;

  /// True when publishing may proceed.
  bool get isValid => errors.isEmpty;

  /// All issues, errors first.
  List<ValidationIssue> get issues => [...errors, ...warnings];
}

/// Overlay keys allowed in a vendored widget's `overlay.json` — catalog
/// meta ONLY. `version`/`id`/runtime flags are single-sourced from the
/// vendor base manifest so the two repos cannot drift structurally.
const allowedOverlayKeys = <String>{
  'icon',
  'tags',
  'author',
  'minRuntime',
  'description',
};

/// Validates one widget directory against the rules in
/// `docs/schema.md`. Never throws for content problems — everything lands
/// in [WidgetValidation.errors]/[warnings]; only a missing directory throws
/// ([FileSystemException] via listSync).
///
/// A directory holding `overlay.json` instead of `manifest.json` is a
/// VENDORED widget: its code + base manifest live in
/// `vendor/js_widget_runtime/example/widgets/<id>/` (the git submodule —
/// single source of truth), while the overlay carries catalog meta
/// ([allowedOverlayKeys]). [vendorRoot] points at the submodule checkout;
/// it defaults to `../vendor/js_widget_runtime` relative to the widgets
/// root's parent when validating through [validateWidgetsRoot].
WidgetValidation validateWidgetDirectory(
  Directory dir, {
  Directory? vendorRoot,
}) {
  final errors = <ValidationError>[];
  final warnings = <ValidationWarning>[];
  final id = p.basename(dir.path);

  void error(String message) => errors.add(ValidationError('$id: $message'));

  final overlayFile = File('${dir.path}/overlay.json');
  final manifestFile = File('${dir.path}/manifest.json');
  if (overlayFile.existsSync() && manifestFile.existsSync()) {
    error(
      'both overlay.json and manifest.json present — a widget is either '
      'vendored (overlay.json, code in the submodule) or local '
      '(manifest.json + widget.js), never both',
    );
    return WidgetValidation._(dir, null, errors, warnings, null);
  }
  if (overlayFile.existsSync()) {
    return _validateVendoredWidget(dir, overlayFile, vendorRoot);
  }
  return _validateLocalWidget(dir, manifestFile);
}

/// The classic path: `manifest.json` + `widget.js` (+ assets) all live in
/// the widget directory (FA-specific and forked widgets).
WidgetValidation _validateLocalWidget(Directory dir, File manifestFile) {
  final errors = <ValidationError>[];
  final warnings = <ValidationWarning>[];
  final id = p.basename(dir.path);

  void error(String message) => errors.add(ValidationError('$id: $message'));
  void warn(String message) => warnings.add(ValidationWarning('$id: $message'));

  WidgetManifest? manifest;
  if (!manifestFile.existsSync()) {
    error('missing manifest.json (or overlay.json for a vendored widget)');
    return WidgetValidation._(dir, null, errors, warnings, null);
  }
  String manifestText;
  try {
    manifestText = manifestFile.readAsStringSync();
  } on FileSystemException catch (e) {
    error('manifest.json unreadable: ${e.message}');
    return WidgetValidation._(dir, null, errors, warnings, null);
  }
  try {
    manifest = WidgetManifest.decode(manifestText);
  } on FormatException catch (e) {
    error('manifest.json is not valid JSON: ${e.message}');
    return WidgetValidation._(dir, null, errors, warnings, null);
  } on ManifestException catch (e) {
    for (final message in e.errors) {
      error('manifest.json: $message');
    }
    return WidgetValidation._(dir, null, errors, warnings, null);
  }

  // ── id / folder identity ────────────────────────────────────────────────
  final idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,31}$');
  if (!idPattern.hasMatch(manifest.id)) {
    error(
      "manifest id '${manifest.id}' must match "
      '[a-z0-9][a-z0-9-]{1,31}',
    );
  }
  if (manifest.id != id) {
    error(
      "manifest id '${manifest.id}' must equal the folder name '$id'",
    );
  }

  // ── version ─────────────────────────────────────────────────────────────
  if (!isValidSemver(manifest.version)) {
    error("version '${manifest.version}' must be strict semver X.Y.Z");
  }

  // ── minRuntime ──────────────────────────────────────────────────────────
  _validateMinRuntime(manifest, error);

  // ── network / allowedCommands types ─────────────────────────────────────
  _validateRuntimeFlags(manifest, error);

  // ── platforms shape / known values (warnings) ───────────────────────────
  _validatePlatforms(manifest, warn);

  // ── entry + icon files ──────────────────────────────────────────────────
  final entry = File('${dir.path}/widget.js');
  if (!entry.existsSync()) {
    error('missing widget.js entry');
  } else {
    final bytes = entry.readAsBytesSync();
    if (bytes.isEmpty) {
      error('widget.js is empty');
    } else if (bytes.length > 1024 * 1024) {
      warn('widget.js larger than 1 MiB');
    }
  }
  _validateIcon(dir, manifest, error, warn);

  // ── size / file-count budget (warnings) ─────────────────────────────────
  final files = dir.listSync(recursive: true).whereType<File>().toList();
  _validateBudget(files, warn);

  // ── presence of description (warning only) ──────────────────────────────
  if (manifest.description.isEmpty) warn('no description');

  // ── unknown keys (warning; additive schema evolution) ───────────────────
  for (final key in manifest.raw.keys) {
    if (!knownManifestKeys.contains(key)) {
      warn("unknown manifest key '$key' (forward-compat: ignored by CI)");
    }
  }

  return WidgetValidation._(
    dir,
    manifest,
    errors,
    warnings,
    errors.isEmpty
        ? [
            for (final file in files)
              (
                path:
                    p.relative(file.path, from: dir.path).replaceAll('\\', '/'),
                bytes: file.readAsBytesSync(),
              ),
          ]
        : null,
  );
}

/// The vendored path: overlay meta + submodule code/manifest.
WidgetValidation _validateVendoredWidget(
  Directory dir,
  File overlayFile,
  Directory? vendorRoot,
) {
  final errors = <ValidationError>[];
  final warnings = <ValidationWarning>[];
  final id = p.basename(dir.path);

  void error(String message) => errors.add(ValidationError('$id: $message'));
  void warn(String message) => warnings.add(ValidationWarning('$id: $message'));

  // ── overlay shape ───────────────────────────────────────────────────────
  Map<String, dynamic> overlay;
  try {
    final decoded = jsonDecode(overlayFile.readAsStringSync());
    if (decoded is! Map) {
      error('overlay.json must be a JSON object');
      return WidgetValidation._(dir, null, errors, warnings, null);
    }
    overlay = decoded.cast<String, dynamic>();
  } on FormatException catch (e) {
    error('overlay.json is not valid JSON: ${e.message}');
    return WidgetValidation._(dir, null, errors, warnings, null);
  }
  for (final key in overlay.keys) {
    if (!allowedOverlayKeys.contains(key)) {
      error(
        "overlay.json key '$key' is not allowed — vendored widgets may "
        'override only ${allowedOverlayKeys.join(', ')}; version/id/runtime '
        'flags are single-sourced from the submodule manifest',
      );
    }
  }
  if (errors.isNotEmpty) {
    return WidgetValidation._(dir, null, errors, warnings, null);
  }

  // ── vendor checkout ─────────────────────────────────────────────────────
  if (vendorRoot == null) {
    error(
      'vendored widget but no vendor submodule checkout '
      '(vendor/js_widget_runtime) — run: git submodule update --init',
    );
    return WidgetValidation._(dir, null, errors, warnings, null);
  }
  final vendorDir = Directory(
    p.join(vendorRoot.path, 'example', 'widgets', id),
  );
  final baseManifestFile = File(p.join(vendorDir.path, 'manifest.json'));
  if (!baseManifestFile.existsSync()) {
    error(
      'vendor source missing: ${p.relative(baseManifestFile.path)} — '
      'run: git submodule update --init',
    );
    return WidgetValidation._(dir, null, errors, warnings, null);
  }

  // ── base manifest ───────────────────────────────────────────────────────
  // Parsed LENIENTLY (raw JSON + id check only): the runtime examples
  // legitimately lack catalog fields (minRuntime/tags) that the overlay
  // supplies — only the MERGED manifest must satisfy the full schema.
  Map<String, dynamic> baseRaw;
  try {
    final decoded = jsonDecode(baseManifestFile.readAsStringSync());
    if (decoded is! Map) {
      error('vendor manifest.json must be a JSON object');
      return WidgetValidation._(dir, null, errors, warnings, null);
    }
    baseRaw = decoded.cast<String, dynamic>();
  } on FormatException catch (e) {
    error('vendor manifest.json is not valid JSON: ${e.message}');
    return WidgetValidation._(dir, null, errors, warnings, null);
  }
  if (baseRaw['id'] != id) {
    error(
      "vendor manifest id '${baseRaw['id']}' must equal the folder name "
      "'$id'",
    );
  }

  // ── merge (overlay meta wins over the allowed keys) ─────────────────────
  final mergedRaw = <String, dynamic>{
    ...baseRaw,
    for (final key in allowedOverlayKeys)
      if (overlay[key] != null) key: overlay[key],
  };
  final manifest = WidgetManifest.fromJson(mergedRaw);

  // ── shared semantic checks on the MERGED manifest ───────────────────────
  final idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,31}$');
  if (!idPattern.hasMatch(manifest.id)) {
    error("manifest id '${manifest.id}' must match [a-z0-9][a-z0-9-]{1,31}");
  }
  if (!isValidSemver(manifest.version)) {
    error("version '${manifest.version}' must be strict semver X.Y.Z");
  }
  _validateMinRuntime(manifest, error);
  _validateRuntimeFlags(manifest, error);
  _validatePlatforms(manifest, warn);

  final entry = File(p.join(vendorDir.path, 'widget.js'));
  if (!entry.existsSync()) {
    error('vendor widget.js entry missing');
  } else {
    final bytes = entry.readAsBytesSync();
    if (bytes.isEmpty) {
      error('vendor widget.js is empty');
    } else if (bytes.length > 1024 * 1024) {
      warn('vendor widget.js larger than 1 MiB');
    }
  }
  _validateIcon(dir, manifest, error, warn);
  if (manifest.description.isEmpty) warn('no description');

  // ── publishable source: vendor files (manifest REPLACED by the merge)
  //    + the local icon ───────────────────────────────────────────────────
  final vendorFiles =
      vendorDir.listSync(recursive: true).whereType<File>().toList();
  _validateBudget(vendorFiles, warn);

  List<({String path, List<int> bytes})>? sourceFiles;
  if (errors.isEmpty) {
    sourceFiles = [
      for (final file in vendorFiles)
        if (p.basename(file.path) != 'manifest.json')
          (
            path: p
                .relative(file.path, from: vendorDir.path)
                .replaceAll('\\', '/'),
            bytes: file.readAsBytesSync(),
          ),
      (path: 'manifest.json', bytes: utf8.encode(manifest.encode())),
      if (manifest.icon.isNotEmpty &&
          File('${dir.path}/${manifest.icon}').existsSync())
        (
          path: manifest.icon,
          bytes: File('${dir.path}/${manifest.icon}').readAsBytesSync(),
        ),
    ];
  }
  return WidgetValidation._(dir, manifest, errors, warnings, sourceFiles);
}

void _validateMinRuntime(
  WidgetManifest manifest,
  void Function(String) error,
) {
  if (manifest.minRuntime.isEmpty) {
    error("missing required 'minRuntime' (js_widget_runtime floor)");
  } else if (!isValidSemver(manifest.minRuntime)) {
    error("minRuntime '${manifest.minRuntime}' must be strict semver X.Y.Z");
  }
}

void _validateRuntimeFlags(
  WidgetManifest manifest,
  void Function(String) error,
) {
  final rawNetwork = manifest.raw['network'];
  if (rawNetwork != null && rawNetwork is! bool) {
    error("'network' must be a boolean");
  }
  final rawCommands = manifest.raw['allowedCommands'];
  if (rawCommands != null && rawCommands is! List) {
    error("'allowedCommands' must be a list");
  }
}

void _validatePlatforms(
  WidgetManifest manifest,
  void Function(String) warn,
) {
  final rawPlatforms = manifest.raw['platforms'];
  if (rawPlatforms == null) return;
  if (rawPlatforms is! List) {
    warn("'platforms' must be a list of non-empty strings");
    return;
  }
  var shapeWarned = false;
  for (final platform in rawPlatforms) {
    if (platform is! String || platform.trim().isEmpty) {
      if (!shapeWarned) {
        warn("'platforms' must be a list of non-empty strings");
        shapeWarned = true;
      }
      continue;
    }
    if (!knownPlatforms.contains(platform.trim().toLowerCase())) {
      warn(
        "unknown platform '$platform' "
        '(known: ${knownPlatforms.join(', ')})',
      );
    }
  }
}

void _validateIcon(
  Directory dir,
  WidgetManifest manifest,
  void Function(String) error,
  void Function(String) warn,
) {
  final icon = manifest.icon;
  if (icon.isNotEmpty) {
    if (icon.contains('..') || icon.startsWith('/')) {
      error("icon '$icon' must be a relative path inside the widget dir");
    } else if (!File('${dir.path}/$icon').existsSync()) {
      error("icon '$icon' not found");
    }
  } else {
    warn('no icon declared — gallery will show a placeholder');
  }
}

void _validateBudget(List<File> files, void Function(String) warn) {
  var totalBytes = 0;
  for (final entity in files) {
    totalBytes += entity.lengthSync();
  }
  if (totalBytes > sizeWarnBytes) {
    warn(
      'widget weighs ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MiB '
      '(>$sizeWarnBytes limit) — consider hosting heavy assets externally',
    );
  }
  if (files.length > fileCountWarn) {
    warn('${files.length} files exceed the soft cap of $fileCountWarn');
  }
}

/// Validates every direct child directory of the widgets root.
/// Returns one [WidgetValidation] per widget folder. [vendorRoot] points
/// at the `flutter_js_widget_runtime` submodule checkout (default:
/// `../vendor/js_widget_runtime` next to the widgets root).
List<WidgetValidation> validateWidgetsRoot(
  Directory widgetsRoot, {
  Directory? vendorRoot,
}) {
  final effectiveVendorRoot = vendorRoot ??
      Directory(
        p.join(
          p.dirname(widgetsRoot.path),
          'vendor',
          'js_widget_runtime',
        ),
      );
  final results = <WidgetValidation>[];
  for (final entity in widgetsRoot.listSync().whereType<Directory>()) {
    results.add(
      validateWidgetDirectory(entity, vendorRoot: effectiveVendorRoot),
    );
  }
  return results
    ..sort(
      (WidgetValidation a, WidgetValidation b) =>
          a.directory.path.compareTo(b.directory.path),
    );
}
