import 'package:flutter/material.dart';
import 'package:flutter_time_picker_spinner/flutter_time_picker_spinner.dart';
import 'package:intl/intl.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/egua_model.dart';
import 'package:nobryo_final/core/models/manejo_model.dart';
import 'package:nobryo_final/core/models/medicamento_model.dart';
import 'package:nobryo_final/core/models/user_model.dart';
import 'package:nobryo_final/core/services/auth_service.dart';
import 'package:nobryo_final/core/services/export_service.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:uuid/uuid.dart';

class EguaDetailsScreen extends StatefulWidget {
  final Egua egua;
  final Function(String eguaId)? onEguaDeleted;

  const EguaDetailsScreen({
    super.key,
    required this.egua,
    this.onEguaDeleted,
  });

  @override
  State<EguaDetailsScreen> createState() => _EguaDetailsScreenState();
}

class _EguaDetailsScreenState extends State<EguaDetailsScreen>
    with AutomaticKeepAliveClientMixin<EguaDetailsScreen> {
  late Egua _currentEgua;
  late Future<List<Manejo>> _historicoFuture;
  late Future<List<Manejo>> _agendadosFuture;
  final ExportService _exportService = ExportService();
  int? _diasPrenheCalculado;
  // NOVO: Variável para armazenar a previsão de parto
  DateTime? _previsaoParto;
  Map<String, AppUser> _allUsers = {};
  final SyncService _syncService = SyncService();
  final AuthService _authService = AuthService();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentEgua = widget.egua;
    _refreshData();
  }

  void _refreshData() {
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
          _historicoFuture =
              SQLiteHelper.instance.readHistoricoByEgua(_currentEgua.id);
          _agendadosFuture =
              SQLiteHelper.instance.readAgendadosByEgua(_currentEgua.id);
        });
        _loadUsersAndCalculateDays();
      }
    });
  }

  Future<void> _autoSync() async {
    await _syncService.syncData(isManual: false);
    if (mounted) {
      _refreshData();
    }
  }

  void _loadUsersAndCalculateDays() async {
    final users = await SQLiteHelper.instance.getAllUsers();
    if (mounted) {
      setState(() {
        _allUsers = {for (var u in users) u.uid: u};
      });
    }
    _calcularDiasPrenhe();
    _calcularPrevisaoParto();
  }

  void _calcularDiasPrenhe() async {
    if (_currentEgua.statusReprodutivo.toLowerCase() != 'prenhe') {
      if (mounted) setState(() => _diasPrenheCalculado = null);
      return;
    }

    final historico = await _historicoFuture;
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

  // NOVO: Função para calcular a previsão de parto para esta égua específica
  void _calcularPrevisaoParto() async {
    if (_currentEgua.statusReprodutivo.toLowerCase() != 'prenhe') {
      if (mounted) setState(() => _previsaoParto = null);
      return;
    }

    final historico = await _historicoFuture;
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
      _refreshData();
    }
  }

  Future<void> _promptForDiagnosticSchedule(DateTime inseminationDate) async {
    await Future.delayed(Duration(seconds: 2));
    final bool? confirm = await showGeneralDialog<bool>(
      context: context,
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: child,
        );
      },
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return AlertDialog(
          title: const Text("Agendamento Automático"),
          content: const Text(
              "Inseminação concluída. Deseja agendar o diagnóstico para daqui a 14 dias?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Não"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Sim"),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      _showAddAgendamentoModal(
        context,
        preselectedType: "Diagnóstico",
        preselectedDate: inseminationDate.add(const Duration(days: 14)),
      );
    }
  }

    Widget _buildControleFolicularInputs({
    required StateSetter setModalState,
    required String? ovarioDirOp,
    required Function(String?) onOvarioDirChange,
    required TextEditingController ovarioDirTamanhoController,
    required String? ovarioEsqOp,
    required Function(String?) onOvarioEsqChange,
    required TextEditingController ovarioEsqTamanhoController,
    required String? edemaSelecionado,
    required Function(String?) onEdemaChange,
    required TextEditingController uteroController,
  }) {
    final ovarioOptions = ["CL", "OV", "PEQ", "FL"];
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
                decoration: const InputDecoration(
                  labelText: "Ovário Direito",
                  prefixIcon: Icon(Icons.join_right_outlined)
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
                decoration: const InputDecoration(
                  labelText: "Ovário Esquerdo",
                  prefixIcon: Icon(Icons.join_left_outlined)
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
          decoration: const InputDecoration(
            labelText: "Edema",
            prefixIcon: Icon(Icons.numbers_outlined)
          ),
          items: ['1', '1-2', '2', '2-3', '3', '3-4', '4', '4-5', '5']
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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Informações da Égua",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkText)),
                  const SizedBox(height: 16),
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
                          backgroundColor: AppTheme.darkGreen.withOpacity(0.9),
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
                  const SizedBox(height: 16),
                  _buildManejoList(_historicoFuture, isHistorico: true),
                  const SizedBox(height: 20),
                ],
              ),
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
              onPressed: () => _showAddHistoricoModal(context, isEditing: false),
              child: const Text("Adicionar Manejo ao Histórico"),
            ),
          ),
        ],
      ),
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
              Expanded(child: _buildInfoItem("RP:", egua.rp)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildInfoItem("Pelagem:", egua.pelagem)),
              if (egua.categoria == 'Matriz' &&
                  egua.cobertura != null &&
                  egua.cobertura!.isNotEmpty)
                Expanded(child: _buildInfoItem("Padreador:", egua.cobertura!))
              else if (egua.categoria != 'Matriz')
                Expanded(child: _buildInfoItem("Categoria:", egua.categoria)),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
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
                Text(label,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: AppTheme.darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
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
  
  Widget _buildManejoList(Future<List<Manejo>> future,
      {required bool isHistorico}) {
    return FutureBuilder<List<Manejo>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text("Erro: ${snapshot.error}"));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
                isHistorico
                    ? "Nenhum manejo no histórico."
                    : "Nenhum manejo agendado.",
                style: const TextStyle(color: Colors.grey)),
          ));
        }

        final manejos = snapshot.data!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: manejos.length,
          itemBuilder: (context, index) {
            final manejo = manejos[index];
            final responsavelNome =
                _allUsers[manejo.responsavelId]?.nome ?? '...';
            final concluidoPorNome =
                _allUsers[manejo.concluidoPorId]?.nome ?? '...';

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
                          Text(
                              DateFormat('dd/MM/yyyy')
                                  .format(manejo.dataAgendada),
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
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
                        _buildDetalhesManejo(manejo.detalhes),
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
              await SQLiteHelper.instance.softDeleteManejo(manejo.id);
              if (mounted) {
                Navigator.of(dialogCtx).pop();
                _refreshData();
                _autoSync();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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

  Widget _buildDetalhesManejo(Map<String, dynamic> detalhes) {
    const labelMap = {
      'resultado': 'Resultado',
      'diasPrenhe': 'Dias de Prenhez',
      'garanhao': 'Garanhão',
      'dataHora': 'Data/Hora da Inseminação',
      'litros': 'Litros',
      'medicamento': 'Medicamento',
      'ovarioDireito': 'Ovário Direito',
      'ovarioDireitoTamanho': 'Tamanho Ov. Direito',
      'ovarioEsquerdo': 'Ovário Esquerdo',
      'ovarioEsquerdoTamanho': 'Tamanho Ov. Esquerdo',
      'edema': 'Edema',
      'utero': 'Útero',
      'idadeEmbriao': 'Idade do Embrião',
      'doadora': 'Doadora',
      'avaliacaoUterina': 'Avaliação Uterina',
      'observacao': 'Observação',
      'inducao': 'Indução',
      'dataHoraInducao': 'Data/Hora da Indução'
    };

    String formatValue(String key, dynamic value) {
      if (value is String) {
        if (key == 'dataHora' || key == 'dataHoraInducao') {
          try {
            final dt = DateTime.parse(value);
            return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dt);
          } catch (e) {}
        }
      }
      return value.toString();
    }

    final detailEntries = detalhes.entries
        .where((entry) =>
            entry.value != null &&
            entry.value.toString().isNotEmpty &&
            labelMap.containsKey(entry.key))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: detailEntries.map((entry) {
        if (entry.key == 'inducao') {
          return Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.statusDiagnostico,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "${labelMap[entry.key]!.toUpperCase()}: ${entry.value.toString().toUpperCase()}",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }

        return Padding(
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
        );
      }).toList(),
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
                final historico = await _historicoFuture;
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
                final historico = await _historicoFuture;
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
      {DateTime? preselectedDate, String? preselectedType}) {
    final currentUser = _authService.currentUserNotifier.value;
    if (currentUser == null) return;

    final formKey = GlobalKey<FormState>();
    DateTime? dataSelecionada = preselectedDate;
    String? tipoManejoSelecionado = preselectedType;
    final detalhesController = TextEditingController();
    final tiposDeManejo = [
      "Controle Folicular", "Inseminação", "Lavado", "Diagnóstico",
      "Transferência de Embrião", "Coleta de Embrião", "Outros Manejos"
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                          prefixIcon:
                              Icon(Icons.calendar_today_outlined),
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
                          prefixIcon: Icon(Icons.edit_note_outlined)),
                      hint: const Text("Selecione o Tipo de Manejo"),
                      items: tiposDeManejo
                          .map((tipo) => DropdownMenuItem(
                              value: tipo, child: Text(tipo)))
                          .toList(),
                      onChanged: (val) =>
                          setModalState(() => tipoManejoSelecionado = val),
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
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.darkGreen),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final novoManejo = Manejo(
                              id: const Uuid().v4(),
                              tipo: tipoManejoSelecionado!,
                              dataAgendada: dataSelecionada!,
                              detalhes: {'descricao': detalhesController.text},
                              eguaId: _currentEgua.id,
                              propriedadeId: _currentEgua.propriedadeId,
                              responsavelId: currentUser.uid,
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
    final responsavelNome = _allUsers[manejo.responsavelId]?.nome ?? 'Desconhecido';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
              _refreshData();
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
                          _refreshData();
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
                            if (value == 'edit_obs') {
                                _showEditObservacaoModal(ctx, manejo);
                            } else if (value == 'reschedule') {
                                reagendarLocal();
                            } else if (value == 'delete') {
                                deletarLocal();
                            }
                        },
                        itemBuilder: (BuildContext popupContext) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                              value: 'edit_obs',
                              child: ListTile(
                                  leading: Icon(Icons.notes_outlined),
                                  title: Text('Editar Observação'),
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
                            backgroundColor:
                                AppTheme.darkGreen,
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

  void _showEditObservacaoModal(BuildContext context, Manejo manejo) {
    final formKey = GlobalKey<FormState>();
    final obsController =
        TextEditingController(text: manejo.detalhes['descricao'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (editCtx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(editCtx).viewInsets.bottom,
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
                Text("Editar Observação",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text("Manejo: ${manejo.tipo}", style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
                const Divider(height: 30),
                TextFormField(
                  controller: obsController,
                  decoration: const InputDecoration(
                    labelText: "Observação",
                    prefixIcon: Icon(Icons.comment_outlined)
                  ),
                  maxLines: 4,
                  autofocus: true,
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text("SALVAR OBSERVAÇÃO"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.darkGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  onPressed: () async {
                    manejo.detalhes['descricao'] = obsController.text;
                    manejo.statusSync = 'pending_update';

                    await SQLiteHelper.instance.updateManejo(manejo);

                      if (mounted) {
                        Navigator.of(editCtx).pop();
                        Navigator.of(context).pop();
                        _refreshData();
                        _autoSync();
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text("Observação atualizada!"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
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

  void _showMarkAsCompleteModal(BuildContext context, Manejo manejo) async {
    final currentUser = _authService.currentUserNotifier.value;
    if(currentUser == null) return;

    final formKey = GlobalKey<FormState>();
    final obsController = TextEditingController(text: manejo.detalhes['observacao']);

    final garanhaoController = TextEditingController(text: _currentEgua.cobertura);
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
    DateTime? dataHoraInseminacao;
    DateTime dataFinalManejo = manejo.dataAgendada;

    Medicamento? medicamentoSelecionado;
    String? inducaoSelecionada;
    DateTime? dataHoraInducao;
    final medicamentoSearchController = TextEditingController();
    List<Medicamento> _filteredMedicamentos = todosMedicamentos;
    bool _showMedicamentoList = false;

    final List<AppUser> allUsersList = await SQLiteHelper.instance.getAllUsers();
    AppUser? concluidoPorSelecionado = allUsersList.firstWhere((u) => u.uid == currentUser.uid, orElse: () => allUsersList.first);

    bool _incluirControleFolicular = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                      medicamentoSearchController: medicamentoSearchController,
                      filterMedicamentos: filterMedicamentos,
                      showMedicamentoList: _showMedicamentoList,
                      onShowMedicamentoListChange: (show) => setModalState(() => _showMedicamentoList = show),
                      filteredMedicamentos: _filteredMedicamentos,
                    ),

                     if (manejo.tipo != 'Controle Folicular') ...[
                      const Divider(height: 20, thickness: 1),
                      Text("Incluir Controle Folicular?", style: Theme.of(context).textTheme.titleMedium),
                      Row(
                        children: [
                          Expanded(child: RadioListTile<bool>(title: const Text("Sim"), value: true, groupValue: _incluirControleFolicular, onChanged: (val) => setModalState(() => _incluirControleFolicular = val!))),
                          Expanded(child: RadioListTile<bool>(title: const Text("Não"), value: false, groupValue: _incluirControleFolicular, onChanged: (val) => setModalState(() => _incluirControleFolicular = val!))),
                        ],
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
                        hint: const Text("Indução"),
                        items: ["HCG", "DESLO", "HCG+DESLO"]
                            .map((label) => DropdownMenuItem(child: Text(label), value: label))
                            .toList(),
                        onChanged: (value) => setModalState(() => inducaoSelecionada = value)),
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
                              setModalState(() => dataHoraInducao = DateTime(date.year, date.month, date.day, time!.hour, time!.minute));
                           }
                        },
                        validator: (v) {
                          if (inducaoSelecionada != null && dataHoraInducao == null) {
                            return "Campo obrigatório";
                          }
                          return null;
                        },  
                      ),
                    ],
                    
                    const Divider(height: 20, thickness: 1),
                    Text("Detalhes da Conclusão", style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 15),

                    DropdownButtonFormField<AppUser>(
                      value: concluidoPorSelecionado,
                      hint: const Text("Responsável pela conclusão"),
                      decoration: const InputDecoration(
                        labelText: "Concluído por",
                        prefixIcon: Icon(Icons.person_outlined)),
                      items: allUsersList.map((user) => DropdownMenuItem(value: user, child: Text(user.nome))).toList(),
                      onChanged: (user) => setModalState(() => concluidoPorSelecionado = user),
                      validator: (v) => v == null ? "Selecione um responsável" : null,
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
                        text: DateFormat('dd/MM/yyyy').format(dataFinalManejo)
                      ),
                      decoration: const InputDecoration(
                          labelText: "Data da Conclusão",
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          hintText: 'Toque para selecionar a data'),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: dataFinalManejo,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030));
                        if (pickedDate != null)
                          setModalState(() => dataFinalManejo = pickedDate);
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
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
                                    statusSync: 'pending_update');
                                await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                                if(mounted) setState(() => _currentEgua = eguaAtualizada);
                              } else {
                                final eguaAtualizada = _currentEgua.copyWith(
                                    statusReprodutivo: 'Vazia',
                                    diasPrenhe: 0,
                                    statusSync: 'pending_update');
                                await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                                if(mounted) setState(() => _currentEgua = eguaAtualizada);
                              }
                            } else if (manejo.tipo == 'Inseminação') {
                              detalhes['garanhao'] = garanhaoController.text;
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
                            manejo.concluidoPorId = concluidoPorSelecionado?.uid;

                            await SQLiteHelper.instance.updateManejo(manejo);

                            if (mounted) Navigator.of(ctx).pop();
                            _refreshData();
                          }

                          if (manejo.tipo == "Inseminação") {
                            _promptForDiagnosticSchedule(dataHoraInseminacao ?? dataFinalManejo);
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

    final formKey = GlobalKey<FormState>();
    final String title = isEditing ? "Editar Manejo do Histórico" : "Adicionar ao Histórico";

    String? tipoManejoSelecionado = manejo?.tipo;
    DateTime dataFinalManejo = manejo?.dataAgendada ?? DateTime.now();
    final obsController = TextEditingController(text: manejo?.detalhes['observacao'] ?? '');
    
    final garanhaoController = TextEditingController(text: manejo?.detalhes['garanhao'] ?? _currentEgua.cobertura);
    final litrosController = TextEditingController(text: manejo?.detalhes['litros']?.toString());
    
    String? ovarioDirOp = manejo?.detalhes['ovarioDireito'];
    String? ovarioEsqOp = manejo?.detalhes['ovarioEsquerdo'];
    String? edemaSelecionado = manejo?.detalhes['edema'];
    String? idadeEmbriaoSelecionada = manejo?.detalhes['idadeEmbriao'];
    String? resultadoDiagnostico = manejo?.detalhes['resultado'];
    
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
       medicamentoSelecionado = todosMedicamentos.firstWhere((med) => med.id == manejo!.medicamentoId, orElse: () => todosMedicamentos.isNotEmpty ? todosMedicamentos.first : null!);
     } else if (manejo?.detalhes['medicamento'] != null) {
       medicamentoSelecionado = todosMedicamentos.firstWhere((med) => med.nome == manejo!.detalhes['medicamento'], orElse: () => todosMedicamentos.isNotEmpty ? todosMedicamentos.first : null!);
     }
    
    String? inducaoSelecionada = manejo?.inducao;
    final medicamentoSearchController = TextEditingController(text: medicamentoSelecionado?.nome);
    List<Medicamento> _filteredMedicamentos = todosMedicamentos;
    bool _showMedicamentoList = false;

    Egua? doadoraSelecionada;
    if (manejo?.detalhes['doadora'] != null) {
        final allEguas = await SQLiteHelper.instance.getAllEguas();
        doadoraSelecionada = allEguas.firstWhere((e) => e.nome == manejo!.detalhes['doadora'], orElse: () => allEguas.isNotEmpty ? allEguas.first : null!);
    }

    final List<AppUser> allUsersList = await SQLiteHelper.instance.getAllUsers();
    AppUser? concluidoPorSelecionado;
    if (manejo?.concluidoPorId != null) {
      concluidoPorSelecionado = allUsersList.firstWhere((u) => u.uid == manejo!.concluidoPorId, orElse: () => allUsersList.first);
    } else {
      concluidoPorSelecionado = allUsersList.firstWhere((u) => u.uid == currentUser.uid, orElse: () => allUsersList.first);
    }
    
    bool _incluirControleFolicular = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                      hint: const Text("Selecione o Tipo de Manejo"),
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
                      ),
                      if (tipoManejoSelecionado != 'Controle Folicular') ...[
                        const Divider(height: 20, thickness: 1),
                        Text("Incluir Controle Folicular?", style: Theme.of(context).textTheme.titleMedium),
                        Row(
                          children: [
                            Expanded(child: RadioListTile<bool>(title: const Text("Sim"), value: true, groupValue: _incluirControleFolicular, onChanged: (val) => setModalState(() => _incluirControleFolicular = val!))),
                            Expanded(child: RadioListTile<bool>(title: const Text("Não"), value: false, groupValue: _incluirControleFolicular, onChanged: (val) => setModalState(() => _incluirControleFolicular = val!))),
                          ],
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
                        decoration: const InputDecoration(
                          labelText: "Tipo de Indução",
                          prefixIcon: Icon(Icons.healing_outlined)
                        ),
                        hint: const Text("Indução"),
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
                              setModalState(() => dataHoraInducao = DateTime(date.year, date.month, date.day, time!.hour, time!.minute));
                           }
                        },
                        validator: (v) {
                          if (inducaoSelecionada != null && dataHoraInducao == null) {
                            return "Campo obrigatório";
                          }
                          return null;
                        },  
                      ),
                    ],

                    const Divider(height: 20, thickness: 1),
                    Text("Detalhes da Conclusão", style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 15),

                    DropdownButtonFormField<AppUser>(
                      value: concluidoPorSelecionado,
                      hint: const Text("Responsável pela conclusão"),
                      decoration: const InputDecoration(
                        labelText: "Concluído por",
                        prefixIcon: Icon(Icons.person_outlined)),
                      items: allUsersList.map((user) => DropdownMenuItem(value: user, child: Text(user.nome))).toList(),
                      onChanged: (user) => setModalState(() => concluidoPorSelecionado = user),
                      validator: (v) => v == null ? "Selecione um responsável" : null,
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
                        text: DateFormat('dd/MM/yyyy').format(dataFinalManejo)
                      ),
                      decoration: const InputDecoration(
                          labelText: "Data da Conclusão",
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          hintText: 'Toque para selecionar a data'),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: dataFinalManejo,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030));
                        if (pickedDate != null)
                          setModalState(() => dataFinalManejo = pickedDate);
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final Map<String, dynamic> detalhes = {
                              'observacao': obsController.text
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
                              detalhes['dataHora'] = dataHoraInseminacao?.toIso8601String();
                            } else if (tipoManejoSelecionado == 'Lavado') {
                              detalhes['litros'] = litrosController.text;
                              detalhes['medicamento'] = medicamentoSelecionado?.nome;
                            } else if (tipoManejoSelecionado == 'Controle Folicular') {
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
                                  concluidoPorId: concluidoPorSelecionado?.uid,
                                  statusSync: 'pending_update',
                                  medicamentoId: tipoManejoSelecionado == 'Controle Folicular' ? medicamentoSelecionado?.id : null,
                                  inducao: tipoManejoSelecionado == 'Controle Folicular' ? inducaoSelecionada : null,
                                  dataHoraInducao: tipoManejoSelecionado == 'Controle Folicular' ? dataHoraInducao : null,
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
                                concluidoPorId: concluidoPorSelecionado?.uid,
                                status: 'Concluído',
                                statusSync: 'pending_create',
                                medicamentoId: tipoManejoSelecionado == 'Controle Folicular' ? medicamentoSelecionado?.id : null,
                                inducao: tipoManejoSelecionado == 'Controle Folicular' ? inducaoSelecionada : null,
                                dataHoraInducao: tipoManejoSelecionado == 'Controle Folicular' ? dataHoraInducao : null,
                              );
                              await SQLiteHelper.instance.createManejo(novoManejo);
                            }
                            
                            _refreshData();
                            if (mounted) {
                              Navigator.of(ctx).pop();
                              _autoSync();
                            }
                            if (tipoManejoSelecionado == "Inseminação" && !isEditing) {
                                _promptForDiagnosticSchedule(dataHoraInseminacao ?? dataFinalManejo);
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
    required TextEditingController medicamentoSearchController,
    required void Function(String) filterMedicamentos,
    required bool showMedicamentoList,
    required void Function(bool) onShowMedicamentoListChange,
    required List<Medicamento> filteredMedicamentos,
  }) {
    final ovarioOptions = ["CL", "OV", "PEQ", "FL"];
    final idadeEmbriaoOptions = ['D6', 'D7', 'D8', 'D9', 'D10', 'D11'];
    switch (tipo) {
      case "Diagnóstico":
        return [
          DropdownButtonFormField<String>(
            value: resultadoDiagnostico,
            hint: const Text("Resultado do Diagnóstico"),
            items: ["Indeterminado", "Prenhe", "Vazia", "Pariu"]
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (val) => setModalState(() => onResultadoChange(val)),
            validator: (v) => v == null ? "Selecione um resultado" : null,
          ),
          if (resultadoDiagnostico == 'Prenhe') ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: diasPrenheController,
              decoration: const InputDecoration(labelText: "Dias de Prenhez"),
              keyboardType: TextInputType.number,
              validator: (v) => v!.isEmpty ? "Informe os dias" : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: garanhaoController,
              decoration: const InputDecoration(labelText: "Padreador"),
              validator: (v) => v!.isEmpty ? "Informe o padreador" : null,
            ),
          ],
          if (resultadoDiagnostico == 'Pariu') ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: garanhaoController,
              decoration: const InputDecoration(labelText: "Padreador"),
              validator: (v) => v!.isEmpty ? "Informe o padreador" : null,
            ),
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
                hintText: 'Toque para selecionar'),
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
            validator: (v) =>
                dataHoraInseminacao == null ? "Obrigatório" : null,
            )
          ]
        ];
      case "Inseminação":
        return [
          TextFormField(
              controller: garanhaoController,
              decoration: const InputDecoration(
                  labelText: "Garanhão",
                  prefixIcon: Icon(Icons.male_outlined))),
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
                hintText: 'Toque para selecionar'),
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
            validator: (v) =>
                dataHoraInseminacao == null ? "Obrigatório" : null,
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
            items: ['1', '1-2', '2', '2-3', '3', '3-4', '4', '4-5', '5']
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
                decoration: const InputDecoration(
                  labelText: "Doadora",
                  prefixIcon: Icon(Icons.volunteer_activism_outlined)
                ),
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
            decoration: const InputDecoration(
              labelText: "Idade do Embrião",
              prefixIcon: Icon(Icons.hourglass_bottom_outlined)
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
            decoration: const InputDecoration(
              labelText: "Idade do Embrião",
              prefixIcon: Icon(Icons.hourglass_bottom_outlined)
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
  late final TextEditingController _rpController;
  late final TextEditingController _pelagemController;
  late final TextEditingController _coberturaController;
  late final TextEditingController _obsController;

  late String _categoriaSelecionada;
  late bool _teveParto;
  late DateTime? _dataParto;
  late String? _sexoPotro;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.egua.nome);
    _rpController = TextEditingController(text: widget.egua.rp);
    _pelagemController = TextEditingController(text: widget.egua.pelagem);
    _coberturaController = TextEditingController(text: widget.egua.cobertura);
    _obsController = TextEditingController(text: widget.egua.observacao);
    
    _categoriaSelecionada = widget.egua.categoria;
    _teveParto = widget.egua.dataParto != null;
    _dataParto = widget.egua.dataParto;
    _sexoPotro = widget.egua.sexoPotro;
  }

  @override
  void dispose() {
    _nomeController.dispose();
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
        rp: _rpController.text,
        pelagem: _pelagemController.text,
        categoria: _categoriaSelecionada,
        cobertura: _categoriaSelecionada == 'Matriz' ? _coberturaController.text : null,
        observacao: _obsController.text,
        dataParto: _teveParto ? _dataParto : null,
        sexoPotro: _teveParto ? _sexoPotro : null,
        statusSync: 'pending_update',
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
                      "Editar Égua",
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outlined, color: Colors.red[700]),
                      onPressed: () => Navigator.of(context).pop('wants_to_delete')
                    ),
                  ],
                ),

              const SizedBox(height: 10),
              TextFormField(controller: _nomeController,
              decoration: const InputDecoration(
                labelText: "Nome da Égua",
                prefixIcon: Icon(Icons.female_outlined)),
              validator: (v) => v!.isEmpty ? "Obrigatório" : null),
              const SizedBox(height: 10),
              TextFormField(controller: _rpController,
              decoration: const InputDecoration(
                labelText: "RP",
                prefixIcon: Icon(Icons.numbers_outlined)
                )),
              const SizedBox(height: 10),
              TextFormField(controller: _pelagemController,
              decoration: const InputDecoration(
                labelText: "Pelagem",
                prefixIcon: Icon(Icons.pets)
                ), 
              validator: (v) => v!.isEmpty ? "Obrigatório" : null),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _categoriaSelecionada,
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
                    setState(() {
                      _categoriaSelecionada = value;
                    });
                  }
                },
              ),
              if (_categoriaSelecionada == 'Matriz')
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
              const Text("Parto?", style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(child: RadioListTile<bool>(title: const Text("Sim"), value: true, groupValue: _teveParto, onChanged: (val) => setState(() => _teveParto = val!))),
                  Expanded(child: RadioListTile<bool>(title: const Text("Não"), value: false, groupValue: _teveParto, onChanged: (val) => setState(() => _teveParto = val!))),
                ],
              ),
              if (_teveParto)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.lightGrey.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        readOnly: true,
                        controller: TextEditingController(
                          text: _dataParto == null ? '' : DateFormat('dd/MM/yyyy').format(_dataParto!),
                        ),
                        decoration: const InputDecoration(
                          labelText: "Data do Parto",
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          hintText: 'Selecione a data',
                        ),
                        onTap: () async {
                          final pickedDate = await showDatePicker(context: context, initialDate: _dataParto ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now());
                          if (pickedDate != null) {
                            setState(() => _dataParto = pickedDate);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text("Sexo do Potro", style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(child: RadioListTile<String>(title: const Text("Macho"), value: "Macho", groupValue: _sexoPotro, onChanged: (val) => setState(() => _sexoPotro = val))),
                          Expanded(child: RadioListTile<String>(title: const Text("Fêmea"), value: "Fêmea", groupValue: _sexoPotro, onChanged: (val) => setState(() => _sexoPotro = val))),
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
                  prefixIcon: Icon(Icons.comment_outlined)), maxLines: 3),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
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
