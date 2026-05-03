/// One CSV row for the export. Sniper-only fields are null on finisseur rows
/// and vice versa.
class ExportRow {
  ExportRow({
    required this.sessionId,
    required this.mode,
    required this.startedAt,
    required this.hits,
    required this.misses,
    required this.helis,
    this.completedAt,
    this.distanceM,
    this.throwTarget,
    this.finField,
    this.finBase,
    this.sticksUsed,
    this.success,
    this.kingHit,
  });

  final String sessionId;
  final String mode;
  final DateTime startedAt;
  final DateTime? completedAt;
  final double? distanceM;
  final int? throwTarget;
  final int hits;
  final int misses;
  final int helis;
  final int? finField;
  final int? finBase;
  final int? sticksUsed;
  final bool? success;
  final bool? kingHit;

  int? get durationSeconds {
    final end = completedAt;
    if (end == null) return null;
    return end.difference(startedAt).inSeconds;
  }
}
