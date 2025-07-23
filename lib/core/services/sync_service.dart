// lib/core/services/sync_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/egua_model.dart';
import 'package:nobryo_final/core/models/manejo_model.dart';
import 'package:nobryo_final/core/models/medicamento_model.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/models/user_model.dart';
import 'package:collection/collection.dart';

class SyncService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SQLiteHelper _dbHelper = SQLiteHelper.instance;
  bool _isSyncing = false;

  Future<bool> syncData({bool isManual = false}) async {
    if (_isSyncing) {
      if (isManual) print("Sincronização já está em andamento.");
      return false;
    }
    _isSyncing = true;

    final connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      if (isManual) print("Sincronização manual falhou: sem internet.");
      _isSyncing = false;
      return false;
    }

    if (isManual) print("Iniciando sincronização de mão dupla...");
    try {
      await _syncUsers(isManual: isManual);
      await _syncPropriedades(isManual: isManual);
      await _syncEguas(isManual: isManual);
      await _syncMedicamentos(isManual: isManual);
      await _syncManejos(isManual: isManual);

      notifyListeners();
      
    } catch (e) {
      print("Erro durante a sincronização: $e");
    } finally {
      _isSyncing = false;
      if (isManual) print("Sincronização concluída.");
    }
    return true;
  }
  
  Future<void> _syncUsers({required bool isManual}) async {
    if (isManual) print("[Usuários] Sincronizando...");
    
    // Upload de dados locais para o Firebase
    final unsyncedLocal = await _dbHelper.getUnsyncedUsers();
    if (unsyncedLocal.isNotEmpty) {
      if (isManual) print("[Usuários] Enviando ${unsyncedLocal.length} registros...");
      final WriteBatch batch = _firestore.batch();
      for (var user in unsyncedLocal) {
        if (user.username == 'admin' || user.username == 'Bruna') continue;
        DocumentReference docRef = _firestore.collection('users').doc(user.uid);
        batch.set(docRef, user.toMapForFirebase(), SetOptions(merge: true));
        user.statusSync = 'synced';
        await _dbHelper.updateUser(user);
      }
      await batch.commit();
    }

    // Download de dados do Firebase para o local
    final remoteSnapshot = await _firestore.collection('users').get();
    final localUsers = await _dbHelper.getAllUsers();
    
    // Lógica para deletar usuários locais que não existem mais no Firebase
    final remoteUserIds = remoteSnapshot.docs.map((doc) => doc.id).toSet();
    for (final localUser in localUsers) {
        // Não deletar contas de administrador padrão
        if (localUser.username == 'admin' || localUser.username == 'Bruna') continue;
        
        if (!remoteUserIds.contains(localUser.uid)) {
            // Este usuário existe localmente, mas não no servidor, então deve ser deletado.
            // (Esta funcionalidade de deletar usuário não foi implementada, mas a lógica estaria aqui)
        }
    }

    final localUsersMap = { for (var u in localUsers) u.uid: u };
    int newRecords = 0;
    int updatedRecords = 0;
    for (final doc in remoteSnapshot.docs) {
      final remoteUser = AppUser.fromFirestore(doc);
      final localUser = localUsersMap[remoteUser.uid];
      if (localUser == null) {
        await _dbHelper.createUser(remoteUser);
        newRecords++;
      } else {
        if (localUser.nome != remoteUser.nome || localUser.crmv != remoteUser.crmv || localUser.photoUrl != remoteUser.photoUrl) {
           await _dbHelper.updateUser(remoteUser.copyWith(statusSync: 'synced'));
           updatedRecords++;
        }
      }
    }
    if (isManual && newRecords > 0) print("[Usuários] $newRecords novos registros baixados.");
    if (isManual && updatedRecords > 0) print("[Usuários] $updatedRecords registros atualizados.");
  }

  Future<void> _syncPropriedades({required bool isManual}) async {
    if (isManual) print("[Propriedades] Sincronizando...");
    
    // Upload de exclusões para o Firebase
    final deletedProps = await _dbHelper.getDeletedPropriedades();
    if(deletedProps.isNotEmpty) {
      if (isManual) print("[Propriedades] Deletando ${deletedProps.length} registros no Firebase...");
      WriteBatch deleteBatch = _firestore.batch();
      for (var prop in deletedProps) {
        if (prop.firebaseId != null) {
          deleteBatch.delete(_firestore.collection('propriedades').doc(prop.firebaseId!));
        }
      }
      await deleteBatch.commit();
      for (var prop in deletedProps) {
        await _dbHelper.permanentlyDeletePropriedade(prop.id);
      }
    }

    // Upload de criações/atualizações para o Firebase
    final unsyncedLocal = await _dbHelper.getUnsyncedPropriedades();
    if (unsyncedLocal.isNotEmpty) {
      if (isManual) print("[Propriedades] Enviando ${unsyncedLocal.length} registros...");
      final WriteBatch batch = _firestore.batch();
      for (var prop in unsyncedLocal) {
        DocumentReference docRef = _firestore.collection('propriedades').doc(prop.firebaseId ?? prop.id);
        batch.set(docRef, {'nome': prop.nome, 'dono': prop.dono, 'idLocal': prop.id}, SetOptions(merge: true));
        prop.firebaseId = docRef.id;
        prop.statusSync = 'synced';
        await _dbHelper.updatePropriedade(prop);
      }
      await batch.commit();
    }

    // Download de dados e tratamento de exclusões remotas
    final remoteSnapshot = await _firestore.collection('propriedades').get();
    final localProps = await _dbHelper.readAllPropriedades();
    
    final remoteFirebaseIds = remoteSnapshot.docs.map((doc) => doc.id).toSet();
    for (final localProp in localProps) {
        if (localProp.firebaseId != null && 
            !remoteFirebaseIds.contains(localProp.firebaseId) && 
            localProp.statusSync != 'pending_delete') {
            if (isManual) print("[Propriedades] Removendo propriedade '${localProp.nome}' deletada remotamente.");
            await _dbHelper.permanentlyDeletePropriedade(localProp.id);
        }
    }

    final updatedLocalProps = await _dbHelper.readAllPropriedades();
    final Map<String, Propriedade> localPropsMap = {
      for (var p in updatedLocalProps) if (p.firebaseId != null) p.firebaseId!: p
    };
    int newRecords = 0;
    int updatedRecords = 0;
    for (final doc in remoteSnapshot.docs) {
      final remoteData = doc.data();
      final remoteProp = Propriedade.fromMap({
        'id': remoteData['idLocal'] ?? doc.id,
        'firebaseId': doc.id,
        'nome': remoteData['nome'] ?? '',
        'dono': remoteData['dono'] ?? '',
        'statusSync': 'synced',
        'isDeleted': 0
      });
      final localProp = localPropsMap[doc.id];
      if (localProp == null) {
        await _dbHelper.createPropriedade(remoteProp);
        newRecords++;
      } else {
        if (localProp.nome != remoteProp.nome || localProp.dono != remoteProp.dono) {
          await _dbHelper.updatePropriedade(remoteProp.copyWith(id: localProp.id));
          updatedRecords++;
        }
      }
    }
    if (isManual && newRecords > 0) print("[Propriedades] $newRecords novos registros baixados.");
    if (isManual && updatedRecords > 0) print("[Propriedades] $updatedRecords registros atualizados.");
  }

  Future<void> _syncEguas({required bool isManual}) async {
    if (isManual) print("[Éguas] Sincronizando...");

    // Upload de exclusões para o Firebase
    final deletedEguas = await _dbHelper.getDeletedEguas();
    if (deletedEguas.isNotEmpty) {
      if (isManual) print("[Éguas] Deletando ${deletedEguas.length} registros no Firebase...");
      WriteBatch deleteBatch = _firestore.batch();
      for (var egua in deletedEguas) {
        if (egua.firebaseId != null) {
          deleteBatch.delete(_firestore.collection('eguas').doc(egua.firebaseId!));
        }
      }
      await deleteBatch.commit();
      for (var egua in deletedEguas) {
        await _dbHelper.permanentlyDeleteEgua(egua.id);
      }
    }

    // Upload de criações/atualizações para o Firebase
    final unsyncedEguas = await _dbHelper.getUnsyncedEguas();
    if (unsyncedEguas.isNotEmpty) {
       if (isManual) print("[Éguas] Enviando ${unsyncedEguas.length} registros...");
      final WriteBatch batch = _firestore.batch();
      for (var egua in unsyncedEguas) {
        final prop = await _dbHelper.readPropriedade(egua.propriedadeId);
        if (prop?.firebaseId == null) continue;
        DocumentReference docRef = _firestore.collection('eguas').doc(egua.firebaseId ?? egua.id);
        batch.set(docRef, egua.toMapForFirebase(prop!.firebaseId!), SetOptions(merge: true));
        egua.firebaseId = docRef.id;
        egua.statusSync = 'synced';
        await _dbHelper.updateEgua(egua);
      }
      await batch.commit();
    }

    // Download de dados e tratamento de exclusões remotas
    final remoteSnapshot = await _firestore.collection('eguas').get();
    final localEguas = await _dbHelper.getAllEguas();

    final remoteFirebaseIds = remoteSnapshot.docs.map((doc) => doc.id).toSet();
    for (final localEgua in localEguas) {
        if (localEgua.firebaseId != null && 
            !remoteFirebaseIds.contains(localEgua.firebaseId) && 
            localEgua.statusSync != 'pending_delete') {
            if (isManual) print("[Éguas] Removendo égua '${localEgua.nome}' deletada remotamente.");
            await _dbHelper.permanentlyDeleteEgua(localEgua.id);
        }
    }
    
    final updatedLocalEguas = await _dbHelper.getAllEguas();
    final Map<String, Egua> localEguasMap = {
        for (var e in updatedLocalEguas) if (e.firebaseId != null) e.firebaseId!: e
    };
    int newRecords = 0;
    int updatedRecords = 0;
    for (final doc in remoteSnapshot.docs) {
        final remoteData = doc.data();
        if (remoteData['propriedadeFirebaseId'] == null) continue;
        final propIdLocal = await _dbHelper.findPropriedadeIdByFirebaseId(remoteData['propriedadeFirebaseId']);
        if (propIdLocal == null) continue;
        final remoteEgua = Egua.fromFirebaseMap(doc.id, propIdLocal, remoteData);
        final localEgua = localEguasMap[doc.id];
        if (localEgua == null) {
            await _dbHelper.createEgua(remoteEgua);
            newRecords++;
        } else {
            if (localEgua.nome != remoteEgua.nome ||
                localEgua.rp != remoteEgua.rp ||
                localEgua.pelagem != remoteEgua.pelagem ||
                localEgua.cobertura != remoteEgua.cobertura ||
                localEgua.dataParto?.toIso8601String() != remoteEgua.dataParto?.toIso8601String() ||
                localEgua.sexoPotro != remoteEgua.sexoPotro ||
                localEgua.statusReprodutivo != remoteEgua.statusReprodutivo ||
                localEgua.diasPrenhe != remoteEgua.diasPrenhe ||
                localEgua.observacao != remoteEgua.observacao)
            {
                await _dbHelper.updateEgua(remoteEgua.copyWith(id: localEgua.id));
                updatedRecords++;
            }
        }
    }
    if (isManual && newRecords > 0) print("[Éguas] $newRecords novos registros baixados.");
    if (isManual && updatedRecords > 0) print("[Éguas] $updatedRecords registros atualizados.");
  }
  
  Future<void> _syncMedicamentos({required bool isManual}) async {
    if (isManual) print("[Medicamentos] Sincronizando...");

    // Upload de exclusões para o Firebase
    final deletedMeds = await _dbHelper.getDeletedMedicamentos();
    if (deletedMeds.isNotEmpty) {
      if (isManual) print("[Medicamentos] Deletando ${deletedMeds.length} registros no Firebase...");
      WriteBatch deleteBatch = _firestore.batch();
      for (var med in deletedMeds) {
        if (med.firebaseId != null) deleteBatch.delete(_firestore.collection('medicamentos').doc(med.firebaseId!));
      }
      await deleteBatch.commit();
      for (var med in deletedMeds) {
        await _dbHelper.permanentlyDeleteMedicamento(med.id);
      }
    }

    // Upload de criações/atualizações para o Firebase
    final unsyncedMedicamentos = await _dbHelper.getUnsyncedMedicamentos();
    if (unsyncedMedicamentos.isNotEmpty) {
      if (isManual) print("[Medicamentos] Enviando ${unsyncedMedicamentos.length} registros...");
      WriteBatch createUpdateBatch = _firestore.batch();
      for (var med in unsyncedMedicamentos) {
        DocumentReference docRef = _firestore.collection('medicamentos').doc(med.firebaseId ?? med.id);
        createUpdateBatch.set(docRef, {'nome': med.nome, 'descricao': med.descricao, 'idLocal': med.id}, SetOptions(merge: true));
        med.firebaseId = docRef.id;
        med.statusSync = 'synced';
        await _dbHelper.updateMedicamento(med);
      }
      await createUpdateBatch.commit();
    }

    // Download de dados e tratamento de exclusões remotas
    final remoteSnapshot = await _firestore.collection('medicamentos').get();
    final localMeds = await _dbHelper.readAllMedicamentos();

    final remoteFirebaseIds = remoteSnapshot.docs.map((doc) => doc.id).toSet();
    for(final localMed in localMeds) {
        if (localMed.firebaseId != null &&
            !remoteFirebaseIds.contains(localMed.firebaseId) &&
            localMed.statusSync != 'pending_delete') {
            if (isManual) print("[Medicamentos] Removendo medicamento '${localMed.nome}' deletado remotamente.");
            await _dbHelper.permanentlyDeleteMedicamento(localMed.id);
        }
    }
    
    final updatedLocalMeds = await _dbHelper.readAllMedicamentos();
    final Map<String, Medicamento> localMedsMap = {
        for (var m in updatedLocalMeds) if (m.firebaseId != null) m.firebaseId!: m
    };
    int newRecords = 0;
    int updatedRecords = 0;
    for (var doc in remoteSnapshot.docs) {
      final remoteData = doc.data();
      final remoteMed = Medicamento.fromMap({
        ...remoteData,
        'id': remoteData['idLocal'] ?? doc.id,
        'firebaseId': doc.id,
        'statusSync': 'synced',
        'isDeleted': 0
      });
      final localMed = localMedsMap[doc.id];
      if (localMed == null) {
        await _dbHelper.createMedicamento(remoteMed);
        newRecords++;
      } else {
        if (localMed.nome != remoteMed.nome || localMed.descricao != remoteMed.descricao) {
          await _dbHelper.updateMedicamento(remoteMed.copyWith(id: localMed.id));
          updatedRecords++;
        }
      }
    }
     if (isManual && newRecords > 0) print("[Medicamentos] $newRecords novos registros baixados.");
     if (isManual && updatedRecords > 0) print("[Medicamentos] $updatedRecords registros atualizados.");
  }

  Future<void> _syncManejos({required bool isManual}) async {
    if (isManual) print("[Manejos] Sincronizando...");

    // Upload de exclusões para o Firebase
    final deletedManejos = await _dbHelper.getDeletedManejos();
    if(deletedManejos.isNotEmpty) {
      if (isManual) print("[Manejos] Deletando ${deletedManejos.length} registros no Firebase...");
      WriteBatch batch = _firestore.batch();
      for (var manejo in deletedManejos) {
        if (manejo.firebaseId != null) batch.delete(_firestore.collection('manejos').doc(manejo.firebaseId!));
      }
      await batch.commit();
      for (var manejo in deletedManejos) {
        await _dbHelper.permanentlyDeleteManejo(manejo.id);
      }
    }

    // Upload de criações/atualizações para o Firebase
    final unsyncedManejos = await _dbHelper.getUnsyncedManejos();
    if (unsyncedManejos.isNotEmpty) {
       if (isManual) print("[Manejos] Enviando ${unsyncedManejos.length} registros...");
      WriteBatch batch = _firestore.batch();
      for (var manejo in unsyncedManejos) {
        final egua = await _dbHelper.getEguaById(manejo.eguaId);
        if (egua?.firebaseId == null) continue;
        DocumentReference docRef = _firestore.collection('manejos').doc(manejo.firebaseId ?? manejo.id);
        batch.set(docRef, manejo.toMapForFirebase(egua!.firebaseId!), SetOptions(merge: true));
        manejo.firebaseId = docRef.id;
        manejo.statusSync = 'synced';
        await _dbHelper.updateManejo(manejo);
      }
      await batch.commit();
    }
    
    // Download de dados e tratamento de exclusões remotas
    final remoteSnapshot = await _firestore.collection('manejos').get();
    final localManejos = await _dbHelper.getAllEguasManejos();

    final remoteFirebaseIds = remoteSnapshot.docs.map((doc) => doc.id).toSet();
    for (final localManejo in localManejos) {
        if(localManejo.firebaseId != null &&
           !remoteFirebaseIds.contains(localManejo.firebaseId) &&
           localManejo.statusSync != 'pending_delete') {
            if (isManual) print("[Manejos] Removendo manejo '${localManejo.tipo}' do dia '${localManejo.dataAgendada}' deletado remotamente.");
            await _dbHelper.permanentlyDeleteManejo(localManejo.id);
        }
    }

    final updatedLocalManejos = await _dbHelper.getAllEguasManejos();
    final Map<String, Manejo> localManejosMap = {
        for (var m in updatedLocalManejos) if (m.firebaseId != null) m.firebaseId!: m
    };
    final allLocalUserUids = (await _dbHelper.getAllUsers()).map((u) => u.uid).toSet();
    int newRecords = 0;
    int updatedRecords = 0;
    int skippedRecords = 0;
    for (var doc in remoteSnapshot.docs) {
      final remoteData = doc.data();
      if (remoteData['eguaFirebaseId'] == null) { skippedRecords++; continue; }
      final eguaIdLocal = await _dbHelper.findEguaIdByFirebaseId(remoteData['eguaFirebaseId']);
      if (eguaIdLocal == null) { skippedRecords++; continue; }
      final Egua? eguaLocal = await _dbHelper.getEguaById(eguaIdLocal);
      if (eguaLocal == null) { skippedRecords++; continue; }
      final responsavelId = remoteData['responsavelId'] as String?;
      if (responsavelId == null || !allLocalUserUids.contains(responsavelId)) { skippedRecords++; continue; }
      final concluidoPorId = remoteData['concluidoPorId'] as String?;
      if (concluidoPorId != null && !allLocalUserUids.contains(concluidoPorId)) { skippedRecords++; continue; }
      final remoteManejo = Manejo.fromFirebaseMap(doc.id, eguaIdLocal, remoteData);
      remoteManejo.propriedadeId = eguaLocal.propriedadeId;
      final localManejo = localManejosMap[doc.id];
      if (localManejo == null) {
        await _dbHelper.createManejo(remoteManejo);
        newRecords++;
      } else {
        if (localManejo.tipo != remoteManejo.tipo ||
            localManejo.dataAgendada.toIso8601String() != remoteManejo.dataAgendada.toIso8601String() ||
            localManejo.status != remoteManejo.status ||
            localManejo.responsavelId != remoteManejo.responsavelId ||
            localManejo.concluidoPorId != remoteManejo.concluidoPorId ||
            !const DeepCollectionEquality().equals(localManejo.detalhes, remoteManejo.detalhes))
        {
          await _dbHelper.updateManejo(remoteManejo.copyWith(id: localManejo.id));
          updatedRecords++;
        }
      }
    }
    if (isManual && newRecords > 0) print("[Manejos] $newRecords novos registros baixados.");
    if (isManual && updatedRecords > 0) print("[Manejos] $updatedRecords registros atualizados.");
    if (isManual && skippedRecords > 0) print("[Manejos] $skippedRecords registros ignorados por inconsistência de dados.");
  }
}