import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/eguas/screens/eguas_list_screen.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';

// NÍVEL 2: Tela que lista as SUB-PROPRIEDADES de uma Propriedade Mãe.
class SubPropriedadesListScreen extends StatefulWidget {
  final Propriedade parentPropriedade;

  const SubPropriedadesListScreen({super.key, required this.parentPropriedade});

  @override
  State<SubPropriedadesListScreen> createState() => _SubPropriedadesListScreenState();
}

class _SubPropriedadesListScreenState extends State<SubPropriedadesListScreen> {
  late Future<List<Propriedade>> _subPropriedadesFuture;

  @override
  void initState() {
    super.initState();
    _refreshSubPropriedadesList();
    Provider.of<SyncService>(context, listen: false).addListener(_refreshSubPropriedadesList);
  }

  @override
  void dispose() {
    Provider.of<SyncService>(context, listen: false).removeListener(_refreshSubPropriedadesList);
    super.dispose();
  }

  void _refreshSubPropriedadesList() {
    setState(() {
      _subPropriedadesFuture = SQLiteHelper.instance.readSubPropriedades(widget.parentPropriedade.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Locais em ${widget.parentPropriedade.nome}"),
      ),
      body: FutureBuilder<List<Propriedade>>(
        future: _subPropriedadesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Erro: ${snapshot.error}"));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "Nenhum local cadastrado.\nClique no '+' para adicionar o primeiro.",
                textAlign: TextAlign.center,
              ),
            );
          } else {
            final subPropriedades = snapshot.data!;
            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: subPropriedades.length,
              itemBuilder: (context, index) {
                return _buildSubPropriedadeCard(subPropriedades[index]);
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSubPropriedadeModal(context),
        tooltip: "Adicionar Local",
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSubPropriedadeCard(Propriedade subPropriedade) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // AÇÃO: Ao clicar, vai para a tela de éguas (Nível 3)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EguasListScreen(
                propriedadeId: subPropriedade.id,
                propriedadeNome: subPropriedade.nome,
              ),
            ),
          ).then((_) => _refreshSubPropriedadesList());
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subPropriedade.nome,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText),
              ),
              const SizedBox(height: 8),
              Text(
                "Dono: ${subPropriedade.dono}",
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Este modal cria uma SUB-PROPRIEDADE (parentId é o da propriedade mãe)
  void _showAddSubPropriedadeModal(BuildContext context) {
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
                  "Adicionar Local em\n${widget.parentPropriedade.nome}",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: nomeController,
                  decoration: const InputDecoration(labelText: "Nome do Local (Ex: Piquete 1)", prefixIcon: Icon(Icons.maps_home_work_outlined)),
                  validator: (value) => value!.isEmpty ? "Este campo é obrigatório" : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: donoController,
                  decoration: const InputDecoration(labelText: "Dono", prefixIcon: Icon(Icons.person_outlined)),
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
                          parentId: widget.parentPropriedade.id, // Define o pai
                          statusSync: 'pending_create',
                        );
                        await SQLiteHelper.instance.createPropriedade(novaPropriedade);
                        if (mounted) {
                          Navigator.of(ctx).pop();
                          _refreshSubPropriedadesList();
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