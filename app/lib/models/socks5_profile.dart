/// پروفایل پروکسی SOCKS5 از راه دور.
///
/// Xray این رو به‌عنوان outbound=socks استفاده می‌کند و ترافیک از سرور
/// SOCKS5 کاربر عبور می‌کند (بدون lایه‌ی رمزنگاری — کاربر مسئول اعتماد
/// به سرور است).
class Socks5Profile {
  final String host;
  final int port;
  final String username;
  final String password;
  final String name;

  const Socks5Profile({
    this.host = '',
    this.port = 1080,
    this.username = '',
    this.password = '',
    this.name = '',
  });

  bool get isComplete => host.isNotEmpty && port > 0;

  String get summary {
    if (host.isEmpty) return 'SOCKS5';
    return 'SOCKS5 · $host:$port';
  }

  String toLink() {
    final q = <String, String>{
      'host': host,
      'port': '$port',
      if (username.isNotEmpty) 'user': username,
      if (password.isNotEmpty) 'pass': password,
      if (name.isNotEmpty) 'name': name,
    };
    return Uri(scheme: 'socks5', host: 'config', queryParameters: q).toString();
  }

  factory Socks5Profile.fromLink(String link) {
    try {
      final uri = Uri.parse(link);
      if (uri.scheme.toLowerCase() != 'socks5') return const Socks5Profile();
      return Socks5Profile.fromQuery(uri.queryParameters);
    } catch (_) {
      return const Socks5Profile();
    }
  }

  factory Socks5Profile.fromQuery(Map<String, String> q) {
    return Socks5Profile(
      host: (q['host'] ?? '').trim(),
      port: int.tryParse(q['port'] ?? '') ?? 1080,
      username: (q['user'] ?? '').trim(),
      password: q['pass'] ?? '',
      name: (q['name'] ?? '').trim(),
    );
  }
}
