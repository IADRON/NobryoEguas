import 'package:flutter/material.dart';
import 'package:nobryo_final/core/services/auth_service.dart';
import 'package:nobryo_final/features/auth/widgets/auth_background.dart';
import 'package:nobryo_final/features/auth/widgets/glass_container.dart';
import 'package:nobryo_final/core/services/sync_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final result = await _authService.signIn(
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        setState(() => _isLoading = false);
        if (result != null) {
          _showSnackBar(result);
        } else {
          SyncService().syncData();
        }
      }
    }
  }

  void _handleForgotPassword() {
    _showSnackBar(
        "Para recuperar a senha, entre em contato com o administrador.",
        isError: false,
      );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthBackground(
      child: GlassContainer(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: 200,
                  child: Image.asset('assets/images/nobryoSemFundo.png')),
              const SizedBox(height: 20),
              TextFormField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'Usuário',
                  labelStyle: TextStyle(color: Colors.black),
                  prefixIcon: Icon(Icons.person_outline, color: Colors.black),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Por favor, insira o usuário' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  labelStyle: TextStyle(color: Colors.black),
                  prefixIcon: Icon(Icons.lock_outline, color: Colors.black),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Por favor, insira a senha' : null,
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white,))
                    : ElevatedButton(
                        onPressed: () => _login(),
                        child: const Text('ENTRAR'),
                      ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: _handleForgotPassword,
                  child: const Text('Esqueci a senha',
                      style: TextStyle(color: Colors.white70)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}