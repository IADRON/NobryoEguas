import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/peao_model.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:uuid/uuid.dart';

class PeoesManagementWidget extends StatefulWidget {
  final String propriedadeId;
  final ScrollController scrollController;

  const PeoesManagementWidget({
    super.key,
    required this.propriedadeId,
    required this.scrollController,
  });

  @override
  State<PeoesManagementWidget> createState() => _PeoesManagementWidgetState();
}

class _PeoesManagementWidgetState extends State<PeoesManagementWidget> {
  late Future<List<Peao>> _peoesFuture;

  @override
  void initState() {
    super.initState();
    _refreshPeoesList();
  }

  void _refreshPeoesList() {
    setState(() {
      _peoesFuture =
          SQLiteHelper.instance.readPeoesByPropriedade(widget.propriedadeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Gerenciar Peões",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppTheme.darkGreen, size: 30),
                  onPressed: () => _showAddOrEditPeaoModal(),
                  tooltip: "Adicionar Peão",
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Peao>>(
              future: _peoesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text("Erro ao carregar dados: ${snapshot.error}"));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      "Nenhum peão cadastrado.\nClique no '+' para adicionar.",
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final peoes = snapshot.data!;
                return ListView.builder(
                  controller: widget.scrollController,
                  itemCount: peoes.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final peao = peoes[index];
                    return Card(
                      child: ListTile(
                        title: Text(peao.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(peao.funcao),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppTheme.brown),
                              onPressed: () => _showAddOrEditPeaoModal(peao: peao),
                              tooltip: "Editar",
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                              onPressed: () => _confirmDeletePeao(peao),
                              tooltip: "Excluir",
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePeao(Peao peao) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmar Exclusão"),
        content: Text("Tem certeza que deseja excluir o peão \"${peao.nome}\"?"),
        actions: [
          TextButton(
            child: const Text("Cancelar"),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Excluir"),
            onPressed: () async {
              await SQLiteHelper.instance.softDeletePeao(peao.id);
              if (mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("${peao.nome} excluído com sucesso."), backgroundColor: Colors.green),
                );
                _refreshPeoesList();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAddOrEditPeaoModal({Peao? peao}) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: peao?.nome ?? '');
    final funcaoController = TextEditingController(text: peao?.funcao ?? '');
    final isEditing = peao != null;

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
                      // **TÍTULO CORRIGIDO**
                      Text(isEditing ? "Editar Peão" : "Adicionar Peão",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Divider(height: 30, thickness: 1),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: nomeController,
                        decoration:
                            const InputDecoration(labelText: "Nome"),
                        validator: (v) =>
                            v!.isEmpty ? "O nome é obrigatório" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: funcaoController,
                        decoration:
                            const InputDecoration(labelText: "Função"),
                        validator: (v) =>
                            v!.isEmpty ? "A função é obrigatória" : null,
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.darkGreen,
                          ),
                          child: const Text("Salvar"),
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              if (isEditing) {
                                final updatedPeao = peao.copyWith(
                                  nome: nomeController.text,
                                  funcao: funcaoController.text,
                                );
                                await SQLiteHelper.instance
                                    .updatePeao(updatedPeao);
                              } else {
                                final novoPeao = Peao(
                                  id: const Uuid().v4(),
                                  nome: nomeController.text,
                                  funcao: funcaoController.text,
                                  propriedadeId: widget.propriedadeId,
                                );
                                await SQLiteHelper.instance
                                    .createPeao(novoPeao);
                              }
                              if (mounted) {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Peão salvo com sucesso."),
                                      backgroundColor: Colors.green),
                                );
                                _refreshPeoesList();
                              }
                            }
                          },
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