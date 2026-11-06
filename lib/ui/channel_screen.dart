import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/strings.dart';
import 'theme.dart';
import 'upload_review.dart';

/// One TirsoDrive channel ("folder"): its files, uploads in progress and the file menu.
class ChannelScreen extends StatefulWidget {
  final Drive drive;
  final String? categoryKey;
  final int? chatId;
  final bool embedded; // inside the Windows layout (upload buttons live in the header)
  const ChannelScreen({super.key, required this.drive, this.categoryKey, this.chatId, this.embedded = false});
  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  String _filter = '';
  int? _loadedFor;

  Drive get d => widget.drive;

  int? get _chatId => widget.chatId ?? (widget.categoryKey == null ? null : d.channelForKey(widget.categoryKey!)?.chatId);

  String get _title {
    if (widget.categoryKey != null) {
      final c = categoryByKey(widget.categoryKey!)!;
      return c.isRom ? 'ROMs · ${c.label(appLang)}' : c.label(appLang);
    }
    return d.channelById(widget.chatId!)?.display ?? '';
  }

  Color get _color => widget.categoryKey == null ? C.accent : categoryByKey(widget.categoryKey!)!.color;

  void _ensureLoaded() {
    final id = _chatId;
    if (id != null && _loadedFor != id) {
      _loadedFor = id;
      WidgetsBinding.instance.addPostFrameCallback((_) => d.loadFiles(id));
    }
  }

  void _menu(DriveFile f) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(formatBytes(f.size), style: const TextStyle(color: C.muted)),
          ),
          const Divider(height: 1),
          _item(ctx, Icons.open_in_new, t('menu_open'), () => d.download(f, 'open')),
          _item(ctx, Icons.download_outlined, t('menu_save'), () => d.download(f, 'save')),
          _item(ctx, Icons.info_outline, t('menu_info'), () => _info(f)),
          _item(ctx, Icons.delete_outline, t('menu_delete'), () => _confirmDelete(f), color: C.red),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _item(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {Color color = C.text}) => ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
      );

  void _info(DriveFile f) {
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

  void _confirmDelete(DriveFile f) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('delete_title'), style: const TextStyle(fontFamily: displayFont)),
        content: Text(t('delete_body', {'n': f.name}), style: const TextStyle(color: C.soft, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white, minimumSize: const Size(96, 44)),
            onPressed: () {
              Navigator.pop(ctx);
              d.deleteFile(f);
            },
            child: Text(t('menu_delete')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        _ensureLoaded();
        final id = _chatId;
        final channel = id == null ? null : d.channelById(id);
        final all = id == null ? <DriveFile>[] : (d.filesByChat[id] ?? <DriveFile>[]);
        final files = _filter.isEmpty ? all : all.where((f) => f.name.toLowerCase().contains(_filter.toLowerCase())).toList();
        final loading = id != null && d.loadingChats.contains(id);
        final pending = d.transfers.where((x) =>
            x.upload &&
            !x.finished &&
            ((id != null && (x.chatId == id || x.destChatId == id)) || (widget.categoryKey != null && x.destKey == widget.categoryKey)));

        return Scaffold(
          appBar: AppBar(
            backgroundColor: C.bg,
            automaticallyImplyLeading: !widget.embedded,
            titleSpacing: widget.embedded ? 24 : 0,
            toolbarHeight: widget.embedded ? 76 : null,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title, style: const TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w600, fontSize: 20)),
              Text(
                channel == null
                    ? t('not_created')
                    : '${t('ready_channel')} · ${channel.title} · ${t('files_count', {'n': all.length})}',
                style: const TextStyle(fontSize: 12, color: C.muted),
              ),
            ]),
            actions: [
              if (id != null)
                IconButton(tooltip: 'Refresh', onPressed: () => d.loadFiles(id, refresh: true), icon: const Icon(Icons.refresh)),
            ],
          ),
          floatingActionButton: widget.embedded ? null : FloatingActionButton.extended(
            backgroundColor: C.accent,
            foregroundColor: C.onAccent,
            onPressed: () => pickAndUpload(context, d, fixedKey: widget.categoryKey, fixedChatId: widget.chatId),
            icon: const Icon(Icons.upload),
            label: Text(t('upload'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              if (id != null) await d.loadFiles(id, refresh: true);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              children: [
                if (all.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '…'),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                for (final tr in pending) _PendingRow(tr: tr),
                if (loading && all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Column(children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(t('loading_files'), style: const TextStyle(color: C.muted)),
                    ]),
                  )
                else if (all.isEmpty && pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Panel(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                      child: Column(children: [
                        Text(t('empty_title'), style: const TextStyle(fontFamily: displayFont, fontSize: 20)),
                        const SizedBox(height: 8),
                        Text(t(widget.embedded ? 'empty_body_pc' : 'empty_body'), style: const TextStyle(color: C.muted)),
                      ]),
                    ),
                  ),
                for (final f in files)
                  _FileRow(
                    file: f,
                    color: _color,
                    downloading: d.transfers.any((x) => !x.upload && !x.finished && x.file?.fileId == f.fileId),
                    onTap: () => _menu(f),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  final DriveFile file;
  final Color color;
  final bool downloading;
  final VoidCallback onTap;
  const _FileRow({required this.file, required this.color, required this.downloading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isTv = RegExp(r'\bTV\.apk$', caseSensitive: false).hasMatch(file.name);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(children: [
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
              Text('${formatBytes(file.size)} · ${formatDate(file.date)}', style: const TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          if (downloading) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))),
          IconButton(tooltip: t('menu_info'), onPressed: onTap, icon: const Icon(Icons.more_vert, color: C.muted)),
        ]),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final Transfer tr;
  const _PendingRow({required this.tr});
  @override
  Widget build(BuildContext context) {
    final label = switch (tr.status) {
      TStatus.creating => t('tr_creating'),
      TStatus.preparing => t('tr_preparing'),
      TStatus.waiting => t('tr_waiting', {'s': tr.waitSeconds}),
      TStatus.active => tr.bytes >= tr.size && tr.size > 0 ? t('tr_finishing') : '${(tr.fraction * 100).round()}%',
      _ => t('tr_next', {'n': ''}).replaceAll(RegExp(r'\s*\(\)'), ''),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Row(children: [
        ExtBadge(extensionOf(tr.name).toUpperCase(), color: C.label),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.soft)),
            const SizedBox(height: 5),
            if (tr.status == TStatus.active) Bar(tr.fraction, height: 4),
            const SizedBox(height: 3),
            Text('${formatBytes(tr.size)} · $label', style: const TextStyle(fontSize: 12, color: C.accentSoft)),
          ]),
        ),
      ]),
    );
  }
}
