import 'package:flutter/material.dart';

ThemeData appTheme(Brightness b) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF5B5BD6),
    brightness: b,
  ),
);
