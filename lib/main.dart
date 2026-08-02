import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/database.dart';
import 'data/repository.dart';
import 'screens/home_screen.dart';
import 'widgets/lock_screen.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final db = AppDatabase();
  final repo = NoteRepository(db);
  final app = AppState(repo, settings);
  await app.bootstrap();
  runApp(NoteflowApp(app: app));
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
            home: app.hasMasterPassword && !app.authenticated
                ? const LockScreen()
                : const HomeScreen(),
          );
        },
      ),
    );
  }
}
