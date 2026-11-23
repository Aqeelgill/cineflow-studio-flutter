import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/core/app_categories.dart';
import 'package:cineflow_flutter/core/download_paths.dart';

void main() {
  test('Linux download root uses Downloads/CineFlow-Studio', () {
    final root = DownloadPaths.rootFor(isWindows: false, env: {'HOME': '/home/test'});
    expect(root, '/home/test/Downloads/CineFlow-Studio');
  });

  test('Windows download root uses Downloads\\CineFlow-Studio', () {
    final root = DownloadPaths.rootFor(isWindows: true, env: {'USERPROFILE': r'C:\Users\Test'});
    expect(root, r'C:\Users\Test\Downloads\CineFlow-Studio');
  });

  test('creates category folders', () async {
    final tmp = await Directory.systemTemp.createTemp('cineflow_paths_');
    addTearDown(() async { if (await tmp.exists()) await tmp.delete(recursive: true); });
    final root = '${tmp.path}/Downloads/CineFlow-Studio';
    final paths = await DownloadPaths.ensureAllCategoryDirs(root, isWindows: false);
    expect(paths.length, 9);
    for (final c in AppCategories.all) {
      expect(Directory(paths[c.id]!).existsSync(), true);
      expect(paths[c.id], contains(c.folderName));
    }
  });
}
