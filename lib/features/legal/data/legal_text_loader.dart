import 'package:flutter/services.dart' show rootBundle;

/// Lade-Routinen fuer statische Rechtstexte (DSGVO Art. 13/14).
///
/// Markdown liegt als gepacktes Asset im `docs/legal/`-Pfad — siehe
/// pubspec.yaml. Die App rendert mit einem eigenen Mini-Renderer im
/// `presentation`-Layer; `flutter_markdown` ist bewusst nicht im Stack
/// (siehe Sprint-C-Briefing). Loader bleibt deshalb ein reiner String-
/// Read und kennt keine Markdown-AST-Strukturen.
const String _privacyPolicyDeAsset = 'docs/legal/privacy-policy-de.md';
const String _imprintDeAsset = 'docs/legal/imprint-de.md';

/// Liest die deutsche Datenschutzerklaerung aus dem Asset-Bundle.
///
/// Wirft, wenn das Asset fehlt — die UI fängt das ab und zeigt einen
/// Fallback-Text statt zu crashen.
Future<String> loadPrivacyPolicyDe() {
  return rootBundle.loadString(_privacyPolicyDeAsset);
}

/// Liest das deutsche Impressum aus dem Asset-Bundle.
///
/// Gleicher Vertrag wie [loadPrivacyPolicyDe]: wirft bei fehlendem Asset,
/// die UI rendert in dem Fall ihren Fallback-Text.
Future<String> loadImprintDe() {
  return rootBundle.loadString(_imprintDeAsset);
}
