import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_2/Widgets/sync_status_sheet.dart';

void main() {
  testWidgets('shows counts and runs sync action', (tester) async {
    final status = ValueNotifier(
      const SyncStatusSnapshot(
        isConfigured: true,
        isConnected: true,
        remoteCount: 460,
        localCount: 120,
        pendingUploadCount: 3,
        pendingDownloadCount: 2,
      ),
    );
    addTearDown(status.dispose);
    var syncCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusSheet(
            providerName: 'WebDAV',
            statusListenable: status,
            onOpenSettings: () {},
            onRefresh: () async {},
            onSync: () async => syncCalls++,
          ),
        ),
      ),
    );

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('460'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('待上传 3  待下载 2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.sync_alt_rounded));
    await tester.pump();
    expect(syncCalls, 1);
  });

  testWidgets('updates current task while synchronization is running', (
    tester,
  ) async {
    final status = ValueNotifier(
      const SyncStatusSnapshot(
        isConfigured: true,
        isRunning: true,
        currentTask: '正在上传 2/8',
      ),
    );
    addTearDown(status.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusSheet(
            providerName: 'S3',
            statusListenable: status,
            onOpenSettings: () {},
            onRefresh: () async {},
            onSync: () async {},
          ),
        ),
      ),
    );

    expect(find.text('正在检测'), findsOneWidget);
    expect(find.text('正在上传 2/8'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    status.value = status.value.copyWith(
      isConnected: true,
      isRunning: false,
      currentTask: '空闲',
      remoteCount: 8,
    );
    await tester.pump();

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('空闲'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
