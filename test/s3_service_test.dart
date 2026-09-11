import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_2/Services/s3_service.dart';

S3Service service({
  String endpoint = 'https://s3.amazonaws.com',
  bool pathStyle = false,
  String token = '',
  String bucket = 'examplebucket',
}) => S3Service(
  endpoint: endpoint,
  region: 'us-east-1',
  bucket: bucket,
  accessKey: 'AKIAIOSFODNN7EXAMPLE',
  secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  pathStyle: pathStyle,
  sessionToken: token,
);

void main() {
  test('matches AWS published list-objects signature vector', () {
    final client = service();
    final headers = client.signedHeaders(
      'GET',
      client.objectUri('', {'prefix': 'J', 'max-keys': '2'}),
      sha256.convert([]).toString(),
      now: DateTime.utc(2013, 5, 24),
    );
    expect(
      headers['Authorization'],
      endsWith(
        'Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7',
      ),
    );
  });

  test('encodes unicode, punctuation and opaque pagination tokens', () {
    final client = service(endpoint: 'http://localhost:9000', pathStyle: true);
    expect(
      client.objectUri("MyPhotos/照片 +%!'().jpg").toString(),
      'http://localhost:9000/examplebucket/MyPhotos/%E7%85%A7%E7%89%87%20%2B%25%21%27%28%29.jpg',
    );
    expect(
      client.objectUri('', {'continuation-token': 'a+/=&'}).query,
      'continuation-token=a%2B%2F%3D%26',
    );
    final headers = service(
      token: 'temporary-token',
    ).signedHeaders('GET', client.objectUri(''), sha256.convert([]).toString());
    expect(headers['x-amz-security-token'], 'temporary-token');
    expect(
      headers['Authorization'],
      contains('x-amz-date;x-amz-security-token'),
    );
    expect(service(bucket: 'other').cacheKey, isNot(client.cacheKey));
  });

  test('round trips objects and reads multiple listing pages over HTTP', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dir = await Directory.systemTemp.createTemp('s3_test_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final stored = <String, List<int>>{};
    final requests = <String>[];
    var listCount = 0;
    server.listen((request) async {
      requests.add(request.method);
      expect(
        request.headers.value('authorization'),
        startsWith('AWS4-HMAC-SHA256'),
      );
      if (request.uri.queryParameters['list-type'] == '2') {
        listCount++;
        expect(request.uri.queryParameters['prefix'], 'MyPhotos/');
        if (listCount == 1) {
          request.response.write(
            '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><IsTruncated>true</IsTruncated><NextContinuationToken>a+/=&amp;</NextContinuationToken><Contents><Key>MyPhotos%2F%E7%85%A7%E7%89%87%20%2B.jpg</Key></Contents><Contents><Key>MyPhotos%2F.thumbs%2Fhidden.jpg</Key></Contents><Contents><Key>MyPhotos%2Freadme.txt</Key></Contents></ListBucketResult>',
          );
        } else {
          expect(request.uri.queryParameters['continuation-token'], 'a+/=&');
          request.response.write(
            '<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>MyPhotos%2Fsecond.png</Key></Contents></ListBucketResult>',
          );
        }
      } else if (request.method == 'PUT') {
        final bytes = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        expect(
          request.headers.value('x-amz-content-sha256'),
          sha256.convert(bytes).toString(),
        );
        expect(request.contentLength, bytes.length);
        stored[request.uri.path] = bytes;
      } else if (request.method == 'GET') {
        request.response.add(stored[request.uri.path]!);
      } else if (request.method == 'DELETE') {
        stored.remove(request.uri.path);
        request.response.statusCode = 204;
      }
      await request.response.close();
    });
    final client = service(
      endpoint: 'http://127.0.0.1:${server.port}',
      pathStyle: true,
    );
    final bytes = Uint8List.fromList(utf8.encode('photo bytes'));
    await client.ensureFolder('MyPhotos/');
    expect(requests, isEmpty);
    await client.uploadBytes(bytes, 'MyPhotos/照片 +.jpg');
    final download = File('${dir.path}/download.jpg');
    await client.downloadFile('MyPhotos/照片 +.jpg', download.path);
    expect(await download.readAsBytes(), bytes);
    await client.upload(download, 'MyPhotos/second.png');
    expect(await client.listRemoteFiles('MyPhotos/'), [
      'second.png',
      '照片 +.jpg',
    ]);
    expect(listCount, 2);
    await client.delete('MyPhotos/照片 +.jpg');
    expect(stored.length, 1);
  });

  test(
    'rejects truncated listings without token and redacts HTTP errors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var forbidden = false;
      server.listen((request) async {
        if (forbidden) {
          request.response.statusCode = 403;
        } else {
          request.response.write(
            '<ListBucketResult><IsTruncated>true</IsTruncated></ListBucketResult>',
          );
        }
        await request.response.close();
      });
      final client = service(
        endpoint: 'http://127.0.0.1:${server.port}',
        pathStyle: true,
      );
      await expectLater(
        client.listRemoteFiles('MyPhotos'),
        throwsFormatException,
      );
      forbidden = true;
      await expectLater(
        client.listRemoteFiles('MyPhotos'),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('权限不足') && !e.toString().contains('AKIA'),
          ),
        ),
      );
    },
  );
}
