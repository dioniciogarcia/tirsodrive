import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/drive.dart';
import '../core/strings.dart';
import 'theme.dart';

class TransfersScreen extends StatelessWidget {
  final Drive drive;
  const TransfersScreen({super.key, required this.drive});

  String _dest(Transfer tr) {
    if (tr.chatId != null) return drive.channelById(tr.chatId!)?.title ?? '';
    if (tr.destChatId != null) return drive.channelById(tr.destChatId!)?.title ?? '';
    if (tr.destKey != null) return categoryByKey(tr.destKey!)?.channelTitle ?? '';
    return '';
  }

  String _status(Transfer tr) => switch (tr.status) {
        TStatus.creating => t('tr_creating'),
        TStatus.preparing => t('tr_preparing'),
        TStatus.waiting => t('tr_waiting', {'s': tr.waitSeconds}),
        TStatus.done => t('tr_done'),
        TStatus.failed => t('tr_failed'),
        TStatus.cancelled => t('tr_cancelled'),
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) {
        final current = drive.transfers.where((x) => x.running).toList();
        final next = drive.transfers.where((x) => x.status == TStatus.queued).toList();
        final done = drive.transfers.where((x) => x.finished).toList().reversed.toList();
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 30),
              children: [
                Row(children: [
                  Text(t('tr_title'), style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, fontSize: 24)),
                  Spacer(),
                  OutlinedButton(onPressed: drive.togglePause, child: Text(drive.paused ? t('tr_resume') : t('tr_pause'))),
                ]),
                SizedBox(height: 16),
                if (drive.paused)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Panel(color: C.amberBg, borderColor: C.amberBorder, child: Text(t('tr_paused'), style: TextStyle(color: C.amberText, fontWeight: FontWeight.w600))),
                  ),
                if (drive.uploadsBlocked != null && next.any((x) => x.upload))
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Panel(color: C.amberBg, borderColor: C.amberBorder, child: Text(drive.uploadsBlocked!, style: TextStyle(color: C.amberText, fontWeight: FontWeight.w600))),
                  ),
                if (current.isEmpty && next.isEmpty)
                  Panel(
                    padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                    child: Column(children: [
                      Icon(Icons.swap_vert, size: 34, color: C.label),
                      SizedBox(height: 10),
                      Text(t('tr_idle'), style: TextStyle(fontFamily: displayFont, fontSize: 18)),
                      SizedBox(height: 6),
                      Text(t('tr_idle_sub'), style: TextStyle(color: C.muted)),
                    ]),
                  ),
                for (final tr in current) ...[_currentCard(tr), SizedBox(height: 12)],
                Panel(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.format_list_numbered, size: 18, color: C.muted),
                    SizedBox(width: 10),
                    Expanded(child: Text(t('tr_one'), style: TextStyle(fontSize: 13, color: C.soft))),
                    Text(t('tr_on'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.green)),
                  ]),
                ),
                if (current.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(t('tr_keep_open'), style: TextStyle(fontSize: 12, color: C.label, height: 1.4)),
                  ),
                if (next.isNotEmpty) ...[
                  SizedBox(height: 22),
                  SectionLabel(t('tr_next', {'n': next.length})),
                  SizedBox(height: 4),
                  for (final (i, tr) in next.indexed)
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.divider))),
                      child: Row(children: [
                        SizedBox(width: 26, child: Text('${i + 1}', textAlign: TextAlign.right, style: TextStyle(color: C.label, fontSize: 13))),
                        SizedBox(width: 12),
                        Icon(tr.upload ? Icons.upload : Icons.download, size: 16, color: C.muted),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            Text('${tr.upload ? _dest(tr) : drive.channelName(tr.file!.chatId)} · ${formatBytes(tr.size)}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                          ]),
                        ),
                        IconButton(tooltip: t('tr_cancel'), onPressed: () => drive.cancel(tr), icon: Icon(Icons.close, size: 18, color: C.muted)),
                      ]),
                    ),
                ],
                if (done.isNotEmpty) ...[
                  SizedBox(height: 22),
                  Row(children: [
                    SectionLabel(t('tr_done')),
                    Spacer(),
                    TextButton(onPressed: drive.clearFinished, child: Text(t('tr_clear'))),
                  ]),
                  for (final tr in done)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(
                          tr.status == TStatus.done ? Icons.check : (tr.status == TStatus.failed ? Icons.error_outline : Icons.block),
                          size: 20,
                          color: tr.status == TStatus.done ? C.green : (tr.status == TStatus.failed ? C.red : C.label),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: C.soft)),
                            if (tr.status == TStatus.done && tr.verified)
                              Text(t('verified'), style: TextStyle(fontSize: 12, color: C.green)),
                            if (tr.status != TStatus.done)
                              Text(tr.error == null ? _status(tr) : '${_status(tr)} · ${tr.error}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                          ]),
                        ),
                        if (tr.status == TStatus.failed) TextButton(onPressed: () => drive.retry(tr), child: Text(t('tr_retry'))),
                      ]),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _currentCard(Transfer tr) {
    final idx = drive.uploadsDone + 1;
    final header = tr.upload ? t('tr_uploading', {'i': idx.clamp(1, drive.uploadsTotal), 'n': drive.uploadsTotal}) : t('tr_downloading');
    final active = tr.status == TStatus.active;
    final finishing = active && tr.upload && tr.size > 0 && tr.bytes >= tr.size;
    final left = tr.secondsLeft;
    return Panel(
      padding: EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(value: active && tr.fraction > 0 && !finishing ? tr.fraction : null, strokeWidth: 5),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(header.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: C.accentSoft)),
              SizedBox(height: 3),
              Text(tr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 2),
              Text(
                active
                    ? '${tr.upload ? '→ ${_dest(tr)}' : drive.channelName(tr.file!.chatId)} · ${formatBytes(tr.bytes)} / ${formatBytes(tr.size)}'
                    : _status(tr),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: C.muted),
              ),
            ]),
          ),
          IconButton(tooltip: t('tr_cancel'), onPressed: () => drive.cancel(tr), icon: Icon(Icons.close, color: C.muted)),
        ]),
        SizedBox(height: 14),
        Bar(active ? tr.fraction : 0, height: 8),
        SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(
              finishing ? t('tr_finishing') : (active ? '${(tr.fraction * 100).round()}% · ${formatBytes(tr.speed)}/s' : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: C.muted),
            ),
          ),
          if (active && !finishing && left != null) Text(t('left', {'t': formatDuration(left)}), style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      ]),
    );
  }
}
