import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/notebook_trip.dart';
import '../../../services/aliyun_asr_service.dart';
import '../../../services/notebook_store.dart';
import '../../../services/notebook_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/speed_dial.dart';
import '../widgets/notebook_shared.dart';

/// 小字段标签：labels-above-inputs（Taste V1）。
Widget _fieldLabel(BuildContext context, String text) => Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.7),
          ),
    );

/// 旅游行程详情：列表 + 手动录入（仅公共信息）+ 语音录入（结构化行程）。
class TripDetail extends StatelessWidget {
  final AliyunAsrService asr;
  final NotebookVoiceService voice;

  const TripDetail({
    super.key,
    required this.asr,
    required this.voice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('旅游行程'),
      ),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final items = store.trips;
          if (items.isEmpty) {
            return const NotebookEmptyState(
              icon: Icons.luggage_rounded,
              title: '还没有行程',
              subtitle: '点下方按钮建行程，或说"五一去厦门三天，住海边酒店"。',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spaceSm),
            itemBuilder: (context, i) {
              final it = items[i];
              return _Row(
                item: it,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _TripDrillDown(trip: it),
                )),
                onEdit: () => _showEdit(context, it),
                onDelete: () => store.deleteTrip(it.id),
              );
            },
          );
        },
      ),
      floatingActionButton: SpeedDialFab(
        onAdd: () => _showAdd(context),
        onVoice: () => _startVoice(context),
      ),
    );
  }

  void _showAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _TripAddSheet(
        onSave: (item) => context.read<NotebookStore>().addTrip(item),
      ),
    );
  }

  void _showEdit(BuildContext context, NotebookTrip trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _TripAddSheet(
        initial: trip,
        onSave: (t) => context.read<NotebookStore>().updateTrip(t),
      ),
    );
  }

  void _startVoice(BuildContext context) {
    showNotebookVoiceSheet<NotebookTrip>(
      context,
      NotebookVoiceSheet<NotebookTrip>(
        asr: asr,
        title: '语音录入旅游行程',
        parse: (t) async {
          final trip = await voice.parseTrip(t);
          return trip == null ? const [] : [trip];
        },
        itemBuilder: (item) => _Preview(item: item),
        onConfirmed: (items) {
          if (items.isNotEmpty) {
            context.read<NotebookStore>().addTrip(items.first);
          }
        },
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final NotebookTrip item;
  const _Preview({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title.isNotEmpty ? item.title : '未命名行程',
            style: Theme.of(context).textTheme.titleMedium),
        if (item.city.isNotEmpty)
          Text(item.city,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppTheme.accent)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final NotebookTrip item;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _Row(
      {required this.item,
      required this.onTap,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dates = [
      if (item.startDate.isNotEmpty) item.startDate,
      if (item.endDate.isNotEmpty) item.endDate,
    ].join(' → ');
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(item.title.isNotEmpty ? item.title : '未命名行程',
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dates.isNotEmpty) Text(dates),
            const SizedBox(height: 4),
            Text('${item.checkpointCount} 个打卡点',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5))),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.totalCost > 0)
              Text('¥${item.totalCost}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: AppTheme.accent)),
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  color: scheme.onSurface.withValues(alpha: 0.45)),
              tooltip: '编辑行程',
              onPressed: onEdit,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.4)),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _TripAddSheet extends StatefulWidget {
  final void Function(NotebookTrip) onSave;
  final NotebookTrip? initial;
  const _TripAddSheet({required this.onSave, this.initial});

  @override
  State<_TripAddSheet> createState() => _TripAddSheetState();
}

class _TripAddSheetState extends State<_TripAddSheet> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _home = TextEditingController();
  String _startStr = '';
  String _endStr = '';

  @override
  void initState() {
    super.initState();
    final it = widget.initial;
    if (it != null) {
      _title.text = it.title;
      _city.text = it.city;
      _home.text = it.homeCity;
      _startStr = it.startDate;
      _endStr = it.endDate;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _home.dispose();
    super.dispose();
  }

  void _save() {
    final it = widget.initial;
    widget.onSave(NotebookTrip(
      id: it?.id ?? notebookNewId(),
      title: _title.text.trim(),
      city: _city.text.trim(),
      homeCity: _home.text.trim(),
      startDate: _startStr,
      endDate: _endStr,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg,
          right: AppTheme.spaceLg,
          top: AppTheme.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spaceLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.initial != null ? '编辑行程' : '新建行程',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledField(
                        label: '行程名', controller: _title, hint: '如 五一厦门游'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: LabeledField(
                                label: '目的地',
                                controller: _city,
                                hint: '厦门')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: LabeledField(
                                label: '出发地',
                                controller: _home,
                                hint: '上海')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: DateField(
                                label: '开始',
                                value: _startStr,
                                onChanged: (v) =>
                                    setState(() => _startStr = v))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: DateField(
                                label: '结束',
                                value: _endStr,
                                onChanged: (v) =>
                                    setState(() => _endStr = v))),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed: _save, child: const Text('保存')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 行程下钻：按天展示打卡点（交通/计费/星评），并支持增 / 改 / 删 + 补充金额。
///
/// 持有 [_trip] 本地副本（初始化自构造入参），所有变更走 [NotebookTrip.copyWith]
/// 后 [NotebookStore.updateTrip] 持久化，并 [setState] 刷新本地显示。与语音产出
/// 的按天数据共存：仅改动 targeted day / checkpoint，其余保持原样。
class _TripDrillDown extends StatefulWidget {
  final NotebookTrip trip;
  const _TripDrillDown({required this.trip});

  @override
  State<_TripDrillDown> createState() => _TripDrillDownState();
}

class _TripDrillDownState extends State<_TripDrillDown> {
  late NotebookTrip _trip;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
  }

  NotebookStore get _store => context.read<NotebookStore>();

  Future<void> _persist() async {
    await _store.updateTrip(_trip);
    if (mounted) setState(() {});
  }

  void _addCheckpoint(int dayIndex) =>
      _showCheckpointSheet(dayIndex: dayIndex, initial: null);

  void _editCheckpoint(int dayIndex, TripCheckpoint cp) =>
      _showCheckpointSheet(dayIndex: dayIndex, initial: cp);

  void _showCheckpointSheet(
      {required int dayIndex, TripCheckpoint? initial}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _CheckpointEditSheet(
        initial: initial,
        onSave: (cp) {
          _applyCheckpoint(dayIndex: dayIndex, cp: cp, initial: initial);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// 应用打卡点变更：新增 / 替换（按对象引用定位）指定天的打卡点。
  /// [days] 为空时自动建首条 [TripDay]（label='未排天'）兜底。
  Future<void> _applyCheckpoint({
    required int dayIndex,
    required TripCheckpoint cp,
    required TripCheckpoint? initial,
  }) async {
    final days = List<TripDay>.from(_trip.days);
    if (days.isEmpty) {
      days.add(TripDay(label: '未排天', checkpoints: [cp]));
    } else {
      final day = days[dayIndex];
      final list = List<TripCheckpoint>.from(day.checkpoints);
      if (initial == null) {
        list.add(cp);
      } else {
        final at = list.indexOf(initial);
        if (at >= 0) {
          list[at] = cp;
        } else {
          list.add(cp);
        }
      }
      days[dayIndex] = day.copyWith(checkpoints: list);
    }
    _trip = _trip.copyWith(days: days);
    await _persist();
  }

  Future<void> _deleteCheckpoint(int dayIndex, TripCheckpoint cp) async {
    final confirmed = await ConfirmDialog.show(
      context,
      '删除打卡点',
      '确定删除「${cp.name}」吗？此操作不可撤销。',
      '删除',
    );
    if (!confirmed) return;
    final days = List<TripDay>.from(_trip.days);
    final day = days[dayIndex];
    final list = day.checkpoints.where((e) => e != cp).toList();
    days[dayIndex] = day.copyWith(checkpoints: list);
    _trip = _trip.copyWith(days: days);
    await _persist();
  }

  Future<void> _addDay({String? label}) async {
    final days = List<TripDay>.from(_trip.days);
    days.add(TripDay(
      label: label ?? '第 ${days.length + 1} 天',
      checkpoints: const [],
    ));
    _trip = _trip.copyWith(days: days);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_trip.title.isNotEmpty ? _trip.title : '行程详情'),
        actions: [
          TextButton(
            onPressed: () => _editAmounts(context),
            child: const Text('金额'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        children: [
          if (_trip.totalCost > 0)
            Container(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Text('本地估算总额：¥${_trip.totalCost}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: AppTheme.accent)),
            ),
          const SizedBox(height: AppTheme.spaceMd),
          ..._trip.days.asMap().entries.expand((e) {
            final dayIndex = e.key;
            final d = e.value;
            return [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.label.isNotEmpty
                            ? d.label
                            : (d.date.isNotEmpty ? d.date : '未排天'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _addCheckpoint(dayIndex),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('打卡点'),
                    ),
                  ],
                ),
              ),
              ...d.checkpoints
                  .map((c) => _checkpointCard(dayIndex: dayIndex, c: c)),
            ];
          }),
          if (_trip.days.isEmpty)
            NotebookEmptyState(
              icon: Icons.place_outlined,
              title: '暂无打卡点',
              subtitle: '点击下方"添加一天"或语音录入可生成按天排布的行程。',
            ),
          const SizedBox(height: AppTheme.spaceSm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _addDay(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加一天'),
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      ),
    );
  }

  Widget _checkpointCard(
      {required int dayIndex, required TripCheckpoint c}) {
    final scheme = Theme.of(context).colorScheme;
    final billings = c.billings.map((b) => b.type).join('、');
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spaceSm),
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _editCheckpoint(dayIndex, c),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          c.done
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: c.done
                              ? AppTheme.ok
                              : scheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(c.name,
                              style:
                                  Theme.of(context).textTheme.titleMedium)),
                    ],
                  ),
                  if (c.transport != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('交通：${c.transport!.mode}',
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                  if (billings.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('计费：$billings',
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                  if (c.rating > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: StarsRow(value: c.rating, size: 14),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: scheme.onSurface.withValues(alpha: 0.4)),
            onPressed: () => _deleteCheckpoint(dayIndex, c),
          ),
        ],
      ),
    );
  }

  void _editAmounts(BuildContext context) {
    final inter = TextEditingController(
        text: (_trip.intercityTransport?.amount ?? 0).toString());
    final hotel =
        TextEditingController(text: (_trip.hotel?.amount ?? 0).toString());
    final per = TextEditingController(text: '0');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg,
          right: AppTheme.spaceLg,
          top: AppTheme.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('补充金额（默认 0）',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            LabeledField(
                label: '城际大交通单价',
                controller: inter,
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            LabeledField(
                label: '酒店每晚价格',
                controller: hotel,
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            LabeledField(
                label: '每个打卡点计费单价',
                controller: per,
                keyboardType: TextInputType.number),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final map = _trip.toJson();
                if (map['intercityTransport'] != null) {
                  (map['intercityTransport'] as Map)['amount'] =
                      num.tryParse(inter.text) ?? 0;
                }
                if (map['hotel'] != null) {
                  (map['hotel'] as Map)['amount'] =
                      num.tryParse(hotel.text) ?? 0;
                }
                final days = (map['days'] as List?) ?? [];
                for (final d in days) {
                  for (final c in (d['checkpoints'] as List?) ?? []) {
                    for (final b in (c['billings'] as List?) ?? []) {
                      b['amount'] = num.tryParse(per.text) ?? 0;
                    }
                  }
                }
                final newTrip = NotebookTrip.fromJson(map);
                _trip = newTrip;
                await _persist();
                if (!mounted) return;
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('保存金额'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 打卡点编辑底部弹层：名称 / 是否完成 / 交通方式(单选) / 计费类型(多选) /
/// 评分 / 备注。保存时回调 [onSave]。
class _CheckpointEditSheet extends StatefulWidget {
  final TripCheckpoint? initial;
  final void Function(TripCheckpoint) onSave;
  const _CheckpointEditSheet({this.initial, required this.onSave});

  @override
  State<_CheckpointEditSheet> createState() => _CheckpointEditSheetState();
}

class _CheckpointEditSheetState extends State<_CheckpointEditSheet> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  late bool _done;
  String? _transportMode;
  late Set<String> _billings;
  late int _rating;

  @override
  void initState() {
    super.initState();
    final it = widget.initial;
    _name.text = it?.name ?? '';
    _note.text = it?.note ?? '';
    _done = it?.done ?? false;
    _transportMode = it?.transport?.mode;
    _billings = (it?.billings.map((b) => b.type) ?? const <String>[]).toSet();
    _rating = it?.rating ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写打卡点名称')),
      );
      return;
    }
    widget.onSave(TripCheckpoint(
      name: name,
      transport: _transportMode == null
          ? null
          : TripTransport(mode: _transportMode!),
      billings: _billings.map((t) => TripBilling(type: t)).toList(),
      done: _done,
      rating: _rating,
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg,
          right: AppTheme.spaceLg,
          top: AppTheme.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spaceLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      widget.initial == null ? '新增打卡点' : '编辑打卡点',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    LabeledField(label: '名称 *', controller: _name),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _fieldLabel(context, '是否完成')),
                        Switch(
                          value: _done,
                          activeThumbColor: AppTheme.accent,
                          onChanged: (v) => setState(() => _done = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _fieldLabel(context, '交通方式（单选）'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kTransportModes.map((mode) {
                        final selected = _transportMode == mode;
                        return ChoiceChip(
                          label: Text(mode),
                          selected: selected,
                          onSelected: (sel) => setState(
                              () => _transportMode = sel ? mode : null),
                          selectedColor: AppTheme.accentSoft,
                          backgroundColor: scheme.surface,
                          labelStyle: TextStyle(
                              color: selected
                                  ? AppTheme.accent
                                  : scheme.onSurface.withValues(alpha: 0.7)),
                          side: BorderSide(
                            color: selected
                                ? AppTheme.accent.withValues(alpha: 0.4)
                                : scheme.onSurface.withValues(alpha: 0.12),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _fieldLabel(context, '计费类型（多选）'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kBillingTypes.map((type) {
                        final selected = _billings.contains(type);
                        return FilterChip(
                          label: Text(type),
                          selected: selected,
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _billings.add(type);
                            } else {
                              _billings.remove(type);
                            }
                          }),
                          selectedColor: AppTheme.accentSoft,
                          backgroundColor: scheme.surface,
                          labelStyle: TextStyle(
                              color: selected
                                  ? AppTheme.accent
                                  : scheme.onSurface.withValues(alpha: 0.7)),
                          side: BorderSide(
                            color: selected
                                ? AppTheme.accent.withValues(alpha: 0.4)
                                : scheme.onSurface.withValues(alpha: 0.12),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _fieldLabel(context, '评分'),
                    const SizedBox(height: 8),
                    StarsRow(
                      value: _rating,
                      size: 26,
                      onChanged: (v) => setState(() => _rating = v),
                    ),
                    const SizedBox(height: 12),
                    LabeledField(label: '备注', controller: _note, maxLines: 2),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed: _save, child: const Text('保存')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
