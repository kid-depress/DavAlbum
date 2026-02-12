import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:photo_manager/photo_manager.dart';

// --- 1. 更新模型：增加 remoteFileName ---
class PhotoItem {
  final String id;
  final AssetEntity? asset;        
  final String? localThumbPath;    
  final String? remoteFileName;    // 【新增】云端文件名 (如 IMG_001.jpg)
  final int createTime;            
  final bool isBackedUp;

  PhotoItem({
    required this.id, 
    this.asset, 
    this.localThumbPath, 
    this.remoteFileName,           // 【新增】
    required this.createTime, 
    this.isBackedUp = false
  });
}

class WebDavService {
  final String url;
  final String user;
  final String pass;
  late Dio _dio;

  WebDavService({required this.url, required this.user, required this.pass}) {
    String cleanUrl = url.endsWith('/') ? url : '$url/';
    _dio = Dio(BaseOptions(
      baseUrl: cleanUrl,
      headers: {"Authorization": "Basic ${base64Encode(utf8.encode("$user:$pass"))}"},
    ));
  }

  Future<void> ensureFolder(String folderName) async {
    try {
      await _dio.request(folderName, options: Options(method: "MKCOL"));
    } on DioException catch (e) {
      if (e.response?.statusCode != 405) rethrow; 
    }
  }

  Future<void> upload(File file, String remotePath) async {
    await _dio.put(remotePath, data: file.openRead(), options: Options(headers: {Headers.contentLengthHeader: await file.length()}));
  }

  Future<void> uploadBytes(Uint8List bytes, String remotePath) async {
    await _dio.put(remotePath, data: Stream.fromIterable(bytes.map((e) => [e])), options: Options(headers: {Headers.contentLengthHeader: bytes.length}));
  }

  // 【新增】获取文件列表 (用于换机同步)
  Future<List<String>> listFiles(String folder) async {
    try {
      final response = await _dio.request(folder, options: Options(method: "PROPFIND", headers: {"Depth": "1"}));
      // 简单正则提取文件名
      final matches = RegExp(r'<d:href>([^<]+)</d:href>').allMatches(response.data.toString());
      return matches
          .map((m) => Uri.decodeFull(m.group(1)!))
          .where((path) => path.toLowerCase().endsWith('.jpg') || path.toLowerCase().endsWith('.png') || path.toLowerCase().endsWith('.heic'))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // 【新增】下载文件
  Future<void> downloadFile(String remotePath, String localPath) async {
    await _dio.download(remotePath, localPath);
  }
}