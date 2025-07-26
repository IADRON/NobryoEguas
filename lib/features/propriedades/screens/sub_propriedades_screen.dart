import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/features/eguas/screens/eguas_list_screen.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:uuid/uuid.dart';

class SubPropriedadesScreen extends StatefulWidget {
  final Propriedade propriedadePai;

  const SubPropriedadesScreen({super.key, required this.propriedadePai});

  @override
  State<SubPropriedadesScreen> createState() => _SubPropriedadesScreenState();
}

class _SubPropriedadesScreenState extends State<SubPropriedadesScreen> {
  bool _isLoading = true;
  List<Propriedade> _subPropriedades = [];
  
  // NOVO: Mapa para guardar o status de manejos pendentes
  Map<String, bool> _hasPendingManejosMap = {};

  @override
  void initState() {
    super.initState();
    _refreshSubPropriedades();
  }

  Future<void> _refreshSubPropriedades() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final subProps = await SQLiteHelper.instance
          .readSubPropriedades(widget.propriedadePai.id);
          
      // NOVO: Verifica manejos pendentes para cada lote
      final Map<String, bool> pendingMap = {};
      for (final subProp in subProps) {
        // A função hasPendingManejosForPropriedade deve ser implementada no seu SQLiteHelper
        pendingMap[subProp.id] = await SQLiteHelper.instance.hasPendingManejosForPropriedade(subProp.id);
      }

      if (mounted) {
        setState(() {
          _subPropriedades = subProps;
          _hasPendingManejosMap = pendingMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao carregar lotes: $e'),
              backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("LOTES EM ${widget.propriedadePai.nome.toUpperCase()}"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subPropriedades.isEmpty
              ? const Center(
                  child: Text(
                    "Nenhum lote encontrado.\nClique no '+' para adicionar o primeiro.",
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _subPropriedades.length,
                  itemBuilder: (context, index) {
                    final subProp = _subPropriedades[index];
                    final hasPending = _hasPendingManejosMap[subProp.id] ?? false;

                    return Card(
                      child: ListTile(
                        // NOVO: Indicador visual de manejo pendente
                        leading: hasPending
                          ? const CircleAvatar(
                              radius: 6,
                              backgroundColor: AppTheme.statusPrenhe,
                            )
                          : const SizedBox(width: 12), // Espaço para alinhar
                        title: Text(subProp.nome,
                            style: const TextStyle(
                                color: AppTheme.darkText,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(subProp.dono,
                            style: TextStyle(color: Colors.grey[600])),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EguasListScreen(
                                propriedadeId: subProp.id,
                                propriedadeNome: subProp.nome,
                              ),
                            ),
                          ).then((_) => _refreshSubPropriedades());
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSubPropriedadeModal(context),
        child: const Icon(Icons.add),
        tooltip: "Adicionar Lote",
      ),
    );
  }

  void _showAddSubPropriedadeModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController();
    final donoController = TextEditingController(text: widget.propriedadePai.dono);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            top: 20, left: 20, right: 20),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Adicionar Lote em ${widget.propriedadePai.nome}",
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Divider(height: 30, thickness: 1),
                TextFormField(
                  controller: nomeController,
                  decoration: const InputDecoration(labelText: "Nome do Lote"),
                  validator: (value) =>
                      value!.isEmpty ? "Este campo não pode ser vazio" : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: donoController,
                  decoration:
                      const InputDecoration(labelText: "Dono do Lote"),
                  validator: (value) =>
                      value!.isEmpty ? "Este campo não pode ser vazio" : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.darkGreen),
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        final novaSubPropriedade = Propriedade(
                          id: const Uuid().v4(),
                          nome: nomeController.text,
                          dono: donoController.text,
                          parentId: widget.propriedadePai.id,
                        );
                        await SQLiteHelper.instance
                            .createPropriedade(novaSubPropriedade);
                        if (mounted) {
                          Navigator.of(ctx).pop();
                          _refreshSubPropriedades();
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