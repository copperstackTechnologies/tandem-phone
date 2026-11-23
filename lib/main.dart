import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'app_scope.dart';
import 'app_state.dart';
import 'background.dart';
import 'screens/home_shell.dart';
import 'screens/pair_screen.dart';
import 'share_intake.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Workmanager().initialize(callbackDispatcher);
  } catch (_) {
    // Background retry is optional; the app works without it.
  }
  final state = await AppState.create();
  runApp(TandemApp(state: state));
}

class TandemApp extends StatefulWidget {
  const TandemApp({super.key, required this.state});
  final AppState state;

  @override
  State<TandemApp> createState() => _TandemAppState();
}

class _TandemAppState extends State<TandemApp> with WidgetsBindingObserver {
  static const _seed = Color(0xFF0F6E6E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShareIntake.init(navKey);
    widget.state.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) widget.state.onResume();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        navigatorKey: navKey,
        title: 'Tandem',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark, useMaterial3: true),
        home: ListenableBuilder(
          listenable: widget.state,
          builder: (_, _) => widget.state.pairing == null ? const PairScreen() : const HomeShell(),
        ),
      ),
    );
  }
}
