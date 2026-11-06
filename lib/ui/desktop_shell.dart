// Windows / wide-screen layout: sidebar + content + upload bar (matches the design canvas).
import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/native.dart';
import '../core/strings.dart';
import 'channel_screen.dart';
import 'library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'theme.dart';
import 'transfers_screen.dart';
import 'upload_review.dart';

class DesktopShell extends StatefulWidget {
  final Drive drive;
  const DesktopShell({super.key, required this.drive});
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  // 'cat:<key>', 'chat:<id>', 'transfers', 'settings'
  String _sel = 'cat:videos';
  bool _dragging = false;
  bool _showAllRoms = false;
  StreamSubscription<String>? _sub;

  Drive get d => widget.drive;

  @override
  void initState() {
    super.initState();
    _sub = d.messages.listen((m) {
      if (mounted) snack(context, m);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String? get _selKey => _sel.startsWith('cat:') ? _sel.substring(4) : null;
  int? get _selChat => _sel.startsWith('chat:') ? int.parse(_sel.substring(5)) : null;

  Future<void> _onDrop(DropDoneDetails detail) async {
    setState(() => _dragging = false);
    final files = await expandPaths(detail.files.map((f) => f.path));
    if (!mounted || files.isEmpty) return;
    // Dropped on a channel: straight into that channel. Otherwise: auto-sort review.
    await uploadFiles(context, d, files, fixedKey: _selKey, fixedChatId: _selChat);
  }

  Widget _navItem(String id, String label, Color dot, {String? trailing}) {
    final on = _sel == id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: on ? const Color(0xFF1E2A44) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() => _sel = id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? Colors.white : C.soft)),
              ),
              if (trailing != null) Text(trailing, style: const TextStyle(fontSize: 12, color: C.label)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 6), child: SectionLabel(s));

  Widget _sidebar() {
    final roms = romCategories.where((c) => _showAllRoms || d.channelForKey(c.key) != null).toList();
    final active = d.transfers.where((x) => !x.finished).length;
    return Container(
      width: 264,
      decoration: const BoxDecoration(color: C.panel, border: Border(right: BorderSide(color: C.divider))),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [
          _navItem('search', t('search_title'), C.accentSoft),
          _label(t('section_library')),
          for (final c in libraryCategories) _navItem('cat:${c.key}', c.label(appLang), c.color),
          Row(children: [
            Expanded(child: _label(t('section_roms'))),
            TextButton(
              onPressed: () => setState(() => _showAllRoms = !_showAllRoms),
              child: Text(_showAllRoms ? '−' : '+', style: const TextStyle(fontSize: 16)),
            ),
          ]),
          if (roms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(t('roms_sub'), style: const TextStyle(fontSize: 12, color: C.label)),
            ),
          for (final c in roms) _navItem('cat:${c.key}', c.label(appLang), C.accent),
          Row(children: [
            Expanded(child: _label(t('section_mine'))),
            IconButton(tooltip: t('new_channel'), onPressed: () => showNewChannelDialog(context, d), icon: const Icon(Icons.add, size: 18, color: C.accentSoft)),
          ]),
          for (final ch in d.customChannels) _navItem('chat:${ch.chatId}', ch.display, C.label),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 8),
          _navItem('sync', t('sync_title'), C.green, trailing: d.sync.pairs.isEmpty ? null : '${d.sync.pairs.length}'),
          _navItem('transfers', t('nav_transfers'), C.accentSoft, trailing: active > 0 ? '$active' : null),
          _navItem('settings', t('nav_settings'), C.label),
        ],
      ),
    );
  }

  Widget _header() {
    final online = d.connection == 'connectionStateReady';
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(color: C.panel, border: Border(bottom: BorderSide(color: C.divider))),
      child: Row(children: [
        const TdLogo(size: 32),
        const SizedBox(width: 10),
        const Text('TirsoDrive', style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, fontSize: 19)),
        const SizedBox(width: 24),
        Container(width: 8, height: 8, decoration: BoxDecoration(color: online ? C.green : C.amber, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(online ? t('status_online') : t('status_connecting'), style: const TextStyle(fontSize: 13, color: C.muted)),
        const SizedBox(width: 24),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: C.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: C.border)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _sel = 'search'),
                  child: SizedBox(
                    height: 38,
                    child: Row(children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.search, size: 18, color: C.muted),
                      const SizedBox(width: 10),
                      Text(t('search_hint'), style: const TextStyle(color: C.muted, fontSize: 14)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        if (!Platform.isAndroid) ...[
          OutlinedButton.icon(
            onPressed: () => pickAndUpload(context, d, folder: true),
            icon: const Icon(Icons.drive_folder_upload_outlined, size: 18),
            label: Text(t('backup_folder')),
          ),
          const SizedBox(width: 10),
        ],
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed: () => pickAndUpload(context, d, fixedKey: _selKey, fixedChatId: _selChat),
          icon: const Icon(Icons.upload, size: 18),
          label: Text(t('upload_files'), style: const TextStyle(fontSize: 14)),
        ),
        const SizedBox(width: 14),
        LangSwitch(lang: d.lang, onChanged: d.setLang),
        const SizedBox(width: 12),
        CircleAvatar(
          radius: 18,
          backgroundColor: C.surface2,
          child: Text(d.myName.isEmpty ? 'T' : d.myName.characters.first.toUpperCase(), style: const TextStyle(color: C.text, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _footer() {
    final current = d.transfers.where((x) => x.running).toList();
    final queued = d.transfers.where((x) => x.status == TStatus.queued).length;
    if (current.isEmpty && queued == 0) return const SizedBox.shrink();
    final tr = current.isNotEmpty ? current.first : null;
    final finishing = tr != null && tr.upload && tr.size > 0 && tr.bytes >= tr.size;
    final title = tr == null
        ? t('tr_paused')
        : tr.upload
            ? '${t('tr_uploading', {'i': (d.uploadsDone + 1).clamp(1, d.uploadsTotal), 'n': d.uploadsTotal})} · ${tr.name}'
            : '${t('tr_downloading')} · ${tr.name}';
    final sub = tr == null
        ? ''
        : finishing
            ? t('tr_finishing')
            : tr.status == TStatus.active
                ? '${(tr.fraction * 100).round()}% · ${formatBytes(tr.speed)}/s'
                : (tr.status == TStatus.creating ? t('tr_creating') : t('tr_preparing'));
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: C.panel, border: Border(top: BorderSide(color: C.divider))),
      child: Row(children: [
        const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              const SizedBox(width: 10),
              Text(sub, style: const TextStyle(fontSize: 13, color: C.muted)),
            ]),
            const SizedBox(height: 7),
            Bar(tr != null && tr.status == TStatus.active && !finishing ? tr.fraction : 0, height: 6),
          ]),
        ),
        const SizedBox(width: 16),
        OutlinedButton(onPressed: d.togglePause, child: Text(d.paused ? t('tr_resume') : t('tr_pause'))),
        const SizedBox(width: 10),
        OutlinedButton(onPressed: () => setState(() => _sel = 'transfers'), child: Text('${t('nav_transfers')} ($queued)')),
      ]),
    );
  }

  Widget _content() {
    if (_sel == 'search') return SearchScreen(drive: d, embedded: true);
    if (_sel == 'sync') return SyncScreen(drive: d, embedded: true);
    if (_sel == 'transfers') return TransfersScreen(drive: d);
    if (_sel == 'settings') return SettingsScreen(drive: d);
    return ChannelScreen(key: ValueKey(_sel), drive: d, categoryKey: _selKey, chatId: _selChat, embedded: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => Scaffold(
        body: Column(children: [
          _header(),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _sidebar(),
              Expanded(
                child: DropTarget(
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: _onDrop,
                  child: Stack(children: [
                    Positioned.fill(child: _content()),
                    if (_dragging)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            margin: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: C.accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: C.accent, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: Text(t('drop_here'),
                                style: const TextStyle(fontFamily: displayFont, fontSize: 22, fontWeight: FontWeight.w600, color: C.accentSoft)),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          _footer(),
        ]),
      ),
    );
  }
}
