// import 'dart:io';
import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
import 'package:nobryo_eguas/core/models/user_model.dart';
import 'package:nobryo_eguas/core/services/auth_service.dart';
// import 'package:nobryo_eguas/shared/theme/theme.dart';

class EditProfileScreen extends StatefulWidget {
  final AppUser user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _usernameController;
  late final TextEditingController _crmvController;
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _newPhotoPath;
  bool _isUsernameReadOnly = false;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.user.nome);
    _usernameController = TextEditingController(text: widget.user.username);
    _crmvController = TextEditingController(text: widget.user.crmv);

    if (widget.user.username == 'admin' || widget.user.username == 'Bruna') {
      _isUsernameReadOnly = true;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _usernameController.dispose();
    _crmvController.dispose();
    super.dispose();
  }

/*  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (image != null && mounted) {
      setState(() {
        _newPhotoPath = image.path;
      });
    }
  }
*/
  Future<void> _saveChanges() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final updatedUser = widget.user.copyWith(
        nome: _nomeController.text.trim(),
        username: _usernameController.text.trim(),
        crmv: _crmvController.text.trim(),
        photoUrl: _newPhotoPath ?? widget.user.photoUrl,
      );

      final String? errorResult =
          await _authService.updateUserProfile(updatedUser);

      if (mounted) {
        setState(() => _isLoading = false);

        if (errorResult == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Perfil atualizado com sucesso!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorResult),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
/*    final String? imagePath = _newPhotoPath ?? widget.user.photoUrl;

    ImageProvider? backgroundImage;
    if (imagePath != null && imagePath.isNotEmpty) {
      if (imagePath.startsWith('http')) {
        backgroundImage = NetworkImage(imagePath);
      } else {
        backgroundImage = FileImage(File(imagePath));
      }
    }
*/
    return Scaffold(
      appBar: AppBar(
        title: const Text("Editar Perfil"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [

              /*

              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: AppTheme.lightGrey,
                      backgroundImage: backgroundImage,
                      child: (backgroundImage == null)
                          ? const Icon(
                              Icons.person,
                              size: 60,
                              color: AppTheme.darkGreen,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppTheme.brown,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              
              */

              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(labelText: 'Nome Completo'),
                validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _usernameController,
                readOnly: _isUsernameReadOnly,
                decoration: InputDecoration(
                  labelText: 'Usuário (para login)',
                  filled: _isUsernameReadOnly,
                  fillColor: _isUsernameReadOnly ? Colors.grey[300] : null,
                ),
                validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _crmvController,
                decoration: const InputDecoration(labelText: 'CRMV'),
                validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _saveChanges,
                        child: const Text('SALVAR ALTERAÇÕES'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}