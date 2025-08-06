import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/medicamento_model.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/auth/screens/manage_users_screen.dart';
import 'package:nobryo_final/core/services/auth_service.dart';
import 'package:nobryo_final/features/auth/widgets/user_profile_modal.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:nobryo_final/shared/widgets/loading_screen.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class MedicamentosScreen extends StatefulWidget {
  const MedicamentosScreen({super.key});

  @override
  State<MedicamentosScreen> createState() => _MedicamentosScreenState();
}

class _MedicamentosScreenState extends State<MedicamentosScreen> {
  late Future<List<Medicamento>> _medicamentosFuture;

  // ALTERAÇÃO 1: Declaramos a variável para guardar a instância do Provider.
  late SyncService _syncService;

  // A instância de AuthService continua local, pois não era a causa do erro.
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _refreshMedicamentos();
    // A chamada para addListener foi movida para didChangeDependencies.
  }

  // ALTERAÇÃO 2: Adicionamos o método didChangeDependencies.
  // Este é o local seguro para obter a referência do Provider.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Obtemos a instância do SyncService do Provider.
    _syncService = Provider.of<SyncService>(context, listen: false);
    // Adicionamos o listener usando a referência segura.
    _syncService.addListener(_refreshMedicamentos);
  }

  @override
  void dispose() {
    // ALTERAÇÃO 3: Usamos a variável _syncService para remover o listener.
    // Isso é seguro porque a referência já foi guardada.
    _syncService.removeListener(_refreshMedicamentos);
    super.dispose();
  }

  void _refreshMedicamentos() {
    if (mounted) {
      setState(() {
        _medicamentosFuture = SQLiteHelper.instance.readAllMedicamentos();
      });
    }
  }

  Future<void> _autoSync() async {
    // A chamada agora usa a instância correta do Provider (_syncService)
    final bool _ = await _syncService.syncData(isManual: false);
    _refreshMedicamentos();
  }

  Future<void> _manualSync() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const LoadingScreen(),
    );

    // A chamada agora usa a instância correta do Provider (_syncService)
    final bool online = await _syncService.syncData(isManual: true);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            online ? "Sincronização concluída!" : "Sem conexão com a internet."),
        backgroundColor: online ? Colors.green : Colors.orange,
      ));
    }
    _refreshMedicamentos();
  }

  @override
  Widget build(BuildContext context) {
    final username = _authService.currentUserNotifier.value?.username;
    final bool isAdmin = username == 'admin' || username == 'Bruna';
    final currentUser = _authService.currentUserNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text("MEDICAMENTOS"),
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
      body: FutureBuilder<List<Medicamento>>(
        future: _medicamentosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Erro: ${snapshot.error}"));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  "Nenhum medicamento cadastrado.\nClique no '+' para adicionar o primeiro.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          final medicamentos = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
            itemCount: medicamentos.length,
            itemBuilder: (context, index) {
              final med = medicamentos[index];
              return Card(
                child: ListTile(
                  title: Text(med.nome,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.darkText)),
                  subtitle: Text(med.descricao,
                      style: TextStyle(color: Colors.grey[700])),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showAddOrEditMedicamentoModal(context,
                            medicamento: med);
                      } else if (value == 'delete') {
                        _confirmDeleteMedicamento(med);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar'),
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          leading:
                              Icon(Icons.delete_outline, color: Colors.red),
                          title:
                              Text('Excluir', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOrEditMedicamentoModal(context),
        child: const Icon(Icons.add),
        tooltip: "Adicionar Medicamento",
      ),
    );
  }

  void _confirmDeleteMedicamento(Medicamento med) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirmar Exclusão"),
        content:
            Text("Tem certeza que deseja excluir o medicamento \"${med.nome}\"?"),
        actions: [
          TextButton(
            child: const Text("Cancelar"),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text("Excluir", style: TextStyle(color: Colors.red[700])),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SQLiteHelper.instance.softDeleteMedicamento(med.id);
      if (mounted) {
        _refreshMedicamentos();
        _autoSync();
      }
    }
  }

  void _showAddOrEditMedicamentoModal(BuildContext context,
      {Medicamento? medicamento}) {
    final isEditing = medicamento != null;
    final formKey = GlobalKey<FormState>();
    final nomeController =
        TextEditingController(text: isEditing ? medicamento.nome : '');
    final descController =
        TextEditingController(text: isEditing ? medicamento.descricao : '');

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
                      Text(isEditing ? "Editar Medicamento" : "Adicionar Medicamento",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Divider(height: 30, thickness: 1),
                      TextFormField(
                        controller: nomeController,
                        decoration: const InputDecoration(
                            labelText: "Nome",
                            prefixIcon: Icon(Icons.medication_outlined)),
                        validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: descController,
                        decoration: const InputDecoration(
                            labelText: "Descrição",
                            prefixIcon: Icon(Icons.notes_outlined)),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.darkGreen),
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              final med = Medicamento(
                                id: isEditing ? medicamento.id : const Uuid().v4(),
                                firebaseId: isEditing ? medicamento.firebaseId : null,
                                nome: nomeController.text,
                                descricao: descController.text,
                                statusSync: isEditing ? 'pending_update' : 'pending_create',
                              );

                              if(isEditing) {
                                await SQLiteHelper.instance.updateMedicamento(med);
                              } else {
                                await SQLiteHelper.instance.createMedicamento(med);
                              }

                              if (mounted) {
                                Navigator.of(ctx).pop();
                                _autoSync();
                              }
                            }
                          },
                          child: Text(isEditing ? "Salvar Alterações" : "Salvar"),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ));
  }
}