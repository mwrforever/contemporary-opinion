import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/notebook_study.dart';
import '../../../services/aliyun_asr_service.dart';
import '../../../services/notebook_store.dart';
import '../../../services/notebook_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/notebook_shared.dart';
import 'study_course_detail.dart';

/// 学习记录：课程列表（课程维度统一管理）。
class StudyCourseList extends StatelessWidget {
  final AliyunAsrService asr;
  final NotebookVoiceService voice;

  const StudyCourseList({
    super.key,
    required this.asr,
    required this.voice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学习记录')),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final courses = store.courses;
          if (courses.isEmpty) {
            return const NotebookEmptyState(
              icon: Icons.school_outlined,
              title: '还没有课程',
              subtitle: '点下方按钮新建一门课程，进入后再记录每次学习。',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            itemCount: courses.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spaceSm),
            itemBuilder: (context, i) {
              final c = courses[i];
              return _Row(
                course: c,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StudyCourseDetail(
                    course: c,
                    asr: asr,
                    voice: voice,
                  ),
                )),
                onDelete: () => store.deleteCourse(c.id),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAdd(context),
        child: const Icon(Icons.add_rounded),
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
      builder: (_) => _CourseAddSheet(
        onSave: (c) => context.read<NotebookStore>().addCourse(c),
      ),
    );
  }
}

const _courseStatusLabel = {'want': '想学', 'learning': '在学', 'done': '学完'};

class _Row extends StatelessWidget {
  final NotebookCourse course;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _Row(
      {required this.course,
      required this.onTap,
      required this.onDelete});

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
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(course.title,
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: course.progress / 100,
              backgroundColor:
                  scheme.onSurface.withValues(alpha: 0.1),
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                NotebookChip(label: label, bg: bg, fg: fg),
                const SizedBox(width: 8),
                Text('${course.records.length} 条记录',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.5))),
              ],
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

class _CourseAddSheet extends StatefulWidget {
  final void Function(NotebookCourse) onSave;
  final NotebookCourse? initial;
  const _CourseAddSheet({required this.onSave, this.initial});

  @override
  State<_CourseAddSheet> createState() => _CourseAddSheetState();
}

class _CourseAddSheetState extends State<_CourseAddSheet> {
  final _title = TextEditingController();
  final _source = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  String _status = 'want';

  @override
  void initState() {
    super.initState();
    final it = widget.initial;
    if (it != null) {
      _title.text = it.title;
      _source.text = it.source;
      _category.text = it.category;
      _note.text = it.note;
      _status = it.status;
    }
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
    final it = widget.initial;
    widget.onSave(NotebookCourse(
      id: it?.id ?? notebookNewId(),
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
                  child: Text(widget.initial != null ? '编辑课程' : '新建课程',
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
