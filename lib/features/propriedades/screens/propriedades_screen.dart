import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/services/auth_service.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/auth/screens/manage_users_screen.dart';
import 'package:nobryo_final/features/auth/widgets/user_profile_modal.dart';
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

  // Instância do AuthService para ser usada na tela
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _refreshData();
    _searchController.addListener(_filterData);
    Provider.of<SyncService>(context, listen: false).addListener(_refreshData);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterData);
    _searchController.dispose();
    Provider.of<SyncService>(context, listen: false).removeListener(_refreshData);
    super.dispose();
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final propriedades = await SQLiteHelper.instance.readTopLevelPropriedades();
      if (mounted) {
        setState(() {
          _allTopLevelPropriedades = propriedades;
          _filteredTopLevelPropriedades = List.from(_allTopLevelPropriedades);
          _filterData();
        });
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterData() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredTopLevelPropriedades = _allTopLevelPropriedades.where((prop) {
        return prop.nome.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
 Widget build(BuildContext context) {
   // Usando ValueListenableBuilder para reagir a mudanças no usuário logado
   return ValueListenableBuilder(
     valueListenable: _authService.currentUserNotifier,
     builder: (context, currentUser, child) {
       final bool isAdmin =
           currentUser?.username == 'admin' || currentUser?.username == 'Bruna';
 
       return Scaffold(
         appBar: AppBar(
        title: const Text("AGENDA"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: "Sincronizar Dados",
            onPressed: () {}, //MANUAL SYNC
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
         body: child, // O body é o child do builder para não ser reconstruído desnecessariamente
         
         // ## CORREÇÃO ##
         // O FloatingActionButton foi movido para dentro do Scaffold.
         floatingActionButton: FloatingActionButton(
           onPressed: () => _showAddPropriedadeModal(context),
           backgroundColor: AppTheme.darkGreen,
           child: const Icon(Icons.add, color: Colors.white),
           tooltip: "Adicionar Propriedade",
         ),
       );
     },
     // O child do ValueListenableBuilder é a parte da UI que não precisa
     // ser reconstruída quando o 'currentUser' muda.
     child: Padding(
       padding: const EdgeInsets.all(20.0),
       child: Column(
         children: [
           TextField(
             controller: _searchController,
             decoration: const InputDecoration(
               hintText: "Buscar por propriedade...",
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
 
                           return Card(
                             elevation: 2,
                             margin: const EdgeInsets.symmetric(vertical: 8),
                             child: ListTile(
                               contentPadding: const EdgeInsets.symmetric(
                                   horizontal: 16, vertical: 8),
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
                                     builder: (context) =>
                                         SubPropriedadesScreen(
                                       propriedadePai: prop,
                                     ),
                                   ),
                                 ).then((_) {
                                   _refreshData();
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
                Text("Nova Propriedade",
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Divider(height: 30, thickness: 1),
                TextFormField(
                  controller: nomeController,
                  decoration:
                      const InputDecoration(labelText: "Nome da Propriedade"),
                  validator: (value) =>
                      value!.isEmpty ? "Este campo não pode ser vazio" : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: donoController,
                  decoration: const InputDecoration(labelText: "Dono"),
                  validator: (value) =>
                      value!.isEmpty ? "Este campo não pode ser vazio" : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.darkGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        final novaPropriedade = Propriedade(
                          id: const Uuid().v4(),
                          nome: nomeController.text,
                          dono: donoController.text,
                          parentId: null,
                          statusSync: 'pending_create',
                        );
                        await SQLiteHelper.instance
                            .createPropriedade(novaPropriedade);
                        if (mounted) {
                          Navigator.of(ctx).pop();
                          _refreshData();
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
      ),
    );
  }
}