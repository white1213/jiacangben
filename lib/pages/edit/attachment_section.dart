import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../consts.dart';
import '../../database/attachment_service.dart';
import '../../model/media_attachment.dart';

/// v1.2：附件清理确认结果
enum AttachmentCleanup { deleteFiles, keepFiles, cancel }

/// 记录删除前的附件处理确认：有关联图片时弹窗二选一（删文件 / 保留文件）。
/// 返回 null 表示没有附件、无需处理；返回 [AttachmentCleanup.cancel] 表示用户取消整个删除。
Future<AttachmentCleanup?> confirmAttachmentCleanup(
  BuildContext context,
  AttachmentService service,
  String ownerType,
  List<int> ownerIds,
) async {
  final count = await service.countByOwners(ownerType, ownerIds);
  if (count == 0) return null;
  if (!context.mounted) return AttachmentCleanup.cancel;
  return showDialog<AttachmentCleanup>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('关联图片处理'),
      content: Text('该记录（含批量选中记录）共关联 $count 张本地图片。删除记录时图片文件如何处理？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, AttachmentCleanup.cancel),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, AttachmentCleanup.keepFiles),
          child: const Text('保留图片文件'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(foregroundColor: kColorExpired),
          onPressed: () => Navigator.pop(ctx, AttachmentCleanup.deleteFiles),
          child: const Text('一并删除图片'),
        ),
      ],
    ),
  );
}

/// v1.2：图片附件区（编辑页内嵌，仅编辑已有记录时可用——新增记录需要先拿到 id）。
/// 点击缩略图放大预览；附件删除即时生效（数据库单条删除，文件删除需确认）。
class AttachmentSection extends StatefulWidget {
  final String ownerType;
  final int ownerId;

  const AttachmentSection({super.key, required this.ownerType, required this.ownerId});

  @override
  State<AttachmentSection> createState() => _AttachmentSectionState();
}

class _AttachmentSectionState extends State<AttachmentSection> {
  final AttachmentService _service = AttachmentService();
  final ImagePicker _picker = ImagePicker();

  List<MediaAttachment> _attachments = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _service.listByOwner(widget.ownerType, widget.ownerId);
    if (!mounted) return;
    setState(() => _attachments = list);
  }

  Future<void> _pickImages() async {
    try {
      final images = await _picker.pickMultiImage();
      if (images.isEmpty) return;
      await _service.addImages(
        widget.ownerType,
        widget.ownerId,
        images.map((x) => x.path).toList(),
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择图片失败：$e')));
      }
    }
  }

  /// 单张附件删除：数据库记录与图片文件一并删除（逐张操作直接删文件，避免遗留孤儿文件）
  Future<void> _deleteAttachment(MediaAttachment attachment) async {
    await _service.deleteSingle(attachment, deleteFile: true);
    await _reload();
  }

  void _preview(MediaAttachment attachment) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black87,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.file(File(attachment.localFilePath), fit: BoxFit.contain),
              ),
            ),
            SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: kColorExpired),
                    tooltip: '删除这张图片',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteAttachment(attachment);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('图片附件（保存在本机，JSON 备份不含图片）', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final attachment in _attachments)
              GestureDetector(
                onTap: () => _preview(attachment),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(attachment.localFilePath),
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            // 添加图片入口
            GestureDetector(
              onTap: _pickImages,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_a_photo_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
