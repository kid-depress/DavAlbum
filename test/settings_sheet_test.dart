import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_2/Widgets/settings_sheet.dart';

void main() {
  late TextEditingController url;
  late TextEditingController user;
  late TextEditingController pass;
  late Map<String, TextEditingController> s3;
  String? savedProvider;
  setUp(() {
    url = TextEditingController(text: 'https://dav.example.com');
    user = TextEditingController(text: 'user');
    pass = TextEditingController(text: 'password');
    s3 = {
      for (final key in [
        'endpoint',
        'region',
        'bucket',
        'accessKey',
        'secretKey',
        'sessionToken',
      ])
        key: TextEditingController(),
    };
    savedProvider = null;
  });
  tearDown(() {
    for (final ctrl in [url, user, pass, ...s3.values]) {
      ctrl.dispose();
    }
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SettingsSheet(
                    urlCtrl: url,
                    userCtrl: user,
                    passCtrl: pass,
                    s3Controllers: s3,
                    provider: 'webdav',
                    pathStyle: true,
                    onSave: (provider, pathStyle) {
                      savedProvider = provider;
                    },
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel leaves saved configuration unchanged', (tester) async {
    await open(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://changed.example.com',
    );
    Navigator.of(tester.element(find.byType(SettingsSheet))).pop();
    await tester.pumpAndSettle();
    expect(url.text, 'https://dav.example.com');
    expect(savedProvider, isNull);
  });
  testWidgets('S3 requires fields and saves complete settings', (tester) async {
    await open(tester);
    await tester.tap(find.text('S3'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存并开始备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并开始备份'));
    await tester.pumpAndSettle();
    expect(savedProvider, isNull);
    final fields = find.byType(TextFormField);
    final values = [
      'https://s3.us-east-1.amazonaws.com',
      'us-east-1',
      'my-photos',
      'access-key',
      'secret-key',
      '',
    ];
    for (var index = 0; index < values.length; index++) {
      await tester.ensureVisible(fields.at(index));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(index), values[index]);
    }
    await tester.ensureVisible(find.text('保存并开始备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并开始备份'));
    await tester.pumpAndSettle();
    expect(savedProvider, 's3');
    expect(s3['bucket']!.text, 'my-photos');
    expect(s3['secretKey']!.text, 'secret-key');
    expect(url.text, 'https://dav.example.com');
    expect(tester.takeException(), isNull);
  });
}
