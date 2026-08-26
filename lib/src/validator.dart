import 'dart:io';

import 'package:path/path.dart' as p;

import 'issues.dart';
import 'manifest.dart';

/// Upper bounds producing warnings (not errors) so oversized submissions
/// still pass local validation but get flagged in review.
const sizeWarnBytes = 5 * 1024 * 1024;
const fileCountWarn = 50;

/// Result of scanning one `widgets/<id>/` directory.
final class WidgetValidation {
  WidgetValidation._(this.directory, this.manifest, this.errors, this.warnings);

  /// The widget directory that was scanned.
  final Directory directory;

  /// Parsed manifest, or null when it could not be parsed at all.
  final WidgetManifest? manifest;

  final List<ValidationError> errors;
  final List<ValidationWarning> warnings;

  /// True when publishing may proceed.
  bool get isValid => errors.isEmpty;

  /// All issues, errors first.
  List<ValidationIssue> get issues => [...errors, ...warnings];
}

/// Validates one widget directory against the rules in
/// `docs/schema.md`. Never throws for content problems — everything lands
/// in [WidgetValidation.errors]/[warnings]; only a missing directory throws
/// ([FileSystemException] via listSync).
WidgetValidation validateWidgetDirectory(Directory dir) {
  final errors = <ValidationError>[];
  final warnings = <ValidationWarning>[];
  final id = p.basename(dir.path);

  void error(String message) => errors.add(ValidationError('$id: $message'));
  void warn(String message) => warnings.add(ValidationWarning('$id: $message'));

  WidgetManifest? manifest;
  final manifestFile = File('${dir.path}/manifest.json');
  if (!manifestFile.existsSync()) {
    error('missing manifest.json');
    return WidgetValidation._(dir, null, errors, warnings);
  }
  String manifestText;
  try {
    manifestText = manifestFile.readAsStringSync();
  } on FileSystemException catch (e) {
    error('manifest.json unreadable: ${e.message}');
    return WidgetValidation._(dir, null, errors, warnings);
  }
  try {
    manifest = WidgetManifest.decode(manifestText);
  } on FormatException catch (e) {
    error('manifest.json is not valid JSON: ${e.message}');
    return WidgetValidation._(dir, null, errors, warnings);
  } on ManifestException catch (e) {
    for (final message in e.errors) {
      error('manifest.json: $message');
    }
    return WidgetValidation._(dir, null, errors, warnings);
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
  if (manifest.minRuntime.isEmpty) {
    error("missing required 'minRuntime' (js_widget_runtime floor)");
  } else if (!isValidSemver(manifest.minRuntime)) {
    error("minRuntime '${manifest.minRuntime}' must be strict semver X.Y.Z");
  }

  // ── network / allowedCommands types ─────────────────────────────────────
  final rawNetwork = manifest.raw['network'];
  if (rawNetwork != null && rawNetwork is! bool) {
    error("'network' must be a boolean");
  }
  final rawCommands = manifest.raw['allowedCommands'];
  if (rawCommands != null && rawCommands is! List) {
    error("'allowedCommands' must be a list");
  }

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

  // ── size / file-count budget (warnings) ─────────────────────────────────
  var totalBytes = 0;
  var fileCount = 0;
  final entities = dir.listSync(recursive: true).whereType<File>();
  for (final entity in entities) {
    totalBytes += entity.lengthSync();
    fileCount++;
  }
  if (totalBytes > sizeWarnBytes) {
    warn(
      'widget weighs ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MiB '
      '(>$sizeWarnBytes limit) — consider hosting heavy assets externally',
    );
  }
  if (fileCount > fileCountWarn) {
    warn('$fileCount files exceed the soft cap of $fileCountWarn');
  }

  // ── presence of description (warning only) ──────────────────────────────
  if (manifest.description.isEmpty) warn('no description');

  // ── unknown keys (warning; additive schema evolution) ───────────────────
  for (final key in manifest.raw.keys) {
    if (!knownManifestKeys.contains(key)) {
      warn("unknown manifest key '$key' (forward-compat: ignored by CI)");
    }
  }

  return WidgetValidation._(dir, manifest, errors, warnings);
}

/// Validates every direct child directory of the widgets root.
/// Returns one [WidgetValidation] per widget folder.
List<WidgetValidation> validateWidgetsRoot(Directory widgetsRoot) {
  final results = <WidgetValidation>[];
  for (final entity in widgetsRoot.listSync().whereType<Directory>()) {
    results.add(validateWidgetDirectory(entity));
  }
  return results..sort(
    (WidgetValidation a, WidgetValidation b) =>
        a.directory.path.compareTo(b.directory.path),
  );
}
