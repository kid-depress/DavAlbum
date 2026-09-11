import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_application_2/models/photo_item.dart';
import 'package:flutter_application_2/services/storage_service.dart';
import 'package:flutter_application_2/Widgets/smart_thumbnail.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class _Asset extends AssetEntity {
  final VoidCallback onRead;
  _Asset(this.onRead)
    : super(
        id: 'thumbnail-cache-test',
        typeInt: 1,
        width: 1,
        height: 1,
        title: 'photo.png',
      );

  @override
  Future<Uint8List?> thumbnailDataWithOption(
    ThumbnailOption option, {
    PMProgressHandler? progressHandler,
    PMCancelToken? cancelToken,
  }) async {
    onRead();
    return _png;
  }
}

class _Storage implements StorageService {
  @override
  String get cacheKey => 'thumbnail-test';
  @override
  Future<void> downloadFile(String remotePath, String localPath) async =>
      throw StateError('Cached thumbnails must not download');
  @override
  Future<void> delete(String remotePath) async => throw UnimplementedError();
  @override
  Future<void> ensureFolder(String folderName) async =>
      throw UnimplementedError();
  @override
  Future<List<String>> listRemoteFiles(String folderPath) async =>
      throw UnimplementedError();
  @override
  Future<void> upload(File file, String remotePath) async =>
      throw UnimplementedError();
  @override
  Future<void> uploadBytes(Uint8List bytes, String remotePath) async =>
      throw UnimplementedError();
}

Widget _gallery(PhotoItem item) => MaterialApp(
  home: SizedBox(
    width: 100,
    height: 100,
    child: SmartThumbnail(item: item, service: _Storage()),
  ),
);

Future<void> _decodeImage(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(RawImage).evaluate().isNotEmpty &&
        tester.widget<RawImage>(find.byType(RawImage)).image != null) {
      return;
    }
  }
  fail('Thumbnail did not decode');
}

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('local thumbnails reuse decoded images on rebuild and remount', (
    tester,
  ) async {
    var reads = 0;
    final asset = _Asset(() => reads++);
    final item = PhotoItem(id: asset.id, asset: asset, createTime: 0);
    await tester.pumpWidget(_gallery(item));
    await _decodeImage(tester);
    expect(reads, 1);
    final originalImage = tester.widget<RawImage>(find.byType(RawImage)).image;
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(_gallery(item));
      await tester.pump();
      expect(reads, 1);
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(originalImage),
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_gallery(item));
    // Returning to an already cached tile should paint in the first frame.
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cloud thumbnail with a saved path skips placeholder on remount',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('thumbnail_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/thumb.png')..writeAsBytesSync(_png);
      final item = PhotoItem(
        id: 'cloud-test',
        localThumbPath: file.path,
        remoteFileName: 'photo.png',
        createTime: 0,
      );
      await tester.pumpWidget(_gallery(item));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _decodeImage(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_gallery(item));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
