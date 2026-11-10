// Global search across every TirsoDrive channel, with filters and sorting.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/strings.dart';
import 'file_actions.dart';
import 'theme.dart';

class SearchScreen extends StatefulWidget {
  final Drive drive;
  final bool embedded;
  const SearchScreen({super.key, required this.drive, this.embedded = false});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  String _where = 'all'; // all | key:<category> | roms | chat:<id>
  String _ext = 'all';
  String _size = 'any'; // any | s | m | l | xl
  int _days = 0; // 0 = any time
  bool _byOriginal = false;
  String _sort = 'new'; // new | old | name | big | small
  final Set<String> _sel = {}; // "<chat>:<message>"

  Drive get d => widget.drive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => d.loadAllChannels());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _id(DriveFile f) => '${f.chatId}:${f.messageId}';

  bool _matchWhere(DriveFile f) {
    if (_where == 'all') return true;
    if (_where.startsWith('prog:')) return true; // the list is already that program's files
    final cat = d.channelById(f.chatId)?.category;
    if (_where == 'roms') return cat?.isRom ?? false;
    if (_where == 'apks') return (cat?.isApk ?? false) || cat?.key == 'games';
    if (_where.startsWith('key:')) return cat?.key == _where.substring(4);
    return _where == 'chat:${f.chatId}';
  }

  bool _matchSize(DriveFile f) {
    const mb = 1024 * 1024;
    switch (_size) {
      case 's':
        return f.size < 10 * mb;
      case 'm':
        return f.size >= 10 * mb && f.size < 100 * mb;
      case 'l':
        return f.size >= 100 * mb && f.size < 1024 * mb;
      case 'xl':
        return f.size >= 1024 * mb;
    }
    return true;
  }

  List<DriveFile> _results(List<DriveFile> base) {
    final words = _q.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final out = base.where((f) {
      final n = f.name.toLowerCase();
      if (!words.every(n.contains)) return false;
      if (_ext != 'all' && f.ext.toLowerCase() != _ext) return false;
      if (!_matchSize(f)) return false;
      if (_days > 0) {
        final when = _byOriginal && f.originalMs != null ? f.originalMs! : f.date;
        if (now - when > _days * 86400) return false;
      }
      return true;
    }).toList();
    int dateOf(DriveFile f) => _byOriginal && f.originalMs != null ? f.originalMs! : f.date;
    switch (_sort) {
      case 'old':
        out.sort((a, b) => dateOf(a).compareTo(dateOf(b)));
        break;
      case 'name':
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'big':
        out.sort((a, b) => b.size.compareTo(a.size));
        break;
      case 'small':
        out.sort((a, b) => a.size.compareTo(b.size));
        break;
      default:
        out.sort((a, b) => dateOf(b).compareTo(dateOf(a)));
    }
    return out;
  }

  Widget _drop<T>(String label, T value, List<(T, String)> options, ValueChanged<T> onChanged) {
    return Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: options.first.$1 == value ? C.border2 : C.accent),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: C.surface2,
          isDense: true,
          style: TextStyle(color: C.text, fontSize: 13, fontFamily: 'Inter'),
          hint: Text(label),
          items: [for (final o in options) DropdownMenuItem<T>(value: o.$1, child: Text(o.$2))],
          onChanged: (v) {
            if (v != null) setState(() => onChanged(v));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final all = _where.startsWith('prog:') ? d.programFiles(_where.substring(5)) : d.allFiles;
        final inPlace = all.where(_matchWhere).toList();
        final exts = <String, int>{};
        for (final f in inPlace) {
          final e = f.ext.toLowerCase();
          if (e.isNotEmpty) exts[e] = (exts[e] ?? 0) + 1;
        }
        final extList = exts.keys.toList()..sort((a, b) => exts[b]!.compareTo(exts[a]!));
        if (_ext != 'all' && !exts.containsKey(_ext)) _ext = 'all';
        final results = _results(inPlace);
        final selected = results.where((f) => _sel.contains(_id(f))).toList();
        final selecting = _sel.isNotEmpty;

        final whereOptions = <(String, String)>[
          ('all', t('f_everywhere')),
          for (final c in libraryCategories)
            if (d.channelForKey(c.key) != null) ('key:${c.key}', c.label(appLang)),
          if (romCategories.any((c) => d.channelForKey(c.key) != null)) ('roms', t('f_all_roms')),
          for (final c in romCategories)
            if (d.channelForKey(c.key) != null) ('key:${c.key}', c.full(appLang)),
          if (apkCategories.any((c) => d.channelForKey(c.key) != null)) ('apks', t('f_all_apks')),
          for (final c in apkCategories)
            if (d.channelForKey(c.key) != null) ('key:${c.key}', c.full(appLang)),
          for (final ch in d.customChannels) ('chat:${ch.chatId}', ch.display),
          for (final pr in d.programs.list)
            if (pr.isolated) ('prog:${pr.name}', '🔒 ${pr.name}'),
        ];
        if (!whereOptions.any((o) => o.$1 == _where)) _where = 'all';

        final body = ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // TV remote: a text field swallows the arrow keys, so Down/Up are handed to the focus system
            // and the field never traps the pointer. "Done/Search" on the keyboard also moves on to the results.
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, ev) {
                if (ev is! KeyDownEvent) return KeyEventResult.ignored;
                final k = ev.logicalKey;
                if (k == LogicalKeyboardKey.arrowDown) {
                  FocusScope.of(context).focusInDirection(TraversalDirection.down);
                  return KeyEventResult.handled;
                }
                if (k == LogicalKeyboardKey.arrowUp) {
                  FocusScope.of(context).focusInDirection(TraversalDirection.up);
                  return KeyEventResult.handled;
                }
                if (d.isTv && k == LogicalKeyboardKey.arrowLeft && _q.selection.baseOffset <= 0) {
                  FocusScope.of(context).focusInDirection(TraversalDirection.left);
                  return KeyEventResult.handled;
                }
                if (d.isTv && k == LogicalKeyboardKey.arrowRight && _q.selection.baseOffset >= _q.text.length) {
                  FocusScope.of(context).focusInDirection(TraversalDirection.right);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
              controller: _q,
              autofocus: !d.isTv, // on a TV the keyboard opens only when the field is selected
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => FocusScope.of(context).focusInDirection(TraversalDirection.down),
              style: TextStyle(fontSize: 16),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: t('search_hint'),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(tooltip: t('cancel'), onPressed: () => setState(_q.clear), icon: Icon(Icons.close)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            ),
            SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _drop<String>(t('f_where'), _where, whereOptions, (v) => _where = v),
              _drop<String>(t('f_type'), _ext, [('all', t('f_any_type')), for (final e in extList.take(40)) (e, '.$e  (${exts[e]})')], (v) => _ext = v),
              _drop<String>(t('f_size'), _size, [
                ('any', t('f_any_size')),
                ('s', '< 10 MB'),
                ('m', '10–100 MB'),
                ('l', '100 MB – 1 GB'),
                ('xl', '> 1 GB'),
              ], (v) => _size = v),
              _drop<int>(t('f_date'), _days, [
                (0, t('f_any_date')),
                (1, t('f_24h')),
                (7, t('f_7d')),
                (30, t('f_30d')),
                (365, t('f_year')),
              ], (v) => _days = v),
              _drop<bool>(t('f_datekind'), _byOriginal, [(false, t('f_uploaded')), (true, t('f_original'))], (v) => _byOriginal = v),
              _drop<String>(t('f_sort'), _sort, [
                ('new', t('s_new')),
                ('old', t('s_old')),
                ('name', t('s_name')),
                ('big', t('s_big')),
                ('small', t('s_small')),
              ], (v) => _sort = v),
            ]),
            SizedBox(height: 14),
            Row(children: [
              Text(t('results_n', {'n': results.length}), style: TextStyle(color: C.muted, fontSize: 13)),
              Spacer(),
              if (d.indexing) ...[
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text(t('indexing', {'i': d.indexDone, 'n': d.channels.length}), style: TextStyle(color: C.muted, fontSize: 12)),
              ] else
                TextButton.icon(
                  onPressed: () => d.loadAllChannels(refresh: true),
                  icon: Icon(Icons.refresh, size: 16),
                  label: Text(t('refresh_index')),
                ),
            ]),
            SizedBox(height: 4),
            for (final f in results.take(500))
              FileRow(
                file: f,
                color: colorForFile(d, f),
                channelLabel: d.channelName(f.chatId),
                selecting: selecting,
                selected: _sel.contains(_id(f)),
                downloading: d.transfers.any((x) => !x.upload && !x.finished && x.file?.fileId == f.fileId),
                onTap: () => selecting
                    ? setState(() => _sel.contains(_id(f)) ? _sel.remove(_id(f)) : _sel.add(_id(f)))
                    : showFileMenu(context, d, f, onSelect: () => setState(() => _sel.add(_id(f)))),
                onLongPress: () => setState(() => _sel.contains(_id(f)) ? _sel.remove(_id(f)) : _sel.add(_id(f))),
                onMenu: () => showFileMenu(context, d, f, onSelect: () => setState(() => _sel.add(_id(f)))),
              ),
            if (results.length > 500)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(t('more_results', {'n': results.length - 500}), style: TextStyle(color: C.label, fontSize: 12)),
              ),
          ],
        );

        return Scaffold(
          appBar: selecting
              ? selectionBar(
                  context: context,
                  d: d,
                  selected: selected,
                  onClose: () => setState(_sel.clear),
                  onSelectAll: () => setState(() => _sel.addAll(results.map(_id))),
                )
              : AppBar(
                  backgroundColor: C.bg,
                  automaticallyImplyLeading: !widget.embedded,
                  titleSpacing: widget.embedded ? 24 : 0,
                  title: Text(t('search_title'), style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w600, fontSize: 20)),
                ),
          body: body,
        );
      },
    );
  }
}
