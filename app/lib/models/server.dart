enum VpnProtocol { trojan, vless, vmess }

class VpnServer {
  final String id;
  final String name;
  final String flag;
  final String shareLink;
  final VpnProtocol protocol;
  final String host;
  final int port;

  int? ping;
  int? speedKbps;
  ServerStatus status;

  VpnServer({
    required this.id,
    required this.name,
    required this.flag,
    required this.shareLink,
    required this.protocol,
    required this.host,
    required this.port,
    this.ping,
    this.speedKbps,
    this.status = ServerStatus.idle,
  });
}

enum ServerStatus { idle, testing, online, offline }

// ═══════════════════════════════════════════════
// سرورهای تو اینجا
// ═══════════════════════════════════════════════
final List<VpnServer> kServers = [
  VpnServer(
    id: 's1',
    name: '🇺🇸 حسن - سریع',
    flag: '🇺🇸',
    protocol: VpnProtocol.trojan,
    host: '8.39.204.21',
    port: 443,
    shareLink: 'trojan://413f4627-bfcb-41ff-8b6b-a0d830364376@8.39.204.21:443?path=%2Fxiron&security=tls&pbk=enabled&insecure=0&host=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev&fp=firefox&type=ws&allowInsecure=0&sni=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev#%F0%9F%87%BA%F0%9F%87%B8%D8%AD%D8%B3%D9%86',
  ),
  VpnServer(
    id: 's2',
    name: '🇺🇸 حسن - پشتیبان',
    flag: '🇺🇸',
    protocol: VpnProtocol.trojan,
    host: '8.39.204.172',
    port: 443,
    shareLink: 'trojan://413f4627-bfcb-41ff-8b6b-a0d830364376@8.39.204.172:443?path=%2Fxiron&security=tls&pbk=enabled&insecure=0&host=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev&fp=firefox&type=ws&allowInsecure=0&sni=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev#%F0%9F%87%BA%F0%9F%87%B8%D8%AD%D8%B3%D9%86',
  ),
  VpnServer(
    id: 's3',
    name: '🕷 Spider-Hasan',
    flag: '🕷',
    protocol: VpnProtocol.vless,
    host: 'spiderpanel-production-d82c.up.railway.app',
    port: 443,
    shareLink: 'vless://97ff6e0e-d059-45a2-8fc7-57d09a07a15d@spiderpanel-production-d82c.up.railway.app:443?path=%2Fws%2F97ff6e0e-d059-45a2-8fc7-57d09a07a15d&security=tls&alpn=http%2F1.1&encryption=none&insecure=0&host=spiderpanel-production-d82c.up.railway.app&fp=chrome&type=ws&allowInsecure=0&sni=spiderpanel-production-d82c.up.railway.app#Spider-Hasan',
  ),
  VpnServer(
    id: 's4',
    name: '☁️ حسن - Cloudflare',
    flag: '☁️',
    protocol: VpnProtocol.trojan,
    host: '104.16.112.215',
    port: 443,
    shareLink: 'trojan://413f4627-bfcb-41ff-8b6b-a0d830364376@104.16.112.215:443?path=%2Fxiron&security=tls&pbk=enabled&insecure=0&host=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev&fp=firefox&type=ws&allowInsecure=0&sni=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev#%F0%9F%87%BA%F0%9F%87%B8%D8%AD%D8%B3%D9%86',
  ),
];
