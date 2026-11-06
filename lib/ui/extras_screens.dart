// Favorites, collections, trash bin and duplicate finder.
import 'package:flutter/material.dart';

import '../core/drive.dart';
import '../core/strings.dart';
import 'file_actions.dart';
import 'theme.dart';

/// A list of files from anywhere in TirsoDrive (favorites, one collection), with selection.
class FileListScreen extends StatefulWidget {
  final Drive drive;
  final String title;
  final List<DriveFile> Function() files;
  final String empty;
  final bool embedded;
  const FileListScreen({super.key, required this.drive, required this.title, required this.files, required this.empty, this.embedded = false});
  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  final Set<String> _sel = {};
  Drive get d => widget.drive;
  String _id(DriveFile f) => '${f.chatId}:${f.messageId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => d.loadAllChannels());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final files = d.sorted(widget.files());
        final selected = files.where((f) => _sel.contains(_id(f))).toList();
        final selecting = _sel.isNotEmpty;
        return Scaffold(
          appBar: selecting
              ? selectionBar(context: context, d: d, selected: selected, onClose: () => setState(_sel.clear), onSelectAll: () => setState(() => _sel.addAll(files.map(_id))))
              : AppBar(
                  backgroundColor: C.bg,
                  automaticallyImplyLeading: !widget.embedded,
                  titleSpacing: widget.embedded ? 24 : 0,
                  title: Text(widget.title, style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w600, fontSize: 20)),
                ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              if (d.indexing && files.isEmpty) Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
              if (!d.indexing && files.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Panel(padding: EdgeInsets.all(28), child: Text(widget.empty, textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
                ),
              for (final f in files)
                FileRow(
                  file: f,
                  color: colorForFile(d, f),
                  channelLabel: d.channelName(f.chatId),
                  selecting: selecting,
                  selected: _sel.contains(_id(f)),
                  downloading: false,
                  onTap: () => selecting
                      ? setState(() => _sel.contains(_id(f)) ? _sel.remove(_id(f)) : _sel.add(_id(f)))
                      : showFileMenu(context, d, f, onSelect: () => setState(() => _sel.add(_id(f)))),
                  onLongPress: () => setState(() => _sel.contains(_id(f)) ? _sel.remove(_id(f)) : _sel.add(_id(f))),
                  onMenu: () => showFileMenu(context, d, f, onSelect: () => setState(() => _sel.add(_id(f)))),
                ),
            ],
          ),
        );
      },
    );
  }
}

class CollectionsScreen extends StatelessWidget {
  final Drive drive;
  final bool embedded;
  const CollectionsScreen({super.key, required this.drive, this.embedded = false});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) {
        final cols = drive.collections;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: C.bg,
            automaticallyImplyLeading: !embedded,
            titleSpacing: embedded ? 24 : 0,
            title: Text(t('collections'), style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w600, fontSize: 20)),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Text(t('collections_intro'), style: TextStyle(color: C.muted, fontSize: 13, height: 1.45)),
              SizedBox(height: 12),
              if (cols.isEmpty) Panel(padding: EdgeInsets.all(28), child: Text(t('collections_empty'), textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
              for (final c in cols)
                ListTile(
                  leading: Icon(Icons.collections_bookmark_outlined, color: C.accentSoft),
                  title: Text(c, style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(t('files_count', {'n': drive.allFiles.where((f) => f.collections.contains(c)).length}), style: TextStyle(color: C.muted, fontSize: 12)),
                  trailing: Icon(Icons.chevron_right, color: C.label),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FileListScreen(drive: drive, title: c, files: () => drive.allFiles.where((f) => f.collections.contains(c)).toList(), empty: t('collections_empty')),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class TrashScreen extends StatefulWidget {
  final Drive drive;
  final bool embedded;
  const TrashScreen({super.key, required this.drive, this.embedded = false});
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final Set<int> _sel = {};
  Drive get d => widget.drive;

  @override
  void initState() {
    super.initState();
    final tc = d.trashChannel;
    if (tc != null) WidgetsBinding.instance.addPostFrameCallback((_) => d.loadFiles(tc.chatId, refresh: true));
  }

  Future<void> _confirm(String title, String body, String action, Future<void> Function() run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: TextStyle(fontFamily: displayFont)),
        content: Text(body, style: TextStyle(color: C.soft, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white, minimumSize: Size(96, 44)), onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    if (ok == true) await run();
  }

  void _menu(DriveFile f) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600))),
          Divider(height: 1),
          ListTile(
            leading: Icon(Icons.restore, color: C.accentSoft),
            title: Text(t('restore')),
            onTap: () {
              Navigator.pop(ctx);
              d.restoreFiles([f]);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: C.red),
            title: Text(t('delete_forever'), style: TextStyle(color: C.red)),
            onTap: () {
              Navigator.pop(ctx);
              _confirm(t('delete_forever_q'), t('delete_forever_body'), t('delete_forever'), () => d.deleteForever([f]));
            },
          ),
          SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final tc = d.trashChannel;
        final files = tc == null ? <DriveFile>[] : List<DriveFile>.from(d.filesByChat[tc.chatId] ?? <DriveFile>[]);
        files.sort((a, b) => (b.trashedAt ?? b.date).compareTo(a.trashedAt ?? a.date));
        final selected = files.where((f) => _sel.contains(f.messageId)).toList();
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: _sel.isEmpty ? C.bg : C.surface2,
            automaticallyImplyLeading: !widget.embedded && _sel.isEmpty,
            leading: _sel.isEmpty ? null : IconButton(onPressed: () => setState(_sel.clear), icon: Icon(Icons.close)),
            titleSpacing: widget.embedded ? 24 : 0,
            title: Text(_sel.isEmpty ? t('trash') : t('selected_n', {'n': _sel.length}), style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w600, fontSize: 20)),
            actions: [
              if (_sel.isNotEmpty) ...[
                IconButton(tooltip: t('select_all'), onPressed: () => setState(() => _sel.addAll(files.map((f) => f.messageId))), icon: Icon(Icons.select_all)),
                IconButton(
                  tooltip: t('restore'),
                  onPressed: () {
                    final l = List<DriveFile>.from(selected);
                    setState(_sel.clear);
                    d.restoreFiles(l);
                  },
                  icon: Icon(Icons.restore),
                ),
                IconButton(
                  tooltip: t('delete_forever'),
                  onPressed: () {
                    final l = List<DriveFile>.from(selected);
                    _confirm(t('delete_forever_q'), t('delete_forever_body'), t('delete_forever'), () async {
                      setState(_sel.clear);
                      await d.deleteForever(l);
                    });
                  },
                  icon: Icon(Icons.delete_forever_outlined, color: C.red),
                ),
              ] else if (files.isNotEmpty)
                TextButton(
                  onPressed: () => _confirm(t('empty_trash_q'), t('delete_forever_body'), t('empty_trash'), () => d.purgeTrash(all: true)),
                  child: Text(t('empty_trash'), style: TextStyle(color: C.red)),
                ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Text(t('trash_intro'), style: TextStyle(color: C.muted, fontSize: 13, height: 1.45)),
              SizedBox(height: 12),
              if (files.isEmpty) Panel(padding: EdgeInsets.all(28), child: Text(t('trash_empty'), textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
              for (final f in files)
                FileRow(
                  file: f,
                  color: C.label,
                  channelLabel: t('trash_left', {
                    'c': f.trashedFrom == null ? '?' : d.channelName(f.trashedFrom!),
                    'n': (30 - (now - (f.trashedAt ?? f.date)) ~/ 86400).clamp(0, 30),
                  }),
                  selecting: _sel.isNotEmpty,
                  selected: _sel.contains(f.messageId),
                  downloading: false,
                  onTap: () => _sel.isNotEmpty ? setState(() => _sel.contains(f.messageId) ? _sel.remove(f.messageId) : _sel.add(f.messageId)) : _menu(f),
                  onLongPress: () => setState(() => _sel.contains(f.messageId) ? _sel.remove(f.messageId) : _sel.add(f.messageId)),
                  onMenu: () => _menu(f),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Finds the same file stored more than once (same size and type), anywhere in TirsoDrive.
class DuplicatesScreen extends StatefulWidget {
  final Drive drive;
  final bool embedded;
  const DuplicatesScreen({super.key, required this.drive, this.embedded = false});
  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  Drive get d => widget.drive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => d.loadAllChannels(refresh: true));
  }

  List<List<DriveFile>> _groups() {
    final map = <String, List<DriveFile>>{};
    for (final f in d.allFiles) {
      if (f.size < 64 * 1024) continue; // tiny files match by chance too easily
      map.putIfAbsent('${f.size}:${f.ext.toLowerCase()}', () => []).add(f);
    }
    final out = map.values.where((g) => g.length > 1).toList();
    for (final g in out) {
      g.sort((a, b) => a.date.compareTo(b.date)); // oldest first = the one we keep
    }
    out.sort((a, b) => (b.first.size * (b.length - 1)).compareTo(a.first.size * (a.length - 1)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final groups = d.indexing ? <List<DriveFile>>[] : _groups();
        final wasted = groups.fold<int>(0, (a, g) => a + g.first.size * (g.length - 1));
        return Scaffold(
          appBar: AppBar(
            backgroundColor: C.bg,
            automaticallyImplyLeading: !widget.embedded,
            titleSpacing: widget.embedded ? 24 : 0,
            title: Text(t('duplicates'), style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w600, fontSize: 20)),
            actions: [
              if (groups.isNotEmpty)
                TextButton(
                  onPressed: () => d.deleteFiles([for (final g in groups) ...g.skip(1)]),
                  child: Text(t('dup_clean_all')),
                ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Text(t('dup_intro'), style: TextStyle(color: C.muted, fontSize: 13, height: 1.45)),
              SizedBox(height: 12),
              if (d.indexing)
                Row(children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text(t('indexing', {'i': d.indexDone, 'n': d.channels.length}), style: TextStyle(color: C.muted)),
                ])
              else if (groups.isEmpty)
                Panel(padding: EdgeInsets.all(28), child: Text(t('dup_none'), textAlign: TextAlign.center, style: TextStyle(color: C.muted)))
              else
                Text(t('dup_summary', {'n': groups.length, 's': formatBytes(wasted)}), style: TextStyle(fontWeight: FontWeight.w600)),
              for (final g in groups)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final (i, f) in g.indexed)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Icon(i == 0 ? Icons.check_circle : Icons.copy, size: 18, color: i == 0 ? C.green : C.label),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text('${d.channelName(f.chatId)} · ${formatBytes(f.size)} · ${formatDate(f.date)}', style: TextStyle(color: C.muted, fontSize: 12)),
                              ]),
                            ),
                          ]),
                        ),
                      SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton(onPressed: () => d.deleteFiles(g.skip(1).toList()), child: Text(t('dup_keep_first'))),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
