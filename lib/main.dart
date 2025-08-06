import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobryo_final/features/auth/screens/splash_screen.dart';
import 'package:nobryo_final/core/services/notification_service.dart';
import 'package:nobryo_final/core/services/realtime_sync_service.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:provider/provider.dart';
import 'core/api/firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await initializeDateFormatting('pt_BR', null);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SyncService()),
        
        Provider(
          create: (context) => RealtimeSyncService(
            Provider.of<SyncService>(context, listen: false),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Nobryo',
        theme: AppTheme.theme,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      ),
    );
  }
}