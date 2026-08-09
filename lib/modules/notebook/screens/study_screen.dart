import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/notebook_study.dart';
import '../../../services/notebook_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirm_dialog.dart';
import '../widgets/enum_chips_field.dart';
import '../widgets/notebook_shared.dart';

/// 学习记录页（设计稿 scr-study / scr-study-edit）。
///
/// 课程列表行=状态徽标（想学灰/学习中黄/已完成绿）+ 课程名 + 来源 + 记录数
/// + 进度条；点行进课程详情（scr-study-detail）维护学习记录。课程与记录
/// 的新增/编辑均走底部抽屉（规格 C6/C11）。
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
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

  Future<void> _addCourse() async {
    await showCourseSheet(context, store: widget.store);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学习记录')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCourse,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final course in widget.store.courses)
            _CourseRow(
              course: course,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _CourseDetail(
                    course: course,
                    store: widget.store,
                  ),
                ),
              ),
            ),
          if (widget.store.courses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有课程，点右下角添加')),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

/// 课程列表行：状态徽标 + 课程名 + 来源/记录数 + 进度条 + 右箭头。
class _CourseRow extends StatelessWidget {
  final NotebookCourse course;
  final VoidCallback onTap;

  const _CourseRow({required this.course, required this.onTap});

  /// 状态徽标配色：想学灰 / 学习中黄 / 已完成绿。
  String get _tone => switch (course.status) {
        'learning' => 'warn',
        'done' => 'ok',
        _ => 'neutral',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(Icons.school_outlined,
                  size: 22, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          course.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 20, color: scheme.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      semanticChip(
                        context,
                        label: studyStatusLabel(course.status),
                        tone: _tone,
                      ),
                      if (course.source.isNotEmpty)
                        Text(
                          course.source,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      Text(
                        '· ${course.records.length} 条记录',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (course.progress.clamp(0, 100)) / 100,
                      minHeight: 5,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: course.status == 'done'
                          ? AppTheme.ok
                          : scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 学习状态中文文案（想学/学习中/已完成）。
String studyStatusLabel(String status) => switch (status) {
      'learning' => '学习中',
      'done' => '已完成',
      _ => '想学',
    };

/// 课程新增/编辑底部抽屉（规格 C6）。
Future<void> showCourseSheet(
  BuildContext context, {
  required NotebookStore store,
  NotebookCourse? initial,
}) async {
  const statusValues = ['want', 'learning', 'done'];
  final titleCtrl = TextEditingController(text: initial?.title ?? '');
  final sourceCtrl = TextEditingController(text: initial?.source ?? '');
  final progressCtrl =
      TextEditingController(text: initial == null ? '' : '${initial.progress}');
  final noteCtrl = TextEditingController(text: initial?.note ?? '');
  var status = initial?.status ?? 'want';
  if (!statusValues.contains(status)) status = 'want';
  var rating = initial?.rating ?? 0;
  String? error;

  await showNotebookEditSheet(
    context,
    title: initial == null ? '添加课程' : '编辑课程',
    builder: (ctx, setSheetState) => [
      TextField(
        controller: titleCtrl,
        decoration: InputDecoration(labelText: '课程名', errorText: error),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: sourceCtrl,
        decoration: const InputDecoration(labelText: '来源 / 平台（可选）'),
      ),
      const SizedBox(height: 12),
      Text('状态', style: Theme.of(ctx).textTheme.labelMedium),
      const SizedBox(height: 8),
      EnumChipsField(
        values: statusValues
            .map((v) => studyStatusLabel(v))
            .toList(growable: false),
        selected: studyStatusLabel(status),
        onChanged: (label) => setSheetState(() {
          status = statusValues.firstWhere(
            (v) => studyStatusLabel(v) == label,
          );
        }),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: progressCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: '进度（0-100）',
          suffixText: '%',
        ),
      ),
      const SizedBox(height: 12),
      Text('评分（可选）', style: Theme.of(ctx).textTheme.labelMedium),
      const SizedBox(height: 6),
      StarsRow(value: rating, onChanged: (v) => setSheetState(() => rating = v)),
      const SizedBox(height: 12),
      TextField(
        controller: noteCtrl,
        decoration: const InputDecoration(
          labelText: '备注（可选）',
          hintText: '如：目标月底学完状态管理',
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () {
          final title = titleCtrl.text.trim();
          if (title.isEmpty) {
            setSheetState(() => error = '请输入课程名');
            return;
          }
          // 进度留空视为默认（新建 0 / 编辑保持原值），非法输入才拦截
          final progress = progressCtrl.text.trim().isEmpty
              ? (initial?.progress ?? 0)
              : int.tryParse(progressCtrl.text.trim());
          if (progress == null || progress < 0 || progress > 100) {
            setSheetState(() => error = '进度需为 0-100 的数字');
            return;
          }
          final entity = NotebookCourse(
            id: initial?.id ?? notebookNewId(),
            title: title,
            source: sourceCtrl.text.trim(),
            status: status,
            progress: progress,
            rating: rating,
            note: noteCtrl.text.trim(),
            records: initial?.records ?? const [],
          );
          if (initial == null) {
            store.addCourse(entity);
          } else {
            store.updateCourse(entity);
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
              '删除课程',
              '删除「${initial.title}」及其全部记录？',
              '删除',
            );
            if (ok) {
              await store.deleteCourse(initial.id);
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

/// 课程详情页（scr-study-detail）：信息卡 + 学习记录列表。
class _CourseDetail extends StatefulWidget {
  const _CourseDetail({required this.course, required this.store});

  final NotebookCourse course;
  final NotebookStore store;

  @override
  State<_CourseDetail> createState() => _CourseDetailState();
}

class _CourseDetailState extends State<_CourseDetail> {
  late NotebookCourse _course = widget.course;

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
    final updated = widget.store.courses
        .where((c) => c.id == widget.course.id)
        .firstOrNull;
    if (!mounted) return;
    if (updated == null) {
      // 课程已在编辑抽屉中被删除，详情页退出避免残留旧数据
      Navigator.of(context).maybePop();
    } else {
      setState(() => _course = updated);
    }
  }

  /// 打开添加/编辑学习记录抽屉（scr-record-edit，规格 C11）。
  Future<void> _editRecord(StudyRecord? record) async {
    final titleCtrl = TextEditingController(text: record?.title ?? '');
    final contentCtrl = TextEditingController(text: record?.content ?? '');
    var date =
        record == null ? '' : DateFormat('yyyy-MM-dd').format(record.createdAt);
    var rating = record?.rating ?? 0;
    String? error;

    await showNotebookEditSheet(
      context,
      title: record == null ? '添加记录' : '编辑记录',
      builder: (ctx, setSheetState) => [
        TextField(
          controller: titleCtrl,
          decoration: InputDecoration(labelText: '标题', errorText: error),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: contentCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '内容（可选）'),
        ),
        const SizedBox(height: 12),
        DateField(
          label: '日期（可选）',
          value: date,
          onChanged: (v) => setSheetState(() => date = v),
        ),
        const SizedBox(height: 12),
        Text('评分（可选）', style: Theme.of(ctx).textTheme.labelMedium),
        const SizedBox(height: 6),
        StarsRow(value: rating, onChanged: (v) => setSheetState(() => rating = v)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            final title = titleCtrl.text.trim();
            if (title.isEmpty) {
              setSheetState(() => error = '请输入标题');
              return;
            }
            // 未选日期时保留原记录日期，新建则取当前时间
            final createdAt = date.isEmpty
                ? (record?.createdAt ?? DateTime.now())
                : DateTime.parse(date);
            final entity = StudyRecord(
              id: record?.id ?? notebookNewId(),
              title: title,
              content: contentCtrl.text.trim(),
              rating: rating,
              createdAt: createdAt,
            );
            if (record == null) {
              widget.store.addRecord(_course.id, entity);
            } else {
              widget.store.updateRecord(_course.id, entity);
            }
            Navigator.of(ctx).pop();
          },
          child: const Text('保存'),
        ),
        if (record != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: () async {
              final ok = await ConfirmDialog.show(
                ctx,
                '删除记录',
                '删除「${record.title}」？',
                '删除',
              );
              if (ok) {
                await widget.store.deleteRecord(_course.id, record.id);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _course.progress.clamp(0, 100);
    return Scaffold(
      appBar: AppBar(
        title: Text(_course.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑课程',
            onPressed: () =>
                showCourseSheet(context, store: widget.store, initial: _course),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 信息卡：来源/状态 + 进度/记录数 + 评分
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow:
                  AppTheme.elevation(scheme.brightness == Brightness.dark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (_course.source.isNotEmpty)
                                Text(
                                  _course.source,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              semanticChip(
                                context,
                                label: studyStatusLabel(_course.status),
                                tone: switch (_course.status) {
                                  'learning' => 'warn',
                                  'done' => 'ok',
                                  _ => 'neutral',
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '进度 $progress% · ${_course.records.length} 条记录',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (_course.rating > 0) ...[
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StarsRow(value: _course.rating, size: 14),
                          const SizedBox(height: 2),
                          Text(
                            '评分',
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: _course.status == 'done'
                              ? AppTheme.ok
                              : scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$progress%',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
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
                '学习记录（${_course.records.length}）',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _editRecord(null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加记录'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final record in _course.records)
            _RecordRow(
              record: record,
              onTap: () => _editRecord(record),
              onDelete: () => _deleteRecord(record),
            ),
          if (_course.records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('还没有记录，点「添加记录」开始')),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteRecord(StudyRecord record) async {
    await widget.store.deleteRecord(_course.id, record.id);
  }
}

/// 学习记录行：标题 + 内容摘要 + 日期 + 星级 + 删除。
class _RecordRow extends StatelessWidget {
  final StudyRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RecordRow({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (record.content.isNotEmpty)
                        Text(
                          record.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      Text(
                        '· ${DateFormat('yyyy-MM-dd').format(record.createdAt)}',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (record.rating > 0)
                        StarsRow(value: record.rating, size: 11),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除记录',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
