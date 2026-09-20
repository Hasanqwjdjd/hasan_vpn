import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/aether_profile.dart';
import '../models/server.dart';
import '../services/app_colors.dart';

class ServerTile extends StatelessWidget {
  final VpnServer server;
  final bool selected;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onTest;

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
    final proto = server.protocol.name.toUpperCase();
    final host = server.host.trim();
    if (host.isEmpty || host == 'unknown') return proto;
    return '$proto · $host';
  }

  /// پینگ واقعی (HTTP از داخل تونل).
  /// good = زیر ۷۰۰ms، fair = زیر ۱۴۰۰ms، بدتر = قرمز.
  Color _pingColor(BuildContext context) {
    final ping = server.ping;
    if (ping == null) return AppColors.muted2(context);

    if (ping < 700) return AppColors.accent;
    if (ping < 1400) return AppColors.warn;
    return AppColors.danger;
  }

  Widget _buildPing(BuildContext context) {
    final ping = server.ping;

    if (ping != null) {
      final testing = server.status == ServerStatus.testing;
      return Text(
        '$ping',
        style: TextStyle(
          color: testing ? AppColors.muted2(context) : _pingColor(context),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    if (server.status == ServerStatus.testing) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accent,
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
        text = '—';
        color = AppColors.muted2(context);
    }

    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _smallIcon({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.elevated(context)
            : AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.border(context),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            child: Row(
              children: [
                if (onPin != null)
                  InkWell(
                    onTap: onPin,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        server.isPinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        color: server.isPinned
                            ? AppColors.accent
                            : AppColors.muted2(context),
                        size: 16,
                      ),
                    ),
                  ),

                Text(server.flag, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              server.displayName,
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

                SizedBox(
                  width: 38,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildPing(context),
                  ),
                ),

                const SizedBox(width: 2),

                if (onTest != null)
                  _smallIcon(
                    icon: Icons.bolt,
                    color: AppColors.warn,
                    onPressed: server.status == ServerStatus.testing
                        ? null
                        : onTest,
                  ),

                if (onEdit != null)
                  _smallIcon(
                    icon: Icons.edit_outlined,
                    color: AppColors.muted(context),
                    onPressed: onEdit,
                  ),

                if (onDelete != null)
                  _smallIcon(
                    icon: Icons.delete_outline,
                    color: AppColors.danger,
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
