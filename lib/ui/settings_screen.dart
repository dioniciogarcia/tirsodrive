import 'package:flutter/material.dart';

import '../core/drive.dart';
import '../core/strings.dart';
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
                Panel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.sync, color: C.accentSoft),
                    title: Text(t('sync_title'), style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(t('sync_pairs_n', {'n': drive.sync.pairs.length}), style: TextStyle(color: C.muted, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyncScreen(drive: drive))),
                  ),
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
