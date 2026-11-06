// File menu, info, rename, delete, copy/move destination picker and the file row — shared by channels and search.
import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/strings.dart';
import 'theme.dart';

Color colorForFile(Drive d, DriveFile f) => d.channelById(f.chatId)?.category?.color ?? C.accent;

Future<void> showFileMenu(BuildContext context, Drive d, DriveFile f, {VoidCallback? onSelect}) {
  Widget item(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {Color color = C.text}) => ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
      );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${formatBytes(f.size)} · ${d.channelName(f.chatId)}', style: const TextStyle(color: C.muted)),
          ),
          const Divider(height: 1),
          item(ctx, Icons.open_in_new, t('menu_open'), () => d.download(f, 'open')),
          item(ctx, Icons.download_outlined, t('menu_save'), () => d.download(f, 'save')),
          item(ctx, Icons.copy_all_outlined, t('menu_copy'), () => copyOrMove(context, d, [f], move: false)),
          item(ctx, Icons.drive_file_move_outline, t('menu_move'), () => copyOrMove(context, d, [f], move: true)),
          item(ctx, Icons.edit_outlined, t('menu_rename'), () => renameDialog(context, d, f)),
          if (onSelect != null) item(ctx, Icons.check_circle_outline, t('menu_select'), onSelect),
          item(ctx, Icons.info_outline, t('menu_info'), () => showFileInfo(context, d, f)),
          item(ctx, Icons.delete_outline, t('menu_delete'), () => confirmDeleteFiles(context, d, [f]), color: C.red),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
}

void showFileInfo(BuildContext context, Drive d, DriveFile f) {
  Widget row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: C.muted, fontSize: 13))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
        ]),
      );
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('menu_info'), style: const TextStyle(fontFamily: displayFont)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        row(t('info_name'), f.name),
        row(t('info_size'), '${formatBytes(f.size)} (${f.size} bytes)'),
        row(t('info_type'), f.mime),
        row(t('info_channel'), d.channelById(f.chatId)?.title ?? ''),
        row(t('info_uploaded'), formatDate(f.date)),
        if (f.originalMs != null) row(t('info_modified'), formatDate(f.originalMs!)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('close')))],
    ),
  );
}

Future<void> confirmDeleteFiles(BuildContext context, Drive d, List<DriveFile> files) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(files.length == 1 ? t('delete_title') : t('delete_title_n', {'n': files.length}), style: const TextStyle(fontFamily: displayFont)),
      content: Text(files.length == 1 ? t('delete_body', {'n': files.first.name}) : t('delete_body_n'),
          style: const TextStyle(color: C.soft, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white, minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t('menu_delete')),
        ),
      ],
    ),
  );
  if (ok == true) await d.deleteFiles(files);
}

Future<void> renameDialog(BuildContext context, Drive d, DriveFile f) async {
  final ctrl = TextEditingController(text: f.name);
  final dot = f.name.lastIndexOf('.');
  ctrl.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : f.name.length);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('menu_rename'), style: const TextStyle(fontFamily: displayFont)),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
          const SizedBox(height: 10),
          Text(t('rename_note'), style: const TextStyle(color: C.muted, fontSize: 12, height: 1.4)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(96, 44)), onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t('menu_rename'))),
      ],
    ),
  );
  if (name != null) await d.renameFile(f, name);
}

/// Asks where to copy/move [files], then does it.
Future<void> copyOrMove(BuildContext context, Drive d, List<DriveFile> files, {required bool move}) async {
  final here = files.map((f) => f.chatId).toSet();
  final dest = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      Widget tile(String id, String label, String sub, Color color, String tag) => ListTile(
            leading: ExtBadge(tag, color: color, size: 36),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(sub, style: const TextStyle(color: C.muted, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, id),
          );
      final tiles = <Widget>[];
      for (final c in allCategories) {
        final ch = d.channelForKey(c.key);
        if (ch != null && here.length == 1 && here.contains(ch.chatId)) continue;
        tiles.add(tile('key:${c.key}', c.isRom ? 'ROMs · ${c.label(appLang)}' : c.label(appLang), ch != null ? c.channelTitle : t('not_created'),
            c.color, c.tag));
      }
      for (final ch in d.customChannels) {
        if (here.length == 1 && here.contains(ch.chatId)) continue;
        tiles.add(tile('chat:${ch.chatId}', ch.display, ch.title, C.label, 'TD'));
      }
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(move ? t('move_to_n', {'n': files.length}) : t('copy_to_n', {'n': files.length}),
                style: const TextStyle(fontFamily: displayFont, fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: ListView(controller: scroll, children: tiles)),
        ]),
      );
    },
  );
  if (dest == null) return;
  if (dest.startsWith('key:')) {
    await d.copyFiles(files, toKey: dest.substring(4), move: move);
  } else {
    await d.copyFiles(files, toChatId: int.parse(dest.substring(5)), move: move);
  }
}

class FileRow extends StatelessWidget {
  final DriveFile file;
  final Color color;
  final bool downloading;
  final bool selecting;
  final bool selected;
  final String? channelLabel; // shown in search results
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenu;
  const FileRow({
    super.key,
    required this.file,
    required this.color,
    required this.downloading,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
    this.selecting = false,
    this.selected = false,
    this.channelLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isTv = RegExp(r'\bTV\.apk$', caseSensitive: false).hasMatch(file.name);
    return Material(
      color: selected ? const Color(0xFF1E2A44) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? C.accent : C.label),
              ),
            ExtBadge(file.ext, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                  if (isTv) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(5)),
                      child: const Text('TV', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1A1204))),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(
                  [formatBytes(file.size), formatDate(file.date), ?channelLabel].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: C.muted),
                ),
              ]),
            ),
            if (downloading)
              const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))),
            if (!selecting) IconButton(tooltip: t('menu_info'), onPressed: onMenu, icon: const Icon(Icons.more_vert, color: C.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Top bar shown while files are selected (channel view and search).
PreferredSizeWidget selectionBar({
  required BuildContext context,
  required Drive d,
  required List<DriveFile> selected,
  required VoidCallback onClose,
  required VoidCallback onSelectAll,
}) {
  return AppBar(
    backgroundColor: C.surface2,
    leading: IconButton(tooltip: t('cancel'), onPressed: onClose, icon: const Icon(Icons.close)),
    title: Text(t('selected_n', {'n': selected.length}), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
    actions: [
      IconButton(tooltip: t('select_all'), onPressed: onSelectAll, icon: const Icon(Icons.select_all)),
      IconButton(
        tooltip: t('menu_save'),
        onPressed: selected.isEmpty
            ? null
            : () {
                for (final f in selected) {
                  d.download(f, 'save');
                }
                onClose();
              },
        icon: const Icon(Icons.download_outlined),
      ),
      IconButton(
        tooltip: t('menu_copy'),
        onPressed: selected.isEmpty
            ? null
            : () async {
                final list = List<DriveFile>.from(selected);
                onClose();
                await copyOrMove(context, d, list, move: false);
              },
        icon: const Icon(Icons.copy_all_outlined),
      ),
      IconButton(
        tooltip: t('menu_move'),
        onPressed: selected.isEmpty
            ? null
            : () async {
                final list = List<DriveFile>.from(selected);
                onClose();
                await copyOrMove(context, d, list, move: true);
              },
        icon: const Icon(Icons.drive_file_move_outline),
      ),
      IconButton(
        tooltip: t('menu_delete'),
        onPressed: selected.isEmpty
            ? null
            : () async {
                final list = List<DriveFile>.from(selected);
                onClose();
                await confirmDeleteFiles(context, d, list);
              },
        icon: const Icon(Icons.delete_outline, color: C.red),
      ),
    ],
  );
}
