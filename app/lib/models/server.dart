enum VpnProtocol { trojan, vless, vmess, hysteria2, aether }

class VpnServer {
  final String id;
  final String name;
  final String flag;
  final String shareLink;
  final VpnProtocol protocol;
  final String host;
  final int port;
  String? sniOrHost;
  bool isDeletable;

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
    this.sniOrHost,
    this.isDeletable = true,
    this.ping,
    this.speedKbps,
    this.status = ServerStatus.idle,
  });
}

enum ServerStatus { idle, testing, online, offline }

final List<VpnServer> kServers = [
  VpnServer(
    id: 's1',
    name: '🇺🇸 حسن - سریع',
    flag: '🇺🇸',
    protocol: VpnProtocol.trojan,
    host: '8.39.204.21',
    port: 443,
    sniOrHost: 'morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev',
    isDeletable: false,
    shareLink: 'trojan://413f4627-bfcb-41ff-8b6b-a0d830364376@8.39.204.21:443?path=%2Fxiron&security=tls&pbk=enabled&insecure=0&host=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev&fp=firefox&type=ws&allowInsecure=0&sni=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev#%F0%9F%87%BA%F0%9F%87%B8%D8%AD%D8%B3%D9%86',
  ),
  VpnServer(
    id: 's2',
    name: '🇺🇸 حسن - پشتیبان',
    flag: '🇺🇸',
    protocol: VpnProtocol.trojan,
    host: '8.39.204.172',
    port: 443,
    sniOrHost: 'morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev',
    isDeletable: false,
    shareLink: 'trojan://413f4627-bfcb-41ff-8b6b-a0d830364376@8.39.204.172:443?path=%2Fxiron&security=tls&pbk=enabled&insecure=0&host=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev&fp=firefox&type=ws&allowInsecure=0&sni=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev#%F0%9F%87%BA%F0%9F%87%B8%D8%AD%D8%B3%D9%86',
  ),
  VpnServer(
    id: 's3',
    name: '🕷 Spider-Hasan',
    flag: '🕷',
    protocol: VpnProtocol.vless,
    host: 'spiderpanel-production-d82c.up.railway.app',
    port: 443,
    sniOrHost: 'spiderpanel-production-d82c.up.railway.app',
    isDeletable: false,
    shareLink: 'vless://97ff6e0e-d059-45a2-8fc7-57d09a07a15d@spiderpanel-production-d82c.up.railway.app:443?path=%2Fws%2F97ff6e0e-d059-45a2-8fc7-57d09a07a15d&security=tls&alpn=http%2F1.1&encryption=none&insecure=0&host=spiderpanel-production-d82c.up.railway.app&fp=chrome&type=ws&allowInsecure=0&sni=spiderpanel-production-d82c.up.railway.app#Spider-Hasan',
  ),
  VpnServer(
    id: 's4',
    name: '☁️ حسن - Cloudflare',
    flag: '☁️',
    protocol: VpnProtocol.trojan,
    host: '104.16.112.215',
    port: 443,
    sniOrHost: 'morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev',
    isDeletable: false,
    shareLink: 'trojan://413f4627-bfcb-41ff-8b6b-a0d830364376@104.16.112.215:443?path=%2Fxiron&security=tls&pbk=enabled&insecure=0&host=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev&fp=firefox&type=ws&allowInsecure=0&sni=morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev#%F0%9F%87%BA%F0%9F%87%B8%D8%AD%D8%B3%D9%86',
  ),
  VpnServer(
    id: 's5',
    name: '🇭🇰 hamedvpns - Hysteria2',
    flag: '🇭🇰',
    protocol: VpnProtocol.hysteria2,
    host: 'nas.aizhzo.com',
    port: 5010,
    sniOrHost: 'nas.aizhzo.com',
    isDeletable: false,
    shareLink: 'hysteria2://eBTe6Ax2pUts8oMEWoYVDfnSlHfkLffQ@nas.aizhzo.com:5010?security=tls&obfs=salamander&obfs-password=7M4RXPFcQyQEGbkxBPfXo4bilMhCW2U9&insecure=0&sni=nas.aizhzo.com#hamedvpns',
  ),
  VpnServer(
    id: 's6',
    name: '🇯🇵 hamedvpns - Reality',
    flag: '🇯🇵',
    protocol: VpnProtocol.vless,
    host: '150.40.126.22',
    port: 443,
    sniOrHost: 'rs4.univesalsrv.com',
    isDeletable: false,
    shareLink: 'vless://2f35965a-9a9b-45fd-ba32-987296dfb6be@150.40.126.22:443?mode=gun&security=reality&encryption=none&pbk=sXsJ4ET-50TYqlhKZf03nPQr2JIy1F0D4m6lOsI0cAs&fp=firefox&type=grpc&serviceName=media.v1.StreamService&sni=rs4.univesalsrv.com&sid=861ac7d66953e55f#hamedvpns',
  ),
];
