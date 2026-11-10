// The small status card shown when you click the TirsoDrive tray icon (like OneDrive's).
import 'package:flutter/material.dart';

import '../core/drive.dart';
import '../core/strings.dart';
import 'theme.dart';

class TrayCard extends StatelessWidget {
  final Drive drive;
  const TrayCard({super.key, required this.drive});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) {
        final d = drive;
        final open = d.transfers.where((x) => !x.finished).toList();
        final done = d.transfers.where((x) => x.finished && x.error == null).length;
        final running = open.where((x) => x.running).toList();
        final overall = d.uploadsTotal > 0 ? ((d.uploadsDone + (running.isNotEmpty ? running.first.fraction : 0)) / d.uploadsTotal).clamp(0.0, 1.0) : null;
        return Scaffold(
          backgroundColor: C.panel,
          body: SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(children: [
                  TdLogo(size: 26),
                  SizedBox(width: 10),
                  Text('TirsoDrive', style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, fontSize: 17)),
                  SizedBox(width: 10),
                  ConnectionDot(state: d.connection),
                  Spacer(),
                  IconButton(
                    tooltip: d.paused ? t('tray_resume') : t('tray_pause'),
                    onPressed: open.isEmpty ? null : d.togglePause,
                    icon: Icon(d.paused ? Icons.play_arrow : Icons.pause),
                  ),
                ]),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    open.isEmpty ? t('tray_uptodate') : (d.uploadsBlocked ?? (d.paused ? t('tr_paused') : t('tray_active', {'n': open.length}))),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  if (overall != null && open.isNotEmpty) ...[
                    SizedBox(height: 8),
                    ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: overall, minHeight: 6)),
                    SizedBox(height: 4),
                    Text(t('tr_uploading', {'i': (d.uploadsDone + 1).clamp(1, d.uploadsTotal), 'n': d.uploadsTotal}), style: TextStyle(color: C.muted, fontSize: 12)),
                  ],
                ]),
              ),
              SizedBox(height: 8),
              Divider(height: 1),
              Expanded(
                child: open.isEmpty
                    ? Center(child: Text(done > 0 ? t('tray_done_n', {'n': done}) : t('tray_idle'), style: TextStyle(color: C.muted, fontSize: 13)))
                    : ListView(padding: EdgeInsets.symmetric(vertical: 6), children: [
                        for (final tr in open.take(30))
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(tr.upload ? Icons.arrow_upward : Icons.arrow_downward, size: 15, color: C.accentSoft),
                                SizedBox(width: 8),
                                Expanded(child: Text(tr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13))),
                                if (tr.running) Text('${(tr.fraction * 100).round()}%', style: TextStyle(color: C.muted, fontSize: 12)),
                              ]),
                              if (tr.running) ...[
                                SizedBox(height: 5),
                                LinearProgressIndicator(value: tr.fraction, minHeight: 3),
                              ],
                            ]),
                          ),
                      ]),
              ),
              Divider(height: 1),
              Padding(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: Size(0, 42)),
                      onPressed: () => d.desktop?.showMain(),
                      child: Text(t('tray_open')),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
