import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Kamera uygulaması olduğu için ekranın otomatik kilitlenmesini engellemek
  // isteğe bağlıdır; burada yalnızca dikey yönü sabitliyoruz.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const EOkulFotoApp());
}

/// e-Okul Vesikalık uygulaması.
class EOkulFotoApp extends StatelessWidget {
  const EOkulFotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'e-Okul Vesikalık',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
