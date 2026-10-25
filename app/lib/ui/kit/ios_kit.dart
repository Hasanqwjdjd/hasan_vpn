import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fx/fx.dart';
import '../theme/ios_palette.dart';

/// کیت iOS — پورت `ui/settings/IosSettings.kt`، `IosAlerts.kt`،
/// `ScreenChrome.kt` از MLM VPN.

// ─────────────────────────────────────────────────────────── شعاع‌ها

class IosRadius {
  static const double badge = 8;
  static const double control = 12;
  static const double panel = 16;
  static const double card = 22;
  static const double menu = 14;
  static const double dock = 30;
  static const double folderPanel = 36;
}

// ─────────────────────────────────────────────────────────── IosScreen

/// اسکلت صفحه — نوار شناور 44dp + عنوان بزرگ با کشش (IosScreen کیوت).
class IosScreen extends StatefulWidget {
  final String? title;
  final String? largeTitle;
  final String? backLabel;
  final VoidCallback? onBack;
  final Widget? trailing;
  final List<Widget> children;
  final bool scrollable;
  final Color? backdropColor; // برای صفحات روی والپیپر شفاف بماند
  final EdgeInsets contentPadding;

  const IosScreen({
    super.key,
    this.title,
    this.largeTitle,
    this.backLabel,
    this.onBack,
    this.trailing,
    required this.children,
    this.scrollable = true,
    this.backdropColor,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  State<IosScreen> createState() => _IosScreenState();
}

class _IosScreenState extends State<IosScreen> {
  static const double _barHeight = 44;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final hasLarge = (widget.largeTitle ?? '').isNotEmpty;

    Widget content;
    if (widget.scrollable) {
      content = SingleChildScrollView(
        padding: EdgeInsets.only(
          top: topInset + _barHeight + 8,
          bottom: bottomInset + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasLarge)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  widget.largeTitle!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ...widget.children,
          ],
        ),
      );
    } else {
      content = Padding(
        padding: EdgeInsets.only(top: topInset + _barHeight + 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasLarge)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  widget.largeTitle!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ...widget.children,
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          widget.backdropColor ?? IosPal.of(context).background,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          FadingEdges(
            top: topInset + _barHeight,
            bottom: bottomInset + 24,
            child: content,
          ),
          // نوار شناور — پس‌زمینه شیشه‌ای نازک
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            height: _barHeight,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: IosPal.of(context).glassTint.withValues(alpha: 0.55),
                  child: NavigationToolbar(
                    leading: widget.onBack != null
                        ? _BackButton(
                            label: widget.backLabel,
                            onTap: widget.onBack)
                        : null,
                    middle: (widget.title ?? '').isEmpty
                        ? null
                        : Text(
                            widget.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                    trailing: widget.trailing,
                    centerMiddle: true,
                    middleSpacing: 8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final String? label;
  final VoidCallback? onTap;
  const _BackButton({this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return const SizedBox.shrink();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.flip(
              flipX: rtl,
              child:
                  const Icon(Icons.arrow_back_ios_new, size: 22,
                      color: Colors.white),
            ),
            if (label != null && label!.isNotEmpty) ...[
              const SizedBox(width: 2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── گروه تنظیمات

/// `SettingsGroup` — کارت شیشه‌ای inset 16 با جداکننده 0.5dp inset 57.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const SettingsGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FrostedGlass(
        borderRadius: BorderRadius.circular(IosRadius.card),
        blur: 16,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 57),
                  child: Container(
                    height: 0.5,
                    color: IosPal.of(context).separator,
                  ),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// گلیف 29dp شماره ۱ تنظیمات — گرادیان عمودی ±10% از تینت.
class SettingsGlyph extends StatelessWidget {
  final Color tint;
  final IconData icon;
  const SettingsGlyph({super.key, required this.tint, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 29,
      height: 29,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(IosRadius.badge),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(tint, Colors.white, 0.10)!,
            Color.lerp(tint, Colors.black, 0.10)!,
          ],
        ),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

/// ردیف استاندارد — حداقل 44dp؛ value خاکستری + شورون 18dp.
class SettingsRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? value;
  final bool chevron;
  final bool destructive;
  final int? badge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const SettingsRow({
    super.key,
    this.leading,
    required this.title,
    this.value,
    this.chevron = true,
    this.destructive = false,
    this.badge,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final titleColor = destructive ? pal.red : Colors.white;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: titleColor, fontSize: 16, height: 1.15),
              ),
            ),
            if (badge != null && badge! > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Ios.badgeRed,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  badge! > 99 ? '99+' : '$badge',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ] else if (value != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: pal.textMuted, fontSize: 16),
                ),
              ),
            ],
            if (chevron) ...[
              const SizedBox(width: 6),
              Transform.flip(
                flipX: rtl,
                child: Icon(Icons.chevron_right,
                    size: 18, color: pal.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ردیف اکشن ساده — آیکون بدون قاب + لیبل.
class SettingsActionRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final bool destructive;
  final VoidCallback? onTap;
  final bool busy;
  const SettingsActionRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.destructive = false,
    this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(icon,
                    size: 20,
                    color: iconColor ??
                        (destructive ? pal.red : Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: destructive ? pal.red : Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// سوییچ iOS — track آبی، thumb سفید، scale 0.85.
class IosSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const IosSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.85,
      child: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// ردیف سوییچ‌دار.
class SettingsToggle extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SettingsToggle({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final row = SettingsRow(
      leading: leading,
      title: title,
      chevron: false,
      trailing: IosSwitch(value: value, onChanged: onChanged),
    );
    if (subtitle == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 57, right: 16, bottom: 8),
          child: Text(
            subtitle!,
            style: TextStyle(
                color: IosPal.of(context).textMuted,
                fontSize: 12,
                height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// ردیف اسلایدر — داخل کارت شیشه‌ای radius 22 با padding 20/14.
class SettingsSliderRow extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) display;
  final ValueChanged<double> onChanged;
  const SettingsSliderRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16)),
              ),
              Text(display(value),
                  textDirection: TextDirection.ltr,
                  style:
                      TextStyle(color: pal.textMuted, fontSize: 14)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: Colors.white,
              activeTrackColor: pal.blue,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// هدر بخش — 13sp، h20، top26 bottom7.
class SettingsSectionHeader extends StatelessWidget {
  final String text;
  const SettingsSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 26, bottom: 7),
      child: Text(
        text,
        style: TextStyle(
            color: IosPal.of(context).textMuted, fontSize: 13),
      ),
    );
  }
}

/// پانویس بخش — 13sp/21، h32.
class SettingsFooter extends StatelessWidget {
  final String text;
  const SettingsFooter(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
      child: Text(
        text,
        textAlign: TextAlign.start,
        style: TextStyle(
          color: IosPal.of(context).textMuted,
          fontSize: 13,
          height: 21 / 13,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── دیالوگ‌ها

Future<void> showIosAlert(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  VoidCallback? onConfirm,
}) {
  final pal = IosPal.of(context);
  final actions = <Widget>[
    if (cancelLabel != null)
      _AlertAction(label: cancelLabel, onTap: () => Navigator.pop(context)),
    if (confirmLabel != null)
      _AlertAction(
        label: confirmLabel,
        destructive: destructive,
        preferred: true,
        onTap: () {
          Navigator.pop(context);
          onConfirm?.call();
        },
      ),
  ];
  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 290,
        decoration: BoxDecoration(
          color: pal.dialog,
          borderRadius: BorderRadius.circular(IosRadius.card),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(IosRadius.card),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    children: [
                      Text(title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          )),
                      if (message != null && message.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: pal.textMuted,
                              fontSize: 13,
                              height: 1.3,
                            )),
                      ],
                    ],
                  ),
                ),
                if (actions.length == 2)
                  Row(
                    children: [
                      Expanded(
                          child: _verticalDivider(pal, actions.first)),
                      Container(width: 0.5, color: pal.separator),
                      Expanded(child: actions.last),
                    ],
                  )
                else
                  Column(children: actions),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _verticalDivider(IosPal pal, Widget action) => action;

class _AlertAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool preferred;
  const _AlertAction({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.preferred = false,
  });

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: destructive ? pal.red : pal.blue,
            fontSize: 17,
            fontWeight: preferred ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// IosPrompt — دیالوگ + فیلد متنی.
Future<String?> showIosPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String initial = '',
  String? hint,
  String? confirmLabel,
  String? cancelLabel,
  TextInputType? keyboardType,
  bool multiline = false,
}) {
  final pal = IosPal.of(context);
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 290,
        decoration: BoxDecoration(
          color: pal.dialog,
          borderRadius: BorderRadius.circular(IosRadius.card),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(IosRadius.card),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Column(
                    children: [
                      Text(title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          )),
                      if (message != null && message.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: pal.textMuted, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: keyboardType ??
                        (multiline ? TextInputType.multiline : null),
                    maxLines: multiline ? 4 : 1,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle:
                          TextStyle(color: pal.textDim, fontSize: 14),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.10),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(IosRadius.control),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _AlertAction(
                        label: cancelLabel ?? 'انصراف',
                        onTap: () => Navigator.pop(ctx),
                      ),
                    ),
                    Container(width: 0.5, height: 44, color: pal.separator),
                    Expanded(
                      child: _AlertAction(
                        label: confirmLabel ?? 'تأیید',
                        preferred: true,
                        onTap: () => Navigator.pop(ctx, controller.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────── انتخابگر

class IosPickerOption<T> {
  final T value;
  final String label;
  final String? detail;
  const IosPickerOption(this.value, this.label, {this.detail});
}

/// IosPickerScreen — ردیف‌های 44dp با تیک آبی؛ انتخاب → pop.
class IosPickerScreen<T> extends StatelessWidget {
  final String title;
  final List<IosPickerOption<T>> options;
  final T? selected;
  final String? footer;
  const IosPickerScreen({
    super.key,
    required this.title,
    required this.options,
    this.selected,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return IosScreen(
      title: title,
      onBack: () => Navigator.pop(context),
      children: [
        SettingsGroup(
          children: [
            for (final opt in options)
              SettingsRow(
                title: opt.label,
                value: opt.detail,
                chevron: false,
                trailing: opt.value == selected
                    ? const Icon(Icons.check,
                        size: 20, color: Color(0xFF007AFF))
                    : null,
                onTap: () => Navigator.pop(context, opt.value),
              ),
          ],
        ),
        if (footer != null) ...[
          const SizedBox(height: 8),
          SettingsFooter(footer!),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

Future<T?> pushIosPicker<T>(
  BuildContext context, {
  required String title,
  required List<IosPickerOption<T>> options,
  T? selected,
  String? footer,
}) {
  return Navigator.push<T>(
    context,
    MaterialPageRoute(
      builder: (_) => IosPickerScreen<T>(
        title: title,
        options: options,
        selected: selected,
        footer: footer,
      ),
    ),
  );
}

/// IosTextScreen — یک فیلد در کارت + پانویس + دکمه تأیید در نوار.
class IosTextScreen extends StatefulWidget {
  final String title;
  final String label;
  final String initial;
  final String? footer;
  final TextInputType? keyboardType;
  final int maxLines;
  final Future<void> Function(String value) onSubmit;
  const IosTextScreen({
    super.key,
    required this.title,
    required this.label,
    required this.initial,
    required this.onSubmit,
    this.footer,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  State<IosTextScreen> createState() => _IosTextScreenState();
}

class _IosTextScreenState extends State<IosTextScreen> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return IosScreen(
      title: widget.title,
      onBack: () => Navigator.pop(context),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : TextButton(
              onPressed: () async {
                setState(() => _busy = true);
                try {
                  await widget.onSubmit(_c.text.trim());
                  if (context.mounted) Navigator.pop(context);
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
              child: Text(
                'تأیید',
                style: TextStyle(color: pal.blue, fontSize: 16),
              ),
            ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FrostedGlass(
            borderRadius: BorderRadius.circular(IosRadius.card),
            blur: 16,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: TextField(
              controller: _c,
              keyboardType: widget.keyboardType,
              maxLines: widget.maxLines,
              autofocus: true,
              style: const TextStyle(
                  color: Colors.white, fontSize: 17),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.label,
                hintStyle:
                    TextStyle(color: pal.textDim, fontSize: 15),
              ),
            ),
          ),
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: 8),
          SettingsFooter(widget.footer!),
        ],
      ],
    );
  }
}

/// HapticFeed سبک برای تعامل‌های iOS-مانند.
void lightHaptic() {
  HapticFeedback.selectionClick();
}
