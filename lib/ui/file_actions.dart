// File menu, info, rename, delete, copy/move destination picker and the file row — shared by channels and search.
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/native.dart';
import '../core/stream_server.dart';
import '../core/strings.dart';
import 'media_viewer.dart';
import 'theme.dart';

Color colorForFile(Drive d, DriveFile f) => d.channelById(f.chatId)?.category?.color ?? C.accent;

Future<void> showFileMenu(BuildContext context, Drive d, DriveFile f, {VoidCallback? onSelect}) {
  Widget item(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
        leading: Icon(icon, color: color ?? C.text),
        title: Text(label, style: TextStyle(color: color ?? C.text, fontWeight: FontWeight.w500)),
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
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${formatBytes(f.size)} · ${d.channelName(f.chatId)}', style: TextStyle(color: C.muted)),
          ),
          Divider(height: 1),
          if (isPlayable(f)) item(ctx, Icons.play_circle_outline, t('menu_play'), () => playMedia(context, d, f), color: C.accentSoft),
          if (isImage(f)) item(ctx, Icons.image_outlined, t('menu_view'), () => viewImage(context, d, f), color: C.accentSoft),
          item(ctx, Icons.open_in_new, t(isPlayable(f) || isImage(f) ? 'menu_open_other' : 'menu_open'), () => d.download(f, 'open')),
          item(ctx, Icons.download_outlined, t('menu_save'), () => d.download(f, 'save')),
          item(ctx, Icons.share_outlined, t('menu_share'), () => showShareSheet(context, d, [f])),
          item(ctx, Icons.copy_all_outlined, t('menu_copy'), () => copyOrMove(context, d, [f], move: false)),
          item(ctx, Icons.drive_file_move_outline, t('menu_move'), () => copyOrMove(context, d, [f], move: true)),
          item(ctx, Icons.edit_outlined, t('menu_rename'), () => renameDialog(context, d, f)),
          if (onSelect != null) item(ctx, Icons.check_circle_outline, t('menu_select'), onSelect),
          item(ctx, Icons.info_outline, t('menu_info'), () => showFileInfo(context, d, f)),
          item(ctx, Icons.delete_outline, t('menu_delete'), () => confirmDeleteFiles(context, d, [f]), color: C.red),
          SizedBox(height: 8),
        ]),
      ),
    ),
  );
}

void showFileInfo(BuildContext context, Drive d, DriveFile f) {
  Widget row(String k, String v) => Padding(
        padding: EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: TextStyle(color: C.muted, fontSize: 13))),
          Expanded(child: SelectableText(v, style: TextStyle(fontSize: 13))),
        ]),
      );
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('menu_info'), style: TextStyle(fontFamily: displayFont)),
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
      title: Text(files.length == 1 ? t('delete_title') : t('delete_title_n', {'n': files.length}), style: TextStyle(fontFamily: displayFont)),
      content: Text(files.length == 1 ? t('delete_body', {'n': files.first.name}) : t('delete_body_n'),
          style: TextStyle(color: C.soft, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white, minimumSize: Size(96, 44)),
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
      title: Text(t('menu_rename'), style: TextStyle(fontFamily: displayFont)),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
          SizedBox(height: 10),
          Text(t('rename_note'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.4)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
        FilledButton(style: FilledButton.styleFrom(minimumSize: Size(96, 44)), onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t('menu_rename'))),
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
            title: Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(sub, style: TextStyle(color: C.muted, fontSize: 12)),
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
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(move ? t('move_to_n', {'n': files.length}) : t('copy_to_n', {'n': files.length}),
                style: TextStyle(fontFamily: displayFont, fontSize: 20, fontWeight: FontWeight.w600)),
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
      color: selected ? C.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(children: [
            if (selecting)
              Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? C.accent : C.label),
              ),
            ExtBadge(file.ext, color: color),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                  if (isTv) ...[
                    SizedBox(width: 6),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(5)),
                      child: Text('TV', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1A1204))),
                    ),
                  ],
                ]),
                SizedBox(height: 3),
                Text(
                  [formatBytes(file.size), formatDate(file.date), ?channelLabel].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: C.muted),
                ),
              ]),
            ),
            if (downloading)
              Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))),
            if (!selecting) IconButton(tooltip: t('menu_info'), onPressed: onMenu, icon: Icon(Icons.more_vert, color: C.muted)),
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
    leading: IconButton(tooltip: t('cancel'), onPressed: onClose, icon: Icon(Icons.close)),
    title: Text(t('selected_n', {'n': selected.length}), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
    actions: [
      IconButton(tooltip: t('select_all'), onPressed: onSelectAll, icon: Icon(Icons.select_all)),
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
        icon: Icon(Icons.download_outlined),
      ),
      IconButton(
        tooltip: t('menu_share'),
        onPressed: selected.isEmpty
            ? null
            : () async {
                final list = List<DriveFile>.from(selected);
                onClose();
                await showShareSheet(context, d, list);
              },
        icon: Icon(Icons.share_outlined),
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
        icon: Icon(Icons.copy_all_outlined),
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
        icon: Icon(Icons.drive_file_move_outline),
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
        icon: Icon(Icons.delete_outline, color: C.red),
      ),
    ],
  );
}

// ---------------------------------------------------------------- sharing

Future<void> showShareSheet(BuildContext context, Drive d, List<DriveFile> files) async {
  final clouds = NativeBridge.cloudFolders();
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(files.length == 1 ? files.first.name : t('selected_n', {'n': files.length}),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(formatBytes(files.fold<int>(0, (a, f) => a + f.size)), style: TextStyle(color: C.muted)),
        ),
        Divider(height: 1),
        ListTile(
          leading: Icon(Icons.send_outlined, color: C.accentSoft),
          title: Text(t('share_telegram')),
          subtitle: Text(t('share_telegram_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
          onTap: () => Navigator.pop(ctx, 'tg'),
        ),
        if (Platform.isAndroid)
          ListTile(
            leading: Icon(Icons.share_outlined, color: C.accentSoft),
            title: Text(t('share_apps')),
            subtitle: Text(t('share_apps_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, 'apps'),
          ),
        for (final (label, path) in clouds)
          ListTile(
            leading: Icon(Icons.cloud_upload_outlined, color: C.accentSoft),
            title: Text(t('send_cloud', {'c': label})),
            subtitle: Text('$path\\TirsoDrive', style: TextStyle(color: C.muted, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, 'cloud:$label|$path'),
          ),
        if (Platform.isWindows && clouds.isEmpty)
          ListTile(
            leading: Icon(Icons.cloud_off_outlined, color: C.label),
            title: Text(t('no_cloud'), style: TextStyle(color: C.muted)),
            subtitle: Text(t('no_cloud_sub'), style: TextStyle(color: C.label, fontSize: 12)),
          ),
        SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'tg') {
    final target = await _pickChat(context, d);
    if (target != null) await d.sendToChat(target, files);
  } else if (choice == 'apps') {
    await d.shareToApps(files);
  } else if (choice.startsWith('cloud:')) {
    final parts = choice.substring(6).split('|');
    await d.sendToFolder(files, parts[1], parts[0]);
  }
}

Future<ShareTarget?> _pickChat(BuildContext context, Drive d) {
  return showModalBottomSheet<ShareTarget>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ChatPicker(drive: d),
  );
}

class _ChatPicker extends StatefulWidget {
  final Drive drive;
  const _ChatPicker({required this.drive});
  @override
  State<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends State<_ChatPicker> {
  late final List<ShareTarget> chats = widget.drive.shareChats();
  List<ShareTarget> contacts = [];
  String q = '';

  @override
  void initState() {
    super.initState();
    widget.drive.shareContacts(chats.map((c) => c.chatId).toSet()).then((c) {
      if (mounted) setState(() => contacts = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    bool match(ShareTarget s) => q.isEmpty || s.title.toLowerCase().contains(q.toLowerCase());
    Widget tile(ShareTarget s) => ListTile(
          leading: CircleAvatar(
            backgroundColor: C.surface2,
            child: s.chatId == widget.drive.myId
                ? Icon(Icons.bookmark_outline, color: C.accentSoft)
                : Icon(s.group ? Icons.group_outlined : Icons.person_outline, color: C.soft),
          ),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.pop(context, s),
        );
    final c1 = chats.where(match).toList();
    final c2 = contacts.where(match).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: t('share_search')),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: ListView(controller: scroll, children: [
            if (c1.isNotEmpty) Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: SectionLabel(t('share_chats'))),
            ...c1.map(tile),
            if (c2.isNotEmpty) Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: SectionLabel(t('share_contacts'))),
            ...c2.map(tile),
          ]),
        ),
      ]),
    );
  }
}
