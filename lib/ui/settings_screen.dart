import 'dart:io';

import 'package:flutter/material.dart';

import '../core/desktop.dart';
import '../core/drive.dart';
import '../core/strings.dart';
import '../core/webdav.dart';
import 'lock_screen.dart';
import 'programs_screen.dart';
import 'sync_screen.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  final Drive drive;
  const SettingsScreen({super.key, required this.drive});

  static const int _gb2 = 2000 * 1024 * 1024;
  static const int _gb4 = 4000 * 1024 * 1024;

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: TextStyle(fontFamily: displayFont)),
        content: Text(body, style: TextStyle(color: C.soft, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: Size(96, 44)), onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _vaultDialog(BuildContext context) async {
    final a = TextEditingController();
    final b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('enc_set'), style: TextStyle(fontFamily: displayFont)),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('enc_warning'), style: TextStyle(color: C.amberText, fontSize: 13, height: 1.4)),
            SizedBox(height: 12),
            TextField(controller: a, obscureText: true, decoration: InputDecoration(labelText: t('enc_pw'))),
            SizedBox(height: 10),
            TextField(controller: b, obscureText: true, decoration: InputDecoration(labelText: t('enc_pw2'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: Size(96, 44)),
            onPressed: () {
              if (a.text.length < 8 || a.text != b.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t('enc_pw_bad'))));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text(t('verify')),
          ),
        ],
      ),
    );
    if (ok == true) await drive.setVaultPassword(a.text);
  }

  Future<void> _pickFavorites(BuildContext context) async {
    final chats = drive.shareChats().where((c) => c.chatId != drive.myId).toList();
    final chosen = {for (final e in drive.watchFavorites) e.$1: e.$2};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(t('watch_favs'), style: TextStyle(fontFamily: displayFont)),
          content: SizedBox(
            width: 420,
            height: 420,
            child: ListView(children: [
              Text(t('watch_favs_help'), style: TextStyle(color: C.muted, fontSize: 12)),
              for (final c in chats.take(80))
                CheckboxListTile(
                  dense: true,
                  value: chosen.containsKey(c.chatId),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onChanged: (v) => setS(() {
                    if (v == true) {
                      if (chosen.length < 6) chosen[c.chatId] = c.title;
                    } else {
                      chosen.remove(c.chatId);
                    }
                  }),
                ),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('done')))],
        ),
      ),
    );
    drive.setWatchFavorites([for (final e in chosen.entries) (e.key, e.value)]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) {
        Widget radio(String label, int value) => ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => drive.setMaxBytes(value),
              leading: Icon(drive.maxBytes == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: drive.maxBytes == value ? C.accent : C.muted),
              title: Text(label, style: TextStyle(fontSize: 14)),
            );
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 30),
              children: [
                Text(t('settings_title'), style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, fontSize: 24)),
                SizedBox(height: 20),
                SectionLabel(t('set_language')),
                SizedBox(height: 10),
                Row(children: [LangSwitch(lang: drive.lang, onChanged: drive.setLang), SizedBox(width: 12), Text(drive.lang == 'es' ? 'Español' : 'English')]),
                SizedBox(height: 24),
                SectionLabel(t('set_theme')),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  for (final (m, label, icon) in [
                    ('light', t('theme_light'), Icons.light_mode_outlined),
                    ('dark', t('theme_dark'), Icons.dark_mode_outlined),
                    ('system', t('theme_system'), Icons.brightness_auto_outlined),
                  ])
                    ChoiceChip(
                      selected: drive.themeMode == m,
                      onSelected: (_) => drive.setTheme(m),
                      avatar: Icon(icon, size: 18),
                      label: Text(label),
                    ),
                ]),
                SizedBox(height: 24),
                SectionLabel(t('set_limit')),
                radio(t('set_limit_free'), _gb2),
                radio(t('set_limit_premium'), _gb4),
                SizedBox(height: 16),
                SectionLabel(t('sync_title')),
                SizedBox(height: 10),
                Material(
                  color: C.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: C.border)),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(Icons.sync, color: C.accentSoft),
                    title: Text(t('sync_title'), style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(t('sync_pairs_n', {'n': drive.sync.pairs.length}), style: TextStyle(color: C.muted, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyncScreen(drive: drive))),
                  ),
                ),
                SizedBox(height: 24),
                SectionLabel(t('rules_title')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: drive.ruleWifi,
                  onChanged: (v) => drive.setRules(wifi: v),
                  title: Text(t('rule_wifi'), style: TextStyle(fontSize: 14)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: drive.ruleCharging,
                  onChanged: (v) => drive.setRules(charging: v),
                  title: Text(t('rule_charging'), style: TextStyle(fontSize: 14)),
                ),
                Row(children: [
                  Expanded(child: Text(t('rule_quiet'), style: TextStyle(fontSize: 14))),
                  DropdownButton<int>(
                    value: drive.quietFrom,
                    dropdownColor: C.surface2,
                    items: [DropdownMenuItem(value: -1, child: Text(t('off'))), for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('$h:00'))],
                    onChanged: (v) => drive.setRules(from: v, to: v == -1 ? -1 : (drive.quietTo < 0 ? (v! + 9) % 24 : drive.quietTo)),
                  ),
                  if (drive.quietFrom >= 0) ...[
                    Text('  →  '),
                    DropdownButton<int>(
                      value: drive.quietTo < 0 ? 0 : drive.quietTo,
                      dropdownColor: C.surface2,
                      items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('$h:00'))],
                      onChanged: (v) => drive.setRules(to: v),
                    ),
                  ],
                ]),
                SizedBox(height: 24),
                SectionLabel(t('prog_title')),
                SizedBox(height: 10),
                Material(
                  color: C.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: C.border)),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(Icons.smart_toy_outlined, color: C.accentSoft),
                    title: Text(t('prog_title'), style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(drive.programs.list.isEmpty ? t('prog_none') : drive.programs.list.map((p) => p.name).join(', '), style: TextStyle(color: C.muted, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgramsScreen(drive: drive))),
                  ),
                ),
                SizedBox(height: 24),
                SectionLabel(t('enc_title')),
                SizedBox(height: 6),
                Text(t('enc_intro'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.4)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: drive.vaultKey != null,
                  onChanged: (on) => on ? _vaultDialog(context) : drive.setVaultPassword(null),
                  title: Text(t('enc_switch'), style: TextStyle(fontSize: 14)),
                  subtitle: Text(drive.vaultKey != null ? t('enc_on') : t('enc_off'), style: TextStyle(color: C.muted, fontSize: 12)),
                ),
                SizedBox(height: 24),
                if (Platform.isWindows) ...[
                  SectionLabel(t('drive_title')),
                  SizedBox(height: 6),
                  Text(t('drive_intro'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.4)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: drive.driveLetter,
                    onChanged: drive.setDriveLetter,
                    title: Text(t('drive_switch'), style: TextStyle(fontSize: 14)),
                    subtitle: Text(drive.webdav.status.isEmpty ? t('drive_off') : drive.webdav.status, style: TextStyle(color: C.muted, fontSize: 12)),
                  ),
                  if (drive.driveLetter)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: WebDavDrive.allowBigFiles,
                        icon: Icon(Icons.admin_panel_settings_outlined, size: 18),
                        label: Text(t('drive_bigfiles')),
                      ),
                    ),
                  SizedBox(height: 24),
                ],
                if (Platform.isAndroid && !drive.isTv) ...[
                  SectionLabel(t('watch_title')),
                  SizedBox(height: 6),
                  Text(t('watch_intro'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.4)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: drive.watchSupport,
                    onChanged: drive.setWatchSupport,
                    title: Text(t('watch_switch'), style: TextStyle(fontSize: 14)),
                    subtitle: Text(t('watch_switch_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.star_outline, color: C.amber),
                    title: Text(t('watch_favs'), style: TextStyle(fontSize: 14)),
                    subtitle: Text(drive.watchFavorites.isEmpty ? t('watch_favs_none') : drive.watchFavorites.map((e) => e.$2).join(', '),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => _pickFavorites(context),
                  ),
                  SizedBox(height: 8),
                  Text(t('picker_note'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.4)),
                  SizedBox(height: 24),
                ],
                if (drive.desktop != null) ...[
                  SectionLabel(t('win_title')),
                  const _AutostartSwitch(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: drive.keepInTray,
                    onChanged: drive.setKeepInTray,
                    title: Text(t('win_tray'), style: TextStyle(fontSize: 14)),
                    subtitle: Text(t('win_tray_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
                  ),
                  SizedBox(height: 24),
                ],
                SectionLabel(t('lock_title_set')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: drive.lockEnabled,
                  onChanged: (_) => lockSettingsDialog(context, drive),
                  title: Text(t('lock_switch'), style: TextStyle(fontSize: 14)),
                  subtitle: Text(drive.lockEnabled ? (drive.lockBio ? t('lock_on_bio') : t('lock_on')) : t('lock_off'), style: TextStyle(color: C.muted, fontSize: 12)),
                ),
                SizedBox(height: 24),
                SectionLabel(t('set_account')),
                SizedBox(height: 10),
                Panel(
                  child: Row(children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: C.surface2,
                      child: Text(drive.myName.isEmpty ? 'T' : drive.myName.characters.first.toUpperCase(), style: TextStyle(color: C.text)),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(drive.myName, style: TextStyle(fontWeight: FontWeight.w600)),
                        if (drive.myPhone.isNotEmpty) Text('+${drive.myPhone}', style: TextStyle(color: C.muted, fontSize: 13)),
                      ]),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        if (await _confirm(context, t('logout_q'), t('logout_body'), t('logout'))) drive.logOut();
                      },
                      child: Text(t('logout')),
                    ),
                  ]),
                ),
                if (!drive.usesBuiltInApi) ...[
                  SizedBox(height: 24),
                  SectionLabel(t('set_api')),
                  SizedBox(height: 10),
                  Panel(
                    child: Row(children: [
                      Expanded(child: Text('API ID ${drive.apiId}', style: TextStyle(color: C.soft))),
                      TextButton(
                        onPressed: () async {
                          if (await _confirm(context, t('set_api_change'), t('set_api_change_body'), t('verify'))) drive.changeApi();
                        },
                        child: Text(t('set_api_change')),
                      ),
                    ]),
                  ),
                ],
                SizedBox(height: 24),
                Text('TirsoDrive · ${t('version')} $appVersion', style: TextStyle(color: C.label, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Start with Windows" switch; keeps its own state because the setting lives in the Windows registry.
class _AutostartSwitch extends StatefulWidget {
  const _AutostartSwitch();
  @override
  State<_AutostartSwitch> createState() => _AutostartSwitchState();
}

class _AutostartSwitchState extends State<_AutostartSwitch> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    DesktopHost.autostartEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _on,
      onChanged: (v) async {
        setState(() => _on = v);
        final err = await DesktopHost.setAutostart(v);
        if (err != null && context.mounted) {
          setState(() => _on = !v);
          snack(context, err.isEmpty ? t('win_autostart_fail') : err);
        }
      },
      title: Text(t('win_autostart'), style: TextStyle(fontSize: 14)),
      subtitle: Text(t('win_autostart_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
    );
  }
}
