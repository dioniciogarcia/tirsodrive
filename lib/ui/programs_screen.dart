import 'package:flutter/material.dart';

import '../core/drive.dart';
import '../core/strings.dart';
import 'theme.dart';

/// Connected programs (Tirso Compiler): each one has its own bot that can only post to its own channels.
class ProgramsScreen extends StatelessWidget {
  final Drive drive;
  final bool embedded;
  const ProgramsScreen({super.key, required this.drive, this.embedded = false});

  Future<void> _connect(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('prog_connect_title'), style: TextStyle(fontFamily: displayFont)),
        content: SizedBox(width: 440, child: Text(t('prog_connect_body'), style: TextStyle(color: C.soft, height: 1.45))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: Size(96, 44)), onPressed: () => Navigator.pop(ctx, true), child: Text(t('prog_connect'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final where = await drive.programs.connectTirso();
      if (context.mounted && where != null) snack(context, t('prog_done', {'p': where}));
    } catch (e) {
      if (context.mounted) snack(context, t('err_generic', {'e': e.toString().replaceFirst('Exception: ', '')}));
    }
  }

  Future<void> _connectOther(BuildContext context) async {
    final name = TextEditingController();
    final chans = TextEditingController();
    var isolate = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(t('prog_other_title'), style: TextStyle(fontFamily: displayFont)),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('prog_other_body'), style: TextStyle(color: C.soft, height: 1.45, fontSize: 13)),
              SizedBox(height: 12),
              TextField(controller: name, decoration: InputDecoration(labelText: t('prog_name'))),
              SizedBox(height: 10),
              TextField(controller: chans, decoration: InputDecoration(labelText: t('prog_chans'), helperText: t('prog_chans_help'))),
              SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isolate,
                onChanged: (v) => setS(() => isolate = v),
                title: Text(t('prog_isolate'), style: TextStyle(fontSize: 14)),
                subtitle: Text(t('prog_isolate_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
            FilledButton(style: FilledButton.styleFrom(minimumSize: Size(96, 44)), onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty), child: Text(t('prog_connect'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final pname = name.text.trim();
    final names = chans.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final map = names.isEmpty ? {pname: 'TD - $pname'} : {for (final n in names) n: names.length == 1 ? 'TD - $pname - $n' : 'TD - $pname - $n'};
    try {
      final where = await drive.programs.connectProgram(pname, map, isolated: isolate);
      if (context.mounted && where != null) snack(context, t('prog_done', {'p': where}));
    } catch (e) {
      if (context.mounted) snack(context, t('err_generic', {'e': e.toString().replaceFirst('Exception: ', '')}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) {
        final p = drive.programs;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: C.bg,
            automaticallyImplyLeading: !embedded,
            titleSpacing: embedded ? 24 : 0,
            title: Text(t('prog_title'), style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w600, fontSize: 20)),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Text(t('prog_intro'), style: TextStyle(color: C.muted, fontSize: 13, height: 1.45)),
              SizedBox(height: 16),
              if (p.busy)
                Panel(
                  child: Row(children: [
                    SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    SizedBox(width: 12),
                    Expanded(child: Text(p.progress)),
                  ]),
                ),
              for (final prog in p.list)
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.smart_toy_outlined, color: C.accentSoft),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(prog.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            Text('@${prog.botUsername}${prog.isolated ? '  ·  🔒 ${t('prog_separate')}' : ''}', style: TextStyle(color: C.muted, fontSize: 12)),
                          ]),
                        ),
                      ]),
                      SizedBox(height: 10),
                      Text(t('prog_channels'), style: TextStyle(color: C.muted, fontSize: 12)),
                      SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 6, children: [for (final c in prog.channels.keys) Chip(label: Text(prog.isolated ? c : 'TD - $c APKs', style: TextStyle(fontSize: 12)))]),
                      SizedBox(height: 10),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final where = await p.exportConfig(prog);
                            if (context.mounted) snack(context, t('saved_to', {'p': where}));
                          },
                          icon: Icon(Icons.file_download_outlined, size: 18),
                          label: Text(t('prog_export')),
                        ),
                        Spacer(),
                        TextButton(onPressed: () => p.disconnect(prog), child: Text(t('prog_disconnect'), style: TextStyle(color: C.red))),
                      ]),
                    ]),
                  ),
                ),
              if (!p.busy && !p.list.any((x) => x.name == 'Tirso Compiler'))
                FilledButton.icon(onPressed: () => _connect(context), icon: Icon(Icons.link), label: Text(t('prog_connect_tirso'))),
              if (!p.busy) ...[
                SizedBox(height: 10),
                OutlinedButton.icon(onPressed: () => _connectOther(context), icon: Icon(Icons.add_link), label: Text(t('prog_connect_other'))),
              ],
              SizedBox(height: 16),
              Text(t('prog_note'), style: TextStyle(color: C.label, fontSize: 12, height: 1.4)),
            ],
          ),
        );
      },
    );
  }
}

