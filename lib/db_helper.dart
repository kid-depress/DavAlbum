import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DbHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    String path = join(await getDatabasesPath(), 'backup_records.db');
    return await openDatabase(
      path,
      // 【关键修改 1】版本号必须升级到 3，否则 onUpgrade 不会执行
      version: 3, 
      onCreate: (db, version) {
        // 新安装用户直接创建完整的表
        return db.execute(
          'CREATE TABLE uploaded_assets(asset_id TEXT PRIMARY KEY, thumbnail_path TEXT, create_time INTEGER, filename TEXT)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) {
        // 【关键修改 2】老用户升级逻辑
        // 如果是从版本 1 升上来的
        if (oldVersion < 2) {
          db.execute('ALTER TABLE uploaded_assets ADD COLUMN thumbnail_path TEXT');
        }
        // 如果是从版本 2 升上来的（你现在就是这种情况）
        if (oldVersion < 3) {
          // 加上缺少的 create_time 和 filename 字段
          try {
            db.execute('ALTER TABLE uploaded_assets ADD COLUMN create_time INTEGER');
          } catch (_) {} // 防止重复添加报错
          try {
            db.execute('ALTER TABLE uploaded_assets ADD COLUMN filename TEXT');
          } catch (_) {}
        }
      },
    );
  }

  // 标记已上传
  static Future<void> markAsUploaded(String id, {String? thumbPath, int? time, String? filename}) async {
    final database = await db;
    await database.insert(
      'uploaded_assets',
      {
        'asset_id': id, 
        'thumbnail_path': thumbPath, 
        'create_time': time,     // 确保这里能写入
        'filename': filename     // 确保这里能写入
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 获取所有记录
  static Future<List<Map<String, dynamic>>> getAllRecords() async {
    final database = await db;
    // 按创建时间倒序排列
    return await database.query('uploaded_assets', orderBy: 'create_time DESC');
  }

  // 检查是否已上传
  static Future<bool> isUploaded(String id) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'uploaded_assets',
      where: 'asset_id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty;
  }
  
  // 获取本地缩略图路径 (兼容旧代码)
  static Future<String?> getThumbPath(String id) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'uploaded_assets',
      where: 'asset_id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) return maps.first['thumbnail_path'] as String?;
    return null;
  }
}