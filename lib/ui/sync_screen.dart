import 'dart:io';

import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/strings.dart';
import '../core/sync.dart';
import 'theme.dart';

class SyncScreen extends StatelessWidget {
  final Drive drive;
  final bool embedded;
  const SyncScreen({super.key, required this.drive, this.embedded = false});

  Future<void> _add(BuildContext context) async {
    final picked = await drive.sync.pickFolder();
    if (picked == null || !context.mounted) return;
    final (folder, label) = picked;
    String dest = 'new';
    bool twoWay = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final options = <(String, String)>[
            ('new', t('sync_new_channel', {'n': label})),
            for (final c in allCategories) ('key:${c.key}', c.isRom ? 'ROMs · ${c.label(appLang)}' : c.label(appLang)),
            for (final ch in drive.customChannels) ('chat:${ch.chatId}', ch.display),
          ];
          return AlertDialog(
            title: Text(t('sync_add_title'), style: TextStyle(fontFamily: displayFont)),
            content: SizedBox(
              width: 460,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('sync_folder'), style: TextStyle(color: C.muted, fontSize: 12)),
                SizedBox(height: 4),
                Text(Platform.isAndroid ? label : folder, style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 16),
                Text(t('sync_to'), style: TextStyle(color: C.muted, fontSize: 12)),
                DropdownButton<String>(
                  value: dest,
                  isExpanded: true,
                  dropdownColor: C.surface2,
                  items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => set(() => dest = v!),
                ),
                SizedBox(height: 12),
                for (final (v, title, sub) in [
                  (false, t('sync_mode_backup'), t('sync_mode_backup_sub')),
                  (true, t('sync_mode_two'), t('sync_mode_two_sub')),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => set(() => twoWay = v),
                    leading: Icon(twoWay == v ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: twoWay == v ? C.accent : C.muted),
                    title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
                  ),
                SizedBox(height: 6),
                Text(t('sync_safety'), style: TextStyle(fontSize: 12, color: C.label, height: 1.4)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
              FilledButton(style: FilledButton.styleFrom(minimumSize: Size(96, 44)), onPressed: () => Navigator.pop(ctx, true), child: Text(t('sync_start'))),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    String? key;
    int? chatId;
    if (dest == 'new') {
      final err = await drive.createCustomChannel(label);
      final title = '$channelPrefix$label'.toLowerCase();
      final ch = drive.channels.where((c) => c.title.toLowerCase() == title);
      if (ch.isEmpty) {
        if (context.mounted) snack(context, err ?? t('err_generic', {'e': '?'}));
        return;
      }
      chatId = ch.first.chatId;
    } else if (dest.startsWith('key:')) {
      key = dest.substring(4);
    } else {
      chatId = int.parse(dest.substring(5));
    }
    await drive.sync.add(SyncPair(
      id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      folder: folder,
      label: label,
      key: key,
      chatId: chatId,
      twoWay: twoWay,
    ));
  }

  String _dest(SyncPair p) {
    if (p.chatId != null) return drive.channelById(p.chatId!)?.title ?? '';
    return categoryByKey(p.key ?? '')?.channelTitle ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) {
        final pairs = drive.sync.pairs;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: C.bg,
            automaticallyImplyLeading: !embedded,
            titleSpacing: embedded ? 24 : 0,
            title: Text(t('sync_title'), style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w600, fontSize: 20)),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: C.accent,
            foregroundColor: C.onAccent,
            onPressed: () => _add(context),
            icon: Icon(Icons.add),
            label: Text(t('sync_add'), style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              Text(t('sync_intro'), style: TextStyle(color: C.muted, fontSize: 13, height: 1.45)),
              SizedBox(height: 16),
              if (pairs.isEmpty)
                Panel(
                  padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  child: Column(children: [
                    Icon(Icons.sync, size: 34, color: C.label),
                    SizedBox(height: 10),
                    Text(t('sync_empty'), style: TextStyle(fontFamily: displayFont, fontSize: 18)),
                  ]),
                ),
              for (final p in pairs)
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(p.twoWay ? Icons.sync : Icons.backup_outlined, color: C.accentSoft),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            Text('→ ${_dest(p)} · ${p.twoWay ? t('sync_mode_two') : t('sync_mode_backup')}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                          ]),
                        ),
                        if (p.running) SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
                      ]),
                      SizedBox(height: 10),
                      Text(p.status.isEmpty ? t('sync_never') : p.status, style: TextStyle(fontSize: 13, color: C.soft, height: 1.4)),
                      if (p.lastRun > 0)
                        Text(t('sync_last', {'d': formatDate(p.lastRun)}), style: TextStyle(fontSize: 12, color: C.label)),
                      SizedBox(height: 10),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: p.running ? null : () => drive.sync.run(p),
                          icon: Icon(Icons.sync, size: 18),
                          label: Text(t('sync_now')),
                        ),
                        Spacer(),
                        TextButton(
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(t('sync_remove_q'), style: TextStyle(fontFamily: displayFont)),
                                content: Text(t('sync_remove_body'), style: TextStyle(color: C.soft, height: 1.4)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('sync_remove'))),
                                ],
                              ),
                            );
                            if (yes == true) await drive.sync.remove(p);
                          },
                          child: Text(t('sync_remove'), style: TextStyle(color: C.red)),
                        ),
                      ]),
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
