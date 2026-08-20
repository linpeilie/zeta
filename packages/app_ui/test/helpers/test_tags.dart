/// Canonical test tags used by package-local and workspace CI filters.
abstract final class TestTag {
  /// Static visual-regression tests run by the dedicated Linux golden job.
  static const String golden = 'golden';
}
