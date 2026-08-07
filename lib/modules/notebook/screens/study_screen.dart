import 'package:flutter/material.dart';

import '../../../models/notebook_study.dart';
import '../../../services/notebook_store.dart';
import '../../../widgets/confirm_dialog.dart';

/// 学习记录页：课程列表 → 课程详情（记录）。
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  static const _statusLabels = {'want': '想学', 'learning': '学习中', 'done': '已完成'};

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
    final title = TextEditingController();
    final result = await showDialog<NotebookCourse>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加课程'),
        content: TextField(
          controller: title,
          decoration: const InputDecoration(labelText: '课程名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              NotebookCourse(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                title: title.text.trim(),
              ),
            ),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null) await widget.store.addCourse(result);
  }

  Future<void> _delete(NotebookCourse course) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除课程',
      '删除「${course.title}」及其全部记录？',
      '删除',
    );
    if (ok) await widget.store.deleteCourse(course.id);
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
            ListTile(
              title: Text(course.title),
              subtitle: Text(
                '${_statusLabels[course.status] ?? course.status} · 进度 ${course.progress}%'
                ' · ${course.records.length} 条记录',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(course),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _CourseDetail(course: course, store: widget.store),
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

/// 课程详情：编辑课程 + 学习记录维护。
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
    if (mounted) setState(() {});
  }

  Future<void> _editCourse() async {
    final title = TextEditingController(text: _course.title);
    final progress = TextEditingController(text: '${_course.progress}');
    final result = await showDialog<NotebookCourse>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑课程'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: '课程名'),
            ),
            TextField(
              controller: progress,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '进度 0-100'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              _course.copyWith(
                title: title.text.trim(),
                progress: int.tryParse(progress.text) ?? 0,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.store.updateCourse(result);
      setState(() => _course = result);
    }
  }

  Future<void> _addRecord() async {
    final title = TextEditingController();
    final content = TextEditingController();
    final result = await showDialog<StudyRecord>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加记录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: content,
              decoration: const InputDecoration(labelText: '内容'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              StudyRecord(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                title: title.text.trim(),
                content: content.text.trim(),
                createdAt: DateTime.now(),
              ),
            ),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.store.addRecord(_course.id, result);
      setState(() => _course = _course.copyWith(records: [..._course.records, result]));
    }
  }

  Future<void> _deleteRecord(StudyRecord record) async {
    await widget.store.deleteRecord(_course.id, record.id);
    setState(() {
      _course = _course.copyWith(
        records: _course.records.where((r) => r.id != record.id).toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_course.title),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _editCourse),
          IconButton(icon: const Icon(Icons.add), onPressed: _addRecord),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('进度 ${_course.progress}% · ${_course.records.length} 条记录'),
          const SizedBox(height: 8),
          for (final record in _course.records)
            ListTile(
              title: Text(record.title),
              subtitle: Text(record.content),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteRecord(record),
              ),
            ),
          if (_course.records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('还没有记录，点右上角添加')),
            ),
        ],
      ),
    );
  }
}
