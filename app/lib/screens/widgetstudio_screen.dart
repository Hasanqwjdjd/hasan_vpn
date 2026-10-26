import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../controllers/home_layout.dart';
import '../l10n/s.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// Widget Studio — استودیوی ویجت‌های صفحه‌خانه (الگوی iOS-springboard
/// MLM): ویرایش برد، اندازهٔ آیکون/برچسب، برچسب داک، کاغذدیواری و تاری.
/// همهٔ تغییرات واقعاً روی صفحه‌خانه اعمال می‌شوند (AppearanceStore).
class WidgetStudioScreen extends StatefulWidget {
  const WidgetStudioScreen({super.key});

  @override
  State<WidgetStudioScreen> createState() => _WidgetStudioScreenState();
}

class _WidgetStudioScreenState extends State<WidgetStudioScreen> {
  AppearanceStore get _ap => AppearanceStore.instance;

  String _t(String fa, String en) => S.isFa ? fa : en;

  String _wallpaperLabel() {
    for (final p in kWallpaperPresets) {
      if (p.id == _ap.wallpaperId) return S.isFa ? p.fa : p.en;
    }
    return _ap.wallpaperId;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ap,
      builder: (context, _) {
        return IosScreen(
          title: S.t('studio_home_tile'),
          onBack: () => Navigator.pop(context),
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _t(
                    'صفحه‌خانه مثل یک ویجت‌برد واقعی: هرچیزی را با نگه‌داشتن جابه‌جا کن، روی هم بینداز تا پوشه شود، یا در حالت ویرایش حذف کنی.',
                    'The home board behaves like a real widget board: long-press to move, drop on another to make a folder, or remove in edit mode.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: IosPal.of(context).textMuted,
                    fontSize: 13,
                    height: 20 / 13),
              ),
            ),
            SettingsSectionHeader(_t('چیدمان', 'Layout')),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: _t('حالت ویرایش صفحه‌خانه', 'Home edit mode'),
                  leading: SettingsGlyph(
                      tint: Ios.tileOrange, icon: Icons.edit),
                  value: _t('نگه‌داشتن روی صفحه‌خانه', 'Long-press on Home'),
                  chevron: false,
                ),
                SettingsActionRow(
                  icon: Icons.restart_alt,
                  title: _t('بازنشانی چیدمان', 'Reset layout'),
                  destructive: true,
                  onTap: () {
                    showIosAlert(
                      context,
                      title: _t('بازنشانی چیدمان؟', 'Reset layout?'),
                      message: _t(
                          'ترتیب و پوشه‌ها به حالت اول برمی‌گردد.',
                          'Order and folders return to defaults.'),
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
            SettingsSectionHeader(_t('اندازه‌ها', 'Sizes')),
            SettingsGroup(
              children: [
                SettingsSliderRow(
                  title: _t('آیکون‌ها', 'Icons'),
                  value: _ap.iconScale.toDouble(),
                  min: AppearanceStore.scaleMin.toDouble(),
                  max: AppearanceStore.scaleMax.toDouble(),
                  divisions:
                      AppearanceStore.scaleMax - AppearanceStore.scaleMin,
                  display: (v) => '${v.round()}%',
                  onChanged: (v) => _ap.setIconScale(v.round()),
                ),
                SettingsSliderRow(
                  title: _t('برچسب‌ها', 'Labels'),
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
              ],
            ),
            SettingsSectionHeader(_t('کاغذدیواری', 'Wallpaper')),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: _t('پریست', 'Preset'),
                  leading: SettingsGlyph(
                      tint: Ios.tilePink, icon: Icons.wallpaper),
                  value: _wallpaperLabel(),
                  onTap: () async {
                    final v = await pushIosPicker<String>(
                      context,
                      title: _t('کاغذدیواری', 'Wallpaper'),
                      selected: _ap.wallpaperId,
                      options: [
                        for (final p in kWallpaperPresets)
                          IosPickerOption(p.id, S.isFa ? p.fa : p.en),
                      ],
                    );
                    if (v != null) await _ap.setWallpaperId(v);
                  },
                ),
                SettingsSliderRow(
                  title: _t('تاری', 'Blur'),
                  value: _ap.wallpaperBlur.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  display: (v) => '${v.round()}',
                  onChanged: (v) => _ap.setWallpaperBlur(v.round()),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
