import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  static const background = homeBackground;
  static const homeBackground = Color(0xFFF1F2ED);
  static const homeCard = Color(0xFFFFFFFF);
  static const homeInk = Color(0xFF30322F);
  static const homeMuted = Color(0xFF858882);
  static const homeBorder = Color(0xFFE5E6E1);
  static const homeAccent = Color(0xFFF47B25);
  static const surface = homeCard;
  static const raised = homeBorder;
  static const ivory = homeInk;
  static const accent = homeAccent;
  static const muted = homeMuted;
  static const inactive = homeMuted;
  static const ink = homeInk;
  static const cardMuted = homeMuted;
}

ThemeData buildAppTheme() {
  final scheme = const ColorScheme.light(
    primary: AppColors.homeAccent,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ivory,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ivory,
      elevation: 0,
      centerTitle: true,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.homeInk,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: const StadiumBorder(),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.raised,
      thumbColor: AppColors.accent,
      trackHeight: 3,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.ink,
      selectionColor: AppColors.raised,
      selectionHandleColor: AppColors.accent,
    ),
  );
}
