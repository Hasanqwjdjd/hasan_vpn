import 'package:flutter/material.dart';

/// یک هسته/موتور استفاده‌شده در Hasan VPN.
class CoreEngine {
  final String id;
  final String name;
  final String descriptionFa;
  final String descriptionEn;
  final String currentVersion;
  final String githubRepo; // owner/repo
  final String githubUrl;
  final IconData icon;

  const CoreEngine({
    required this.id,
    required this.name,
    required this.descriptionFa,
    required this.descriptionEn,
    required this.currentVersion,
    required this.githubRepo,
    required this.githubUrl,
    required this.icon,
  });
}

/// لیست هسته‌های برنامه — نسخه‌ها در زمان build freeze می‌شن.
class CoreEngines {
  CoreEngines._();

  static const List<CoreEngine> all = <CoreEngine>[
    CoreEngine(
      id: 'xray',
      name: 'Xray Core',
      descriptionFa:
          'موتور اصلی VPN. VLESS/VMess/Trojan/Shadowsocks/Reality و ...',
      descriptionEn:
          'Main VPN engine. VLESS/VMess/Trojan/Shadowsocks/Reality etc.',
      currentVersion: '26.7.11',
      githubRepo: 'XTLS/Xray-core',
      githubUrl: 'https://github.com/XTLS/Xray-core',
      icon: Icons.bolt,
    ),
    CoreEngine(
      id: 'pingng',
      name: 'PingNG Desync',
      descriptionFa:
          'موتور دور زدن DPI (Split/Disorder/FakeSNI) روی ClientHello',
      descriptionEn:
          'DPI bypass engine (Split/Disorder/FakeSNI) on ClientHello',
      currentVersion: '2.3.9',
      githubRepo: 'rezakhosh78/PingNG',
      githubUrl: 'https://github.com/rezakhosh78/PingNG',
      icon: Icons.security_update_good,
    ),
    CoreEngine(
      id: 'psiphon',
      name: 'Psiphon (JNI)',
      descriptionFa:
          'هسته Psiphon برای عبور از فیلترینگ با protocol های meek/OSSH/fronted',
      descriptionEn:
          'Psiphon engine with meek/OSSH/fronted protocols',
      currentVersion: '2.0.40',
      githubRepo: 'Psiphon-Labs/psiphon-tunnel-core',
      githubUrl:
          'https://github.com/Psiphon-Labs/psiphon-tunnel-core',
      icon: Icons.shield_outlined,
    ),
    CoreEngine(
      id: 'tor',
      name: 'Tor',
      descriptionFa:
          'شبکه Tor با پل‌های obfs4/snowflake/meek/conjure',
      descriptionEn:
          'Tor network with obfs4/snowflake/meek/conjure bridges',
      currentVersion: '0.4.9.11-dev',
      githubRepo: 'torproject/tor',
      githubUrl: 'https://github.com/torproject/tor',
      icon: Icons.privacy_tip_outlined,
    ),
    CoreEngine(
      id: 'usque',
      name: 'WARP MASQUE (usque)',
      descriptionFa:
          'کلاینت MASQUE/H2 کلاودفلر. بدون کلید، خودکار register',
      descriptionEn:
          'Cloudflare MASQUE/H2 client. Auto-registers without keys',
      currentVersion: 'latest',
      githubRepo: 'Diniboy1123/usque',
      githubUrl: 'https://github.com/Diniboy1123/usque',
      icon: Icons.cloud_queue,
    ),
    CoreEngine(
      id: 'tun2socks',
      name: 'tun2socks (HEV)',
      descriptionFa:
          'پل بین Android TUN و پروکسی SOCKS5 (hev-socks5-tunnel)',
      descriptionEn:
          'Bridge between Android TUN and SOCKS5 (hev-socks5-tunnel)',
      currentVersion: '2.5.4',
      githubRepo: 'heiher/hev-socks5-tunnel',
      githubUrl: 'https://github.com/heiher/hev-socks5-tunnel',
      icon: Icons.settings_ethernet,
    ),
    CoreEngine(
      id: 'aether',
      name: 'Aether',
      descriptionFa:
          'تونل هوشمند با MASQUE/WireGuard/MIM. اسکن خودکار بهترین edge',
      descriptionEn:
          'Smart tunnel with MASQUE/WireGuard/MIM. Auto edge scan',
      currentVersion: 'latest',
      githubRepo: 'CluvexStudio/Aether',
      githubUrl: 'https://github.com/CluvexStudio/Aether',
      icon: Icons.auto_awesome,
    ),
    CoreEngine(
      id: 'dnstt',
      name: 'DNSTT',
      descriptionFa:
          'تونل DNS برای عبور از فیلترینگ روی port 53',
      descriptionEn:
          'DNS tunnel to bypass filtering on port 53',
      currentVersion: 'latest',
      githubRepo: 'bamsoftware/dnstt',
      githubUrl: 'https://github.com/bamsoftware/dnstt',
      icon: Icons.dns_outlined,
    ),
    CoreEngine(
      id: 'masterdns',
      name: 'MasterDNS',
      descriptionFa:
          'تونل DNS با کلاینت Go اختصاصی — سرور MasterDnsVPN لازم داره',
      descriptionEn:
          'DNS tunnel with Go client — needs MasterDnsVPN server',
      currentVersion: '2026.05.10',
      githubRepo: 'masterdns/masterdns',
      githubUrl: 'https://github.com/masterdns',
      icon: Icons.travel_explore,
    ),
    CoreEngine(
      id: 'snowflake',
      name: 'Snowflake',
      descriptionFa:
          'پل P2P Tor بر اساس WebRTC — سخت برای فیلتر کامل',
      descriptionEn:
          'P2P Tor bridge via WebRTC — hard to fully block',
      currentVersion: 'latest',
      githubRepo: 'tpo/anti-censorship/pluggable-transports/snowflake',
      githubUrl: 'https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake',
      icon: Icons.ac_unit,
    ),
  ];

  static CoreEngine? byId(String id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }
}
