import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum ShareKind { shared, savedToFile }

class ShareResult {
  const ShareResult({required this.kind, this.path});
  final ShareKind kind;
  final String? path;
}

/// Wraps `share_plus` for mobile and falls back to writing the CSV into the
/// platform's downloads/documents directory on desktop and web. Stays a thin
/// adapter so widgets can be tested without channel mocks.
class CsvShareService {
  Future<ShareResult> share(String csv, {required String filename}) async {
    final bytes = Uint8List.fromList(utf8.encode(csv));
    if (_useSystemShare) {
      final file = XFile.fromData(bytes, name: filename, mimeType: 'text/csv');
      await SharePlus.instance.share(
        ShareParams(files: [file], fileNameOverrides: [filename]),
      );
      return const ShareResult(kind: ShareKind.shared);
    }
    final dir = await _writableDir();
    final path = p.join(dir.path, filename);
    final file = File(path);
    await file.writeAsBytes(bytes);
    return ShareResult(kind: ShareKind.savedToFile, path: path);
  }

  bool get _useSystemShare {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<Directory> _writableDir() async {
    try {
      final dl = await getDownloadsDirectory();
      if (dl != null) return dl;
    } on Object {
      // Falls through to documents dir on platforms without downloads support.
    }
    return getApplicationDocumentsDirectory();
  }
}

final csvShareServiceProvider = Provider<CsvShareService>((ref) {
  return CsvShareService();
});
