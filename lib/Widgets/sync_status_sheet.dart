import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    this.isConfigured = false,
    this.isConnected = false,
    this.isRunning = false,
    this.currentTask = '正在加载',
    this.remoteCount,
    this.localCount = 0,
    this.pendingUploadCount = 0,
    this.pendingDownloadCount = 0,
    this.lastMessage,
  });

  final bool isConfigured;
  final bool isConnected;
  final bool isRunning;
  final String currentTask;
  final int? remoteCount;
  final int localCount;
  final int pendingUploadCount;
  final int pendingDownloadCount;
  final String? lastMessage;

  SyncStatusSnapshot copyWith({
    bool? isConfigured,
    bool? isConnected,
    bool? isRunning,
    String? currentTask,
    int? remoteCount,
    int? localCount,
    int? pendingUploadCount,
    int? pendingDownloadCount,
    String? lastMessage,
    bool clearRemoteCount = false,
  }) {
    return SyncStatusSnapshot(
      isConfigured: isConfigured ?? this.isConfigured,
      isConnected: isConnected ?? this.isConnected,
      isRunning: isRunning ?? this.isRunning,
      currentTask: currentTask ?? this.currentTask,
      remoteCount: clearRemoteCount ? null : remoteCount ?? this.remoteCount,
      localCount: localCount ?? this.localCount,
      pendingUploadCount: pendingUploadCount ?? this.pendingUploadCount,
      pendingDownloadCount: pendingDownloadCount ?? this.pendingDownloadCount,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}

class SyncStatusSheet extends StatelessWidget {
  const SyncStatusSheet({
    super.key,
    required this.providerName,
    required this.statusListenable,
    required this.onOpenSettings,
    required this.onRefresh,
    required this.onSync,
  });

  final String providerName;
  final ValueListenable<SyncStatusSnapshot> statusListenable;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<SyncStatusSnapshot>(
      valueListenable: statusListenable,
      builder: (context, status, _) {
        final statusColor = !status.isConfigured
            ? theme.colorScheme.outline
            : status.isConnected
            ? Colors.green
            : theme.colorScheme.error;

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('连接状态', style: theme.textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: status.isRunning ? null : onOpenSettings,
                      child: Text('$providerName 设置'),
                    ),
                  ],
                ),
                Text(
                  !status.isConfigured
                      ? '未配置'
                      : status.isRunning && !status.isConnected
                      ? '正在检测'
                      : status.isConnected
                      ? '已连接'
                      : '连接不可用',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                Text('当前任务队列', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (status.isRunning) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        status.isRunning ? status.currentTask : '空闲',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (status.isRunning) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 30),
                _StatusRow(
                  title: '远程照片数',
                  value: status.remoteCount?.toString() ?? '—',
                  actionTooltip: '刷新状态',
                  actionIcon: Icons.refresh_rounded,
                  onPressed: status.isRunning ? null : onRefresh,
                ),
                const SizedBox(height: 28),
                _StatusRow(
                  title: '本地照片数',
                  value: '${status.localCount}',
                  subtitle:
                      '待上传 ${status.pendingUploadCount}  待下载 ${status.pendingDownloadCount}',
                  actionTooltip: '立即同步',
                  actionIcon: Icons.sync_alt_rounded,
                  onPressed: status.isRunning || !status.isConfigured
                      ? null
                      : onSync,
                ),
                if (status.lastMessage != null) ...[
                  const SizedBox(height: 28),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        status.lastMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.title,
    required this.value,
    required this.actionTooltip,
    required this.actionIcon,
    required this.onPressed,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;
  final String actionTooltip;
  final IconData actionIcon;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 72,
          height: 56,
          child: FilledButton(
            onPressed: onPressed == null ? null : () => onPressed!(),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Icon(actionIcon, semanticLabel: actionTooltip),
          ),
        ),
      ],
    );
  }
}
