import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/core/app_i18n.dart';

void main() {
  test('missing key falls back to English', () {
    final v = AppI18n.t('definitely_missing_key_xyz', const Locale('ar'));
    expect(v, 'definitely_missing_key_xyz');
  });

  test('Arabic sets RTL', () {
    expect(AppI18n.isRtl(const Locale('ar')), true);
    expect(AppI18n.isRtl(const Locale('en', 'US')), false);
  });
}
