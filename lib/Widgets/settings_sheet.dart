import 'package:flutter/material.dart';

class SettingsSheet extends StatefulWidget {
  final TextEditingController urlCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final Map<String, TextEditingController> s3Controllers;
  final String provider;
  final bool pathStyle;
  final void Function(String provider, bool pathStyle) onSave;

  const SettingsSheet({
    super.key,
    required this.urlCtrl,
    required this.userCtrl,
    required this.passCtrl,
    required this.s3Controllers,
    required this.provider,
    required this.pathStyle,
    required this.onSave,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _provider = widget.provider;
  late bool _pathStyle = widget.pathStyle;
  late final _url = TextEditingController(text: widget.urlCtrl.text);
  late final _user = TextEditingController(text: widget.userCtrl.text);
  late final _pass = TextEditingController(text: widget.passCtrl.text);
  late final _s3 = {
    for (final entry in widget.s3Controllers.entries)
      entry.key: TextEditingController(text: entry.value.text),
  };

  @override
  void dispose() {
    for (final controller in [_url, _user, _pass, ..._s3.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    bool optional = false,
    String? hint,
    bool address = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return optional ? null : '请填写$label';
        if (address) {
          final uri = Uri.tryParse(text);
          if (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty ||
              uri.hasQuery ||
              uri.hasFragment) {
            return '请输入完整的 http:// 或 https:// 地址，不含账号和查询参数';
          }
        }
        if (label == 'Bucket' &&
            (text.contains('/') || text.contains(' ') || text.contains('\\'))) {
          return '请填写存储桶名称，不含路径';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      MediaQuery.of(context).viewInsets.bottom + 24,
    ),
    child: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('连接设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'webdav',
                label: Text('WebDAV'),
                icon: Icon(Icons.cloud_outlined),
              ),
              ButtonSegment(
                value: 's3',
                label: Text('S3'),
                icon: Icon(Icons.storage_outlined),
              ),
            ],
            selected: {_provider},
            onSelectionChanged: (value) =>
                setState(() => _provider = value.first),
          ),
          const SizedBox(height: 24),
          if (_provider == 'webdav') ...[
            _field(_url, 'WebDAV 地址', address: true),
            _field(_user, '用户名'),
            _field(_pass, '密码', secret: true),
          ] else ...[
            _field(
              _s3['endpoint']!,
              'Endpoint',
              address: true,
              hint: 'https://s3.us-east-1.amazonaws.com',
            ),
            _field(_s3['region']!, 'Region', hint: 'us-east-1'),
            _field(_s3['bucket']!, 'Bucket'),
            _field(_s3['accessKey']!, 'Access Key ID'),
            _field(_s3['secretKey']!, 'Secret Access Key', secret: true),
            _field(
              _s3['sessionToken']!,
              'Session Token（可选）',
              secret: true,
              optional: true,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('路径式访问'),
              subtitle: const Text('开启：Endpoint/Bucket；关闭：Bucket.Endpoint'),
              value: _pathStyle,
              onChanged: (value) => setState(() => _pathStyle = value),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('请先创建存储桶，并授予列出、读取、写入和删除对象的权限。照片保存在 MyPhotos/。'),
            ),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                widget.urlCtrl.text = _url.text.trim();
                widget.userCtrl.text = _user.text;
                widget.passCtrl.text = _pass.text;
                for (final entry in _s3.entries) {
                  widget.s3Controllers[entry.key]!.text = entry.value.text;
                }
                widget.onSave(_provider, _pathStyle);
                Navigator.pop(context);
              },
              child: const Text('保存并开始备份'),
            ),
          ),
        ],
      ),
    ),
  );
}
