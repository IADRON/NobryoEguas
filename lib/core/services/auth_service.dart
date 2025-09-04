import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nobryo_eguas/core/database/sqlite_helper.dart';
import 'package:nobryo_eguas/core/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nobryo_eguas/core/services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:nobryo_eguas/core/services/realtime_sync_service.dart';
import 'package:nobryo_eguas/core/services/storage_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SQLiteHelper _dbHelper = SQLiteHelper.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final StorageService _storageService = StorageService();

  final ValueNotifier<AppUser?> currentUserNotifier = ValueNotifier(null);

  static const String _sessionTimestampKey = 'session_timestamp';
  static const String _sessionUserIdKey = 'session_user_id';

  Future<String?> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final user = await _dbHelper.getUserByUsernameAndPassword(username, password);
      if (user != null) {
        
        try {
          await _firebaseAuth.signInAnonymously();
          print("Firebase anonymous sign-in successful. UID: ${_firebaseAuth.currentUser?.uid}");
        } catch (e) {
          print("Firebase anonymous sign-in failed: $e");
          return 'Falha ao conectar com o serviço online. Tente novamente.';
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_sessionTimestampKey, DateTime.now().toIso8601String());
        await prefs.setString(_sessionUserIdKey, user.uid);

        await SyncService().syncData(isManual: false);

        currentUserNotifier.value = user;
        return null;
      } else {
        return 'Usuário ou senha incorretos.';
      }
    } catch (e) {
      print("Erro no login: $e");
      return 'Ocorreu um erro. Tente novamente.';
    }
  }

  Future<void> signOut(BuildContext context) async {
    await _firebaseAuth.signOut();
    print("Firebase session signed out.");

    Provider.of<RealtimeSyncService>(context, listen: false).stopListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTimestampKey);
    await prefs.remove(_sessionUserIdKey);

    currentUserNotifier.value = null;
  }

  Future<String?> createUser({
    required String nome,
    required String username,
    required String password,
    required String crmv,
  }) async {
    try {
      final existingUser = await _dbHelper.getUserByUsername(username);
      if (existingUser != null) {
        return 'Nome de usuário indisponível.';
      }

      final newUser = AppUser(
        uid: const Uuid().v4(),
        nome: nome,
        username: username,
        password: password,
        crmv: crmv,
        statusSync: 'pending_create',
      );
      await _dbHelper.createUser(newUser);
      return null;
    } catch (e) {
      if (e.toString().contains('UNIQUE constraint failed')) {
        return 'Nome de usuário indisponível.';
      }
      print("Erro ao criar usuário: $e");
      return 'Ocorreu um erro ao criar a conta.';
    }
  }

  Future<bool> updatePassword(String uid, String newPassword) async {
    try {
       final users = await _dbHelper.getAllUsers();
       final AppUser user = users.firstWhere((u) => u.uid == uid);
       user.password = newPassword;
       user.statusSync = 'pending_create';
       
       await _dbHelper.updateUser(user);
       return true;
    } catch(e) {
      print("Erro ao resetar senha: $e");
      return false;
    }
  }

  Future<String?> updateUserProfile(AppUser updatedUser) async {
    try {
      if (updatedUser.username != currentUserNotifier.value?.username) {
        final existingUser = await _dbHelper.getUserByUsername(updatedUser.username);
        if (existingUser != null) {
          return 'Nome de usuário indisponível.';
        }
      }
      
      String? photoUrl = updatedUser.photoUrl;
      if (photoUrl != null && !photoUrl.startsWith('http')) {
        final file = File(photoUrl);
        if (await file.exists()) {
            final newPhotoUrl = await _storageService.uploadProfilePhoto(photoUrl, updatedUser.uid);
            if (newPhotoUrl != null) {
              photoUrl = newPhotoUrl;
            } else {
              return 'Erro ao fazer upload da foto.';
            }
        } else if (updatedUser.photoUrl != currentUserNotifier.value?.photoUrl) {
            return 'Arquivo de imagem não encontrado.';
        }
      }

      final userToSave = updatedUser.copyWith(
        photoUrl: photoUrl,
        statusSync: 'pending_update',
      );

      await _dbHelper.updateUser(userToSave);
      currentUserNotifier.value = userToSave;
      await SyncService().syncData(isManual: false);
      return null;
    } catch (e) {
      print("Erro ao atualizar perfil: $e");
      return "Ocorreu um erro desconhecido ao atualizar o perfil.";
    }
  }
}