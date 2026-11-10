import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/auth_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.i.init();
  runApp(const CliporaApp());
}

class CliporaApp extends StatelessWidget {
  const CliporaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Clipora',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ValueListenableBuilder<bool>(
          valueListenable: Api.i.loggedIn,
          builder: (_, ok, __) => ok ? const Shell() : const AuthScreen(),
        ),
      );
}
