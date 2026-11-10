import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/strings.dart';
import 'channel_screen.dart';
import 'extras_screens.dart';
import 'search_screen.dart';
import 'theme.dart';
import 'upload_review.dart';

Future<void> showNewChannelDialog(BuildContext context, Drive drive) async {
  final ctrl = TextEditingController();
  String? err;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(t('new_channel_title'), style: TextStyle(fontFamily: displayFont)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: t('new_channel_hint')), onChanged: (_) => set(() {})),
          SizedBox(height: 10),
          Text(t('new_channel_note', {'n': ctrl.text.trim().isEmpty ? '…' : ctrl.text.trim()}), style: TextStyle(color: C.muted, fontSize: 13)),
          if (err != null) Padding(padding: EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: C.red, fontSize: 13))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: Size(96, 44)),
            onPressed: () async {
              final e = await drive.createCustomChannel(ctrl.text);
              if (e == null) {
                if (ctx.mounted) Navigator.pop(ctx);
              } else {
                set(() => err = e);
              }
            },
            child: Text(t('create')),
          ),
        ],
      ),
    ),
  );
}


class LibraryScreen extends StatelessWidget {
  final Drive drive;
  const LibraryScreen({super.key, required this.drive});

  void _openKey(BuildContext context, String key) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelScreen(drive: drive, categoryKey: key)));

  Future<void> _newChannel(BuildContext context) => showNewChannelDialog(context, drive);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) {
        final mine = drive.customChannels;
        final romCount = romCategories.where((c) => drive.channelForKey(c.key) != null).length;
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            tooltip: t('upload_files'),
            backgroundColor: C.accent,
            foregroundColor: C.onAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            onPressed: () => pickAndUpload(context, drive),
            child: Icon(Icons.add, size: 28),
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final cols = box.maxWidth > 900 ? 4 : (box.maxWidth > 600 ? 3 : 2);
              return ListView(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 110),
                children: [
                  Row(children: [
                    Text('TirsoDrive', style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, fontSize: 24)),
                    SizedBox(width: 10),
                    ConnectionDot(state: drive.connection),
                    Spacer(),
                    IconButton.outlined(
                      tooltip: t('search_title'),
                      style: IconButton.styleFrom(side: BorderSide(color: C.border), backgroundColor: C.surface, minimumSize: Size(44, 44)),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(drive: drive))),
                      icon: Icon(Icons.search),
                    ),
                    SizedBox(width: 10),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: C.surface2,
                      child: Text(drive.myName.isEmpty ? 'T' : drive.myName.characters.first.toUpperCase(),
                          style: TextStyle(color: C.text, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  SizedBox(height: 22),
                  SectionLabel(t('section_library')),
                  SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.75,
                    children: [
                      for (final c in libraryCategories)
                        _Tile(
                          tag: c.tag,
                          color: c.color,
                          title: c.label(appLang),
                          sub: drive.channelForKey(c.key) != null ? t('ready_channel') : t('not_created'),
                          onTap: () => _openKey(context, c.key),
                        ),
                      _Tile(
                        tag: 'ROM',
                        color: C.accent,
                        title: t('roms'),
                        sub: romCount > 0 ? '$romCount / ${romCategories.length}' : t('roms_sub'),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RomsScreen(drive: drive))),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (label, icon, color, page) in [
                      (t('favorites'), Icons.star_border, C.amber, () => FileListScreen(drive: drive, title: t('favorites'), files: () => drive.allFiles.where((f) => f.fav).toList(), empty: t('favorites_empty'))),
                      (t('collections'), Icons.collections_bookmark_outlined, C.accentSoft, () => CollectionsScreen(drive: drive)),
                      (t('duplicates'), Icons.content_copy_outlined, C.soft, () => DuplicatesScreen(drive: drive)),
                      (t('trash'), Icons.delete_outline, C.red, () => TrashScreen(drive: drive)),
                    ])
                      ActionChip(
                        avatar: Icon(icon, size: 18, color: color),
                        label: Text(label),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page())),
                      ),
                  ]),
                  SizedBox(height: 24),
                  Row(children: [
                    SectionLabel(t('section_mine')),
                    Spacer(),
                    TextButton.icon(onPressed: () => _newChannel(context), icon: Icon(Icons.add, size: 18), label: Text(t('new_channel'))),
                  ]),
                  for (final ch in mine)
                    _Row(
                      tag: 'TD',
                      title: ch.display,
                      sub: ch.title,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelScreen(drive: drive, chatId: ch.chatId))),
                    ),
                ],
              );
            }),
          ),
        );
      },
    );
  }
}

class RomsScreen extends StatelessWidget {
  final Drive drive;
  const RomsScreen({super.key, required this.drive});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) => Scaffold(
        appBar: AppBar(backgroundColor: C.bg, title: Text(t('section_roms'), style: TextStyle(fontFamily: displayFont))),
        body: ListView(
          padding: EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            for (final c in romCategories)
              _Row(
                tag: c.tag,
                title: c.label(appLang),
                sub: drive.channelForKey(c.key) != null ? c.channelTitle : t('not_created'),
                dim: drive.channelForKey(c.key) == null,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelScreen(drive: drive, categoryKey: c.key))),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String tag;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _Tile({required this.tag, required this.color, required this.title, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: C.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            ExtBadge(tag, color: color, size: 30),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.muted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String tag;
  final String title;
  final String sub;
  final bool dim;
  final VoidCallback onTap;
  const _Row({required this.tag, required this.title, required this.sub, required this.onTap, this.dim = false});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(children: [
          ExtBadge(tag, color: dim ? C.label : C.accent, size: 42),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: dim ? C.soft : C.text)),
              SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          Icon(Icons.chevron_right, color: C.label),
        ]),
      ),
    );
  }
}
