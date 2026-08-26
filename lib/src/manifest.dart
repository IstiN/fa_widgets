import 'dart:convert';

import 'issues.dart';

/// Keys this tool understands. Anything else parses but yields a
/// [ValidationWarning] so new fields can ship additively without breaking
/// older tooling.
const knownManifestKeys = <String>{
  // runtime (consumed by the Fa app)
  'id', 'name', 'description', 'version', 'icon',
  'network', 'allowedCommands', 'cli', 'widget',
  'platforms', 'chrome',
  // service permission gates — default denied regardless
  'llm', 'homekit', 'health', 'contacts', 'calendar',
  'microphone', 'notifications', 'media', 'keys',
  // catalog metadata
  'author', 'tags', 'minRuntime', 'license',
};

/// A parsed `widgets/<id>/manifest.json`. See `docs/schema.md`.
final class WidgetManifest {
  WidgetManifest._(
    this.raw, {
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.tags,
    required this.minRuntime,
    required this.icon,
    required this.license,
    required this.network,
    required this.allowedCommands,
  });

  /// Builds from decoded JSON. Throws [ManifestException] when the JSON is
  /// not an object or when `id`/`name`/`version` are structurally broken
  /// (semantic rules live in the [validateWidgetDirectory] step instead so
  /// every problem surfaces together).
  factory WidgetManifest.fromJson(Object? json) {
    final errors = <String>[];
    if (json is! Map) {
      throw ManifestException(['manifest must be a JSON object']);
    }
    String stringField(String key, {bool required_ = true}) {
      final value = json[key];
      if (value == null && !required_) return '';
      if (value is! String || value.trim().isEmpty) {
        if (required_) {
          errors.add("'$key' must be a non-empty string");
          return '';
        }
        return '';
      }
      return value.trim();
    }

    final id = stringField('id');
    final name = stringField('name');
    final version = stringField('version');

    final descriptionValue = json['description'];
    final description = descriptionValue is String ? descriptionValue.trim() : '';

    final authorValue = json['author'];
    final author = authorValue is String ? authorValue.trim() : '';

    final tags = <String>[];
    final tagsValue = json['tags'];
    if (tagsValue != null) {
      if (tagsValue is List) {
        tags.addAll([
          for (final tag in tagsValue)
            if (tag is String && tag.trim().isNotEmpty) tag.trim().toLowerCase(),
        ]);
      } else {
        errors.add("'tags' must be a list of strings");
      }
    }

    final minRuntime = stringField('minRuntime');

    final iconValue = json['icon'];
    final icon = iconValue is String ? iconValue.trim() : '';

    final licenseValue = json['license'];
    final license = licenseValue is String ? licenseValue.trim() : '';

    final networkValue = json['network'];

    final allowedCommands = <String>[];
    final commandsValue = json['allowedCommands'];
    if (commandsValue != null) {
      if (commandsValue is List) {
        allowedCommands.addAll([
          for (final command in commandsValue)
            if (command is String) command,
        ]);
      } else {
        errors.add("'allowedCommands' must be a list of strings");
      }
    }

    if (errors.isNotEmpty) throw ManifestException(errors);

    return WidgetManifest._(
      Map<String, dynamic>.from(json),
      id: id,
      name: name,
      version: version,
      description: description,
      author: author,
      tags: List.unmodifiable(tags),
      minRuntime: minRuntime,
      icon: icon,
      license: license,
      network: networkValue == true,
      allowedCommands: List.unmodifiable(allowedCommands),
    );
  }

  /// The raw decoded manifest (all keys, including unknown ones).
  final Map<String, dynamic> raw;

  final String id;
  final String name;
  final String version;

  /// Empty when absent — a warning at validation time.
  final String description;

  /// Empty when absent.
  final String author;

  /// Lowercased, trimmed. Empty when absent.
  final List<String> tags;

  /// Minimum `js_widget_runtime` version, e.g. `0.4.79`. May be empty when
  /// missing — an error at validation time.
  final String minRuntime;

  /// Icon path relative to the widget directory; empty when absent.
  final String icon;

  /// Defaults to the repo MIT when empty.
  final String license;

  /// `network: true|false` — false when absent/non-boolean.
  final bool network;

  /// Shell command allowlist (`jsr.exec`); empty when absent.
  final List<String> allowedCommands;

  /// Decodes [text] as JSON and constructs the manifest.
  factory WidgetManifest.decode(String text) =>
      WidgetManifest.fromJson(jsonDecode(text));

  /// Encodes back to a JSON string (stable formatting: no spaces).
  String encode() => jsonEncode(raw);
}
