// The "Updates" block of Settings (all platforms). Buttons are plain Material buttons, so a TV remote's D-pad reaches each one;
// on a TV the text is larger. Part of the update kit (see lib/core/updater.dart).
import 'package:flutter/material.dart';

import '../core/drive.dart';
import '../core/strings.dart';
import '../core/updater.dart';
import 'theme.dart';

class UpdateSection extends StatelessWidget {
  final Drive drive;
  const UpdateSection({super.key, required this.drive});

  Future<void> _update(BuildContext context) async {
    final u = drive.updater;
    if (u.transfersRunning()) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('upd_busy_title')),
          content: Text(t('upd_busy_body')),
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: Text(t('upd_wait'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('upd_anyway'))),
          ],
        ),
      );
      if (go != true) return;
    }
    await u.install();
  }

  @override
  Widget build(BuildContext context) {
    final u = drive.updater;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final tv = drive.isTv;
        final big = tv ? 17.0 : 13.0;
        String status;
        switch (u.state) {
          case UpdState.checking:
            status = t('upd_checking');
            break;
          case UpdState.upToDate:
            status = t('upd_uptodate');
            break;
          case UpdState.available:
            status = t('upd_available', {'v': u.latest});
            break;
          case UpdState.downloading:
            status = t('upd_downloading', {'p': (u.progress * 100).round()});
            break;
          case UpdState.installing:
            status = t('upd_installing');
            break;
          case UpdState.needsPermission:
            status = t('upd_perm');
            break;
          case UpdState.error:
            status = t('upd_err', {'e': u.error});
            break;
          case UpdState.idle:
            status = '';
            break;
        }
        final canUpdate = (u.state == UpdState.available || u.state == UpdState.needsPermission) && u.latest.isNotEmpty;
        final shape = ButtonStyle(
          textStyle: WidgetStatePropertyAll(TextStyle(fontSize: tv ? 18 : 14, fontWeight: FontWeight.w600)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: tv ? 24 : 16, vertical: tv ? 16 : 12)),
        );
        if (!u.supported) {
          return Text(t('upd_unsupported'), style: TextStyle(color: C.muted, fontSize: big));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${t('upd_installed')}: ', style: TextStyle(color: C.muted, fontSize: big)),
            Text(u.installed, style: TextStyle(color: C.strong, fontSize: big, fontWeight: FontWeight.w600)),
          ]),
          SizedBox(height: 4),
          Row(children: [
            Text('${t('upd_latest')}: ', style: TextStyle(color: C.muted, fontSize: big)),
            Text(u.latest.isEmpty ? '—' : u.latest, style: TextStyle(color: canUpdate ? C.green : C.strong, fontSize: big, fontWeight: FontWeight.w600)),
          ]),
          if (status.isNotEmpty) ...[
            SizedBox(height: 8),
            Text(status, style: TextStyle(color: u.state == UpdState.error ? C.red : C.soft, fontSize: big, height: 1.35)),
          ],
          if (u.state == UpdState.downloading) ...[
            SizedBox(height: 8),
            LinearProgressIndicator(value: u.progress <= 0 ? null : u.progress, minHeight: tv ? 8 : 5),
          ],
          SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
              style: shape,
              onPressed: u.busy ? null : () => u.check(),
              icon: Icon(Icons.refresh),
              label: Text(t('upd_check')),
            ),
            FilledButton.icon(
              style: shape,
              onPressed: canUpdate && !u.busy ? () => _update(context) : null,
              icon: Icon(Icons.system_update),
              label: Text(t('upd_now')),
            ),
            TextButton.icon(
              style: shape,
              onPressed: u.openReleases,
              icon: Icon(Icons.open_in_new),
              label: Text(t('upd_releases')),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: u.autoCheck,
            onChanged: u.setAuto,
            title: Text(t('upd_auto'), style: TextStyle(fontSize: tv ? 18 : 14)),
          ),
          if (u.notes.isNotEmpty && u.latest.isNotEmpty) ...[
            SizedBox(height: 4),
            Text(t('upd_notes'), style: TextStyle(color: C.label, fontSize: big, fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: BoxConstraints(maxHeight: tv ? 260 : 200),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
              child: SingleChildScrollView(child: Text(u.notes, style: TextStyle(color: C.soft, fontSize: tv ? 15 : 12, height: 1.4))),
            ),
          ],
        ]);
      },
    );
  }
}
