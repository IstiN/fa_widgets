import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Creates a throwaway widgets root with fixture widgets.
class FixtureTree {
  FixtureTree(this.root);

  final Directory root;

  static Future<FixtureTree> create(
    Map<String, Map<String, Object?>?> widgets,
  ) async {
    final dir = await Directory.systemTemp.createTemp('faw_fixtures');
    final tree = FixtureTree(dir);
    for (final entry in widgets.entries) {
      tree.addWidget(entry.key, entry.value);
    }
    return tree;
  }

  Directory widgetDir(String id, [Map<String, Object?>? manifest]) {
    final dir = Directory(p.join(root.path, id))..createSync(recursive: true);
    File(p.join(dir.path, 'widget.js')).writeAsStringSync(
      '(function(){ jsr.render({type:"text",data:"hi"}); })();',
    );
    File(p.join(dir.path, 'icon.svg')).writeAsStringSync('<svg/>');
    // null override == healthy base manifest; a map merges on top.
    final effective = <String, Object?>{
      ..._baseManifest(id),
      ...?manifest,
    };
    File(p.join(dir.path, 'manifest.json')).writeAsStringSync(
      jsonEncode(effective),
    );
    return dir;
  }

  void addWidget(String id, Map<String, Object?>? overrides) =>
      widgetDir(id, overrides ?? _baseManifest(id));

  /// Writes a manifest as INVALID JSON (format-error fixtures).
  void writeBrokenManifest(String id, String text) {
    widgetDir(id, _baseManifest(id));
    File(
      p.join(root.path, id, 'manifest.json'),
    ).writeAsStringSync(text);
  }

  static Map<String, Object?> _baseManifest(String id) => {
    'id': id,
    'name': 'Widget $id',
    'description': 'Test widget',
    'version': '1.0.0',
    'icon': 'icon.svg',
    'minRuntime': '0.4.79',
    'network': false,
    'allowedCommands': <String>[],
  };

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

/// Extracted zip root-folder name of the first archive entry.
String firstEntryRoot(List<int> bytes) =>
    ZipDecoder().decodeBytes(bytes).files.first.name.split('/').first;

/// sha256 hex digest over [bytes].
String hexSha256(List<int> bytes) => sha256.convert(bytes).toString();
