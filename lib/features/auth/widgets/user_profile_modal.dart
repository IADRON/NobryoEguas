import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nobryo_final/core/models/user_model.dart';
import 'package:nobryo_final/features/auth/screens/edit_profile_screen.dart';
import 'package:nobryo_final/core/services/auth_service.dart';
import 'package:nobryo_final/shared/theme/theme.dart';

void showUserProfileModal(BuildContext context) {
  final authService = AuthService();
  final user = authService.currentUserNotifier.value;

  if (user == null) return;

  ImageProvider? backgroundImage;
  if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
    if (user.photoUrl!.startsWith('http')) {
      backgroundImage = NetworkImage(user.photoUrl!);
    } else {
      backgroundImage = FileImage(File(user.photoUrl!));
    }
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        padding: const EdgeInsets.all(24.0),
        decoration: const BoxDecoration(
          color: AppTheme.offWhite,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppTheme.lightGrey,
                  backgroundImage: backgroundImage,
                  child: (backgroundImage == null)
                      ? const Icon(
                          Icons.person,
                          size: 45,
                          color: AppTheme.darkGreen,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.nome,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text("Usuário: ${user.username}",
                          style: TextStyle(color: Colors.grey[700])),
                      const SizedBox(height: 4),
                      Text("CRMV: ${user.crmv}",
                          style: TextStyle(color: Colors.grey[700])),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppTheme.brown),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showPasswordConfirmationDialog(context, user);
                  },
                )
              ],
            ),
            const Divider(height: 30),
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.darkText),
              title: const Text("Sair do Aplicativo",
                  style: TextStyle(color: AppTheme.darkText)),
              onTap: () {
                Navigator.of(ctx).pop();
                authService.signOut(context);
              },
            )
          ],
        ),
      );
    },
  );
}

void _showPasswordConfirmationDialog(BuildContext context, AppUser user) {
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final authService = AuthService();

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Confirmar Identidade"),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                "Para editar seu perfil, por favor, insira sua senha novamente."),
            const SizedBox(height: 15),
            TextFormField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Senha"),
              validator: (v) => v!.isEmpty ? "Senha obrigatória" : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text("Cancelar"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
          onPressed: () async {
            if (formKey.currentState!.validate()) {
              final result = await authService.signIn(
                username: user.username,
                password: passwordController.text,
              );

              if (result == null && context.mounted) {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(user: user),
                  ),
                );
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Senha incorreta. Tente novamente."),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          child: const Text("Confirmar"),
        )
      ],
    ),
  );
}