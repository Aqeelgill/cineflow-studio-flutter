import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../core/app_env.dart';
import '../core/app_i18n.dart';

enum BotConnectionState { disconnected, connecting, connected, error }

class ChatMessage {
  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool fromTelegram;
  ChatMessage({required this.id, required this.sender, required this.text, required this.timestamp, this.fromTelegram = false});
}

class TelegramBotService extends ChangeNotifier {
  BotConnectionState _state = BotConnectionState.disconnected;
  String _lastError = '';
  int _lastUpdateId = 0;
  int _unread = 0;
  bool _polling = false;
  bool _disposed = false;
  http.Client? _client;
  final List<ChatMessage> _messages = [];
  AppEnv _env = const AppEnv(telegramBotToken: null, authorizedUserIds: {}, rpcSecret: null, envFilePresent: false, raw: {});
  Locale _locale = const Locale('en', 'US');
  bool _downloadManagerReady = false;

  Future<String> Function()? onStatus;
  Future<String> Function(String url)? onDownload;
  Future<String> Function()? onPause;
  Future<String> Function()? onResume;
  Future<String> Function()? onHelp;

  BotConnectionState get state => _state;
  String get lastError => _lastError;
  int get unread => _unread;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isConnected => _state == BotConnectionState.connected;
  AppEnv get env => _env;
  bool get downloadManagerReady => _downloadManagerReady;
  Locale get locale => _locale;

  void setLocale(Locale locale) { _locale = locale; }
  void setDownloadManagerReady(bool ready) { _downloadManagerReady = ready; }

  Future<void> loadEnv({String? path}) async {
    _env = await AppEnv.load(path: path);
    _safeNotify();
  }

  String t(String key) => AppI18n.t(key, _locale);

  void clearUnread() { if (_unread == 0) return; _unread = 0; _safeNotify(); }

  void _addMessage(ChatMessage m) {
    _messages.add(m);
    if (_messages.length > 300) _messages.removeRange(0, _messages.length - 300);
    _safeNotify();
  }

  Future<bool> connect() async {
    await loadEnv();
    if (!_env.hasToken) {
      _lastError = t('bot_missing_token');
      _state = BotConnectionState.error;
      _addSystem(_lastError);
      _safeNotify();
      return false;
    }
    if (!_env.hasAuthorizedIds) {
      _lastError = 'No authorized user IDs configured in .env.';
      _state = BotConnectionState.error;
      _addSystem(_lastError);
      _safeNotify();
      return false;
    }
    _state = BotConnectionState.connecting;
    _lastError = '';
    _safeNotify();
    _client?.close();
    _client = http.Client();
    try {
      final me = await _apiGet('getMe');
      if (me['ok'] != true) throw Exception(me['description'] ?? 'Invalid bot token');
      _state = BotConnectionState.connected;
      _addSystem('${t('bot_ready')} @${me['result']?['username'] ?? 'bot'}');
      _startPolling();
      _safeNotify();
      return true;
    } catch (e) {
      _lastError = e.toString();
      _state = BotConnectionState.error;
      _addSystem(_lastError);
      _safeNotify();
      return false;
    }
  }

  Future<void> disconnect() async {
    _polling = false;
    _client?.close();
    _client = null;
    _state = BotConnectionState.disconnected;
    _addSystem('Bot disconnected');
    _safeNotify();
  }

  void _addSystem(String text) {
    _addMessage(ChatMessage(id: _id(), sender: 'system', text: text, timestamp: DateTime.now()));
  }

  void _startPolling() {
    if (_polling) return;
    _polling = true;
    unawaited(_pollLoop());
  }

  Future<void> _pollLoop() async {
    while (_polling && !_disposed) {
      try {
        if (_state != BotConnectionState.connected) { await Future.delayed(const Duration(seconds: 2)); continue; }
        final res = await _apiGet('getUpdates', params: {
          'offset': '${_lastUpdateId + 1}', 'timeout': '20', 'allowed_updates': json.encode(['message']),
        });
        if (res['ok'] == true && res['result'] is List) {
          for (final upd in res['result'] as List) {
            if (upd is! Map) continue;
            final uid = upd['update_id'];
            if (uid is int && uid > _lastUpdateId) _lastUpdateId = uid;
            final msg = upd['message'];
            if (msg is Map) await _handleMessage(Map<String, dynamic>.from(msg));
          }
        }
      } catch (_) {
        if (_polling && !_disposed) await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> _handleMessage(Map<String, dynamic> msg) async {
    final chat = msg['chat'];
    final chatId = chat is Map ? chat['id']?.toString() : null;
    final text = msg['text']?.toString().trim() ?? '';
    if (chatId == null || text.isEmpty) return;
    if (!_env.isAuthorized(chatId)) {
      // Secure handling: do not process unauthorized users
      await _sendToChat(chatId, t('bot_unauthorized'));
      return;
    }
    _addMessage(ChatMessage(id: _id(), sender: 'user', text: text, timestamp: DateTime.now(), fromTelegram: true));
    _unread++;
    _safeNotify();
    final reply = await handleAuthorizedCommand(text);
    _addMessage(ChatMessage(id: _id(), sender: 'bot', text: reply, timestamp: DateTime.now()));
    await _sendToChat(chatId, reply);
  }

  Future<String> handleAuthorizedCommand(String text) async {
    final lower = text.trim().toLowerCase();
    if (!_downloadManagerReady) return t('bot_not_connected');
    if (lower == '/help' || lower == '/start') {
      return await (onHelp?.call() ?? Future.value(_defaultHelp()));
    }
    if (lower == '/status') {
      return await (onStatus?.call() ?? Future.value(t('bot_not_connected')));
    }
    if (lower == '/pause') {
      return await (onPause?.call() ?? Future.value(t('bot_not_connected')));
    }
    if (lower == '/resume') {
      return await (onResume?.call() ?? Future.value(t('bot_not_connected')));
    }
    if (lower.startsWith('/download')) {
      final url = text.substring('/download'.length).trim();
      if (url.isEmpty) return 'Usage: /download <URL>';
      return await (onDownload?.call(url) ?? Future.value(t('bot_not_connected')));
    }
    return _defaultHelp();
  }

  String _defaultHelp() => '''${t('help')}:
/status
/pause
/resume
/download <URL>
/help''';

  Future<void> _sendToChat(String chatId, String text) async {
    if (!_env.hasToken) return;
    try {
      await _apiPost('sendMessage', {
        'chat_id': chatId,
        'text': text.length > 4000 ? text.substring(0, 4000) : text,
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _apiGet(String method, {Map<String, String>? params}) async {
    final token = _env.telegramBotToken ?? '';
    final uri = Uri.parse('https://api.telegram.org/bot$token/$method').replace(queryParameters: params);
    final resp = await (_client ?? http.Client()).get(uri).timeout(const Duration(seconds: 30));
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _apiPost(String method, Map<String, dynamic> body) async {
    final token = _env.telegramBotToken ?? '';
    final uri = Uri.parse('https://api.telegram.org/bot$token/$method');
    final resp = await (_client ?? http.Client()).post(uri, headers: {'Content-Type': 'application/json'}, body: json.encode(body)).timeout(const Duration(seconds: 30));
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_messages.length}';
  void _safeNotify() { if (!_disposed) notifyListeners(); }
  @override
  void dispose() { _disposed = true; _polling = false; _client?.close(); super.dispose(); }
}
