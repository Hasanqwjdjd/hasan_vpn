import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../controllers/home_layout.dart';
import '../l10n/s.dart';
import '../services/package_info_proxy.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';
import 'log_screen.dart';

/// تنظیمات — پورت `ui/settings/SettingsScreen.kt` (ساختار iOS).
/// فاز P1: نمایش/کاغذدیواری/زبان/بازنشانی صفحه‌خانه/درباره.
/// گروه‌های VPN و شبکه در فازهای P2a+ به‌مرور با موتورها اضافه می‌شوند.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppearanceStore get _ap => AppearanceStore.instance;
  LocaleStore get _lo => LocaleStore.instance;

  String _t(String fa, String en) => S.isFa ? fa : en;

  String _themeLabel() {
    switch (_ap.theme) {
      case 'light':
        return _t('روشن', 'Light');
      case 'auto':
        return _t('خودکار', 'Automatic');
      default:
        return _t('تاریک', 'Dark');
    }
  }

  String _wallpaperLabel() {
    for (final p in kWallpaperPresets) {
      if (p.id == _ap.wallpaperId) return S.isFa ? p.fa : p.en;
    }
    return _ap.wallpaperId;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_ap, _lo]),
      builder: (context, _) {
        final version = PackageInfoProxy.version;
        return IosScreen(
          largeTitle: S.t('home_settings'),
          title: S.t('home_settings'),
          backdropColor: Colors.transparent,
          children: [
            SettingsSectionHeader(_t('صفحه‌نمایش', 'Display')),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: _t('کاغذدیواری', 'Wallpaper'),
                  leading: SettingsGlyph(
                      tint: Ios.tilePink, icon: Icons.wallpaper),
                  value: _wallpaperLabel(),
                  onTap: _pickWallpaper,
                ),
                SettingsRow(
                  title: _t('تم برنامه', 'App theme'),
                  leading: SettingsGlyph(
                      tint: Ios.tilePurple, icon: Icons.dark_mode),
                  value: _themeLabel(),
                  onTap: _pickTheme,
                ),
                SettingsSliderRow(
                  title: _t('اندازهٔ آیکون‌ها', 'Icon size'),
                  value: _ap.iconScale.toDouble(),
                  min: AppearanceStore.scaleMin.toDouble(),
                  max: AppearanceStore.scaleMax.toDouble(),
                  divisions:
                      AppearanceStore.scaleMax - AppearanceStore.scaleMin,
                  display: (v) => '${v.round()}%',
                  onChanged: (v) => _ap.setIconScale(v.round()),
                ),
                SettingsToggle(
                  title: _t('اندازهٔ متن — دنبال سیستم', 'Text size — follow system'),
                  value: _ap.textScaleAuto,
                  onChanged: (v) => _ap.setTextScaleAuto(v),
                ),
                if (!_ap.textScaleAuto)
                  SettingsSliderRow(
                    title: _t('اندازهٔ متن', 'Text size'),
                    value: _ap.textScale.toDouble(),
                    min: AppearanceStore.scaleMin.toDouble(),
                    max: AppearanceStore.scaleMax.toDouble(),
                    divisions: AppearanceStore.scaleMax -
                        AppearanceStore.scaleMin,
                    display: (v) => '${v.round()}%',
                    onChanged: (v) => _ap.setTextScale(v.round()),
                  ),
                SettingsSliderRow(
                  title: _t('اندازهٔ برچسب‌ها', 'Label size'),
                  value: _ap.labelScale.toDouble(),
                  min: AppearanceStore.scaleMin.toDouble(),
                  max: AppearanceStore.scaleMax.toDouble(),
                  divisions:
                      AppearanceStore.scaleMax - AppearanceStore.scaleMin,
                  display: (v) => '${v.round()}%',
                  onChanged: (v) => _ap.setLabelScale(v.round()),
                ),
                SettingsToggle(
                  title: _t('نام زیر آیکون‌های داک', 'Dock labels'),
                  value: _ap.dockLabels,
                  onChanged: (v) => _ap.setDockLabels(v),
                ),
                SettingsToggle(
                  title: _t('کاغذدیواری همه‌جا', 'Wallpaper everywhere'),
                  value: _ap.wallpaperEverywhere,
                  onChanged: (v) => _ap.setWallpaperEverywhere(v),
                ),
                SettingsSliderRow(
                  title: _t('تاری کاغذدیواری', 'Wallpaper blur'),
                  value: _ap.wallpaperBlur.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  display: (v) => '${v.round()}',
                  onChanged: (v) => _ap.setWallpaperBlur(v.round()),
                ),
              ],
            ),
            SettingsFooter(_t(
                '«کاغذدیواری همه‌جا» خاموش شود، صفحات پس‌زمینهٔ سادهٔ تیره/روشن می‌گیرند.',
                'With "Wallpaper everywhere" off, pages use plain dark/light backgrounds.')),
            SettingsSectionHeader(_t('زبان', 'Language')),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: _t('زبان برنامه', 'App language'),
                  leading: SettingsGlyph(
                      tint: Ios.tileBlue, icon: Icons.language),
                  value: S.isFa ? 'فارسی' : 'English',
                  onTap: _pickLanguage,
                ),
              ],
            ),
            SettingsSectionHeader(_t('سیستم', 'System')),
            SettingsGroup(
              children: [
                SettingsActionRow(
                  icon: Icons.restart_alt,
                  title: _t('بازنشانی صفحه‌خانه', 'Reset Home Screen'),
                  destructive: true,
                  onTap: () {
                    showIosAlert(
                      context,
                      title: _t('بازنشانی صفحه‌خانه؟', 'Reset Home Screen?'),
                      message: _t(
                          'چیدمان و پوشه‌های شما به حالت اول برمی‌گردد.',
                          'Your layout and folders return to defaults.'),
                      confirmLabel: _t('بازنشانی', 'Reset'),
                      destructive: true,
                      onConfirm: () {
                        HomeLayoutStore.instance.reset();
                      },
                    );
                  },
                ),
              ],
            ),
            SettingsSectionHeader(_t('درباره', 'About')),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: _t('نسخه', 'Version'),
                  leading: SettingsGlyph(
                      tint: Ios.tileGray, icon: Icons.info_outline),
                  value: version,
                  chevron: false,
                ),
                SettingsRow(
                  title: _t('گزارش‌ها', 'App logs'),
                  leading: SettingsGlyph(
                      tint: Ios.tileOrange, icon: Icons.receipt_long),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LogScreen())),
                ),
              ],
            ),
            SettingsFooter(_t(
                'Hasan VPN — بازطراحی رابط کاربری بر پایهٔ الگوی iOS.',
                'Hasan VPN — UI rebuilt after the iOS-style design.')),
            const SizedBox(height: 30),
          ],
        );
      },
    );
  }

  Future<void> _pickTheme() async {
    final v = await pushIosPicker<String>(
      context,
      title: _t('تم برنامه', 'App theme'),
      selected: _ap.theme,
      options: [
        IosPickerOption('auto', _t('خودکار', 'Automatic')),
        IosPickerOption('light', _t('روشن', 'Light')),
        IosPickerOption('dark', _t('تاریک', 'Dark')),
      ],
    );
    if (v != null) await _ap.setTheme(v);
  }

  Future<void> _pickWallpaper() async {
    final v = await pushIosPicker<String>(
      context,
      title: _t('کاغذدیواری', 'Wallpaper'),
      selected: _ap.wallpaperId,
      footer: _t(
          'پس از انتخاب، تاری را با اسلایدر صفحهٔ تنظیمات تنظیم کن.',
          'After choosing, tune the blur with the settings slider.'),
      options: [
        for (final p in kWallpaperPresets)
          IosPickerOption(p.id, S.isFa ? p.fa : p.en),
      ],
    );
    if (v != null) await _ap.setWallpaperId(v);
  }

  Future<void> _pickLanguage() async {
    final v = await pushIosPicker<String>(
      context,
      title: _t('زبان برنامه', 'App language'),
      selected: _lo.lang,
      options: [
        const IosPickerOption('fa', 'فارسی'),
        const IosPickerOption('en', 'English'),
      ],
    );
    if (v != null) await _lo.set(v);
  }
}
