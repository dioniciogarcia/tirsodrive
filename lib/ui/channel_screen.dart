import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/strings.dart';
import 'file_actions.dart';
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

  final Set<int> _sel = {}; // selected message ids

  void _toggle(DriveFile f) => setState(() => _sel.contains(f.messageId) ? _sel.remove(f.messageId) : _sel.add(f.messageId));

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

        final selected = all.where((f) => _sel.contains(f.messageId)).toList();
        final selecting = _sel.isNotEmpty;
        return Scaffold(
          appBar: selecting
              ? selectionBar(
                  context: context,
                  d: d,
                  selected: selected,
                  onClose: () => setState(_sel.clear),
                  onSelectAll: () => setState(() => _sel.addAll(files.map((f) => f.messageId))),
                )
              : AppBar(
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
          floatingActionButton: widget.embedded || selecting ? null : FloatingActionButton.extended(
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
                  FileRow(
                    file: f,
                    color: _color,
                    selecting: selecting,
                    selected: _sel.contains(f.messageId),
                    downloading: d.transfers.any((x) => !x.upload && !x.finished && x.file?.fileId == f.fileId),
                    onTap: () => selecting ? _toggle(f) : showFileMenu(context, d, f, onSelect: () => _toggle(f)),
                    onLongPress: () => _toggle(f),
                    onMenu: () => showFileMenu(context, d, f, onSelect: () => _toggle(f)),
                  ),
              ],
            ),
          ),
        );
      },
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
