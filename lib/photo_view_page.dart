import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'webdav_service.dart'; // 引入 PhotoItem

class PhotoViewer extends StatefulWidget {
  // 【关键修改】这里接收列表和索引，而不是单张 item
  final List<PhotoItem> galleryItems;
  final int initialIndex;
  final WebDavService service;

  const PhotoViewer({
    super.key,
    required this.galleryItems,
    required this.initialIndex,
    required this.service,
  });

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    // 初始化控制器，确保打开时直接显示点击的那张图
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // 【关键修改】使用 PageView 构建左右滑动的相册
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.galleryItems.length,
        itemBuilder: (context, index) {
          return _buildSinglePage(widget.galleryItems[index]);
        },
      ),
    );
  }

  Widget _buildSinglePage(PhotoItem item) {
    return Center(
      child: FutureBuilder<File>(
        future: _getBestImage(item),
        builder: (context, snap) {
          if (snap.hasData && snap.data != null) {
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(snap.data!, fit: BoxFit.contain),
            );
          }
          if (snap.hasError) {
            return const Icon(Icons.broken_image, color: Colors.white54, size: 50);
          }
          return const CircularProgressIndicator(color: Colors.white);
        },
      ),
    );
  }

  Future<File> _getBestImage(PhotoItem item) async {
    // 1. 本地有原图
    if (item.asset != null) {
      final file = await item.asset!.file;
      if (file != null && file.existsSync()) return file;
    }
    
    // 2. 本地无原图，去下载
    final appDir = await getTemporaryDirectory();
    final localPath = '${appDir.path}/temp_${item.id}.jpg';
    final file = File(localPath);
    
    if (!file.existsSync() || file.lengthSync() == 0) {
      String fileName = item.remoteFileName ?? "${item.id}.jpg";
      if (!fileName.contains('.')) fileName += ".jpg";
      try {
        await widget.service.downloadFile("MyPhotos/$fileName", localPath);
      } catch (e) {
        if (file.existsSync()) file.deleteSync();
        rethrow;
      }
    }
    return file;
  }
}