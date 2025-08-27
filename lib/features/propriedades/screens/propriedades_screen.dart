import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/services/auth_service.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/auth/screens/manage_users_screen.dart';
import 'package:nobryo_final/features/auth/widgets/user_profile_modal.dart';
import 'package:nobryo_final/features/eguas/screens/eguas_list_screen.dart';
import 'package:nobryo_final/shared/widgets/loading_screen.dart';
import 'package:nobryo_final/features/propriedades/screens/sub_propriedades_screen.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class PropriedadesScreen extends StatefulWidget {
  const PropriedadesScreen({super.key});

  @override
  State<PropriedadesScreen> createState() => _PropriedadeScreenState();
}

class _PropriedadeScreenState extends State<PropriedadesScreen> {
  bool _isLoading = true;
  List<Propriedade> _allTopLevelPropriedades = [];
  List<Propriedade> _filteredTopLevelPropriedades = [];
  final TextEditingController _searchController = TextEditingController();

  Map<String, bool> _hasPendingManejosMap = {};
  Map<String, int> _eguasCountMap = {};

  final AuthService _authService = AuthService();
  late SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _refreshData();
    _searchController.addListener(_filterData);
    _syncService = Provider.of<SyncService>(context, listen: false);  
    _syncService.addListener(_refreshData);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterData);
    _searchController.dispose();
    _syncService.removeListener(_refreshData);
    super.dispose();
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final propriedades = await SQLiteHelper.instance.readTopLevelPropriedades();

      final Map<String, int> counts = {};
      for (final prop in propriedades) {
        counts[prop.id] = await SQLiteHelper.instance.countEguasByPropriedade(prop.id);
      }
      
      final Map<String, bool> pendingMap = {};
      for (final prop in propriedades) {
        pendingMap[prop.id] = await SQLiteHelper.instance.hasPendingManejosRecursive(prop.id);
      }
      
      if (mounted) {
        setState(() {
          _allTopLevelPropriedades = propriedades;
          _filteredTopLevelPropriedades = List.from(_allTopLevelPropriedades);
          _hasPendingManejosMap = pendingMap;
          _isLoading = false;
          _eguasCountMap = counts;
        });
        _filterData(); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao carregar propriedades: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted && _isLoading) { 
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _filterData() async {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredTopLevelPropriedades = List.from(_allTopLevelPropriedades);
      });
      return;
    }

    final allEguas = await SQLiteHelper.instance.getAllEguas();
    List<Propriedade> filtered = [];

    for (final prop in _allTopLevelPropriedades) {
      if (prop.nome.toLowerCase().contains(query)) {
        if (!filtered.contains(prop)) {
          filtered.add(prop);
        }
        continue; 
      }

      final subProps = await SQLiteHelper.instance.readSubPropriedades(prop.id);
      final allPropIds = [prop.id, ...subProps.map((p) => p.id)];
      
      final eguaEncontrada = allEguas.any((egua) =>
          allPropIds.contains(egua.propriedadeId) &&
          (egua.nome.toLowerCase().contains(query) || egua.rp.toLowerCase().contains(query)));
      
      if (eguaEncontrada) {
        if (!filtered.contains(prop)) {
          filtered.add(prop);
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _filteredTopLevelPropriedades = filtered;
      });
    }
  }

  Future<void> _manualSync() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const LoadingScreen(),
    );

    final bool online = await _syncService.syncData(isManual: true);
    
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            online ? "Sincronização concluída!" : "Sem conexão com a internet."),
        backgroundColor: online ? Colors.green : Colors.orange,
      ));
    }
    _refreshData();
  }

  Future<void> _autoSync() async {
    final bool _ = await _syncService.syncData(isManual: false);
    if (mounted) {}
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _authService.currentUserNotifier,
      builder: (context, currentUser, child) {
        final bool isAdmin =
            currentUser?.username == 'admin' || currentUser?.username == 'Bruna';
  
        return Scaffold(
          appBar: AppBar(
            title: const Text("PROPRIEDADES"),
            actions: [
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: "Sincronizar Dados",
                onPressed: _manualSync,
              ),
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.group_outlined),
                  tooltip: "Gerenciar Usuários",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ManageUsersScreen()),
                    );
                  },
                ),
              if (currentUser != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: GestureDetector(
                    onTap: () => showUserProfileModal(context),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.lightGrey,
                      backgroundImage: (currentUser.photoUrl != null &&
                              currentUser.photoUrl!.isNotEmpty)
                          ? FileImage(File(currentUser.photoUrl!)) as ImageProvider
                          : null,
                      child: (currentUser.photoUrl == null ||
                              currentUser.photoUrl!.isEmpty)
                          ? const Icon(Icons.person, color: AppTheme.darkGreen)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          body: child,
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddPropriedadeModal(context),
            backgroundColor: AppTheme.brown,
            child: const Icon(Icons.add, color: Colors.white),
            tooltip: "Adicionar Propriedade",
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: "Buscar por propriedade ou égua...",
                prefixIcon: Icon(Icons.search, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredTopLevelPropriedades.isEmpty
                      ? const Center(
                          child: Text(
                          "Nenhuma propriedade encontrada.\nClique no '+' para adicionar a primeira.",
                          textAlign: TextAlign.center,
                        ))
                      : ListView.builder(
                          itemCount: _filteredTopLevelPropriedades.length,
                          itemBuilder: (context, index) {
                            final prop = _filteredTopLevelPropriedades[index];
                            final hasPending = _hasPendingManejosMap[prop.id] ?? false;
                            final eguasCount = _eguasCountMap[prop.id] ?? 0;

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(prop.nome,
                                        style: const TextStyle(
                                            color: AppTheme.darkText,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                      '$eguasCount éguas', // Adicione esta linha
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 14), // Adicione esta linha
                                    ),
                                  ],
                                ),
                                subtitle: Text(prop.dono,
                                    style: TextStyle(color: Colors.grey[600])),
                                trailing: hasPending
                                  ? const CircleAvatar(
                                      radius: 6,
                                      backgroundColor: AppTheme.statusPrenhe,
                                    )
                                  : const SizedBox(width: 12),
                                onTap: () {
                                  if (prop.hasLotes) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            SubPropriedadesScreen(
                                          propriedadePai: prop,
                                        ),
                                      ),
                                    ).then((_) {
                                      _refreshData();
                                    });
                                  } else {
                                     Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EguasListScreen(
                                          propriedadeId: prop.id,
                                          propriedadeNome: prop.nome,
                                        ),
                                      ),
                                    ).then((_) {
                                      _refreshData();
                                    });
                                  }
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPropriedadeModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController();
    final donoController = TextEditingController();
    bool hasLotes = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                top: 20,
                left: 20,
                right: 20),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text("Adicionar Propriedade",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const Divider(height: 30, thickness: 1),
                      TextFormField(
                        controller: nomeController,
                        decoration: const InputDecoration(
                            labelText: "Nome da Propriedade",
                            prefixIcon: Icon(Icons.home_work_outlined)),
                        validator: (value) => value!.isEmpty
                            ? "Este campo não pode ser vazio"
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: donoController,
                        decoration: const InputDecoration(
                          labelText: "Dono",
                          prefixIcon: Icon(Icons.person_outline)),
                        validator: (value) => value!.isEmpty
                            ? "Este campo não pode ser vazio"
                            : null,
                      ),
                      const SizedBox(height: 15),
                      SwitchListTile(
                        title: const Text("Possui Lotes?"),
                        value: hasLotes,
                        onChanged: (bool value) {
                          setModalState(() {
                            hasLotes = value;
                          });
                        },
                        activeColor: AppTheme.darkGreen,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.darkGreen,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12)),
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              final novaPropriedade = Propriedade(
                                id: const Uuid().v4(),
                                nome: nomeController.text,
                                dono: donoController.text,
                                hasLotes: hasLotes,
                                parentId: null,
                                statusSync: 'pending_create',
                              );
                              await SQLiteHelper.instance
                                  .createPropriedade(novaPropriedade);
                              if (mounted) {
                                Navigator.of(ctx).pop();
                                _autoSync();
                              }
                            }
                          },
                          child: const Text("Salvar",
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}