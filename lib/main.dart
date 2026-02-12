import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db_helper.dart';
import 'webdav_service.dart';
import 'photo_view_page.dart';

void main() => runApp(const MaterialApp(home: SuperBackupPage()));

class SuperBackupPage extends StatefulWidget {
  const SuperBackupPage({super.key});
  @override
  State<SuperBackupPage> createState() => _SuperBackupPageState();
}

class _SuperBackupPageState extends State<SuperBackupPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String log = "等待操作...";
  bool isRunning = false;
  
  List<PhotoItem> _displayItems = []; 
  int _crossAxisCount = 3; // 当前列数
  int _startColCount = 3;  // 记录缩放开始时的列数

  @override
  void initState() {
    super.initState();
    _loadConfig();
    Future.delayed(Duration.zero, () => _refreshGallery());
  }

  _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlCtrl.text = prefs.getString('url') ?? "";
      _userCtrl.text = prefs.getString('user') ?? "";
      _passCtrl.text = prefs.getString('pass') ?? "";
    });
  }

  _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('url', _urlCtrl.text);
    await prefs.setString('user', _userCtrl.text);
    await prefs.setString('pass', _passCtrl.text);
  }

  void addLog(String m) => setState(() => log += "\n$m");

  Future<void> _refreshGallery() async {
    final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    List<AssetEntity> localAssets = [];
    if (albums.isNotEmpty) {
      localAssets = await albums.first.getAssetListPaged(page: 0, size: 100);
    }

    final dbRecords = await DbHelper.getAllRecords();
    Map<String, PhotoItem> mergedMap = {};

    for (var row in dbRecords) {
      String id = row['asset_id'];
      mergedMap[id] = PhotoItem(
        id: id,
        localThumbPath: row['thumbnail_path'],
        remoteFileName: row['filename'],
        createTime: row['create_time'] ?? 0,
        isBackedUp: true,
      );
    }

    for (var asset in localAssets) {
      bool backed = mergedMap.containsKey(asset.id);
      mergedMap[asset.id] = PhotoItem(
        id: asset.id,
        asset: asset,
        localThumbPath: backed ? mergedMap[asset.id]?.localThumbPath : null,
        remoteFileName: backed ? mergedMap[asset.id]?.remoteFileName : null,
        createTime: asset.createDateTime.millisecondsSinceEpoch,
        isBackedUp: backed,
      );
    }

    var list = mergedMap.values.toList();
    list.sort((a, b) => b.createTime.compareTo(a.createTime));
    
    if (mounted) setState(() => _displayItems = list);
  }

  Future<void> doBackup() async {
    if (isRunning) return;
    setState(() { isRunning = true; log = "🚀 开始备份..."; });
    await _saveConfig();

    try {
      final service = WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text);
      if (!(await Permission.photos.request().isGranted)) return addLog("❌ 无相册权限");

      await service.ensureFolder("MyPhotos/");
      await service.ensureFolder("MyPhotos/.thumbs/");

      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      if (albums.isNotEmpty) {
        final photos = await albums.first.getAssetListPaged(page: 0, size: 50);
        final appDir = await getApplicationDocumentsDirectory();
        int count = 0;

        for (var asset in photos) {
          if (await DbHelper.isUploaded(asset.id)) continue;

          File? file = await asset.file;
          if (file == null) continue;

          String fileName = p.basename(file.path);
          addLog("正在传: $fileName");

          await service.upload(file, "MyPhotos/$fileName");

          final thumbData = await asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
          String? localPath;
          
          if (thumbData != null) {
            await service.uploadBytes(thumbData, "MyPhotos/.thumbs/$fileName");
            final thumbFile = File('${appDir.path}/thumb_${asset.id}.jpg');
            await thumbFile.writeAsBytes(thumbData);
            localPath = thumbFile.path;
          }

          await DbHelper.markAsUploaded(
            asset.id, 
            thumbPath: localPath,
            time: asset.createDateTime.millisecondsSinceEpoch,
            filename: fileName
          );
          
          count++;
          await _refreshGallery(); 
        }
        addLog("✅ 完成！新增 $count 张");
      }
    } catch (e) {
      addLog("❌ 失败: $e");
    } finally {
      setState(() => isRunning = false);
    }
  }

  Future<void> syncFromCloud() async {
    if (isRunning) return;
    setState(() { isRunning = true; log = "🔍 拉取云端数据..."; });
    try {
      final service = WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text);
      final remoteFiles = await service.listFiles("MyPhotos/");
      final appDir = await getApplicationDocumentsDirectory();
      int syncCount = 0;

      for (var remotePath in remoteFiles) {
        String fileName = p.basename(remotePath); 
        String assetId = fileName; 

        if (!(await DbHelper.isUploaded(assetId))) {
          String localThumb = '${appDir.path}/thumb_$assetId.jpg';
          try {
            await service.downloadFile("MyPhotos/.thumbs/$fileName", localThumb);
            syncCount++;
          } catch (_) {}

          await DbHelper.markAsUploaded(
            assetId, 
            thumbPath: localThumb, 
            time: DateTime.now().millisecondsSinceEpoch,
            filename: fileName 
          );
        }
      }
      addLog("✅ 同步完成！拉回 $syncCount 条记录");
      await _refreshGallery(); 
    } catch (e) {
      addLog("❌ 同步失败: $e");
    } finally {
      setState(() => isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("云相册 (融合版)")),
      body: Column(
        children: [
          ExpansionTile(
            title: const Text("配置 & 操作"),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: "服务器")),
                  TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: "账号")),
                  TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: "密码"), obscureText: true),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(onPressed: isRunning ? null : doBackup, child: const Text("备份相册")),
                      ElevatedButton(onPressed: isRunning ? null : syncFromCloud, child: const Text("换机同步")),
                    ],
                  ),
                  Container(height: 60, color: Colors.black12, child: SingleChildScrollView(child: Text(log, style: const TextStyle(fontSize: 10)))),
                ]),
              ),
            ],
          ),
          Expanded(
            child: _displayItems.isEmpty 
              ? const Center(child: Text("暂无照片，请尝试备份或同步"))
              : GestureDetector(
                  onScaleStart: (details) {
                    _startColCount = _crossAxisCount; // 记录起始列数
                  },
                  onScaleUpdate: (details) {
                    // 比例计算法：起始列数 / 缩放比例，并四舍五入
                    // clamp(2, 6) 确保列数在 2 到 6 之间
                    final newCount = (_startColCount / details.scale).round().clamp(2, 6);
                    if (newCount != _crossAxisCount) {
                      setState(() {
                        _crossAxisCount = newCount;
                      });
                    }
                  },
                  child: GridView.builder(
                    physics: const BouncingScrollPhysics(), // 避免手势冲突
                    padding: const EdgeInsets.all(4),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _crossAxisCount, 
                      crossAxisSpacing: 4, 
                      mainAxisSpacing: 4
                    ),
                    itemCount: _displayItems.length,
                    itemBuilder: (context, index) {
                      final item = _displayItems[index];
                      return GestureDetector(
                        onTap: () {
                          final service = WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(
                            galleryItems: _displayItems,
                            initialIndex: index,
                            service: service,
                          )));
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Builder(builder: (context) {
                              if (item.asset != null) {
                                return FutureBuilder<Uint8List?>(
                                  future: item.asset!.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
                                  builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : Container(color: Colors.grey[200]),
                                );
                              } 
                              else if (item.localThumbPath != null && File(item.localThumbPath!).existsSync()) {
                                return Image.file(File(item.localThumbPath!), fit: BoxFit.cover);
                              }
                              return Container(color: Colors.grey[300], child: const Icon(Icons.cloud_download));
                            }),
                            if (item.isBackedUp)
                              const Positioned(right: 4, top: 4, child: Icon(Icons.cloud_done, color: Colors.green, size: 20)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
    );
  }
}