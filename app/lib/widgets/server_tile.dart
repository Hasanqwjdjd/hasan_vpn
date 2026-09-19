import 'package:flutter/material.dart';
import '../models/server.dart';
import '../services/app_colors.dart';

class ServerTile extends StatelessWidget {
  final VpnServer server;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onTest;

  const ServerTile({
    super.key,
    required this.server,
    required this.selected,
    required this.onTap,
    this.onDelete,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Text(server.flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
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
                if (onTest != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32),
                    iconSize: 18,
                    icon: const Icon(Icons.bolt,
                        color: AppColors.warn, size: 18),
                    onPressed: server.status == ServerStatus.testing
                        ? null
                        : onTest,
                  ),
                if (onDelete != null && server.isDeletable)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32),
                    iconSize: 18,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                      size: 18,
                    ),
                    onPressed: onDelete,
                  )
                else
                  const SizedBox(width: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
