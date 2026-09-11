import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import 'storage_service.dart';

/// S3 REST client using AWS Signature V4, including S3-compatible endpoints.
class S3Service implements StorageService {
  final String endpoint;
  final String region;
  final String bucket;
  final String accessKey;
  final String secretKey;
  final String sessionToken;
  final bool pathStyle;
  final Dio _dio;

  S3Service({
    required this.endpoint,
    required this.region,
    required this.bucket,
    required this.accessKey,
    required this.secretKey,
    this.sessionToken = '',
    this.pathStyle = true,
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(minutes: 2),
               sendTimeout: const Duration(minutes: 10),
             ),
           );

  @override
  String get cacheKey => sha256
      .convert(
        utf8.encode(
          's3|${endpoint.replaceAll(RegExp(r'/+$'), '')}|$bucket|$accessKey',
        ),
      )
      .toString();

  static String encode(String value) => utf8.encode(value).map((byte) {
    if ((byte >= 65 && byte <= 90) ||
        (byte >= 97 && byte <= 122) ||
        (byte >= 48 && byte <= 57) ||
        [45, 46, 95, 126].contains(byte)) {
      return String.fromCharCode(byte);
    }
    return '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}';
  }).join();

  Uri objectUri(String key, [Map<String, String> query = const {}]) {
    final base = Uri.parse(endpoint);
    final host = pathStyle ? base.host : '$bucket.${base.host}';
    final authority = base.hasPort ? '$host:${base.port}' : host;
    final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
    final path =
        '$prefix/${pathStyle ? '${encode(bucket)}/' : ''}'
        '${key.split('/').map(encode).join('/')}';
    final params =
        query.entries.map((e) => '${encode(e.key)}=${encode(e.value)}').toList()
          ..sort();
    return Uri.parse(
      '${base.scheme}://$authority$path${params.isEmpty ? '' : '?${params.join('&')}'}',
    );
  }

  Map<String, String> signedHeaders(
    String method,
    Uri uri,
    String payloadHash, {
    DateTime? now,
  }) {
    final timestamp =
        '${(now ?? DateTime.now()).toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';
    final date = timestamp.substring(0, 8);
    final headers = <String, String>{
      'host': uri.authority,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': timestamp,
      if (sessionToken.isNotEmpty) 'x-amz-security-token': sessionToken,
    };
    final names = headers.keys.toList()..sort();
    final canonicalHeaders = names
        .map((name) => '$name:${headers[name]!.trim()}\n')
        .join();
    final signedNames = names.join(';');
    final canonical =
        '$method\n${uri.path}\n${uri.query}\n$canonicalHeaders\n$signedNames\n$payloadHash';
    final scope = '$date/$region/s3/aws4_request';
    final toSign =
        'AWS4-HMAC-SHA256\n$timestamp\n$scope\n${sha256.convert(utf8.encode(canonical))}';
    List<int> hmac(List<int> key, String value) =>
        Hmac(sha256, key).convert(utf8.encode(value)).bytes;
    final signingKey = hmac(
      hmac(hmac(hmac(utf8.encode('AWS4$secretKey'), date), region), 's3'),
      'aws4_request',
    );
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(toSign));
    headers['Authorization'] =
        'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, SignedHeaders=$signedNames, Signature=$signature';
    return headers;
  }

  Future<Response<dynamic>> _request(
    String method,
    String key, {
    Map<String, String> query = const {},
    Stream<List<int>>? data,
    int? length,
    String? payloadHash,
    String? downloadPath,
  }) async {
    final uri = objectUri(key, query);
    final headers = <String, dynamic>{
      ...signedHeaders(
        method,
        uri,
        payloadHash ?? sha256.convert(const <int>[]).toString(),
      ),
      Headers.contentLengthHeader: ?length,
    };
    final options = Options(
      method: method,
      headers: headers,
      responseType: ResponseType.plain,
      followRedirects: false,
    );
    try {
      if (downloadPath != null) {
        return await _dio.download(
          uri.toString(),
          downloadPath,
          options: options,
        );
      }
      return await _dio.request(uri.toString(), data: data, options: options);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Do not expose signed request headers or credentials in UI logs.
      throw Exception(
        status == 401 || status == 403
            ? 'S3 认证或权限不足，请检查密钥、区域和存储桶权限'
            : status == 301 || status == 307
            ? 'S3 地址或区域不匹配，请填写存储桶所在区域的 Endpoint'
            : 'S3 请求失败${status == null ? '，请检查网络和 Endpoint' : ' (HTTP $status)'}',
      );
    }
  }

  @override
  Future<void> ensureFolder(String folderName) async {} // S3 uses key prefixes.

  @override
  Future<List<String>> listRemoteFiles(String folderPath) async {
    final prefix = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    final files = <String>{};
    final seenTokens = <String>{};
    String? token;
    do {
      final response = await _request(
        'GET',
        '',
        query: {
          'list-type': '2',
          'prefix': prefix,
          'delimiter': '/',
          'encoding-type': 'url',
          'continuation-token': ?token,
        },
      );
      final document = XmlDocument.parse(response.data as String);
      String? value(String name) => document.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == name)
          .firstOrNull
          ?.innerText;
      for (final element in document.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'Key',
      )) {
        final key = Uri.decodeComponent(element.innerText);
        if (!key.startsWith(prefix)) continue;
        final name = key.substring(prefix.length);
        if (name.contains('/') || name.contains('\\') || name.startsWith('.')) {
          continue;
        }
        if (RegExp(
          r'\.(jpe?g|png|heic|heif|webp|gif)$',
          caseSensitive: false,
        ).hasMatch(name)) {
          files.add(name);
        }
      }
      if (value('IsTruncated') != 'true') break;
      token = value('NextContinuationToken');
      if (token == null || token.isEmpty || !seenTokens.add(token)) {
        throw const FormatException('S3 分页响应缺少有效的继续标记');
      }
    } while (true);
    return files.toList()..sort();
  }

  @override
  Future<void> upload(File file, String remotePath) async {
    final hash = await sha256.bind(file.openRead()).first;
    await _request(
      'PUT',
      remotePath,
      data: file.openRead(),
      length: await file.length(),
      payloadHash: hash.toString(),
    );
  }

  @override
  Future<void> uploadBytes(Uint8List bytes, String remotePath) async {
    await _request(
      'PUT',
      remotePath,
      data: Stream.value(bytes),
      length: bytes.length,
      payloadHash: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    await _request('GET', remotePath, downloadPath: localPath);
  }

  @override
  Future<void> delete(String remotePath) async {
    await _request('DELETE', remotePath);
  }
}
