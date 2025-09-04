import 'package:flutter/material.dart';
import 'package:nobryo_eguas/core/services/auth_service.dart';
import 'package:nobryo_eguas/features/auth/widgets/glass_container.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _crmvController = TextEditingController();
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

  Future<void> _createUser() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final result = await _authService.createUser(
        nome: _nomeController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        crmv: _crmvController.text.trim(),
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (result != null) {
          _showSnackBar(result);
        } else {
          _showSnackBar("Conta criada com sucesso!", isError: false);
          Navigator.of(context).pop();
        }
      }
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _usernameController.dispose();
    _crmvController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/images/login_screen.jpg"),
          fit: BoxFit.cover,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Criar Novo Usuário"),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: GlassContainer(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nomeController,
                        style: const TextStyle(color: Colors.black),
                        decoration: const InputDecoration(
                            labelText: 'Nome Completo',
                            labelStyle: TextStyle(color: Colors.black)),
                        validator: (v) =>
                            v!.isEmpty ? 'Campo obrigatório' : null,
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _usernameController,
                        style: const TextStyle(color: Colors.black),
                        decoration: const InputDecoration(
                            labelText: 'Usuário (para login)',
                            labelStyle: TextStyle(color: Colors.black)),
                        validator: (v) =>
                            v!.isEmpty ? 'Campo obrigatório' : null,
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _crmvController,
                        style: const TextStyle(color: Colors.black),
                        decoration: const InputDecoration(
                            labelText: 'CRMV',
                            labelStyle: TextStyle(color: Colors.black)),
                        validator: (v) =>
                            v!.isEmpty ? 'Campo obrigatório' : null,
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.black),
                        decoration: const InputDecoration(
                            labelText: 'Senha',
                            labelStyle: TextStyle(color: Colors.black)),
                        validator: (v) => v!.length < 6
                            ? 'A senha deve ter no mínimo 6 caracteres'
                            : null,
                      ),
                      const SizedBox(height: 25),
                      SizedBox(
                        width: double.infinity,
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: () => _createUser(),
                                child: const Text('CRIAR USUÁRIO'),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}