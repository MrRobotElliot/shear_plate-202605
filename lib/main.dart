import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shear_plate/settings_page.dart';
import 'package:window_manager/window_manager.dart';

bool get _supportsNativeWindow {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supportsNativeWindow) {
    await windowManager.ensureInitialized();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final List<String> _clipboardHistory = [];
  /// Index into [_getFilteredHistory()]; null means no row selected.
  int? _selectedFilteredIndex;
  bool _alwaysOnTop = false;
  String? _lastClipboardContent;
  Timer? _clipboardTimer;
  late TextEditingController _searchController;
  final ScrollController _historyScrollController = ScrollController();
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text;
        _selectedFilteredIndex = null;
      });
    });
    _loadClipboardHistory();
    _startClipboardListener();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _historyScrollController.dispose();
    _clipboardTimer?.cancel();
    super.dispose();
  }

  List<String> _getFilteredHistory() {
    if (_searchText.isEmpty) {
      return _clipboardHistory;
    }
    return _clipboardHistory
        .where((item) => item.toLowerCase().contains(_searchText.toLowerCase()))
        .toList();
  }

  /// Collapsed list preview: truncate by grapheme count, append ellipsis.
  static const int _kPreviewMaxGraphemes = 80;

  InlineSpan _clipboardCollapsedSpan(String full, {bool isSelected = false}) {
    final g = full.characters;
    if (g.length <= _kPreviewMaxGraphemes || isSelected) {
      return TextSpan(text: full);
    }
    return TextSpan(
      children: [
        TextSpan(text: g.take(_kPreviewMaxGraphemes).toString()),
        TextSpan(
          text: '······',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// Inserts or moves [text] to the front of history.
  void _bumpClipboardEntry(String text) {
    _clipboardHistory.remove(text);
    _clipboardHistory.insert(0, text);
  }

  /// Toggles whether the app window stays above other windows (desktop only).
  Future<void> _toggleWindowAlwaysOnTop() async {
    if (!_supportsNativeWindow) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅桌面端支持窗口置顶')),
      );
      return;
    }

    final next = !_alwaysOnTop;
    setState(() => _alwaysOnTop = next);
    try {
      await windowManager.setAlwaysOnTop(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _alwaysOnTop = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法切换窗口置顶：$e')),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const SettingsPage(),
      ),
    );
  }

  void _startClipboardListener() {
    _clipboardTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      String? clipboardText = data?.text?.trim();

      if (clipboardText != null && 
          clipboardText.isNotEmpty && 
          clipboardText != _lastClipboardContent) {
        _lastClipboardContent = clipboardText;
        debugPrint('Clipboard changed: $clipboardText');

        setState(() {
          _bumpClipboardEntry(clipboardText);
        });
      }
    });
  }

  void _loadClipboardHistory() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    String? clipboardText = data?.text?.trim();
    debugPrint('Clipboard content: $clipboardText');

    if (clipboardText != null && clipboardText.isNotEmpty) {
      _lastClipboardContent = clipboardText;
      setState(() {
        _bumpClipboardEntry(clipboardText);
      });
    }
  }

  /// Double-tap history row: sync system clipboard and move item to front.
  Future<void> _activateHistoryItem(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      _lastClipboardContent = text;
      _bumpClipboardEntry(text);
      final list = _getFilteredHistory();
      final i = list.indexOf(text);
      _selectedFilteredIndex = i >= 0 ? i : null;
    });
    debugPrint('Clipboard restored from history: $text');
  }

  @override
  Widget build(BuildContext context) {
  
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16 + MediaQuery.paddingOf(context).top,
          16,
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索剪切板历史...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchText.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchText = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16.0),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openSettings,
                ),
                IconButton(
                  tooltip: _alwaysOnTop ? '取消窗口置顶' : '窗口置顶（显示在其他窗口之上）',
                  icon: Icon(
                    _alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                    color: _alwaysOnTop
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onPressed: _toggleWindowAlwaysOnTop,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _getFilteredHistory().isEmpty
                  ? const Center(child: Text('正在获取剪切板内容...'))
                  : Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Scrollbar(
                        controller: _historyScrollController,
                        thumbVisibility: true,
                        thickness: 8,
                        radius: const Radius.circular(4),
                        child: ListView.builder(
                          controller: _historyScrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                          itemCount: _getFilteredHistory().length,
                          itemBuilder: (context, index) {
                            final item = _getFilteredHistory()[index];
                            final isSelected = _selectedFilteredIndex == index;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedFilteredIndex =
                                      isSelected ? null : index;
                                });
                                debugPrint(
                                    'Selected list index: $_selectedFilteredIndex',
                                );
                              },
                              onDoubleTap: () => _activateHistoryItem(item),
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(vertical: 4.0),
                                padding: const EdgeInsets.all(12.0),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: isSelected
                                      ? Border.all(
                                          color:
                                              Theme.of(context).colorScheme.primary,
                                          width: 2.0,
                                        )
                                      : null,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        _clipboardCollapsedSpan(item, isSelected: isSelected),
                                      ],
                                      style: TextStyle(
                                        color: isSelected
                                            ? Theme.of(context).colorScheme.onPrimary
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    textAlign: TextAlign.start,
                                    softWrap: true,
                                    maxLines: isSelected ? null : 3,
                                    overflow: isSelected
                                        ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
