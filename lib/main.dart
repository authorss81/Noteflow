import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/database.dart';
import 'data/repository.dart';
import 'screens/home_screen.dart';
import 'widgets/lock_screen.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final db = AppDatabase();
  final repo = NoteRepository(db);
  final app = AppState(repo, settings);
  // R1-16: don't block the first frame on DB bootstrap + P2P server start —
  // render immediately and load the tree in the background.
  runApp(NoteflowApp(app: app));
  unawaited(app.bootstrap());
}

class NoteflowApp extends StatelessWidget {
  const NoteflowApp({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: app,
      child: Consumer<AppState>(
        builder: (context, app, _) {
          return MaterialApp(
            title: 'Noteflow',
            debugShowCheckedModeBanner: false,
            // R1-31: the theme was never bound before — all 4 modes are
            // computed from AppTheme.build and applied directly.
            theme: AppTheme.build(app.theme),
            themeMode: ThemeMode.light,
            home: _Root(app: app),
          );
        },
      ),
    );
  }
}

/// Root widget that observes app lifecycle and locks the vault when the app
/// is backgrounded (R1-9). Re-locks whenever the process is resumed, so notes
/// are never left open on a borrowed/unlocked device.
class _Root extends StatefulWidget {
  const _Root({required this.app});

  final AppState app;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          widget.app.onBackgrounded();
        } else if (state == AppLifecycleState.resumed) {
          widget.app.onResumed();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.app.loaded) {
      // Splash while bootstrap runs in the background (R1-16).
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Track any user interaction to reset the inactivity auto-lock timer (R1-9).
    return Listener(
      onPointerDown: (_) => widget.app.registerActivity(),
      behavior: HitTestBehavior.translucent,
      child: widget.app.hasMasterPassword && !widget.app.authenticated
          ? const LockScreen()
          : const HomeScreen(),
    );
  }
}
