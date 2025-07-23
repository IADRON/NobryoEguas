import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class Manejo {
  String id;
  String? firebaseId;
  String tipo;
  DateTime dataAgendada;
  String status;
  Map<String, dynamic> detalhes;

  String eguaId;
  String propriedadeId;
  
  String responsavelId;
  String? concluidoPorId;

  String statusSync;
  bool isDeleted;

  // Campos adicionados para "Controle Folicular"
  String? medicamentoId;
  String? inducao;
  DateTime? dataHoraInducao;


  Manejo({
    required this.id,
    this.firebaseId,
    required this.tipo,
    required this.dataAgendada,
    this.status = 'Agendado',
    required this.detalhes,
    required this.eguaId,
    required this.propriedadeId,
    required this.responsavelId,
    this.concluidoPorId,
    this.statusSync = 'pending_create',
    this.isDeleted = false,
    this.medicamentoId,
    this.inducao,
    this.dataHoraInducao,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebaseId': firebaseId,
      'tipo': tipo,
      'dataAgendada': dataAgendada.toIso8601String(),
      'status': status,
      'detalhes': jsonEncode(detalhes),
      'eguaId': eguaId,
      'propriedadeId': propriedadeId,
      'responsavelId': responsavelId,
      'concluidoPorId': concluidoPorId,
      'statusSync': statusSync,
      'isDeleted': isDeleted ? 1 : 0,
      'medicamentoId': medicamentoId,
      'inducao': inducao,
      'dataHoraInducao': dataHoraInducao?.toIso8601String(),
    };
  }

  factory Manejo.fromMap(Map<String, dynamic> map) {
    return Manejo(
      id: map['id'],
      firebaseId: map['firebaseId'],
      tipo: map['tipo'],
      dataAgendada: DateTime.parse(map['dataAgendada']),
      status: map['status'],
      detalhes:
          map['detalhes'] is String ? jsonDecode(map['detalhes']) : map['detalhes'],
      eguaId: map['eguaId'],
      propriedadeId: map['propriedadeId'],
      responsavelId: map['responsavelId'] ?? '',
      concluidoPorId: map['concluidoPorId'],
      statusSync: map['statusSync'],
      isDeleted: map['isDeleted'] == 1,
      medicamentoId: map['medicamentoId'],
      inducao: map['inducao'],
      dataHoraInducao: map['dataHoraInducao'] != null ? DateTime.parse(map['dataHoraInducao']) : null,
    );
  }

  Map<String, dynamic> toMapForFirebase(String eguaFirebaseId) {
    // Adiciona os novos campos ao mapa do Firebase
    final firebaseMap = {
      'idLocal': id,
      'tipo': tipo,
      'dataAgendada': dataAgendada,
      'status': status,
      'detalhes': detalhes,
      'eguaFirebaseId': eguaFirebaseId,
      'propriedadeId': propriedadeId,
      'responsavelId': responsavelId,
      'concluidoPorId': concluidoPorId,
    };

    if (medicamentoId != null) {
      firebaseMap['medicamentoId'] = medicamentoId;
    }
    if (inducao != null) {
      firebaseMap['inducao'] = inducao;
    }
    if (dataHoraInducao != null) {
      firebaseMap['dataHoraInducao'] = dataHoraInducao;
    }

    return firebaseMap;
  }

  factory Manejo.fromFirebaseMap(
      String firebaseId, String eguaId, Map<String, dynamic> map) {
    return Manejo(
      id: map['idLocal'] ?? firebaseId,
      firebaseId: firebaseId,
      eguaId: eguaId,
      propriedadeId: map['propriedadeId'] ?? '',
      tipo: map['tipo'] ?? '',
      dataAgendada: (map['dataAgendada'] as Timestamp).toDate(),
      status: map['status'] ?? 'Agendado',
      detalhes: map['detalhes'] ?? {},
      responsavelId: map['responsavelId'] ?? '',
      concluidoPorId: map['concluidoPorId'],
      statusSync: 'synced',
      // Adiciona os novos campos vindos do Firebase
      medicamentoId: map['medicamentoId'],
      inducao: map['inducao'],
      dataHoraInducao: (map['dataHoraInducao'] as Timestamp?)?.toDate(),
    );
  }

  Manejo copyWith({
    String? id,
    String? firebaseId,
    String? tipo,
    DateTime? dataAgendada,
    String? status,
    Map<String, dynamic>? detalhes,
    String? eguaId,
    String? propriedadeId,
    String? responsavelId,
    String? concluidoPorId,
    String? statusSync,
    bool? isDeleted,
    String? medicamentoId,
    String? inducao,
    DateTime? dataHoraInducao,
  }) {
    return Manejo(
      id: id ?? this.id,
      firebaseId: firebaseId ?? this.firebaseId,
      tipo: tipo ?? this.tipo,
      dataAgendada: dataAgendada ?? this.dataAgendada,
      status: status ?? this.status,
      detalhes: detalhes ?? this.detalhes,
      eguaId: eguaId ?? this.eguaId,
      propriedadeId: propriedadeId ?? this.propriedadeId,
      responsavelId: responsavelId ?? this.responsavelId,
      concluidoPorId: concluidoPorId ?? this.concluidoPorId,
      statusSync: statusSync ?? this.statusSync,
      isDeleted: isDeleted ?? this.isDeleted,
      medicamentoId: medicamentoId ?? this.medicamentoId,
      inducao: inducao ?? this.inducao,
      dataHoraInducao: dataHoraInducao ?? this.dataHoraInducao,
    );
  }
}