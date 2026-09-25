// app/lib/models/dns_entry.dart
//
// New data model for the "DNS Game" directory (v2).
// Replaces the old flat `GameDns` class in game_dns.dart, which stays
// in place (unchanged) so any legacy references still compile; new
// code should use DnsEntry / DnsStats instead.

/// Transport the server is reachable over.
enum DnsProtocol { udp, tcp, doh, dot, doq }

/// Free-form classification tags used for filtering / category chips.
enum DnsTag {
  anycast, // globally routed anycast network
  geo, // region/country-local resolver
  blocking, // blocks ads/trackers/malware
  family, // family-safe / adult content filter
  dnssec, // validates DNSSEC
  unfiltered, // explicitly does not filter/block anything
  privacy, // no-logging / privacy-focused project
  nonprofit, // run by a non-profit / community org
  security, // security/malware-threat filtering specifically
  ecs, // supports EDNS Client Subnet
  requiresConfig, // needs a per-user config id (e.g. NextDNS) before use
}

/// A single resolvable DNS endpoint, sourced from a public, freely
/// licensed directory (see `source` on each entry / file header).
class DnsEntry {
  /// Stable id, e.g. "cloudflare-v4-unfiltered". NOT a uuid — uuids are
  /// generated only for user-created custom entries in DnsRegistry.
  final String id;
  final String name;

  final String? primary; // IPv4
  final String? secondary; // IPv4
  final String? primaryV6;
  final String? secondaryV6;

  final String? dohUrl; // e.g. https://cloudflare-dns.com/dns-query
  final String? dotHost; // e.g. dns.google

  /// ISO 3166-1 alpha-2, or "ZZ" for global anycast with no single home.
  final String country;
  final String provider;
  final Set<DnsTag> tags;
  final Set<DnsProtocol> protocols;

  /// Short citation for where this entry's addresses came from, shown
  /// in the "edit / info" sheet. Not shown as a big banner in the list.
  final String source;

  const DnsEntry({
    required this.id,
    required this.name,
    this.primary,
    this.secondary,
    this.primaryV6,
    this.secondaryV6,
    this.dohUrl,
    this.dotHost,
    required this.country,
    required this.provider,
    this.tags = const <DnsTag>{},
    this.protocols = const <DnsProtocol>{DnsProtocol.udp},
    required this.source,
  });

  bool get hasV6 => primaryV6 != null;
  bool get hasV4 => primary != null;
  bool get isDohOnly => primary == null && primaryV6 == null && dohUrl != null;

  /// The value to hand to Xray as the primary DNS server string.
  /// Prefers plain IPv4, then IPv6, then DoH URL.
  String get xrayPrimary => primary ?? primaryV6 ?? dohUrl ?? '';
  String? get xraySecondary => secondary ?? secondaryV6;
}

/// Per-user, per-entry state — the part that actually changes on-device
/// and gets persisted (ping history, pin/hide, notes). Kept separate
/// from DnsEntry so the big static directory can stay a `const` list.
class DnsStats {
  int? lastPingMs;
  int? lastJitterMs;
  DateTime? lastCheckedAt;
  int successCount;
  int failureCount;
  bool pinned;
  bool hidden;
  bool deleted;
  String? notes;

  DnsStats({
    this.lastPingMs,
    this.lastJitterMs,
    this.lastCheckedAt,
    this.successCount = 0,
    this.failureCount = 0,
    this.pinned = false,
    this.hidden = false,
    this.deleted = false,
    this.notes,
  });

  factory DnsStats.fromJson(Map<String, dynamic> j) => DnsStats(
        lastPingMs: j['lastPingMs'] as int?,
        lastJitterMs: j['lastJitterMs'] as int?,
        lastCheckedAt: j['lastCheckedAt'] != null
            ? DateTime.tryParse(j['lastCheckedAt'] as String)
            : null,
        successCount: (j['successCount'] as int?) ?? 0,
        failureCount: (j['failureCount'] as int?) ?? 0,
        pinned: (j['pinned'] as bool?) ?? false,
        hidden: (j['hidden'] as bool?) ?? false,
        deleted: (j['deleted'] as bool?) ?? false,
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'lastPingMs': lastPingMs,
        'lastJitterMs': lastJitterMs,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'successCount': successCount,
        'failureCount': failureCount,
        'pinned': pinned,
        'hidden': hidden,
        'deleted': deleted,
        'notes': notes,
      };

  /// green / yellow / red stability classification.
  /// Prefers low jitter over low raw ping, per spec.
  String get stability {
    final p = lastPingMs;
    final j = lastJitterMs;
    if (p == null) return 'unknown';
    if (p <= 60 && (j ?? 0) <= 15) return 'green';
    if (p <= 150 && (j ?? 0) <= 40) return 'yellow';
    return 'red';
  }
}

/// A user-added custom DNS entry (kept separate from the static
/// directory; these DO need a real uuid since they're user data).
class CustomDnsEntry {
  final String id; // uuid
  final String name;
  final String? primary;
  final String? secondary;
  final String? primaryV6;
  final String? secondaryV6;
  final String? dohUrl;
  final String? dotHost;
  final DnsProtocol protocol;

  const CustomDnsEntry({
    required this.id,
    required this.name,
    this.primary,
    this.secondary,
    this.primaryV6,
    this.secondaryV6,
    this.dohUrl,
    this.dotHost,
    this.protocol = DnsProtocol.udp,
  });

  factory CustomDnsEntry.fromJson(Map<String, dynamic> j) => CustomDnsEntry(
        id: j['id'] as String,
        name: j['name'] as String,
        primary: j['primary'] as String?,
        secondary: j['secondary'] as String?,
        primaryV6: j['primaryV6'] as String?,
        secondaryV6: j['secondaryV6'] as String?,
        dohUrl: j['dohUrl'] as String?,
        dotHost: j['dotHost'] as String?,
        protocol: DnsProtocol.values.firstWhere(
          (p) => p.name == (j['protocol'] as String? ?? 'udp'),
          orElse: () => DnsProtocol.udp,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'primary': primary,
        'secondary': secondary,
        'primaryV6': primaryV6,
        'secondaryV6': secondaryV6,
        'dohUrl': dohUrl,
        'dotHost': dotHost,
        'protocol': protocol.name,
      };
}
