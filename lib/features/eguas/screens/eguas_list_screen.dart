// lib/features/eguas/screens/eguas_list_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/egua_model.dart';
import 'package:nobryo_final/core/models/manejo_model.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/services/export_service.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/eguas/screens/egua_details_page_view.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';

// --- CORREÇÃO: Notificador para avisar sobre a movimentação de éguas ---
final ValueNotifier<bool> eguasMovedNotifier = ValueNotifier(false);

class EguasListScreen extends StatefulWidget {
  final String propriedadeId;
  final String propriedadeNome;
  final String? propriedadeMaeId;

  const EguasListScreen({
    super.key,
    required this.propriedadeId,
    required this.propriedadeNome,
    this.propriedadeMaeId,
  });

  @override
  State<EguasListScreen> createState() => _EguasListScreenState();
}

class _EguasListScreenState extends State<EguasListScreen> {
  List<Egua> _allEguas = [];
  List<Egua> _filteredEguas = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  Map<String, DateTime?> _previsaoPartoMap = {};
  Map<String, Manejo?> _proximoManejoMap = {};

  bool _isSelectionMode = false;
  final Set<String> _selectedEguas = <String>{};

  final ExportService _exportService = ExportService();
  final SyncService _syncService = SyncService();

  Propriedade? _propriedade;
  late String _currentPropriedadeNome;

  @override
  void initState() {
    super.initState();
    _currentPropriedadeNome = widget.propriedadeNome;
    _refreshEguasList();
    Provider.of<SyncService>(context, listen: false).addListener(_refreshEguasList);
    _searchController.addListener(_filterEguas);
  }

  @override
  void dispose() {
    Provider.of<SyncService>(context, listen: false).removeListener(_refreshEguasList);
    _searchController.removeListener(_filterEguas);
    _searchController.dispose();
    super.dispose();
  }

  void _filterEguas() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredEguas = _allEguas.where((egua) {
        return egua.nome.toLowerCase().contains(query) ||
               egua.rp.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _toggleSelection(String eguaId) {
    setState(() {
      if (_selectedEguas.contains(eguaId)) {
        _selectedEguas.remove(eguaId);
      } else {
        _selectedEguas.add(eguaId);
      }
      if (_selectedEguas.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _enterSelectionMode(String eguaId) {
    setState(() {
      _isSelectionMode = true;
      _selectedEguas.add(eguaId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedEguas.clear();
    });
  }

  Future<void> _refreshEguasList() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final propFuture =
        SQLiteHelper.instance.readPropriedade(widget.propriedadeId);
    final eguasFuture =
        SQLiteHelper.instance.readEguasByPropriedade(widget.propriedadeId);

    final results = await Future.wait([propFuture, eguasFuture]);

    final prop = results[0] as Propriedade?;
    final initialEguas = results[1] as List<Egua>;

    final List<Future<Egua>> updateFutures = initialEguas
        .map((egua) => _getEguaWithUpdatedDiasPrenhe(egua))
        .toList();
    final updatedEguas = await Future.wait(updateFutures);

    if (mounted) {
      setState(() {
        _propriedade = prop;
        if (prop != null) _currentPropriedadeNome = prop.nome;
        _allEguas = updatedEguas;
        _isLoading = false;
      });
      _filterEguas();
      _calcularPrevisoesDeParto(updatedEguas);
      _calcularProximosManejos(updatedEguas);
    }
  }

  Future<void> _calcularProximosManejos(List<Egua> eguas) async {
    final Map<String, Manejo?> newMap = {};
    for (final egua in eguas) {
      final agendados = await SQLiteHelper.instance.readAgendadosByEgua(egua.id);
      if (agendados.isNotEmpty) {
        newMap[egua.id] = agendados.first;
      }
    }
    if (mounted) {
      setState(() {
        _proximoManejoMap = newMap;
      });
    }
  }

  Future<void> _calcularPrevisoesDeParto(List<Egua> eguas) async {
    final Map<String, DateTime?> newMap = {};
    for (final egua in eguas) {
      if (egua.statusReprodutivo.toLowerCase() == 'prenhe') {
        final historico = await SQLiteHelper.instance.readHistoricoByEgua(egua.id);
        historico.sort((a, b) => b.dataAgendada.compareTo(a.dataAgendada));

        Manejo? diagnosticoPositivo;
        for (var manejo in historico) {
          if (manejo.tipo.toLowerCase() == 'diagnóstico' &&
              manejo.detalhes['resultado']?.toString().toLowerCase() == 'prenhe') {
            diagnosticoPositivo = manejo;
            break;
          }
        }

        if (diagnosticoPositivo != null) {
          Manejo? ultimaInseminacao;
          for (var manejo in historico) {
            if (manejo.tipo.toLowerCase() == 'inseminação' &&
                manejo.dataAgendada.isBefore(diagnosticoPositivo.dataAgendada)) {
              ultimaInseminacao = manejo;
              break;
            }
          }

          if (ultimaInseminacao != null) {
            final dataInseminacao = ultimaInseminacao.dataAgendada;
            final previsao = DateTime(dataInseminacao.year, dataInseminacao.month + 11, dataInseminacao.day);
            newMap[egua.id] = previsao;
          }
        }
      }
    }
    if (mounted) {
      setState(() {
        _previsaoPartoMap = newMap;
      });
    }
  }

  Future<Egua> _getEguaWithUpdatedDiasPrenhe(Egua egua) async {
    if (egua.statusReprodutivo.toLowerCase() != 'prenhe') {
      return egua.copyWith(diasPrenhe: 0);
    }

    final historico = await SQLiteHelper.instance.readHistoricoByEgua(egua.id);
    if (historico.isEmpty) {
      return egua;
    }

    historico.sort((a, b) => b.dataAgendada.compareTo(a.dataAgendada));

    Manejo? ultimoDiagnosticoPrenhe;
    for (var manejo in historico) {
      if (manejo.tipo.toLowerCase() == 'diagnóstico' &&
          manejo.detalhes['resultado']?.toString().toLowerCase() == 'prenhe') {
        ultimoDiagnosticoPrenhe = manejo;
        break;
      }
    }

    if (ultimoDiagnosticoPrenhe != null) {
      final diasNoDiagnostico = int.tryParse(
              ultimoDiagnosticoPrenhe.detalhes['diasPrenhe']?.toString() ?? '0') ??
          0;
      final dataDiagnostico = ultimoDiagnosticoPrenhe.dataAgendada;
      final diasDesdeDiagnostico =
          DateTime.now().difference(dataDiagnostico).inDays;
      final diasCalculados = diasNoDiagnostico + diasDesdeDiagnostico;
      return egua.copyWith(diasPrenhe: diasCalculados);
    } else {
      return egua;
    }
  }

  Future<void> _autoSync() async {
    await _syncService.syncData(isManual: false);
    if (mounted) {
       _refreshEguasList();
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_isSelectionMode) return;

    final Egua movedEgua = _filteredEguas[oldIndex];
    int realOldIndex = _allEguas.indexOf(movedEgua);

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final Egua targetEgua = _filteredEguas[newIndex];
    int realNewIndex = _allEguas.indexOf(targetEgua);

    final Egua item = _allEguas.removeAt(realOldIndex);
    _allEguas.insert(realNewIndex, item);

    setState(() {
      _filteredEguas.removeAt(oldIndex);
      _filteredEguas.insert(newIndex, item);
    });

    await SQLiteHelper.instance.updateEguasOrder(_allEguas);
    _autoSync();
  }

  void _exportarRelatorioCompleto(
    Future<void> Function(Propriedade, Map<Egua, List<Manejo>>, BuildContext)
        exportFunction,
  ) async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Buscando todos os dados do local..."),
      backgroundColor: Colors.blue,
    ));

    try {
      if (_allEguas.isEmpty || _propriedade == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Não há éguas neste local para exportar."),
        ));
        setState(() => _isLoading = false);
        return;
      }

      final Map<Egua, List<Manejo>> dadosCompletos = {};

      for (final egua in _allEguas) {
        final List<Manejo> historico =
            await SQLiteHelper.instance.readHistoricoByEgua(egua.id);
        dadosCompletos[egua] = historico;
      }

      if (dadosCompletos.values.every((list) => list.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Nenhum manejo encontrado para exportar neste local."),
          backgroundColor: Colors.orange,
        ));
      } else {
        await exportFunction(_propriedade!, dadosCompletos, context);
      }
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

  void _showOptionsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Exportar Relatório do Local'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showExportOptions(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar Local'),
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

  void _showEditPropriedadeModal(BuildContext context) {
    if (_propriedade == null) return;

    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: _propriedade!.nome);
    final donoController = TextEditingController(text: _propriedade!.dono);

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Editar Local",
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outlined, color: Colors.red[700]),
                      onPressed: () => _showDeletePropriedadeConfirmationDialog(ctx),
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
                      prefixIcon: Icon(Icons.person_outlined)),
                  validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.darkGreen),
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        final updatedProp = _propriedade!.copyWith(
                          nome: nomeController.text,
                          dono: donoController.text,
                          statusSync: 'pending_update',
                        );
                        await SQLiteHelper.instance
                            .updatePropriedade(updatedProp);
                        if (mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text("Local atualizado!"),
                            backgroundColor: Colors.green,
                          ));
                          setState(() {
                            _currentPropriedadeNome = updatedProp.nome;
                          });
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
      ),
    );
  }

  void _showDeletePropriedadeConfirmationDialog(BuildContext modalContext) {
    if (_propriedade == null) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Confirmar Exclusão"),
        content: Text(
            'Tem certeza que deseja excluir "${_propriedade!.nome}"? Todas as éguas e manejos associados serão perdidos.'),
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
              await SQLiteHelper.instance.softDeletePropriedade(_propriedade!.id);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nome ou RP da égua...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredEguas.isEmpty
                      ? const Center(
                          child: Text(
                            "Nenhuma égua encontrada.",
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _filteredEguas.length,
                          itemBuilder: (context, index) {
                            final egua = _filteredEguas[index];
                            return _buildEguaCard(egua, index);
                          },
                          onReorder: _onReorder,
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOrEditEguaModal(context),
        child: const Icon(Icons.add),
        tooltip: "Adicionar Égua",
      ),
    );
  }

  AppBar _buildDefaultAppBar() {
    return AppBar(
      backgroundColor: AppTheme.darkGreen,
      foregroundColor: AppTheme.lightGrey,
      title: Text(
        _currentPropriedadeNome.toUpperCase(),
        style: const TextStyle(fontSize: 18, color: AppTheme.lightGrey),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showOptionsModal(context),
          tooltip: "Mais Opções",
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: AppTheme.brown,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text("${_selectedEguas.length} selecionada(s)"),
      actions: [
        IconButton(
          icon: const Icon(Icons.swap_horiz),
          onPressed: _showMoveEguasModal,
          tooltip: "Mover Éguas",
        ),
      ],
    );
  }

  Widget _buildEguaCard(Egua egua, int index) {
    final statusColor = egua.statusReprodutivo.toLowerCase() == 'prenhe'
        ? AppTheme.statusPrenhe
        : AppTheme.statusVazia;
    final previsaoParto = _previsaoPartoMap[egua.id];
    final proximoManejo = _proximoManejoMap[egua.id];
    final isSelected = _selectedEguas.contains(egua.id);

    return Card(
      key: ValueKey(egua.id),
      color: isSelected ? AppTheme.brown.withOpacity(0.2) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () {
          if (!_isSelectionMode) {
            _enterSelectionMode(egua.id);
          }
        },
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(egua.id);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EguaDetailsPageView(
                  eguas: _filteredEguas,
                  initialIndex: index,
                  propriedadeMaeId: widget.propriedadeMaeId ?? widget.propriedadeId,
                ),
              ),
            ).then((_) {
              _refreshEguasList();
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      _toggleSelection(egua.id);
                    },
                    activeColor: AppTheme.brown,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(egua.nome,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkText)),
                    Text("RP: ${egua.rp}",
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[600])),

                    if (proximoManejo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.statusDiagnostico,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_month_outlined, size: 14, color: AppTheme.darkGreen),
                            const SizedBox(width: 4),
                            Text(
                            "Próximo manejo: ${DateFormat('dd/MM/yy').format(proximoManejo.dataAgendada)}",
                            style: const TextStyle(
                              color: Color.fromARGB(255, 250, 250, 250),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ]
                      ),
                    )
                  ),
                  const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 6.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(egua.statusReprodutivo.toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                        if (egua.diasPrenhe != null && egua.diasPrenhe! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: AppTheme.brown,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text("${egua.diasPrenhe} D",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ),
                        if (previsaoParto != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 4),
                                Text(
                                  "Parto: ${DateFormat('dd/MM/yy').format(previsaoParto)}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[800],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_isSelectionMode)
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoveEguasModal() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return MoveEguasWidget(
          currentPropriedadeId: widget.propriedadeId,
          selectedEguas: _selectedEguas,
          onMoveConfirmed: () {
            _exitSelectionMode();
            _autoSync();
            // --- CORREÇÃO: Notifica que éguas foram movidas ---
            eguasMovedNotifier.value = !eguasMovedNotifier.value;
          },
        );
      },
    );
  }

  void _showAddOrEditEguaModal(BuildContext context, {Egua? egua}) {
    final isEditing = egua != null;
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: egua?.nome ?? '');
    final rpController = TextEditingController(text: egua?.rp ?? '');
    final pelagemController = TextEditingController(text: egua?.pelagem ?? '');
    final coberturaController =
        TextEditingController(text: egua?.cobertura ?? '');
    final obsController = TextEditingController(text: egua?.observacao ?? '');

    String categoriaSelecionada = egua?.categoria ?? 'Matriz';
    bool teveParto = egua?.dataParto != null;
    DateTime? dataParto = egua?.dataParto;
    String? sexoPotro = egua?.sexoPotro;

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
                      Text(
                          isEditing
                              ? "Editar Égua"
                              : "Adicionar Égua em\n$_currentPropriedadeNome",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Divider(height: 30, thickness: 1),
                      TextFormField(
                          controller: nomeController,
                          decoration: const InputDecoration(
                              labelText: "Nome da Égua",
                              prefixIcon: Icon(Icons.female_outlined)),
                          validator: (v) => v!.isEmpty ? "Obrigatório" : null),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: rpController,
                        decoration: const InputDecoration(
                            labelText: "RP",
                            prefixIcon: Icon(Icons.numbers_outlined)),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                          controller: pelagemController,
                          decoration: const InputDecoration(
                              labelText: "Pelagem",
                              prefixIcon: Icon(Icons.pets_outlined)),
                          validator: (v) => v!.isEmpty ? "Obrigatório" : null),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: categoriaSelecionada,
                        decoration: const InputDecoration(
                          labelText: "Categoria",
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: ['Matriz', 'Doadora', 'Receptora']
                            .map((label) => DropdownMenuItem(
                                  child: Text(label),
                                  value: label,
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setModalState(() {
                              categoriaSelecionada = value;
                            });
                          }
                        },
                      ),
                      if (categoriaSelecionada == 'Matriz')
                        Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: TextFormField(
                            controller: coberturaController,
                            decoration: const InputDecoration(
                              labelText: "Padreador",
                              prefixIcon: Icon(Icons.male),
                            ),
                          ),
                        ),
                      const SizedBox(height: 15),
                      const Text("Parto?",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(
                              child: RadioListTile<bool>(
                                  title: const Text("Sim"),
                                  value: true,
                                  groupValue: teveParto,
                                  onChanged: (val) =>
                                      setModalState(() => teveParto = val!))),
                          Expanded(
                              child: RadioListTile<bool>(
                                  title: const Text("Não"),
                                  value: false,
                                  groupValue: teveParto,
                                  onChanged: (val) =>
                                      setModalState(() => teveParto = val!))),
                        ],
                      ),
                      if (teveParto)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppTheme.lightGrey.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                readOnly: true,
                                controller: TextEditingController(
                                  text: dataParto == null ? '' : DateFormat('dd/MM/yyyy').format(dataParto!),
                                ),
                                decoration: const InputDecoration(
                                  labelText: "Data do Parto",
                                  prefixIcon:
                                      Icon(Icons.calendar_today_outlined),
                                  hintText: 'Selecione a data',
                                ),
                                onTap: () async {
                                  final pickedDate = await showDatePicker(
                                      context: context,
                                      initialDate: dataParto ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now());
                                  if (pickedDate != null) {
                                    setModalState(
                                        () => dataParto = pickedDate);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              const Text("Sexo do Potro",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Row(
                                children: [
                                  Expanded(
                                      child: RadioListTile<String>(
                                          title: const Text("Macho"),
                                          value: "Macho",
                                          groupValue: sexoPotro,
                                          onChanged: (val) => setModalState(
                                              () => sexoPotro = val))),
                                  Expanded(
                                      child: RadioListTile<String>(
                                          title: const Text("Fêmea"),
                                          value: "Fêmea",
                                          groupValue: sexoPotro,
                                          onChanged: (val) => setModalState(
                                              () => sexoPotro = val))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      TextFormField(
                          controller: obsController,
                          decoration: const InputDecoration(
                              labelText: "Observação",
                              prefixIcon: Icon(Icons.comment_outlined)),
                          maxLines: 3),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.darkGreen),
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              final eguaData = Egua(
                                id: isEditing ? egua.id : const Uuid().v4(),
                                firebaseId: egua?.firebaseId,
                                nome: nomeController.text,
                                rp: rpController.text,
                                pelagem: pelagemController.text,
                                categoria: categoriaSelecionada,
                                cobertura: categoriaSelecionada == 'Matriz'
                                    ? coberturaController.text
                                    : null,
                                dataParto: teveParto ? dataParto : null,
                                sexoPotro: teveParto ? sexoPotro : null,
                                observacao: obsController.text,
                                statusReprodutivo:
                                    egua?.statusReprodutivo ?? 'Vazia',
                                propriedadeId: widget.propriedadeId,
                                statusSync: isEditing
                                    ? 'pending_update'
                                    : 'pending_create',
                                orderIndex: isEditing
                                    ? egua.orderIndex
                                    : _allEguas.length,
                              );

                              if (isEditing) {
                                await SQLiteHelper.instance
                                    .updateEgua(eguaData);
                              } else {
                                await SQLiteHelper.instance
                                    .createEgua(eguaData);
                              }

                              if (mounted) {
                                Navigator.of(ctx).pop();
                                _autoSync();
                              }
                            }
                          },
                          child: Text(
                              isEditing ? "Salvar Alterações" : "Salvar"),
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

class MoveEguasWidget extends StatefulWidget {
  final String currentPropriedadeId;
  final Set<String> selectedEguas;
  final VoidCallback onMoveConfirmed;

  const MoveEguasWidget({
    super.key,
    required this.currentPropriedadeId,
    required this.selectedEguas,
    required this.onMoveConfirmed,
  });

  @override
  _MoveEguasWidgetState createState() => _MoveEguasWidgetState();
}

class _MoveEguasWidgetState extends State<MoveEguasWidget> {
  int _step = 0;
  Propriedade? _selectedPropriedadeMae;
  
  List<Propriedade> _topLevelProps = [];
  List<Propriedade> _subProps = [];
  List<Propriedade> _filteredList = [];
  
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTopLevelProps();
    _searchController.addListener(_filterList);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterList);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTopLevelProps() async {
    final props = await SQLiteHelper.instance.readTopLevelPropriedades();
    if (mounted) {
      setState(() {
        _topLevelProps = props;
        _filteredList = props;
      });
    }
  }

  Future<void> _loadSubProps(String parentId) async {
    final lotes = await SQLiteHelper.instance.readSubPropriedades(parentId);
    if (mounted) {
      setState(() {
        _subProps = lotes.where((lote) => lote.id != widget.currentPropriedadeId).toList();
        _filteredList = _subProps;
      });
    }
  }

  void _filterList() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (_step == 0) {
        _filteredList = _topLevelProps.where((prop) => prop.nome.toLowerCase().contains(query)).toList();
      } else {
        _filteredList = _subProps.where((lote) => lote.nome.toLowerCase().contains(query)).toList();
      }
    });
  }

  void _handleSelection(Propriedade prop) {
    if (_step == 0) {
      setState(() {
        _step = 1;
        _selectedPropriedadeMae = prop;
        _searchController.clear();
      });
      _loadSubProps(prop.id);
    } else {
      _confirmAndMove(prop);
    }
  }

  void _confirmAndMove(Propriedade destLote) async {
    Navigator.of(context).pop(); 
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Confirmar Movimentação"),
        content: Text("Deseja mover ${widget.selectedEguas.length} égua(s) para o lote \"${destLote.nome}\"?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
            onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text("Mover")),
        ],
      ),
    );

    if (confirmed == true) {
      final eguasToMove = await SQLiteHelper.instance.readEguasByPropriedade(widget.currentPropriedadeId);
      for (String eguaId in widget.selectedEguas) {
        final egua = eguasToMove.firstWhere((e) => e.id == eguaId);
        final updatedEgua = egua.copyWith(
          propriedadeId: destLote.id,
          statusSync: 'pending_update',
        );
        await SQLiteHelper.instance.updateEgua(updatedEgua);
      }
      widget.onMoveConfirmed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (_step == 1)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _step = 0;
                      _selectedPropriedadeMae = null;
                      _searchController.clear();
                      _filteredList = _topLevelProps;
                    });
                  },
                ),
              Expanded(
                child: Text(
                  _step == 0 ? "Selecione a Propriedade" : "Selecione o Lote em \"${_selectedPropriedadeMae!.nome}\"",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: "Buscar...",
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _filteredList.isEmpty
                ? Center(child: Text(_step == 0 ? "Nenhuma propriedade encontrada." : "Nenhum lote disponível."))
                : ListView.builder(
                    itemCount: _filteredList.length,
                    itemBuilder: (context, index) {
                      final prop = _filteredList[index];
                      return ListTile(
                        title: Text(prop.nome),
                        onTap: () => _handleSelection(prop),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}