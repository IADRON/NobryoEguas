import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String?> uploadProfilePhoto(String filePath, String userId) async {
    try {
      final file = File(filePath);
      final fileExtension = filePath.split('.').last;
      final fileName = '${const Uuid().v4()}.$fileExtension';
      final ref = _storage.ref('profile_photos/$userId/$fileName');
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask.whenComplete(() => {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Erro ao fazer upload da foto de perfil: $e');
      return null;
    }
  }
}