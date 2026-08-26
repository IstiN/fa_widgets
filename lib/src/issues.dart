/// Problem types shared by validation and building.
library;

/// A problem found while inspecting the widget tree.
///
/// [ValidationError] blocks publishing; [ValidationWarning] does not
/// (forward compatibility / advice only).
sealed class ValidationIssue {
  ValidationIssue(this.message);

  /// Human-readable description, prefixed with the widget directory.
  final String message;

  @override
  String toString() => message;
}

final class ValidationError extends ValidationIssue {
  ValidationError(super.message);
}

final class ValidationWarning extends ValidationIssue {
  ValidationWarning(super.message);
}

/// Thrown when parsing a manifest fails structurally (not valid JSON object
/// or a hard-required field is unusable).
final class ManifestException implements Exception {
  ManifestException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'ManifestException: ${errors.join('; ')}';
}

/// The strict semver subset accepted for widget versions: `X.Y.Z`.
final RegExp _semverRegExp = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
);

/// Whether [value] is a strict `X.Y.Z` semver string.
bool isValidSemver(String value) => _semverRegExp.hasMatch(value);
