import 'package:flutter/material.dart';

import '../../../models/notebook_trip.dart';
import '../../../services/notebook_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirm_dialog.dart';
import '../widgets/enum_chips_field.dart';
import '../widgets/notebook_shared.dart';

/// 旅游行程页（设计稿 scr-trip）。
///
/// 列表行=目的地 + 日期区间 + 天数/打卡数 + 费用；点行进行程详情
/// （scr-trip-detail）维护天与打卡点。基础信息（标题/目的地/出发地/日期
/// 区间/交通方式/备注）走底部抽屉（scr-trip-edit，规格 C5）。
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
    await showTripSheet(context, store: widget.store, initial: initial);
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
            _TripRow(
              trip: trip,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _TripDetail(
                    trip: trip,
                    store: widget.store,
                  ),
                ),
              ),
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

/// 行程列表行：目的地 + 日期区间 + 天数/打卡数 + 总费用。
class _TripRow extends StatelessWidget {
  final NotebookTrip trip;
  final VoidCallback onTap;

  const _TripRow({required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasRange =
        trip.startDate.isNotEmpty && trip.endDate.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(
                Icons.flight_takeoff_outlined,
                size: 22,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (trip.city.isNotEmpty)
                        Text(
                          trip.city,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      if (hasRange)
                        Text(
                          '· ${_shortDate(trip.startDate)} 至 ${_shortDate(trip.endDate)}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${trip.days.length} 天 · ${trip.checkpointCount} 打卡',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  formatYuanThousands(trip.totalCost),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// yyyy-MM-dd → MM-dd（列表行紧凑日期展示）。
  String _shortDate(String date) {
    final dt = DateTime.tryParse(date);
    return dt == null ? date : '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// 行程基础信息底部抽屉（规格 C5）：标题/目的地/出发地/日期区间/交通方式/备注。
Future<void> showTripSheet(
  BuildContext context, {
  required NotebookStore store,
  NotebookTrip? initial,
}) async {
  final titleCtrl = TextEditingController(text: initial?.title ?? '');
  final cityCtrl = TextEditingController(text: initial?.city ?? '');
  final homeCtrl = TextEditingController(text: initial?.homeCity ?? '');
  final noteCtrl = TextEditingController(text: initial?.note ?? '');
  var startDate = initial?.startDate ?? '';
  var endDate = initial?.endDate ?? '';
  var transportMode = '';
  final initialTransport = initial?.intercityTransport;
  if (initialTransport != null && initialTransport.mode.isNotEmpty) {
    transportMode = initialTransport.mode;
  }
  String? titleError;
  String? dateError;

  await showNotebookEditSheet(
    context,
    title: initial == null ? '新建行程' : '编辑行程',
    builder: (ctx, setSheetState) => [
      TextField(
        autocorrect: false,
        controller: titleCtrl,
        decoration: InputDecoration(labelText: '标题', errorText: titleError),
      ),
      const SizedBox(height: 12),
      TextField(
        autocorrect: false,
        controller: cityCtrl,
        decoration: const InputDecoration(labelText: '目的地（可选）'),
      ),
      const SizedBox(height: 12),
      TextField(
        autocorrect: false,
        controller: homeCtrl,
        decoration: const InputDecoration(labelText: '出发地（可选）'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: DateField(
              label: '开始日期',
              value: startDate,
              onChanged: (v) => setSheetState(() => startDate = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DateField(
              label: '结束日期',
              value: endDate,
              onChanged: (v) => setSheetState(() => endDate = v),
            ),
          ),
        ],
      ),
      if (dateError != null) ...[
        const SizedBox(height: 6),
        Text(
          dateError!,
          style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                color: Theme.of(ctx).colorScheme.error,
              ),
        ),
      ],
      const SizedBox(height: 12),
      Text('交通方式（可选）', style: Theme.of(ctx).textTheme.labelMedium),
      const SizedBox(height: 8),
      EnumChipsField(
        values: kTransportModes,
        selected: transportMode,
        onChanged: (v) => setSheetState(() => transportMode = v),
      ),
      const SizedBox(height: 12),
      TextField(
        autocorrect: false,
        controller: noteCtrl,
        decoration: const InputDecoration(
          labelText: '备注（可选）',
          hintText: '如：住春熙路附近',
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () {
          final title = titleCtrl.text.trim();
          if (title.isEmpty) {
            setSheetState(() => titleError = '请输入标题');
            return;
          }
          // 结束日期不得早于开始日期（同格式字符串可直接比较）
          if (startDate.isNotEmpty &&
              endDate.isNotEmpty &&
              endDate.compareTo(startDate) < 0) {
            setSheetState(() => dateError = '结束日期不得早于开始日期');
            return;
          }
          final entity = NotebookTrip(
            id: initial?.id ?? notebookNewId(),
            title: title,
            city: cityCtrl.text.trim(),
            homeCity: homeCtrl.text.trim(),
            startDate: startDate,
            endDate: endDate,
            intercityTransport: transportMode.isEmpty
                ? null
                : TripTransport(mode: transportMode),
            days: initial?.days ?? const [],
          );
          if (initial == null) {
            store.addTrip(entity);
          } else {
            store.updateTrip(entity);
          }
          Navigator.of(ctx).pop();
        },
        child: const Text('保存'),
      ),
      if (initial != null) ...[
        const SizedBox(height: 10),
        TextButton(
          onPressed: () async {
            final ok = await ConfirmDialog.show(
              ctx,
              '删除行程',
              '删除「${initial.title}」及其全部安排？',
              '删除',
            );
            if (ok) {
              await store.deleteTrip(initial.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('删除'),
        ),
      ],
    ],
  );
}

/// 行程详情页（scr-trip-detail）：信息卡 + 天卡 + 打卡点 + 「加一天」。
class _TripDetail extends StatefulWidget {
  const _TripDetail({required this.trip, required this.store});

  final NotebookTrip trip;
  final NotebookStore store;

  @override
  State<_TripDetail> createState() => _TripDetailState();
}

class _TripDetailState extends State<_TripDetail> {
  late NotebookTrip _trip = widget.trip;

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
    // 外部更新（如编辑基本信息）后同步本地副本
    final updated = widget.store.trips
        .where((t) => t.id == widget.trip.id)
        .firstOrNull;
    if (!mounted) return;
    if (updated == null) {
      // 行程已在编辑抽屉中被删除，详情页退出避免残留旧数据
      Navigator.of(context).maybePop();
    } else {
      setState(() => _trip = updated);
    }
  }

  /// 持久化当前行程并刷新本地状态。
  Future<void> _persist(NotebookTrip next) async {
    await widget.store.updateTrip(next);
    if (mounted) setState(() => _trip = next);
  }

  /// 打开「加一天」抽屉：日期选择器 + 标签（scr-checkpoint-edit 附注）。
  Future<void> _addDay() async {
    var date = '';
    final labelCtrl = TextEditingController();
    await showNotebookEditSheet(
      context,
      title: '加一天',
      builder: (ctx, setSheetState) => [
        DateField(
          label: '日期（可选）',
          value: date,
          onChanged: (v) => setSheetState(() => date = v),
        ),
        const SizedBox(height: 12),
        TextField(
          autocorrect: false,
          controller: labelCtrl,
          decoration: const InputDecoration(
            labelText: '标签（可选）',
            hintText: '如：D1 / 抵达日',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            _persist(
              _trip.copyWith(
                days: [
                  ..._trip.days,
                  TripDay(date: date, label: labelCtrl.text.trim()),
                ],
              ),
            );
            Navigator.of(ctx).pop();
          },
          child: const Text('添加'),
        ),
      ],
    );
  }

  /// 打开添加/编辑打卡点抽屉（scr-checkpoint-edit，规格 C10）。
  Future<void> _editCheckpoint(TripDay day, TripCheckpoint? cp) async {
    final nameCtrl = TextEditingController(text: cp?.name ?? '');
    final amountCtrl =
        TextEditingController(text: cp == null ? '' : _trimAmount(_cpAmount(cp)));
    final noteCtrl = TextEditingController(text: cp?.note ?? '');
    var transportMode = cp?.transport?.mode ?? '';
    var billingTypes = <String>{
      for (final b in (cp?.billings ?? const <TripBilling>[])) b.type,
    };
    var rating = cp?.rating ?? 0;
    String? nameError;
    String? amountError;

    await showNotebookEditSheet(
      context,
      title: cp == null ? '添加打卡点' : '编辑打卡点',
      builder: (ctx, setSheetState) => [
        TextField(
          autocorrect: false,
          controller: nameCtrl,
          decoration: InputDecoration(labelText: '名称', errorText: nameError),
        ),
        const SizedBox(height: 12),
        Text('交通方式（可选）', style: Theme.of(ctx).textTheme.labelMedium),
        const SizedBox(height: 8),
        EnumChipsField(
          values: kTransportModes,
          selected: transportMode,
          onChanged: (v) => setSheetState(() => transportMode = v),
        ),
        const SizedBox(height: 12),
        Text('计费类型（可多选）', style: Theme.of(ctx).textTheme.labelMedium),
        const SizedBox(height: 8),
        MultiEnumChipsField(
          values: kBillingTypes,
          selected: billingTypes,
          onChanged: (v) => setSheetState(() => billingTypes = v),
        ),
        const SizedBox(height: 12),
        TextField(
          autocorrect: false,
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '金额',
            prefixText: '¥ ',
            errorText: amountError,
          ),
        ),
        const SizedBox(height: 12),
        Text('评分（可选）', style: Theme.of(ctx).textTheme.labelMedium),
        const SizedBox(height: 6),
        StarsRow(value: rating, onChanged: (v) => setSheetState(() => rating = v)),
        const SizedBox(height: 12),
        TextField(
          autocorrect: false,
          controller: noteCtrl,
          decoration: const InputDecoration(
            labelText: '备注（可选）',
            hintText: '如：早上 8 点前到人少',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            final name = nameCtrl.text.trim();
            final amount = num.tryParse(amountCtrl.text.trim());
            if (name.isEmpty) {
              setSheetState(() => nameError = '请输入名称');
              return;
            }
            if (amount == null || amount < 0) {
              setSheetState(() => amountError = '请输入有效金额（不小于 0）');
              return;
            }
            final types = billingTypes.isEmpty
                ? const ['其他']
                : billingTypes.toList();
            final entity = TripCheckpoint(
              name: name,
              transport: transportMode.isEmpty
                  ? null
                  : TripTransport(mode: transportMode),
              // 金额记在首个计费类型上，其余类型仅作标签，总额不重复累计
              billings: [
                for (var i = 0; i < types.length; i++)
                  TripBilling(type: types[i], amount: i == 0 ? amount : 0),
              ],
              done: cp?.done ?? false,
              rating: rating,
              note: noteCtrl.text.trim(),
            );
            // 编辑在原位置替换、新增追加到末尾，保持打卡点顺序
            final checkpoints = <TripCheckpoint>[
              for (final c in day.checkpoints)
                if (cp != null && c == cp) entity else c,
            ];
            if (cp == null) checkpoints.add(entity);
            final days = [
              for (final d in _trip.days)
                if (d == day) day.copyWith(checkpoints: checkpoints) else d,
            ];
            _persist(_trip.copyWith(days: days));
            Navigator.of(ctx).pop();
          },
          child: const Text('保存'),
        ),
        if (cp != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: () async {
              final ok = await ConfirmDialog.show(
                ctx,
                '删除打卡点',
                '删除「${cp.name}」？',
                '删除',
              );
              if (ok) {
                final days = [
                  for (final d in _trip.days)
                    if (d == day)
                      d.copyWith(
                        checkpoints: d.checkpoints
                            .where((c) => c != cp)
                            .toList(),
                      )
                    else
                      d,
                ];
                await _persist(_trip.copyWith(days: days));
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ],
    );
  }

  /// 打卡点金额合计（编辑回填与行展示共用）。
  num _cpAmount(TripCheckpoint cp) =>
      cp.billings.fold<num>(0, (s, b) => s + b.amount);

  /// 删除一天（连带其打卡点），二次确认防误删。
  Future<void> _deleteDay(TripDay day) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除这一天',
      '删除该天及其全部打卡点？',
      '删除',
    );
    if (ok) {
      await _persist(
        _trip.copyWith(days: _trip.days.where((d) => d != day).toList()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasRange =
        _trip.startDate.isNotEmpty && _trip.endDate.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(_trip.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑行程',
            onPressed: () =>
                showTripSheet(context, store: widget.store, initial: _trip),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 信息卡：目的地/出发地 + 日期区间/天数 + 合计费用
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow:
                  AppTheme.elevation(scheme.brightness == Brightness.dark),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _trip.city.isEmpty
                            ? _trip.title
                            : '${_trip.city}'
                                '${_trip.homeCity.isEmpty ? '' : ' · ${_trip.homeCity}出发'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasRange
                            ? '${_shortDate(_trip.startDate)} 至 ${_shortDate(_trip.endDate)} · ${_trip.days.length} 天'
                            : '${_trip.days.length} 天',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatYuanThousands(_trip.totalCost),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '合计费用',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '行程安排（${_trip.days.length} 天）',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _addDay,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('加一天'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _trip.days.length; i++) ...[
            _DayCard(
              index: i,
              day: _trip.days[i],
              onAddCheckpoint: () => _editCheckpoint(_trip.days[i], null),
              onToggleDone: (cp) => _toggleDone(_trip.days[i], cp),
              onTapCheckpoint: (cp) => _editCheckpoint(_trip.days[i], cp),
              onDeleteDay: () => _deleteDay(_trip.days[i]),
            ),
            const SizedBox(height: 8),
          ],
          if (_trip.days.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('下方「加一天」开始安排行程')),
            ),
        ],
      ),
    );
  }

  /// 点完成圈切换打卡点完成态并持久化。
  void _toggleDone(TripDay day, TripCheckpoint cp) {
    final days = [
      for (final d in _trip.days)
        if (d == day)
          d.copyWith(
            checkpoints: [
              for (final c in d.checkpoints)
                if (c == cp) c.copyWith(done: !c.done) else c,
            ],
          )
        else
          d,
    ];
    _persist(_trip.copyWith(days: days));
  }

  /// yyyy-MM-dd → MM-dd（详情页紧凑日期展示）。
  String _shortDate(String date) {
    final dt = DateTime.tryParse(date);
    return dt == null
        ? date
        : '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// 天卡：第 N 天标题 + 加打卡点/删天 + 打卡点行列表。
class _DayCard extends StatelessWidget {
  final int index;
  final TripDay day;
  final VoidCallback onAddCheckpoint;
  final ValueChanged<TripCheckpoint> onToggleDone;
  final ValueChanged<TripCheckpoint> onTapCheckpoint;
  final VoidCallback onDeleteDay;

  const _DayCard({
    required this.index,
    required this.day,
    required this.onAddCheckpoint,
    required this.onToggleDone,
    required this.onTapCheckpoint,
    required this.onDeleteDay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = day.label.isEmpty
        ? '第 ${index + 1} 天'
        : day.label;
    final dateText = day.date.isEmpty ? '' : ' · ${_shortDate(day.date)}';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$title$dateText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '加打卡点',
                  onPressed: onAddCheckpoint,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除这一天',
                  onPressed: onDeleteDay,
                ),
              ],
            ),
          ),
          for (final cp in day.checkpoints)
            _CheckpointRow(
              checkpoint: cp,
              onToggleDone: () => onToggleDone(cp),
              onTap: () => onTapCheckpoint(cp),
            ),
          if (day.checkpoints.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '暂无打卡点',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// yyyy-MM-dd → MM-dd（天卡标题紧凑日期展示）。
  String _shortDate(String date) {
    final dt = DateTime.tryParse(date);
    return dt == null
        ? date
        : '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// 打卡点行：完成圈 + 名称 + 交通/计费 chip + 金额。
class _CheckpointRow extends StatelessWidget {
  final TripCheckpoint checkpoint;
  final VoidCallback onToggleDone;
  final VoidCallback onTap;

  const _CheckpointRow({
    required this.checkpoint,
    required this.onToggleDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amount =
        checkpoint.billings.fold<num>(0, (s, b) => s + b.amount);
    final types = checkpoint.billings
        .map((b) => b.type)
        .where((t) => t.isNotEmpty)
        .toSet();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            GestureDetector(
              onTap: onToggleDone,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checkpoint.done ? AppTheme.ok : Colors.transparent,
                  border: Border.all(
                    color: checkpoint.done
                        ? AppTheme.ok
                        : scheme.onSurface.withValues(alpha: 0.3),
                    width: 1.6,
                  ),
                ),
                child: checkpoint.done
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    checkpoint.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: checkpoint.done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (types.isNotEmpty || checkpoint.transport != null) ...[
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (checkpoint.transport != null)
                          NotebookChip(
                            label: checkpoint.transport!.mode,
                            bg: scheme.primaryContainer,
                            fg: scheme.onPrimaryContainer,
                          ),
                        for (final t in types)
                          Text(
                            t,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatYuanThousands(amount),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// 金额回填：整数不带小数点，小数保留两位。
String _trimAmount(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
