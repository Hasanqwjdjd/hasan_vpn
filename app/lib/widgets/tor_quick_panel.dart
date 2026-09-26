import 'package:flutter/material.dart';
import '../services/app_colors.dart';
import '../services/tor_session_service.dart';

/// پنل کوچک inline برای اتصال سریع Tor از داخل صفحهٔ «افزودن کانفیگ».
class TorQuickPanel extends StatefulWidget {
  final String language;
  final String panelId;
  const TorQuickPanel({
    super.key,
    required this.language,
    this.panelId = 'inline_tor_panel',
  });

  @override
  State<TorQuickPanel> createState() => _TorQuickPanelState();
}

class _TorQuickPanelState extends State<TorQuickPanel> {
  static const List<Map<String, String>> _bridgeTypes = [
    {'id': 'vanilla', 'fa': 'Tor ساده (بدون پل)', 'en': 'Vanilla'},
    {'id': 'webtunnel', 'fa': 'WebTunnel', 'en': 'WebTunnel'},
    {'id': 'snowflake', 'fa': 'Snowflake (P2P)', 'en': 'Snowflake'},
    {'id': 'meek_lite', 'fa': 'Meek / Azure', 'en': 'Meek'},
    {'id': 'obfs4', 'fa': 'obfs4', 'en': 'obfs4'},
  ];

  String _type = 'vanilla';

  String _t(String fa, String en) => widget.language == 'fa' ? fa : en;

  @override
  Widget build(BuildContext context) {
    final notifier = TorSessionService.instance.notifierFor(widget.panelId);
    return ValueListenableBuilder<TorSessionState>(
      valueListenable: notifier,
      builder: (context, st, _) {
        final running = st.running || st.routingThroughVpn;
        final busy = st.connecting ||
            (st.running && st.bootstrap > 0 && st.bootstrap < 100);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🧅', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t('شبکهٔ رسمی Tor', 'Official Tor Network'),
                      style: TextStyle(
                        color: AppColors.fg(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'اتصال واقعی از طریق libtor با پل‌های رایگان.',
                  'Real connection via libtor with free bridges.',
                ),
                style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.bg(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _type,
                    isExpanded: true,
                    dropdownColor: AppColors.elevated(context),
                    style: TextStyle(
                      color: AppColors.fg(context),
                      fontSize: 13,
                    ),
                    items: [
                      for (final bt in _bridgeTypes)
                        DropdownMenuItem<String>(
                          value: bt['id'],
                          child: Text(widget.language == 'fa'
                              ? bt['fa']!
                              : bt['en']!),
                        ),
                    ],
                    onChanged: (running || busy)
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _type = v);
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (busy) ...[
                LinearProgressIndicator(
                  value: st.bootstrap > 0 ? st.bootstrap / 100 : null,
                  color: AppColors.accent,
                  backgroundColor: AppColors.border(context),
                ),
                const SizedBox(height: 6),
                Text(
                  '${st.bootstrap}%${st.bootstrapMsg.isNotEmpty ? " · ${st.bootstrapMsg}" : ""}',
                  style: TextStyle(
                    color: AppColors.muted2(context),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          if (running) {
                            await TorSessionService.instance.disconnect();
                          } else {
                            await TorSessionService.instance
                                .connectWithType(widget.panelId, _type);
                          }
                        },
                  icon: Icon(
                    running ? Icons.stop : Icons.power_settings_new,
                    size: 18,
                  ),
                  label: Text(
                    running
                        ? _t('قطع Tor', 'Stop Tor')
                        : _t('اتصال Tor', 'Connect Tor'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        running ? AppColors.danger : AppColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (st.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  st.error!,
                  style: TextStyle(color: AppColors.danger, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
