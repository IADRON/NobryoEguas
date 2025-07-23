// lib/core/services/realtime_sync_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nobryo_final/core/services/sync_service.dart';

class RealtimeSyncService {
  final SyncService _syncService;
  final List<StreamSubscription> _subscriptions = [];

  // O serviço recebe a instância do SyncService para poder chamá-lo
  RealtimeSyncService(this._syncService);

  void startListeners() {
    // Evita iniciar múltiplos ouvintes
    if (_subscriptions.isNotEmpty) {
      print(">> RealtimeSyncService: Ouvintes já iniciados.");
      return;
    }

    print(">> RealtimeSyncService: Iniciando ouvintes do Firebase...");

    // Ouvinte para a coleção 'manejos'
    final manejosSub = FirebaseFirestore.instance.collection('manejos').snapshots().listen((snapshot) {
      if (snapshot.docChanges.isNotEmpty) {
        print(">> RealtimeSyncService: Mudança detectada em 'manejos'! Sincronizando...");
        _syncService.syncData(isManual: false);
      }
    }, onError: (e) => print("Erro no ouvinte de manejos: $e"));
    _subscriptions.add(manejosSub);

    // Adicione aqui outros ouvintes para outras coleções se necessário
    // Ex: propriedades, eguas, etc. seguindo o mesmo padrão.
  }

  void stopListeners() {
    print(">> RealtimeSyncService: Parando ouvintes.");
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}