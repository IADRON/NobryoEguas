import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/auth/screens/manage_users_screen.dart';
import 'package:nobryo_final/core/services/auth_service.dart';
import 'package:nobryo_final/features/auth/widgets/user_profile_modal.dart';
import 'package:nobryo_final/features/eguas/screens/eguas_list_screen.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:nobryo_final/shared/widgets/loading_screen.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class PropriedadesScreen extends StatefulWidget {
  const PropriedadesScreen({super.key});

  @override
  State<PropriedadesScreen> createState() => _PropriedadesScreenState();
}

class _PropriedadesScreenState extends State<PropriedadesScreen> {
  bool _isLoading = true;
  List<Propriedade> _allPropriedades = [];
  List<Propriedade> _filteredPropriedades = [];
  final TextEditingController _searchController = TextEditingController();

  final SyncService _syncService = SyncService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _refreshPropriedades();
    _searchController.addListener(_filterPropriedades);
    Provider.of<SyncService>(context, listen: false).addListener(_refreshPropriedades);
  }

  @override
  void dispose() {
    _searchController.dispose();
    Provider.of<SyncService>(context, listen: false).removeListener(_refreshPropriedades);
    super.dispose();
  }

  Future<void> _refreshPropriedades() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _allPropriedades = await SQLiteHelper.instance.readAllPropriedades();
      _filterPropriedades();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao carregar dados: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _autoSync() async {
    final bool _ = await _syncService.syncData(isManual: false);
    if (mounted) {}
    await _refreshPropriedades();
  }

  Future<void> _manualSync() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const LoadingScreen(),
    );

    final bool online = await _syncService.syncData(isManual: true);
    
    if (mounted) {
      Navigator.of(context).pop(); // Fecha a tela de loading
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            online ? "Sincronização concluída!" : "Sem conexão com a internet."),
        backgroundColor: online ? Colors.green : Colors.orange,
      ));
    }
    _refreshPropriedades();
  }

  void _filterPropriedades() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredPropriedades = _allPropriedades.where((prop) {
        return prop.nome.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final username = _authService.currentUserNotifier.value?.username;
    final bool isAdmin = username == 'admin' || username == 'Bruna';
    final currentUser = _authService.currentUserNotifier.value;

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
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: "Busca por nome",
                prefixIcon: Icon(Icons.search, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredPropriedades.isEmpty
                      ? const Center(
                          child: Text(
                          "Nenhuma propriedade encontrada.\nClique no '+' para adicionar a primeira.",
                          textAlign: TextAlign.center,
                        ))
                      : ListView.builder(
                          itemCount: _filteredPropriedades.length,
                          itemBuilder: (context, index) {
                            final prop = _filteredPropriedades[index];
                            return Card(
                              child: ListTile(
                                title: Text(
                                  prop.nome,
                                  style: const TextStyle(
                                      color: AppTheme.darkText,
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(prop.dono,
                                    style: TextStyle(color: Colors.grey[600])),
                                trailing: const Icon(Icons.chevron_right,
                                    color: Colors.grey),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EguasListScreen(
                                        propriedadeId: prop.id,
                                        propriedadeNome: prop.nome,
                                      ),
                                    ),
                                  ).then((_) {
                                    _refreshPropriedades();
                                  });
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddPropriedadeModal(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddPropriedadeModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController();
    final donoController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
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
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: nomeController,
                    decoration: InputDecoration(
                      labelText: "Propriedade",
                      prefixIcon: const Icon(Icons.home_work_outlined)),
                    validator: (value) =>
                      value!.isEmpty ? "Este campo não pode ser vazio" : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: donoController,
                    decoration: InputDecoration(
                          labelText: "Dono da Propriedade",
                          prefixIcon: Icon(Icons.person_outlined)),
                    validator: (value) =>
                        value!.isEmpty ? "Este campo não pode ser vazio" : null,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          final novaPropriedade = Propriedade(
                            id: const Uuid().v4(),
                            nome: nomeController.text,
                            dono: donoController.text,
                          );
                          await SQLiteHelper.instance
                              .createPropriedade(novaPropriedade);
                          if (mounted) {
                            Navigator.of(ctx).pop();
                            _autoSync();
                          }
                        }
                      },
                    child: const Text("Salvar"),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      )
    );
  }
} 