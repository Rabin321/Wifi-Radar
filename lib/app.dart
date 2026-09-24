import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/theme/app_theme.dart';
import 'features/home/screens/home_screen.dart';

class WifiRadarApp extends StatelessWidget {
  const WifiRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Wifi radar',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const WifiRadarHomeScreen(),
        );
      },
    );
  }
}
