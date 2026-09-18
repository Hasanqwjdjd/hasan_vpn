import 'package:flutter/material.dart';
import '../models/server.dart';

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
      pingColor = Colors.white38;
    } else if (server.ping == null) {
      pingColor = const Color(0xFFE07070);
    } else if (server.ping! < 200) {
      pingColor = const Color(0xFF3DCF9A);
    } else if (server.ping! < 500) {
      pingColor = const Color(0xFFFFB74D);
    } else {
      pingColor = const Color(0xFFE07070);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1A1D25) : const Color(0xFF12141A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? const Color(0xFF3DCF9A) : Colors.white12,
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // پینگ یا لودر
                if (server.status == ServerStatus.testing)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF3DCF9A),
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
                // دکمه تست جداگانه
                if (onTest != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 18,
                    icon: const Icon(Icons.bolt,
                        color: Color(0xFFFFB74D), size: 18),
                    onPressed: server.status == ServerStatus.testing
                        ? null
                        : onTest,
                  ),
                // دکمه حذف
                if (onDelete != null && server.isDeletable)
                  IconButton(
                    padding: const EdgeInsets.only(right: 4, left: 0),
                    constraints: const BoxConstraints(),
                    iconSize: 18,
                    icon: const Text('🗑️', style: TextStyle(fontSize: 14)),
                    onPressed: onDelete,
                  )
                else
                  const SizedBox(width: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
