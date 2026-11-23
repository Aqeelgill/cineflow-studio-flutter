import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/core/app_env.dart';

void main() {
  test('Telegram authorization allows only configured IDs', () {
    final env = AppEnv.fromMap({'TELEGRAM_AUTHORIZED_USER_IDS': '111,222'});
    expect(env.isAuthorized('111'), true);
    expect(env.isAuthorized('222'), true);
    expect(env.isAuthorized('333'), false);
    expect(env.isAuthorized(null), false);
    expect(env.isAuthorized(''), false);
  });
}
