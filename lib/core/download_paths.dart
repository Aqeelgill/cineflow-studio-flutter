import 'dart:io';
import 'app_categories.dart';

class DownloadPaths {
  static String rootFor({
    required bool isWindows,
    Map<String, String>? env,
    String? homeDir,
    String? userProfile,
  }) {
    final e = env ?? Platform.environment;
    if (isWindows) {
      final base = userProfile ?? e['USERPROFILE'] ?? Directory.current.path;
      return _join(base, ['Downloads', 'CineFlow-Studio'], true);
    }
    final base = homeDir ?? e['HOME'] ?? Directory.current.path;
    return _join(base, ['Downloads', 'CineFlow-Studio'], false);
  }

  static String categoryDir(String root, AppCategory category, {required bool isWindows}) {
    return _join(root, [category.folderName], isWindows);
  }

  static Future<Directory> ensureCategoryDir(String root, AppCategory category, {required bool isWindows}) async {
    final dir = Directory(categoryDir(root, category, isWindows: isWindows));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Map<String, String>> ensureAllCategoryDirs(String root, {required bool isWindows}) async {
    final out = <String, String>{};
    for (final c in AppCategories.all) {
      final d = await ensureCategoryDir(root, c, isWindows: isWindows);
      out[c.id] = d.path;
    }
    return out;
  }

  static String _join(String base, List<String> parts, bool windows) {
    final sep = windows ? '\\' : '/';
    var p = base;
    if (p.endsWith(sep)) p = p.substring(0, p.length - 1);
    for (final part in parts) {
      p = '$p$sep$part';
    }
    return p;
  }
}
