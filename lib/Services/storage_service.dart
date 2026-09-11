import 'dart:io';
import 'dart:typed_data';

abstract class StorageService {
  String get cacheKey;
  Future<void> ensureFolder(String folderName);
  Future<List<String>> listRemoteFiles(String folderPath);
  Future<void> upload(File file, String remotePath);
  Future<void> uploadBytes(Uint8List bytes, String remotePath);
  Future<void> downloadFile(String remotePath, String localPath);
  Future<void> delete(String remotePath);
}
