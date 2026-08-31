import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:fa_widgets_tool/fa_widgets_tool.dart';

/// Exit codes: 0 ok, 1 validation/build failure, 2 usage error.
const _exitOk = 0;
const _exitFail = 1;
const _exitUsage = 2;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addCommand(
      'validate',
      ArgParser()
        ..addOption(
          'root',
          abbr: 'r',
          defaultsTo: 'widgets',
          help: 'Path to the widgets root directory.',
        ),
    )
    ..addCommand(
      'catalog',
      ArgParser()
        ..addOption(
          'root',
          abbr: 'r',
          defaultsTo: 'widgets',
          help: 'Path to the widgets root directory.',
        )
        ..addOption(
          'out',
          abbr: 'o',
          defaultsTo: 'build/catalog',
          help: 'Output directory for catalog.json and zips.',
        ),
    )
    ..addCommand(
      'diff-tags',
      ArgParser()
        ..addOption(
          'previous',
          abbr: 'p',
          help: 'Path to the currently published catalog.json '
              '(missing or unreadable = nothing published yet).',
        )
        ..addOption(
          'current',
          abbr: 'c',
          help: 'Path to the freshly built catalog.json.',
        ),
    );

  ArgResults parsed;
  try {
    parsed = parser.parse(arguments);
  } on ArgParserException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exit(_exitUsage);
  }

  switch (parsed.command?.name) {
    case 'validate':
      exit(_runValidate(parsed.command!));
    case 'catalog':
      exit(_runCatalog(parsed.command!));
    case 'diff-tags':
      exit(_runDiffTags(parsed.command!));
    default:
      stderr.writeln(
        'usage: dart run bin/fa_widgets.dart <validate|catalog> [options]\n'
        '${parser.usage}',
      );
      exit(_exitUsage);
  }
}

int _runValidate(ArgResults command) {
  final root = Directory(command['root'] as String);
  if (!root.existsSync()) {
    stderr.writeln('widgets root not found: ${root.path}');
    return _exitFail;
  }
  var hadErrors = false;
  var count = 0;
  for (final result in validateWidgetsRoot(root)) {
    count++;
    for (final issue in result.issues) {
      final isError = issue is ValidationError;
      stderr.writeln('${isError ? "ERROR" : "warn "} $issue');
      if (isError) hadErrors = true;
    }
  }
  stderr.writeln('$count widget(s) checked');
  stderr.writeln(hadErrors ? 'INVALID' : 'OK');
  return hadErrors ? _exitFail : _exitOk;
}

/// The git ref the vendor submodule is pinned at — preview URLs for
/// vendored widgets point at exactly this revision of the runtime repo.
/// Falls back to `main` when the submodule is not initialized (validation
/// fails loudly for vendored widgets in that case anyway).
String _resolveVendorRef() {
  try {
    final result = Process.runSync(
      'git',
      ['-C', 'vendor/js_widget_runtime', 'rev-parse', 'HEAD'],
    );
    if (result.exitCode == 0) {
      final ref = (result.stdout as String).trim();
      if (ref.isNotEmpty) return ref;
    }
  } on ProcessException {
    // git not available — fall through.
  }
  return 'main';
}

int _runCatalog(ArgResults command) {
  final root = Directory(command['root'] as String);
  final out = Directory(command['out'] as String);
  try {
    final result = CatalogBuilder(
      widgetsRoot: root,
      vendorRef: _resolveVendorRef(),
    ).build(outDir: out);
    for (final warning in result.warnings) {
      stderr.writeln('warn  $warning');
    }
    stderr.writeln('catalog: ${result.catalogFile.path}');
    for (final zip in result.zipFiles) {
      stderr.writeln('  ${p.basename(zip.path)} (${zip.lengthSync()} bytes)');
    }
    return _exitOk;
  } on CatalogBuildException catch (e) {
    stderr.write('$e\n');
    return _exitFail;
  }
}

/// Prints `<id> <version>` lines for widgets that are new or version-bumped
/// against the published catalog (stdout, one line per tag to cut). Always
/// exits 0 — an empty output means "nothing changed". Missing `--current`
/// is a usage error.
int _runDiffTags(ArgResults command) {
  final currentPath = command['current'] as String?;
  if (currentPath == null || currentPath.isEmpty) {
    stderr.writeln('--current is required');
    return _exitUsage;
  }

  Map<String, dynamic>? readCatalog(String? path) {
    if (path == null) return null;
    try {
      final text = File(path).readAsStringSync();
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      // Missing/malformed previous catalog = first publish or GH hiccup.
      return null;
    }
  }

  final current = readCatalog(currentPath);
  if (current == null) {
    stderr.writeln('current catalog unreadable: ${command['current']}');
    return _exitFail;
  }
  final previous = readCatalog(command['previous'] as String?);
  for (final change in diffTagChanges(previous, current)) {
    stdout.writeln('${change.id} ${change.version}');
  }
  return _exitOk;
}
