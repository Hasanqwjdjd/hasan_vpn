/// پروفایل اتصال SSH.
///
/// معماری: اپ به سرور SSH وصل می‌شود و از طریق `forwardLocal` یک پورت
/// محلی می‌سازد که به SOCKS5 روی همان سرور SSH (پیش‌فرض 127.0.0.1:1080)
/// فوروارد می‌کند. سپس Xray از آن به‌عنوان outbound=socks استفاده می‌کند.
///
/// روی سرور SSH کاربر باید یک SOCKS5 ساده اجرا کند (مثلاً microsocks):
///   microsocks -p 1080 -i 127.0.0.1
class SshProfile {
  final String host;
  final int port;
  final String username;

  /// رمز عبور — خالی اگر از کلید استفاده می‌شود.
  final String password;

  /// کلید خصوصی PEM — خالی اگر از رمز استفاده می‌شود.
  final String privateKey;

  /// passphrase کلید خصوصی (اختیاری).
  final String passphrase;

  /// پورت SOCKS5 روی سرور SSH (باید فقط روی 127.0.0.1 گوش بده).
  final int remoteSocksPort;

  /// برچسب نمایشی.
  final String name;

  const SshProfile({
    this.host = '',
    this.port = 22,
    this.username = '',
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
    this.remoteSocksPort = 1080,
    this.name = '',
  });

  String get summary {
    if (host.isEmpty) return 'SSH';
    return 'SSH · $username@$host:$port';
  }

  bool get isComplete =>
      host.isNotEmpty &&
      username.isNotEmpty &&
      (password.isNotEmpty || privateKey.isNotEmpty);

  String toLink() {
    final q = <String, String>{
      'host': host,
      'port': '$port',
      'user': username,
      if (password.isNotEmpty) 'pass': password,
      if (privateKey.isNotEmpty) 'key': privateKey,
      if (passphrase.isNotEmpty) 'passphrase': passphrase,
      if (remoteSocksPort != 1080) 'socks': '$remoteSocksPort',
      if (name.isNotEmpty) 'name': name,
    };
    return Uri(scheme: 'ssh', host: 'config', queryParameters: q).toString();
  }

  factory SshProfile.fromLink(String link) {
    try {
      final uri = Uri.parse(link);
      if (uri.scheme.toLowerCase() != 'ssh') return const SshProfile();
      return SshProfile.fromQuery(uri.queryParameters);
    } catch (_) {
      return const SshProfile();
    }
  }

  factory SshProfile.fromQuery(Map<String, String> q) {
    return SshProfile(
      host: (q['host'] ?? '').trim(),
      port: int.tryParse(q['port'] ?? '') ?? 22,
      username: (q['user'] ?? '').trim(),
      password: q['pass'] ?? '',
      privateKey: q['key'] ?? '',
      passphrase: q['passphrase'] ?? '',
      remoteSocksPort: int.tryParse(q['socks'] ?? '') ?? 1080,
      name: (q['name'] ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'privateKey': privateKey,
        'passphrase': passphrase,
        'remoteSocksPort': remoteSocksPort,
        'name': name,
      };

  factory SshProfile.fromJson(Map<String, dynamic> j) => SshProfile(
        host: j['host']?.toString() ?? '',
        port: (j['port'] as num?)?.toInt() ?? 22,
        username: j['username']?.toString() ?? '',
        password: j['password']?.toString() ?? '',
        privateKey: j['privateKey']?.toString() ?? '',
        passphrase: j['passphrase']?.toString() ?? '',
        remoteSocksPort: (j['remoteSocksPort'] as num?)?.toInt() ?? 1080,
        name: j['name']?.toString() ?? '',
      );
}
