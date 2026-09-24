import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF06131D),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF5EE6C5),
      brightness: Brightness.dark,
    ),
    textTheme: Typography.whiteMountainView,
  );
}
