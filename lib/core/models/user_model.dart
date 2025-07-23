import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String nome;
  final String username;
  final String crmv;
  String? password;
  String? statusSync;
  String? photoUrl;
  bool isDeleted; // Adicionado para o soft delete

  AppUser({
    required this.uid,
    required this.nome,
    required this.username,
    required this.crmv,
    this.password,
    this.statusSync = 'pending_create',
    this.photoUrl,
    this.isDeleted = false, // Valor padrão é falso
  });

  /// Converte o objeto para um Map para o banco de dados local (SQLite).
  Map<String, dynamic> toMapForDb() {
    return {
      'uid': uid,
      'nome': nome,
      'username': username,
      'crmv': crmv,
      'password': password,
      'statusSync': statusSync,
      'photoUrl': photoUrl,
      'isDeleted': isDeleted ? 1 : 0, // Converte booleano para inteiro
    };
  }

  /// Cria um objeto AppUser a partir de um Map vindo do banco de dados local (SQLite).
  factory AppUser.fromDbMap(Map<String, dynamic> map) {
    return AppUser(
      uid: map['uid'],
      nome: map['nome'] ?? '',
      username: map['username'] ?? '',
      crmv: map['crmv'] ?? '',
      password: map['password'],
      statusSync: map['statusSync'],
      photoUrl: map['photoUrl'],
      isDeleted: map['isDeleted'] == 1, // Converte inteiro para booleano
    );
  }

  /// Converte o objeto para um Map para ser enviado ao Firebase/Firestore.
  Map<String, dynamic> toMapForFirebase() {
    return {
      'uid': uid,
      'nome': nome,
      'username': username,
      'crmv': crmv,
      'password_backup': password, // Por segurança, não enviamos a senha diretamente
      'photoUrl': photoUrl,
      'isDeleted': isDeleted, // Envia o valor booleano diretamente
    };
  }

  /// Cria um objeto AppUser a partir de um DocumentSnapshot do Firestore.
  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      nome: data['nome'] ?? '',
      username: data['username'] ?? '',
      crmv: data['crmv'] ?? '',
      password: data['password_backup'],
      photoUrl: data['photoUrl'],
      isDeleted: data['isDeleted'] ?? false, // Lê o valor do Firestore
      statusSync: 'synced',
    );
  }

  /// Cria uma cópia do objeto AppUser, permitindo a modificação de alguns campos.
  AppUser copyWith({
    String? uid,
    String? nome,
    String? username,
    String? crmv,
    String? password,
    String? statusSync,
    String? photoUrl,
    bool? isDeleted,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      nome: nome ?? this.nome,
      username: username ?? this.username,
      crmv: crmv ?? this.crmv,
      password: password ?? this.password,
      statusSync: statusSync ?? this.statusSync,
      photoUrl: photoUrl ?? this.photoUrl,
      isDeleted: isDeleted ?? this.isDeleted, // Adicionado ao copyWith
    );
  }
}