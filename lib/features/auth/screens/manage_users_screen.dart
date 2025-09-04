import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nobryo_eguas/core/database/sqlite_helper.dart';
import 'package:nobryo_eguas/core/models/user_model.dart';
import 'package:nobryo_eguas/core/services/sync_service.dart';
import 'package:nobryo_eguas/features/auth/screens/signup_screen.dart';
import 'package:nobryo_eguas/core/services/auth_service.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  late Future<List<AppUser>> _usersFuture;
  final AuthService _authService = AuthService();
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _refreshUsers();
  }

  void _refreshUsers() {
    setState(() {
      _usersFuture = SQLiteHelper.instance.getAllUsers();
    });
  }

  Future<void> _autoSync() async {
    await _syncService.syncData(isManual: false);
    if (mounted) {
      _refreshUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gerenciar Usuários"),
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Erro: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Nenhum usuário cadastrado."));
          }

          final users = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final bool isAdminAccount =
                  user.username == 'admin' || user.username == 'Bruna';

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user.photoUrl != null &&
                            File(user.photoUrl!).existsSync()
                        ? FileImage(File(user.photoUrl!))
                        : null,
                    child: user.photoUrl == null ||
                            !File(user.photoUrl!).existsSync()
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(user.nome,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Usuário: ${user.username}"),
                      Text("CRMV: ${user.crmv}"),
                    ],
                  ),
                  trailing: isAdminAccount
                      ? null
                      : PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == 'view_data') {
                              _showUserDetails(context, user);
                            } else if (value == 'update_password') {
                              _showResetPasswordModal(context, user);
                            } else if (value == 'delete') {
                              _showDeleteConfirmationDialog(context, user);
                            }
                          },
                          itemBuilder: (BuildContext context) =>
                              <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'view_data',
                              child: ListTile(
                                leading: Icon(Icons.visibility_outlined),
                                title: Text('Ver dados'),
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'update_password',
                              child: ListTile(
                                leading: Icon(Icons.password_outlined),
                                title: Text('Atualizar senha'),
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: ListTile(
                                leading:
                                    Icon(Icons.delete_outline, color: Colors.red),
                                title: Text('Deletar',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ),
                          ],
                        ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(builder: (_) => const SignUpScreen()),
              )
              .then((_) => _refreshUsers());
        },
        child: const Icon(Icons.person_add_alt_1),
        tooltip: "Criar Novo Usuário",
      ),
    );
  }

  void _showUserDetails(BuildContext context, AppUser user) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: UserDetailsCard(user: user),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Deletar ${user.nome}?"),
        content: const Text(
            "Tem certeza que deseja deletar este usuário? Esta ação não pode ser desfeita."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // A função para deletar o usuário deve ser implementada no AuthService e no SQLiteHelper
              // Exemplo: await _authService.softDeleteUser(user.uid);
              if (mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Usuário deletado com sucesso!"),
                    backgroundColor: Colors.green,
                  ),
                );
                _autoSync();
              }
            },
            child: const Text("Deletar"),
          ),
        ],
      ),
    );
  }

  void _showResetPasswordModal(BuildContext context, AppUser user) {
    final formKey = GlobalKey<FormState>();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Resetar senha de ${user.nome}"),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: passwordController,
            decoration: const InputDecoration(labelText: "Nova Senha"),
            obscureText: true,
            validator: (v) => v!.length < 6 ? 'Mínimo 6 caracteres' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final success = await _authService.updatePassword(
                    user.uid, passwordController.text);
                if (mounted) {
                  _autoSync();
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? "Senha alterada com sucesso!"
                          : "Falha ao alterar senha."),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }
}

class UserDetailsCard extends StatelessWidget {
  final AppUser user;

  const UserDetailsCard({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage:
                user.photoUrl != null && File(user.photoUrl!).existsSync()
                    ? FileImage(File(user.photoUrl!))
                    : null,
            child: user.photoUrl == null || !File(user.photoUrl!).existsSync()
                ? const Icon(Icons.person, size: 50)
                : null,
          ),
          const SizedBox(height: 16),
          Text(user.nome,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Usuário: ${user.username}",
              style: TextStyle(color: Colors.grey[700], fontSize: 16)),
          const SizedBox(height: 4),
          Text("CRMV: ${user.crmv}",
              style: TextStyle(color: Colors.grey[700], fontSize: 16)),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("FECHAR"),
            ),
          )
        ],
      ),
    );
  }
}