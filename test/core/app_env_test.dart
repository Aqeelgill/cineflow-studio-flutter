import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/core/app_env.dart';

void main() {
  test('missing .env returns safe empty config', () async {
    final env = await AppEnv.load(path: '/tmp/definitely-missing-cineflow.env');
    expect(env.envFilePresent, false);
    expect(env.hasToken, false);
    expect(env.hasAuthorizedIds, false);
  });

  test('parses token and authorized IDs from env map', () {
    final env = AppEnv.fromMap({
      'TELEGRAM_BOT_TOKEN': 'test-token',
      'TELEGRAM_AUTHORIZED_USER_IDS': '123, 456 789',
    });
    expect(env.telegramBotToken, 'test-token');
    expect(env.authorizedUserIds, {'123', '456', '789'});
    expect(env.isAuthorized('456'), true);
    expect(env.isAuthorized('999'), false);
  });
}
