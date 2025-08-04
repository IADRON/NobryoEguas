import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class Manejo {
  String id;
  String? firebaseId;
  String tipo;
  DateTime dataAgendada;
  DateTime? dataConclusao;
  String status;
  Map<String, dynamic> detalhes;

  String eguaId;
  String propriedadeId;
  
  String? responsavelId;
  String? concluidoPorId;

  String? responsavelPeaoId;
  String? concluidoPorPeaoId;

  String statusSync;
  bool isDeleted;
  bool isAtrasado;

  String? medicamentoId;
  String? inducao;
  DateTime? dataHoraInducao;


  Manejo({
    required this.id,
    this.firebaseId,
    required this.tipo,
    required this.dataAgendada,
    this.status = 'Agendado',
    this.dataConclusao,
    required this.detalhes,
    required this.eguaId,
    required this.propriedadeId,
    this.responsavelId,
    this.concluidoPorId,
    this.responsavelPeaoId,
    this.concluidoPorPeaoId,
    this.statusSync = 'pending_create',
    this.isDeleted = false,
    this.isAtrasado = false,
    this.medicamentoId,
    this.inducao,
    this.dataHoraInducao,
  });

  // Método para o banco de dados local (SQLite)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebaseId': firebaseId,
      'tipo': tipo,
      'dataAgendada': dataAgendada.toIso8601String(),
      'dataConclusao': dataConclusao?.toIso8601String(),
      'status': status,
      'detalhes': jsonEncode(detalhes),
      'eguaId': eguaId,
      'propriedadeId': propriedadeId,
      'responsavelId': responsavelId,
      'concluidoPorId': concluidoPorId,
      'responsavelPeaoId': responsavelPeaoId,
      'concluidoPorPeaoId': concluidoPorPeaoId,
      'statusSync': statusSync,
      'isDeleted': isDeleted ? 1 : 0,
      'isAtrasado': isAtrasado ? 1 : 0,
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
      dataConclusao: map['dataConclusao'] != null ? DateTime.parse(map['dataConclusao']) : null,
      status: map['status'],
      detalhes:
          map['detalhes'] is String ? jsonDecode(map['detalhes']) : map['detalhes'],
      eguaId: map['eguaId'],
      propriedadeId: map['propriedadeId'],
      responsavelId: map['responsavelId'],
      concluidoPorId: map['concluidoPorId'],
      responsavelPeaoId: map['responsavelPeaoId'],
      concluidoPorPeaoId: map['concluidoPorPeaoId'],
      statusSync: map['statusSync'],
      isDeleted: map['isDeleted'] == 1,
      isAtrasado: map['isAtrasado'] == 1,
      medicamentoId: map['medicamentoId'],
      inducao: map['inducao'],
      dataHoraInducao: map['dataHoraInducao'] != null ? DateTime.parse(map['dataHoraInducao']) : null,
    );
  }

  Map<String, dynamic> toMapForFirebase(String eguaFirebaseId) {
    final firebaseMap = {
      'idLocal': id,
      'tipo': tipo,
      'dataAgendada': dataAgendada,
      'dataConclusao': dataConclusao,
      'status': status,
      'detalhes': detalhes,
      'eguaFirebaseId': eguaFirebaseId,
      'propriedadeId': propriedadeId,
      'responsavelId': responsavelId,
      'concluidoPorId': concluidoPorId,
      'responsavelPeaoId': responsavelPeaoId,
      'concluidoPorPeaoId': concluidoPorPeaoId,
    };

    if (medicamentoId != null) firebaseMap['medicamentoId'] = medicamentoId;
    if (inducao != null) firebaseMap['inducao'] = inducao;
    if (dataHoraInducao != null) firebaseMap['dataHoraInducao'] = dataHoraInducao;

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
      dataConclusao: (map['dataConclusao'] as Timestamp?)?.toDate(),
      status: map['status'] ?? 'Agendado',
      detalhes: map['detalhes'] ?? {},
      responsavelId: map['responsavelId'],
      concluidoPorId: map['concluidoPorId'],
      responsavelPeaoId: map['responsavelPeaoId'],
      concluidoPorPeaoId: map['concluidoPorPeaoId'],
      statusSync: 'synced',
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
    String? responsavelPeaoId,
    String? concluidoPorPeaoId,
    String? statusSync,
    bool? isDeleted,
    bool? isAtrasado,
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
      responsavelPeaoId: responsavelPeaoId ?? this.responsavelPeaoId,
      concluidoPorPeaoId: concluidoPorPeaoId ?? this.concluidoPorPeaoId,
      statusSync: statusSync ?? this.statusSync,
      isDeleted: isDeleted ?? this.isDeleted,
      isAtrasado: isAtrasado ?? this.isAtrasado,
      medicamentoId: medicamentoId ?? this.medicamentoId,
      inducao: inducao ?? this.inducao,
      dataHoraInducao: dataHoraInducao ?? this.dataHoraInducao,
    );
  }
}