class Subscription {
  final String id;
  final String name;
  final String url;
  bool autoUpdate;
  DateTime? lastUpdated;
  int serverCount;

  Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.autoUpdate = true,
    this.lastUpdated,
    this.serverCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'autoUpdate': autoUpdate,
        'lastUpdated': lastUpdated?.toIso8601String(),
        'serverCount': serverCount,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        autoUpdate: json['autoUpdate'] as bool? ?? true,
        lastUpdated: json['lastUpdated'] != null
            ? DateTime.tryParse(json['lastUpdated'] as String)
            : null,
        serverCount: json['serverCount'] as int? ?? 0,
      );
}
