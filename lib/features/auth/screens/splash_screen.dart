import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nobryo_eguas/core/database/sqlite_helper.dart';
import 'package:nobryo_eguas/core/services/sync_service.dart';
import 'package:nobryo_eguas/core/services/realtime_sync_service.dart';
import 'package:nobryo_eguas/features/auth/widgets/auth_wrapper.dart';
import 'package:nobryo_eguas/core/services/auth_service.dart';
import 'package:nobryo_eguas/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initializeAppAndRedirect();
  }

  Future<void> _initializeAppAndRedirect() async {
    await WidgetsFlutterBinding.ensureInitialized();
    
    final syncService = Provider.of<SyncService>(context, listen: false);
    final realtimeSyncService = Provider.of<RealtimeSyncService>(context, listen: false);

    final prefs = await SharedPreferences.getInstance();
    final String? sessionTimestampStr = prefs.getString('session_timestamp');
    final String? sessionUserId = prefs.getString('session_user_id');

    if (sessionTimestampStr != null && sessionUserId != null) {
      final loginTime = DateTime.parse(sessionTimestampStr);
      final currentTime = DateTime.now();
      final difference = currentTime.difference(loginTime);

      if (difference.inHours < 8) {
        try {
          final users = await SQLiteHelper.instance.getAllUsers();
          final user = users.firstWhere((u) => u.uid == sessionUserId);
          
          _authService.currentUserNotifier.value = user;

          realtimeSyncService.startListeners();
          
          await syncService.syncData(isManual: false);

        } catch (e) {
          await _authService.signOut(context);
        }
      } else {
        await _authService.signOut(context);
      }
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthWrapper(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkGreen,
      body: Center(
        child: SizedBox(
          width: 250,
          child: Image.asset('assets/images/nobryoSemFundo.png'),
        ),
      ),
    );
  }
}