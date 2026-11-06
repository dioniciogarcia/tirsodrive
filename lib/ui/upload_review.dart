import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/native.dart';
import '../core/strings.dart';
import 'theme.dart';

/// Picks files and either sends them straight to [fixedKey]/[fixedChatId],
/// or shows the auto-sort review sheet when no destination is fixed.
Future<void> pickAndUpload(BuildContext context, Drive drive, {String? fixedKey, int? fixedChatId, bool folder = false}) async {
  final picked = folder ? await drive.pickFolder() : await drive.pick();
  if (!context.mounted) return;
  await uploadFiles(context, drive, picked, fixedKey: fixedKey, fixedChatId: fixedChatId);
}

/// Sends already-chosen files (picker, drag and drop, folder scan) to a fixed channel or the review sheet.
Future<void> uploadFiles(BuildContext context, Drive drive, List<PickedFile> picked, {String? fixedKey, int? fixedChatId}) async {
  if (picked.isEmpty) return;
  final ok = picked.where((f) => f.size >= 0 && f.size <= drive.maxBytes).toList();
  final big = picked.where((f) => f.size > drive.maxBytes).toList();

  if (fixedKey != null || fixedChatId != null) {
    if (big.isNotEmpty) snack(context, '${t('too_large', {'n': big.length})} · ${formatBytes(drive.maxBytes)}');
    if (ok.isEmpty) return;
    drive.enqueueUploads(ok.map((f) => _transfer(f, fixedKey, fixedChatId)).toList());
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReviewSheet(drive: drive, files: ok, tooLarge: big),
  );
}

Transfer _transfer(PickedFile f, String? key, int? chatId) => Transfer.upload(
      name: f.name,
      size: f.size,
      uri: f.uri,
      sourcePath: f.path,
      modifiedMs: f.modifiedMs,
      destKey: key,
      destChatId: chatId,
    );

class _Entry {
  final PickedFile file;
  String? dest; // category key, or "chat:<id>"
  _Entry(this.file, this.dest);
}

class _ReviewSheet extends StatefulWidget {
  final Drive drive;
  final List<PickedFile> files;
  final List<PickedFile> tooLarge;
  const _ReviewSheet({required this.drive, required this.files, required this.tooLarge});
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final List<_Entry> entries = widget.files.map((f) => _Entry(f, routeFile(f.name))).toList();

  List<DropdownMenuItem<String>> _options(_Entry e) {
    final ext = extensionOf(e.file.name);
    final suggested = ambiguousExt[ext] ?? const <String>[];
    final ordered = <String>[...suggested, ...allCategories.map((c) => c.key).where((k) => !suggested.contains(k))];
    final items = ordered.map((k) {
      final c = categoryByKey(k)!;
      return DropdownMenuItem(value: k, child: Text(c.isRom ? 'ROMs · ${c.label(appLang)}' : c.label(appLang), overflow: TextOverflow.ellipsis));
    }).toList();
    for (final ch in widget.drive.customChannels) {
      items.add(DropdownMenuItem(value: 'chat:${ch.chatId}', child: Text(ch.display, overflow: TextOverflow.ellipsis)));
    }
    return items;
  }

  void _start() {
    final list = entries.map((e) {
      final d = e.dest!;
      return d.startsWith('chat:') ? _transfer(e.file, null, int.parse(d.substring(5))) : _transfer(e.file, d, null);
    }).toList();
    Navigator.pop(context);
    widget.drive.enqueueUploads(list);
  }

  @override
  Widget build(BuildContext context) {
    final missing = entries.where((e) => e.dest == null).length;
    final total = entries.fold<int>(0, (a, e) => a + e.file.size);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('review_title'), style: const TextStyle(fontFamily: displayFont, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${t('files_count', {'n': entries.length})} · ${formatBytes(total)}', style: const TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 4),
            Text(t('review_sub'), style: const TextStyle(color: C.muted, fontSize: 13)),
          ]),
        ),
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    ExtBadge(extensionOf(e.file.name).toUpperCase(), color: categoryByKey(e.dest ?? '')?.color ?? C.label, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(formatBytes(e.file.size), style: const TextStyle(color: C.muted, fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: DropdownButton<String>(
                        value: e.dest,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: C.surface2,
                        hint: Text(t('choose_console'), style: const TextStyle(color: C.amber, fontSize: 13, fontWeight: FontWeight.w600)),
                        style: const TextStyle(color: C.soft, fontSize: 13, fontFamily: 'Inter'),
                        items: _options(e),
                        onChanged: (v) => setState(() => e.dest = v),
                      ),
                    ),
                  ]),
                ),
              if (widget.tooLarge.isNotEmpty) ...[
                const SizedBox(height: 12),
                Panel(
                  color: C.amberBg,
                  borderColor: C.amberBorder,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('too_large', {'n': widget.tooLarge.length}), style: const TextStyle(color: C.amberText, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    for (final f in widget.tooLarge)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFF1DDBA), fontSize: 13))),
                          Text(formatBytes(f.size), style: const TextStyle(color: Color(0xFFF1DDBA), fontSize: 13)),
                        ]),
                      ),
                    const SizedBox(height: 6),
                    Text(t('too_large_tip', {'s': formatBytes(widget.drive.maxBytes)}), style: const TextStyle(color: Color(0xFFD9BE8E), fontSize: 12, height: 1.4)),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: missing > 0 || entries.isEmpty ? null : _start,
                child: Text(missing > 0
                    ? t('needs_choice', {'n': missing})
                    : entries.length == 1
                        ? t('upload_one')
                        : t('upload_n', {'n': entries.length})),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
