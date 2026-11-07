import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/server_config_repository_impl.dart';
import '../../domain/app_design.dart';
import '../providers.dart';
import '../theme.dart';

/// Config store key of the chosen design.
const kDesignConfigKey = 'app_design';

/// The design stored in [store]; standard when none is stored.
Future<AppDesign> loadDesign(ConfigStore store) async =>
    AppDesign.parse(await store.read(kDesignConfigKey));

/// The design the app starts in; overridden in `main.dart` with the stored
/// one, read before `runApp`.
final initialDesignProvider = Provider<AppDesign>((ref) => AppDesign.standard);

/// The design in use; changed from the admin area.
final appDesignProvider = NotifierProvider<AppDesignNotifier, AppDesign>(
  AppDesignNotifier.new,
);

class AppDesignNotifier extends Notifier<AppDesign> {
  @override
  AppDesign build() => ref.watch(initialDesignProvider);

  /// Stores [design] and switches to it; a failed write keeps the old one.
  Future<void> select(AppDesign design) async {
    await ref
        .read(configStoreProvider)
        .write(kDesignConfigKey, design.storageKey);
    state = design;
  }
}

/// Colours and fonts of a design.
@immutable
class DesignTokens extends ThemeExtension<DesignTokens> {
  const DesignTokens({
    required this.background,
    required this.backgroundHighlight,
    required this.surface,
    required this.surfaceHigh,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.highlight,
    required this.frame,
    required this.tierPalette,
    required this.bodyFont,
    required this.displayFont,
    required this.displayHasWeights,
    required this.setsFontWeight,
  });

  /// Main background (the darker end of a background gradient).
  final Color background;

  /// Lighter start of the background gradient; equals [background] when
  /// the design has none.
  final Color backgroundHighlight;

  /// Tiles and panels.
  final Color surface;

  /// Raised elements on the background: buttons, dividers.
  final Color surfaceHigh;

  /// Main text on [background].
  final Color text;

  /// Secondary text on [background].
  final Color muted;

  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Highlighted items (collective accounts, favourites).
  final Color highlight;

  /// Frames around boards.
  final Color frame;

  /// Tier colours by tier `sort_order` index, cycling.
  final List<Color> tierPalette;

  final String bodyFont;

  /// Headings and names.
  final String displayFont;

  /// The display font comes in several weights. Alfa Slab One has a single
  /// face: a bold weight would be faked, so its text sets none.
  final bool displayHasWeights;

  /// Text sets [TextStyle.fontWeight] next to its `wght` variation: Barlow
  /// Condensed's static faces are picked by weight only. Standard keeps its
  /// styles as before the designs: Archivo is weighted by its variation.
  final bool setsFontWeight;

  Color tierColor(int index) => tierPalette[index % tierPalette.length];

  /// The tokens of the current theme; standard when the theme has none.
  static DesignTokens of(BuildContext context) =>
      Theme.of(context).extension<DesignTokens>() ?? _standard;

  @override
  DesignTokens copyWith({
    Color? background,
    Color? backgroundHighlight,
    Color? surface,
    Color? surfaceHigh,
    Color? text,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? highlight,
    Color? frame,
    List<Color>? tierPalette,
    String? bodyFont,
    String? displayFont,
    bool? displayHasWeights,
    bool? setsFontWeight,
  }) => DesignTokens(
    background: background ?? this.background,
    backgroundHighlight: backgroundHighlight ?? this.backgroundHighlight,
    surface: surface ?? this.surface,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    highlight: highlight ?? this.highlight,
    frame: frame ?? this.frame,
    tierPalette: tierPalette ?? this.tierPalette,
    bodyFont: bodyFont ?? this.bodyFont,
    displayFont: displayFont ?? this.displayFont,
    displayHasWeights: displayHasWeights ?? this.displayHasWeights,
    setsFontWeight: setsFontWeight ?? this.setsFontWeight,
  );

  /// Designs switch at once; fonts and palettes cannot be blended.
  @override
  DesignTokens lerp(DesignTokens? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

const _standard = DesignTokens(
  background: BarTabTheme.bottle,
  backgroundHighlight: BarTabTheme.bottle,
  surface: BarTabTheme.bottle2,
  surfaceHigh: BarTabTheme.bottle3,
  text: BarTabTheme.paper,
  muted: BarTabTheme.muted,
  accent: BarTabTheme.collectiveAccent,
  onAccent: BarTabTheme.bottle,
  highlight: BarTabTheme.collectiveAccent,
  frame: BarTabTheme.bottle3,
  tierPalette: BarTabTheme.tierPalette,
  bodyFont: BarTabTheme.fontFamily,
  displayFont: BarTabTheme.fontFamily,
  displayHasWeights: true,
  setsFontWeight: false,
);

const _kreidetafel = DesignTokens(
  background: Color(0xFF232724),
  backgroundHighlight: Color(0xFF3A403C),
  surface: Color(0xFF2E332F),
  surfaceHigh: Color(0xFF4A514C),
  text: Color(0xFFF4F1E8),
  muted: Color(0xFFB4B1A8),
  accent: Color(0xFFF7D774),
  onAccent: Color(0xFF232724),
  highlight: Color(0xFFF7D774),
  frame: Color(0xFF7A5534),
  // Coloured chalk: blue, pink, green, orange.
  tierPalette: [
    Color(0xFF9CCBEA),
    Color(0xFFF2A9A3),
    Color(0xFFB8DB9F),
    Color(0xFFF5C28E),
  ],
  bodyFont: 'Caveat',
  displayFont: 'Caveat',
  displayHasWeights: true,
  setsFontWeight: true,
);

const _bierdeckel = DesignTokens(
  background: Color(0xFF17322A),
  backgroundHighlight: Color(0xFF2F5A47),
  surface: Color(0xFFF3E7CF),
  surfaceHigh: Color(0xFF24493B),
  text: Color(0xFFF3E7CF),
  muted: Color(0xFFA9BFB3),
  accent: Color(0xFF7A1F1F),
  onAccent: Color(0xFFF3E7CF),
  highlight: Color(0xFFD9A441),
  frame: Color(0xFFD9A441),
  // Coaster rings, readable on cream and as dots on the green counter.
  tierPalette: [
    Color(0xFFD0603F),
    Color(0xFF4A86C0),
    Color(0xFF9A6BB0),
    Color(0xFF7FB8A4),
  ],
  bodyFont: 'Barlow Condensed',
  displayFont: 'Alfa Slab One',
  displayHasWeights: false,
  setsFontWeight: true,
);

DesignTokens tokensFor(AppDesign design) => switch (design) {
  AppDesign.standard => _standard,
  AppDesign.kreidetafel => _kreidetafel,
  AppDesign.bierdeckel => _bierdeckel,
};

/// The app theme of [design]; standard is today's [BarTabTheme.data].
ThemeData themeFor(AppDesign design) {
  final tokens = tokensFor(design);
  final base = design == AppDesign.standard
      ? BarTabTheme.data
      : _themeFrom(tokens);
  return base.copyWith(extensions: [tokens]);
}

ThemeData _themeFrom(DesignTokens t) {
  final base = ThemeData(
    brightness: Brightness.dark,
    fontFamily: t.bodyFont,
    useMaterial3: true,
    colorScheme: ColorScheme.dark(
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accent,
      onSecondary: t.onAccent,
      surface: t.background,
      onSurface: t.text,
      surfaceContainerHighest: t.surfaceHigh,
    ),
    scaffoldBackgroundColor: t.background,
    canvasColor: t.background,
    cardColor: t.surfaceHigh,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: t.bodyFont,
      bodyColor: t.text,
      displayColor: t.text,
    ),
  );
}

const _fontLicenses = {
  'Archivo': 'assets/fonts/OFL-Archivo.txt',
  'Caveat': 'assets/fonts/OFL-Caveat.txt',
  'Alfa Slab One': 'assets/fonts/OFL-AlfaSlabOne.txt',
  'Barlow Condensed': 'assets/fonts/OFL-BarlowCondensed.txt',
};

/// Adds the OFL licences of the bundled fonts to the app's licence list.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: font, value: asset) in _fontLicenses.entries) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString(asset));
    }
  });
}
