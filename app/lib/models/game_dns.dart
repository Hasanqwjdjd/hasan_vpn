class GameDns {
  final String name;
  final String primary;
  final String secondary;
  final String? primaryV6;
  final String? secondaryV6;

  const GameDns({
    required this.name,
    required this.primary,
    required this.secondary,
    this.primaryV6,
    this.secondaryV6,
  });

  bool get hasV6 => primaryV6 != null && secondaryV6 != null;
}

final List<GameDns> kGameDnsList = const <GameDns>[
  // ---------- 🇮🇷 ایران ----------
  GameDns(name: '🇮🇷 ایران ۱', primary: '37.32.5.61', secondary: '37.32.5.60'),
  GameDns(name: '🇮🇷 ایران ۲', primary: '10.139.177.22', secondary: '10.139.177.21'),
  GameDns(name: '🇮🇷 ایران ۳', primary: '94.103.125.158', secondary: '94.103.125.157'),
  GameDns(name: '🇮🇷 ایران ۴', primary: '10.202.10.11', secondary: '10.202.10.10'),
  GameDns(name: '🇮🇷 ایران ۵', primary: '31.192.108.180', secondary: '31.192.108.181'),
  GameDns(name: '🇮🇷 ایران ۶', primary: '31.129.110.240', secondary: '45.90.33.120'),
  GameDns(name: '🇮🇷 ایران ۷', primary: '185.55.225.25', secondary: '185.55.226.26'),
  GameDns(name: '🇮🇷 ایران ۸', primary: '111.88.96.50', secondary: '111.88.96.51'),
  GameDns(name: '🇮🇷 ایران ۹ (همراه اول)', primary: '178.22.122.100', secondary: '185.40.202.5'),
  GameDns(name: '🇮🇷 ایران ۱۰ (ایرانسل)', primary: '178.22.122.100', secondary: '185.51.200.2'),
  GameDns(name: '🇮🇷 ایران ۱۱ (مناطق خاص)', primary: '178.22.122.100', secondary: '48.83.124.16'),

  // ---------- 🌐 عمومی ----------
  GameDns(name: '🌐 Shecan', primary: '78.157.42.100', secondary: '78.157.42.101'),
  GameDns(name: '🌐 Shecan v2', primary: '78.157.32.100', secondary: '1.1.1.1'),
  GameDns(name: '🌐 76.76 A', primary: '76.76.2.22', secondary: '76.76.10.22'),
  GameDns(name: '🌐 132.132', primary: '132.132.7.7', secondary: '78.157.32.202'),
  GameDns(name: '🌐 45.90', primary: '45.90.33.120', secondary: '45.90.126.10'),

  // ---------- ☁ Cloudflare / OpenDNS ----------
  GameDns(name: '☁ Cloudflare', primary: '1.1.1.1', secondary: '1.0.0.1'),
  GameDns(name: '☁ Cloudflare+OpenDNS', primary: '1.1.1.1', secondary: '208.67.222.222'),
  GameDns(name: '🟠 OpenDNS', primary: '208.67.220.220', secondary: '129.250.35.20'),
  GameDns(name: '🟠 OpenDNS 2', primary: '185.106.54.225', secondary: '209.244.0.3'),
  GameDns(name: '🔵 Level3', primary: '209.244.0.3', secondary: '209.244.0.4'),

  // ---------- 🛡 AdGuard / امن ----------
  GameDns(name: '🛡 AdGuard', primary: '94.103.125.158', secondary: '94.103.125.157'),
  GameDns(name: '🛡 AdGuard 2', primary: '176.97.78.78', secondary: '1.1.1.1'),
  GameDns(name: '🟢 45.90 - A', primary: '45.90.30.190', secondary: '45.90.28.190'),
  GameDns(name: '🟢 45.90 - B', primary: '45.90.28.190', secondary: '45.90.30.190'),
  GameDns(name: '🟢 45.90 - C', primary: '185.51.200.2', secondary: '45.90.28.0'),

  // ---------- 🎮 Gaming 50.x ----------
  GameDns(name: '🎮 Game 50.155', primary: '50.155.77.121', secondary: '1.1.1.1'),
  GameDns(name: '🎮 Game 50.57', primary: '50.57.126.32', secondary: '1.1.1.1'),
  GameDns(name: '🎮 Game 50.43', primary: '50.43.66.162', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.229', primary: '50.229.158.27', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.194', primary: '50.194.26.120', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.233', primary: '50.233.133.248', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.137', primary: '50.137.149.238', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.72', primary: '50.72.132.158', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.3', primary: '50.3.121.54', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.214', primary: '50.214.62.98', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.21', primary: '50.21.23.88', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.198', primary: '50.198.128.213', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.89', primary: '50.89.102.61', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.101', primary: '50.101.247.89', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.70', primary: '50.70.97.119', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.123', primary: '50.123.63.237', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.97', primary: '50.97.223.66', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.108', primary: '50.108.5.223', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.1', primary: '50.1.79.33', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.15', primary: '50.15.111.249', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.213', primary: '50.213.155.206', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.68', primary: '50.68.118.111', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.113', primary: '50.113.227.119', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.12', primary: '50.12.148.236', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.50', primary: '50.50.5.58', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.131', primary: '50.131.141.140', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.31', primary: '50.31.48.158', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.200', primary: '50.200.96.227', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.45', primary: '50.45.159.244', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.230', primary: '50.230.79.142', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.53', primary: '50.53.62.4', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.36', primary: '50.36.165.208', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.174', primary: '50.174.101.218', secondary: '78.157.42.101'),
  GameDns(name: '🎮 Game 50.62', primary: '78.157.42.101', secondary: '50.62.185.5'),
  GameDns(name: '🎮 Game 50.0', primary: '78.157.42.101', secondary: '50.0.212.76'),
  GameDns(name: '🎮 Game 50.227', primary: '78.157.42.101', secondary: '50.227.104.49'),

  // ---------- 🔒 DoH (DNS روی HTTPS) ----------
  GameDns(name: '🔒 DoH zdn.ro', primary: 'https://zdn.ro/dns-query', secondary: 'https://dns.anon.no/dns-query'),
  GameDns(name: '🔒 DoH ada', primary: 'https://ada.openbld.net/dns-query', secondary: 'https://dns.l337.site/dns-query'),
  GameDns(name: '🔒 DoH Cloudflare GW', primary: 'https://frd4wvnobp.cloudflare-gateway.com/dns-query', secondary: 'https://dns.l337.site/dns-query'),

  // ---------- 🇩🇪 آلمان (Game) ----------
  GameDns(
    name: '🇩🇪 Germany v4+v6',
    primary: '78.157.42.100',
    secondary: '91.108.145.18',
    primaryV6: '2001:4fef:80ff::b2d1',
    secondaryV6: '2001:d534:3fa5::adfd',
  ),

  // ---------- 🔵 IPv6 مخصوص ----------
  GameDns(
    name: '🔵 IPv6 Set A',
    primary: '1.1.1.1',
    secondary: '1.0.0.1',
    primaryV6: '5e56:a508:873b:1e6d:5936:14de:c799:e24a',
    secondaryV6: 'cb1c:2deb:28ed:d339:3bbe:1665:81df:4938',
  ),
  GameDns(
    name: '🔵 IPv6 Set B',
    primary: '78.157.42.100',
    secondary: '78.157.42.101',
    primaryV6: '2001:4fef:80ff::b2d1',
    secondaryV6: '2001:d534:3fa5::adfd',
  ),

  // ---------- 🔐 DNSCrypt (منتخب از لیست رسمی) ----------
  GameDns(name: '🔐 AdGuard DNSCrypt', primary: '94.140.14.14', secondary: '94.140.15.15'),
  GameDns(name: '🔐 AdGuard Family', primary: '94.140.14.15', secondary: '94.140.15.16'),
  GameDns(name: '🔐 AdGuard Unfiltered', primary: '94.140.14.140', secondary: '94.140.14.141'),
  GameDns(name: '🔐 Quad9 DNSCrypt', primary: '9.9.9.9', secondary: '149.112.112.112'),
  GameDns(name: '🔐 Cloudflare DNSCrypt', primary: '1.1.1.1', secondary: '1.0.0.1'),
  GameDns(name: '🔐 ADFilter Adelaide', primary: '103.249.238.124', secondary: '203.29.241.76'),
  GameDns(name: '🔐 ADFilter Perth', primary: '203.29.241.76', secondary: '112.213.32.219'),
  GameDns(name: '🔐 ADFilter Sydney', primary: '112.213.32.219', secondary: '103.249.238.124'),
  GameDns(name: '🔐 dnscry.pt Geneva', primary: '194.135.119.158', secondary: '194.135.119.158'),
  GameDns(name: '🔐 Cryptostorm Bulgaria', primary: '37.120.152.235', secondary: '37.120.152.235'),

  // ---------- ⚡ متفرقه ----------
  GameDns(name: '⚡ 1.92.36', primary: '1.92.36.131', secondary: '78.157.42.100'),
  GameDns(name: '⚡ 65.21', primary: '65.21.242.77', secondary: '78.157.42.100'),
  GameDns(name: '⚡ 78.157.42.100', primary: '78.157.42.100', secondary: '8.119.51.48'),
  GameDns(name: '⚡ 1.1.1.1 + 10.183', primary: '1.1.1.1', secondary: '10.183.213.29'),
];
