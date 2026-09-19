import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/server.dart';
import '../services/app_colors.dart';

class ServerTile extends StatelessWidget {
  final VpnServer server;
  final bool selected;
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
    this.onDelete,
    this.onPin,
    this.onShare,
    this.onEdit,
    this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    Color pingColor;
    if (server.status == ServerStatus.testing) {
      pingColor = AppColors.muted2(context);
    } else if (server.ping == null) {
      pingColor = AppColors.danger;
    } else if (server.ping! < 200) {
      pingColor = AppColors.accent;
    } else if (server.ping! < 500) {
      pingColor = AppColors.warn;
    } else {
      pingColor = AppColors.danger;
    }

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
                // Pin
                if (onPin != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28),
                    iconSize: 18,
                    icon: Icon(
                      server.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: server.isPinned
                          ? AppColors.accent
                          : AppColors.muted2(context),
                      size: 18,
                    ),
                    onPressed: onPin,
                  ),

                // Flag
                Text(server.flag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),

                // Name
                Expanded(
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

                // Ping
                if (server.status == ServerStatus.testing)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                else
                  Text(
                    server.ping != null ? '${server.ping} ms' : '---',
                    style: TextStyle(
                      color: pingColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                // Copy
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28),
                  iconSize: 16,
                  icon: const Icon(Icons.copy, color: AppColors.accent, size: 16),
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

                // Bolt / Test one server (صاعقه) - طبق درخواست کاربر نگه داشته شد
                if (onTest != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28),
                    iconSize: 16,
                    icon: const Icon(Icons.bolt, color: AppColors.warn, size: 16),
                    onPressed: server.status == ServerStatus.testing ? null : onTest,
                  ),

                // Share
                if (onShare != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28),
                    iconSize: 16,
                    icon: Icon(Icons.share_outlined,
                        color: AppColors.muted(context), size: 16),
                    onPressed: onShare,
                  ),

                // Edit (optional)
                if (onEdit != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28),
                    iconSize: 16,
                    icon: Icon(Icons.edit_outlined,
                        color: AppColors.muted(context), size: 16),
                    onPressed: onEdit,
                  ),

                // Delete
                if (onDelete != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28),
                    iconSize: 16,
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.danger, size: 16),
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
