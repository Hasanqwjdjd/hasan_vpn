/// Dart port of `PingNgCompat.kt`'s argument builder.
///
/// Only the pieces we need on the UI side live here: presets, the bounded
/// custom-options structure and the shell-split tokenizer. The Kotlin side
/// remains the authority on what the native engine accepts — this just
/// produces the same `ciadpi`-style grammar so the two stay in sync.
class PingNgArgs {
  PingNgArgs._();

  static const String off = 'Off';
  static const String light = 'Light';
  static const String balanced = 'Balanced';
  static const String severe = 'Severe';
  static const String adaptive = 'Adaptive';
  static const String custom = 'Custom';

  static const List<String> profiles = <String>[
    off,
    light,
    balanced,
    severe,
    adaptive,
    custom,
  ];

  static const String methodSplit = 'Split';
  static const String methodDisorder = 'Disorder';
  static const String methodFakeSni = 'Fake SNI';
  static const String methodOutOfBand = 'Out of Band';
  static const String methodDisorderOutOfBand = 'Disorder + Out of Band';

  static const List<String> methods = <String>[
    methodSplit,
    methodDisorder,
    methodFakeSni,
    methodOutOfBand,
    methodDisorderOutOfBand,
  ];

  static String normalizeProfile(String? value) {
    switch (value?.trim()) {
      case 'Aggressive':
        return severe;
      case off:
        return off;
      case light:
        return light;
      case balanced:
        return balanced;
      case severe:
        return severe;
      case adaptive:
        return adaptive;
      case custom:
        return custom;
      default:
        return off;
    }
  }

  static bool isEnabled(String? profile) =>
      normalizeProfile(profile) != off;

  /// Builds the full argument list passed to the JNI `prepare()` call.
  ///
  /// Returns `null` when [profile] is Off or Custom with empty arguments,
  /// so callers can skip starting the native listener entirely.
  static List<String>? build({
    required String? profile,
    String? customArgs,
    required int port,
    bool udpDesync = false,
  }) {
    if (port < 1 || port > 65535) return null;
    final normalized = normalizeProfile(profile);
    if (normalized == off) return null;

    final List<String> strategy;
    switch (normalized) {
      case light:
        strategy = const <String>[
          '--proto=tls', '--split', '1+s',
          '--tlsrec', '1+s', '--delay-range', '0-1',
        ];
        break;
      case balanced:
        strategy = const <String>[
          '--proto=tls', '--split-range', '1-3+s',
          '--tlsrec', '1-3+s', '--delay-range', '1-3',
        ];
        break;
      case severe:
        strategy = const <String>[
          '--proto=tls', '--split', '1+s', '--tlsrec', '1+s',
          '--disorder', '3+s', '--fake', '-1', '--ttl', '8',
          '--fake-jitter', '--delay-range', '1-5',
        ];
        break;
      case adaptive:
        strategy = const <String>[
          '--proto=tls', '--split-range', '1-3+s', '--tlsrec', '1-3+s',
          '--auto=torst,redirect,ssl_err', '--disorder', '1',
          '--tlsrec', '1-3+s', '--auto=torst,redirect,ssl_err',
          '--fake', '-1', '--ttl-range', '7-10', '--fake-jitter',
          '--cache-ttl', '3600', '--delay-range', '1-5', '--timeout', '3',
        ];
        break;
      case custom:
        final parsed = shellSplit(customArgs ?? '');
        if (parsed.isEmpty) return null;
        strategy = parsed;
        break;
      default:
        return null;
    }

    // UDP mode: allow both TLS (TCP) and UDP traffic through Desync and
    // add one fake packet per real UDP datagram. Used for Hysteria2/QUIC
    // servers where the outer protocol is UDP.
    final finalStrategy = <String>[];
    if (udpDesync) {
      var replacedProto = false;
      for (final tok in strategy) {
        if (tok == '--proto=tls') {
          finalStrategy.add('--proto=t,u');
          replacedProto = true;
        } else {
          finalStrategy.add(tok);
        }
      }
      // اگه preset اصلاً --proto نداشت، اضافه کن
      if (!replacedProto && !finalStrategy.any((s) => s.startsWith('--proto'))) {
        finalStrategy.insert(0, '--proto=t,u');
      }
      if (!finalStrategy.contains('--udp-fake')) {
        finalStrategy.addAll(const ['--udp-fake', '1']);
      }
    } else {
      finalStrategy.addAll(strategy);
    }

    return <String>[
      'ciadpi',
      ...finalStrategy,
      '--ip', '127.0.0.1',
      '--port', port.toString(),
    ];
  }

  /// Splits a user-supplied argument string the same way the shell would,
  /// honouring single and double quotes plus backslash escapes.
  static List<String> shellSplit(String input) {
    final result = <String>[];
    final current = StringBuffer();
    String? quote;
    bool escaped = false;

    void flush() {
      if (current.isNotEmpty) {
        result.add(current.toString());
        current.clear();
      }
    }

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (escaped) {
        current.write(char);
        escaped = false;
      } else if (char == r'\' && quote != "'") {
        escaped = true;
      } else if (quote != null && char == quote) {
        quote = null;
      } else if (quote == null && (char == "'" || char == '"')) {
        quote = char;
      } else if (quote == null && RegExp(r'\s').hasMatch(char)) {
        flush();
      } else {
        current.write(char);
      }
    }
    if (escaped) current.write(r'\');
    flush();
    return result;
  }
}
