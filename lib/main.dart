import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'core/app_categories.dart';
import 'core/app_i18n.dart';
import 'core/download_paths.dart';
import 'core/ram_guard.dart';
import 'core/lead_models.dart';
import 'core/media_scan_models.dart';
import 'engine/download_engine.dart';
import 'services/file_filter_bridge.dart';
import 'services/ram_guard_service.dart';
import 'services/telegram_bot_service.dart';
import 'widgets/telegram_bot_panel.dart';
import 'widgets/ui_effects.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CineFlowApp());
}

class CineFlowApp extends StatefulWidget {
  const CineFlowApp({super.key});

  @override
  State<CineFlowApp> createState() => _CineFlowAppState();
}

class _CineFlowAppState extends State<CineFlowApp> {
  @override
  void initState() {
    super.initState();
    HandCursorProvider.load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = const ColorScheme.dark(
      primary: Color(0xFF06B6D4),
      secondary: Color(0xFF10B981),
      surface: Color(0xFF111827),
      error: Color(0xFFEF4444),
    );
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.transparent),
    );
    return MaterialApp(
      title: 'CineFlow Studio — Universal Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: scheme,
        cardColor: const Color(0xFF111827),
        dividerColor: const Color(0xFF1F2937),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: const Color(0xFF0B1220),
          border: baseBorder,
          enabledBorder: baseBorder,
          focusedBorder: baseBorder,
          disabledBorder: baseBorder,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.selected)) {
              return const Color(0xFF06B6D4);
            }
            return Colors.transparent;
          }),
          checkColor: WidgetStateProperty.all(Colors.black),
        ),
      ),
      home: const StudioHomeScreen(),
    );
  }
}

class StudioHomeScreen extends StatefulWidget {
  const StudioHomeScreen({super.key});

  @override
  State<StudioHomeScreen> createState() => _StudioHomeScreenState();
}

class _StudioHomeScreenState extends State<StudioHomeScreen> {
  final UniversalDownloadEngine _engine = UniversalDownloadEngine();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _seriesUrlController = TextEditingController();
  final TextEditingController _scrapeUrlController = TextEditingController();
  final List<DownloadItem> _queue = [];
  String _saveDir = '';
  int _selectedTab = 0;
  DownloadQuality _addQuality = DownloadQuality.best4k;

  // Series tab
  List<EpisodeInfo> _episodes = [];
  bool _fetchingEpisodes = false;
  String? _seriesError;
  DownloadQuality _seriesQuality = DownloadQuality.best4k;

  // Scraper tab
  bool _scraping = false;
  String? _scrapeError;
  final List<LeadEntry> _leadResults = [];
  final LeadFilterState _leadFilter = LeadFilterState();
  int _leadPreviewLimit = 200;
  bool _pickerOpen = false;

  // Downloader scan preview
  final List<ScannedMediaItem> _scanResults = [];
  MediaFilter _mediaFilter = MediaFilter.all;
  bool _scanning = false;
  int _scanPreviewLimit = 200;

  // Scheduler tab
  final List<ScheduledJob> _jobs = [];
  Timer? _schedulerTimer;
  String _seriesWatchUrl = '';

  // RAM guard
  final RamGuardService _ramGuard = RamGuardService(initialMode: RamMode.standard);
  StreamSubscription<RamDecision>? _ramSub;
  int _ramPercent = 0;
  RamMode _ramMode = RamMode.standard;
  bool _showRamBanner = false;

  // Telegram bot
  final TelegramBotService _telegram = TelegramBotService();
  Locale _locale = const Locale('en', 'US');
  AppCategory _selectedCategory = AppCategories.webSeries;

  int get _concurrencyLimit => RamGuard.evaluate(_ramPercent, _ramMode).allowedConcurrency;

  @override
  void initState() {
    super.initState();
    _initDir();
    _schedulerTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _tickScheduler());
    _ramGuard.start();
    _ramSub = _ramGuard.stream.listen((s) {
      if (!mounted) return;
      setState(() {
        _ramPercent = s.usedPercent;
        _showRamBanner = s.alert;
      });
      _pumpQueue();
    });
    _wireTelegram();
  }

  void _wireTelegram() {
    _telegram.setDownloadManagerReady(true);
    _telegram.setLocale(_locale);
    _telegram.onStatus = _botStatus;
    _telegram.onDownload = _botAddUrl;
    _telegram.onPause = _botPause;
    _telegram.onResume = _botResume;
    _telegram.onHelp = () async => _botHelp();
    _telegram.onScan = _botScanUrl;
    _telegram.onGet = _botGetScan;
    _telegram.addListener(_onTelegramChanged);
    _telegram.loadEnv();
  }

  void _onTelegramChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initDir() async {
    final dir = _engine.getDefaultSaveDirectory();
    await DownloadPaths.ensureAllCategoryDirs(dir, isWindows: Platform.isWindows);
    if (mounted) setState(() => _saveDir = dir);
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    _ramSub?.cancel();
    _ramGuard.dispose();
    _telegram.removeListener(_onTelegramChanged);
    _telegram.dispose();
    _urlController.dispose();
    _seriesUrlController.dispose();
    _scrapeUrlController.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _newId(String seed) =>
      '${DateTime.now().microsecondsSinceEpoch}_${seed.hashCode}';

  void _refresh() {
    if (mounted) setState(() {});
    _pumpQueue();
  }

  // ---------- Concurrency / RAM Guard ----------
  void _pumpQueue() {
    final decision = RamGuard.evaluate(_ramPercent, _ramMode);
    if (decision.shouldPauseNewStarts) return;
    final active = _queue.where((i) => i.status == 'Downloading').length;
    if (active >= decision.allowedConcurrency) return;
    final pending = _queue
        .where((i) => i.status == 'Queued')
        .take(decision.allowedConcurrency - active)
        .toList();
    for (final item in pending) {
      _engine.startDownload(item, _saveDir, _refresh, maxConcurrentChunks: decision.allowedConcurrency);
    }
  }

  void _enqueueStart(DownloadItem item) {
    if (item.status == 'Completed') return;
    item.error = null;
    final decision = RamGuard.evaluate(_ramPercent, _ramMode);
    final active = _queue.where((i) => i.status == 'Downloading').length;
    if (!decision.shouldPauseNewStarts && active < decision.allowedConcurrency) {
      _engine.startDownload(item, _saveDir, _refresh, maxConcurrentChunks: decision.allowedConcurrency);
    } else {
      setState(() => item.status = 'Queued');
    }
  }

  // ---------- Tab 1: Universal Downloader ----------
  Future<void> _pasteAndAdd() async {
    var raw = _urlController.text.trim();
    if (raw.isEmpty) {
      final clip = await Clipboard.getData('text/plain');
      raw = clip?.text?.trim() ?? '';
    }
    final urlReg = RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false);
    final matches = urlReg.allMatches(raw).map((m) {
      var u = m.group(0)!;
      return u.replaceAll(RegExp(r'''[.,;:!?]+$'''), '');
    }).toSet();
    if (matches.isEmpty) {
      _showSnack('No valid http/https links found');
      return;
    }
    setState(() {
      for (final u in matches) {
        final direct = _engine.isDirectFile(u);
        _queue.add(DownloadItem(
          id: _newId(u),
          url: u,
          title: Uri.tryParse(u)?.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => u) ?? u,
          platform: direct ? 'Direct File' : 'Web Video',
          quality: _addQuality,
          category: _selectedCategory,
        ));
      }
      _urlController.clear();
    });
  }

  List<ScannedMediaItem> get _filteredScanResults => _scanResults.where((i) => i.matches(_mediaFilter)).toList();

  Future<void> _scanPage() async {
    final url = _urlController.text.trim();
    if (!url.startsWith('http')) { _showSnack('Paste a webpage URL to scan'); return; }
    if (_scanning || _pickerOpen) return;
    setState(() { _scanning = true; _scanPreviewLimit = 200; });
    _showSnack('Scanning media links...');
    try {
      final items = await FileFilterBridge.scanMedia(url: url);
      if (!mounted) return;
      setState(() { _scanResults..clear()..addAll(items); _scanning = false; });
      _showSnack('${items.length} media links found');
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _showSnack('Scan error: $e');
    }
  }

  Future<void> _attachFile() async {
    if (_pickerOpen || _scanning) { _showSnack('File operation already in progress'); return; }
    setState(() => _pickerOpen = true);
    try {
      final files = await FilePicker.pickFiles(
        allowedExtensions: ['json', 'txt', 'csv', 'html', 'htm', 'xml'],
        type: FileType.custom,
      );
      if (!mounted) return;
      if (files.isEmpty) return;
      final path = files.single.path;
      if (path == null) { _showSnack('Could not read selected file path'); return; }
      setState(() { _scanning = true; _scanPreviewLimit = 200; });
      final items = await FileFilterBridge.scanMedia(filePath: path);
      if (!mounted) return;
      setState(() { _scanResults..clear()..addAll(items); _scanning = false; });
      _showSnack('${items.length} media links extracted');
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _showSnack('Attach/parse error: $e');
    } finally {
      if (mounted) setState(() => _pickerOpen = false); else _pickerOpen = false;
    }
  }

  Future<void> _browseFolder() async {
    if (_pickerOpen) return;
    setState(() => _pickerOpen = true);
    try {
      final uri = await FilePicker.pickDirectory();
      if (uri == null || !mounted) return;
      String dir;
      if (uri.scheme == 'file' || uri.scheme.isEmpty) {
        try { dir = uri.toFilePath(); } catch (_) { dir = uri.path; }
      } else { dir = uri.toString(); }
      if (dir.isNotEmpty) setState(() => _saveDir = dir);
    } catch (e) { _showSnack('Folder picker error: $e'); }
    finally { if (mounted) setState(() => _pickerOpen = false); else _pickerOpen = false; }
  }

  void _downloadSelectedScanResults() {
    final selected = _filteredScanResults.where((i) => i.selected).toList();
    if (selected.isEmpty) {
      _showSnack('No scanned items selected');
      return;
    }
    setState(() {
      for (final s in selected) {
        final exists = _queue.any((q) => q.url == s.url);
        if (exists) continue;
        _queue.add(DownloadItem(
          id: _newId(s.url),
          url: s.url,
          title: s.title.isNotEmpty ? s.title : (Uri.tryParse(s.url)?.pathSegments.lastWhere((p) => p.isNotEmpty, orElse: () => s.url) ?? s.url),
          platform: _engine.isDirectFile(s.url) ? 'Direct File' : 'Scanned Media',
          quality: _addQuality,
          category: _selectedCategory,
          selected: true,
        ));
      }
    });
    _downloadSelected();
  }

  void _downloadSelected() {
    final items = _queue.where((i) => i.selected).toList();
    if (items.isEmpty) {
      _showSnack('No items selected');
      return;
    }
    for (final item in items) {
      _enqueueStart(item);
    }
  }

  void _deleteSelected() {
    setState(() {
      final toRemove = _queue.where((i) => i.selected).toList();
      for (final item in toRemove) {
        _engine.pauseItem(item);
      }
      _queue.removeWhere((i) => i.selected);
    });
  }

  void _pauseSelectedOrRunning() {
    final targets = _queue
        .where((i) => i.selected || i.status == 'Downloading')
        .toList();
    for (final item in targets) {
      _engine.pauseItem(item);
    }
    _refresh();
  }

  void _resumeSelected() {
    final items = _queue
        .where((i) =>
            i.selected &&
            (i.status == 'Paused' || i.status.startsWith('Failed')))
        .toList();
    if (items.isEmpty) {
      _showSnack('No paused/failed selected items');
      return;
    }
    for (final item in items) {
      _enqueueStart(item);
    }
  }

  void _restartSelected() {
    final items = _queue.where((i) => i.selected).toList();
    if (items.isEmpty) {
      _showSnack('No items selected');
      return;
    }
    for (final item in items) {
      _engine.pauseItem(item);
      item.progress = 0;
      item.speed = '--';
      item.status = 'Queued';
      item.error = null;
      item.paused = false;
      _enqueueStart(item);
    }
  }

  void _startOrResume(DownloadItem item) {
    _enqueueStart(item);
  }

  Future<void> _openFolder() async {
    if (_saveDir.isEmpty) return;
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [_saveDir]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [_saveDir]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_saveDir]);
      } else {
        _showSnack(_saveDir);
      }
    } catch (e) {
      _showSnack('Open folder error: $e');
    }
  }

  Future<void> _editSource(DownloadItem item) async {
    final urlCtrl = TextEditingController(text: item.url);
    final proxyCtrl = TextEditingController(text: item.proxyUrl ?? '');
    final headersCtrl = TextEditingController(text: item.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: Text(AppI18n.t('edit_source', _locale)),
        content: SizedBox(width: 560, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL')),
          const SizedBox(height: 8),
          TextField(controller: proxyCtrl, decoration: const InputDecoration(labelText: 'Proxy (http://host:port)')),
          const SizedBox(height: 8),
          TextField(controller: headersCtrl, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Headers (Key: Value per line)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppI18n.t('cancel', _locale))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppI18n.t('save', _locale))),
        ],
      ),
    );
    if (ok != true) return;
    final hdrs = <String, String>{};
    for (final line in headersCtrl.text.split(RegExp(r'\r?\n'))) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      hdrs[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
    setState(() {
      _engine.updateTaskSource(item, newUrl: urlCtrl.text, newHeaders: hdrs, proxyUrl: proxyCtrl.text);
    });
  }

  // ---------- Tab 2: Series & Drama ----------
  Future<void> _fetchEpisodes() async {
    final url = _seriesUrlController.text.trim();
    if (!url.startsWith('http')) {
      _showSnack('Enter a valid playlist/channel/show URL');
      return;
    }
    setState(() {
      _fetchingEpisodes = true;
      _seriesError = null;
      _episodes = [];
    });
    try {
      final eps = await _engine.fetchPlaylist(url);
      setState(() {
        _episodes = eps;
        _fetchingEpisodes = false;
        _seriesWatchUrl = url;
      });
      _showSnack('${eps.length} episodes found');
    } catch (e) {
      setState(() {
        _fetchingEpisodes = false;
        _seriesError = e.toString();
      });
    }
  }

  void _downloadSelectedEpisodes({bool startNow = true}) {
    final selected = _episodes.where((e) => e.selected).toList();
    if (selected.isEmpty) {
      _showSnack('No episodes selected');
      return;
    }
    for (final ep in selected) {
      final item = DownloadItem(
        id: _newId(ep.url),
        url: ep.url,
        title: ep.title,
        platform: 'Series',
        quality: _seriesQuality,
        category: _selectedCategory,
      );
      _queue.add(item);
      if (startNow) _enqueueStart(item);
    }
    _showSnack('${selected.length} episodes sent to Downloader');
    setState(() => _selectedTab = 0);
  }

  // ---------- Tab 3: Lead Scraper ----------
  bool _looksLikeMedia(String u){
    final low=u.toLowerCase();
    return RegExp(r'\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|ts|m3u8|mpd|mp3|m4a|aac|flac|wav|ogg)(\?|$)').hasMatch(low);
  }

  Future<void> _runScrape() async {
    final raw = _scrapeUrlController.text.trim();
    if (raw.isEmpty) { _showSnack('Enter target website URL(s)'); return; }
    final urlReg = RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false);
    final urls = urlReg.allMatches(raw).map((m) => m.group(0)!).toSet().toList();
    if (urls.isEmpty) { _showSnack('No valid URLs found'); return; }
    setState(() { _scraping = true; _scrapeError = null; });
    try {
      final results = <LeadEntry>[];
      final seen = <String>{};
      for (final u in urls) {
        final res = await http.get(Uri.parse(u), headers: {'User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'});
        if (res.statusCode != 200) continue;
        final leads = await FileFilterBridge.scanLeads(url: u, rawContent: res.body);
        for (final l in leads) {
          final key='${l.email}|${l.phone}|${l.website}|${l.social}|${l.name}'.toLowerCase();
          if (seen.add(key)) results.add(l);
        }
      }
      if (!mounted) return;
      setState(() { _leadResults..clear()..addAll(results); _scraping = false; });
      _showSnack('${results.length} leads found');
    } catch (e) {
      if (!mounted) return;
      setState(() { _scraping = false; _scrapeError = e.toString(); });
    }
  }

  Future<void> _importLeadsJson() async {
    if (_pickerOpen || _scraping) { _showSnack('File operation already in progress'); return; }
    setState(() => _pickerOpen = true);
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json','txt','csv','xml','html','htm']);
      if (!mounted) return;
      if (files.isEmpty) return;
      final path = files.single.path;
      if (path == null) { _showSnack('Could not read selected file path'); return; }
      setState(() { _scraping = true; _leadPreviewLimit = 200; });
      final leads = await FileFilterBridge.scanLeads(filePath: path);
      if (!mounted) return;
      setState(() { _leadResults..clear()..addAll(leads); _scraping = false; });
      _showSnack('${leads.length} leads imported');
    } catch (e) {
      if (!mounted) return;
      setState(() => _scraping = false);
      _showSnack('Lead import error: $e');
    } finally {
      if (mounted) setState(() => _pickerOpen = false); else _pickerOpen = false;
    }
  }

  void _deleteSelectedLeads() { setState(() => _leadResults.removeWhere((l) => l.selected)); }

  String _csvEscape(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) return '"${v.replaceAll('"', '""')}"';
    return v;
  }

  Future<void> _exportScrapeCsv() async {
    final rows = _filteredLeads;
    if (rows.isEmpty) { _showSnack('No results to export'); return; }
    try {
      final buf = StringBuffer();
      buf.writeln('name,email,phone,website,social,category');
      for (final r in rows) {
        buf.writeln('${_csvEscape(r.name)},${_csvEscape(r.email)},${_csvEscape(r.phone)},${_csvEscape(r.website)},${_csvEscape(r.social)},${_csvEscape(r.category)}');
      }
      final bytes = utf8.encode(buf.toString());
      String? saved;
      try {
        final uri = await FilePicker.saveFile(fileName: 'leads_export.csv', bytes: Uint8List.fromList(bytes), mimeType: 'text/csv', dialogTitle: 'Export CSV');
        if (uri != null) { saved = (uri.scheme == 'file' || uri.scheme.isEmpty) ? uri.toFilePath() : uri.toString(); }
      } catch (_) { saved = null; }
      if (saved == null || saved.isEmpty) {
        final fallback = '$_saveDir${Platform.pathSeparator}leads_export_${DateTime.now().millisecondsSinceEpoch}.csv';
        final file = File(fallback); await file.create(recursive: true); await file.writeAsBytes(bytes); saved = file.path;
      }
      _showSnack('Exported: $saved');
    } catch (e) { _showSnack('Export error: $e'); }
  }

  void _sendScrapeMediaToDownloader() {
    final media = _leadResults.where((l) => _looksLikeMedia(l.website) && l.selected).toList();
    final source = media.isNotEmpty ? media : _leadResults.where((l) => _looksLikeMedia(l.website)).toList();
    if (source.isEmpty) { _showSnack('No media links found'); return; }
    setState(() {
      for (final m in source) {
        if (_queue.any((q) => q.url == m.website)) continue;
        _queue.add(DownloadItem(id: _newId(m.website), url: m.website, title: Uri.tryParse(m.website)?.pathSegments.lastWhere((s)=>s.isNotEmpty, orElse:()=>m.website) ?? m.website, platform: 'Scraped Media', quality: _addQuality, category: _selectedCategory));
      }
      _selectedTab = 0;
    });
    _showSnack('${source.length} media links sent to Downloader');
  }

  // ---------- Tab 4: Scheduler ----------
  Future<void> _addScheduledJob() async {
    final type = await showDialog<JobType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Job Type'),
        children: JobType.values
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, t),
                  child: Text(t.label),
                ))
            .toList(),
      ),
    );
    if (type == null || !mounted) return;

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay.fromDateTime(now.add(const Duration(minutes: 1))),
    );
    if (time == null || !mounted) return;
    DateTime scheduled =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (scheduled.isBefore(DateTime.now())) {
      scheduled = DateTime.now().add(const Duration(minutes: 1));
    }

    final interval = await showDialog<RepeatInterval>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Repeat Interval'),
        children: RepeatInterval.values
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, r),
                  child: Text(r.label),
                ))
            .toList(),
      ),
    );
    if (interval == null || !mounted) return;

    setState(() {
      _jobs.add(ScheduledJob(
        id: _newId(type.label),
        type: type,
        nextRun: scheduled,
        interval: interval,
        status: 'Armed',
      ));
    });
  }

  void _tickScheduler() {
    final now = DateTime.now();
    bool changed = false;
    for (final job in List<ScheduledJob>.from(_jobs)) {
      if (job.status == 'Running') continue;
      if (now.isAfter(job.nextRun) || now.isAtSameMomentAs(job.nextRun)) {
        job.status = 'Running';
        job.lastRun = now;
        changed = true;
        _executeJob(job).whenComplete(() {
          if (!mounted) return;
          setState(() {
            job.runCount++;
            if (job.interval == RepeatInterval.once) {
              job.status = 'Completed';
            } else {
              job.status = 'Armed';
              job.nextRun = job.interval.nextAfter(now);
            }
          });
        });
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _executeJob(ScheduledJob job) async {
    try {
      switch (job.type) {
        case JobType.downloadAll:
          _startAllQueued();
          break;
        case JobType.seriesWatch:
          if (_seriesWatchUrl.isNotEmpty) {
            final eps = await _engine.fetchPlaylist(_seriesWatchUrl);
            for (final ep in eps) {
              if (_queue.any((q) => q.url == ep.url)) continue;
              final item = DownloadItem(
                id: _newId(ep.url),
                url: ep.url,
                title: ep.title,
                platform: 'Series',
                quality: _seriesQuality,
              );
              _queue.add(item);
              _enqueueStart(item);
            }
          }
          break;
        case JobType.leadScraper:
          if (_scrapeUrlController.text.trim().isNotEmpty) {
            await _runScrape();
          }
          break;
      }
    } catch (_) {}
  }

  void _startAllQueued() {
    for (final item in _queue) {
      if (item.status == 'Queued' ||
          item.status == 'Paused' ||
          item.status.startsWith('Failed')) {
        _enqueueStart(item);
      }
    }
    _pumpQueue();
  }

  // ---------- Telegram Bot handlers ----------
  Future<String> _botStatus() async {
    final decision = RamGuard.evaluate(_ramPercent, _ramMode);
    final active = _queue.where((i) => i.status == 'Downloading').length;
    final queued = _queue.where((i) => i.status == 'Queued').length;
    final paused = _queue.where((i) => i.status == 'Paused').length;
    final failed = _queue.where((i) => i.status.startsWith('Failed')).length;
    final completed = _queue.where((i) => i.status == 'Completed').length;
    return """${AppI18n.t('status', _locale)}: CineFlow
${AppI18n.t('ram', _locale)}: $_ramPercent% (${_ramMode.label}, limit ${decision.allowedConcurrency})
Active: $active
Queued: $queued
Paused: $paused
Failed: $failed
Completed: $completed
Category root: $_saveDir""";
  }

  Future<String> _botAddUrl(String url) async {
    final u = url.trim();
    if (!u.startsWith('http')) return 'Invalid URL';
    final direct = _engine.isDirectFile(u);
    final item = DownloadItem(
      id: _newId(u),
      url: u,
      title: Uri.tryParse(u)?.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => u) ?? u,
      platform: direct ? 'Direct File' : 'Web Video',
      quality: _addQuality,
      category: _selectedCategory,
    );
    setState(() => _queue.add(item));
    _enqueueStart(item);
    return '${AppI18n.t('download_all', _locale)}: queued 1 (${item.category.label}) -> ${item.title}';
  }

  Future<String> _botPause() async {
    for (final item in _queue.where((i) => i.status == 'Downloading')) {
      _engine.pauseItem(item);
    }
    _refresh();
    return AppI18n.t('pause', _locale);
  }

  Future<String> _botResume() async {
    int count = 0;
    for (final item in _queue) {
      if (item.status == 'Paused' || item.status.startsWith('Failed') || item.status == 'Queued') {
        item.status = 'Queued';
        count++;
      }
    }
    _pumpQueue();
    _refresh();
    return '${AppI18n.t('resume', _locale)}: $count';
  }

  String _botHelp() {
    return '${AppI18n.t('help', _locale)}:\n/status\n/pause\n/resume\n/download <URL>\n/scan <URL>\n/get 1,3\n/get all\n/help';
  }

  Future<String> _botScanUrl(String url) async {
    if (!url.startsWith('http')) return 'Usage: /scan <URL>';
    final items = await FileFilterBridge.scanMedia(url: url);
    if (!mounted) return 'Scan failed';
    setState(() { _scanResults..clear()..addAll(items); _selectedTab = 0; });
    if (items.isEmpty) return 'No media links found.';
    final lines = <String>['Found ${items.length} media links:'];
    for (var i=0; i<items.length && i<20; i++) {
      final it=items[i];
      final tag = it.tag.isNotEmpty ? ' [${it.tag}]' : '';
      lines.add('${i+1}. ${it.title}$tag');
    }
    if (items.length>20) lines.add('...and ${items.length-20} more');
    lines.add('Use /get 1,3 or /get all');
    return lines.join('\n');
  }

  Future<String> _botGetScan(String selection) async {
    if (_scanResults.isEmpty) return 'No scan results. Use /scan <URL> first.';
    final sel = selection.trim().toLowerCase();
    final picked = <ScannedMediaItem>[];
    if (sel == 'all') {
      picked.addAll(_scanResults);
    } else {
      final idxs = sel.split(RegExp(r'[\s,]+')).where((s)=>s.isNotEmpty).map((s)=>int.tryParse(s)).whereType<int>();
      for (final i in idxs) { if (i>=1 && i<=_scanResults.length) picked.add(_scanResults[i-1]); }
    }
    if (picked.isEmpty) return 'No valid selection. Use /get 1,3 or /get all';
    var started=0;
    for (final s in picked) {
      if (_queue.any((q)=>q.url==s.url)) continue;
      final item = DownloadItem(id:_newId(s.url), url:s.url, title:s.title.isNotEmpty?s.title:s.url, platform:_engine.isDirectFile(s.url)?'Direct File':'Scanned Media', quality:_addQuality, category:_selectedCategory, selected:true);
      setState(()=>_queue.add(item));
      _enqueueStart(item);
      started++;
    }
    _pumpQueue();
    return 'Started $started download(s) from scan selection.';
  }

  void _openTelegramPanel() {
    _telegram.clearUnread();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: TelegramBotPanel(service: _telegram),
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: Row(children: [
          Image.asset('assets/logo/cineflow_icon.png', width: 32, height: 32),
          const SizedBox(width: 10),
          const Text('CineFlow Studio'),
        ]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CineFlow Studio Universal Downloader'),
            SizedBox(height: 8),
            Text('Creator: Aqeel Gill'),
            Text('Copyright: Copyright (c) 2026 Aqeel Gill - CineFlow Studio'),
            Text('Support Contact: +92 3202080379'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final decision = RamGuard.evaluate(_ramPercent, _ramMode);
    final dir = AppI18n.isRtl(_locale) ? TextDirection.rtl : TextDirection.ltr;
    return Directionality(
      textDirection: dir,
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        titleSpacing: 16,
        title: const GradientTitle(),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 8), child: Center(child: _languagePicker())),
          Padding(padding: const EdgeInsets.only(right: 8), child: Center(child: _ramModePicker())),
          Padding(padding: const EdgeInsets.only(right: 8), child: Center(child: _telegramButton())),
          IconButton(tooltip: 'About', onPressed: _showAbout, icon: const Icon(Icons.info_outline, color: Color(0xFF9CA3AF))),
          Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: _ramPill(decision.alert))),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tabChip(0, '1. ${AppI18n.t('tab_downloader', _locale)}'),
                  _tabChip(1, '2. ${AppI18n.t('tab_series', _locale)}'),
                  _tabChip(2, '3. ${AppI18n.t('tab_leads', _locale)}'),
                  _tabChip(3, '4. ${AppI18n.t('tab_scheduler', _locale)}'),
                ],
              ),
            ),
          ),
          if (_showRamBanner)
            Container(
              width: double.infinity,
              color: const Color(0xFF450A0A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFCA5A5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'RAM ${_ramPercent}% reached 65% limit. Concurrency reduced/paused; system RAM is not restarted. RAM limits are targets, not guarantees.',
                      style: const TextStyle(color: Color(0xFFFCA5A5)),
                    ),
                  ),
                  ClickableRegion(
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFFFCA5A5)),
                      onPressed: () => setState(() => _showRamBanner = false),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Center(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.08,
                          child: Image.asset(
                            'assets/logo/cineflow_icon.png',
                            height: constraints.maxHeight * 0.35,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    _buildTab(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _languagePicker() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<Locale>(
        value: _locale,
        dropdownColor: const Color(0xFF111827),
        iconEnabledColor: const Color(0xFF06B6D4),
        items: AppI18n.supported.map((l) => DropdownMenuItem(value: l, child: Text(AppI18n.codeOf(l), style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (l) {
          if (l == null) return;
          setState(() => _locale = l);
          _telegram.setLocale(l);
        },
      ),
    );
  }

  Widget _ramModePicker() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<RamMode>(
        value: _ramMode,
        dropdownColor: const Color(0xFF111827),
        iconEnabledColor: const Color(0xFF10B981),
        items: RamMode.values.map((m) => DropdownMenuItem(value: m, child: Text(m.label, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (m) {
          if (m == null) return;
          setState(() => _ramMode = m);
          _ramGuard.setMode(m);
          _pumpQueue();
        },
      ),
    );
  }

  Widget _telegramButton() {
    final connected = _telegram.isConnected;
    final err = _telegram.state == BotConnectionState.error;
    final dotColor = connected
        ? const Color(0xFF10B981)
        : err
            ? const Color(0xFFEF4444)
            : Colors.white38;
    final unread = _telegram.unread;
    return ClickableRegion(
      child: Tooltip(
        message: connected ? 'Telegram Bot Connected' : 'Telegram Bot',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _openTelegramPanel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.smart_toy_rounded,
                        size: 18, color: Color(0xFF06B6D4)),
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                if (unread > 0)
                  Positioned(
                    right: -10,
                    top: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ramPill(bool high) {
    final decision = RamGuard.evaluate(_ramPercent, _ramMode);
    final bg = high ? const Color(0xFF450A0A) : const Color(0xFF052E1F);
    final fg = high ? const Color(0xFFFCA5A5) : const Color(0xFF34D399);
    final border = high ? const Color(0xFF7F1D1D) : const Color(0xFF065F46);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.memory, size: 16, color: fg),
        const SizedBox(width: 6),
        Text('RAM: ${_ramPercent.toString().padLeft(2, '0')}% ${_ramMode.label}',
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
        if (decision.shouldReduceConcurrency) ...[const SizedBox(width: 6), Text('DL ${decision.allowedConcurrency}', style: TextStyle(color: fg, fontSize: 10))],
      ]),
    );
  }

  Widget _tabChip(int index, String label) {
    final active = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ClickableRegion(
        child: HoverGlow(
          baseColor:
              active ? const Color(0xFF164E63) : const Color(0xFF111827),
          hoverColor:
              active ? const Color(0xFF155E75) : const Color(0xFF162033),
          borderColor:
              active ? const Color(0xFF06B6D4) : const Color(0xFF1F2937),
          hoverBorderColor: const Color(0xFF22D3EE),
          borderRadius: BorderRadius.circular(20),
          child: ChoiceChip(
            label: Text(label),
            selected: active,
            selectedColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            side: const BorderSide(color: Colors.transparent),
            labelStyle: TextStyle(
              color: active ? const Color(0xFF22D3EE) : Colors.white70,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
            onSelected: (_) => setState(() => _selectedTab = index),
          ),
        ),
      ),
    );
  }

  Widget _buildTab() {
    switch (_selectedTab) {
      case 0:
        return _buildDownloaderTab();
      case 1:
        return _buildSeriesTab();
      case 2:
        return _buildScraperTab();
      case 3:
        return _buildSchedulerTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------- Downloader UI ----------
  Widget _buildDownloaderTab() {
    final allSelected = _queue.isNotEmpty && _queue.every((i) => i.selected);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 280, maxWidth: 520),
                      child: FocusGlow(
                        child: TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(hintText: 'Paste video, document, or webpage URL...'),
                          onSubmitted: (_) => _pasteAndAdd(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: FocusGlow(
                        child: DropdownButtonFormField<DownloadQuality>(
                          initialValue: _addQuality,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Quality'),
                          items: DownloadQuality.values.map((q) => DropdownMenuItem(value: q, child: Text(q.label))).toList(),
                          onChanged: (v) => setState(() => _addQuality = v ?? _addQuality),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: FocusGlow(
                        child: DropdownButtonFormField<AppCategory>(
                          initialValue: _selectedCategory,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: AppI18n.t('category', _locale)),
                          items: AppCategories.all.map((c) => DropdownMenuItem(value: c, child: Text(c.label, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _selectedCategory = v ?? _selectedCategory),
                        ),
                      ),
                    ),
                    _btnPrimary('Paste & Add', _pasteAndAdd, color: const Color(0xFF06B6D4)),
                    _btnOutline(_scanning ? 'Scanning...' : 'Scan Page', (_scanning || _pickerOpen) ? null : _scanPage),
                    _btnOutline(_pickerOpen ? 'Opening...' : 'Attach File', (_scanning || _pickerOpen) ? null : _attachFile),
                    _filterIconButton(),
                  ],
                ),
                const SizedBox(height: 10),
                if (_scanResults.isNotEmpty) _buildScanPreviewPanel(),
                if (_scanResults.isNotEmpty) const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _clickBox(
                          child: Checkbox(
                            value: allSelected,
                            onChanged: (v) {
                              setState(() {
                                for (final i in _queue) {
                                  i.selected = v ?? false;
                                }
                              });
                            },
                          ),
                        ),
                        const Text('Select All',
                            style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    _btnPrimary('Download Selected', _downloadSelected, color: const Color(0xFF10B981)),
                    _btnOutline(AppI18n.t('pause', _locale), _pauseSelectedOrRunning),
                    _btnOutline(AppI18n.t('resume', _locale), _resumeSelected),
                    _btnOutline('Restart', _restartSelected),
                    _btnDanger('Delete Selected', _deleteSelected),
                    _btnOutline('Browse Folder', _browseFolder),
                    _btnOutline('Open Folder', _openFolder),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Save Folder: ${_saveDir.isEmpty ? '...' : _saveDir}   •   Concurrency: $_concurrencyLimit DL${RamGuard.evaluate(_ramPercent,_ramMode).shouldReduceConcurrency ? ' (Guard)' : ''}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _queue.isEmpty
                ? const Center(
                    child: Text('No downloads in queue',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: _queue.length,
                    itemBuilder: (context, i) => _downloadTile(_queue[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _downloadTile(DownloadItem item) {
    final pct = item.progress.clamp(0, 100);
    final statusColor = item.status == 'Completed'
        ? const Color(0xFF10B981)
        : item.status == 'Downloading'
            ? const Color(0xFF06B6D4)
            : item.status == 'Paused'
                ? Colors.amber
                : item.status.startsWith('Failed')
                    ? const Color(0xFFEF4444)
                    : Colors.white54;
    return Card(
      color: const Color(0xFF111827),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF1F2937)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clickBox(
              child: Checkbox(
                value: item.selected,
                onChanged: (v) => setState(() => item.selected = v ?? false),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      _badge(item.platform, const Color(0xFF06B6D4)),
                      const SizedBox(width: 6),
                      _badge(item.quality.label, const Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      _badge(item.category.label, const Color(0xFF9B72CB)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white38)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct / 100.0,
                            minHeight: 7,
                            backgroundColor: const Color(0xFF1F2937),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(statusColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${pct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(item.status,
                          style: TextStyle(fontSize: 12, color: statusColor)),
                      const SizedBox(width: 12),
                      Text(item.speed,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54)),
                      if (item.error != null && item.error!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(item.error!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFFEF4444))),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                SizedBox(
                  width: 140,
                  child: FocusGlow(
                    child: DropdownButtonFormField<DownloadQuality>(
                      initialValue: item.quality,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Quality'),
                      items: DownloadQuality.values
                          .map((q) => DropdownMenuItem(
                              value: q,
                              child: Text(q.label,
                                  style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => item.quality = v ?? item.quality),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconBtn(tooltip: 'Start/Resume', icon: Icons.play_arrow, color: const Color(0xFF10B981), onPressed: () => _startOrResume(item)),
                    _iconBtn(tooltip: 'Pause', icon: Icons.pause, color: Colors.amber, onPressed: () { _engine.pauseItem(item); _refresh(); }),
                    _iconBtn(tooltip: AppI18n.t('edit_source', _locale), icon: Icons.link, color: const Color(0xFFD96570), onPressed: () => _editSource(item)),
                    _iconBtn(tooltip: 'Restart', icon: Icons.restart_alt, color: const Color(0xFF06B6D4), onPressed: () { _engine.pauseItem(item); setState(() { item.progress=0; item.speed='--'; item.status='Queued'; item.error=null; }); _enqueueStart(item); }),
                    _iconBtn(tooltip: 'Delete', icon: Icons.delete_outline, color: const Color(0xFFEF4444), onPressed: () { _engine.pauseItem(item); setState(() => _queue.remove(item)); }),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Series UI ----------
  Widget _buildSeriesTab() {
    final allSelected =
        _episodes.isNotEmpty && _episodes.every((e) => e.selected);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FocusGlow(
                        child: TextField(
                          controller: _seriesUrlController,
                          decoration: const InputDecoration(
                            hintText:
                                'YouTube Playlist, Channel, or Show URL...',
                          ),
                          onSubmitted: (_) => _fetchEpisodes(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: FocusGlow(
                        child: DropdownButtonFormField<DownloadQuality>(
                          initialValue: _seriesQuality,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Quality'),
                          items: DownloadQuality.values
                              .map((q) => DropdownMenuItem(
                                  value: q, child: Text(q.label)))
                              .toList(),
                          onChanged: (v) => setState(
                              () => _seriesQuality = v ?? _seriesQuality),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _btnPrimary('Fetch Episodes',
                        _fetchingEpisodes ? null : _fetchEpisodes,
                        color: const Color(0xFF06B6D4)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _clickBox(
                      child: Checkbox(
                        value: allSelected,
                        onChanged: _episodes.isEmpty
                            ? null
                            : (v) {
                                setState(() {
                                  for (final e in _episodes) {
                                    e.selected = v ?? false;
                                  }
                                });
                              },
                      ),
                    ),
                    const Text('Select All'),
                    const SizedBox(width: 12),
                    _btnPrimary(
                        'Download Selected / Season',
                        _episodes.isEmpty
                            ? null
                            : () => _downloadSelectedEpisodes(startNow: true),
                        color: const Color(0xFF10B981)),
                    if (_fetchingEpisodes) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      const Text('Fetching...',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ],
                ),
                if (_seriesError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_seriesError!,
                        style: const TextStyle(
                            color: Color(0xFFEF4444), fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _episodes.isEmpty
                ? const Center(
                    child: Text('No episodes loaded',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: _episodes.length,
                    itemBuilder: (context, i) {
                      final ep = _episodes[i];
                      return Card(
                        color: const Color(0xFF111827),
                        margin: const EdgeInsets.only(bottom: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF1F2937)),
                        ),
                        child: _clickBox(
                          child: CheckboxListTile(
                            value: ep.selected,
                            onChanged: (v) =>
                                setState(() => ep.selected = v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text('${ep.index}. ${ep.title}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(ep.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white38)),
                            secondary:
                                _badge(ep.duration, const Color(0xFF06B6D4)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ---------- Scraper UI ----------
  List<LeadEntry> get _filteredLeads => _leadResults.where((l) => l.matches(_leadFilter)).toList();

  Widget _buildScraperTab() {
    final visible = _filteredLeads;
    final capped = visible.take(_leadPreviewLimit).toList();
    final allSelected = visible.isNotEmpty && visible.every((l) => l.selected);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FocusGlow(
                  child: TextField(
                    controller: _scrapeUrlController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Target website URL(s) — space or newline separated...'),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _btnPrimary('Scrape', _scraping ? null : _runScrape, color: const Color(0xFF06B6D4)),
                  _btnOutline('Import Leads JSON', (_scraping || _pickerOpen) ? null : _importLeadsJson),
                  _leadFilterIconButton(),
                  _btnOutline('Export CSV', _leadResults.isEmpty ? null : _exportScrapeCsv),
                  _btnDanger('Delete Selected', _leadResults.any((l)=>l.selected) ? _deleteSelectedLeads : null),
                  _btnPrimary('Send Media to Downloader', _leadResults.any((l)=>_looksLikeMedia(l.website)) ? _sendScrapeMediaToDownloader : null, color: const Color(0xFF10B981)),
                  if (_scraping) const Padding(padding: EdgeInsets.only(left:8), child: SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2))),
                ]),
                if (_scrapeError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_scrapeError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _leadResults.isEmpty
                ? Center(child: _scraping ? const CircularProgressIndicator() : const Text('No leads found', style: TextStyle(color: Colors.white38)))
                : _panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        _clickBox(child: Checkbox(value: allSelected, onChanged: (v)=>setState((){for(final l in visible){l.selected=v??false;}}))),
                        Expanded(child: Text('${visible.length} visible / ${_leadResults.length} total (showing ${capped.length})', style: const TextStyle(color: Colors.white54, fontSize: 12))),
                        if (visible.length > capped.length) TextButton(onPressed: ()=>setState(()=>_leadPreviewLimit += 200), child: Text('Show more (${visible.length - capped.length})')),
                      ]),
                      const SizedBox(height: 8),
                      Expanded(child: ListView.builder(
                        itemCount: capped.length,
                        itemBuilder: (c, i) {
                          final l = capped[i];
                          return Container(margin: const EdgeInsets.only(bottom:6), padding: const EdgeInsets.symmetric(horizontal:8, vertical:6), decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1F2937))), child: Row(children: [
                            _clickBox(child: Checkbox(value: l.selected, onChanged: (v)=>setState(()=>l.selected=v??false))),
                            SizedBox(width:120, child: Text(l.name, maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize:12))),
                            SizedBox(width:170, child: Text(l.email, maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize:12))),
                            SizedBox(width:120, child: Text(l.phone, maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize:12))),
                            Expanded(child: Text(l.website.isNotEmpty ? l.website : l.social, maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize:12, color: Colors.white70))),
                            SizedBox(width:100, child: Text(l.category, maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize:11, color: Colors.white54))),
                          ]));
                        },
                      )),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------- Scheduler UI ----------
  Widget _buildSchedulerTab() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _panel(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _btnPrimary('Add Scheduled Job', _addScheduledJob,
                    color: const Color(0xFF06B6D4)),
                SizedBox(
                  width: 420,
                  child: FocusGlow(
                    child: TextField(
                      controller: _seriesUrlController,
                      decoration: const InputDecoration(
                        labelText:
                            'Series Watchlist URL (for Series Watchlist Check jobs)',
                        hintText:
                            'Used by scheduler when running Series Watchlist Check',
                      ),
                      onChanged: (v) => _seriesWatchUrl = v.trim(),
                    ),
                  ),
                ),
                Text('Scheduler checks every 30s',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _jobs.isEmpty
                ? const Center(
                    child: Text('No scheduled jobs',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: _jobs.length,
                    itemBuilder: (context, i) => _jobTile(_jobs[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _jobTile(ScheduledJob job) {
    Color statusColor;
    switch (job.status) {
      case 'Armed':
        statusColor = const Color(0xFF06B6D4);
        break;
      case 'Running':
        statusColor = Colors.amber;
        break;
      case 'Completed':
        statusColor = const Color(0xFF10B981);
        break;
      default:
        statusColor = Colors.white54;
    }
    return Card(
      color: const Color(0xFF111827),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF1F2937)),
      ),
      child: ListTile(
        title: Text(job.type.label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
                'Next: ${_fmtDt(job.nextRun)}   •   Repeat: ${job.interval.label}   •   Runs: ${job.runCount}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.white60)),
            if (job.lastRun != null)
              Text('Last: ${_fmtDt(job.lastRun!)}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white38)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _badge(job.status, statusColor),
            const SizedBox(width: 8),
            _iconBtn(
              tooltip: 'Remove',
              icon: Icons.delete_outline,
              color: const Color(0xFFEF4444),
              onPressed: () => setState(() => _jobs.remove(job)),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // ---------- Shared widgets ----------
  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: child,
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _filterIconButton() {
    return PopupMenuButton<MediaFilter>(
      tooltip: 'Filter media',
      onSelected: (f) => setState(() => _mediaFilter = f),
      itemBuilder: (_) => MediaFilter.values.map((f) => PopupMenuItem(value: f, child: Row(children: [Icon(_mediaFilter==f?Icons.radio_button_checked:Icons.radio_button_off, size:16, color: const Color(0xFF06B6D4)), const SizedBox(width:8), Flexible(child: Text(f.label))]))).toList(),
      child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha:0.5))), child: const Icon(Icons.filter_list, color: Color(0xFF06B6D4), size: 20)),
    );
  }

  Widget _leadFilterIconButton() {
    return PopupMenuButton<String>(
      tooltip: 'Filter leads',
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value:'email', checked:_leadFilter.mustHaveEmail, child: const Text('Must have email')),
        CheckedPopupMenuItem(value:'phone', checked:_leadFilter.mustHavePhone, child: const Text('Must have phone')),
        CheckedPopupMenuItem(value:'website', checked:_leadFilter.hasWebsite, child: const Text('Has website')),
        CheckedPopupMenuItem(value:'social', checked:_leadFilter.hasSocial, child: const Text('Has social links')),
        const PopupMenuDivider(),
        PopupMenuItem(value:'keyword', child: Text(_leadFilter.keyword.isEmpty ? 'Set keyword filter...' : 'Keyword: ${_leadFilter.keyword}')),
        PopupMenuItem(value:'clear', child: const Text('Clear filters')),
      ],
      onSelected: (v) async {
        if (v=='email') setState(()=>_leadFilter.mustHaveEmail=!_leadFilter.mustHaveEmail);
        if (v=='phone') setState(()=>_leadFilter.mustHavePhone=!_leadFilter.mustHavePhone);
        if (v=='website') setState(()=>_leadFilter.hasWebsite=!_leadFilter.hasWebsite);
        if (v=='social') setState(()=>_leadFilter.hasSocial=!_leadFilter.hasSocial);
        if (v=='clear') setState((){_leadFilter.mustHaveEmail=false;_leadFilter.mustHavePhone=false;_leadFilter.hasWebsite=false;_leadFilter.hasSocial=false;_leadFilter.keyword='';});
        if (v=='keyword') {
          final c = TextEditingController(text:_leadFilter.keyword);
          final kw = await showDialog<String>(context: context, builder: (ctx)=>AlertDialog(title: const Text('Keyword filter'), content: TextField(controller:c, decoration: const InputDecoration(hintText:'email domain, name, niche...')), actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()), child: const Text('Apply'))]));
          if (kw!=null) setState(()=>_leadFilter.keyword=kw);
        }
      },
      child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha:0.5))), child: const Icon(Icons.filter_alt, color: Color(0xFF06B6D4), size: 20)),
    );
  }

  Widget _buildScanPreviewPanel() {
    final visible = _filteredScanResults;
    final capped = visible.take(_scanPreviewLimit).toList();
    final allSelected = visible.isNotEmpty && visible.every((i)=>i.selected);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF0B1220), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1F2937))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.playlist_add_check, color: Color(0xFF06B6D4), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Scanned Media (${visible.length}/${_scanResults.length})', style: const TextStyle(fontWeight: FontWeight.w600))),
          _clickBox(child: Checkbox(value: allSelected, onChanged: (v)=>setState((){for(final i in visible){i.selected=v??false;}}))),
          const Text('Select all filtered', style: TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(width: 8),
          _btnPrimary('Download Selected', visible.any((i)=>i.selected) ? _downloadSelectedScanResults : null, color: const Color(0xFF10B981)),
        ]),
        const SizedBox(height: 8),
        SizedBox(height: 220, child: ListView.builder(
          itemCount: capped.length + (visible.length > capped.length ? 1 : 0),
          itemBuilder: (c,i){
            if (i >= capped.length) {
              return Center(child: TextButton(onPressed: ()=>setState(()=>_scanPreviewLimit += 200), child: Text('Show more (${visible.length - capped.length} remaining)')));
            }
            final m=capped[i];
            return Container(margin: const EdgeInsets.only(bottom:6), padding: const EdgeInsets.symmetric(horizontal:8, vertical:6), decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1F2937))), child: Row(children:[_clickBox(child: Checkbox(value:m.selected, onChanged:(v)=>setState(()=>m.selected=v??false))), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(m.title, maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize:12, fontWeight: FontWeight.w500)), Text(m.url, maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize:10, color: Colors.white38))])), const SizedBox(width:8), _badge(m.format, const Color(0xFF06B6D4)), if(m.tag.isNotEmpty) ...[const SizedBox(width:6), _badge(m.tag, const Color(0xFFF59E0B))]]));
          },
        )),
      ]),
    );
  }

  Widget _clickBox({required Widget child}) =>
      ClickableRegion(child: child);

  Widget _iconBtn({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ClickableRegion(
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
        splashRadius: 18,
        hoverColor: color.withValues(alpha: 0.12),
      ),
    );
  }

  Widget _btnPrimary(String label, VoidCallback? onPressed,
      {required Color color}) {
    final enabled = onPressed != null;
    return ClickableRegion(
      enabled: enabled,
      child: _HoverButton(
        onPressed: onPressed,
        baseColor: enabled ? color : color.withValues(alpha: 0.3),
        hoverColor: Color.lerp(color, Colors.white, 0.12) ?? color,
        borderColor: color.withValues(alpha: 0.9),
        hoverBorderColor: Colors.white70,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black)),
        ),
      ),
    );
  }

  Widget _btnOutline(String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return ClickableRegion(
      enabled: enabled,
      child: _HoverButton(
        onPressed: onPressed,
        baseColor: Colors.transparent,
        hoverColor: const Color(0xFF0B2230),
        borderColor: const Color(0xFF1F2937),
        hoverBorderColor: const Color(0xFF22D3EE),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(label,
              style: TextStyle(
                  color: enabled
                      ? const Color(0xFF22D3EE)
                      : const Color(0xFF22D3EE).withValues(alpha: 0.4))),
        ),
      ),
    );
  }

  Widget _btnDanger(String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return ClickableRegion(
      enabled: enabled,
      child: _HoverButton(
        onPressed: onPressed,
        baseColor: Colors.transparent,
        hoverColor: const Color(0xFF2A1010),
        borderColor: const Color(0xFFEF4444),
        hoverBorderColor: const Color(0xFFFCA5A5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(label,
              style: TextStyle(
                  color: enabled
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFEF4444).withValues(alpha: 0.4))),
        ),
      ),
    );
  }

}

class _HoverButton extends StatefulWidget {
  const _HoverButton({
    required this.child,
    required this.onPressed,
    required this.baseColor,
    required this.hoverColor,
    required this.borderColor,
    required this.hoverBorderColor,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Color baseColor;
  final Color hoverColor;
  final Color borderColor;
  final Color hoverBorderColor;

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final hover = _hover && enabled;
    return MouseRegion(
      cursor: enabled ? HandCursorProvider.cursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: hover ? widget.hoverColor : widget.baseColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: hover ? widget.hoverBorderColor : widget.borderColor),
            boxShadow: hover
                ? [
                    BoxShadow(
                      color: widget.hoverBorderColor.withValues(alpha: 0.25),
                      blurRadius: 10,
                      spreadRadius: 0,
                    )
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------- Models ----------

enum JobType { downloadAll, seriesWatch, leadScraper }

extension JobTypeX on JobType {
  String get label {
    switch (this) {
      case JobType.downloadAll:
        return 'Download All Queue';
      case JobType.seriesWatch:
        return 'Series Watchlist Check';
      case JobType.leadScraper:
        return 'Lead Scraper Job';
    }
  }
}

enum RepeatInterval { once, hourly, daily }

extension RepeatIntervalX on RepeatInterval {
  String get label {
    switch (this) {
      case RepeatInterval.once:
        return 'Once';
      case RepeatInterval.hourly:
        return 'Hourly';
      case RepeatInterval.daily:
        return 'Daily';
    }
  }

  DateTime nextAfter(DateTime from) {
    switch (this) {
      case RepeatInterval.once:
        return from;
      case RepeatInterval.hourly:
        return from.add(const Duration(hours: 1));
      case RepeatInterval.daily:
        return from.add(const Duration(days: 1));
    }
  }
}

class ScheduledJob {
  final String id;
  final JobType type;
  DateTime nextRun;
  final RepeatInterval interval;
  String status;
  DateTime? lastRun;
  int runCount;

  ScheduledJob({
    required this.id,
    required this.type,
    required this.nextRun,
    required this.interval,
    required this.status,
    this.lastRun,
    this.runCount = 0,
  });
}
