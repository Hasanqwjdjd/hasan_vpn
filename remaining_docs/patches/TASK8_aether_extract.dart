// Paste inside _aetherScanNow after building `log`.
String outer = '';
String inner = '';
final hostPort = RegExp(
  r'(?:\d{1,3}\.){3}\d{1,3}:\d{1,5}'
  r'|(?:\[[0-9a-fA-F:]+\]):\d{1,5}',
);

void tryPair(String text) {
  if (outer.isNotEmpty && inner.isNotEmpty) return;
  var m = RegExp(r'مسیر\s+بیرونی\s+(\S+?)\s+و\s+مسیر\s+درونی\s+(\S+)', unicode: true)
      .firstMatch(text);
  if (m != null) {
    outer = m.group(1) ?? '';
    inner = m.group(2) ?? '';
    return;
  }
  m = RegExp(r'cloudflare edge\s+(\S+)\s*\(outer\)\s*and\s*(\S+)\s*\(inner\)',
          caseSensitive: false)
      .firstMatch(text);
  if (m != null) {
    outer = m.group(1) ?? '';
    inner = m.group(2) ?? '';
    return;
  }
  m = RegExp(r'outer[=:\s]+(\S+).*?inner[=:\s]+(\S+)', caseSensitive: false, dotAll: true)
      .firstMatch(text);
  if (m != null) {
    outer = m.group(1) ?? '';
    inner = m.group(2) ?? '';
    return;
  }
  final tail = text.length > 500 ? text.substring(text.length - 500) : text;
  final all = hostPort.allMatches(tail).map((e) => e.group(0)!).toList();
  if (all.length >= 2) {
    outer = all[all.length - 2];
    inner = all[all.length - 1];
  } else if (all.length == 1 && outer.isEmpty) {
    outer = all.first;
  }
}

tryPair(log);
if (outer.isEmpty || inner.isEmpty) {
  final tail = log.length > 500 ? log.substring(log.length - 500) : log;
  tryPair(tail);
}
if (outer.isNotEmpty) _aetherOuterController.text = outer;
if (inner.isNotEmpty) _aetherInnerController.text = inner;
