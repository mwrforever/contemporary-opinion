import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../widgets/section.dart';
import '../widgets/field_label.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;
  const SettingsScreen({super.key, required this.settings});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.settings.ringSecondsDefault.toString();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = int.tryParse(_ctrl.text.trim());
    if (n == null || n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效秒数（1~600）')),
      );
      return;
    }
    await widget.settings.setRingSecondsDefault(n);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Section(
            title: '提醒',
            children: [
              const FieldLabel('默认响铃时长（秒）'),
              TextFormField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '默认 5，范围 1~600',
                  suffixText: '秒',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('保存')),
            ],
          ),
        ],
      ),
    );
  }
}
