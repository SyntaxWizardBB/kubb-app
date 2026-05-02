import 'package:kubb_domain/src/rules/opening_rule.dart';
import 'package:meta/meta.dart';

@immutable
final class RuleSetVersion {
  const RuleSetVersion({required this.id, required this.label});

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleSetVersion && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'RuleSetVersion($id)';
}

@immutable
final class FieldSpec {
  const FieldSpec({
    this.baselineMeters = 5.0,
    this.sidelineMeters = 8.0,
  });

  final double baselineMeters;
  final double sidelineMeters;
}

@immutable
final class EquipmentSpec {
  const EquipmentSpec({
    this.kubbCount = 10,
    this.batonCount = 6,
    this.kingPresent = true,
  });

  final int kubbCount;
  final int batonCount;
  final bool kingPresent;
}

@immutable
final class ThrowValidation {
  const ThrowValidation({
    this.maxDeviationDegrees = 30.0,
    this.helicopterAllowed = false,
  });

  final double maxDeviationDegrees;
  final bool helicopterAllowed;
}

@immutable
final class RuleSet {
  const RuleSet({
    required this.version,
    required this.field,
    required this.equipment,
    required this.throwValidation,
    required this.defaultOpening,
    required this.allowedOpenings,
  });

  /// Schweizer Kubbverband v1.11 (April 2026), default opening 6-6-6.
  factory RuleSet.swiss() => RuleSet(
        version: const RuleSetVersion(
          id: 'kubb-ch-1.11',
          label: 'Schweizer Kubbverband v1.11 (April 2026)',
        ),
        field: const FieldSpec(),
        equipment: const EquipmentSpec(),
        throwValidation: const ThrowValidation(),
        defaultOpening: OpeningRule.sixSixSix(),
        allowedOpenings: [
          OpeningRule.sixSixSix(),
          OpeningRule.fourSixSix(),
          OpeningRule.threeSixSix(),
          OpeningRule.twoFourSix(),
        ],
      );

  final RuleSetVersion version;
  final FieldSpec field;
  final EquipmentSpec equipment;
  final ThrowValidation throwValidation;
  final OpeningRule defaultOpening;
  final List<OpeningRule> allowedOpenings;

  bool isOpeningAllowed(OpeningRule opening) =>
      allowedOpenings.any((o) => o.code == opening.code);
}
