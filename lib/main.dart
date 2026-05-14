import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shear_plate/account_page.dart';
import 'package:shear_plate/settings_page.dart';
import 'package:window_manager/window_manager.dart';

/// Represents a clipboard item that can be either text or an image
class ClipboardItem {
  final String? text;
  final Uint8List? imageData;
  final String? sourceAppName;
  final Uint8List? sourceAppIcon;
  final DateTime timestamp;

  ClipboardItem.text(this.text, {this.sourceAppName, this.sourceAppIcon})
    : imageData = null,
      timestamp = DateTime.now();

  ClipboardItem.image(this.imageData, {this.sourceAppName, this.sourceAppIcon})
    : text = null,
      timestamp = DateTime.now();

  bool get isText => text != null;
  bool get isImage => imageData != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ClipboardItem) return false;
    if (isText && other.isText) return text == other.text;
    if (isImage && other.isImage) {
      final a = imageData;
      final b = other.imageData;
      if (a == null || b == null) return false;
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return false;
  }

  @override
  int get hashCode => isText
      ? text.hashCode
      : imageData == null
      ? 0
      : Object.hashAll(imageData!);
}

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
  final List<ClipboardItem> _clipboardHistory = [];

  /// Index into [_getFilteredHistory()]; null means no row selected.
  int? _selectedFilteredIndex;
  bool _alwaysOnTop = false;
  ClipboardItem? _lastClipboardContent;
  Timer? _clipboardTimer;
  late TextEditingController _searchController;
  final ScrollController _historyScrollController = ScrollController();
  final FocusNode _listFocusNode = FocusNode();
  String _searchText = '';
  DateTime? _suppressClipboardListenerUntil;

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
    _listFocusNode.dispose();
    _clipboardTimer?.cancel();
    super.dispose();
  }

  List<ClipboardItem> _getFilteredHistory() {
    if (_searchText.isEmpty) {
      return _clipboardHistory;
    }
    return _clipboardHistory
        .where(
          (item) =>
              item.isText &&
              item.text!.toLowerCase().contains(_searchText.toLowerCase()),
        )
        .toList();
  }

  Future<Map<String, Object?>> _fetchClipboardSourceInfo() async {
    if (!_supportsNativeWindow) {
      return <String, Object?>{};
    }

    try {
      const platform = MethodChannel('clipboard_image');
      final Map<String, Object?>? result = await platform
          .invokeMapMethod<String, Object?>('getClipboardOwnerInfo');
      return result ?? <String, Object?>{};
    } catch (e) {
      debugPrint('Failed to get clipboard source info: $e');
      return <String, Object?>{};
    }
  }

  Uint8List? _normalizeSourceIcon(Object? raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return null;
  }

  /// Collapsed list preview: truncate by grapheme count, append ellipsis.
  static const int _kPreviewMaxGraphemes = 80;

  InlineSpan _clipboardCollapsedSpan(
    ClipboardItem item, {
    bool isSelected = false,
  }) {
    if (item.isImage) {
      return const TextSpan(text: '[图片]');
    }

    final full = item.text!;
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

  /// Inserts or moves [item] to the front of history.
  void _bumpClipboardEntry(ClipboardItem item) {
    _clipboardHistory.removeWhere((entry) => entry == item);
    _clipboardHistory.insert(0, item);
  }

  /// Toggles whether the app window stays above other windows (desktop only).
  Future<void> _toggleWindowAlwaysOnTop() async {
    if (!_supportsNativeWindow) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('仅桌面端支持窗口置顶')));
      return;
    }

    final next = !_alwaysOnTop;
    setState(() => _alwaysOnTop = next);
    try {
      await windowManager.setAlwaysOnTop(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _alwaysOnTop = !next);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法切换窗口置顶：$e')));
    }
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const SettingsPage()),
    );
  }

  void _openLogin() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const AccountPage()),
    );
  }

  void _startClipboardListener() {
    _clipboardTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) async {
      try {
        if (_suppressClipboardListenerUntil != null &&
            DateTime.now().isBefore(_suppressClipboardListenerUntil!)) {
          return;
        }

        // 1. Priority: Check for image data first
        // This includes actual image pixels and image files copied from Explorer
        try {
          const platform = MethodChannel('clipboard_image');
          final Uint8List? imageData = await platform.invokeMethod<Uint8List>(
            'getImage',
          );
          if (imageData != null && imageData.isNotEmpty) {
            final sourceInfo = await _fetchClipboardSourceInfo();
            final item = ClipboardItem.image(
              imageData,
              sourceAppName: sourceInfo['name'] as String?,
              sourceAppIcon: _normalizeSourceIcon(sourceInfo['icon']),
            );
            if (item != _lastClipboardContent) {
              _lastClipboardContent = item;
              debugPrint('Clipboard changed: image');
              setState(() {
                _bumpClipboardEntry(item);
              });
            }
            return; // Found an image, skip text check
          }
        } catch (e) {
          debugPrint('Failed to get image from clipboard: $e');
        }

        // 2. Fallback: Check for text data
        ClipboardData? textData = await Clipboard.getData(Clipboard.kTextPlain);
        String? clipboardText = textData?.text?.trim();

        if (clipboardText != null && clipboardText.isNotEmpty) {
          final sourceInfo = await _fetchClipboardSourceInfo();
          final item = ClipboardItem.text(
            clipboardText,
            sourceAppName: sourceInfo['name'] as String?,
            sourceAppIcon: _normalizeSourceIcon(sourceInfo['icon']),
          );
          if (item != _lastClipboardContent) {
            _lastClipboardContent = item;
            debugPrint('Clipboard changed: text');
            setState(() {
              _bumpClipboardEntry(item);
            });
          }
        }
      } catch (e) {
        debugPrint('Failed to read clipboard: $e');
      }
    });
  }

  void _loadClipboardHistory() async {
    try {
      // 1. Priority: Check for image data first
      try {
        const platform = MethodChannel('clipboard_image');
        final Uint8List? imageData = await platform.invokeMethod<Uint8List>(
          'getImage',
        );
        if (imageData != null && imageData.isNotEmpty) {
          final sourceInfo = await _fetchClipboardSourceInfo();
          final item = ClipboardItem.image(
            imageData,
            sourceAppName: sourceInfo['name'] as String?,
            sourceAppIcon: _normalizeSourceIcon(sourceInfo['icon']),
          );
          _lastClipboardContent = item;
          setState(() {
            _bumpClipboardEntry(item);
          });
          debugPrint('Loaded clipboard image');
          return;
        }
      } catch (e) {
        debugPrint('Failed to load image from clipboard: $e');
      }

      // 2. Fallback: Check for text data
      ClipboardData? textData = await Clipboard.getData(Clipboard.kTextPlain);
      String? clipboardText = textData?.text?.trim();

      if (clipboardText != null && clipboardText.isNotEmpty) {
        final item = ClipboardItem.text(clipboardText);
        _lastClipboardContent = item;
        setState(() {
          _bumpClipboardEntry(item);
        });
        debugPrint('Loaded clipboard text');
      }
    } catch (e) {
      debugPrint('Failed to load clipboard history: $e');
    }
  }

  /// Double-tap history row: sync system clipboard and move item to front.
  Future<void> _activateHistoryItem(ClipboardItem item) async {
    debugPrint('=== _activateHistoryItem START ===');
    debugPrint('Item type: ${item.isText ? "text" : "image"}');
    if (item.isImage) {
      debugPrint('Image data length: ${item.imageData?.length}');
    }

    final int identicalHistoryIndex = _clipboardHistory.indexWhere(
      (entry) => identical(entry, item),
    );
    final int historyIndex = identicalHistoryIndex != -1
        ? identicalHistoryIndex
        : _clipboardHistory.indexWhere((entry) => entry == item);
    final ClipboardItem historyItem = historyIndex != -1
        ? _clipboardHistory[historyIndex]
        : item;

    final ClipboardItem? previousClipboardContent = _lastClipboardContent;
    _lastClipboardContent = historyItem;
    _suppressClipboardListenerUntil = DateTime.now().add(
      const Duration(seconds: 3),
    );
    try {
      if (historyItem.isText) {
        debugPrint('Setting text to clipboard: ${historyItem.text}');
        await Clipboard.setData(ClipboardData(text: historyItem.text!));
        debugPrint('✓ Clipboard text set successfully');
      } else if (historyItem.isImage) {
        debugPrint(
          'Attempting to restore image to clipboard, data length: ${historyItem.imageData?.length}',
        );
        const platform = MethodChannel('clipboard_image');
        debugPrint('Calling platform method: setImage');
        await platform.invokeMethod('setImage', {
          'data': historyItem.imageData,
        });
        debugPrint('✓ Successfully called platform method: setImage');
      }
    } catch (e) {
      _lastClipboardContent = previousClipboardContent;
      _suppressClipboardListenerUntil = null;
      debugPrint('✗ ERROR: Failed to set clipboard: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法复制内容到剪切板: $e')));
      }
      return;
    }

    if (!mounted) return;
    debugPrint('Moving item to front of history...');
    setState(() {
      _bumpClipboardEntry(historyItem);
      _selectedFilteredIndex = 0;
      debugPrint('✓ Item moved to position 0');
    });
    debugPrint('=== _activateHistoryItem END ===');
  }

  void _handleCopyShortcut() {
    if (_selectedFilteredIndex != null) {
      final list = _getFilteredHistory();
      if (_selectedFilteredIndex! < list.length) {
        final text = list[_selectedFilteredIndex!];
        _activateHistoryItem(text);
      }
    }
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '帐号',
                  icon: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.account_circle_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  onPressed: _openLogin,
                ),
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openSettings,
                ),
                if (_supportsNativeWindow)
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
              child: KeyboardListener(
                focusNode: _listFocusNode,
                autofocus: true,
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.keyC &&
                      HardwareKeyboard.instance.isControlPressed) {
                    _handleCopyShortcut();
                  }
                },
                child: _getFilteredHistory().isEmpty
                    ? const Center(child: Text('正在获取剪切板内容...'))
                    : Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
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
                              final isSelected =
                                  _selectedFilteredIndex == index;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedFilteredIndex = isSelected
                                        ? null
                                        : index;
                                  });
                                  if (_selectedFilteredIndex != null) {
                                    _listFocusNode.requestFocus();
                                  }
                                  debugPrint(
                                    'Selected list index: $_selectedFilteredIndex',
                                  );
                                },
                                onDoubleTap: () => _activateHistoryItem(item),
                                child: Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4.0,
                                  ),
                                  padding: const EdgeInsets.all(12.0),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8.0),
                                    border: isSelected
                                        ? Border.all(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            width: 2.0,
                                          )
                                        : null,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (item.sourceAppName != null ||
                                          item.sourceAppIcon != null)
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            if (item.sourceAppIcon != null)
                                              Container(
                                                width: 20,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        4.0,
                                                      ),
                                                  image: DecorationImage(
                                                    image: MemoryImage(
                                                      item.sourceAppIcon!,
                                                    ),
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              )
                                            else
                                              Icon(
                                                Icons.apps,
                                                size: 20,
                                                color: isSelected
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .onPrimaryContainer
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                              ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                item.sourceAppName != null
                                                    ? '来自：${item.sourceAppName}'
                                                    : '来自：未知应用',
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .onPrimaryContainer
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (item.sourceAppName != null ||
                                          item.sourceAppIcon != null)
                                        const SizedBox(height: 10),
                                      item.isImage
                                          ? Row(
                                              children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4.0,
                                                        ),
                                                    image: DecorationImage(
                                                      image: MemoryImage(
                                                        item.imageData!,
                                                      ),
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                const Text('[图片]'),
                                              ],
                                            )
                                          : RichText(
                                              text: TextSpan(
                                                children: [
                                                  _clipboardCollapsedSpan(
                                                    item,
                                                    isSelected: isSelected,
                                                  ),
                                                ],
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .onPrimaryContainer
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                ),
                                              ),
                                              textAlign: TextAlign.start,
                                              softWrap: true,
                                              maxLines: isSelected ? null : 3,
                                              overflow: isSelected
                                                  ? TextOverflow.visible
                                                  : TextOverflow.ellipsis,
                                            ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
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
