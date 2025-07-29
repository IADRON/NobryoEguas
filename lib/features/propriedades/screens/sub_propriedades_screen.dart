import 'package:flutter/material.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/egua_model.dart';
import 'package:nobryo_final/core/models/manejo_model.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/services/export_service.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/eguas/screens/eguas_list_screen.dart'; 
import 'package:nobryo_final/features/propriedades/widgets/peoes_management_widget.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

final ValueNotifier<bool> eguasMovedNotifier = ValueNotifier(false);

class SubPropriedadesScreen extends StatefulWidget {
  final Propriedade propriedadePai;

  const SubPropriedadesScreen({super.key, required this.propriedadePai});

  @override
  State<SubPropriedadesScreen> createState() => _SubPropriedadesScreenState();
}

class _SubPropriedadesScreenState extends State<SubPropriedadesScreen> {
  bool _isLoading = true;
  late Propriedade _currentPropriedadePai;
  List<Propriedade> _allSubPropriedades = [];
  List<Propriedade> _filteredSubPropriedades = [];
  final TextEditingController _searchController = TextEditingController();

  Map<String, bool> _hasPendingManejosMap = {};

  final SyncService _syncService = SyncService();
  final ExportService _exportService = ExportService();

  @override
  void initState() {
    super.initState();
    _currentPropriedadePai = widget.propriedadePai;
    _refreshSubPropriedades();
    _searchController.addListener(_filterLotes);
    Provider.of<SyncService>(context, listen: false).addListener(_refreshSubPropriedades);
    
    eguasMovedNotifier.addListener(_onEguasMoved);
  }

  @override
  void dispose() {
    Provider.of<SyncService>(context, listen: false).removeListener(_refreshSubPropriedades);
    _searchController.removeListener(_filterLotes);
    _searchController.dispose();
    
    eguasMovedNotifier.removeListener(_onEguasMoved);
    super.dispose();
  }
  
  void _onEguasMoved() {
    if (mounted) {
      _refreshSubPropriedades();
    }
  }

  Future<void> _filterLotes() async {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _filteredSubPropriedades = List.from(_allSubPropriedades);
        });
      }
      return;
    }

    List<Propriedade> filtered = [];
    for (final lote in _allSubPropriedades) {
      if (lote.nome.toLowerCase().contains(query)) {
        if (!filtered.contains(lote)) {
           filtered.add(lote);
        }
        continue;
      }
      final eguasDoLote = await SQLiteHelper.instance.readEguasByPropriedade(lote.id);
      final eguaEncontrada = eguasDoLote.any((egua) =>
          egua.nome.toLowerCase().contains(query) ||
          egua.rp.toLowerCase().contains(query));
      if (eguaEncontrada) {
         if (!filtered.contains(lote)) {
           filtered.add(lote);
        }
      }
    }
    if (mounted) {
      setState(() {
        _filteredSubPropriedades = filtered;
      });
    }
  }

  Future<void> _autoSync() async {
    await _syncService.syncData(isManual: false);
    if (mounted) {
      _refreshSubPropriedades();
    }
  }

  Future<void> _refreshSubPropriedades() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final subProps = await SQLiteHelper.instance
          .readSubPropriedades(widget.propriedadePai.id);

      final Map<String, bool> pendingMap = {};
      for (final subProp in subProps) {
        pendingMap[subProp.id] = await SQLiteHelper.instance.hasPendingManejosForPropriedade(subProp.id);
      }

      final updatedPropPai = await SQLiteHelper.instance.readPropriedade(widget.propriedadePai.id);

      if (mounted) {
        setState(() {
          if (updatedPropPai != null) {
            _currentPropriedadePai = updatedPropPai;
          }
          _allSubPropriedades = subProps;
          _filteredSubPropriedades = List.from(_allSubPropriedades);
          _hasPendingManejosMap = pendingMap;
          _isLoading = false;
        });
        _filterLotes();
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
        title: Text("LOTES EM ${_currentPropriedadePai.nome.toUpperCase()}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showOptionsModal(context),
            tooltip: "Mais Opções",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por lote ou égua...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredSubPropriedades.isEmpty
                      ? const Center(
                          child: Text(
                            "Nenhum lote ou égua encontrada.",
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _filteredSubPropriedades.length,
                          itemBuilder: (context, index) {
                            final subProp = _filteredSubPropriedades[index];
                            final hasPending = _hasPendingManejosMap[subProp.id] ?? false;

                            return Card(
                              child: ListTile(
                                title: Text(subProp.nome,
                                    style: const TextStyle(
                                        color: AppTheme.darkText,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(subProp.dono,
                                    style: TextStyle(color: Colors.grey[600])),
                                trailing: hasPending
                                  ? const CircleAvatar(
                                      radius: 6,
                                      backgroundColor: AppTheme.statusPrenhe,
                                    )
                                  : const SizedBox(width: 12),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EguasListScreen(
                                        propriedadeId: subProp.id,
                                        propriedadeNome: subProp.nome,
                                        propriedadeMaeId: widget.propriedadePai.id, 
                                      ),
                                    ),
                                  ).then((_) => _refreshSubPropriedades());
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSubPropriedadeModal(context),
        child: const Icon(Icons.add),
        tooltip: "Adicionar Lote",
      ),
    );
  }

  void _showOptionsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: <Widget>[
             ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: const Text('Gerenciar Deslocamentos'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showDeslocamentosDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Gerenciar Peões'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showPeoesWidget();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Exportar Relatório Completo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showExportOptions(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar Propriedade'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showEditPropriedadeModal(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeslocamentosDialog(BuildContext context) {
    int deslocamentos = _currentPropriedadePai.deslocamentos;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Contador de Deslocamentos"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Propriedade: ${_currentPropriedadePai.nome}", style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle, size: 40, color: AppTheme.statusVazia),
                        onPressed: () {
                          if (deslocamentos > 0) {
                            setDialogState(() {
                              deslocamentos--;
                            });
                          }
                        },
                      ),
                      Text(
                        deslocamentos.toString(),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, size: 40, color: AppTheme.darkGreen),
                        onPressed: () {
                          setDialogState(() {
                            deslocamentos++;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final updatedProp = _currentPropriedadePai.copyWith(
                      deslocamentos: deslocamentos,
                      statusSync: 'pending_update',
                    );
                    await SQLiteHelper.instance.updatePropriedade(updatedProp);
                    if (mounted) {
                      Navigator.of(ctx).pop();
                      _autoSync();
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Contador de deslocamentos salvo!"),
                        backgroundColor: Colors.green,
                      ));
                    }
                  },
                  child: const Text("Salvar"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showExportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Exportar para Excel (.xlsx)'),
              onTap: () {
                Navigator.of(ctx).pop();
                _exportarRelatorioCompleto(
                    _exportService.exportarPropriedadeParaExcel);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Exportar para PDF (.pdf)'),
              onTap: () {
                Navigator.of(ctx).pop();
                _exportarRelatorioCompleto(
                    _exportService.exportarPropriedadeParaPdf);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportarRelatorioCompleto(
    Future<void> Function(Propriedade, Map<Egua, List<Manejo>>, BuildContext)
        exportFunction,
  ) async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Buscando todos os dados da propriedade..."),
      backgroundColor: Colors.blue,
    ));

    try {
      final allPropriedadesIds = [..._allSubPropriedades.map((p) => p.id), widget.propriedadePai.id];
      final Map<Egua, List<Manejo>> dadosCompletos = {};

      for (String propId in allPropriedadesIds) {
        final eguasDoLote = await SQLiteHelper.instance.readEguasByPropriedade(propId);
        if (eguasDoLote.isEmpty) continue;

        for (final egua in eguasDoLote) {
          final List<Manejo> historico = await SQLiteHelper.instance.readHistoricoByEgua(egua.id);
          dadosCompletos[egua] = historico;
        }
      }

      if (dadosCompletos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Não há éguas ou manejos nesta propriedade para exportar."),
        ));
        setState(() => _isLoading = false);
        return;
      }

      await exportFunction(_currentPropriedadePai, dadosCompletos, context);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Erro ao buscar dados para exportação: $e"),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showPeoesWidget() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppTheme.pageBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: PeoesManagementWidget(
                propriedadeId: widget.propriedadePai.id,
                scrollController: scrollController,
              ),
            );
          },
        );
      },
    );
  }

  void _showEditPropriedadeModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: _currentPropriedadePai.nome);
    final donoController = TextEditingController(text: _currentPropriedadePai.dono);
    bool hasLotes = _currentPropriedadePai.hasLotes;
    bool canEditHasLotes = _allSubPropriedades.length <= 1;

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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Editar Propriedade",
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outlined,
                                color: Colors.red[700]),
                            onPressed: () =>
                                _showDeletePropriedadeConfirmationDialog(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: nomeController,
                        decoration: const InputDecoration(
                            labelText: "Nome",
                            prefixIcon: Icon(Icons.home_work_outlined)),
                        validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: donoController,
                        decoration: const InputDecoration(
                            labelText: "Dono",
                            prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                      ),
                      const SizedBox(height: 15),
                      SwitchListTile(
                        title: const Text("Possui Lotes?"),
                        subtitle: !canEditHasLotes
                            ? Text(
                                "Remova os lotes extras para alterar esta opção.",
                                style: TextStyle(color: Colors.red[700]),
                              )
                            : null,
                        value: hasLotes,
                        onChanged: canEditHasLotes
                            ? (bool value) {
                                setModalState(() {
                                  hasLotes = value;
                                });
                              }
                            : null,
                        activeColor: AppTheme.darkGreen,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.darkGreen),
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              if (_currentPropriedadePai.hasLotes &&
                                  !hasLotes &&
                                  _allSubPropriedades.length == 1) {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogCtx) => AlertDialog(
                                    title: const Text("Atenção"),
                                    content: Text(
                                        "Ao desativar os lotes, todas as éguas do lote '${_allSubPropriedades.first.nome}' serão movidas para a propriedade principal e o lote será excluído. Deseja continuar?"),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogCtx).pop(false),
                                        child: const Text("Cancelar"),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.of(dialogCtx).pop(true),
                                        child: const Text("Continuar"),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm != true) return;

                                final lote = _allSubPropriedades.first;
                                final eguasDoLote = await SQLiteHelper.instance.readEguasByPropriedade(lote.id);
                                for (var egua in eguasDoLote) {
                                  await SQLiteHelper.instance.updateEgua(egua.copyWith(propriedadeId: _currentPropriedadePai.id));
                                }
                                await SQLiteHelper.instance.softDeletePropriedade(lote.id);
                              }
                              final updatedProp =
                                  _currentPropriedadePai.copyWith(
                                nome: nomeController.text,
                                dono: donoController.text,
                                hasLotes: hasLotes,
                                statusSync: 'pending_update',
                              );
                              await SQLiteHelper.instance
                                  .updatePropriedade(updatedProp);
                              if (mounted) {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text("Propriedade atualizada!"),
                                  backgroundColor: Colors.green,
                                ));
                                _autoSync();
                              }
                            }
                          },
                          child: const Text("Salvar Alterações"),
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

  void _showDeletePropriedadeConfirmationDialog(BuildContext modalContext) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Confirmar Exclusão"),
        content: Text(
            'Tem certeza que deseja excluir "${_currentPropriedadePai.nome}"? TODOS os lotes, éguas e manejos associados serão perdidos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text("Cancelar"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              Navigator.of(modalContext).pop();
              await SQLiteHelper.instance.softDeletePropriedade(_currentPropriedadePai.id);
              if (mounted) {
                Navigator.of(context).pop(); 
                _autoSync();
              }
            },
            child: const Text("Confirmar Exclusão"),
          ),
        ],
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
                  Text("Adicionar Lote em ${widget.propriedadePai.nome}",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const Divider(height: 30, thickness: 1),
                  TextFormField(
                  controller: nomeController,
                  decoration: const InputDecoration(
                    labelText: "Nome do Lote",
                    prefixIcon: Icon(Icons.location_on_outlined)),
                  validator: (value) =>
                      value!.isEmpty ? "Este campo não pode ser vazio" : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: donoController,
                  decoration:
                      const InputDecoration(
                      labelText: "Dono do Lote",
                      prefixIcon: Icon(Icons.person_outline)),
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
                          statusSync: 'pending_create',
                        );
                        await SQLiteHelper.instance
                            .createPropriedade(novaSubPropriedade);
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
      ),
    );
  }
}