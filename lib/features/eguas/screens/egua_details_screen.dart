import 'package:collection/collection.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_time_picker_spinner/flutter_time_picker_spinner.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nobryo_eguas/core/database/sqlite_helper.dart';
import 'package:nobryo_eguas/core/models/egua_model.dart';
import 'package:nobryo_eguas/core/models/manejo_model.dart';
import 'package:nobryo_eguas/core/models/medicamento_model.dart';
import 'package:nobryo_eguas/core/models/peao_model.dart';
import 'package:nobryo_eguas/core/models/propriedade_model.dart';
import 'package:nobryo_eguas/core/models/user_model.dart';
import 'package:nobryo_eguas/core/services/auth_service.dart';
import 'package:nobryo_eguas/core/services/export_service.dart';
import 'package:nobryo_eguas/core/services/sync_service.dart';
import 'package:nobryo_eguas/shared/theme/theme.dart';
import 'package:uuid/uuid.dart';

class EguaDetailsScreen extends StatefulWidget {
  final Egua egua;
  final Function(String eguaId)? onEguaDeleted;
  final Function(Egua egua)? onEguaUpdated;
  final String propriedadeMaeId;

  const EguaDetailsScreen({
    super.key,
    required this.egua,
    this.onEguaDeleted,
    this.onEguaUpdated,
    required this.propriedadeMaeId,
  });

  @override
  State<EguaDetailsScreen> createState() => _EguaDetailsScreenState();
}

class _EguaDetailsScreenState extends State<EguaDetailsScreen>
    with AutomaticKeepAliveClientMixin<EguaDetailsScreen> {
  late Egua _currentEgua;
  Future<List<Manejo>>? _historicoFuture;
  Future<List<Manejo>>? _agendadosFuture;
  final ExportService _exportService = ExportService();
  int? _diasPrenheCalculado;
  DateTime? _previsaoParto;
  Map<String, AppUser> _allUsers = {};
  Map<String, Peao> _allPeoes = {};
  Map<String, Egua> _allEguas = {};
  Map<String, Propriedade> _allPropriedades = {};
  Map<String, Medicamento> _allMedicamentos = {}; 
  final SyncService _syncService = SyncService();
  final AuthService _authService = AuthService();

  DateTime? _startDate;
  DateTime? _endDate;

  String? _selectedManejoType;
  // ignore: unused_field
  final List<String> _manejoTypes = [
    "Todos",
    "Controle Folicular",
    "Inseminação",
    "Lavado",
    "Diagnóstico",
    "Transferência de Embrião",
    "Coleta de Embrião",
    "Outros Manejos"
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentEgua = widget.egua;
    refreshData();
  }

  void refreshData() {
    SQLiteHelper.instance.getEguaById(widget.egua.id).then((refreshedEgua) {
      if (refreshedEgua == null) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      if (mounted) {
        setState(() {
          _currentEgua = refreshedEgua;
          _historicoFuture = SQLiteHelper.instance
              .readHistoricoByEgua(_currentEgua.id, startDate: _startDate, endDate: _endDate);
          _agendadosFuture =
              SQLiteHelper.instance.readAgendadosByEgua(_currentEgua.id);
        });
        _loadAuxiliaryData();
      }
    });
  }

  Future<void> _autoSync() async {
    await _syncService.syncData(isManual: false);
    if (mounted) {
      refreshData();
    }
  }

  Future<void> _pickAndUpdateEguaImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (image != null && mounted) {
      final updatedEgua = _currentEgua.copyWith(
        photoPath: image.path,
        statusSync: 'pending_update',
      );

      await SQLiteHelper.instance.updateEgua(updatedEgua);
      
      setState(() {
        _currentEgua = updatedEgua;
      });

      _autoSync();
    }
  }
/*
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (image != null && mounted) {
      final updatedEgua = _currentEgua.copyWith(
        photoPath: image.path,
        statusSync: 'pending_update',
      );

      await SQLiteHelper.instance.updateEgua(updatedEgua);
      
      setState(() {
        _currentEgua = updatedEgua;
      });

      _autoSync();
    }
  }
*/
  Future<void> _loadAuxiliaryData() async {
    final usersFuture = SQLiteHelper.instance.getAllUsers();
    final peoesFuture =
        SQLiteHelper.instance.readPeoesByPropriedade(widget.propriedadeMaeId);
    final eguasFuture = SQLiteHelper.instance.getAllEguas();
    final propriedadesFuture = SQLiteHelper.instance.readAllPropriedades();
    final medicamentosFuture = SQLiteHelper.instance.readAllMedicamentos();

    final results = await Future.wait([usersFuture, peoesFuture, eguasFuture, propriedadesFuture, medicamentosFuture]);

    if (mounted) {
      final users = results[0] as List<AppUser>;
      final peoes = results[1] as List<Peao>;
      final eguas = results[2] as List<Egua>;
      final propriedades = results[3] as List<Propriedade>;
      final medicamentos = results[4] as List<Medicamento>;
      setState(() {
        _allUsers = {for (var u in users) u.uid: u};
        _allPeoes = {for (var p in peoes) p.id: p};
        _allEguas = {for (var e in eguas) e.id: e};
        _allPropriedades = {for (var p in propriedades) p.id: p};
        _allMedicamentos = {for (var m in medicamentos) m.id: m};
      });
    }
    _calcularDiasPrenhe();
    _calcularPrevisaoParto();
  }

  void _calcularDiasPrenhe() async {
    if (_currentEgua.statusReprodutivo.toLowerCase() != 'prenhe' ||
        _historicoFuture == null) {
      if (mounted) setState(() => _diasPrenheCalculado = null);
      return;
    }

    final historico = await _historicoFuture!;
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

      if (mounted) {
        setState(() {
          _diasPrenheCalculado = diasNoDiagnostico + diasDesdeDiagnostico;
        });
      }
    } else {
      if (mounted) {
        setState(() => _diasPrenheCalculado = _currentEgua.diasPrenhe);
      }
    }
  }

  void _calcularPrevisaoParto() async {
    if (_currentEgua.statusReprodutivo.toLowerCase() != 'prenhe' ||
        _historicoFuture == null) {
      if (mounted) setState(() => _previsaoParto = null);
      return;
    }

    final historico = await _historicoFuture!;
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
        final previsao = DateTime(
            dataInseminacao.year, dataInseminacao.month + 11, dataInseminacao.day);
        if (mounted) {
          setState(() {
            _previsaoParto = previsao;
          });
        }
      } else {
        if (mounted) setState(() => _previsaoParto = null);
      }
    } else {
      if (mounted) setState(() => _previsaoParto = null);
    }
  }

  void _showDeleteConfirmationDialog(BuildContext screenContext) {
    showDialog(
      context: screenContext,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Confirmar Exclusão"),
        content: Text(
            "Tem certeza que deseja excluir a égua \"${_currentEgua.nome}\"? Todos os seus manejos também serão excluídos."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text("Cancelar"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final eguaId = _currentEgua.id;
              await SQLiteHelper.instance.softDeleteEgua(eguaId);
              _autoSync();
              if (!mounted) return;

              Navigator.of(dialogCtx).pop();

              if (widget.onEguaDeleted != null) {
                widget.onEguaDeleted!(eguaId);
              } else {
                Navigator.of(screenContext).pop();
              }
            },
            child: const Text("Excluir"),
          ),
        ],
      ),
    );
  }

  void _handleEditEgua(BuildContext screenContext) async {
    final result = await showModalBottomSheet(
      context: screenContext,
      isScrollControlled: true,
      isDismissible: false,
      builder: (modalCtx) {
        return _EditEguaForm(egua: _currentEgua);
      },
    );

    if (result == 'wants_to_delete' && mounted) {
      _showDeleteConfirmationDialog(screenContext);
    } else if (result is Egua && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Dados da égua atualizados!"),
        backgroundColor: Colors.green,
      ));
      refreshData();
      widget.onEguaUpdated?.call(result);
    }
  }

  Future<void> _promptForInseminationScheduleOnInduction(
      BuildContext context, Egua egua, Propriedade propriedade, DateTime inductionDate) async {
    
    final DateTime inseminationDate = inductionDate.add(const Duration(hours: 36));
    final String formattedDate =
        DateFormat('dd/MM/yyyy \'às\' HH:mm', 'pt_BR').format(inseminationDate);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Agendamento Automático"),
        content: Text(
            "Indução concluída para a égua ${egua.nome}. Deseja agendar a inseminação para daqui a 36 horas (${formattedDate}h)?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Não"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Sim"),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _showAddAgendamentoModal(
        context,
        preselectedType: "Inseminação",
        preselectedDate: inseminationDate,
      );
    }
  }

  Future<void> _promptForDiagnosticSchedule(DateTime inseminationDate) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Agendamento Automático"),
        content: const Text(
            "Inseminação concluída. Deseja agendar o diagnóstico de prenhez para daqui a 14 dias?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Não"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Sim"),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _showAddAgendamentoModal(
        context,
        preselectedType: "Diagnóstico",
        preselectedDate: inseminationDate.add(const Duration(days: 14)),
      );
    }
  }

  Future<void> _promptForFollicularControlSchedule(DateTime controlDate, String follicleSizeRight, String follicleSizeLeft) async {
    final double? sizeRight = double.tryParse(follicleSizeRight.replaceAll(',', '.'));
    final double? sizeLeft = double.tryParse(follicleSizeLeft.replaceAll(',', '.'));

    double? currentMaxSize;
    if (sizeRight != null && sizeLeft != null) {
      currentMaxSize = sizeRight > sizeLeft ? sizeRight : sizeLeft;
    } else if (sizeRight != null) {
      currentMaxSize = sizeRight;
    } else if (sizeLeft != null) {
      currentMaxSize = sizeLeft;
    }

    if (currentMaxSize == null || currentMaxSize >= 33) {
      return;
    }

    const double targetSize = 33.0;
    const double growthRate = 3.0;
    final double sizeDifference = targetSize - currentMaxSize;
    final int daysToReachTarget = (sizeDifference / growthRate).ceil();

    if (daysToReachTarget <= 0) {
      return;
    }

    final DateTime scheduledDate = controlDate.add(Duration(days: daysToReachTarget));
    final String formattedDate = DateFormat('dd/MM/yyyy').format(scheduledDate);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Agendamento Automático"),
        content: Text(
            "O folículo atingirá aproximadamente 33mm em $formattedDate. Deseja agendar um novo Controle Folicular para este dia?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Não"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Sim"),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _showAddAgendamentoModal(
        context,
        preselectedType: "Controle Folicular",
        preselectedDate: scheduledDate,
      );
    }
  }

  Future<void> _updateEguaStatusAfterDeletion() async {
    final historicoCompleto = await SQLiteHelper.instance.readHistoricoByEgua(_currentEgua.id);
    historicoCompleto.sort((a, b) => b.dataAgendada.compareTo(a.dataAgendada));

    final ultimoParto = historicoCompleto.firstWhereOrNull((m) =>
        m.tipo.toLowerCase() == 'diagnóstico' &&
        m.detalhes['resultado']?.toString().toLowerCase() == 'pariu');

    final ultimoDiagnostico = historicoCompleto.firstWhereOrNull(
        (m) => m.tipo.toLowerCase() == 'diagnóstico');

    Egua eguaParaAtualizar = _currentEgua;

    if (ultimoParto != null) {
      final dataParto = DateTime.tryParse(ultimoParto.detalhes['dataHoraParto'] ?? '');
      final sexoPotro = ultimoParto.detalhes['sexoPotro'] as String?;
      eguaParaAtualizar = eguaParaAtualizar.copyWith(dataParto: dataParto, sexoPotro: sexoPotro);
    } else {
      eguaParaAtualizar = eguaParaAtualizar.copyWith(dataParto: null, sexoPotro: null);
    }
    
    if (ultimoDiagnostico == null ||
        ['vazia', 'indeterminado', 'pariu'].contains(ultimoDiagnostico.detalhes['resultado']?.toString().toLowerCase())) {
      eguaParaAtualizar = eguaParaAtualizar.copyWith(
        statusReprodutivo: 'Vazia',
        diasPrenhe: 0,
        cobertura: ''
      );
    } else if (ultimoDiagnostico.detalhes['resultado']?.toString().toLowerCase() == 'prenhe') {
      final dias = int.tryParse(ultimoDiagnostico.detalhes['diasPrenhe']?.toString() ?? '0') ?? 0;
      final cobertura = ultimoDiagnostico.detalhes['garanhao'] as String?;
      eguaParaAtualizar = eguaParaAtualizar.copyWith(
        statusReprodutivo: 'Prenhe',
        diasPrenhe: dias,
        cobertura: cobertura
      );
    }

    await SQLiteHelper.instance.updateEgua(eguaParaAtualizar.copyWith(statusSync: 'pending_update'));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.darkGreen,
        foregroundColor: AppTheme.lightGrey,
        title: Text("ÉGUA - ${_currentEgua.nome.toUpperCase()}",
            style: const TextStyle(fontSize: 18, color: AppTheme.lightGrey)),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _showMoveEguaModal,
            tooltip: "Mover Égua",
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _showExportOptions(context),
            tooltip: "Exportar Histórico Individual",
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _handleEditEgua(context),
            tooltip: "Editar Égua",
          ),
        ],
      ),
      body: RefreshIndicator( // ADICIONADO
        onRefresh: () async {
          await _autoSync();
          refreshData();
        },
        child: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_currentEgua.photoPath != null &&
                            _currentEgua.photoPath!.isNotEmpty) ...[
                          Column(
                            children: [
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12.0),
                                    child: Image.file(
                                      File(_currentEgua.photoPath!),
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 175,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => _pickAndUpdateEguaImage(),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: const BoxDecoration(
                                          color: AppTheme.brown,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 6,
                                              offset: Offset(0, 2),
                                            )
                                          ],
                                        ),
                                        child: const Icon(Icons.edit,
                                            color: Colors.white, size: 24),
                                      ),
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      const SizedBox(height: 220),
                                      const Text("Informações da Égua",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.darkText)),
                                      const SizedBox(height: 15),
                                    ],
                                  )
                                ],
                              ),
                            ]
                          ),
                        ] else ...[
                          const Text("Informações da Égua",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkText)),
                          const SizedBox(height: 15)
                        ],
                        _buildInfoCard(_currentEgua),
                        const SizedBox(height: 24),
                        const Text("Próximos Agendamentos",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkText)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text("Agendar Novo Manejo"),
                            onPressed: () => _showAddAgendamentoModal(context),
                            style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildManejoList(_agendadosFuture, isHistorico: false),
                        const SizedBox(height: 24),
                            const Text("Histórico de Manejos Concluídos",
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.darkText)),
                            Row(
                              children: [
                                Expanded(
                                  child: ListTile(
                                    title: Text(
                                      _startDate == null || _endDate == null
                                          ? 'Selecione um período'
                                          : '${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}',
                                    ),
                                    trailing: Icon(Icons.calendar_today),
                                    onTap: () async {
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
                                          refreshData();
                                        });
                                      }
                                    },
                                  ),
                                ),
                                if (_startDate != null || _endDate != null)
                                  IconButton(
                                    icon: Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        _startDate = null;
                                        _endDate = null;
                                        refreshData();
                                      });
                                    },
                                  ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedManejoType,
                                    hint: const Text("Tipo"),
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                                      prefixIcon: const Icon(Icons.filter_list),
                                      suffixIcon: _selectedManejoType != null
                                          ? IconButton(
                                              icon: const Icon(Icons.clear, size: 20),
                                              onPressed: () {
                                                setState(() {
                                                  _selectedManejoType = null;
                                                });
                                              },
                                            )
                                          : null,
                                    ),
                                    items: _manejoTypes
                                        .map((tipo) => DropdownMenuItem(
                                              value: tipo,
                                              child: Text(tipo),
                                            ))
                                        .toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == "Todos") {
                                          _selectedManejoType = null;
                                        } else {
                                          _selectedManejoType = val;
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                        const SizedBox(height: 10),
                        _buildManejoList(_historicoFuture, isHistorico: true),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.pageBackground,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 0,
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brown),
                onPressed: () => _showAddHistoricoModal(context, isEditing: false),
                child: const Text("Adicionar Manejo ao Histórico"),
              ),
            ),
          ],
        ),
      )
    );
  }

  void _showMoveEguaModal() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (ctx) {
        return MoveEguasWidget(
          currentPropriedadeId: _currentEgua.propriedadeId,
          selectedEguas: {_currentEgua.id},
          onMoveConfirmed: () {
            if (mounted) {
              widget.onEguaDeleted?.call(_currentEgua.id);
              _autoSync();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Égua transferida com sucesso!"),
                backgroundColor: Colors.green,
              ));
            }
          },
        );
      },
    );
  }

  Widget _buildInfoCard(Egua egua) {
    final statusColor = egua.statusReprodutivo.toLowerCase() == 'prenhe'
        ? AppTheme.statusPrenhe
        : AppTheme.statusVazia;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.offWhite, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildInfoItem("Nome:", egua.nome)),
              if (egua.proprietario != null && egua.proprietario!.isNotEmpty)
                Expanded(child: _buildInfoItem("Proprietário:", egua.proprietario!)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildInfoItem("Pelagem:", egua.pelagem)),
              if (egua.rp.isNotEmpty)
                Expanded(child: _buildInfoItem("RP:", egua.rp)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCategoriaChip(egua.categoria)),
              if (egua.categoria != 'Receptora' &&
                  egua.cobertura != null &&
                  egua.cobertura!.isNotEmpty)
                Expanded(child: _buildInfoItem("Padreador:", egua.cobertura!)),
            ],
          ),
          if (egua.dataParto != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _buildInfoItem("Último Parto:",
                        DateFormat('dd/MM/yyyy').format(egua.dataParto!))),
                if (egua.sexoPotro != null && egua.sexoPotro!.isNotEmpty)
                  Expanded(
                      child: _buildInfoItem("Sexo do Potro:", egua.sexoPotro!)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (egua.observacao != null && egua.observacao!.isNotEmpty) ...[
            _buildInfoItem("Observação:", egua.observacao!),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8.0,
            runSpacing: 6.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(egua.statusReprodutivo.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              if (_diasPrenheCalculado != null && _diasPrenheCalculado! > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppTheme.brown,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text("$_diasPrenheCalculado DIAS",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              if (_previsaoParto != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.child_friendly,
                          color: Colors.pink[300], size: 14),
                      const SizedBox(width: 4),
                      Text(
                        "Parto: ${DateFormat('dd/MM/yy').format(_previsaoParto!)}",
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
          )
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: AppTheme.darkText,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Categoria:", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            categoria.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManejoList(Future<List<Manejo>>? future,
      {required bool isHistorico}) {
    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return FutureBuilder<List<Manejo>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text("Erro: ${snapshot.error}"));
        }

        final allManejos = snapshot.data ?? [];

        final List<Manejo> manejos;
        if (isHistorico && _selectedManejoType != null) {
          manejos = allManejos
              .where((manejo) => manejo.tipo == _selectedManejoType)
              .toList();
        } else {
          manejos = allManejos;
        }

        if (manejos.isEmpty) {
          return Center(
            child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              isHistorico
                  ? "Nenhum manejo encontrado para este filtro."
                  : "Nenhum manejo agendado.",
              style: const TextStyle(color: Colors.grey)),
          ));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: manejos.length,
          itemBuilder: (context, index) {
            final manejo = manejos[index];

            String responsavelNome = '...';
            if (manejo.responsavelId != null) {
              responsavelNome =
                  _allUsers[manejo.responsavelId]?.nome ?? 'Usuário desconhecido';
            } else if (manejo.responsavelPeaoId != null) {
              responsavelNome =
                  _allPeoes[manejo.responsavelPeaoId]?.nome ?? 'Peão desconhecido';
            }

            String concluidoPorNome = '...';
            if (manejo.concluidoPorId != null) {
              concluidoPorNome =
                  _allUsers[manejo.concluidoPorId]?.nome ?? 'Usuário desconhecido';
            } else if (manejo.concluidoPorPeaoId != null) {
              concluidoPorNome =
                  _allPeoes[manejo.concluidoPorPeaoId]?.nome ??
                      'Peão desconhecido';
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: isHistorico
                    ? null
                    : () => _showConfirmationModal(context, manejo),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (isHistorico) ...[
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm')
                                .format(manejo.dataAgendada),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                          ] else ...[
                            Text(
                              DateFormat('dd/MM/yyyy')
                                  .format(manejo.dataAgendada),
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                          ],
                          if (isHistorico)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert,
                                  size: 20, color: Colors.grey),
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showAddHistoricoModal(context,
                                      manejo: manejo, isEditing: true);
                                } else if (value == 'delete') {
                                  _showDeleteManejoConfirmationDialog(manejo);
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
                                    leading: Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    title: Text('Excluir',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ),
                              ],
                            )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (isHistorico)
                            _buildManejoTitle(manejo.tipo)
                          else
                            Expanded(
                              child: Text(
                                manejo.tipo,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkText,
                                ),
                              ),
                            ),
                          if (!isHistorico)
                            const Icon(Icons.chevron_right,
                                color: Colors.grey, size: 20)
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isHistorico)
                        Text("Concluído por: $concluidoPorNome",
                            style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                                fontStyle: FontStyle.italic))
                      else
                        Text("Responsável: $responsavelNome",
                            style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                                fontStyle: FontStyle.italic)),
                      if (isHistorico && manejo.detalhes.isNotEmpty) ...[
                        const Divider(height: 20, thickness: 0.5),
                        _buildDetalhesManejo(manejo),
                      ]
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

  Widget _buildManejoTitle(String tipo) {
    if (tipo == 'Inseminação') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.statusPrenhe,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          tipo.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    } else {
      return Text(
        tipo,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppTheme.darkText,
        ),
      );
    }
  }

Widget _buildDetalhesManejo(Manejo manejo) {
  final detalhes = manejo.detalhes;
  const labelMap = {
    'resultado': 'Resultado',
    'resultadoParto': 'Resultado do Parto',
    'diasPrenhe': 'Dias de Prenhez',
    'garanhao': 'Garanhão',
    'tipoSemem': 'Tipo de Sêmen',
    'quantidadePalhetas': 'Quantidade de Palhetas',
    'dataHora': 'Data/Hora da Inseminação',
    'litros': 'Litros',
    'medicamento': 'Medicamento',
    'ovarioDireito': 'Ovário Direito',
    'ovarioDireitoTamanho': 'Tamanho Fl. Direito',
    'ovarioEsquerdo': 'Ovário Esquerdo',
    'ovarioEsquerdoTamanho': 'Tamanho Fl. Esquerdo',
    'edema': 'Edema',
    'utero': 'Útero',
    'idadeEmbriao': 'Idade do Embrião',
    'doadora': 'Doadora',
    'avaliacaoUterina': 'Avaliação Uterina',
    'observacao': 'Observação',
    'inducao': 'Indução',
    'dataHoraInducao': 'Data/Hora da Indução',
    'sexoPotro': 'Sexo do Potro',
    'pelagemPotro': 'Pelagem do Potro',
    'dataHoraParto': 'Data e Hora do Parto',
    'observacoesParto': 'Observações do Parto',
    'tratamento': 'Tratamento',
  };

    String formatValue(String key, dynamic value) {
      if (value is String) {
        if (key == 'dataHora' || key == 'dataHoraInducao' || key == 'dataHoraParto') {
          try {
            final dt = DateTime.parse(value);
            return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dt);
          } catch (e) {
            return value;
          }
        }
      }
      return value.toString();
    }

    final List<Widget> children = [];

     if (manejo.tipo == 'Controle Folicular' && manejo.medicamentoId != null) {
    final medicamento = _allMedicamentos[manejo.medicamentoId];
    if (medicamento != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 14, color: Colors.grey[800]),
              children: [
                const TextSpan(
                  text: "Medicamento (Indução): ",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: medicamento.nome),
              ],
            ),
          ),
        ),
      );
    }
  }
  
    final detailEntries = detalhes.entries
        .where((entry) =>
            entry.value != null &&
            entry.value.toString().isNotEmpty &&
            labelMap.containsKey(entry.key))
        .toList();

    for (final entry in detailEntries) {
      if (entry.key == 'inducao' || entry.key == 'resultadoParto') {
       final bool isSuccess = entry.key == 'resultadoParto' ? entry.value == 'Criou' : true;
       final Color chipColor = entry.key == 'inducao' 
        ? AppTheme.statusDiagnostico
        : isSuccess ? AppTheme.darkGreen : Theme.of(context).colorScheme.error;

        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6.0,
              children: [
                Text(
                  "${labelMap[entry.key]}:",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: chipColor,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    formatValue(entry.key, entry.value).toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (entry.key == 'resultado' && entry.value.toString().toLowerCase() == 'pariu') {
         children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6.0,
              children: [
                Text(
                  "${labelMap[entry.key]}:",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.lightBlue[300],
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    formatValue(entry.key, entry.value).toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                children: [
                  TextSpan(
                    text: "${labelMap[entry.key]}: ",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: formatValue(entry.key, entry.value)),
                ],
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  void _showDeleteManejoConfirmationDialog(Manejo manejo) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Excluir Manejo do Histórico"),
        content: Text(
            "Tem certeza que deseja excluir o manejo de '${manejo.tipo}' do dia ${DateFormat('dd/MM/yyyy').format(manejo.dataAgendada)}? Esta ação não pode ser desfeita."),
        actions: [
          TextButton(
            child: const Text("Cancelar"),
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
            child: const Text("Confirmar Exclusão"),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();

              await SQLiteHelper.instance.softDeleteManejo(manejo.id);
              
              final tipo = manejo.tipo.toLowerCase();
              final resultado = manejo.detalhes['resultado']?.toString().toLowerCase();

              if (tipo == 'diagnóstico' && (resultado == 'prenhe' || resultado == 'pariu')) {
                   await _updateEguaStatusAfterDeletion();
              }

              if (mounted) {
                refreshData();
                _autoSync();
                ScaffoldMessenger.of(context)
                  ..removeCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: const Text("Manejo excluído do histórico."),
                    backgroundColor: Colors.red[700],
                  ));
              }
            },
          ),
        ],
      ),
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
              onTap: () async {
                Navigator.of(ctx).pop();
                if (_historicoFuture == null) return;
                final historico = await _historicoFuture!;
                if (historico.isNotEmpty) {
                  await _exportService.exportarParaExcel(
                      _currentEgua, historico, context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Não há histórico para exportar."),
                  ));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Exportar para PDF (.pdf)'),
              onTap: () async {
                Navigator.of(ctx).pop();
                if (_historicoFuture == null) return;
                final historico = await _historicoFuture!;
                if (historico.isNotEmpty) {
                  await _exportService.exportarParaPdf(
                      _currentEgua, historico, context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Não há histórico para exportar."),
                  ));
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showAddAgendamentoModal(BuildContext context,
      {DateTime? preselectedDate, String? preselectedType}) async {
    final currentUser = _authService.currentUserNotifier.value;
    if (currentUser == null) return;

    final allUsersList = await SQLiteHelper.instance.getAllUsers();
    final peoesDaPropriedade =
        await SQLiteHelper.instance.readPeoesByPropriedade(widget.propriedadeMaeId);
    final propriedade =
        await SQLiteHelper.instance.readPropriedade(_currentEgua.propriedadeId);

    final formKey = GlobalKey<FormState>();
    DateTime? dataSelecionada = preselectedDate;
    String? tipoManejoSelecionado = preselectedType;
    final detalhesController = TextEditingController();
    final tiposDeManejo = [
      "Controle Folicular",
      "Inseminação",
      "Lavado",
      "Diagnóstico",
      "Transferência de Embrião",
      "Coleta de Embrião",
      "Outros Manejos"
    ];

    dynamic responsavelSelecionado;
    bool isVeterinario = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,

      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          List<DropdownMenuItem<dynamic>> veterinarioItems = [
            const DropdownMenuItem<dynamic>(
              enabled: false,
              child: Text("Veterinários",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
            ),
            ...allUsersList
                .map((user) => DropdownMenuItem<dynamic>(
                    value: user, child: Text(user.nome)))
                .toList(),
          ];

          List<DropdownMenuItem<dynamic>> cabanhaItems = [];
          if (propriedade != null) {
            cabanhaItems.add(
              const DropdownMenuItem<dynamic>(
                enabled: false,
                child: Text("Proprietário",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppTheme.brown)),
              ),
            );
            cabanhaItems.add(
              DropdownMenuItem<dynamic>(
                value: propriedade.dono,
                child: Text(propriedade.dono),
              ),
            );
          }

          if (peoesDaPropriedade.isNotEmpty) {
            cabanhaItems.add(const DropdownMenuItem<dynamic>(
                enabled: false, child: Divider()));
            cabanhaItems.add(const DropdownMenuItem<dynamic>(
              enabled: false,
              child: Text("Peões da Propriedade",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.brown)),
            ));
            cabanhaItems.addAll(peoesDaPropriedade
                .map((peao) =>
                    DropdownMenuItem<dynamic>(value: peao, child: Text(peao.nome)))
                .toList());
          }

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
                    Text("Agendar para ${_currentEgua.nome}",
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: 30, thickness: 1),
                    const SizedBox(height: 10),
                    TextFormField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: dataSelecionada == null
                            ? ''
                            : DateFormat('dd/MM/yyyy').format(dataSelecionada!),
                      ),
                      decoration: const InputDecoration(
                          labelText: "Data do Manejo",
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          hintText: 'Toque para selecionar a data'),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: dataSelecionada ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030));
                        if (pickedDate != null) {
                          setModalState(() => dataSelecionada = pickedDate);
                        }
                      },
                      validator: (v) =>
                          dataSelecionada == null ? "Obrigatório" : null,
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: tipoManejoSelecionado,
                      decoration: const InputDecoration(
                        labelText: "Tipo de Manejo",
                        prefixIcon: Icon(Icons.edit_note_outlined),
                      ),
                      hint: const Text("Obrigatório"),
                      items: tiposDeManejo
                          .map((tipo) =>
                              DropdownMenuItem(value: tipo, child: Text(tipo)))
                          .toList(),
                      onChanged: (val) =>
                          setModalState(() => tipoManejoSelecionado = val),
                      validator: (v) => v == null ? "Obrigatório" : null,
                    ),
                    const SizedBox(height: 15),
                    SwitchListTile(
                      title: Text(
                          isVeterinario ? 'Veterinário' : 'Da Cabanha'),
                      value: isVeterinario,
                      onChanged: (bool value) {
                        setModalState(() {
                          isVeterinario = value;
                          responsavelSelecionado = null;
                        });
                      },
                      secondary: Icon(isVeterinario
                          ? Icons.medical_services_outlined
                          : Icons.home_work_outlined),
                    ),
                    DropdownButtonFormField<dynamic>(
                      value: responsavelSelecionado,
                      decoration: const InputDecoration(
                        labelText: "Responsável",
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      items: isVeterinario ? veterinarioItems : cabanhaItems,
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => responsavelSelecionado = value);
                        }
                      },
                      validator: (v) => v == null ? "Obrigatório" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                        controller: detalhesController,
                        decoration: const InputDecoration(
                            labelText: "Detalhes/Observações",
                            prefixIcon: Icon(Icons.comment_outlined)),
                        maxLines: 2),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final novoManejo = Manejo(
                              id: const Uuid().v4(),
                              tipo: tipoManejoSelecionado!,
                              dataAgendada: dataSelecionada!,
                              detalhes: {'descricao': detalhesController.text},
                              eguaId: _currentEgua.id,
                              propriedadeId: _currentEgua.propriedadeId,
                              responsavelId: responsavelSelecionado is AppUser
                                  ? responsavelSelecionado.uid
                                  : null,
                              responsavelPeaoId:
                                  responsavelSelecionado is Peao
                                      ? responsavelSelecionado.id
                                      : null,
                            );
                            await SQLiteHelper.instance
                                .createManejo(novoManejo);
                            if (mounted) {
                              Navigator.of(ctx).pop();
                              _autoSync();
                            }
                          }
                        },
                        child: const Text("Agendar"),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showConfirmationModal(BuildContext context, Manejo manejo) {
    String responsavelNome = '...';
    if (manejo.responsavelId != null) {
      responsavelNome = _allUsers[manejo.responsavelId]?.nome ?? 'Desconhecido';
    } else if (manejo.responsavelPeaoId != null) {
      responsavelNome = _allPeoes[manejo.responsavelPeaoId]?.nome ?? 'Desconhecido';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (ctx) {
        
        void reagendarLocal() async {
          Navigator.of(ctx).pop();
          final novaData = await showDatePicker(
              context: context,
              initialDate: manejo.dataAgendada,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030));
          if (novaData != null) {
            manejo.dataAgendada = novaData;
            manejo.statusSync = 'pending_update';
            await SQLiteHelper.instance.updateManejo(manejo);
            refreshData();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Data do manejo reagendada!"),
                  backgroundColor: Colors.green));
            }
          }
        }

        void deletarLocal() async {
          Navigator.of(ctx).pop();
          showDialog(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: const Text("Excluir Agendamento"),
              content: Text(
                  "Tem certeza que deseja excluir o manejo de '${manejo.tipo}' para a égua ${_currentEgua.nome}? Esta ação não pode ser desfeita."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text("Cancelar")),
                TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                    onPressed: () async {
                      await SQLiteHelper.instance.softDeleteManejo(manejo.id);
                      if (mounted) {
                        Navigator.of(dialogCtx).pop();
                        refreshData();
                        _autoSync();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text("Agendamento excluído."),
                            backgroundColor: Colors.red[700]));
                      }
                    },
                    child: const Text("Excluir")),
              ],
            ),
          );
        }

        final observacao = manejo.detalhes['descricao'];
        final textoObservacao = (observacao != null && observacao.isNotEmpty)
            ? observacao
            : "Nenhuma observação.";

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text("Detalhes do Agendamento",
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                          if (value == 'edit') {
                              _showEditAgendamentoModal(ctx, manejo: manejo);
                          } else if (value == 'reschedule') {
                              reagendarLocal();
                          } else if (value == 'delete') {
                              deletarLocal();
                          }
                      },
                      itemBuilder: (BuildContext popupContext) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.notes_outlined),
                            title: Text('Editar Agendamento'),
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'reschedule',
                          child: ListTile(
                            leading: Icon(Icons.edit_calendar_outlined),
                            title: Text('Reagendar'),
                          ),
                        ),
                          PopupMenuItem<String>(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline, color: Colors.red),
                            title: Text('Excluir Agendamento', style: TextStyle(color: Colors.red)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                    Icons.calendar_today_outlined,
                    "Data Agendada",
                    DateFormat('EEEE, dd/MM/yyyy', 'pt_BR')
                        .format(manejo.dataAgendada)),
                const SizedBox(height: 12),
                _buildDetailRow(
                    Icons.edit_note_outlined, "Tipo de Manejo", manejo.tipo),
                const SizedBox(height: 12),
                _buildDetailRow(Icons.person_outline, "Responsável", responsavelNome),
                const SizedBox(height: 12),
                _buildDetailRow(Icons.comment_outlined, "Observação", textoObservacao),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text("Concluir Manejo"),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showMarkAsCompleteModal(context, manejo);
                      },
                      style: ElevatedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14))),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditAgendamentoModal(BuildContext context, {required Manejo manejo}) async {
    final currentUser = _authService.currentUserNotifier.value;
    if (currentUser == null) return;

    final allUsersList = await SQLiteHelper.instance.getAllUsers();
    final formKey = GlobalKey<FormState>();

    final Egua? egua = _allEguas[manejo.eguaId];
    final Propriedade? lote = _allPropriedades[manejo.propriedadeId];
    final Propriedade? propriedadeMae = lote?.parentId != null ? _allPropriedades[lote!.parentId] : lote;

    Egua? eguaSelecionada = egua;
    DateTime? dataSelecionada = manejo.dataAgendada;
    String? tipoManejoSelecionado = manejo.tipo;
    final detalhesController = TextEditingController(text: manejo.detalhes['descricao'] ?? '');
    final tiposDeManejo = [
      "Controle Folicular", "Inseminação", "Lavado", "Diagnóstico",
      "Transferência de Embrião", "Coleta de Embrião", "Outros Manejos"
    ];

    dynamic responsavelSelecionado;

    if (manejo.responsavelId != null) {
      responsavelSelecionado = allUsersList.firstWhereOrNull((u) => u.uid == manejo.responsavelId);
    } else if (manejo.responsavelPeaoId != null) {
      final peoes = await SQLiteHelper.instance.readPeoesByPropriedade(propriedadeMae?.id ?? '');
      responsavelSelecionado = peoes.firstWhereOrNull((p) => p.id == manejo.responsavelPeaoId);
    }

    if (responsavelSelecionado == null) {
      responsavelSelecionado = allUsersList.firstWhere((u) => u.uid == currentUser.uid, orElse: () => allUsersList.first);
    }

    List<Peao> peoesDaPropriedade = [];
    if (propriedadeMae != null) {
      peoesDaPropriedade = await SQLiteHelper.instance.readPeoesByPropriedade(propriedadeMae.id);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
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
                    const SizedBox(height: 10),
                    Text("Editar Agendamento",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: 30, thickness: 1),

                    if (propriedadeMae != null)
                      FutureBuilder<List<Egua>>(
                        future: () async {
                            final subPropriedades = await SQLiteHelper.instance.readSubPropriedades(propriedadeMae.id);
                            final allPropIds = [propriedadeMae.id, ...subPropriedades.map((p) => p.id)];
                            
                            List<Egua> eguasDaPropriedade = [];
                            for (final propId in allPropIds) {
                                final eguasDoLote = await SQLiteHelper.instance.readEguasByPropriedade(propId);
                                eguasDaPropriedade.addAll(eguasDoLote);
                            }
                            return eguasDaPropriedade;
                        }(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator()));
                          }
                          return DropdownButtonFormField<Egua>(
                            value: eguaSelecionada,
                            decoration: const InputDecoration(
                              labelText: "Égua",
                              prefixIcon: Icon(Icons.female_outlined),
                            ),
                            items: snapshot.data!
                                .map((egua) => DropdownMenuItem(
                                    value: egua, child: Text(egua.nome)))
                                .toList(),
                            onChanged: (egua) =>
                                setModalState(() => eguaSelecionada = egua),
                            validator: (v) => v == null ? "Selecione uma égua" : null,
                          );
                        },
                      ),
                    const SizedBox(height: 15),

                    TextFormField(
                      readOnly: true,
                      controller: TextEditingController(
                          text: dataSelecionada == null
                              ? ''
                              : DateFormat('dd/MM/yyyy').format(dataSelecionada!),
                        ),
                      decoration: const InputDecoration(
                        labelText: "Data do Manejo",
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        hintText: 'Toque para selecionar',
                      ),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: dataSelecionada ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030));
                        if (pickedDate != null) {
                          setModalState(() => dataSelecionada = pickedDate);
                        }
                      },
                      validator: (v) =>
                          dataSelecionada == null ? "Selecione a data" : null,
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: tipoManejoSelecionado,
                      decoration: const InputDecoration(
                        labelText: "Tipo de Manejo",
                        prefixIcon: Icon(Icons.edit_note_outlined),
                      ),
                      items: tiposDeManejo
                          .map((tipo) =>
                              DropdownMenuItem(value: tipo, child: Text(tipo)))
                          .toList(),
                      onChanged: (val) =>
                          setModalState(() => tipoManejoSelecionado = val),
                      validator: (v) => v == null ? "Selecione o tipo" : null,
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<dynamic>(
                      value: responsavelSelecionado,
                      decoration: const InputDecoration(labelText: "Responsável", prefixIcon: Icon(Icons.person_outline)),
                      items: [
                        const DropdownMenuItem<dynamic>(
                          enabled: false,
                          child: Text("Usuários", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
                        ),
                        ...allUsersList.map((user) => DropdownMenuItem<dynamic>(value: user, child: Text(user.nome))),
                        if (peoesDaPropriedade.isNotEmpty) ...[
                          const DropdownMenuItem<dynamic>(enabled: false, child: Divider()),
                          const DropdownMenuItem<dynamic>(
                            enabled: false,
                            child: Text("Peões da Propriedade", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.brown)),
                          ),
                          ...peoesDaPropriedade.map((peao) => DropdownMenuItem<dynamic>(value: peao, child: Text(peao.nome))),
                        ]
                      ],
                      onChanged: (value) {
                        if (value != null) setModalState(() => responsavelSelecionado = value);
                      },
                      validator: (v) => v == null ? "Selecione um responsável" : null,
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                        controller: detalhesController,
                        decoration: const InputDecoration(
                            labelText: "Detalhes/Observações",
                            prefixIcon: Icon(Icons.comment_outlined)),
                        maxLines: 2),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text("SALVAR ALTERAÇÕES"),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final manejoAtualizado = manejo.copyWith(
                              tipo: tipoManejoSelecionado!,
                              dataAgendada: dataSelecionada!,
                              detalhes: {'descricao': detalhesController.text},
                              eguaId: eguaSelecionada!.id,
                              propriedadeId: eguaSelecionada!.propriedadeId,
                              responsavelId: responsavelSelecionado is AppUser ? responsavelSelecionado.uid : null,
                              responsavelPeaoId: responsavelSelecionado is Peao ? responsavelSelecionado.id : null,
                              statusSync: 'pending_update'
                            );
                            await SQLiteHelper.instance
                                .updateManejo(manejoAtualizado);
                            if (mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text("Agendamento atualizado com sucesso!"),
                                backgroundColor: Colors.green,
                              ));
                              _autoSync();
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
          );
        },
      ),
    );
  }

  void _showMarkAsCompleteModal(BuildContext context, Manejo manejo) async {
    final currentUser = _authService.currentUserNotifier.value;
    if(currentUser == null) return;

    final allUsersList = await SQLiteHelper.instance.getAllUsers();
    final peoesDaPropriedade = await SQLiteHelper.instance.readPeoesByPropriedade(widget.propriedadeMaeId);

    final Propriedade? propriedadeMaeSelecionada =
        await SQLiteHelper.instance.readPropriedade(widget.propriedadeMaeId);

    final formKey = GlobalKey<FormState>();
    final obsController = TextEditingController(text: manejo.detalhes['observacao']);

    final garanhaoController = TextEditingController(text: _currentEgua.cobertura);
    String? tipoSememSelecionado;
    int? quantidadePalhetas;
    final litrosController = TextEditingController();
    
    final todosMedicamentos = await SQLiteHelper.instance.readAllMedicamentos();
    String? ovarioDirOp;
    String? ovarioEsqOp;
    final ovarioDirTamanhoController = TextEditingController();
    final ovarioEsqTamanhoController = TextEditingController();
    String? edemaSelecionado;
    final uteroController = TextEditingController();

    String? idadeEmbriaoSelecionada;
    final avaliacaoUterinaController = TextEditingController();
    Egua? doadoraSelecionada;

    String? resultadoDiagnostico;
    final diasPrenheController = TextEditingController();
    String? sexoPotro;
    final pelagemController = TextEditingController();
    DateTime? dataHoraParto;
    final observacoesPartoController = TextEditingController();
    bool partoComSucesso = true;

    DateTime? dataHoraInseminacao;
    DateTime dataFinalManejo = DateTime.now();

    final tratamentoController = TextEditingController(text: manejo.detalhes['tratamento']);
    Medicamento? medicamentoSelecionado;
    String? inducaoSelecionada;
    DateTime? dataHoraInducao;
    final medicamentoSearchController = TextEditingController();
    List<Medicamento> _filteredMedicamentos = todosMedicamentos;
    bool _showMedicamentoList = false;

    dynamic concluidoPorSelecionado = allUsersList.firstWhere((u) => u.uid == currentUser.uid, orElse: () => allUsersList.first);
    bool isVeterinario = true;
    
    bool _incluirControleFolicular = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (ctx) { 
        return StatefulBuilder(
        builder: (modalContext, setModalState) {
          void filterMedicamentos(String query) {
            setModalState(() {
              _filteredMedicamentos = query.isEmpty
                  ? todosMedicamentos
                  : todosMedicamentos
                      .where((med) => med.nome.toLowerCase().contains(query.toLowerCase()))
                      .toList();
            });
          }

          List<DropdownMenuItem<dynamic>> veterinarioItems = [
            ...allUsersList
                .map((user) => DropdownMenuItem<dynamic>(
                    value: user, child: Text(user.nome)))
                .toList(),
          ];

          List<DropdownMenuItem<dynamic>> cabanhaItems = [];
          if (propriedadeMaeSelecionada != null) {
            cabanhaItems.add(
              const DropdownMenuItem<dynamic>(
                enabled: false,
                child: Text("Proprietário",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppTheme.brown)),
              ),
            );
            cabanhaItems.add(
              DropdownMenuItem<dynamic>(
                value: propriedadeMaeSelecionada.dono,
                child: Text(propriedadeMaeSelecionada.dono),
              ),
            );
          }

          if (peoesDaPropriedade.isNotEmpty) {
            cabanhaItems.add(const DropdownMenuItem<dynamic>(
                enabled: false, child: Divider()));
            cabanhaItems.add(const DropdownMenuItem<dynamic>(
              enabled: false,
              child: Text("Peões da Propriedade",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.brown)),
            ));
            cabanhaItems.addAll(peoesDaPropriedade
                .map((peao) =>
                    DropdownMenuItem<dynamic>(value: peao, child: Text(peao.nome)))
                .toList());
          }


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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${manejo.tipo}",
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    Text("Égua: ${_currentEgua.nome}",
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
                    if (manejo.tipo != 'Outros Manejos')
                      const Divider(height: 30, thickness: 1),
                    
                    ..._buildSpecificForm(
                      context: context,
                      tipo: manejo.tipo,
                      setModalState: setModalState,
                      garanhaoController: garanhaoController,
                      dataHoraInseminacao: dataHoraInseminacao,
                      onDataHoraInseminacaoChange: (val) => setModalState(() => dataHoraInseminacao = val),
                      litrosController: litrosController,
                      medicamentoSelecionado: medicamentoSelecionado,
                      onMedicamentoChange: (val) => setModalState(() => medicamentoSelecionado = val),
                      allMeds: todosMedicamentos,
                      ovarioDirOp: ovarioDirOp,
                      onOvarioDirChange: (val) => setModalState(() => ovarioDirOp = val),
                      ovarioEsqOp: ovarioEsqOp,
                      onOvarioEsqChange: (val) => setModalState(() => ovarioEsqOp = val),
                      ovarioDirTamanhoController: ovarioDirTamanhoController,
                      ovarioEsqTamanhoController: ovarioEsqTamanhoController,
                      edemaSelecionado: edemaSelecionado,
                      onEdemaChange: (val) => setModalState(() => edemaSelecionado = val),
                      uteroController: uteroController,
                      idadeEmbriao: idadeEmbriaoSelecionada,
                      onIdadeEmbriaoChange: (val) => setModalState(() => idadeEmbriaoSelecionada = val),
                      doadoraSelecionada: doadoraSelecionada,
                      onDoadoraChange: (val) => setModalState(() => doadoraSelecionada = val),
                      avaliacaoUterinaController: avaliacaoUterinaController,
                      resultadoDiagnostico: resultadoDiagnostico,
                      onResultadoChange: (val) => setModalState(() => resultadoDiagnostico = val),
                      diasPrenheController: diasPrenheController,
                      sexoPotro: sexoPotro,
                      onSexoPotroChange: (val) => setModalState(() => sexoPotro = val),
                      pelagemController: pelagemController,
                      dataHoraParto: dataHoraParto,
                      onDataHoraPartoChange: (val) => setModalState(() => dataHoraParto = val),
                      observacoesPartoController: observacoesPartoController,
                      medicamentoSearchController: medicamentoSearchController,
                      filterMedicamentos: filterMedicamentos,
                      showMedicamentoList: _showMedicamentoList,
                      onShowMedicamentoListChange: (show) => setModalState(() => _showMedicamentoList = show),
                      filteredMedicamentos: _filteredMedicamentos,
                      tipoSememSelecionado: tipoSememSelecionado,
                      onTipoSememChange: (val) => setModalState(() => tipoSememSelecionado = val),
                      quantidadePalhetas: quantidadePalhetas,
                      onQuantidadePalhetasChange: (val) => setModalState(() => quantidadePalhetas = val),
                      partoComSucesso: partoComSucesso,
                      onPartoComSucessoChange: (val) => setModalState(() => partoComSucesso = val),
                    ),

                      if (manejo.tipo != 'Controle Folicular') ...[
                        const Divider(height: 20, thickness: 1),
                        SwitchListTile(
                          title: const Text("Incluir Controle Folicular?"),
                          value: _incluirControleFolicular,
                          onChanged: (bool value) {
                            setModalState(() {
                              _incluirControleFolicular = value;
                            });
                          },
                          activeColor: AppTheme.darkGreen,
                        ),

                        if (_incluirControleFolicular)
                        _buildControleFolicularInputs(
                          setModalState: setModalState,
                          ovarioDirOp: ovarioDirOp,
                          onOvarioDirChange: (val) => setModalState(() => ovarioDirOp = val),
                          ovarioDirTamanhoController: ovarioDirTamanhoController,
                          ovarioEsqOp: ovarioEsqOp,
                          onOvarioEsqChange: (val) => setModalState(() => ovarioEsqOp = val),
                          ovarioEsqTamanhoController: ovarioEsqTamanhoController,
                          edemaSelecionado: edemaSelecionado,
                          onEdemaChange: (val) => setModalState(() => edemaSelecionado = val),
                          uteroController: uteroController,
                        ),
                      ],

                      if (manejo.tipo == 'Controle Folicular') ...[
                        const Divider(height: 20, thickness: 1),
                        Text("Tratamento", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 15),
                        TextFormField(
                        controller: tratamentoController,
                        decoration:
                            InputDecoration(
                              labelText: "Descrição do tratamento",
                              prefixIcon: Icon(Icons.healing_outlined))
                        ),
                        const Divider(height: 20, thickness: 1),
                        Text("Indução", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 15),
                        TextFormField(
                          controller: medicamentoSearchController,
                          decoration: InputDecoration(
                            labelText: "Buscar Medicamento",
                            prefixIcon: Icon(Icons.medication_outlined),
                            suffixIcon: medicamentoSelecionado != null
                                ? IconButton(
                                    icon: Icon(Icons.close),
                                    onPressed: () {
                                      setModalState(() {
                                        medicamentoSelecionado = null;
                                        medicamentoSearchController.clear();
                                        _showMedicamentoList = true;
                                        FocusScope.of(context).unfocus();
                                      });
                                    },
                                  )
                                : const Icon(Icons.search_outlined),
                          ),
                          onChanged: filterMedicamentos,
                          onTap: () => setModalState(() => _showMedicamentoList = true),
                        ),
                        if (_showMedicamentoList)
                          SizedBox(
                            height: 150,
                            child: ListView.builder(
                              itemCount: _filteredMedicamentos.length,
                              itemBuilder: (context, index) {
                                final med = _filteredMedicamentos[index];
                                return ListTile(
                                  title: Text(med.nome),
                                  onTap: () {
                                    setModalState(() {
                                      medicamentoSelecionado = med;
                                      medicamentoSearchController.text = med.nome;
                                      _showMedicamentoList = false;
                                      FocusScope.of(context).unfocus();
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: inducaoSelecionada,
                          decoration: InputDecoration(
                            labelText: "Tipo de Indução", 
                            prefixIcon: Icon(Icons.healing_outlined),
                            suffixIcon: inducaoSelecionada != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      setModalState(() {
                                        inducaoSelecionada = null;
                                        dataHoraInducao = null;
                                      });
                                    },
                                  )
                                : null,
                          ),
                          items: ["HCG", "DESLO", "HCG+DESLO"]
                              .map((label) => DropdownMenuItem(child: Text(label), value: label))
                              .toList(),
                          onChanged: (value) => setModalState(() => inducaoSelecionada = value),
                        ),
                        const SizedBox(height: 15),
                        
                        TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: dataHoraInducao == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(dataHoraInducao!),
                          ),
                          decoration: const InputDecoration(
                              labelText: "Data e Hora da Indução",
                              hintText: 'Selecione',
                          ),
                          onTap: () async {
                              final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                              if (date == null) return;
                              TimeOfDay? time;
                                await showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Text("Selecione a Hora"),
                                      content: TimePickerSpinner(
                                        is24HourMode: true,
                                        minutesInterval: 5,
                                        onTimeChange: (dateTime) {
                                          time = TimeOfDay.fromDateTime(dateTime);
                                        },
                                      ),
                                      actions: <Widget>[
                                        TextButton(
                                          child: Text("CANCELAR"),
                                          onPressed: () => Navigator.of(context).pop(),
                                        ),
                                        TextButton(
                                          child: Text("OK"),
                                          onPressed: () => Navigator.of(context).pop(),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              if (time != null) {
                                 setModalState(() => dataHoraInducao = DateTime(date.year, date.month, date.day, time!.hour, time!.minute));
                              }
                          },
                          validator: (v) {
                            if (inducaoSelecionada != null && dataHoraInducao == null) {
                              return "Obrigatório se indução foi selecionada";
                            }
                            return null;
                          },  
                        ),
                      ],
                    
                    const Divider(height: 20, thickness: 1),
                    Text("Detalhes da Conclusão", style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 15),

                    SwitchListTile(
                      title: Text(
                          isVeterinario ? 'Veterinário' : 'Da Cabanha'),
                      value: isVeterinario,
                      onChanged: (bool value) {
                        setModalState(() {
                          isVeterinario = value;
                          concluidoPorSelecionado = null;
                        });
                      },
                      secondary: Icon(isVeterinario
                          ? Icons.medical_services_outlined
                          : Icons.home_work_outlined),
                    ),
                    DropdownButtonFormField<dynamic>(
                      value: concluidoPorSelecionado,
                      decoration: const InputDecoration(
                          labelText: "Concluído por",
                          prefixIcon: Icon(Icons.person_outline)),
                      items: isVeterinario ? veterinarioItems : cabanhaItems,
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => concluidoPorSelecionado = value);
                        }
                      },
                      validator: (v) =>
                          v == null ? "Selecione um responsável" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: DateFormat('dd/MM/yyyy HH:mm').format(dataFinalManejo)
                      ),
                      decoration: const InputDecoration(
                          labelText: "Data e Hora da Conclusão",
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          hintText: 'Toque para selecionar a data e hora'),
                      validator: (v) => v == null ? "Obrigatório" : null,
                      onTap: () async {
                        final date = await showDatePicker(
                            context: context,
                            initialDate: dataFinalManejo,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030));
                        if (date == null) return;
                        TimeOfDay? time;
                          await showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text("Selecione a Hora"),
                                content: TimePickerSpinner(
                                  is24HourMode: true,
                                  minutesInterval: 5,
                                  onTimeChange: (dateTime) {
                                    time = TimeOfDay.fromDateTime(dateTime);
                                  },
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    child: Text("CANCELAR"),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                  TextButton(
                                    child: Text("OK"),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ],
                              );
                            },
                          );
                        if (time != null) {
                            setModalState(() => dataFinalManejo = DateTime(date.year, date.month, date.day, time!.hour, time!.minute));
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                        controller: obsController,
                        decoration:
                            const InputDecoration(
                                labelText: "Observações Finais",
                                prefixIcon: Icon(Icons.comment_outlined)),
                        maxLines: 3),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final Map<String, dynamic> detalhes = manejo.detalhes;
                            detalhes['observacao'] = obsController.text;

                            if (_incluirControleFolicular && manejo.tipo != 'Controle Folicular') {
                                detalhes['ovarioDireito'] = ovarioDirOp;
                                detalhes['ovarioDireitoTamanho'] = ovarioDirTamanhoController.text;
                                detalhes['ovarioEsquerdo'] = ovarioEsqOp;
                                detalhes['ovarioEsquerdoTamanho'] = ovarioEsqTamanhoController.text;
                                detalhes['edema'] = edemaSelecionado;
                                detalhes['utero'] = uteroController.text;
                            }

                            if (manejo.tipo == 'Controle Folicular') {
                                detalhes['tratamento'] = tratamentoController.text;
                                manejo.medicamentoId = medicamentoSelecionado?.id;
                                manejo.inducao = inducaoSelecionada;
                                manejo.dataHoraInducao = dataHoraInducao;
                                detalhes['ovarioDireito'] = ovarioDirOp;
                                detalhes['ovarioDireitoTamanho'] = ovarioDirTamanhoController.text;
                                detalhes['ovarioEsquerdo'] = ovarioEsqOp;
                                detalhes['ovarioEsquerdoTamanho'] = ovarioEsqTamanhoController.text;
                                detalhes['edema'] = edemaSelecionado;
                                detalhes['utero'] = uteroController.text;
                            } else if (manejo.tipo == 'Diagnóstico') {
                              detalhes['resultado'] = resultadoDiagnostico;
                              if (resultadoDiagnostico == 'Prenhe') {
                                final dias = int.tryParse(diasPrenheController.text) ?? 0;
                                detalhes['diasPrenhe'] = dias;
                                final eguaAtualizada = _currentEgua.copyWith(
                                  statusReprodutivo: 'Prenhe',
                                  diasPrenhe: dias,
                                  cobertura: garanhaoController.text,
                                  statusSync: 'pending_update'
                                );
                                await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                              } else if (resultadoDiagnostico == 'Pariu') {
                                  detalhes['resultadoParto'] = partoComSucesso ? 'Criou' : 'Perdeu';
                                  if (partoComSucesso) {
                                    detalhes['sexoPotro'] = sexoPotro;
                                    detalhes['pelagemPotro'] = pelagemController.text;
                                    detalhes['dataHoraParto'] = dataHoraParto?.toIso8601String();
                                    detalhes['observacoesParto'] = observacoesPartoController.text;
                                    final eguaAtualizada = _currentEgua.copyWith(
                                      statusReprodutivo: 'Vazia',
                                      dataParto: dataHoraParto,
                                      sexoPotro: sexoPotro,
                                      statusSync: 'pending_update'
                                    );
                                    await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                                  } else {
                                    detalhes['observacoesParto'] = observacoesPartoController.text;
                                    final eguaAtualizada = _currentEgua.copyWith(
                                      statusReprodutivo: 'Vazia',
                                      dataParto: null,
                                      sexoPotro: null,
                                      statusSync: 'pending_update'
                                    );
                                    await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                                  }
                              } else {
                                final eguaAtualizada = _currentEgua.copyWith(
                                    statusReprodutivo: 'Vazia',
                                    diasPrenhe: 0,
                                    statusSync: 'pending_update'
                                  );
                                await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                              }
                            } else if (manejo.tipo == 'Inseminação') {
                              detalhes['garanhao'] = garanhaoController.text;
                              detalhes['tipoSemem'] = tipoSememSelecionado;
                              if (tipoSememSelecionado == 'Congelado') {
                                detalhes['quantidadePalhetas'] = quantidadePalhetas.toString();
                                manejo.quantidadePalhetas = quantidadePalhetas; 
                              }
                              detalhes['dataHora'] = dataHoraInseminacao?.toIso8601String();
                            } else if (manejo.tipo == 'Lavado') {
                              detalhes['litros'] = litrosController.text;
                              detalhes['medicamento'] = medicamentoSelecionado?.nome;
                            } else if (manejo.tipo == 'Coleta de Embrião') {
                              detalhes['idadeEmbriao'] = idadeEmbriaoSelecionada;
                            } else if (manejo.tipo == 'Transferência de Embrião') {
                              detalhes['doadora'] = doadoraSelecionada?.nome;
                              detalhes['idadeEmbriao'] = idadeEmbriaoSelecionada;
                              detalhes['avaliacaoUterina'] = avaliacaoUterinaController.text;
                            }

                            manejo.status = 'Concluído';
                            manejo.statusSync = 'pending_update';
                            manejo.detalhes = detalhes;
                            manejo.dataAgendada = dataFinalManejo;
                            
                            if (concluidoPorSelecionado is AppUser) {
                              manejo.concluidoPorId = concluidoPorSelecionado.uid;
                              manejo.concluidoPorPeaoId = null;
                            } else if (concluidoPorSelecionado is Peao) {
                              manejo.concluidoPorPeaoId = concluidoPorSelecionado.id;
                              manejo.concluidoPorId = null;
                            }

                            await SQLiteHelper.instance.updateManejo(manejo);

                            if (mounted) {
                              Navigator.of(ctx).pop();
                            }
                            refreshData();
                            _autoSync();

                            if (manejo.tipo == 'Controle Folicular' && dataHoraInducao != null) {
                              final Propriedade? prop = _allPropriedades[widget.propriedadeMaeId]; 
                              if (prop != null) {
                                await _promptForInseminationScheduleOnInduction(
                                  context, 
                                  _currentEgua,
                                  prop, 
                                  dataHoraInducao!
                                );
                              }
                            }

                            final isFollicularControl = manejo.tipo == 'Controle Folicular' || _incluirControleFolicular;
                            if (isFollicularControl) {
                              await _promptForFollicularControlSchedule(
                                dataFinalManejo,
                                ovarioDirTamanhoController.text,
                                ovarioEsqTamanhoController.text,
                              );
                            }

                            if (manejo.tipo == "Inseminação") {
                              await _promptForDiagnosticSchedule(dataHoraInseminacao ?? dataFinalManejo);
                            }
                          }
                        },
                        child: const Text("Salvar Conclusão"),
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

  void _showAddHistoricoModal(BuildContext context, {Manejo? manejo, required bool isEditing}) async {
    final currentUser = _authService.currentUserNotifier.value;
    if(currentUser == null) return;

    final propriedade =
        await SQLiteHelper.instance.readPropriedade(_currentEgua.propriedadeId);

    final allUsersList = await SQLiteHelper.instance.getAllUsers();

    final peoesDaPropriedade = await SQLiteHelper.instance.readPeoesByPropriedade(widget.propriedadeMaeId);
    bool isVeterinario = true;

    final formKey = GlobalKey<FormState>();
    final String title = isEditing ? "Editar Manejo do Histórico" : "Adicionar ao Histórico";

    String? tipoManejoSelecionado = manejo?.tipo;
    DateTime dataFinalManejo = manejo?.dataAgendada ?? DateTime.now();
    final obsController = TextEditingController(text: manejo?.detalhes['observacao'] ?? '');
    
    final garanhaoController = TextEditingController(text: manejo?.detalhes['garanhao'] ?? _currentEgua.cobertura);
    String? tipoSememSelecionado = manejo?.detalhes['tipoSemem'];
    int? quantidadePalhetas = manejo?.detalhes['quantidadePalhetas'];
    final litrosController = TextEditingController(text: manejo?.detalhes['litros']?.toString());
    
    String? ovarioDirOp = manejo?.detalhes['ovarioDireito'];
    String? ovarioEsqOp = manejo?.detalhes['ovarioEsquerdo'];
    String? edemaSelecionado = manejo?.detalhes['edema'];
    String? idadeEmbriaoSelecionada = manejo?.detalhes['idadeEmbriao'];

    String? resultadoDiagnostico = manejo?.detalhes['resultado'];
    String? sexoPotro = manejo?.detalhes['sexoPotro'];
    final pelagemController = TextEditingController(text: manejo?.detalhes['pelagemPotro']);
    DateTime? dataHoraParto = manejo?.detalhes['dataHoraParto'] != null
        ? DateTime.tryParse(manejo!.detalhes['dataHoraParto'])
        : null;
    final observacoesPartoController = TextEditingController(text: manejo?.detalhes['observacoesParto']);
    bool partoComSucesso = (manejo?.detalhes['resultadoParto'] as String? ?? 'Criou') == 'Criou';
  
    final ovarioDirTamanhoController = TextEditingController(text: manejo?.detalhes['ovarioDireitoTamanho']?.toString());
    final ovarioEsqTamanhoController = TextEditingController(text: manejo?.detalhes['ovarioEsquerdoTamanho']?.toString());
    final uteroController = TextEditingController(text: manejo?.detalhes['utero']?.toString());
    final avaliacaoUterinaController = TextEditingController(text: manejo?.detalhes['avaliacaoUterina']?.toString());
    final diasPrenheController = TextEditingController(text: manejo?.detalhes['diasPrenhe']?.toString());

    DateTime? dataHoraInseminacao = manejo?.detalhes['dataHora'] != null ? DateTime.tryParse(manejo!.detalhes['dataHora']) : null;
    DateTime? dataHoraInducao = manejo?.dataHoraInducao;
    
    final todosMedicamentos = await SQLiteHelper.instance.readAllMedicamentos();
    Medicamento? medicamentoSelecionado;
      if (manejo?.medicamentoId != null) {
        // ignore: null_check_always_fails
        medicamentoSelecionado = todosMedicamentos.firstWhere((med) => med.id == manejo!.medicamentoId, orElse: () => todosMedicamentos.isNotEmpty ? todosMedicamentos.first : null!);
      } else if (manejo?.detalhes['medicamento'] != null) {
        // ignore: null_check_always_fails
        medicamentoSelecionado = todosMedicamentos.firstWhere((med) => med.nome == manejo!.detalhes['medicamento'], orElse: () => todosMedicamentos.isNotEmpty ? todosMedicamentos.first : null!);
      }
    
    String? inducaoSelecionada = manejo?.inducao;
    final medicamentoSearchController = TextEditingController(text: medicamentoSelecionado?.nome);
    List<Medicamento> _filteredMedicamentos = todosMedicamentos;
    bool _showMedicamentoList = false;

    final tratamentoController = TextEditingController(text: manejo?.detalhes['tratamento']);
    Egua? doadoraSelecionada;
    if (manejo?.detalhes['doadora'] != null) {
        final allEguas = await SQLiteHelper.instance.getAllEguas();
        // ignore: null_check_always_fails
        doadoraSelecionada = allEguas.firstWhere((e) => e.nome == manejo!.detalhes['doadora'], orElse: () => allEguas.isNotEmpty ? allEguas.first : null!);
    }

    dynamic concluidoPorSelecionado;
    final AppUser currentUserDefault = allUsersList.firstWhere((u) => u.uid == currentUser.uid, orElse: () => allUsersList.first);

    if (manejo?.concluidoPorId != null) {
      concluidoPorSelecionado = allUsersList.firstWhereOrNull((u) => u.uid == manejo!.concluidoPorId) ?? currentUserDefault;
    } else if (manejo?.concluidoPorPeaoId != null) {
      concluidoPorSelecionado = peoesDaPropriedade.firstWhereOrNull((p) => p.id == manejo!.concluidoPorPeaoId) ?? currentUserDefault;
    } else {
      concluidoPorSelecionado = currentUserDefault;
    }
    
    bool _incluirControleFolicular = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (ctx) { 
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
          void filterMedicamentos(String query) {
            setModalState(() {
              _filteredMedicamentos = query.isEmpty
                  ? todosMedicamentos
                  : todosMedicamentos
                      .where((med) => med.nome.toLowerCase().contains(query.toLowerCase()))
                      .toList();
            });
          }

          List<DropdownMenuItem<dynamic>> veterinarioItems = [
            ...allUsersList
                .map((user) => DropdownMenuItem<dynamic>(
                    value: user, child: Text(user.nome)))
                .toList(),
          ];

          List<DropdownMenuItem<dynamic>> cabanhaItems = [];
              cabanhaItems.add(
                const DropdownMenuItem<dynamic>(
                  enabled: false,
                  child: Text("Proprietário",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: AppTheme.brown)),
                ),
              );
              cabanhaItems.add(
                DropdownMenuItem<dynamic>(
                  value: propriedade!.dono,
                  child: Text(propriedade.dono),
                ),
              );

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
                          title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    Text("Égua: ${_currentEgua.nome}",
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
                    const SizedBox(height: 5),
                    const Divider(height: 30, thickness: 1),
                    DropdownButtonFormField<String>(
                      value: tipoManejoSelecionado,
                      decoration: InputDecoration(
                        labelText: "Tipo de Manejo",
                        prefixIcon: Icon(Icons.edit_note_outlined),
                        filled: isEditing,
                        fillColor: isEditing ? Colors.grey[200] : null,
                      ),
                      hint: const Text("Obrigatório"),
                      items: [
                        "Controle Folicular", "Inseminação", "Lavado", "Diagnóstico",
                        "Transferência de Embrião", "Coleta de Embrião", "Outros Manejos"
                      ]
                          .map((tipo) =>
                              DropdownMenuItem(value: tipo, child: Text(tipo)))
                          .toList(),
                      onChanged: isEditing ? null : (val) {
                        setModalState(() => tipoManejoSelecionado = val);
                      },
                      validator: (v) => v == null ? "Obrigatório" : null,
                    ),
                    
                    if (tipoManejoSelecionado != null) ...[
                      const SizedBox(height: 10),
                      ..._buildSpecificForm(
                        context: context,
                        tipo: tipoManejoSelecionado!,
                        setModalState: setModalState,
                        garanhaoController: garanhaoController,
                        dataHoraInseminacao: dataHoraInseminacao,
                        onDataHoraInseminacaoChange: (val) => setModalState(() => dataHoraInseminacao = val),
                        litrosController: litrosController,
                        medicamentoSelecionado: medicamentoSelecionado,
                        onMedicamentoChange: (val) => setModalState(() => medicamentoSelecionado = val),
                        allMeds: todosMedicamentos,
                        ovarioDirOp: ovarioDirOp,
                        onOvarioDirChange: (val) => setModalState(() => ovarioDirOp = val),
                        ovarioEsqOp: ovarioEsqOp,
                        onOvarioEsqChange: (val) => setModalState(() => ovarioEsqOp = val),
                        ovarioDirTamanhoController: ovarioDirTamanhoController,
                        ovarioEsqTamanhoController: ovarioEsqTamanhoController,
                        edemaSelecionado: edemaSelecionado,
                        onEdemaChange: (val) => setModalState(() => edemaSelecionado = val),
                        uteroController: uteroController,
                        idadeEmbriao: idadeEmbriaoSelecionada,
                        onIdadeEmbriaoChange: (val) => setModalState(() => idadeEmbriaoSelecionada = val),
                        doadoraSelecionada: doadoraSelecionada,
                        onDoadoraChange: (val) => setModalState(() => doadoraSelecionada = val),
                        avaliacaoUterinaController: avaliacaoUterinaController,
                        resultadoDiagnostico: resultadoDiagnostico,
                        onResultadoChange: (val) => setModalState(() => resultadoDiagnostico = val),
                        diasPrenheController: diasPrenheController,
                        medicamentoSearchController: medicamentoSearchController,
                        filterMedicamentos: filterMedicamentos,
                        showMedicamentoList: _showMedicamentoList,
                        onShowMedicamentoListChange: (show) => setModalState(() => _showMedicamentoList = show),
                        filteredMedicamentos: _filteredMedicamentos,
                        tipoSememSelecionado: tipoSememSelecionado,
                        onTipoSememChange: (val) => setModalState(() => tipoSememSelecionado = val),
                        quantidadePalhetas: quantidadePalhetas,
                        onQuantidadePalhetasChange: (val) => setModalState(() => quantidadePalhetas = val),
                        sexoPotro: sexoPotro,
                        onSexoPotroChange: (val) => setModalState(() => sexoPotro = val),
                        pelagemController: pelagemController,
                        dataHoraParto: dataHoraParto,
                        onDataHoraPartoChange: (val) => setModalState(() => dataHoraParto = val),
                        observacoesPartoController: observacoesPartoController,
                        partoComSucesso: partoComSucesso,
                        onPartoComSucessoChange: (val) => setModalState(() => partoComSucesso = val),
                      ),
                      if (tipoManejoSelecionado != 'Controle Folicular') ...[
                        const Divider(height: 20, thickness: 1),
                        SwitchListTile(
                          title: const Text("Incluir Controle Folicular?"),
                          value: _incluirControleFolicular,
                          onChanged: (bool value) {
                            setModalState(() {
                              _incluirControleFolicular = value;
                            });
                          },
                          activeColor: AppTheme.darkGreen,
                        ),
                        if (_incluirControleFolicular)
                        _buildControleFolicularInputs(
                          setModalState: setModalState,
                          ovarioDirOp: ovarioDirOp,
                          onOvarioDirChange: (val) => setModalState(() => ovarioDirOp = val),
                          ovarioDirTamanhoController: ovarioDirTamanhoController,
                          ovarioEsqOp: ovarioEsqOp,
                          onOvarioEsqChange: (val) => setModalState(() => ovarioEsqOp = val),
                          ovarioEsqTamanhoController: ovarioEsqTamanhoController,
                          edemaSelecionado: edemaSelecionado,
                          onEdemaChange: (val) => setModalState(() => edemaSelecionado = val),
                          uteroController: uteroController,
                        ),
                      ],
                    ],

                    if (tipoManejoSelecionado == 'Controle Folicular') ...[
                      const Divider(height: 20, thickness: 1),
                      Text("Tratamento", style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: tratamentoController,
                        decoration:
                            InputDecoration(
                              labelText: "Descrição do tratamento",
                              prefixIcon: Icon(Icons.healing_outlined))
                      ),
                      const Divider(height: 20, thickness: 1),
                      Text("Indução", style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: medicamentoSearchController,
                        decoration: InputDecoration(
                          labelText: "Buscar Medicamento",
                          prefixIcon: Icon(Icons.medication_outlined),
                          suffixIcon: medicamentoSelecionado != null
                              ? IconButton(
                                  icon: Icon(Icons.close),
                                  onPressed: () {
                                    setModalState(() {
                                      medicamentoSelecionado = null;
                                      medicamentoSearchController.clear();
                                      _showMedicamentoList = true;
                                      FocusScope.of(context).unfocus();
                                    });
                                  },
                                )
                              : const Icon(Icons.search_outlined),
                        ),
                        onChanged: filterMedicamentos,
                        onTap: () => setModalState(() => _showMedicamentoList = true),
                      ),
                      if (_showMedicamentoList)
                        SizedBox(
                          height: 150,
                          child: ListView.builder(
                            itemCount: _filteredMedicamentos.length,
                            itemBuilder: (context, index) {
                              final med = _filteredMedicamentos[index];
                              return ListTile(
                                title: Text(med.nome),
                                onTap: () {
                                  setModalState(() {
                                    medicamentoSelecionado = med;
                                    medicamentoSearchController.text = med.nome;
                                    _showMedicamentoList = false;
                                    FocusScope.of(context).unfocus();
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: inducaoSelecionada,
                        decoration: InputDecoration(
                          labelText: "Tipo de Indução", 
                          prefixIcon: Icon(Icons.healing_outlined),
                          suffixIcon: inducaoSelecionada != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    setModalState(() {
                                      inducaoSelecionada = null;
                                      dataHoraInducao = null;
                                    });
                                  },
                                )
                              : null,
                        ),
                        items: ["HCG", "DESLO", "HCG+DESLO"]
                            .map((label) => DropdownMenuItem(child: Text(label), value: label))
                            .toList(),
                        onChanged: (value) => setModalState(() => inducaoSelecionada = value),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        readOnly: true,
                        controller: TextEditingController(
                          text: dataHoraInducao == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(dataHoraInducao!),
                        ),
                        decoration: const InputDecoration(
                            labelText: "Data e Hora da Indução",
                            hintText: 'Selecione',
                        ),
                        onTap: () async {
                            final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                            if (date == null) return;
                            TimeOfDay? time;
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: Text("Selecione a Hora"),
                                    content: TimePickerSpinner(
                                      is24HourMode: true,
                                      minutesInterval: 5,
                                      onTimeChange: (dateTime) {
                                        time = TimeOfDay.fromDateTime(dateTime);
                                      },
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        child: Text("CANCELAR"),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                      TextButton(
                                        child: Text("OK"),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ],
                                  );
                                },
                              );
                            if (time != null) {
                               setModalState(() => dataHoraInducao = DateTime(date.year, date.month, date.day, time!.hour, time!.minute));
                            }
                        },
                        validator: (v) {
                          if (inducaoSelecionada != null && dataHoraInducao == null) {
                            return "Obrigatório se indução foi selecionada";
                          }
                          return null;
                        },  
                      ),
                    ],
                    
                    const Divider(height: 20, thickness: 1),
                    Text("Detalhes da Conclusão", style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 15),

                    SwitchListTile(
                      title: Text(
                          isVeterinario ? 'Veterinário' : 'Da Cabanha'),
                      value: isVeterinario,
                      onChanged: (bool value) {
                        setModalState(() {
                          isVeterinario = value;
                          concluidoPorSelecionado = null;
                        });
                      },
                      secondary: Icon(isVeterinario
                          ? Icons.medical_services_outlined
                          : Icons.home_work_outlined),
                    ),
                    DropdownButtonFormField<dynamic>(
                      value: concluidoPorSelecionado,
                      decoration: const InputDecoration(
                          labelText: "Concluído por",
                          prefixIcon: Icon(Icons.person_outline)),
                      items: isVeterinario ? veterinarioItems : cabanhaItems,
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => concluidoPorSelecionado = value);
                        }
                      },
                      validator: (v) => v == null ? "Obrigatório" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                        controller: obsController,
                        decoration:
                            const InputDecoration(
                                labelText: "Observações Finais",
                                prefixIcon: Icon(Icons.comment_outlined)),
                        maxLines: 3),
                    const SizedBox(height: 10),
                    TextFormField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: DateFormat('dd/MM/yyyy HH:mm').format(dataFinalManejo)
                      ),
                      decoration: const InputDecoration(
                          labelText: "Data e Hora da Conclusão",
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          hintText: 'Toque para selecionar a data e hora'),
                      validator: (v) => v == null ? "Obrigatório" : null,
                      onTap: () async {
                        final date = await showDatePicker(
                            context: context,
                            initialDate: dataFinalManejo,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030));
                        if (date == null) return;
                        TimeOfDay? time;
                          await showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text("Selecione a Hora"),
                                content: TimePickerSpinner(
                                  is24HourMode: true,
                                  minutesInterval: 5,
                                  onTimeChange: (dateTime) {
                                    time = TimeOfDay.fromDateTime(dateTime);
                                  },
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    child: Text("CANCELAR"),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                  TextButton(
                                    child: Text("OK"),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ],
                              );
                            },
                          );
                        if (time != null) {
                            setModalState(() => dataFinalManejo = DateTime(date.year, date.month, date.day, time!.hour, time!.minute));
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final Map<String, dynamic> detalhes = {
                              'observacao': obsController.text,
                            };

                            if (_incluirControleFolicular && tipoManejoSelecionado != 'Controle Folicular') {
                              detalhes['ovarioDireito'] = ovarioDirOp;
                              detalhes['ovarioDireitoTamanho'] = ovarioDirTamanhoController.text;
                              detalhes['ovarioEsquerdo'] = ovarioEsqOp;
                              detalhes['ovarioEsquerdoTamanho'] = ovarioEsqTamanhoController.text;
                              detalhes['edema'] = edemaSelecionado;
                              detalhes['utero'] = uteroController.text;
                            }

                            if (tipoManejoSelecionado == 'Diagnóstico') {
                              detalhes['resultado'] = resultadoDiagnostico;
                              if (resultadoDiagnostico == 'Prenhe') {
                                final dias = int.tryParse(diasPrenheController.text) ?? 0;
                                detalhes['diasPrenhe'] = dias;
                                final eguaAtualizada = _currentEgua.copyWith(
                                    statusReprodutivo: 'Prenhe',
                                    diasPrenhe: dias,
                                    cobertura: garanhaoController.text,
                                    statusSync: 'pending_update');
                                await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                                if(mounted) setState(() => _currentEgua = eguaAtualizada);
                              } else if (resultadoDiagnostico == 'Pariu') {
                                  detalhes['resultadoParto'] = partoComSucesso ? 'Criou' : 'Perdeu';
                                  if (partoComSucesso) {
                                    detalhes['sexoPotro'] = sexoPotro;
                                    detalhes['pelagemPotro'] = pelagemController.text;
                                    detalhes['dataHoraParto'] = dataHoraParto?.toIso8601String();
                                    detalhes['observacoesParto'] = observacoesPartoController.text;
                                    final eguaAtualizada = _currentEgua.copyWith(
                                      statusReprodutivo: 'Vazia',
                                      dataParto: dataHoraParto,
                                      sexoPotro: sexoPotro,
                                      statusSync: 'pending_update');
                                    await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                                    if (mounted) setState(() => _currentEgua = eguaAtualizada);
                                  } else {
                                    detalhes['observacoesParto'] = observacoesPartoController.text;
                                    final eguaAtualizada = _currentEgua.copyWith(
                                      statusReprodutivo: 'Vazia',
                                      dataParto: null,
                                      sexoPotro: null,
                                      statusSync: 'pending_update');
                                    await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                                    if(mounted) setState(() => _currentEgua = eguaAtualizada);
                                  }
                                } else {
                                final eguaAtualizada = _currentEgua.copyWith(
                                    statusReprodutivo: 'Vazia',
                                    diasPrenhe: 0,
                                    statusSync: 'pending_update');
                                await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                                if(mounted) setState(() => _currentEgua = eguaAtualizada);
                              }
                            } else if (tipoManejoSelecionado == 'Inseminação') {
                              detalhes['garanhao'] = garanhaoController.text;
                              detalhes['tipoSemem'] = tipoSememSelecionado;
                              detalhes['dataHora'] = dataHoraInseminacao?.toIso8601String();
                              if (tipoSememSelecionado == 'Congelado') {
                                detalhes['quantidadePalhetas'] = quantidadePalhetas.toString();
                              }
                            } else if (tipoManejoSelecionado == 'Lavado') {
                              detalhes['litros'] = litrosController.text;
                              detalhes['medicamento'] = medicamentoSelecionado?.nome;
                            } else if (tipoManejoSelecionado == 'Controle Folicular') {
                              detalhes['tratamento'] = tratamentoController.text;          
                              detalhes['ovarioDireito'] = ovarioDirOp;
                              detalhes['ovarioDireitoTamanho'] = ovarioDirTamanhoController.text;
                              detalhes['ovarioEsquerdo'] = ovarioEsqOp;
                              detalhes['ovarioEsquerdoTamanho'] = ovarioEsqTamanhoController.text;
                              detalhes['edema'] = edemaSelecionado;
                              detalhes['utero'] = uteroController.text;
                              detalhes['medicamentoId'] = medicamentoSelecionado?.id;
                              detalhes['inducao'] = inducaoSelecionada;
                              detalhes['dataHoraInducao'] = dataHoraInducao?.toIso8601String();
                            } else if (tipoManejoSelecionado == 'Coleta de Embrião') {
                              detalhes['idadeEmbriao'] = idadeEmbriaoSelecionada;
                            } else if (tipoManejoSelecionado == 'Transferência de Embrião') {
                              detalhes['doadora'] = doadoraSelecionada?.nome;
                              detalhes['idadeEmbriao'] = idadeEmbriaoSelecionada;
                              detalhes['avaliacaoUterina'] = avaliacaoUterinaController.text;
                            }

                            if(isEditing && manejo != null){
                              final updatedManejo = manejo.copyWith(
                                  dataAgendada: dataFinalManejo,
                                  detalhes: detalhes,
                                  concluidoPorId: concluidoPorSelecionado is AppUser ? concluidoPorSelecionado.uid : null,
                                  concluidoPorPeaoId: concluidoPorSelecionado is Peao ? concluidoPorSelecionado.id : null,
                                  statusSync: 'pending_update',
                                  medicamentoId: tipoManejoSelecionado == 'Controle Folicular' ? medicamentoSelecionado?.id : null,
                                  inducao: tipoManejoSelecionado == 'Controle Folicular' ? inducaoSelecionada : null,
                                  dataHoraInducao: tipoManejoSelecionado == 'Controle Folicular' ? dataHoraInducao : null,
                                  quantidadePalhetas: (tipoManejoSelecionado == 'Inseminação' && tipoSememSelecionado == 'Congelado') ? quantidadePalhetas : null,
                              );
                              await SQLiteHelper.instance.updateManejo(updatedManejo);
                            } else {
                              final novoManejo = Manejo(
                                id: const Uuid().v4(),
                                tipo: tipoManejoSelecionado!,
                                dataAgendada: dataFinalManejo,
                                detalhes: detalhes,
                                eguaId: _currentEgua.id,
                                propriedadeId: _currentEgua.propriedadeId,
                                responsavelId: currentUser.uid,
                                concluidoPorId: concluidoPorSelecionado is AppUser ? concluidoPorSelecionado.uid : null,
                                concluidoPorPeaoId: concluidoPorSelecionado is Peao ? concluidoPorSelecionado.id : null,
                                quantidadePalhetas: (tipoManejoSelecionado == 'Inseminação' && tipoSememSelecionado == 'Congelado') ? quantidadePalhetas : null,
                                status: 'Concluído',
                                statusSync: 'pending_create',
                                medicamentoId: tipoManejoSelecionado == 'Controle Folicular' ? medicamentoSelecionado?.id : null,
                                inducao: tipoManejoSelecionado == 'Controle Folicular' ? inducaoSelecionada : null,
                                dataHoraInducao: tipoManejoSelecionado == 'Controle Folicular' ? dataHoraInducao : null,
                              );
                              await SQLiteHelper.instance.createManejo(novoManejo);
                            }
                            
                            refreshData();
                            if (mounted) {
                              Navigator.of(ctx).pop();
                              _autoSync();
                            }
                            
                            final isFollicularControl = tipoManejoSelecionado == 'Controle Folicular' || _incluirControleFolicular;
                            if (isFollicularControl) {
                              await _promptForFollicularControlSchedule(
                                dataFinalManejo,
                                ovarioDirTamanhoController.text,
                                ovarioEsqTamanhoController.text,
                              );
                            }

                            if (tipoManejoSelecionado == "Inseminação" && !isEditing) {
                                await _promptForDiagnosticSchedule(dataHoraInseminacao ?? dataFinalManejo);
                            }
                          }
                        },
                        child: Text(isEditing ? "Salvar Alterações" : "Salvar no Histórico"),
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

  List<Widget> _buildSpecificForm({
    required BuildContext context,
    required String tipo,
    required StateSetter setModalState,
    required TextEditingController garanhaoController,
    String? tipoSememSelecionado,
    required Function(String?) onTipoSememChange,
    int? quantidadePalhetas,
    required Function(int?) onQuantidadePalhetasChange,
    required DateTime? dataHoraInseminacao,
    required Function(DateTime?) onDataHoraInseminacaoChange,
    required TextEditingController litrosController,
    required Medicamento? medicamentoSelecionado,
    required Function(Medicamento?) onMedicamentoChange,
    required List<Medicamento> allMeds,
    required String? ovarioDirOp,
    required Function(String?) onOvarioDirChange,
    required String? ovarioEsqOp,
    required Function(String?) onOvarioEsqChange,
    required TextEditingController ovarioDirTamanhoController,
    required TextEditingController ovarioEsqTamanhoController,
    required String? edemaSelecionado,
    required Function(String?) onEdemaChange,
    required TextEditingController uteroController,
    required String? idadeEmbriao,
    required Function(String?) onIdadeEmbriaoChange,
    required Egua? doadoraSelecionada,
    required Function(Egua?) onDoadoraChange,
    required TextEditingController avaliacaoUterinaController,
    required String? resultadoDiagnostico,
    required Function(String?) onResultadoChange,
    required TextEditingController diasPrenheController,
    String? sexoPotro,
    required Function(String?) onSexoPotroChange,
    required TextEditingController pelagemController,
    DateTime? dataHoraParto,
    required Function(DateTime?) onDataHoraPartoChange,
    required TextEditingController observacoesPartoController,
    required TextEditingController medicamentoSearchController,
    required void Function(String) filterMedicamentos,
    required bool showMedicamentoList,
    required void Function(bool) onShowMedicamentoListChange,
    required List<Medicamento> filteredMedicamentos,
    required bool partoComSucesso,
    required Function(bool) onPartoComSucessoChange,
  }) {
    final ovarioOptions = ["CL", "OV", "PEQ", "FL", "FH"];
    final idadeEmbriaoOptions = ['D6', 'D7', 'D8', 'D9', 'D10', 'D11'];
    final tiposSemem = ['Refrigerado', 'Congelado', 'A Fresco', 'Monta Natural'];
    switch (tipo) {
      case "Diagnóstico":
        final List<String> diagnosticoItems = ["Indeterminado", "Prenhe", "Vazia"];
          if (_currentEgua.statusReprodutivo.toLowerCase() == 'prenhe' && _currentEgua.categoria != 'Doadora') {
            diagnosticoItems.add("Pariu");
          }
        return [
          DropdownButtonFormField<String>(
            value: resultadoDiagnostico,
            hint: const Text("Resultado do Diagnóstico"),
            items: diagnosticoItems
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (val) => setModalState(() => onResultadoChange(val)),
            validator: (v) => v == null ? "Obrigatório" : null,
            decoration: InputDecoration(
              labelText: "Resultado do Diagnóstico",
            ),
          ),
          if (resultadoDiagnostico == 'Prenhe') ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: diasPrenheController,
              decoration: const InputDecoration(labelText: "Dias de Prenhez"),
              keyboardType: TextInputType.number,
              validator: (v) => v!.isEmpty ? "Obrigatório" : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: garanhaoController,
              decoration: const InputDecoration(labelText: "Padreador"),
              validator: (v) => v!.isEmpty ? "Obrigatório" : null,
            ),
          ],
          if (resultadoDiagnostico == 'Pariu') ...[
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text("Dados do parto", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    Text("Perdeu", style: TextStyle(color: partoComSucesso ? Colors.grey[600] : Colors.red, fontWeight: partoComSucesso ? FontWeight.normal : FontWeight.bold)),
                    const SizedBox(width: 4),
                    Switch(
                      value: partoComSucesso,
                      onChanged: (value) {
                        setModalState(() => onPartoComSucessoChange(value));
                      },
                      activeColor: AppTheme.darkGreen,
                      inactiveThumbColor: Colors.red,
                      inactiveTrackColor: Colors.red.withOpacity(0.4),
                    ),
                    const SizedBox(width: 4),
                    Text("Criou", style: TextStyle(color: partoComSucesso ? AppTheme.darkGreen : Colors.grey[600], fontWeight: partoComSucesso ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (partoComSucesso) ...[
              const Text("Sexo do Potro"),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                    Text("Macho", style: TextStyle(fontWeight: sexoPotro == "Macho" ? FontWeight.bold : FontWeight.normal, color: sexoPotro == "Macho" ? AppTheme.darkGreen: Colors.grey[600])),
                    Switch(
                      value: sexoPotro == "Fêmea",
                      onChanged: (value) {
                        final novoSexo = value ? "Fêmea" : "Macho";
                        onSexoPotroChange(novoSexo);
                      },
                      activeColor: Colors.pink[200],
                      inactiveThumbColor: AppTheme.darkGreen,
                      inactiveTrackColor: AppTheme.darkGreen.withOpacity(0.5),
                        thumbColor: MaterialStateProperty.resolveWith((states) {
                          if (states.contains(MaterialState.selected)) {
                            return Colors.pink[200];
                          }
                          return AppTheme.darkGreen;
                        }),
                      ),
                    Text("Fêmea", style: TextStyle(fontWeight: sexoPotro == "Fêmea" ? FontWeight.bold : FontWeight.normal, color: sexoPotro == "Fêmea" ? Colors.pink[300]: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: pelagemController,
                decoration: const InputDecoration(
                labelText: "Pelagem do Potro",
                prefixIcon: Icon(Icons.pets_outlined)),
                validator: (v) => v!.isEmpty ? "Obrigatório" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                readOnly: true,
                controller: TextEditingController(
                  text: dataHoraParto == null
                      ? ''
                      : DateFormat('dd/MM/yyyy HH:mm').format(dataHoraParto),
                ),
                decoration: const InputDecoration(
                  labelText: "Data e Hora do Parto",
                  hintText: 'Toque para selecionar',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (date == null) return;
                  TimeOfDay? time;
                  await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text("Selecione a Hora"),
                        content: TimePickerSpinner(
                          is24HourMode: true,
                          minutesInterval: 5,
                          onTimeChange: (dateTime) {
                            time = TimeOfDay.fromDateTime(dateTime);
                          },
                        ),
                        actions: <Widget>[
                          TextButton(
                            child: const Text("CANCELAR"),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          TextButton(
                            child: const Text("OK"),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      );
                    },
                  );
                  if (time != null) {
                    onDataHoraPartoChange(DateTime(date.year, date.month, date.day, time!.hour, time!.minute));
                  }
                },
                validator: (v) => dataHoraParto == null ? "Obrigatório" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: observacoesPartoController,
                decoration: const InputDecoration(
                  labelText: "Observações",
                  prefixIcon: Icon(Icons.comment_outlined)),
                maxLines: 2,
              ),
            ] else ...[
              const SizedBox(height: 10),
                TextFormField(
                controller: observacoesPartoController,
                decoration: const InputDecoration(
                  labelText: "Observações sobre a perda",
                  prefixIcon: Icon(Icons.comment_outlined)),
                maxLines: 2,
              ),
            ]
          ]
        ];
      case "Inseminação":
        return [
          TextFormField(
            controller: garanhaoController,
            decoration: const InputDecoration(
                labelText: "Garanhão",
                prefixIcon: Icon(Icons.male_outlined)),
            validator: (v) => v == null ? "Obrigatório" : null,
          ),
          const SizedBox(height: 10),
            DropdownButtonFormField<String>(
            value: tipoSememSelecionado,
            decoration: InputDecoration(
                labelText: "Tipo de Sêmen",
                prefixIcon: Icon(Icons.science_outlined),
                ),
            hint: const Text("Selecione o tipo"),
            items: tiposSemem
                .map((tipo) => DropdownMenuItem(value: tipo, child: Text(tipo)))
                .toList(),
            onChanged: (val) => setModalState(() => onTipoSememChange(val)),
            validator: (v) => v == null ? "Obrigatório" : null,
          ),
          if (tipoSememSelecionado == 'Congelado') ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: quantidadePalhetas,
              decoration: const InputDecoration(
                labelText: "Quantidade de Palhetas",
                prefixIcon: Icon(Icons.unfold_more_outlined),
              ),
              hint: const Text("Selecione a quantidade"),
              items: List.generate(15, (index) => index + 1)
                  .map((qnt) => DropdownMenuItem(value: qnt, child: Text(qnt.toString())))
                  .toList(),
              onChanged: (val) => setModalState(() => onQuantidadePalhetasChange(val)),
              validator: (v) => v == null ? "Obrigatório" : null,
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            readOnly: true,
            controller: TextEditingController(
              text: dataHoraInseminacao == null
                  ? ''
                  : DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dataHoraInseminacao),
            ),
            decoration: const InputDecoration(
                labelText: "Data/Hora da Inseminação",
                prefixIcon: Icon(Icons.calendar_today_outlined),
                hintText: 'Toque para selecionar',
                ),
            validator: (v) => v == null ? "Obrigatório" : null,
            onTap: () async {
              final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now());
              if (date == null) return;
              TimeOfDay? time;
                await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text("Selecione a Hora"),
                      content: TimePickerSpinner(
                        is24HourMode: true,
                        minutesInterval: 5,
                        onTimeChange: (dateTime) {
                          time = TimeOfDay.fromDateTime(dateTime);
                        },
                      ),
                      actions: <Widget>[
                        TextButton(
                          child: const Text("CANCELAR"),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        TextButton(
                          child: const Text("OK"),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    );
                  },
                );

              if (time != null) {
                  onDataHoraInseminacaoChange(DateTime(
                    date.year, date.month, date.day, time!.hour, time!.minute));
              }
            },
          ),
        ];
      case "Lavado":
      return [
        TextFormField(
            controller: litrosController,
            decoration: const InputDecoration(
                labelText: "Litros",
                prefixIcon: Icon(Icons.water_drop_outlined)),
            keyboardType: TextInputType.number),
        const SizedBox(height: 10),
        TextFormField(
          controller: medicamentoSearchController,
          decoration: InputDecoration(
            labelText: "Buscar Medicamento",
            prefixIcon: Icon(Icons.medication_outlined),
            suffixIcon: medicamentoSelecionado != null
                ? IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      setModalState(() {
                        onMedicamentoChange(null);
                        onShowMedicamentoListChange(true);
                        medicamentoSearchController.clear();
                        FocusScope.of(context).unfocus();
                      });
                    },
                  )
                : const Icon(Icons.search_outlined),
          ),
          onChanged: filterMedicamentos,
          onTap: () => onShowMedicamentoListChange(true),
        ),
        if (showMedicamentoList)
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: filteredMedicamentos.length,
              itemBuilder: (context, index) {
                final med = filteredMedicamentos[index];
                return ListTile(
                  title: Text(med.nome),
                  onTap: () {
                    setModalState(() {
                      onMedicamentoChange(med);
                      medicamentoSearchController.text = med.nome;
                      onShowMedicamentoListChange(false);
                      FocusScope.of(context).unfocus();
                    });
                  },
                );
              },
            ),
          ),
      ];
      case "Controle Folicular":
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: DropdownButtonFormField<String>(
                      value: ovarioDirOp,
                      decoration: const InputDecoration(
                        labelText: "Ovário Direito",
                        prefixIcon: Icon(Icons.join_right_outlined)
                      ),
                      items: ovarioOptions
                          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                          .toList(),
                      onChanged: (val) => setModalState(() => onOvarioDirChange(val)))),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextFormField(
                  controller: ovarioDirTamanhoController,
                  decoration:
                      const InputDecoration(labelText: "Tamanho (mm)"),
                ),
              )
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: DropdownButtonFormField<String>(
                      value: ovarioEsqOp,
                      decoration: const InputDecoration(
                        labelText: "Ovário Esquerdo",
                        prefixIcon: Icon(Icons.join_left_outlined)
                      ),
                      items: ovarioOptions
                          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                          .toList(),
                      onChanged: (val) => setModalState(() => onOvarioEsqChange(val)))),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextFormField(
                    controller: ovarioEsqTamanhoController,
                    decoration:
                        const InputDecoration(labelText: "Tamanho (mm)")),
              )
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: edemaSelecionado,
            decoration: const InputDecoration(
              labelText: "Edema",
              prefixIcon: Icon(Icons.numbers_outlined)
            ),
            items: ['0', '1', '1-2', '2', '2-3', '3', '3-4', '4', '4-5', '5']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) => setModalState(() => onEdemaChange(val)),
          ),
          const SizedBox(height: 10),
          TextFormField(
              controller: uteroController,
              decoration: const InputDecoration(
                  labelText: "Útero",
                  prefixIcon: Icon(Icons.notes_outlined))),
        ];
      case "Transferência de Embrião":
        return [
          FutureBuilder<List<Egua>>(
            future: SQLiteHelper.instance.getAllEguas(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              return DropdownButtonFormField<Egua>(
                value: doadoraSelecionada,
                decoration: InputDecoration(
                  labelText: "Doadora",
                  prefixIcon: Icon(Icons.volunteer_activism_outlined),
                    suffixIcon: doadoraSelecionada != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          setModalState(() {
                            onDoadoraChange(null);
                          });
                        },
                      )
                    : null,
                ),
                validator: (v) => v == null ? "Obrigatório" : null,
                items: snapshot.data!
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.nome)))
                    .toList(),
                onChanged: (val) => setModalState(() => onDoadoraChange(val)),
              );
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: idadeEmbriao,
            decoration: InputDecoration(
              labelText: "Idade do Embrião",
              prefixIcon: Icon(Icons.hourglass_bottom_outlined),
                suffixIcon: idadeEmbriao != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      setModalState(() {
                        onIdadeEmbriaoChange(null);
                      });
                    },
                  )
                : null,
            ),
            items: idadeEmbriaoOptions
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) => setModalState(() => onIdadeEmbriaoChange(val)),
          ),
          const SizedBox(height: 10),
          TextFormField(
              controller: avaliacaoUterinaController,
              decoration:
              const InputDecoration(
                  labelText: "Avaliação Uterina",
                  prefixIcon: Icon(Icons.notes))),
        ];
      case "Coleta de Embrião":
        return [
          DropdownButtonFormField<String>(
            value: idadeEmbriao,
            decoration: InputDecoration(
              labelText: "Idade do Embrião",
              prefixIcon: Icon(Icons.hourglass_bottom_outlined),
                suffixIcon: idadeEmbriao != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      setModalState(() {
                        onIdadeEmbriaoChange(null);
                      });
                    },
                  )
                : null,
            ),
            items: idadeEmbriaoOptions
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) => setModalState(() => onIdadeEmbriaoChange(val)),
          )
        ];
      default:
        return [];
    }
  }

  _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.darkGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: AppTheme.darkText, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _buildControleFolicularInputs({required void Function(void Function()) setModalState, required String? ovarioDirOp, required void Function(String? val) onOvarioDirChange, required TextEditingController ovarioDirTamanhoController, required String? ovarioEsqOp, required void Function(String? val) onOvarioEsqChange, required TextEditingController ovarioEsqTamanhoController, required String? edemaSelecionado, required void Function(String? val) onEdemaChange, required TextEditingController uteroController}) {
    final ovarioOptions = ["CL", "OV", "PEQ", "FL", "FH"];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text("Dados do Controle Folicular", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 15),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: ovarioDirOp,
                decoration: InputDecoration(
                  labelText: "Ovário Direito",
                  prefixIcon: Icon(Icons.join_right_outlined),
                    suffixIcon: ovarioDirOp != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          setModalState(() {
                            onOvarioDirChange(null);
                          });
                        },
                      )
                    : null,
                ),
                items: ovarioOptions
                    .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                    .toList(),
                onChanged: onOvarioDirChange,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: ovarioDirTamanhoController,
                decoration: const InputDecoration(labelText: "Tamanho (mm)"),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: ovarioEsqOp,
                decoration: InputDecoration(
                  labelText: "Ovário Esquerdo",
                  prefixIcon: Icon(Icons.join_left_outlined),
                    suffixIcon: ovarioEsqOp != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          setModalState(() {
                            onOvarioEsqChange(null);
                          });
                        },
                      )
                    : null,
                ),
                items: ovarioOptions
                    .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                    .toList(),
                onChanged: onOvarioEsqChange,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: ovarioEsqTamanhoController,
                decoration: const InputDecoration(labelText: "Tamanho (mm)"),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            )
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: edemaSelecionado,
          decoration: InputDecoration(
            labelText: "Edema",
            prefixIcon: Icon(Icons.numbers_outlined),
              suffixIcon: edemaSelecionado != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          setModalState(() {
                            onEdemaChange(null);
                          });
                        },
                      )
                    : null,
          ),
          items: ['0', '1', '1-2', '2', '2-3', '3', '3-4', '4', '4-5', '5']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onEdemaChange,
        ),
        const SizedBox(height: 10),
        TextFormField(
            controller: uteroController,
            decoration: const InputDecoration(
                labelText: "Útero",
                prefixIcon: Icon(Icons.notes_outlined))),
      ],
    );
  }
}

class _EditEguaForm extends StatefulWidget {
  final Egua egua;

  const _EditEguaForm({required this.egua});

  @override
  _EditEguaFormState createState() => _EditEguaFormState();
}

class _EditEguaFormState extends State<_EditEguaForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _proprietarioController;
  late final TextEditingController _rpController;
  late final TextEditingController _pelagemController;
  late final TextEditingController _coberturaController;
  late final TextEditingController _obsController;

  String? _newPhotoPath;

  late String _categoriaSelecionada;
  late bool _teveParto;
  late DateTime? _dataParto;
  late String? _sexoPotro;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.egua.nome);
    _proprietarioController = TextEditingController(text: widget.egua.proprietario);
    _rpController = TextEditingController(text: widget.egua.rp);
    _pelagemController = TextEditingController(text: widget.egua.pelagem);
    _coberturaController = TextEditingController(text: widget.egua.cobertura);
    _obsController = TextEditingController(text: widget.egua.observacao);

    _categoriaSelecionada = widget.egua.categoria;
    _teveParto = widget.egua.dataParto != null;
    _dataParto = widget.egua.dataParto;
    _sexoPotro = widget.egua.sexoPotro ?? 'Macho';
    _newPhotoPath = widget.egua.photoPath;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _proprietarioController.dispose();
    _rpController.dispose();
    _pelagemController.dispose();
    _coberturaController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_formKey.currentState!.validate()) {
      final updatedEgua = widget.egua.copyWith(
        nome: _nomeController.text,
        proprietario: _proprietarioController.text,
        rp: _rpController.text,
        pelagem: _pelagemController.text,
        categoria: _categoriaSelecionada,
        cobertura: _categoriaSelecionada != 'Receptora'
            ? _coberturaController.text
            : null,
        observacao: _obsController.text,
        dataParto: _teveParto ? _dataParto : null,
        sexoPotro: _teveParto ? (_sexoPotro ?? 'Macho') : null,
        statusSync: 'pending_update',
        photoPath: _newPhotoPath,
      );

      await SQLiteHelper.instance.updateEgua(updatedEgua);

      if (mounted) {
        Navigator.of(context).pop(updatedEgua);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 20,
          left: 20,
          right: 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: (IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close),
                  ))),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Editar Égua",
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                      icon:
                          Icon(Icons.delete_outlined, color: Colors.red[700]),
                      onPressed: () =>
                          Navigator.of(context).pop('wants_to_delete')),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                  controller: _nomeController,
                  decoration: const InputDecoration(
                      labelText: "Nome da Égua",
                      prefixIcon: Icon(Icons.female_outlined)),
                  validator: (v) => v!.isEmpty ? "Obrigatório" : null),
              const SizedBox(height: 10),
              TextFormField(
                  controller: _proprietarioController,
                  decoration: const InputDecoration(
                      labelText: "Proprietário",
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => v!.isEmpty ? "Obrigatório" : null),
              const SizedBox(height: 10),
              TextFormField(
                  controller: _rpController,
                  decoration: const InputDecoration(
                      labelText: "RP",
                      prefixIcon: Icon(Icons.numbers_outlined))),
              const SizedBox(height: 10),
              TextFormField(
                  controller: _pelagemController,
                  decoration: const InputDecoration(
                      labelText: "Pelagem", prefixIcon: Icon(Icons.pets)),
                  validator: (v) => v!.isEmpty ? "Obrigatório" : null),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _categoriaSelecionada,
                decoration: InputDecoration(
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
                    setState(() {
                      _categoriaSelecionada = value;
                    });
                  }
                },
              ),
              if (_categoriaSelecionada != 'Receptora')
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: TextFormField(
                    controller: _coberturaController,
                    decoration: const InputDecoration(
                      labelText: "Padreador",
                      prefixIcon: Icon(Icons.male),
                    ),
                  ),
                ),
              const SizedBox(height: 15),
              SwitchListTile(
                title: const Text("Teve Parto?"),
                value: _teveParto,
                onChanged: (bool value) {
                  setState(() {
                    _teveParto = value;
                  });
                },
                activeColor: AppTheme.darkGreen,
              ),
              if (_teveParto)
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
                          text: _dataParto == null
                              ? ''
                              : DateFormat('dd/MM/yyyy').format(_dataParto!),
                        ),
                        decoration: const InputDecoration(
                          labelText: "Data do Parto",
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          hintText: 'Selecione a data',
                        ),
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: _dataParto ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now());
                          if (pickedDate != null) {
                            setState(() => _dataParto = pickedDate);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text("Sexo do Potro"),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text("Macho",
                              style: TextStyle(
                                  fontWeight: _sexoPotro == "Macho"
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _sexoPotro == "Macho"
                                      ? AppTheme.darkGreen
                                      : Colors.grey[600])),
                          Switch(
                            value: _sexoPotro == "Fêmea",
                            onChanged: (value) {
                              setState(() {
                                _sexoPotro = value ? "Fêmea" : "Macho";
                              });
                            },
                            activeColor: Colors.pink[200],
                            inactiveThumbColor: AppTheme.darkGreen,
                            inactiveTrackColor:
                                AppTheme.darkGreen.withOpacity(0.5),
                            thumbColor:
                                MaterialStateProperty.resolveWith((states) {
                              if (states.contains(MaterialState.selected)) {
                                return Colors.pink[200];
                              }
                              return AppTheme.darkGreen;
                            }),
                          ),
                          Text("Fêmea",
                              style: TextStyle(
                                  fontWeight: _sexoPotro == "Fêmea"
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _sexoPotro == "Fêmea"
                                      ? Colors.pink[300]
                                      : Colors.grey[600])),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              TextFormField(
                  controller: _obsController,
                  decoration: const InputDecoration(
                      labelText: "Observação",
                      prefixIcon: Icon(Icons.comment_outlined)),
                  maxLines: 3),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveChanges,
                  child: const Text("Salvar Alterações"),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTopLevelProps() async {
    final props = await SQLiteHelper.instance.readTopLevelPropriedades();
    setState(() {
      _topLevelProps = props;
      _filteredList = props;
    });
  }

  Future<void> _loadSubProps(String parentId) async {
    final lotes = await SQLiteHelper.instance.readSubPropriedades(parentId);
    setState(() {
      _subProps = lotes.where((lote) => lote.id != widget.currentPropriedadeId).toList();
      _filteredList = _subProps;
    });
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

  void _confirmAndMove(Propriedade destPropriedade) async {
    Navigator.of(context).pop();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Confirmar Movimentação"),
        content: Text(
            "Deseja mover ${widget.selectedEguas.length} égua(s) para \"${destPropriedade.nome}\"?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text("Cancelar")),
          ElevatedButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text("Mover")),
        ],
      ),
    );

    if (confirmed == true) {
      for (String eguaId in widget.selectedEguas) {
        final eguaToMove = await SQLiteHelper.instance.getEguaById(eguaId);
        final manejosToMove = await SQLiteHelper.instance.readAgendadosByEgua(eguaId);
        if (eguaToMove != null) {
          final updatedEgua = eguaToMove.copyWith(
            propriedadeId: destPropriedade.id,
            statusSync: 'pending_update',
          );
          await SQLiteHelper.instance.updateEgua(updatedEgua);
        }
        if (manejosToMove.isNotEmpty) {
          for (final manejo in manejosToMove) {
          final updatedManejos = manejo.copyWith(
            propriedadeId: destPropriedade.id,
            statusSync: 'pending_update',
          );
          await SQLiteHelper.instance.updateManejo(updatedManejos);
          }
        }
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