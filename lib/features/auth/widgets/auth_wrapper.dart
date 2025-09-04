import 'package:flutter/material.dart';
import 'package:nobryo_eguas/core/models/user_model.dart';
import 'package:nobryo_eguas/features/auth/screens/login_screen.dart';
import 'package:nobryo_eguas/core/services/auth_service.dart';
import 'package:nobryo_eguas/main_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: AuthService().currentUserNotifier,
      builder: (context, user, _) {
        if (user != null) {
          return const MainScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}