import 'package:flutter/material.dart';

import '../services/telegram_bot_service.dart';
import 'ui_effects.dart';

class TelegramBotPanel extends StatefulWidget {
  const TelegramBotPanel({super.key, required this.service});
  final TelegramBotService service;
  @override
  State<TelegramBotPanel> createState() => _TelegramBotPanelState();
}

class _TelegramBotPanelState extends State<TelegramBotPanel> {
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onService);
  }
  @override
  void dispose() {
    widget.service.removeListener(_onService);
    super.dispose();
  }
  void _onService() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Container(
          decoration: const BoxDecoration(color: Color(0xFF090D16), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          child: Column(children: [
            const SizedBox(height: 8),
            Container(width: 44, height: 4, decoration: BoxDecoration(color: const Color(0xFF263244), borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(children: [
                const Icon(Icons.smart_toy_rounded, color: Color(0xFF06B6D4)),
                const SizedBox(width: 8),
                const Expanded(child: Text('Telegram Bot Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
                _statusChip(s),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white70)),
              ]),
            ),
            const TabBar(tabs: [Tab(text: 'Setup & Connection'), Tab(text: 'Live Bot Chat')], labelColor: Color(0xFF22D3EE), unselectedLabelColor: Colors.white54, indicatorColor: Color(0xFF06B6D4)),
            Expanded(child: TabBarView(children: [_setupTab(s), _chatTab(s)])),
          ]),
        ),
      ),
    );
  }

  Widget _statusChip(TelegramBotService s) {
    Color c; String t;
    switch (s.state) {
      case BotConnectionState.connected: c = const Color(0xFF10B981); t = 'Connected'; break;
      case BotConnectionState.connecting: c = Colors.amber; t = 'Connecting'; break;
      case BotConnectionState.error: c = const Color(0xFFEF4444); t = 'Error'; break;
      default: c = Colors.white38; t = 'Disconnected';
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.6))), child: Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)));
  }

  Widget _setupTab(TelegramBotService s) {
    final env = s.env;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _info('Bot config source', '.env (TELEGRAM_BOT_TOKEN, TELEGRAM_AUTHORIZED_USER_IDS)'),
      _info('.env file', env.envFilePresent ? 'Found' : 'Missing - create from .env.example'),
      _info('Token configured', env.hasToken ? 'Yes' : 'No'),
      _info('Authorized IDs configured', env.hasAuthorizedIds ? 'Yes (${env.authorizedUserIds.length})' : 'No'),
      _info('Download manager connected', s.downloadManagerReady ? 'Yes' : 'No'),
      const SizedBox(height: 8),
      const Text('Security: bot is optional, manual start/stop, and processes commands only from authorized IDs in .env.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      if (s.lastError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(s.lastError, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _actionBtn(label: s.isConnected ? 'Disconnect' : 'Connect', color: s.isConnected ? const Color(0xFFEF4444) : const Color(0xFF10B981), onTap: () async { if (s.isConnected) { await s.disconnect(); } else { await s.connect(); } }),
        _actionBtn(label: 'Reload .env', color: const Color(0xFF06B6D4), onTap: () async { await s.loadEnv(); }),
      ]),
      const SizedBox(height: 18),
      const Text('Commands: /status /pause /resume /download <URL> /help', style: TextStyle(color: Colors.white38, fontSize: 12)),
    ]));
  }

  Widget _info(String k, String v) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [SizedBox(width: 180, child: Text(k, style: const TextStyle(color: Colors.white54))), Expanded(child: Text(v, style: const TextStyle(color: Colors.white)))] ));

  Widget _chatTab(TelegramBotService s) {
    final msgs = s.messages;
    return Column(children: [
      Expanded(child: msgs.isEmpty ? const Center(child: Text('No bot messages yet', style: TextStyle(color: Colors.white38))) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: msgs.length, itemBuilder: (c, i) => _bubble(msgs[i]))),
      Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(top: BorderSide(color: Color(0xFF1F2937)))), child: const Text('Chat is read-only log. Use Telegram or commands after connect; no secrets are stored in UI config.', style: TextStyle(color: Colors.white54, fontSize: 12))),
    ]);
  }

  Widget _bubble(ChatMessage m) {
    final isUser = m.sender == 'user';
    final isBot = m.sender == 'bot';
    final bg = isUser ? const Color(0xFF164E63) : isBot ? const Color(0xFF111827) : const Color(0xFF1F2937);
    final border = isUser ? const Color(0xFF06B6D4) : const Color(0xFF263244);
    final label = isUser ? (m.fromTelegram ? 'Mobile Telegram' : 'You (App)') : isBot ? 'CineFlow Bot' : 'System';
    return Column(crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      Container(constraints: const BoxConstraints(maxWidth: 560), margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: isUser ? const Color(0xFF22D3EE) : Colors.white54, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ])),
    ]);
  }

  Widget _actionBtn({required String label, required Color color, required VoidCallback onTap}) {
    return ClickableRegion(child: MouseRegion(cursor: HandCursorProvider.cursor, child: GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.7))), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12))))));
  }
}
