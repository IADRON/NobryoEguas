import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/egua_model.dart';
import 'package:nobryo_final/core/models/manejo_model.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/services/export_service.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:nobryo_final/features/eguas/screens/egua_details_screen.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';

class EguasListScreen extends StatefulWidget {
  final String propriedadeId;
  final String propriedadeNome;

  const EguasListScreen({
    super.key,
    required this.propriedadeId,
    required this.propriedadeNome,
  });

  @override
  State<EguasListScreen> createState() => _EguasListScreenState();
}

class _EguasListScreenState extends State<EguasListScreen> {
  // State variables to hold the list of mares and loading status.
  List<Egua>? _eguas;
  bool _isLoadingEguas = true;

  final ExportService _exportService = ExportService();
  final SyncService _syncService = SyncService();
  bool _isLoading = false;

  Propriedade? _propriedade;
  late String _currentPropriedadeNome;

  @override
  void initState() {
    super.initState();
    _currentPropriedadeNome = widget.propriedadeNome;
    _loadPropriedade();
    _refreshEguasList();
    Provider.of<SyncService>(context, listen: false)
        .addListener(_refreshEguasList);
  }

  @override
  void dispose() {
    Provider.of<SyncService>(context, listen: false)
        .removeListener(_refreshEguasList);
    super.dispose();
  }

  Future<void> _loadPropriedade() async {
    final prop = await SQLiteHelper.instance.readPropriedade(widget.propriedadeId);
    if (prop != null && mounted) {
      setState(() {
        _propriedade = prop;
        _currentPropriedadeNome = prop.nome;
      });
    }
  }

  /// Calculates the current days of pregnancy for a single mare.
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

  /// Refreshes the list of mares and calculates pregnancy days for each one.
  Future<void> _refreshEguasList() async {
    if (!mounted) return;

    setState(() {
      _isLoadingEguas = true;
    });

    List<Egua> initialEguas =
        await SQLiteHelper.instance.readEguasByPropriedade(widget.propriedadeId);

    // Create a list of futures to update all mares in parallel.
    final List<Future<Egua>> updateFutures =
        initialEguas.map((egua) => _getEguaWithUpdatedDiasPrenhe(egua)).toList();

    // Wait for all calculations to complete.
    final List<Egua> updatedEguas = await Future.wait(updateFutures);

    if (mounted) {
      setState(() {
        _eguas = updatedEguas;
        _isLoadingEguas = false;
      });
    }
  }

  Future<void> _autoSync() async {
    final bool _ = await _syncService.syncData(isManual: false);
    if (mounted) {}
    _refreshEguasList();
  }

  void _exportarRelatorioCompleto(
    Future<void> Function(String, Map<Egua, List<Manejo>>, BuildContext)
        exportFunction,
  ) async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Buscando todos os dados da propriedade..."),
      backgroundColor: Colors.blue,
    ));

    try {
      final List<Egua>? eguasDaPropriedade = _eguas;

      if (eguasDaPropriedade == null || eguasDaPropriedade.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Não há éguas nesta propriedade para exportar."),
        ));
        setState(() => _isLoading = false);
        return;
      }

      final Map<Egua, List<Manejo>> dadosCompletos = {};

      for (final egua in eguasDaPropriedade) {
        final List<Manejo> historico =
            await SQLiteHelper.instance.readHistoricoByEgua(egua.id);
        dadosCompletos[egua] = historico;
      }

      if (dadosCompletos.values.every((list) => list.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Nenhum manejo encontrado para exportar nesta propriedade."),
          backgroundColor: Colors.orange,
        ));
      } else {
        await exportFunction(_currentPropriedadeNome, dadosCompletos, context);
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
                      "Editar Propriedade",
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
                      labelText: "Nome da Propriedade",
                      prefixIcon: Icon(Icons.home_work_outlined)),
                  validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: donoController,
                  decoration: const InputDecoration(
                      labelText: "Dono da Propriedade",
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

                        await SQLiteHelper.instance.updatePropriedade(updatedProp);

                        if (mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text("Propriedade atualizada com sucesso!"),
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
            'Tem certeza que deseja excluir a propriedade "${_propriedade!.nome}"? Todos os dados de éguas e manejos associados a ela serão perdidos.'),
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
      appBar: AppBar(
        backgroundColor: AppTheme.darkGreen,
        foregroundColor: AppTheme.lightGrey,
        title: Text(
          _currentPropriedadeNome.toUpperCase(),
          style: const TextStyle(fontSize: 18, color: AppTheme.lightGrey),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                  child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: AppTheme.darkText))),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _showExportOptions(context),
              tooltip: "Exportar Relatório da Propriedade",
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditPropriedadeModal(context),
            tooltip: "Editar Propriedade",
          ),
        ],
      ),
      body: _isLoadingEguas
          ? const Center(child: CircularProgressIndicator())
          : _eguas == null || _eguas!.isEmpty
              ? const Center(
                  child: Text(
                    "Nenhuma égua cadastrada.\nClique no '+' para adicionar a primeira.",
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _eguas!.length,
                  itemBuilder: (context, index) {
                    final egua = _eguas![index];
                    return _buildEguaCard(egua);
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEguaModal(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEguaCard(Egua egua) {
    final statusColor = egua.statusReprodutivo.toLowerCase() == 'prenhe'
        ? AppTheme.statusPrenhe
        : AppTheme.statusVazia;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => EguaDetailsScreen(egua: egua)),
          ).then((_) {
            _refreshEguasList();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
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
                    const SizedBox(height: 8),
                    Row(
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
                        if (egua.diasPrenhe != null && egua.diasPrenhe! > 0) ...[
                          const SizedBox(width: 8),
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
                        ]
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddEguaModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController();
    final rpController = TextEditingController();
    final pelagemController = TextEditingController();
    final coberturaController = TextEditingController();
    final obsController = TextEditingController();

    bool teveParto = false;
    DateTime? dataParto;
    String? sexoPotro;

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
                    Text("Adicionar Égua",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: 30, thickness: 1),
                    const SizedBox(height: 20),
                      TextFormField(
                          controller: nomeController,
                          decoration:
                              const InputDecoration(
                                labelText: "Nome da Égua",
                                prefixIcon: Icon(Icons.female_outlined)),
                          validator: (v) => v!.isEmpty ? "Obrigatório" : null),
                      const SizedBox(height: 10),
                      TextFormField(
                          controller: rpController,
                          decoration:
                              const InputDecoration(
                                labelText: "RP",
                                prefixIcon: Icon(Icons.numbers_outlined))
                        ),
                      const SizedBox(height: 10),
                      TextFormField(
                          controller: pelagemController,
                          decoration: const InputDecoration(
                            labelText: "Pelagem",
                            prefixIcon: Icon(Icons.pets_outlined)),
                          validator: (v) => v!.isEmpty ? "Obrigatório" : null),
                      const SizedBox(height: 10),
                      TextFormField(controller: coberturaController,
                        decoration: const InputDecoration(
                          labelText: "Cobertura",
                          prefixIcon: Icon(Icons.male),
                        ),
                        validator: (value) {
                          if (teveParto && (value == null || value.isEmpty)) {
                            return "Cobertura é obrigatória se houve parto";
                          }
                          return null;
                        },
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
                                decoration: InputDecoration(
                                  labelText: "Data do Parto",
                                  prefixIcon: Icon(Icons.calendar_today_outlined),
                                  hintText: dataParto == null
                                      ? 'Selecione a data'
                                      : DateFormat('dd/MM/yyyy')
                                          .format(dataParto!),
                                ),
                                onTap: () async {
                                  final pickedDate = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now());
                                  if (pickedDate != null) {
                                    setModalState(() => dataParto = pickedDate);
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
                          decoration:
                              const InputDecoration(
                                labelText: "Observação",
                                prefixIcon: Icon(Icons.comment_outlined)),
                          maxLines: 3),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkGreen),
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              final novaEgua = Egua(
                                id: const Uuid().v4(),
                                nome: nomeController.text,
                                rp: rpController.text,
                                pelagem: pelagemController.text,
                                cobertura: coberturaController.text,
                                dataParto: teveParto ? dataParto : null,
                                sexoPotro: teveParto ? sexoPotro : null,
                                observacao: obsController.text,
                                statusReprodutivo: 'Vazia',
                                propriedadeId: widget.propriedadeId,
                              );
                              await SQLiteHelper.instance.createEgua(novaEgua);
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
            );
          },
        );
      },
    );
  }
}
