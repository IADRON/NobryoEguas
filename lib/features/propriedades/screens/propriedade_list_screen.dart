import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/propriedades/screens/sub_propriedades_list_screen.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';

// NÍVEL 1: Tela que lista apenas as PROPRIEDADES MÃE.
class PropriedadesListScreen extends StatefulWidget {
  const PropriedadesListScreen({super.key});

  @override
  State<PropriedadesListScreen> createState() => _PropriedadesListScreenState();
}

class _PropriedadesListScreenState extends State<PropriedadesListScreen> {
  late Future<List<Propriedade>> _propriedadesFuture;

  @override
  void initState() {
    super.initState();
    _refreshPropriedadesList();
    Provider.of<SyncService>(context, listen: false).addListener(_refreshPropriedadesList);
  }

  @override
  void dispose() {
    Provider.of<SyncService>(context, listen: false).removeListener(_refreshPropriedadesList);
    super.dispose();
  }

  void _refreshPropriedadesList() {
    setState(() {
      _propriedadesFuture = SQLiteHelper.instance.readTopLevelPropriedades();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Propriedades"),
      ),
      body: FutureBuilder<List<Propriedade>>(
        future: _propriedadesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Erro: ${snapshot.error}"));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "Nenhuma propriedade cadastrada.\nClique no '+' para adicionar a primeira.",
                textAlign: TextAlign.center,
              ),
            );
          } else {
            final propriedades = snapshot.data!;
            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: propriedades.length,
              itemBuilder: (context, index) {
                return _buildPropriedadeCard(propriedades[index]);
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddPropriedadeModal(context),
        tooltip: "Adicionar Propriedade",
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPropriedadeCard(Propriedade propriedade) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // AÇÃO: Ao clicar, vai para a tela de sub-propriedades (Nível 2)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SubPropriedadesListScreen(
                parentPropriedade: propriedade,
              ),
            ),
          ).then((_) => _refreshPropriedadesList());
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                propriedade.nome,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText),
              ),
              const SizedBox(height: 8),
              Text(
                "Dono: ${propriedade.dono}",
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Este modal cria uma PROPRIEDADE MÃE (parentId é nulo)
  void _showAddPropriedadeModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController();
    final donoController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Adicionar Nova Propriedade",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: nomeController,
                  decoration: const InputDecoration(labelText: "Nome da Propriedade", prefixIcon: Icon(Icons.home_work_outlined)),
                  validator: (value) => value!.isEmpty ? "Este campo é obrigatório" : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: donoController,
                  decoration: const InputDecoration(labelText: "Dono da Propriedade", prefixIcon: Icon(Icons.person_outlined)),
                  validator: (value) => value!.isEmpty ? "Este campo é obrigatório" : null,
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
                          parentId: null, // Nulo, pois é uma propriedade mãe
                          statusSync: 'pending_create',
                        );
                        await SQLiteHelper.instance.createPropriedade(novaPropriedade);
                        if (mounted) {
                          Navigator.of(ctx).pop();
                          _refreshPropriedadesList();
                          Provider.of<SyncService>(context, listen: false).syncData(isManual: false);
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
      ),
    );
  }
}