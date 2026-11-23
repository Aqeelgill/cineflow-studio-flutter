import 'dart:io';

class AppEnv {
  final String? telegramBotToken;
  final Set<String> authorizedUserIds;
  final String? rpcSecret;
  final bool envFilePresent;
  final Map<String, String> raw;

  const AppEnv({
    required this.telegramBotToken,
    required this.authorizedUserIds,
    required this.rpcSecret,
    required this.envFilePresent,
    required this.raw,
  });

  bool get hasToken => (telegramBotToken ?? '').trim().isNotEmpty;
  bool get hasAuthorizedIds => authorizedUserIds.isNotEmpty;
  bool get botConfigured => hasToken && hasAuthorizedIds;

  static Future<AppEnv> load({String? path}) async {
    final envPath = path ?? '${Directory.current.path}${Platform.pathSeparator}.env';
    final file = File(envPath);
    if (!await file.exists()) {
      return const AppEnv(telegramBotToken: null, authorizedUserIds: {}, rpcSecret: null, envFilePresent: false, raw: {});
    }
    final lines = await file.readAsLines();
    final map = <String, String>{};
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final idx = t.indexOf('=');
      if (idx <= 0) continue;
      final k = t.substring(0, idx).trim();
      var v = t.substring(idx + 1).trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      map[k] = v;
    }
    return fromMap(map, envFilePresent: true);
  }

  static AppEnv fromMap(Map<String, String> map, {bool envFilePresent = true}) {
    final token = (map['TELEGRAM_BOT_TOKEN'] ?? '').trim();
    final idsRaw = (map['TELEGRAM_AUTHORIZED_USER_IDS'] ?? '').trim();
    final ids = idsRaw
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim())
        .where((s) => RegExp(r'^\d+$').hasMatch(s))
        .toSet();
    final rpc = (map['CINEFLOW_RPC_SECRET'] ?? '').trim();
    return AppEnv(
      telegramBotToken: token.isEmpty ? null : token,
      authorizedUserIds: ids,
      rpcSecret: rpc.isEmpty ? null : rpc,
      envFilePresent: envFilePresent,
      raw: Map.unmodifiable(map),
    );
  }

  bool isAuthorized(String? chatId) {
    if (chatId == null) return false;
    final t = chatId.trim();
    if (t.isEmpty) return false;
    return authorizedUserIds.contains(t);
  }
}
