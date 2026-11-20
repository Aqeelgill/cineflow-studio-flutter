import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'engine/download_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CineFlowApp());
}

class CineFlowApp extends StatelessWidget {
  const CineFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = const ColorScheme.dark(
      primary: Color(0xFF06B6D4),
      secondary: Color(0xFF10B981),
      surface: Color(0xFF111827),
      error: Color(0xFFEF4444),
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1F2937)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1F2937)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF06B6D4)),
          ),
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
  bool _scrapeEmails = true;
  bool _scrapePhones = true;
  bool _scrapeSocial = true;
  bool _scrapeMedia = true;
  final List<ScrapeResult> _scrapeResults = [];

  // Scheduler tab
  final List<ScheduledJob> _jobs = [];
  Timer? _schedulerTimer;
  String _seriesWatchUrl = '';

  @override
  void initState() {
    super.initState();
    _initDir();
    _schedulerTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tickScheduler());
  }

  Future<void> _initDir() async {
    final dir = await _engine.getDefaultSaveDirectory();
    if (mounted) setState(() => _saveDir = dir);
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
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
        ));
      }
      _urlController.clear();
    });
  }

  Future<void> _scanPage() async {
    final url = _urlController.text.trim();
    if (!url.startsWith('http')) {
      _showSnack('Paste a webpage URL to scan');
      return;
    }
    _showSnack('Scanning webpage...');
    try {
      final links = await _engine.scanWebpage(url);
      setState(() {
        for (final l in links) {
          _queue.add(DownloadItem(
            id: _newId(l),
            url: l,
            title: Uri.tryParse(l)?.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => l) ?? l,
            platform: _engine.isDirectFile(l) ? 'Direct File' : 'Scanned',
            quality: _addQuality,
          ));
        }
      });
      _showSnack('${links.length} links found');
    } catch (e) {
      _showSnack('Scan error: $e');
    }
  }

  Future<void> _attachFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final path = files.single.path;
      if (path == null) {
        _showSnack('Could not read selected file path');
        return;
      }
      final links = await _engine.parseFileLinks(path);
      setState(() {
        for (final l in links) {
          _queue.add(DownloadItem(
            id: _newId(l),
            url: l,
            title: Uri.tryParse(l)
                    ?.pathSegments
                    .lastWhere((s) => s.isNotEmpty, orElse: () => l) ??
                l,
            platform: _engine.isDirectFile(l) ? 'Direct File' : 'Parsed Link',
            quality: _addQuality,
          ));
        }
      });
      _showSnack('${links.length} links extracted');
    } catch (e) {
      _showSnack('Attach/parse error: $e');
    }
  }

  Future<void> _browseFolder() async {
    try {
      final uri = await FilePicker.pickDirectory();
      if (uri == null) return;
      String dir;
      if (uri.scheme == 'file' || uri.scheme.isEmpty) {
        try {
          dir = uri.toFilePath();
        } catch (_) {
          dir = uri.path;
        }
      } else {
        dir = uri.toString();
      }
      if (dir.isNotEmpty) {
        setState(() => _saveDir = dir);
      }
    } catch (e) {
      _showSnack('Folder picker error: $e');
    }
  }

  void _downloadSelected() {
    final items = _queue.where((i) => i.selected).toList();
    if (items.isEmpty) {
      _showSnack('No items selected');
      return;
    }
    for (final item in items) {
      _startOrResume(item);
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
    final targets = _queue.where((i) => i.selected || i.status == 'Downloading').toList();
    for (final item in targets) {
      _engine.pauseItem(item);
    }
    _refresh();
  }

  void _resumeSelected() {
    final items = _queue.where((i) => i.selected && (i.status == 'Paused' || i.status.startsWith('Failed'))).toList();
    if (items.isEmpty) {
      _showSnack('No paused/failed selected items');
      return;
    }
    for (final item in items) {
      _startOrResume(item);
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
      _engine.startDownload(item, _saveDir, _refresh);
    }
  }

  void _startOrResume(DownloadItem item) {
    if (item.status == 'Completed') return;
    _engine.startDownload(item, _saveDir, _refresh);
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
      );
      _queue.add(item);
      if (startNow) {
        _engine.startDownload(item, _saveDir, _refresh);
      }
    }
    _showSnack('${selected.length} episodes sent to Downloader');
    setState(() => _selectedTab = 0);
  }

  // ---------- Tab 3: Lead Scraper ----------
  Future<void> _runScrape() async {
    final raw = _scrapeUrlController.text.trim();
    if (raw.isEmpty) {
      _showSnack('Enter target website URL(s)');
      return;
    }
    final urlReg = RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false);
    final urls = urlReg.allMatches(raw).map((m) => m.group(0)!).toSet().toList();
    if (urls.isEmpty) {
      _showSnack('No valid URLs found');
      return;
    }
    setState(() {
      _scraping = true;
      _scrapeError = null;
      _scrapeResults.clear();
    });
    try {
      final results = <ScrapeResult>[];
      final seen = <String>{};
      for (final u in urls) {
        final res = await http.get(Uri.parse(u), headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        });
        if (res.statusCode != 200) continue;
        final body = res.body;
        final doc = html_parser.parse(body);
        final base = Uri.parse(u);

        if (_scrapeEmails) {
          final re = RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false);
          for (final m in re.allMatches(body)) {
            final v = m.group(0)!;
            final key = 'email:$v';
            if (seen.add(key)) {
              results.add(ScrapeResult(type: 'Email', value: v, source: u));
            }
          }
          for (final a in doc.querySelectorAll('a[href^="mailto:"]')) {
            final href = a.attributes['href'] ?? '';
            final v = href.replaceFirst(RegExp(r'^mailto:', caseSensitive: false), '').split('?').first;
            if (v.isNotEmpty && seen.add('email:$v')) {
              results.add(ScrapeResult(type: 'Email', value: v, source: u));
            }
          }
        }

        if (_scrapePhones) {
          final re = RegExp(r'(?:\+?\d[\d\s().-]{7,}\d)');
          for (final m in re.allMatches(body)) {
            final v = m.group(0)!.trim();
            final digits = v.replaceAll(RegExp(r'\D'), '');
            if (digits.length < 7) continue;
            final key = 'phone:$digits';
            if (seen.add(key)) {
              results.add(ScrapeResult(type: 'Phone', value: v, source: u));
            }
          }
        }

        if (_scrapeSocial) {
          for (final a in doc.querySelectorAll('a[href]')) {
            final href = a.attributes['href'] ?? '';
            try {
              final abs = base.resolve(href).toString();
              final low = abs.toLowerCase();
              if (low.contains('facebook.com') ||
                  low.contains('twitter.com') ||
                  low.contains('x.com') ||
                  low.contains('instagram.com') ||
                  low.contains('linkedin.com') ||
                  low.contains('youtube.com') ||
                  low.contains('tiktok.com') ||
                  low.contains('wa.me') ||
                  low.contains('t.me')) {
                final key = 'social:$abs';
                if (seen.add(key)) {
                  results.add(ScrapeResult(type: 'Social', value: abs, source: u));
                }
              }
            } catch (_) {}
          }
        }

        if (_scrapeMedia) {
          for (final el in doc.querySelectorAll('a[href], img[src], video[src], source[src]')) {
            final rawLink = el.attributes['href'] ?? el.attributes['src'] ?? '';
            if (rawLink.isEmpty) continue;
            try {
              final abs = base.resolve(rawLink).toString();
              final path = Uri.parse(abs).path.toLowerCase();
              if (UniversalDownloadEngine.directExts.any((ext) => path.endsWith(ext))) {
                final key = 'media:$abs';
                if (seen.add(key)) {
                  results.add(ScrapeResult(type: 'Media/Doc', value: abs, source: u));
                }
              }
            } catch (_) {}
          }
        }
      }
      setState(() {
        _scrapeResults.addAll(results);
        _scraping = false;
      });
      _showSnack('${results.length} results found');
    } catch (e) {
      setState(() {
        _scraping = false;
        _scrapeError = e.toString();
      });
    }
  }

  String _csvEscape(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  Future<void> _exportScrapeCsv() async {
    if (_scrapeResults.isEmpty) {
      _showSnack('No results to export');
      return;
    }
    try {
      final buf = StringBuffer();
      buf.writeln('type,value,source');
      for (final r in _scrapeResults) {
        buf.writeln(
            '${_csvEscape(r.type)},${_csvEscape(r.value)},${_csvEscape(r.source)}');
      }
      final bytes = utf8.encode(buf.toString());
      String? saved;
      try {
        final uri = await FilePicker.saveFile(
          fileName: 'leads_export.csv',
          bytes: Uint8List.fromList(bytes),
          mimeType: 'text/csv',
          dialogTitle: 'Export CSV',
        );
        if (uri != null) {
          if (uri.scheme == 'file' || uri.scheme.isEmpty) {
            try {
              saved = uri.toFilePath();
            } catch (_) {
              saved = uri.toString();
            }
          } else {
            saved = uri.toString();
          }
        }
      } catch (_) {
        saved = null;
      }
      if (saved == null || saved.isEmpty) {
        final fallback =
            '$_saveDir${Platform.pathSeparator}leads_export_${DateTime.now().millisecondsSinceEpoch}.csv';
        final file = File(fallback);
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
        saved = file.path;
      }
      _showSnack('Exported: $saved');
    } catch (e) {
      _showSnack('Export error: $e');
    }
  }

  void _sendScrapeMediaToDownloader() {
    final media = _scrapeResults.where((r) => r.type == 'Media/Doc').toList();
    if (media.isEmpty) {
      _showSnack('No media/docs found');
      return;
    }
    setState(() {
      for (final m in media) {
        final exists = _queue.any((q) => q.url == m.value);
        if (exists) continue;
        _queue.add(DownloadItem(
          id: _newId(m.value),
          url: m.value,
          title: Uri.tryParse(m.value)?.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => m.value) ?? m.value,
          platform: 'Scraped Media',
          quality: _addQuality,
        ));
      }
      _selectedTab = 0;
    });
    _showSnack('${media.length} media links sent to Downloader');
  }

  // ---------- Tab 4: Scheduler ----------
  Future<void> _addScheduledJob() async {
    final type = await showDialog<JobType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Job Type'),
        children: JobType.values.map((t) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, t),
          child: Text(t.label),
        )).toList(),
      ),
    );
    if (type == null || !mounted) return;

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 0)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 1))),
    );
    if (time == null || !mounted) return;
    DateTime scheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (scheduled.isBefore(DateTime.now())) {
      scheduled = DateTime.now().add(const Duration(minutes: 1));
    }

    final interval = await showDialog<RepeatInterval>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Repeat Interval'),
        children: RepeatInterval.values.map((r) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, r),
          child: Text(r.label),
        )).toList(),
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
              _engine.startDownload(item, _saveDir, _refresh);
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
        _engine.startDownload(item, _saveDir, _refresh);
      }
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            const Text('CineFlow Studio',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF06B6D4)),
              ),
              child: const Text('DARK FIGMA STUDIO',
                  style: TextStyle(fontSize: 10, color: Color(0xFF22D3EE))),
            ),
          ],
        ),
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
                  _tabChip(0, '1. Universal Downloader'),
                  _tabChip(1, '2. Series & Drama Watcher'),
                  _tabChip(2, '3. Lead Generator & Media Scraper'),
                  _tabChip(3, '4. Task Scheduler'),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildTab()),
        ],
      ),
    );
  }

  Widget _tabChip(int index, String label) {
    final active = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        selectedColor: const Color(0xFF164E63),
        backgroundColor: const Color(0xFF111827),
        side: BorderSide(color: active ? const Color(0xFF06B6D4) : const Color(0xFF1F2937)),
        labelStyle: TextStyle(
          color: active ? const Color(0xFF22D3EE) : Colors.white70,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
        onSelected: (_) => setState(() => _selectedTab = index),
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          hintText: 'Paste video, document, or webpage URL...',
                        ),
                        onSubmitted: (_) => _pasteAndAdd(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<DownloadQuality>(
                        initialValue: _addQuality,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Quality'),
                        items: DownloadQuality.values
                            .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
                            .toList(),
                        onChanged: (v) => setState(() => _addQuality = v ?? _addQuality),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _btnPrimary('Paste & Add', _pasteAndAdd, color: const Color(0xFF06B6D4)),
                    const SizedBox(width: 6),
                    _btnOutline('Scan Page', _scanPage),
                    const SizedBox(width: 6),
                    _btnOutline('Attach File', _attachFile),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: allSelected,
                          onChanged: (v) {
                            setState(() {
                              for (final i in _queue) {
                                i.selected = v ?? false;
                              }
                            });
                          },
                        ),
                        const Text('Select All', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    _btnPrimary('Download Selected', _downloadSelected, color: const Color(0xFF10B981)),
                    _btnOutline('Pause', _pauseSelectedOrRunning),
                    _btnOutline('Resume', _resumeSelected),
                    _btnOutline('Restart', _restartSelected),
                    _btnDanger('Delete Selected', _deleteSelected),
                    _btnOutline('Browse Folder', _browseFolder),
                    _btnOutline('Open Folder', _openFolder),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Save Folder: ${_saveDir.isEmpty ? '...' : _saveDir}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _queue.isEmpty
                ? const Center(child: Text('No downloads in queue', style: TextStyle(color: Colors.white38)))
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
            Checkbox(
              value: item.selected,
              onChanged: (v) => setState(() => item.selected = v ?? false),
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
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      _badge(item.platform, const Color(0xFF06B6D4)),
                      const SizedBox(width: 6),
                      _badge(item.quality.label, const Color(0xFF10B981)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white38)),
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
                            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${pct.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(item.status, style: TextStyle(fontSize: 12, color: statusColor)),
                      const SizedBox(width: 12),
                      Text(item.speed, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      if (item.error != null && item.error!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(item.error!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
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
                  child: DropdownButtonFormField<DownloadQuality>(
                    initialValue: item.quality,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Quality'),
                    items: DownloadQuality.values
                        .map((q) => DropdownMenuItem(value: q, child: Text(q.label, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() => item.quality = v ?? item.quality),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Start/Resume',
                      icon: const Icon(Icons.play_arrow, color: Color(0xFF10B981)),
                      onPressed: () => _startOrResume(item),
                    ),
                    IconButton(
                      tooltip: 'Pause',
                      icon: const Icon(Icons.pause, color: Colors.amber),
                      onPressed: () {
                        _engine.pauseItem(item);
                        _refresh();
                      },
                    ),
                    IconButton(
                      tooltip: 'Restart',
                      icon: const Icon(Icons.restart_alt, color: Color(0xFF06B6D4)),
                      onPressed: () {
                        _engine.pauseItem(item);
                        setState(() {
                          item.progress = 0;
                          item.speed = '--';
                          item.status = 'Queued';
                          item.error = null;
                        });
                        _engine.startDownload(item, _saveDir, _refresh);
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                      onPressed: () {
                        _engine.pauseItem(item);
                        setState(() => _queue.remove(item));
                      },
                    ),
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
    final allSelected = _episodes.isNotEmpty && _episodes.every((e) => e.selected);
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
                      child: TextField(
                        controller: _seriesUrlController,
                        decoration: const InputDecoration(
                          hintText: 'YouTube Playlist, Channel, or Show URL...',
                        ),
                        onSubmitted: (_) => _fetchEpisodes(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<DownloadQuality>(
                        initialValue: _seriesQuality,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Quality'),
                        items: DownloadQuality.values
                            .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
                            .toList(),
                        onChanged: (v) => setState(() => _seriesQuality = v ?? _seriesQuality),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _btnPrimary('Fetch Episodes', _fetchingEpisodes ? null : _fetchEpisodes, color: const Color(0xFF06B6D4)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Checkbox(
                      value: allSelected,
                      onChanged: _episodes.isEmpty ? null : (v) {
                        setState(() {
                          for (final e in _episodes) {
                            e.selected = v ?? false;
                          }
                        });
                      },
                    ),
                    const Text('Select All'),
                    const SizedBox(width: 12),
                    _btnPrimary('Download Selected / Season', _episodes.isEmpty ? null : () => _downloadSelectedEpisodes(startNow: true),
                        color: const Color(0xFF10B981)),
                    if (_fetchingEpisodes) ...[
                      const SizedBox(width: 12),
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      const Text('Fetching...', style: TextStyle(color: Colors.white54)),
                    ],
                  ],
                ),
                if (_seriesError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_seriesError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _episodes.isEmpty
                ? const Center(child: Text('No episodes loaded', style: TextStyle(color: Colors.white38)))
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
                        child: CheckboxListTile(
                          value: ep.selected,
                          onChanged: (v) => setState(() => ep.selected = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text('${ep.index}. ${ep.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(ep.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white38)),
                          secondary: _badge(ep.duration, const Color(0xFF06B6D4)),
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
  Widget _buildScraperTab() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _scrapeUrlController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Target website URL(s) — space or newline separated...',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    _checkLabel('Emails', _scrapeEmails, (v) => setState(() => _scrapeEmails = v)),
                    _checkLabel('Phone Numbers', _scrapePhones, (v) => setState(() => _scrapePhones = v)),
                    _checkLabel('Social Links', _scrapeSocial, (v) => setState(() => _scrapeSocial = v)),
                    _checkLabel('Downloadable Media/Docs', _scrapeMedia, (v) => setState(() => _scrapeMedia = v)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _btnPrimary('Scrape', _scraping ? null : _runScrape, color: const Color(0xFF06B6D4)),
                    _btnOutline('Export CSV', _scrapeResults.isEmpty ? null : _exportScrapeCsv),
                    _btnPrimary('Send Media to Downloader', _scrapeResults.any((r) => r.type == 'Media/Doc') ? _sendScrapeMediaToDownloader : null,
                        color: const Color(0xFF10B981)),
                    if (_scraping) ...[
                      const SizedBox(width: 8),
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 6),
                      const Text('Scraping...', style: TextStyle(color: Colors.white54)),
                    ],
                  ],
                ),
                if (_scrapeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_scrapeError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _scrapeResults.isEmpty
                ? const Center(child: Text('No scrape results', style: TextStyle(color: Colors.white38)))
                : _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_scrapeResults.length} results', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(const Color(0xFF0B1220)),
                                dataRowMinHeight: 36,
                                dataRowMaxHeight: 56,
                                columns: const [
                                  DataColumn(label: Text('Type')),
                                  DataColumn(label: Text('Value')),
                                  DataColumn(label: Text('Source')),
                                ],
                                rows: _scrapeResults.map((r) {
                                  return DataRow(cells: [
                                    DataCell(_badge(r.type, _typeColor(r.type))),
                                    DataCell(SizedBox(
                                      width: 420,
                                      child: SelectableText(r.value,
                                          maxLines: 2,
                                          style: const TextStyle(fontSize: 12)),
                                    )),
                                    DataCell(SizedBox(
                                      width: 260,
                                      child: Text(r.source,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                    )),
                                  ]);
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Email':
        return const Color(0xFF06B6D4);
      case 'Phone':
        return const Color(0xFF10B981);
      case 'Social':
        return Colors.purpleAccent;
      case 'Media/Doc':
        return Colors.orangeAccent;
      default:
        return Colors.white54;
    }
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
                _btnPrimary('Add Scheduled Job', _addScheduledJob, color: const Color(0xFF06B6D4)),
                SizedBox(
                  width: 420,
                  child: TextField(
                    controller: _seriesUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Series Watchlist URL (for Series Watchlist Check jobs)',
                      hintText: 'Used by scheduler when running Series Watchlist Check',
                    ),
                    onChanged: (v) => _seriesWatchUrl = v.trim(),
                  ),
                ),
                Text('Scheduler checks every 30s', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _jobs.isEmpty
                ? const Center(child: Text('No scheduled jobs', style: TextStyle(color: Colors.white38)))
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
        title: Text(job.type.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Next: ${_fmtDt(job.nextRun)}   •   Repeat: ${job.interval.label}   •   Runs: ${job.runCount}',
                style: const TextStyle(fontSize: 12, color: Colors.white60)),
            if (job.lastRun != null)
              Text('Last: ${_fmtDt(job.lastRun!)}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _badge(job.status, statusColor),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
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
      child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _btnPrimary(String label, VoidCallback? onPressed, {required Color color}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        disabledBackgroundColor: color.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _btnOutline(String label, VoidCallback? onPressed) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF22D3EE),
        side: const BorderSide(color: Color(0xFF1F2937)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Widget _btnDanger(String label, VoidCallback? onPressed) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFEF4444),
        side: const BorderSide(color: Color(0xFFEF4444)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Widget _checkLabel(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          Text(label),
        ],
      ),
    );
  }
}

// ---------- Models ----------
class ScrapeResult {
  final String type;
  final String value;
  final String source;
  ScrapeResult({required this.type, required this.value, required this.source});
}

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
