import 'package:cineflow_flutter/services/telegram_bot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('telegram /scan and /get dispatch to callbacks', () async {
    final svc = TelegramBotService();
    svc.setDownloadManagerReady(true);
    String? scanned;
    String? got;
    svc.onScan = (u) async { scanned = u; return 'Found 2'; };
    svc.onGet = (s) async { got = s; return 'Started 1'; };

    expect(await svc.handleAuthorizedCommand('/scan https://example.com'), 'Found 2');
    expect(scanned, 'https://example.com');
    expect(await svc.handleAuthorizedCommand('/get 1,3'), 'Started 1');
    expect(got, '1,3');
    expect(await svc.handleAuthorizedCommand('/scan'), contains('Usage'));
    svc.dispose();
  });
}
