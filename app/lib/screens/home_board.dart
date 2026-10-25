import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/registry.dart';
import '../controllers/app_state.dart';
import '../controllers/connection.dart';
import '../controllers/home_layout.dart';
import '../l10n/s.dart';
import '../models/server.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/kit/tiles.dart';

/// صفحه‌خانه — پورت کامل `ui/home/HomeScreen.kt`:
/// نوار وضعیت 40dp + گرید 4×6 با صفحه‌بندی + داک شیشه‌ای + حالت ویرایش.
class HomeBoard extends StatefulWidget {
  final void Function(String tabId) onOpenTab;
  final AppearanceStore appearance;
  const HomeBoard({
    super.key,
    required this.onOpenTab,
    required this.appearance,
  });

  @override
  State<HomeBoard> createState() => _HomeBoardState();
}

class _HomeBoardState extends State<HomeBoard> {
  final HomeLayoutStore _store = HomeLayoutStore.instance;
  final ConnectionController _conn = ConnectionController.instance;
  final GlobalKey _gridKey = GlobalKey();

  bool _editMode = false;
  String? _draggingId;
  String? _openFolderKey;

  static const int _columns = 4;
  static const int _rows = 6;
  static const int _pageSize = _columns * _rows;

  String _t(String fa, String en) => S.isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
    _conn.addListener(_onChange);
    widget.appearance.addListener(_onChange);
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    _conn.removeListener(_onChange);
    widget.appearance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _fmtSpeed(int bytesPerSec) {
    if (bytesPerSec <= 0) return '0 KB/s';
    final kb = bytesPerSec / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB/s';
    return '${(kb / 1024).toStringAsFixed(1)} MB/s';
  }

  bool _isRunning(String destId) {
    final c = _conn;
    if (!c.connected) return false;
    switch (destId) {
      case 'nodes':
        return c.activeServer != null &&
            !c.activeServer!.isPsiphon &&
            !c.activeServer!.isAether &&
            !c.activeServer!.id.startsWith('tor_fake_') &&
            c.activeServer!.protocol != VpnProtocol.amneziaWg;
      case 'psiphon':
        return c.activeServer?.protocol == VpnProtocol.psiphon;
      case 'masque':
      case 'warp_on_warp':
        return c.activeServer?.protocol == VpnProtocol.aether &&
            ((destId == 'masque') ==
                !c.activeServer!.id.contains('_gool'));
      case 'warp':
        return c.activeServer?.protocol == VpnProtocol.amneziaWg;
      case 'tor':
        return c.activeServer?.id.startsWith('tor_fake_') == true;
      case 'cloud':
      case 'settings':
        return false;
      default:
        return false;
    }
  }

  void _openDestination(String id) {
    final d = destinationById(id);
    if (d == null) return;
    lightHaptic();
    widget.onOpenTab(id);
  }

  // ── درگ ──

  void _onDragStarted(String id) {
    setState(() {
      _editMode = true;
      _draggingId = id;
    });
  }

  void _onDragEnd(DraggableDetails details, String draggedId) {
    if (!_editMode) return;
    final box =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      setState(() => _draggingId = null);
      return;
    }
    final local =
        box.globalToLocal(details.offset - const Offset(0, 0));
    final cellW = box.size.width / _columns;
    final cellH = box.size.height / _rows;
    final col = (local.dx / cellW).floor().clamp(0, _columns - 1);
    final row = (local.dy / cellH).floor().clamp(0, _rows - 1);
    final slot = row * _columns + col;
    final items = _flatItems();
    setState(() => _draggingId = null);

    if (slot < 0 || slot >= items.length) {
      // انداخته در فضای خالی — آخر برد
      _store.moveOnBoard(draggedId, _store.board.length - 1);
      return;
    }
    final target = items[slot];
    if (target is AppItem) {
      if (target.id == draggedId) return;
      _store.mergeIntoFolder(draggedId, target.id);
    } else if (target is FolderItem) {
      _store.dropIntoFolder(draggedId, target.key);
    }
  }

  void _onFolderDragEnd(DraggableDetails details, String appId,
      String folderKey) {
    final box =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() => _draggingId = null);
    if (box == null) {
      _store.moveOut(appId, folderKey);
      return;
    }
    final local = box.globalToLocal(details.offset);
    final cellW = box.size.width / _columns;
    final cellH = box.size.height / _rows;
    final col = (local.dx / cellW).floor().clamp(0, _columns - 1);
    final row = (local.dy / cellH).floor().clamp(0, _rows - 1);
    final slot = row * _columns + col;
    final items = _flatItems();
    final inside = slot >= 0 &&
        slot < items.length &&
        items[slot] is FolderItem &&
        (items[slot] as FolderItem).key == folderKey;
    if (inside) {
      // هنوز داخل همان پوشه است — کاری نکن
    } else {
      _store.moveOut(appId, folderKey);
    }
  }

  List<BoardItem> _flatItems() => List<BoardItem>.from(_store.board);

  // ── پوشه ──

  void _openFolder(String key) {
    lightHaptic();
    setState(() => _openFolderKey = key);
  }

  Future<void> _renameFolder(FolderItem f) async {
    final name = await showIosPrompt(
      context,
      title: _t('نام پوشه', 'Folder name'),
      initial: f.title,
    );
    if (name != null) {
      await _store.renameFolder(f.key, name);
    }
  }

  // ── رندر ──

  @override
  Widget build(BuildContext context) {
    final iconScale = widget.appearance.iconScale / 100.0;
    final labelScale = widget.appearance.labelScale / 100.0;

    return Stack(
      children: [
        Column(
          children: [
            StatusStrip(
              running: _conn.connected,
              download: _fmtSpeed(_conn.downSpeed),
              upload: _fmtSpeed(_conn.upSpeed),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cellW = constraints.maxWidth / _columns;
                  final cellH = constraints.maxHeight / _rows;
                  final tile =
                      (math.min(cellH - 26, cellW - 14))
                          .clamp(40.0, 64.0) *
                      iconScale;
                  return _gridPages(tile, cellH, labelScale);
                },
              ),
            ),
            _dock(labelScale),
          ],
        ),
        if (_openFolderKey != null) _folderOverlay(_openFolderKey!),
        if (_draggingId != null) const SizedBox.expand(),
      ],
    );
  }

  Widget _gridPages(double tile, double cellH, double labelScale) {
    final items = _flatItems();
    final pages = <List<BoardItem>>[];
    for (var i = 0; i < items.length; i += _pageSize) {
      pages.add(items.sublist(i, math.min(i + _pageSize, items.length)));
    }
    if (pages.isEmpty) pages.add(<BoardItem>[]);

    return DragTarget<Object>(
      onAcceptWithDetails: (details) {
        // خروج عضو پوشه به بیرون
        final data = details.data;
        if (data is _FolderMemberDrag) {
          _onFolderDragEndFallback(data);
        }
      },
      builder: (context, _, __) {
        if (pages.length == 1) {
          return _gridPage(pages[0], tile, cellH, labelScale, 0);
        }
        return PageView(
          children: [
            for (var p = 0; p < pages.length; p++)
              _gridPage(pages[p], tile, cellH, labelScale, p),
          ],
        );
      },
    );
  }

  void _onFolderDragEndFallback(_FolderMemberDrag data) {
    _store.moveOut(data.appId, data.folderKey);
    setState(() => _draggingId = null);
  }

  Widget _gridPage(List<BoardItem> pageItems, double tile, double cellH,
      double labelScale, int pageIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Stack(
        key: pageIndex == 0 ? _gridKey : null,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: cellH * _rows,
              child: Column(
                children: [
                  for (var r = 0; r < _rows; r++)
                    SizedBox(
                      height: cellH,
                      child: Row(
                        children: [
                          for (var c = 0; c < _columns; c++)
                            Expanded(
                              child: _cellFor(
                                  pageItems, r * _columns + c, tile,
                                  labelScale),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_editMode)
            Positioned(
              top: 0,
              right: 12,
              child: _donePill(),
            ),
        ],
      ),
    );
  }

  Widget _donePill() {
    return GestureDetector(
      onTap: () => setState(() => _editMode = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _t('انجام شد', 'Done'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _cellFor(List<BoardItem> items, int index, double tile,
      double labelScale) {
    if (index >= items.length) return const SizedBox();
    final item = items[index];
    if (item is AppItem) {
      return _appCell(item.id, tile, labelScale, index);
    } else if (item is FolderItem) {
      return _folderCell(item, tile, labelScale, index);
    }
    return const SizedBox();
  }

  Widget _appCell(String id, double tile, double labelScale, int index) {
    final d = destinationById(id);
    if (d == null) return const SizedBox();
    return _tileColumn(
      key: ValueKey('app_$id'),
      tile: tile,
      labelScale: labelScale,
      index: index,
      label: d.label(),
      dragging: _draggingId == id,
      onTap: _editMode ? null : () => _openDestination(id),
      onRename: null,
      onRemove: _editMode
          ? () {
              showIosAlert(
                context,
                title: _t('حذف از صفحه‌خانه؟', 'Remove from Home?'),
                message: d.label(),
                confirmLabel: _t('حذف', 'Remove'),
                destructive: true,
                onConfirm: () => _store.removeFromBoard(id),
              );
            }
          : null,
      icon: AppIconTile(
        size: tile,
        art: d.art,
        tint: d.tint,
        running: _isRunning(id),
      ),
      dragData: id,
      onDragStarted: () => _onDragStarted(id),
      onDragEnd: (det) => _onDragEnd(det, id),
    );
  }

  Widget _folderCell(
      FolderItem f, double tile, double labelScale, int index) {
    return _tileColumn(
      key: ValueKey('folder_${f.key}'),
      tile: tile,
      labelScale: labelScale,
      index: index,
      label: f.title,
      dragging: _draggingId == f.key,
      onTap: _editMode ? null : () => _openFolder(f.key),
      onRename: _editMode ? () => _renameFolder(f) : null,
      onRemove: _editMode
          ? () {
              showIosAlert(
                context,
                title:
                    _t('انحلال پوشه؟', 'Remove folder?'),
                message: f.title,
                confirmLabel: _t('حذف', 'Remove'),
                destructive: true,
                onConfirm: () => _store.ungroup(f.key),
              );
            }
          : null,
      icon: FolderIconTile(size: tile, folder: f),
      dragData: f.key,
      onDragStarted: () => _onDragStarted(f.key),
      onDragEnd: (det) => _onDragEnd(det, f.key),
    );
  }

  Widget _tileColumn({
    required Key key,
    required double tile,
    required double labelScale,
    required int index,
    required String label,
    required bool dragging,
    required VoidCallback? onTap,
    required VoidCallback? onRename,
    required VoidCallback? onRemove,
    required Widget icon,
    required Object dragData,
    required VoidCallback onDragStarted,
    required void Function(DraggableDetails) onDragEnd,
  }) {
    Widget content = GestureDetector(
      onTap: onTap,
      onLongPress: onRename,
      child: Column(
        children: [
          SizedBox(
            width: tile,
            height: tile,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Jiggle(
                  enabled: _editMode,
                  index: index,
                  child: dragging
                      ? Opacity(opacity: 0.3, child: icon)
                      : icon,
                ),
                if (_editMode && onRemove != null)
                  Positioned.directional(
                    textDirection: Directionality.of(context),
                    top: -(tile * 0.34 * 0.5),
                    start: -(tile * 0.34 * 0.5),
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        width: tile * 0.34,
                        height: tile * 0.34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF8E8E93)
                              .withValues(alpha: 0.96),
                        ),
                        child: Icon(Icons.close,
                            size: tile * 0.20, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: tile + 14,
            child: TileCaption(label,
                labelScale: labelScale, emphasized: _editMode),
          ),
        ],
      ),
    );

    if (dragging) return content;

    return LongPressDraggable<Object>(
      data: dragData,
      delay: const Duration(milliseconds: 120),
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      onDraggableCanceled: (_, __) =>
          setState(() => _draggingId = null),
      feedback: Transform.scale(
        scale: 1.12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 6),
            TileCaption(label, labelScale: labelScale),
          ],
        ),
      ),
      child: content,
    );
  }

  Widget _dock(double labelScale) {
    final dockTiles = <Widget>[];
    for (final id in kDockIds) {
      final d = destinationById(id);
      if (d == null) continue;
      dockTiles.add(
        GestureDetector(
          onTap: () => _openDestination(id),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconTile(
                size: 56,
                art: d.art,
                tint: d.tint,
                running: _isRunning(id),
                badgeCount:
                    id == 'settings' ? _updateBadge() : null,
              ),
              if (widget.appearance.dockLabels) ...[
                const SizedBox(height: 4),
                TileCaption(d.label(), labelScale: labelScale),
              ],
            ],
          ),
        ),
      );
    }
    return GlassDock(
      tiles: dockTiles,
      showLabels: widget.appearance.dockLabels,
    );
  }

  int? _updateBadge() {
    return null; // نشان به‌روزرسانی در فاز Update (P3) وصل می‌شود
  }

  // ── پوشه باز ──

  Widget _folderOverlay(String key) {
    final f = _store.folders[key];
    if (f == null) return const SizedBox();
    final size = MediaQuery.sizeOf(context);
    final panelW = math.min(size.width - 48, 360.0);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _openFolderKey = null),
        child: Container(
          color: Colors.black.withValues(alpha: 0.24),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: FrostedGlass(
              borderRadius: BorderRadius.circular(IosRadius.folderPanel),
              blur: 34,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 18),
              child: SizedBox(
                width: panelW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            f.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_editMode) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _renameFolder(f),
                            child: Icon(Icons.edit,
                                size: 18,
                                color: Colors.white
                                    .withValues(alpha: 0.6)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, c) {
                        final cellW = (panelW - 28) / 3;
                        final tile =
                            (cellW - 22).clamp(40.0, 80.0);
                        return Column(
                          children: [
                            for (var r = 0;
                                r < (f.apps.length + 2) ~/ 3;
                                r++)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  for (var c2 = 0; c2 < 3; c2++)
                                    Builder(builder: (ctx) {
                                      final i = r * 3 + c2;
                                      if (i >= f.apps.length) {
                                        return SizedBox(
                                            width: tile, height: tile + 26);
                                      }
                                      final appId = f.apps[i];
                                      final d = destinationById(appId);
                                      if (d == null) {
                                        return SizedBox(
                                            width: tile, height: tile + 26);
                                      }
                                      return Column(
                                        children: [
                                          GestureDetector(
                                            onTap: _editMode
                                                ? null
                                                : () {
                                                    setState(() =>
                                                        _openFolderKey =
                                                            null);
                                                    _openDestination(appId);
                                                  },
                                            onLongPress: _editMode
                                                ? () => _renameFolder(f)
                                                : null,
                                            child: LongPressDraggable<
                                                _FolderMemberDrag>(
                                              data: _FolderMemberDrag(
                                                  appId, f.key),
                                              delay: const Duration(
                                                  milliseconds: 120),
                                              onDragStarted: () {
                                                setState(() {
                                                  _editMode = true;
                                                  _draggingId = appId;
                                                });
                                              },
                                              onDragEnd: (det) =>
                                                  _onFolderDragEnd(
                                                      det, appId, f.key),
                                              feedback:
                                                  Transform.scale(
                                                scale: 1.12,
                                                child: AppIconTile(
                                                    size: tile,
                                                    art: d.art,
                                                    tint: d.tint),
                                              ),
                                              child: Jiggle(
                                                enabled: _editMode,
                                                index: i,
                                                child: _draggingId == appId
                                                    ? Opacity(
                                                        opacity: 0.3,
                                                        child: AppIconTile(
                                                            size: tile,
                                                            art: d.art,
                                                            tint: d.tint))
                                                    : AppIconTile(
                                                        size: tile,
                                                        art: d.art,
                                                        tint: d.tint),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            width: tile,
                                            child: TileCaption(d.label(),
                                                labelScale:
                                                    widget.appearance
                                                            .labelScale /
                                                        100.0),
                                          ),
                                        ],
                                      );
                                    }),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// دادهٔ درگ عضو پوشه.
class _FolderMemberDrag {
  final String appId;
  final String folderKey;
  const _FolderMemberDrag(this.appId, this.folderKey);
}

/// آیکون پوشه — مینیاتور 3×3 اعضا روی شیشه (HomeFolders.kt L104-134).
class FolderIconTile extends StatelessWidget {
  final double size;
  final FolderItem folder;
  const FolderIconTile(
      {super.key, required this.size, required this.folder});

  @override
  Widget build(BuildContext context) {
    final pad = size * 0.13;
    final gap = size * 0.055;
    final mini = (size - 2 * pad - 2 * gap) / 3;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: FrostedGlass(
          borderRadius: BorderRadius.circular(size * 0.26),
          blur: 18,
          child: Center(
            child: SizedBox(
              width: mini * 3 + gap * 2,
              height: mini * 3 + gap * 2,
              child: Column(
                children: [
                  for (var r = 0; r < 3; r++)
                    Row(
                      children: [
                        for (var c = 0; c < 3; c++)
                          Builder(builder: (ctx) {
                            final i = r * 3 + c;
                            if (i >= folder.apps.length) {
                              return SizedBox(width: mini, height: mini);
                            }
                            final d =
                                destinationById(folder.apps[i]);
                            if (d == null) {
                              return SizedBox(width: mini, height: mini);
                            }
                            return Padding(
                              padding: EdgeInsets.all(gap / 2),
                              child: SizedBox(
                                width: mini,
                                height: mini,
                                child: AppIconTile(
                                    size: mini, art: d.art, tint: d.tint),
                              ),
                            );
                          }),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
