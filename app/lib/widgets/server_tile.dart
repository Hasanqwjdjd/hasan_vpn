import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/aether_profile.dart';
import '../models/server.dart';
import '../services/app_colors.dart';

class ServerTile extends StatelessWidget {
  final VpnServer server;
  final bool selected;

  /// true اگر همین سرور الان متصل است (تیک سبز کنار نام).
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onTest; // تست پینگ تکی (صاعقه)

  const ServerTile({
    super.key,
    required this.server,
    required this.selected,
    required this.onTap,
    this.active = false,
    this.onDelete,
    this.onPin,
    this.onShare,
    this.onEdit,
    this.onTest,
  });

  String get _caption {
    if (server.isAether) {
      return 'AETHER · ${AetherProfile.fromLink(server.shareLink).summary}';
    }
    final name = server.protocol.name.toUpperCase();
    final host = server.host.trim();
    if (host.isEmpty || host == 'unknown') return name;
    return '$name · $host';
  }

  /// پینگ واقعی (HTTP از داخل تونل) بزرگ‌تر از TCP است چون شامل دست‌دادن
  /// TLS/WS و یک رفت‌وبرگشت کامل می‌شود؛ آستانه‌ها جدا هستند.
  Color _pingColor(BuildContext context) {
    final ping = server.ping;
    if (ping == null) return AppColors.muted2(context);

    final real = server.pingKind == PingKind.real;
    final good = real ? 700 : 150;
    final fair = real ? 1400 : 350;

    if (ping < good) return AppColors.accent;
    if (ping < fair) return AppColors.warn;
    return AppColors.danger;
  }

  Widget _buildPing(BuildContext context) {
    if (server.status == ServerStatus.testing) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accent,
        ),
      );
    }

    final ping = server.ping;
    final isTcp = server.pingKind == PingKind.tcp;

    if (ping != null) {
      // «~» یعنی فقط زمان رسیدن TCP به سرور (تقریبی)؛ بدون آن = پینگ واقعی.
      return Tooltip(
        message: isTcp ? 'TCP' : 'Real',
        child: Text(
          '${isTcp ? '~' : ''}$ping ms',
          style: TextStyle(
            color: _pingColor(context),
            fontSize: 12,
            fontWeight: isTcp ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
      );
    }

    final String text;
    final Color color;
    switch (server.status) {
      case ServerStatus.offline:
        text = '✕';
        color = AppColors.danger;
        break;
      case ServerStatus.unknown:
        text = '?';
        color = AppColors.muted(context);
        break;
      default:
        text = '---';
        color = AppColors.muted2(context);
    }

    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    double size = 16,
  }) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28),
      iconSize: size,
      icon: Icon(icon, color: color, size: size),
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.elevated(context)
            : AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.border(context),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                if (onPin != null)
                  _iconButton(
                    icon: server.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    color: server.isPinned
                        ? AppColors.accent
                        : AppColors.muted2(context),
                    onPressed: onPin,
                    size: 18,
                  ),

                Text(server.flag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              server.name,
                              style: TextStyle(
                                color: AppColors.fg(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.accent,
                              size: 14,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _caption,
                        style: TextStyle(
                          color: AppColors.muted2(context),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),
                _buildPing(context),

                _iconButton(
                  icon: Icons.copy,
                  color: AppColors.accent,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: server.shareLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('لینک کپی شد'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),

                // صاعقه: تست تکی
                if (onTest != null)
                  _iconButton(
                    icon: Icons.bolt,
                    color: AppColors.warn,
                    onPressed:
                        server.status == ServerStatus.testing ? null : onTest,
                  ),

                if (onShare != null)
                  _iconButton(
                    icon: Icons.share_outlined,
                    color: AppColors.muted(context),
                    onPressed: onShare,
                  ),

                if (onEdit != null)
                  _iconButton(
                    icon: Icons.edit_outlined,
                    color: AppColors.muted(context),
                    onPressed: onEdit,
                  ),

                if (onDelete != null)
                  _iconButton(
                    icon: Icons.delete_outline,
                    color: AppColors.danger,
                    onPressed: onDelete,
                  )
                else
                  const SizedBox(width: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
