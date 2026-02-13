import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/photo_item.dart';
import '../services/db_helper.dart';
import '../services/webdav_service.dart';
import '../widgets/smart_thumbnail.dart';
import 'photo_view_page.dart';

class SuperBackupPage extends StatefulWidget {
  const SuperBackupPage({super.key});
  @override
  State<SuperBackupPage> createState() => _SuperBackupPageState();
}

class _SuperBackupPageState extends State<SuperBackupPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  
  final List<String> _logs = [];
  bool isRunning = false;
  Map<String, List<PhotoItem>> _groupedItems = {}; 
  int _crossAxisCount = 3; 
  int _startColCount = 3; 
  final Set<String> _sessionUploadedIds = {};

  @override
  void initState() {
    super.initState();
    _startAutoTasks();
  }

  void addLog(String m) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, "${DateTime.now().hour}:${DateTime.now().minute} $m"); 
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  Future<void> _startAutoTasks() async {
    await _loadConfig();
    if (_urlCtrl.text.isEmpty) return;
    _manageCache();
    await _syncCloudToLocal(); 
    doBackup(silent: true);
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlCtrl.text = prefs.getString('url') ?? "";
      _userCtrl.text = prefs.getString('user') ?? "";
      _passCtrl.text = prefs.getString('pass') ?? "";
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('url', _urlCtrl.text);
    await prefs.setString('user', _userCtrl.text);
    await prefs.setString('pass', _passCtrl.text);
  }

  Future<void> _manageCache() async {
    try {
      final appDir = await getTemporaryDirectory();
      final files = appDir.listSync().whereType<File>().where((f) => p.basename(f.path).startsWith('temp_full_')).toList();
      int totalSize = 0;
      for (var f in files) {
        totalSize += await f.length();
      }
      if (totalSize > 200 * 1024 * 1024) {
        files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        for (var f in files) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }

  // --- 核心逻辑：刷新相册列表（合并本地与云端记录） ---
  Future<void> _refreshGallery() async {
    // 1. 获取本地
    final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    List<AssetEntity> localAssets = albums.isNotEmpty ? await albums.first.getAssetListPaged(page: 0, size: 5000) : [];
    Map<String, AssetEntity> localAssetMap = {for (var e in localAssets) e.id: e};

    // 2. 获取数据库
    final dbRecords = await DbHelper.getAllRecords();
    
    Map<String, PhotoItem> mergedMap = {};

    // A. 处理数据库记录（包含本地已删云端还在的）
    for (var row in dbRecords) {
      String id = row['asset_id'];
      AssetEntity? localAsset = localAssetMap[id];
      
      mergedMap[id] = PhotoItem(
        id: id,
        asset: localAsset, // 如果本地已删，这里是 null
        localThumbPath: row['thumbnail_path'], 
        remoteFileName: row['filename'], 
        createTime: row['create_time'] ?? 0, 
        isBackedUp: true
      );
    }

    // B. 处理本地新增未备份的
    for (var asset in localAssets) {
      if (!mergedMap.containsKey(asset.id)) {
        mergedMap[asset.id] = PhotoItem(
          id: asset.id, 
          asset: asset, 
          createTime: asset.createDateTime.millisecondsSinceEpoch, 
          isBackedUp: false
        );
      }
    }

    var list = mergedMap.values.toList()..sort((a, b) => b.createTime.compareTo(a.createTime));
    Map<String, List<PhotoItem>> groups = {};
    for (var item in list) {
      DateTime date = DateTime.fromMillisecondsSinceEpoch(item.createTime);
      String key = "${date.year}年${date.month}月"; 
      groups.putIfAbsent(key, () => []).add(item);
    }
    if (mounted) setState(() => _groupedItems = groups);
  }

  // --- 核心逻辑：同步云端文件到本地数据库 ---
  Future<void> _syncCloudToLocal() async {
    if (isRunning) return;
    try {
      final service = WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text);
      
      addLog("检查云端文件...");
      List<String> cloudFiles = await service.listRemoteFiles("MyPhotos/");
      if (cloudFiles.isEmpty) return;

      final dbRecords = await DbHelper.getAllRecords();
      final localKnownFiles = dbRecords.map((e) => e['filename'] as String?).toSet();
      final appDir = await getApplicationDocumentsDirectory();
      
      bool hasNewData = false;

      for (String fileName in cloudFiles) {
        if (!localKnownFiles.contains(fileName)) {
          hasNewData = true;
          // 生成虚拟ID
          String virtualId = "cloud_${fileName.hashCode}";
          String thumbLocalPath = '${appDir.path}/thumb_$virtualId.jpg';
          File thumbFile = File(thumbLocalPath);
          
          if (!thumbFile.existsSync()) {
             try {
                await service.downloadFile("MyPhotos/.thumbs/$fileName", thumbLocalPath);
             } catch (e) {
                continue; 
             }
          }

          await DbHelper.markAsUploaded(
              virtualId, 
              thumbPath: thumbLocalPath, 
              time: DateTime.now().millisecondsSinceEpoch, 
              filename: fileName
          );
        }
      }

      if (hasNewData) {
        addLog("发现新照片");
        if (mounted) _refreshGallery();
      }
    } catch (e) {
      addLog("同步异常: $e");
    }
  }

  // --- 核心逻辑：执行备份（含权限修复） ---
  Future<void> doBackup({bool silent = false}) async {
    if (isRunning) return;
    setState(() => isRunning = true);
    await _saveConfig();
    try {
      // 1. 权限检查
      bool hasPermission = false;
      if (Platform.isAndroid) {
        final ps = await PhotoManager.requestPermissionExtend();
        if (ps.isAuth) {
          hasPermission = true;
        } else {
           if (!silent && mounted) {
             showDialog(context: context, builder: (ctx) => AlertDialog(
               title: const Text("需要权限"),
               content: const Text("请在设置中允许访问照片权限"),
               actions: [
                 TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
                 TextButton(onPressed: () { Navigator.pop(ctx); openAppSettings(); }, child: const Text("去设置")),
               ],
             ));
           }
        }
      } else {
        if (await Permission.photos.request().isGranted || await Permission.photos.isLimited) hasPermission = true;
      }

      if (!hasPermission) {
        if (!silent) addLog("无权限");
        return;
      }

      // 2. 开始备份
      final service = WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text);
      await service.ensureFolder("MyPhotos/");
      await service.ensureFolder("MyPhotos/.thumbs/");
      
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      if (albums.isNotEmpty) {
        final photos = await albums.first.getAssetListPaged(page: 0, size: 200);
        final appDir = await getApplicationDocumentsDirectory();
        
        int count = 0;
        for (var asset in photos) {
          if (await DbHelper.isUploaded(asset.id)) continue;
          
          File? file = await asset.file;
          if (file == null) continue; // iCloud 未下载或异常
          
          String fileName = p.basename(file.path);
          addLog("上传: $fileName");
          
          await service.upload(file, "MyPhotos/$fileName");
          
          // 生成并上传缩略图
          final thumbData = await asset.thumbnailDataWithSize(const ThumbnailSize(300, 300));
          String? localThumbPath;
          if (thumbData != null) {
            await service.uploadBytes(thumbData, "MyPhotos/.thumbs/$fileName");
            final thumbFile = File('${appDir.path}/thumb_${asset.id}.jpg')..writeAsBytesSync(thumbData);
            localThumbPath = thumbFile.path;
          }
          
          await DbHelper.markAsUploaded(asset.id, thumbPath: localThumbPath, time: asset.createDateTime.millisecondsSinceEpoch, filename: fileName);
          if (mounted) setState(() => _sessionUploadedIds.add(asset.id));
          count++;
        }
        if (count > 0) addLog("备份完成: $count 张");
      }
    } catch (e) {
      addLog("错误: $e");
    } finally { 
      if (mounted) {
        setState(() => isRunning = false); 
        _refreshGallery(); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        onPressed: isRunning ? null : () => doBackup(),
        backgroundColor: isRunning ? Colors.grey : Colors.blueAccent,
        child: isRunning ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.cloud_upload),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _startColCount = _crossAxisCount,
        onScaleUpdate: (d) {
          if (d.pointerCount >= 2) {
            final newCount = (_startColCount / d.scale).round().clamp(2, 6);
            if (newCount != _crossAxisCount) setState(() => _crossAxisCount = newCount);
          }
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true, floating: true, expandedHeight: 80,
              backgroundColor: Colors.white,
              flexibleSpace: const FlexibleSpaceBar(title: Text("云相册", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
              actions: [
                IconButton(icon: const Icon(Icons.refresh, color: Colors.black87), onPressed: _syncCloudToLocal),
                IconButton(icon: const Icon(Icons.settings, color: Colors.black87), onPressed: _showSettingsPanel)
              ],
            ),
            SliverToBoxAdapter(
               child: Container(
                 height: 30, 
                 padding: const EdgeInsets.symmetric(horizontal: 16),
                 child: Text(_logs.isNotEmpty ? _logs.first : "准备就绪", style: const TextStyle(color: Colors.grey, fontSize: 12))
               )
            ),
            ..._buildSliverContent(),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSliverContent() {
    List<Widget> slivers = [];
    _groupedItems.forEach((date, items) {
      slivers.add(SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 10), child: Text(date, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))));
      slivers.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _crossAxisCount, crossAxisSpacing: 4, mainAxisSpacing: 4),
          delegate: SliverChildBuilderDelegate((_, i) => _buildPhotoTile(items[i], items, i), childCount: items.length),
        ),
      ));
    });
    return slivers;
  }

  Widget _buildPhotoTile(PhotoItem item, List<PhotoItem> group, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(galleryItems: group, initialIndex: index, service: WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text)))),
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Stack(fit: StackFit.expand, children: [
        SmartThumbnail(item: item, service: WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text)),
        if (item.isBackedUp) 
           Positioned(
             right: 5, top: 5, 
             child: Icon(item.asset == null ? Icons.cloud_download : Icons.cloud_done, 
             color: Colors.white, size: 18)
           ),
      ])),
    );
  }

  void _showSettingsPanel() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: "WebDAV URL (如: https://dav.jianguoyun.com/dav/)")),
      TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: "账号")),
      TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: "密码"), obscureText: true),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: () { Navigator.pop(context); doBackup(); }, child: const Text("保存并备份")),
    ])));
  }
}