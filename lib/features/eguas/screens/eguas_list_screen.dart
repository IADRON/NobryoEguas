import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nobryo_eguas/core/database/sqlite_helper.dart';
import 'package:nobryo_eguas/core/models/egua_model.dart';
import 'package:nobryo_eguas/core/models/manejo_model.dart';
import 'package:nobryo_eguas/core/models/propriedade_model.dart';
import 'package:nobryo_eguas/core/services/export_service.dart';
import 'package:nobryo_eguas/core/services/sync_service.dart';
import 'package:nobryo_eguas/features/eguas/screens/egua_details_page_view.dart';
import 'package:nobryo_eguas/features/propriedades/widgets/peoes_management_widget.dart';
import 'package:nobryo_eguas/shared/theme/theme.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

final ValueNotifier<bool> eguasMovedNotifier = ValueNotifier<bool>(false);

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
  late SyncService _syncService = SyncService();

  Propriedade? _currentPropriedade;

  @override
  void initState() {
    super.initState();
    _refreshEguas();
    _syncService = Provider.of<SyncService>(context, listen: false);
    _syncService.addListener(_refreshEguas);
    _searchController.addListener(_filterEguas);
  }

  @override
  void dispose() {
    _syncService.removeListener(_refreshEguas);
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

  Future<void> _refreshEguas() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final propIdToLoad = widget.propriedadeMaeId ?? widget.propriedadeId;
    _currentPropriedade =
        await SQLiteHelper.instance.readPropriedade(propIdToLoad);

    final eguas =
        await SQLiteHelper.instance.readEguasByPropriedade(widget.propriedadeId);

    final List<Future<Egua>> updateFutures =
        eguas.map((egua) => _getEguaWithUpdatedDiasPrenhe(egua)).toList();
    final updatedEguas = await Future.wait(updateFutures);

    if (mounted) {
      setState(() {
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
      final agendados =
          await SQLiteHelper.instance.readAgendadosByEgua(egua.id);
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
        final historico =
            await SQLiteHelper.instance.readHistoricoByEgua(egua.id);
        historico.sort((a, b) => b.dataAgendada.compareTo(a.dataAgendada));

        Manejo? diagnosticoPositivo;
        for (var manejo in historico) {
          if (manejo.tipo.toLowerCase() == 'diagnóstico' &&
              manejo.detalhes['resultado']?.toString().toLowerCase() ==
                  'prenhe') {
            diagnosticoPositivo = manejo;
            break;
          }
        }

        if (diagnosticoPositivo != null) {
          Manejo? ultimaInseminacao;
          for (var manejo in historico) {
            if (manejo.tipo.toLowerCase() == 'inseminação' &&
                manejo.dataAgendada
                    .isBefore(diagnosticoPositivo.dataAgendada)) {
              ultimaInseminacao = manejo;
              break;
            }
          }

          if (ultimaInseminacao != null) {
            final dataInseminacao = ultimaInseminacao.dataAgendada;
            final previsao = DateTime(dataInseminacao.year,
                dataInseminacao.month + 11, dataInseminacao.day);
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
              ultimoDiagnosticoPrenhe.detalhes['diasPrenhe']?.toString() ??
                  '0') ??
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
      _refreshEguas();
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
      Future<void> Function(
              Propriedade, Map<Egua, List<Manejo>>, BuildContext)
          exportFunction,
      {Set<String>? eguasSelecionadas,
      DateTime? dataInicio,
      DateTime? dataFim}) async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Buscando todos os dados do lote..."),
      backgroundColor: Colors.blue,
    ));

    try {
      if (_allEguas.isEmpty || _currentPropriedade == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Não há éguas neste lote para exportar."),
        ));
        setState(() => _isLoading = false);
        return;
      }

      final Map<Egua, List<Manejo>> dadosCompletos = {};

      final eguasParaExportar = eguasSelecionadas != null
          ? _allEguas
              .where((egua) => eguasSelecionadas.contains(egua.id))
              .toList()
          : _allEguas;

      for (final egua in eguasParaExportar) {
        List<Manejo> historico =
            await SQLiteHelper.instance.readHistoricoByEgua(egua.id);

        if (dataInicio != null && dataFim != null) {
          historico = historico
              .where((manejo) =>
                  !manejo.dataAgendada.isBefore(dataInicio) &&
                  !manejo.dataAgendada.isAfter(dataFim))
              .toList();
        }

        dadosCompletos[egua] = historico;
      }

      if (dadosCompletos.values.every((list) => list.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Nenhum manejo encontrado para exportar neste lote."),
          backgroundColor: Colors.orange,
        ));
      } else {
        await exportFunction(_currentPropriedade!, dadosCompletos, context);
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

  void _showPropOptionsModal(BuildContext context) {
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

  void _showPeoesWidget() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
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
                propriedadeId: widget.propriedadeMaeId ?? widget.propriedadeId,
                scrollController: scrollController,
              ),
            );
          },
        );
      },
    );
  }

  void _showSubPropOptionsModal(BuildContext context) {
    bool canEditProp =
        _currentPropriedade != null && _currentPropriedade!.parentId == null;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Exportar Relatório do Lote'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showExportOptions(context);
              },
            ),
            if (canEditProp || _currentPropriedade!.hasLotes)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Editar Lote'),
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

  void _showExportOptions(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppTheme.pageBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ExportOptionsModal(
                eguas: _allEguas,
                scrollController: scrollController,
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      final eguasSelecionadas = result['selectedEguas'] as Set<String>;
      final dataInicio = result['startDate'] as DateTime?;
      final dataFim = result['endDate'] as DateTime?;
      final format = result['format'] as String;

      if (format == 'excel') {
        _exportarRelatorioCompleto(
          _exportService.exportarPropriedadeParaExcel,
          eguasSelecionadas: eguasSelecionadas,
          dataInicio: dataInicio,
          dataFim: dataFim,
        );
      } else if (format == 'pdf') {
        _exportarRelatorioCompleto(
          _exportService.exportarPropriedadeParaPdf,
          eguasSelecionadas: eguasSelecionadas,
          dataInicio: dataInicio,
          dataFim: dataFim,
        );
      }
    }
  }

  void _showDeslocamentosDialog(BuildContext context) {
    int deslocamentos = _currentPropriedade!.deslocamentos;

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
                  Text("Propriedade: ${_currentPropriedade!.nome}",
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle,
                            size: 40, color: AppTheme.statusVazia),
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
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle,
                            size: 40, color: AppTheme.darkGreen),
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
                    final updatedProp = _currentPropriedade!.copyWith(
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

  void _showEditPropriedadeModal(BuildContext context) async {
    if (_currentPropriedade == null) return;

    Propriedade? propToEdit;
    String modalTitle = "Editar Propriedade";

    if (_currentPropriedade!.hasLotes) {
      propToEdit =
          await SQLiteHelper.instance.readPropriedade(widget.propriedadeId);
      modalTitle = "Editar Lote";
    } else {
      propToEdit = _currentPropriedade;
    }

    if (propToEdit == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Erro: Lote não encontrado para edição."),
        backgroundColor: Colors.red,
      ));
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: propToEdit.nome);
    final donoController = TextEditingController(text: propToEdit.dono);
    bool hasLotes = propToEdit.hasLotes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
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
                            modalTitle,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outlined,
                                color: Colors.red[700]),
                            onPressed: () =>
                                _showDeletePropriedadeConfirmationDialog(
                                    ctx, propToEdit!),
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
                            labelText: "Proprietário",
                            prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                      ),
                      if (!_currentPropriedade!.hasLotes) ...[
                        const SizedBox(height: 15),
                        SwitchListTile(
                          title: const Text("Possui Lotes?"),
                          subtitle: Text(
                              "Ative para organizar suas éguas em lotes.",
                              style: TextStyle(color: Colors.grey[600])),
                          value: hasLotes,
                          onChanged: (bool value) {
                            setModalState(() {
                              hasLotes = value;
                            });
                          },
                          activeColor: AppTheme.darkGreen,
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.darkGreen),
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              if (_currentPropriedade!.hasLotes) {
                                final updatedProp = propToEdit!.copyWith(
                                  nome: nomeController.text,
                                  dono: donoController.text,
                                  statusSync: 'pending_update',
                                );
                                await SQLiteHelper.instance
                                    .updatePropriedade(updatedProp);
                              } else {
                                if (!_currentPropriedade!.hasLotes &&
                                    hasLotes) {
                                  if (_allEguas.isNotEmpty) {
                                    final novoLote = await _showCreateLoteModal(
                                        context, _currentPropriedade!);
                                    if (novoLote != null) {
                                      for (var egua in _allEguas) {
                                        await SQLiteHelper.instance
                                            .updateEgua(egua.copyWith(
                                          propriedadeId: novoLote.id,
                                          statusSync: 'pending_update',
                                        ));
                                        final manejosDaEgua =
                                            await SQLiteHelper.instance
                                                .readAgendadosByEgua(egua.id);
                                        for (var manejo in manejosDaEgua) {
                                          await SQLiteHelper.instance
                                              .updateManejo(manejo.copyWith(
                                            propriedadeId: novoLote.id,
                                            statusSync: 'pending_update',
                                          ));
                                        }
                                      }
                                    } else {
                                      return;
                                    }
                                  }
                                }
                                final updatedProp =
                                    _currentPropriedade!.copyWith(
                                  nome: nomeController.text,
                                  dono: donoController.text,
                                  hasLotes: hasLotes,
                                  statusSync: 'pending_update',
                                );
                                await SQLiteHelper.instance
                                    .updatePropriedade(updatedProp);
                              }

                              if (mounted) {
                                Navigator.of(ctx).pop();
                                if (!_currentPropriedade!.hasLotes &&
                                    hasLotes) {
                                  Navigator.of(ctx).pop();
                                }
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text("Lote atualizado!"),
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

  Future<Propriedade?> _showCreateLoteModal(
      BuildContext context, Propriedade propriedadePai) async {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController();
    final donoController = TextEditingController(text: propriedadePai.dono);

    return showDialog<Propriedade>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text("Ativar Lotes em ${propriedadePai.nome}"),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    "Para habilitar os lotes, você precisa criar o primeiro. Todas as éguas existentes nesta propriedade serão movidas para ele."),
                const SizedBox(height: 20),
                TextFormField(
                  controller: nomeController,
                  decoration: const InputDecoration(
                      labelText: "Nome do Lote",
                      prefixIcon: Icon(Icons.location_on_outlined)),
                  validator: (value) =>
                      value!.isEmpty ? "Campo obrigatório" : null,
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: donoController,
                  decoration: const InputDecoration(
                      labelText: "Dono do Lote",
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (value) =>
                      value!.isEmpty ? "Campo obrigatório" : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.darkGreen),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final novoLote = Propriedade(
                    id: const Uuid().v4(),
                    nome: nomeController.text,
                    dono: donoController.text,
                    parentId: propriedadePai.id,
                    statusSync: 'pending_create',
                  );
                  await SQLiteHelper.instance.createPropriedade(novoLote);
                  Navigator.of(context).pop(novoLote);
                }
              },
              child: const Text("Criar e Mover Éguas"),
            ),
          ],
        );
      },
    );
  }

  void _showDeletePropriedadeConfirmationDialog(
      BuildContext modalContext, Propriedade propToDelete) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Confirmar Exclusão"),
        content: Text(
            'Tem certeza que deseja excluir "${propToDelete.nome}"? Todos os lotes, éguas e manejos associados serão perdidos.'),
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
              await SQLiteHelper.instance.softDeletePropriedade(propToDelete.id);
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
      appBar:
          _isSelectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
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
        widget.propriedadeNome.toUpperCase(),
        style: const TextStyle(fontSize: 18, color: AppTheme.lightGrey),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () {
            _currentPropriedade!.hasLotes
              ? _showSubPropOptionsModal(context)
              : _showPropOptionsModal(context);
          },
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

  Widget _buildCategoriaChip(String categoria) {
    Color chipColor;
    switch (categoria) {
      case 'Doadora':
        chipColor = AppTheme.statusDoadora;
        break;
      case 'Receptora':
        chipColor = AppTheme.statusReceptora;
        break;
      default:
        chipColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        categoria.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
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
                  propriedadeMaeId:
                      widget.propriedadeMaeId ?? widget.propriedadeId,
                ),
              ),
            ).then((_) {
              _refreshEguas();
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              if (egua.photoPath != null && egua.photoPath!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: CircleAvatar(
                  radius: 25,
                  backgroundImage: FileImage(File(egua.photoPath!)),
                ),
              ),
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
                    egua.categoria == 'Matriz'
                      ? Text(
                          egua.nome,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkText)
                        )
                      : Row(
                          children: [
                            Text(
                              egua.nome,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildCategoriaChip(egua.categoria),
                          ],
                        ),
                      if (egua.rp.isNotEmpty) ...[
                      Text("RP: ${egua.rp}",
                          style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                          ] else ...[
                      Text("Pelagem: ${egua.pelagem}",
                          style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                      ],
                      if (egua.observacao != null && egua.observacao!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Obs: ${egua.observacao!}",
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[800],
                              fontStyle: FontStyle.italic),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    if (proximoManejo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.statusDiagnostico,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_month_outlined,
                                    size: 14, color: AppTheme.darkGreen),
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
                        ),
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
      isDismissible: false,
      builder: (ctx) {
        return MoveEguasWidget(
          currentPropriedadeId: widget.propriedadeId,
          selectedEguas: _selectedEguas,
          onMoveConfirmed: () {
            _exitSelectionMode();
            _autoSync();
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
    final proprietarioController = TextEditingController(text: egua?.proprietario ?? '');
    final rpController = TextEditingController(text: egua?.rp ?? '');
    final pelagemController =
        TextEditingController(text: egua?.pelagem ?? '');
    final coberturaController =
        TextEditingController(text: egua?.cobertura ?? '');
    final obsController =
        TextEditingController(text: egua?.observacao ?? '');
    final dataPartoController = TextEditingController(
        text: egua?.dataParto == null
            ? ''
            : DateFormat('dd/MM/yyyy').format(egua!.dataParto!));

    String categoriaSelecionada = egua?.categoria ?? 'Matriz';
    bool teveParto = egua?.dataParto != null;
    String? sexoPotro = egua?.sexoPotro ?? 'Macho';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
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
                              : "Adicionar Égua em\n${widget.propriedadeNome}",
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
                          validator: (v) =>
                              v!.isEmpty ? "Obrigatório" : null),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: proprietarioController,
                        decoration: const InputDecoration(
                            labelText: "Proprietário",
                            prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) =>
                            v!.isEmpty ? "Obrigatório" : null,
                      ),
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
                          validator: (v) =>
                              v!.isEmpty ? "Obrigatório" : null),
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
                      if (categoriaSelecionada != 'Receptora')
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
                      SwitchListTile(
                        title: const Text("Teve Parto?"),
                        value: teveParto,
                        onChanged: (bool value) {
                          setModalState(() {
                            teveParto = value;
                          });
                        },
                        activeColor: AppTheme.darkGreen,
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
                                controller: dataPartoController,
                                decoration: const InputDecoration(
                                  labelText: "Data do Parto",
                                  hintText: "dd/mm/aaaa",
                                  prefixIcon: Icon(Icons.calendar_today_outlined),
                                ),
                                readOnly: true,
                                onTap: () async {
                                  DateTime? pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2101),
                                  );

                                  if (pickedDate != null) {
                                    String formattedDate = DateFormat('dd/MM/yyyy').format(pickedDate);
                                    setState(() {
                                      dataPartoController.text = formattedDate;
                                    });
                                  }
                                },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, insira uma data.';
                                  }
                                  try {
                                    DateFormat('dd/MM/yyyy').parseStrict(value);
                                    return null;
                                  } catch (e) {
                                    return 'Formato inválido (use dd/mm/aaaa).';
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              const Text("Sexo do Potro",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Text("Macho",
                                      style: TextStyle(
                                          fontWeight: sexoPotro == "Macho"
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: sexoPotro == "Macho"
                                              ? AppTheme.darkGreen
                                              : Colors.grey[600])),
                                  Switch(
                                    value: sexoPotro == "Fêmea",
                                    onChanged: (value) {
                                      setModalState(() {
                                        sexoPotro = value ? "Fêmea" : "Macho";
                                      });
                                    },
                                    activeColor: Colors.pink[200],
                                    inactiveThumbColor: AppTheme.darkGreen,
                                    inactiveTrackColor:
                                        AppTheme.darkGreen.withOpacity(0.5),
                                    thumbColor:
                                        MaterialStateProperty.resolveWith(
                                            (states) {
                                      if (states
                                          .contains(MaterialState.selected)) {
                                        return Colors.pink[200];
                                      }
                                      return AppTheme.darkGreen;
                                    }),
                                  ),
                                  Text("Fêmea",
                                      style: TextStyle(
                                          fontWeight: sexoPotro == "Fêmea"
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: sexoPotro == "Fêmea"
                                              ? Colors.pink[300]
                                              : Colors.grey[600])),
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
                              DateTime? dataPartoFinal;
                              if (teveParto) {
                                try {
                                  dataPartoFinal = DateFormat('dd/MM/yyyy')
                                      .parseStrict(dataPartoController.text);
                                } catch (e) {
                                  return;
                                }
                              }

                              final eguaData = Egua(
                                id: isEditing ? egua.id : const Uuid().v4(),
                                firebaseId: egua?.firebaseId,
                                nome: nomeController.text,
                                proprietario: proprietarioController.text,
                                rp: rpController.text,
                                pelagem: pelagemController.text,
                                categoria: categoriaSelecionada,
                                cobertura: categoriaSelecionada == 'Matriz'
                                    ? coberturaController.text
                                    : null,
                                dataParto: dataPartoFinal,
                                sexoPotro: teveParto ? (sexoPotro ?? 'Macho') : null,
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
                          child:
                              Text(isEditing ? "Salvar Alterações" : "Salvar"),
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

class ExportOptionsModal extends StatefulWidget {
  final List<Egua> eguas;
  final ScrollController scrollController;

  const ExportOptionsModal(
      {super.key, required this.eguas, required this.scrollController});

  @override
  _ExportOptionsModalState createState() => _ExportOptionsModalState();
}

class _ExportOptionsModalState extends State<ExportOptionsModal> {
  Set<String> _selectedEguas = {};
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedEguas = widget.eguas.map((e) => e.id).toSet();
  }

  void _toggleEguaSelection(String eguaId) {
    setState(() {
      if (_selectedEguas.contains(eguaId)) {
        _selectedEguas.remove(eguaId);
      } else {
        _selectedEguas.add(eguaId);
      }
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      if (value == true) {
        _selectedEguas = widget.eguas.map((e) => e.id).toSet();
      } else {
        _selectedEguas.clear();
      }
    });
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 16),
          Text('Opções de Exportação',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text('Selecionar Éguas',
              style: TextStyle(fontWeight: FontWeight.bold)),
          CheckboxListTile(
            title: const Text('Selecionar Todas'),
            value: _selectedEguas.length == widget.eguas.length,
            onChanged: _toggleSelectAll,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: widget.eguas.length,
              itemBuilder: (context, index) {
                final egua = widget.eguas[index];
                return CheckboxListTile(
                  title: Text(egua.nome),
                  value: _selectedEguas.contains(egua.id),
                  onChanged: (bool? value) {
                    _toggleEguaSelection(egua.id);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text('Selecionar Período',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(_startDate == null || _endDate == null
                ? 'Todo o período'
                : '${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}'),
            onTap: _selectDateRange,
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                child: const Text('Cancelar'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Excel'),
                onPressed: () {
                  Navigator.of(context).pop({
                    'selectedEguas': _selectedEguas,
                    'startDate': _startDate,
                    'endDate': _endDate,
                    'format': 'excel',
                  });
                },
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
                onPressed: () {
                  Navigator.of(context).pop({
                    'selectedEguas': _selectedEguas,
                    'startDate': _startDate,
                    'endDate': _endDate,
                    'format': 'pdf',
                  });
                },
              ),
            ],
          )
        ],
      ),
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
        _subProps = lotes
            .where((lote) => lote.id != widget.currentPropriedadeId)
            .toList();
        _filteredList = _subProps;
      });
    }
  }

  void _filterList() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (_step == 0) {
        _filteredList = _topLevelProps
            .where((prop) => prop.nome.toLowerCase().contains(query))
            .toList();
      } else {
        _filteredList = _subProps
            .where((lote) => lote.nome.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _handleSelection(Propriedade prop) {
    if (_step == 0) {
      if (prop.hasLotes) {
        setState(() {
          _step = 1;
          _selectedPropriedadeMae = prop;
          _searchController.clear();
        });
        _loadSubProps(prop.id);
      } else {
        _confirmAndMove(prop);
      }
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
        content: Text(
            "Deseja mover ${widget.selectedEguas.length} égua(s) para \"${destLote.nome}\"?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text("Cancelar")),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text("Mover")),
        ],
      ),
    );

    if (confirmed == true) {
      // Busca todas as éguas do lote atual para otimizar a busca.
      final eguasToMove = await SQLiteHelper.instance
          .readEguasByPropriedade(widget.currentPropriedadeId);

      for (String eguaId in widget.selectedEguas) {
        // Encontra a égua a ser movida na lista já carregada.
        final egua = eguasToMove.firstWhere((e) => e.id == eguaId);

        // Atualiza a propriedade da égua.
        final updatedEgua = egua.copyWith(
          propriedadeId: destLote.id,
          statusSync: 'pending_update',
        );
        await SQLiteHelper.instance.updateEgua(updatedEgua);

        // --- LÓGICA ADICIONADA ---
        // Busca os manejos agendados para a égua.
        final manejosToMove = await SQLiteHelper.instance.readAgendadosByEgua(eguaId);
        if (manejosToMove.isNotEmpty) {
          // Itera sobre os manejos e atualiza a propriedade de cada um.
          for (final manejo in manejosToMove) {
            final updatedManejos = manejo.copyWith(
              propriedadeId: destLote.id,
              statusSync: 'pending_update',
            );
            await SQLiteHelper.instance.updateManejo(updatedManejos);
          }
        }
        // --- FIM DA LÓGICA ADICIONADA ---
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
                  _step == 0
                      ? "Selecione a Propriedade"
                      : "Selecione o Lote em \"${_selectedPropriedadeMae!.nome}\"",
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
                ? Center(
                    child: Text(_step == 0
                        ? "Nenhuma propriedade encontrada."
                        : "Nenhum lote disponível."))
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