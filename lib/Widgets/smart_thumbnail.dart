import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../models/photo_item.dart';
import '../services/storage_service.dart';

class SmartThumbnail extends StatefulWidget {
  final PhotoItem item;
  final StorageService service;
  const SmartThumbnail({super.key, required this.item, required this.service});

  @override
  State<SmartThumbnail> createState() => _SmartThumbnailState();
}

class _SmartThumbnailState extends State<SmartThumbnail> {
  static String? _documentsPath;
  int _loadVersion = 0;
  File? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  @override
  void didUpdateWidget(covariant SmartThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.remoteFileName != widget.item.remoteFileName ||
        oldWidget.item.asset?.id != widget.item.asset?.id ||
        oldWidget.item.localThumbPath != widget.item.localThumbPath ||
        oldWidget.service.cacheKey != widget.service.cacheKey) {
      _imageFile = null;
      _isLoading = false;
      _checkAndLoad();
    }
  }

  Future<void> _checkAndLoad() async {
    final version = ++_loadVersion;
    final item = widget.item;
    final service = widget.service;
    if (item.asset != null) return;
    bool isCurrent() => mounted && version == _loadVersion;

    // Resolve known disk paths synchronously so remounting a cached tile does
    // not insert a placeholder frame before Flutter can reuse its image cache.
    final savedPath = item.localThumbPath;
    if (savedPath != null) {
      final savedFile = File(savedPath);
      if (savedFile.existsSync() && savedFile.lengthSync() > 0) {
        _imageFile = savedFile;
        return;
      }
    }
    try {
      final directoryPath = _documentsPath ??=
          (await getApplicationDocumentsDirectory()).path;
      if (!isCurrent()) return;
      final targetPath =
          '$directoryPath/thumb_${service.cacheKey}_${Uri.encodeComponent(item.id)}.jpg';
      final file = File(targetPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        setState(() => _imageFile = file);
        return;
      }
      setState(() => _isLoading = true);
      String remoteName = item.remoteFileName ?? '${item.id}.jpg';
      if (!remoteName.contains('.')) remoteName += '.jpg';
      await service.downloadFile('MyPhotos/.thumbs/$remoteName', targetPath);
      if (!isCurrent()) return;
      setState(() {
        _imageFile = file;
        _isLoading = false;
      });
    } catch (_) {
      if (isCurrent()) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.asset != null) {
      return AssetEntityImage(
        widget.item.asset!,
        key: ValueKey(widget.item.asset!.id),
        isOriginal: false,
        thumbnailSize: const ThumbnailSize(200, 200),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, error, stackTrace) => Container(
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
        ),
      );
    }
    if (_imageFile != null) return Image.file(_imageFile!, fit: BoxFit.cover);
    return Container(
      color: Colors.grey[200],
      child: _isLoading
          ? const Center(
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : const Icon(Icons.cloud_download, color: Colors.white),
    );
  }
}
