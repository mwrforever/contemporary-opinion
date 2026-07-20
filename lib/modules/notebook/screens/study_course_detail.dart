import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/notebook_study.dart';
import '../../../services/aliyun_asr_service.dart';
import '../../../services/notebook_store.dart';
import '../../../services/notebook_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/speed_dial.dart';
import '../widgets/notebook_shared.dart';

/// 课程详情：课程信息与学习记录。语音录入绑定到本课程，记录直接挂在该课程下。
class StudyCourseDetail extends StatelessWidget {
  final NotebookCourse course;
  final AliyunAsrService asr;
  final NotebookVoiceService voice;

  const StudyCourseDetail({
    super.key,
    required this.course,
    required this.asr,
    required this.voice,
  });

  void _editCourse(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _CourseEditSheet(
        course: course,
        onSave: (c) => context.read<NotebookStore>().updateCourse(c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(course.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑课程',
            onPressed: () => _editCourse(context),
          ),
        ],
      ),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final live =
              store.courses.where((c) => c.id == course.id).firstOrNull ??
                  course;
          return Column(
            children: [
              _Header(course: live),
              Expanded(
                child: live.records.isEmpty
                    ? const NotebookEmptyState(
                        icon: Icons.record_voice_over_outlined,
                        title: '还没有学习记录',
                        subtitle: '点下方按钮手动添加，或用话筒语音记录本次学习。',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppTheme.spaceLg),
                        itemCount: live.records.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppTheme.spaceSm),
                        itemBuilder: (context, i) {
                          final r = live.records[i];
                          return _RecordRow(
                            record: r,
                            onTap: () => _showEdit(context, r),
                            onDelete: () =>
                                store.deleteRecord(course.id, r.id),
                          );
                        },
                      ),
              ),
            ],
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
      builder: (_) => _RecordAddSheet(
        onSave: (r) => context.read<NotebookStore>().addRecord(course.id, r),
      ),
    );
  }

  void _showEdit(BuildContext context, StudyRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _RecordAddSheet(
        item: record,
        onSave: (r) =>
            context.read<NotebookStore>().updateRecord(course.id, r),
      ),
    );
  }

  void _startVoice(BuildContext context) {
    showNotebookVoiceSheet<StudyRecord>(
      context,
      NotebookVoiceSheet<StudyRecord>(
        asr: asr,
        title: '记录「${course.title}」的学习',
        parse: voice.parseStudy,
        itemBuilder: (item) => _Preview(item: item),
        onConfirmed: (records) {
          final store = context.read<NotebookStore>();
          for (final r in records) store.addRecord(course.id, r);
        },
      ),
    );
  }
}

const _courseStatusLabel = {'want': '想学', 'learning': '在学', 'done': '学完'};

class _Header extends StatelessWidget {
  final NotebookCourse course;
  const _Header({required this.course});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _courseStatusLabel[course.status] ?? '想学';
    final (bg, fg) = switch (course.status) {
      'learning' => (AppTheme.warnSoft, AppTheme.warn),
      'done' => (AppTheme.okSoft, AppTheme.ok),
      _ => (AppTheme.accentSoft, AppTheme.accent),
    };
    return Container(
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NotebookChip(label: label, bg: bg, fg: fg),
              const Spacer(),
              if (course.rating > 0) StarsRow(value: course.rating, size: 16),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('进度 ${course.progress}%',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: course.progress.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  activeColor: AppTheme.accent,
                  onChanged: (v) {
                    final store = context.read<NotebookStore>();
                    store.updateCourse(
                        course.copyWith(progress: v.round()));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final StudyRecord item;
  const _Preview({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: Theme.of(context).textTheme.titleMedium),
        if (item.content.isNotEmpty)
          Text(item.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppTheme.accent)),
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  final StudyRecord record;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  const _RecordRow(
      {required this.record, this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(record.title,
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.content.isNotEmpty)
              Text(record.content, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              '${record.createdAt.month}月${record.createdAt.day}日'
              '${record.rating > 0 ? ' · ${record.rating}星' : ''}',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded,
              color: scheme.onSurface.withValues(alpha: 0.4)),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _RecordAddSheet extends StatefulWidget {
  final void Function(StudyRecord) onSave;
  final StudyRecord? item;
  const _RecordAddSheet({required this.onSave, this.item});

  @override
  State<_RecordAddSheet> createState() => _RecordAddSheetState();
}

class _RecordAddSheetState extends State<_RecordAddSheet> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _note = TextEditingController();
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    if (it != null) {
      _title.text = it.title;
      _content.text = it.content;
      _note.text = it.note;
      _rating = it.rating;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final base = widget.item ??
        StudyRecord(
            id: notebookNewId(), title: title, createdAt: DateTime.now());
    widget.onSave(base.copyWith(
      title: title,
      content: _content.text.trim(),
      rating: _rating,
      note: _note.text.trim(),
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
                  child: Text(widget.item == null ? '添加学习记录' : '编辑学习记录',
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
                        label: '主题 *', controller: _title, hint: '如 第3章 指针'),
                    const SizedBox(height: 12),
                    LabeledField(
                        label: '要点/笔记', controller: _content, maxLines: 4),
                    const SizedBox(height: 12),
                    Text('满意度', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    StarsRow(
                        value: _rating,
                        onChanged: (v) => setState(() => _rating = v)),
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

/// 课程编辑弹层（详情页「编辑课程」入口）：预填课程主信息，保存走 updateCourse。
class _CourseEditSheet extends StatefulWidget {
  final NotebookCourse course;
  final void Function(NotebookCourse) onSave;
  const _CourseEditSheet({required this.course, required this.onSave});

  @override
  State<_CourseEditSheet> createState() => _CourseEditSheetState();
}

class _CourseEditSheetState extends State<_CourseEditSheet> {
  final _title = TextEditingController();
  final _source = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  String _status = 'want';

  @override
  void initState() {
    super.initState();
    _title.text = widget.course.title;
    _source.text = widget.course.source;
    _category.text = widget.course.category;
    _note.text = widget.course.note;
    _status = widget.course.status;
  }

  @override
  void dispose() {
    _title.dispose();
    _source.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    widget.onSave(NotebookCourse(
      id: widget.course.id,
      title: title,
      source: _source.text.trim(),
      status: _status,
      category: _category.text.trim(),
      note: _note.text.trim(),
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
                  child: Text('编辑课程',
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
                        label: '课程名 *', controller: _title, hint: '如 C 语言'),
                    const SizedBox(height: 12),
                    LabeledField(
                        label: '来源/平台',
                        controller: _source,
                        hint: '如 学校/网课'),
                    const SizedBox(height: 12),
                    Text('状态', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'want', label: Text('想学')),
                        ButtonSegment(value: 'learning', label: Text('在学')),
                        ButtonSegment(value: 'done', label: Text('学完')),
                      ],
                      selected: {_status},
                      onSelectionChanged: (s) =>
                          setState(() => _status = s.first),
                    ),
                    const SizedBox(height: 12),
                    LabeledField(label: '分类', controller: _category),
                    const SizedBox(height: 12),
                    LabeledField(
                        label: '备注', controller: _note, maxLines: 2),
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
