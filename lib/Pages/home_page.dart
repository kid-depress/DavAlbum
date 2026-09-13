import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_zoom.dart';
import '../widgets/photo_tile.dart';
import '../widgets/scalable_grid_delegate.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/sync_status_sheet.dart';
import 'home_logic_mixin.dart';
import 'photo_view_page.dart';

class SuperBackupPage extends StatefulWidget {
  const SuperBackupPage({super.key});

  @override
  State<SuperBackupPage> createState() => _SuperBackupPageState();
}

class _SuperBackupPageState extends State<SuperBackupPage>
    with SingleTickerProviderStateMixin, HomeLogicMixin {
  double _columnCount = 4;
  double _columnsAtGestureStart = 4;
  int _lastHapticColumnCount = 4;
  int _pointerCount = 0;
  late final AnimationController _columnController;
  Animation<double>? _columnAnimation;

  @override
  void initState() {
    super.initState();
    _columnController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(() {
          final animation = _columnAnimation;
          if (animation != null && mounted) {
            setState(() => _columnCount = animation.value);
          }
        });
    initLogic();
  }

  @override
  void dispose() {
    _columnController.dispose();
    super.dispose();
  }

  void _updatePointerCount(int count) {
    final wasPinching = _pointerCount >= 2;
    _pointerCount = count.clamp(0, 10);
    // A single-finger scroll does not change the gallery layout.
    if (wasPinching != (_pointerCount >= 2)) setState(() {});
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (details.pointerCount < 2) return;
    _columnController.stop();
    _columnsAtGestureStart = _columnCount;
    _lastHapticColumnCount = _columnCount.round();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    final nextColumnCount = (_columnsAtGestureStart / details.scale).clamp(
      galleryColumnLevels.first,
      galleryColumnLevels.last,
    );
    final nearestColumnCount = nearestGalleryColumnLevel(
      nextColumnCount,
    ).round();
    if (nearestColumnCount != _lastHapticColumnCount) {
      _lastHapticColumnCount = nearestColumnCount;
      HapticFeedback.selectionClick();
    }
    if (nextColumnCount != _columnCount) {
      setState(() => _columnCount = nextColumnCount);
    }
  }

  void _animateToNearestColumnCount() {
    final target = nearestGalleryColumnLevel(_columnCount);
    _columnAnimation = Tween<double>(begin: _columnCount, end: target).animate(
      CurvedAnimation(parent: _columnController, curve: Curves.easeOutCubic),
    );
    _columnController.forward(from: 0);
  }

  void _handleScaleEnd() {
    _animateToNearestColumnCount();
  }

  void _showSettings() {
    if (isRunning) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SettingsSheet(
        urlCtrl: urlCtrl,
        userCtrl: userCtrl,
        passCtrl: passCtrl,
        provider: syncProvider,
        pathStyle: s3PathStyle,
        s3Controllers: s3Controllers,
        onSave: applyStorageSettings,
      ),
    );
  }

  void _showSyncStatus() {
    unawaited(refreshSyncStatus());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.72,
        child: SyncStatusSheet(
          providerName: syncProvider == 's3' ? 'S3' : 'WebDAV',
          statusListenable: syncStatus,
          onOpenSettings: () {
            Navigator.pop(sheetContext);
            _showSettings();
          },
          onRefresh: refreshSyncStatus,
          onSync: () async {
            await connectAndRestoreThenBackup();
            await refreshSyncStatus();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: (isSelectionMode || isRunning)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => doBackup(silent: false),
              icon: const Icon(Icons.backup_outlined),
              label: const Text("立即备份"),
            ),
      bottomNavigationBar: isSelectionMode
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: downloadSelectedToLocal,
                    icon: const Icon(
                      Icons.cloud_download_outlined,
                      color: Colors.blue,
                    ),
                    label: const Text(
                      "保存到本地",
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: deleteSelectedCloud,
                    icon: const Icon(Icons.cloud_off, color: Colors.red),
                    label: const Text(
                      "删除云端",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            )
          : null,
      body: Listener(
        onPointerDown: (_) => _updatePointerCount(_pointerCount + 1),
        onPointerUp: (_) => _updatePointerCount(_pointerCount - 1),
        onPointerCancel: (_) => _updatePointerCount(_pointerCount - 1),
        child: GestureDetector(
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: (_) => _handleScaleEnd(),
          child: CustomScrollView(
            physics: (_pointerCount >= 2 || _columnController.isAnimating)
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                floating: true,
                snap: true,
                backgroundColor: theme.colorScheme.surface,
                surfaceTintColor: theme.colorScheme.surfaceTint,
                title: isSelectionMode
                    ? Text("已选 ${selectedIds.length} 项")
                    : const Text(
                        "相册",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                leading: isSelectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: exitSelectionMode,
                      )
                    : null,
                actions: [
                  if (!isSelectionMode) ...[
                    IconButton(
                      tooltip: '同步状态',
                      onPressed: _showSyncStatus,
                      icon: const Icon(Icons.sync),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'settings') _showSettings();
                        if (value == 'free_space') freeAllLocalSpace();
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'free_space',
                          child: Row(
                            children: [
                              Icon(Icons.cleaning_services_outlined),
                              SizedBox(width: 12),
                              Text('释放本地空间'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'settings',
                          child: Row(
                            children: [
                              Icon(Icons.settings_outlined),
                              SizedBox(width: 12),
                              Text('连接设置'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    IconButton(
                      onPressed: selectAll,
                      icon: const Icon(Icons.select_all),
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
              ),
              if (isRunning)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (logs.isNotEmpty && !isSelectionMode)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Text(
                      logs.first,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ..._buildGridContent(theme),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGridContent(ThemeData theme) {
    final slivers = <Widget>[];
    final service = createStorageService();
    final cacheKey = service.cacheKey;
    final visibleGroups = groupGalleryItems(groupedItems, _columnCount);
    final gridSpacing = _gridSpacingForDensity(_columnCount);
    final horizontalPadding = _gridPaddingForDensity(_columnCount);
    visibleGroups.forEach((date, items) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Text(
              date,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );

      slivers.add(
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: SliverGrid(
            gridDelegate: ScalableGridDelegate(
              columnCount: _columnCount,
              crossAxisSpacing: gridSpacing,
              mainAxisSpacing: gridSpacing,
            ),
            delegate: SliverChildBuilderDelegate((_, index) {
              final item = items[index];
              return PhotoTile(
                key: ValueKey('${cacheKey}_${item.id}'),
                item: item,
                isSelectionMode: isSelectionMode,
                isSelected: selectedIds.contains(item.id),
                service: service,
                onLongPress: () {
                  if (!isSelectionMode) {
                    setState(() {
                      isSelectionMode = true;
                      selectedIds.add(item.id);
                      HapticFeedback.selectionClick();
                    });
                  }
                },
                onTap: () {
                  if (isSelectionMode) {
                    toggleSelection(item.id);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PhotoViewer(
                          galleryItems: items,
                          initialIndex: index,
                          service: service,
                        ),
                      ),
                    );
                  }
                },
              );
            }, childCount: items.length),
          ),
        ),
      );
    });
    return slivers;
  }

  double _gridSpacingForDensity(double density) {
    if (density <= 6) return 8;
    if (density <= 8) return 8 - 5 * ((density - 6) / 2);
    return 3 - 2 * ((density - 8) / 8);
  }

  double _gridPaddingForDensity(double density) {
    if (density <= 6) return 16;
    if (density <= 8) return 16 - 8 * ((density - 6) / 2);
    return 8 - 4 * ((density - 8) / 8);
  }
}
