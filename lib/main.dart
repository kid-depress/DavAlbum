import 'dart:io';
import 'dart:typed_data';
import 'dart:ui'; // 用于磨砂效果
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db_helper.dart';
import 'webdav_service.dart';
import 'photo_view_page.dart';

void main() {
  // 设置状态栏透明
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.light,
    home: SuperBackupPage(),
  ));
}

class SuperBackupPage extends StatefulWidget {
  const SuperBackupPage({super.key});
  @override
  State<SuperBackupPage> createState() => _SuperBackupPageState();
}

class _SuperBackupPageState extends State<SuperBackupPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  
  // 日志列表，用于在设置页显示
  List<String> _logs = [];
  bool isRunning = false;
  
  Map<String, List<PhotoItem>> _groupedItems = {}; 
  int _crossAxisCount = 3; 
  int _startColCount = 3; 

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

  void addLog(String m) {
    // 只保留最近 50 条日志
    setState(() {
      _logs.insert(0, m); 
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  // --- 核心业务逻辑 (保持不变) ---
  Future<void> _refreshGallery() async {
    final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    List<AssetEntity> localAssets = [];
    if (albums.isNotEmpty) {
      localAssets = await albums.first.getAssetListPaged(page: 0, size: 500);
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

    Map<String, List<PhotoItem>> groups = {};
    for (var item in list) {
      DateTime date = DateTime.fromMillisecondsSinceEpoch(item.createTime);
      String key = "${date.year}年${date.month}月"; 
      if (!groups.containsKey(key)) groups[key] = [];
      groups[key]!.add(item);
    }
    
    if (mounted) setState(() => _groupedItems = groups);
  }

  Future<void> _clearCache() async {
    try {
      final appDir = await getTemporaryDirectory();
      int count = 0;
      if (appDir.existsSync()) {
        appDir.listSync().forEach((FileSystemEntity entity) {
          if (entity is File && p.basename(entity.path).startsWith('temp_')) {
            entity.deleteSync();
            count++;
          }
        });
      }
      addLog("🧹 已清理 $count 个缓存文件");
    } catch (e) {
      addLog("❌ 清理失败: $e");
    }
  }

  Future<void> _syncDatabase({bool isRestore = false}) async {
    if (isRunning) return;
    setState(() => isRunning = true);
    addLog(isRestore ? "📥 正在恢复数据库..." : "📤 正在备份数据库...");
    
    try {
      final service = WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text);
      await service.ensureFolder("MyPhotos/");
      final dbPath = await DbHelper.getDbPath();
      
      if (isRestore) {
        await DbHelper.close(); 
        await service.downloadFile("MyPhotos/backup_records.db", dbPath);
        addLog("✅ 数据库恢复成功！");
        await _refreshGallery(); 
      } else {
        if (File(dbPath).existsSync()) {
          await service.upload(File(dbPath), "MyPhotos/backup_records.db");
          addLog("✅ 数据库备份成功！");
        }
      }
    } catch (e) {
      addLog("❌ 操作失败: $e");
    } finally {
      setState(() => isRunning = false);
    }
  }

  Future<void> doBackup() async {
    if (isRunning) return;
    setState(() => isRunning = true);
    addLog("🚀 开始备份...");
    await _saveConfig();

    try {
      final service = WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text);
      if (!(await Permission.photos.request().isGranted)) {
         addLog("❌ 无相册权限");
         return;
      }

      await service.ensureFolder("MyPhotos/");
      await service.ensureFolder("MyPhotos/.thumbs/");

      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      if (albums.isNotEmpty) {
        final photos = await albums.first.getAssetListPaged(page: 0, size: 50); // 每次50张
        final appDir = await getApplicationDocumentsDirectory();
        int count = 0;

        for (var asset in photos) {
          if (await DbHelper.isUploaded(asset.id)) continue;

          File? file = await asset.file;
          if (file == null) continue;

          String fileName = p.basename(file.path);
          
          // 更新UI提示，不刷屏
          // addLog("正在传: $fileName"); 

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
          // 局部刷新太频繁会卡顿，建议每几张刷新一次
          if (count % 5 == 0) await _refreshGallery(); 
        }
        addLog("✅ 备份完成：新增 $count 张");
        
        final dbFile = File(await DbHelper.getDbPath());
        await service.upload(dbFile, "MyPhotos/backup_records.db");
        addLog("☁️ 数据库已同步");
      }
    } catch (e) {
      addLog("❌ 失败: $e");
    } finally {
      setState(() => isRunning = false);
      _refreshGallery(); // 最后刷新一次
    }
  }

  // --- UI 构建 ---

  // 显示设置面板 (Bottom Sheet)
  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允许全屏
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: controller,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text("服务器配置", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              _buildTextField(_urlCtrl, "WebDAV 地址", Icons.link),
              const SizedBox(height: 10),
              _buildTextField(_userCtrl, "用户名", Icons.person),
              const SizedBox(height: 10),
              _buildTextField(_passCtrl, "密码", Icons.lock, isObscure: true),
              const SizedBox(height: 20),
              const Text("高级功能", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildActionButton(Icons.restore, "恢复数据", Colors.orange, () => _syncDatabase(isRestore: true)),
                  _buildActionButton(Icons.cleaning_services, "清理缓存", Colors.grey, _clearCache),
                ],
              ),
              const SizedBox(height: 20),
              const Text("运行日志", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                height: 150,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(_logs[i], style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom), // 键盘避让
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {bool isObscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isObscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blueGrey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // 点击后关闭面板
        onTap();
      },
      child: Column(
        children: [
          CircleAvatar(radius: 25, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 悬浮按钮：备份
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isRunning ? null : doBackup,
        icon: isRunning 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.cloud_upload),
        label: Text(isRunning ? "正在同步..." : "开始备份"),
        backgroundColor: isRunning ? Colors.grey : Colors.blueAccent,
        elevation: 4,
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. 沉浸式标题栏
          SliverAppBar(
            expandedHeight: 120.0,
            floating: true,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: const Text(
                "TimeAlbum", 
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
              ),
              background: Container(color: Colors.white),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.black87),
                onPressed: _showSettingsPanel, // 点击打开设置面板
              ),
            ],
          ),
          
          // 2. 照片内容
          if (_groupedItems.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 10),
                    Text("暂无照片，请点击右下角备份", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 80), // 底部留白给FAB
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = _groupedItems.entries.elementAt(index);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 日期标题
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                          child: Text(
                            entry.key, 
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ),
                        // 照片网格
                        GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shrinkWrap: true, // 关键：让GridView在SliverList里自适应高度
                          physics: const NeverScrollableScrollPhysics(), // 禁止内部滚动
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _crossAxisCount,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                          ),
                          itemCount: entry.value.length,
                          itemBuilder: (_, i) => _buildPhotoTile(entry.value[i], entry.value, i),
                        ),
                      ],
                    );
                  },
                  childCount: _groupedItems.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoTile(PhotoItem item, List<PhotoItem> groupList, int index) {
    return GestureDetector(
      onTap: () {
        final service = WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text);
        Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(
          galleryItems: groupList, 
          initialIndex: index,
          service: service
        )));
      },
      child: ClipRRect( // 圆角效果
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            SmartThumbnail(
              item: item, 
              service: WebDavService(url: _urlCtrl.text, user: _userCtrl.text, pass: _passCtrl.text)
            ),
            // 云端状态图标优化
            if (item.isBackedUp)
              Positioned(
                right: 4, 
                top: 4, 
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3), // 半透明背景
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_done, color: Colors.white, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// SmartThumbnail 组件保持不变，这里省略，请保留原有的 SmartThumbnail 代码
class SmartThumbnail extends StatefulWidget {
  final PhotoItem item;
  final WebDavService service;
  const SmartThumbnail({super.key, required this.item, required this.service});
  @override
  State<SmartThumbnail> createState() => _SmartThumbnailState();
}

class _SmartThumbnailState extends State<SmartThumbnail> {
  File? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  Future<void> _checkAndLoad() async {
    if (widget.item.asset != null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final targetPath = '${appDir.path}/thumb_${widget.item.id}.jpg';
    final file = File(targetPath);
    if (file.existsSync()) {
      if (mounted) setState(() => _imageFile = file);
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    try {
      String remoteName = widget.item.remoteFileName ?? "${widget.item.id}.jpg";
      if (!remoteName.contains('.')) remoteName += ".jpg";
      await widget.service.downloadFile("MyPhotos/.thumbs/$remoteName", targetPath);
      await DbHelper.markAsUploaded(widget.item.id, thumbPath: targetPath, time: widget.item.createTime, filename: widget.item.remoteFileName);
      if (mounted) setState(() { _imageFile = File(targetPath); _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.asset != null) {
      return FutureBuilder<Uint8List?>(
        future: widget.item.asset!.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
        builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : Container(color: Colors.grey[200]),
      );
    }
    if (_imageFile != null) return Image.file(_imageFile!, fit: BoxFit.cover);
    if (_isLoading) return Container(color: Colors.grey[200], child: const Center(child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))));
    return Container(color: Colors.grey[300], child: const Icon(Icons.cloud_download, color: Colors.white));
  }
}