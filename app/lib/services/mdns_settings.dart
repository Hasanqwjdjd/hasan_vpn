/// پورت Dart از MasterDnsSettings.kt در PingNG.
///
/// یک TOML string رو به فیلد های قابل ویرایش تبدیل می‌کنه، مقادیر
/// رو با حفظ unknown keys برمی‌گردونه، و اعتبارسنجی می‌کنه.
///
/// فرمت ورودی معمولاً خطوط `<KEY> = <value>` با کامنت‌های `# N) section`.
class MdnsSettings {
  MdnsSettings._();

  static final RegExp _assignment =
      RegExp(r'^([A-Z][A-Z0-9_]*)\s*=\s*(.*)$');
  static final RegExp _section = RegExp(r'^# [0-9]+\) (.+)$');

  /// کلیدهایی که به‌عنوان reserved توسط client TOML مدیریت می‌شوند
  /// و نباید در ویرایشگر نمایش داده شوند.
  static const Set<String> _reserved = {
    'DOMAINS',
    'DATA_ENCRYPTION_METHOD',
    'ENCRYPTION_KEY',
    'PROTOCOL_TYPE',
    'LISTEN_IP',
    'LISTEN_PORT',
    'MTU_TEST_PARALLELISM',
  };

  /// نوع مقدار — برای رندر صحیح کنترل UI.
  static MdnsFieldKind _kindOf(String raw) {
    final trimmed = raw.trim();
    if (trimmed == 'true' || trimmed == 'false') {
      return MdnsFieldKind.boolean;
    }
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return MdnsFieldKind.string;
    }
    return MdnsFieldKind.number;
  }

  /// استخراج لیست فیلدهای قابل ویرایش از یه TOML string.
  ///
  /// section ها از کامنت‌های `# N) Title` استخراج می‌شن. اگه هیچ
  /// section ی نبود، همه به "Other settings" نسبت داده می‌شن.
  static List<MdnsField> fields(String config) {
    var group = 'Other settings';
    final out = <MdnsField>[];
    for (final rawLine in const LineSplitter().convert(config)) {
      final line = rawLine.trim();

      // چک section
      final sectionMatch = _section.firstMatch(line);
      if (sectionMatch != null) {
        group = sectionMatch.group(1)?.trim() ?? group;
      }

      // چک assignment
      final assignMatch = _assignment.firstMatch(line);
      if (assignMatch == null) continue;
      final key = assignMatch.group(1);
      if (key == null || _reserved.contains(key)) continue;

      final rawValue = (assignMatch.group(2) ?? '').trim();
      final kind = _kindOf(rawValue);
      final decoded = kind == MdnsFieldKind.string
          ? _decodeString(rawValue)
          : rawValue;

      out.add(MdnsField(
        key: key,
        section: group,
        value: decoded,
        kind: kind,
      ));
    }
    return out;
  }

  /// خواندن مقدار یک کلید خاص.
  static String? value(String config, String key) {
    for (final line in const LineSplitter().convert(config)) {
      final match = _assignment.firstMatch(line.trim());
      if (match == null) continue;
      if (match.group(1) == key) {
        return match.group(2)?.trim();
      }
    }
    return null;
  }

  /// جایگزینی مقدار یک کلید با حفظ فرمت اصلی.
  /// اگه کلید وجود نداشت، به انتهای فایل اضافه می‌شه.
  static String put(
    String config,
    String key,
    String value,
    MdnsFieldKind kind,
  ) {
    if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(key)) {
      throw ArgumentError('Invalid key: $key');
    }
    final encoded = switch (kind) {
      MdnsFieldKind.string => _encodeString(value),
      MdnsFieldKind.boolean => (value.trim() == 'true') ? 'true' : 'false',
      MdnsFieldKind.number => value.trim(),
    };
    final replacement = '$key = $encoded';

    var found = false;
    final lines = <String>[];
    for (final rawLine in const LineSplitter().convert(config)) {
      final match = _assignment.firstMatch(rawLine.trim());
      if (match != null && match.group(1) == key) {
        found = true;
        lines.add(replacement);
      } else {
        lines.add(rawLine);
      }
    }
    if (!found) lines.add(replacement);
    return lines.join('\n');
  }

  /// اعتبارسنجی مقدار یک فیلد بر اساس نوعش.
  static bool valid(MdnsField field) {
    switch (field.kind) {
      case MdnsFieldKind.boolean:
        return field.value == 'true' || field.value == 'false';
      case MdnsFieldKind.number:
        final n = num.tryParse(field.value);
        return n != null && n.isFinite;
      case MdnsFieldKind.string:
        return true;
    }
  }

  /// اعتبارسنجی کل لیست.
  static ({bool ok, List<String> badKeys}) validate(
      List<MdnsField> fields) {
    final bad = <String>[];
    for (final f in fields) {
      if (!valid(f)) bad.add(f.key);
    }
    return (ok: bad.isEmpty, badKeys: bad);
  }

  // ── String encode/decode برای TOML ──

  static String _encodeString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return '"$escaped"';
  }

  static String _decodeString(String raw) {
    if (raw.length < 2) return raw;
    var s = raw.substring(1, raw.length - 1);
    s = s.replaceAll(r'\n', '\n');
    s = s.replaceAll(r'\r', '\r');
    s = s.replaceAll(r'\"', '"');
    s = s.replaceAll(r'\\', r'\');
    return s;
  }
}

/// نوع فیلد TOML.
enum MdnsFieldKind { boolean, string, number }

/// یک فیلد قابل ویرایش از client_config.toml.
class MdnsField {
  final String key;
  final String section;
  final String value;
  final MdnsFieldKind kind;

  const MdnsField({
    required this.key,
    required this.section,
    required this.value,
    required this.kind,
  });

  MdnsField copyWith({String? value}) => MdnsField(
        key: key,
        section: section,
        value: value ?? this.value,
        kind: kind,
      );
}

/// LineSplitter معادل const نداره، پس اینجا یه نمونه ساده می‌سازیم.
class LineSplitter {
  const LineSplitter();
  List<String> convert(String input) => input.split('\n');
}
