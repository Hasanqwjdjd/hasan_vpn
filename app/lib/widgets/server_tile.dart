import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/aether_profile.dart';
import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/psiphon_service.dart';
import '../services/cdn_detector.dart';

class ServerTile extends StatelessWidget {
  final VpnServer server;
  final bool selected;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onTest;
  final VoidCallback? onHomeWidget;
  final VoidCallback? onRescanWarp;
  /// متن زنده — مثلاً "Scanning · 3/5" در زمان اسکن فعال.
  final String? liveBadge;
  /// امتیاز کیفیت آخر این سرور (null = هنوز ثبت نشده).
  final int? qualityScore;
  final VoidCallback? onLongPress;
  /// حالت گرید دوستونی: آیکون‌ها و padding فشرده می‌شن تا همپوشانی نشه.
  final bool compact;

  const ServerTile({
    super.key,
    required this.server,
    required this.selected,
    required this.onTap,
    this.active = false,
    this.onDelete,
    this.onPin,
    this.onShare,
    this.onCopy,
    this.onEdit,
    this.onTest,
    this.onHomeWidget,
    this.onRescanWarp,
    this.liveBadge,
    this.qualityScore,
    this.onLongPress,
    this.compact = false,
  });

  String get _caption {
    if (server.protocol == VpnProtocol.psiphon) {
      if (PsiphonService.isAutoLink(server.shareLink)) {
        final r = PsiphonService.regionOfLink(server.shareLink);
        return r.isEmpty ? 'PSIPHON · Auto' : 'PSIPHON · Auto · $r';
      }
      return 'PSIPHON · Manual';
    }
    if (server.isAether) {
      final summary = AetherProfile.fromLink(server.shareLink).summary;
      final id = server.id;
      final n = server.name.toLowerCase();
      if (id.startsWith('oblivion_') || n.contains('oblivion')) {
        return 'OBLIVION · $summary';
      }
      if (id.startsWith('siphon_') || n.contains('siphon')) {
        return 'SIPHON · $summary';
      }
      if (id.startsWith('tor_') || n.startsWith('tor ') || n.startsWith('tor·') || n.startsWith('tor ·')) {
        return 'TOR · $summary';
      }
      return 'AETHER · $summary';
    }
    // سرورهای اشتراک (isDeletable=false) آدرس سرورشان نمایش داده نمی‌شود.
    final hideHost = !server.isDeletable;
    if (server.protocol == VpnProtocol.xrayJson) {
      final host = server.host.trim();
      if (hideHost || host.isEmpty || host == 'direct' || host == 'local') {
        return 'XRAY · JSON';
      }
      return 'XRAY · $host';
    }
    // WARP Plus 2-hop: chain:// با vpn:// تودرتو
    if (server.protocol == VpnProtocol.chain) {
      final link = server.shareLink;
      final isWarpChain = link.contains('vpn%3A%2F%2F') ||
          link.contains('vpn://');
      if (isWarpChain) {
        final host = server.host.trim();
        final mode = server.warpEndpointMode ?? '';
        final modeTag = mode.isNotEmpty ? ' · $mode' : '';
        final t = host.isEmpty || hideHost ? 'WARP+' : 'WARP+ · $host';
        return '$t · 2-hop$modeTag';
      }
    }
    // WARP تک‌هاپ با mode
    if (server.protocol == VpnProtocol.amneziaWg &&
        server.warpEndpointMode != null) {
      final host = server.host.trim();
      final mode = server.warpEndpointMode!;
      if (hideHost || host.isEmpty) return 'WARP · $mode';
      return 'WARP · $host · $mode';
    }
    // WARP MASQUE
    if (server.protocol == VpnProtocol.warpMasque) {
      final host = server.host.trim();
      if (hideHost || host.isEmpty) return 'WARP MASQUE';
      return 'MASQUE · $host';
    }
    final proto = server.protocol.name.toUpperCase();
    final host = server.host.trim();
    if (hideHost || host.isEmpty || host == 'unknown') return proto;
    return '$proto · $host';
  }

  /// Does this host sit inside a Cloudflare-owned IPv4 range? Used to put
  /// a "CF" badge on MASQUE / WARP+ / chain servers that are fronted.
  static bool _isCloudflareHost(String host) {
    if (host.isEmpty) return false;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    // Ranges Cloudflare actually announces for WARP/MASQUE + their Anycast
    // edge pool (162.159.192.0/24 is what usque registers against).
    if (a == 162 && b == 159) return true;
    if (a == 104 && b >= 16 && b <= 31) return true;
    if (a == 172 && b >= 64 && b <= 71) return true;
    if (a == 188 && b == 114) return true;
    if (a == 190 && b == 93) return true;
    if (a == 197 && b == 234) return true;
    if (a == 198 && b == 41) return true;
    return false;
  }

  /// Side-strip color: ping-tier at a glance.
  /// green = good (<700ms), amber = ok (<1400ms), red = poor, grey = unknown.
  Color _sideStripColor(BuildContext context) {
    final p = server.ping;
    final status = server.status;
    if (status == ServerStatus.offline) return AppColors.danger;
    if (p == null || p <= 0) return AppColors.muted2(context);
    if (server.pingKind == PingKind.tcp) {
      // TCP-only is approximate; keep it neutral but slightly cooler.
      return p < 700 ? AppColors.accent : AppColors.warn;
    }
    if (p < 700) return AppColors.accent;
    if (p < 1400) return AppColors.warn;
    return AppColors.danger;
  }

  /// badge های کوچیک برای نشان دادن ویژگی‌های خاص سرور.
  List<String> get _badges {
    final out = <String>[];
    // Desync
    final profile = server.pingNgProfile;
    if (profile != null && profile.isNotEmpty && profile != 'Off') {
      out.add(profile == 'Custom' ? 'DSYNC·C' : 'DSYNC');
    }
    if (server.pingNgUdpDesync) out.add('UDP');

    // MASQUE servers are always fronted by Cloudflare Anycast; the parallel
    // scanner always runs, so show "CF" and "SCAN·P" even without a mode.
    if (server.protocol == VpnProtocol.warpMasque) {
      final candidates = server.warpMasqueEndpointCandidates ?? '';
      if (candidates.isNotEmpty) {
        final n = candidates.split(',').length;
        out.add('SCAN·P$n');
      } else {
        out.add('SCAN·P');
      }
      if (_isCloudflareHost(server.host)) out.add('CF');
    }

    // WarpScout — فقط برای WARP/WARP+ با mode ست‌شده
    final mode = server.warpEndpointMode;
    final isWarpLike = server.protocol == VpnProtocol.amneziaWg ||
        (server.protocol == VpnProtocol.chain &&
            (server.shareLink.contains('vpn://') ||
                server.shareLink.contains('vpn%3A%2F%2F')));
    if (isWarpLike && mode != null && mode.isNotEmpty) {
      final abbrev = switch (mode) {
        'Fast' => 'SCAN·F',
        'Medium' => 'SCAN·M',
        'Slow' => 'SCAN·S',
        'Custom' => 'SCAN·C',
        _ => 'SCAN',
      };
      out.add(abbrev);
    }
    // Cloudflare-fronted WARP+ too
    if (isWarpLike && _isCloudflareHost(server.host)) {
      out.add('CF');
    }
    // Multi-address failover pool (BackPack-derived).
    if (server.backupAddresses.isNotEmpty) {
      out.add('MULTI·${server.backupAddresses.length + 1}');
    }
    // Live badge — جایگزین پیش‌فرض
    final live = liveBadge;
    if (live != null && live.isNotEmpty) {
      out.insert(0, live);
    }
    // Quality score badge — Q۴۵ یعنی امتیاز ۴۵
    final q = qualityScore;
    if (q != null && q > 0 && live == null) {
      final emoji = q >= 85
          ? '🟢'
          : q >= 70
              ? '🟢'
              : q >= 50
                  ? '🟡'
                  : q >= 30
                      ? '🟠'
                      : '🔴';
      out.add('$emoji $q');
    }
    return out;
  }

  /// پینگ واقعی (HTTP از داخل تونل).
  /// good = زیر ۷۰۰ms، fair = زیر ۱۴۰۰ms، بدتر = قرمز.
  Color _pingColor(BuildContext context) {
    final ping = server.ping;
    if (ping == null) return AppColors.muted2(context);

    if (server.pingKind == PingKind.tcp) return AppColors.muted2(context);
    if (ping < 700) return AppColors.accent;
    if (ping < 1400) return AppColors.warn;
    return AppColors.danger;
  }

  /// نام تمیزشده: اگر displayName با flag شروع شود، flag تکراری حذف شود.
  String _cleanName() {
    final name = server.displayName;
    final flag = server.flag;
    if (flag.isNotEmpty && name.startsWith(flag)) {
      return name.substring(flag.length).trimLeft();
    }
    return name;
  }

  Widget _buildPing(BuildContext context) {
    final ping = server.ping;

    if (ping != null) {
      final testing = server.status == ServerStatus.testing;
      return Text(
        (server.pingKind == PingKind.tcp ? '~$ping' : '$ping'),
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

  // برچسب‌های منو
  static const String _copyLabel = 'کپی / Copy';
  static const String _shareLabel = 'اشتراک / Share';
  static const String _pinLabel = 'سنجاق / Pin';
  static const String _unpinLabel = 'برداشتن سنجاق / Unpin';
  static const String _pingLabel = 'پینگ / Ping';
  static const String _editLabel = 'ویرایش نام / Rename';
  static const String _widgetLabel = 'ویجت / Home widget';
  static const String _deleteLabel = 'حذف / Delete';
  static const String _rescanLabel = 'اسکن دوباره endpoints / Rescan endpoints';

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
    // حالت compact: گرید دوستونی — آیکون‌ها فشرده،
    // Pin / Test / CDN-badge مخفی، متن ellipsis.
    final c = compact;
    // The side strip conveys ping-tier at a glance, matching PingNG:
    // green = good, amber = ok, red = poor, grey = untested / offline.
    final stripColor = _sideStripColor(context);
    return Container(
      margin: EdgeInsets.only(bottom: c ? 0 : 6),
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
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4-px tier bar on the leading edge.
          Container(width: 4, color: stripColor),
          Expanded(
            child: Material(
              color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: EdgeInsets.fromLTRB(c ? 6 : 4, c ? 4 : 6, c ? 4 : 8,
                c ? 4 : 6),
            child: Row(
              children: [
                // FIX: سنجاق در هر دو حالت نمایش داده می‌شه.
                // در حالت compact کوچیک‌تر و بدون padding اضافه.
                if (onPin != null)
                  InkWell(
                    onTap: onPin,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: EdgeInsets.all(c ? 3 : 6),
                      child: Icon(
                        server.isPinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        color: server.isPinned
                            ? AppColors.accent
                            : AppColors.muted2(context),
                        size: c ? 13 : 16,
                      ),
                    ),
                  ),

                Text(server.flag,
                    style: TextStyle(fontSize: c ? 13 : 16)),

                // CDN badge فقط در حالت لیست
                if (!c)
                  Builder(builder: (ctx) {
                    final cdn = CdnDetector.label(server.host);
                    if (cdn == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.accent.withOpacity(0.4),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          cdn,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                SizedBox(width: c ? 3 : 6),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _cleanName(),
                              style: TextStyle(
                                color: AppColors.fg(context),
                                fontSize: c ? 11 : 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.check_circle,
                              color: AppColors.accent,
                              size: c ? 11 : 14,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _caption,
                              style: TextStyle(
                                color: AppColors.muted2(context),
                                fontSize: c ? 9 : 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_badges.isNotEmpty && !c) ...[
                            const SizedBox(width: 4),
                            for (final b in _badges.take(3))
                              Padding(
                                padding: const EdgeInsets.only(left: 3),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.warn.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: AppColors.warn.withOpacity(0.5),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    b,
                                    style: TextStyle(
                                      color: AppColors.warn,
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(width: c ? 2 : 6),

                SizedBox(
                  width: c ? 28 : 38,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildPing(context),
                  ),
                ),

                SizedBox(width: c ? 0 : 2),

                // Test icon فقط در حالت لیست
                if (!c && onTest != null)
                  _smallIcon(
                    icon: Icons.bolt,
                    color: AppColors.warn,
                    onPressed: server.status == ServerStatus.testing
                        ? null
                        : onTest,
                  ),

                // FIX3: منوی سه‌نقطه — همه گزینه‌ها در یک PopupMenu.
                // کپی/اشتراک فقط برای سرورهای خود کاربر (onCopy/onShare
                // از home_screen فقط وقتی isDeletable=true پاس داده می‌شن).
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: AppColors.muted(context),
                    size: c ? 16 : 18,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: c ? 16 : 18,
                  color: AppColors.surface(context),
                  onSelected: (value) {
                    switch (value) {
                      case 'copy':
                        onCopy?.call();
                        break;
                      case 'share':
                        onShare?.call();
                        break;
                      case 'edit':
                        onEdit?.call();
                        break;
                      case 'pin':
                        onPin?.call();
                        break;
                      case 'test':
                        onTest?.call();
                        break;
                      case 'rescan':
                        onRescanWarp?.call();
                        break;
                      case 'delete':
                        onDelete?.call();
                        break;
                    }
                  },
                  itemBuilder: (bCtx) => <PopupMenuEntry<String>>[
                    if (onCopy != null)
                      PopupMenuItem(
                        value: 'copy',
                        child: Row(children: [
                          Icon(Icons.copy,
                              size: 16, color: AppColors.fg(bCtx)),
                          const SizedBox(width: 8),
                          Text(_copyLabel,
                              style: TextStyle(color: AppColors.fg(bCtx))),
                        ]),
                      ),
                    if (onShare != null)
                      PopupMenuItem(
                        value: 'share',
                        child: Row(children: [
                          Icon(Icons.share_outlined,
                              size: 16, color: AppColors.fg(bCtx)),
                          const SizedBox(width: 8),
                          Text(_shareLabel,
                              style: TextStyle(color: AppColors.fg(bCtx))),
                        ]),
                      ),
                    if (onPin != null)
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(children: [
                          Icon(
                            server.isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 16,
                            color: AppColors.fg(bCtx),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            server.isPinned ? _unpinLabel : _pinLabel,
                            style: TextStyle(color: AppColors.fg(bCtx)),
                          ),
                        ]),
                      ),
                    if (onTest != null)
                      PopupMenuItem(
                        value: 'test',
                        child: Row(children: [
                          Icon(Icons.bolt,
                              size: 16, color: AppColors.fg(bCtx)),
                          const SizedBox(width: 8),
                          Text(_pingLabel,
                              style: TextStyle(color: AppColors.fg(bCtx))),
                        ]),
                      ),
                    if (onRescanWarp != null &&
                        (server.protocol == VpnProtocol.amneziaWg ||
                            server.protocol == VpnProtocol.chain ||
                            server.protocol == VpnProtocol.warpMasque))
                      PopupMenuItem(
                        value: 'rescan',
                        child: Row(children: [
                          Icon(Icons.refresh,
                              size: 16, color: AppColors.fg(bCtx)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(_rescanLabel,
                                style: TextStyle(color: AppColors.fg(bCtx)),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                    if (onEdit != null)
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined,
                              size: 16, color: AppColors.fg(bCtx)),
                          const SizedBox(width: 8),
                          Text(_editLabel,
                              style: TextStyle(color: AppColors.fg(bCtx))),
                        ]),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          const Icon(Icons.delete_outline,
                              size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(_deleteLabel,
                              style: TextStyle(color: Colors.red)),
                        ]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
          ),
        ],
      ),
    );
  }
}
