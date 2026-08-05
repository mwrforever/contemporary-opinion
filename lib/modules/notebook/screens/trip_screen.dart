import 'package:flutter/material.dart';

import '../../../models/notebook_trip.dart';
import '../../../services/notebook_store.dart';
import '../../../widgets/confirm_dialog.dart';

/// 旅游行程页：行程列表 + 天/打卡点嵌套编辑。
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openEditor(NotebookTrip? initial) async {
    final result = await Navigator.of(context).push<NotebookTrip>(
      MaterialPageRoute(builder: (_) => _TripEditor(initial: initial)),
    );
    if (result == null || !mounted) return;
    if (initial == null) {
      await widget.store.addTrip(result);
    } else {
      await widget.store.updateTrip(result);
    }
  }

  Future<void> _delete(NotebookTrip trip) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除行程',
      '删除「${trip.title}」？',
      '删除',
    );
    if (ok) await widget.store.deleteTrip(trip.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('旅游行程')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final trip in widget.store.trips)
            ListTile(
              title: Text(trip.title),
              subtitle: Text(
                '${trip.city}${trip.startDate.isEmpty ? '' : ' · ${trip.startDate} 至 ${trip.endDate}'}'
                ' · ${trip.days.length} 天 ${trip.checkpointCount} 打卡 · ¥${trip.totalCost}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(trip),
              ),
              onTap: () => _openEditor(trip),
            ),
          if (widget.store.trips.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有行程，点右下角新建')),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

/// 行程编辑器：基本信息 + 天/打卡点维护。
class _TripEditor extends StatefulWidget {
  const _TripEditor({this.initial});

  final NotebookTrip? initial;

  @override
  State<_TripEditor> createState() => _TripEditorState();
}

class _TripEditorState extends State<_TripEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.initial?.title ?? '');
  late final TextEditingController _city = TextEditingController(text: widget.initial?.city ?? '');
  late final TextEditingController _home = TextEditingController(text: widget.initial?.homeCity ?? '');
  late final TextEditingController _start = TextEditingController(text: widget.initial?.startDate ?? '');
  late final TextEditingController _end = TextEditingController(text: widget.initial?.endDate ?? '');
  late final List<TripDay> _days = List.of(widget.initial?.days ?? const []);

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _home.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _addDay() async {
    final date = TextEditingController();
    final label = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加一天'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: date,
              decoration: const InputDecoration(labelText: '日期 yyyy-MM-dd'),
            ),
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: '标签（如 D1）'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((date.text.trim(), label.text.trim())),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null) setState(() => _days.add(TripDay(date: result.$1, label: result.$2)));
  }

  Future<void> _addCheckpoint(TripDay day) async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final result = await showDialog<(String, num)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加打卡点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '计费金额'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((name.text.trim(), num.tryParse(amount.text) ?? 0)),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final i = _days.indexOf(day);
    setState(() {
      _days[i] = day.copyWith(
        checkpoints: [
          ...day.checkpoints,
          TripCheckpoint(
            name: result.$1,
            billings: [TripBilling(type: '其他', amount: result.$2)],
          ),
        ],
      );
    });
  }

  void _save() {
    Navigator.of(context).pop(
      NotebookTrip(
        id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: _title.text.trim(),
        city: _city.text.trim(),
        homeCity: _home.text.trim(),
        startDate: _start.text.trim(),
        endDate: _end.text.trim(),
        days: _days,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '新建行程' : '编辑行程'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: '标题')),
          TextField(controller: _city, decoration: const InputDecoration(labelText: '目的地')),
          TextField(controller: _home, decoration: const InputDecoration(labelText: '出发地')),
          Row(
            children: [
              Expanded(child: TextField(controller: _start, decoration: const InputDecoration(labelText: '开始日期'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _end, decoration: const InputDecoration(labelText: '结束日期'))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('行程天数（${_days.length}）', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addDay,
                icon: const Icon(Icons.add),
                label: const Text('加一天'),
              ),
            ],
          ),
          for (var di = 0; di < _days.length; di++) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_days[di].label.isEmpty ? '第 ${di + 1} 天' : _days[di].label}'
                          '${_days[di].date.isEmpty ? '' : ' · ${_days[di].date}'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _addCheckpoint(_days[di]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _days.removeAt(di)),
                        ),
                      ],
                    ),
                    for (final cp in _days[di].checkpoints)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(cp.name),
                        trailing: Text('¥${cp.billings.fold<num>(0, (s, b) => s + b.amount)}'),
                      ),
                    if (_days[di].checkpoints.isEmpty)
                      const Text('暂无打卡点', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
