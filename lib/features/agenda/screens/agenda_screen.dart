import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_time_picker_spinner/flutter_time_picker_spinner.dart';
import 'package:flutter/rendering.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nobryo_final/core/database/sqlite_helper.dart';
import 'package:nobryo_final/core/models/egua_model.dart';
import 'package:nobryo_final/core/models/manejo_model.dart';
import 'package:nobryo_final/core/models/propriedade_model.dart';
import 'package:nobryo_final/core/models/medicamento_model.dart';
import 'package:nobryo_final/core/models/user_model.dart';
import 'package:nobryo_final/core/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'package:nobryo_final/features/auth/screens/manage_users_screen.dart';
import 'package:nobryo_final/core/services/auth_service.dart';
import 'package:nobryo_final/features/auth/widgets/user_profile_modal.dart';
import 'package:nobryo_final/features/eguas/screens/egua_details_screen.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:nobryo_final/shared/widgets/loading_screen.dart';
import 'package:uuid/uuid.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> with TickerProviderStateMixin {
  DateTime? _selectedDate;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isFabVisible = true;
  bool _isTodayFilterActive = true;
  bool _myTasksFilterActive = true;

  List<Manejo> _allManejos = [];
  Map<String, Propriedade> _allPropriedades = {};
  Map<String, Egua> _allEguas = {};
  Map<String, AppUser> _allUsers = {};

  final SyncService _syncService = SyncService();
  final AuthService _authService = AuthService();
  StreamSubscription? _manejosSubscription;

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _refreshAgenda();
    _searchController.addListener(() => setState(() {}));
    _setupFirebaseListener();
    Provider.of<SyncService>(context, listen: false).addListener(_refreshAgenda);

   _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isFabVisible) {
          setState(() {
            _isFabVisible = false;
            _animationController.reverse();
          });
        }
      } else {
        if (!_isFabVisible) {
          setState(() {
            _isFabVisible = true;
            _animationController.forward();
          });
        }
      }
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _animationController.value = 1.0;
  }


  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _manejosSubscription?.cancel();
    _animationController.dispose();
    Provider.of<SyncService>(context, listen: false).removeListener(_refreshAgenda);
    super.dispose();
  }

  Future<void> _refreshAgenda() async {
    final results = await Future.wait([
      SQLiteHelper.instance.readAllManejos(),
      SQLiteHelper.instance.readAllPropriedades(),
      SQLiteHelper.instance.getAllEguas(),
      SQLiteHelper.instance.getAllUsers(),
    ]);

    if (mounted) {
      setState(() {
        _allManejos = results[0] as List<Manejo>;
        final propriedades = results[1] as List<Propriedade>;
        final eguas = results[2] as List<Egua>;
        final users = results[3] as List<AppUser>;

        _allPropriedades = {for (var p in propriedades) p.id: p};
        _allEguas = {for (var e in eguas) e.id: e};
        _allUsers = {for (var u in users) u.uid: u};
      });
    }
  }

  Future<void> _autoSync() async {
    final bool _ = await _syncService.syncData(isManual: false);
    if (mounted) {}
    await _refreshAgenda();
  }

  Future<void> _manualSync() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const LoadingScreen(),
    );

    final bool online = await _syncService.syncData(isManual: true);
    
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            online ? "Sincronização concluída!" : "Sem conexão com a internet."),
        backgroundColor: online ? Colors.green : Colors.orange,
      ));
    }
    _refreshAgenda();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    final userName =
        _authService.currentUserNotifier.value?.nome.split(' ').first ?? '';
    if (hour < 12) {
      return "Bom dia, $userName";
    } else if (hour < 18) {
      return "Boa tarde, $userName";
    } else {
      return "Boa noite, $userName";
    }
  }

  List<Manejo> _getFilteredManejos() {
    List<Manejo> result = _allManejos;
    final searchText = _searchController.text.toLowerCase();
    final currentUserId = _authService.currentUserNotifier.value?.uid;

    if (_myTasksFilterActive) {
      result = result.where((m) => m.responsavelId == currentUserId).toList();
    }
    
    if (_isTodayFilterActive) {
      result = result
          .where((m) => DateUtils.isSameDay(m.dataAgendada, DateTime.now()))
          .toList();
    } else if (_selectedDate != null) {
      result = result
          .where((m) => DateUtils.isSameDay(m.dataAgendada, _selectedDate))
          .toList();
    }

    if (searchText.isNotEmpty) {
      result = result.where((manejo) {
        final propNome =
            _allPropriedades[manejo.propriedadeId]?.nome.toLowerCase() ?? '';
        final eguaNome = _allEguas[manejo.eguaId]?.nome.toLowerCase() ?? '';
        return propNome.contains(searchText) || eguaNome.contains(searchText);
      }).toList();
    }

    result.sort((a, b) {
      final dateComparison = a.dataAgendada.compareTo(b.dataAgendada);
      if (dateComparison != 0) return dateComparison;

      if (currentUserId != null) {
        final isAMine = a.responsavelId == currentUserId;
        final isBMine = b.responsavelId == currentUserId;
        if (isAMine && !isBMine) return -1;
        if (!isAMine && isBMine) return 1;
      }
      return 0;
    });

    return result;
  }

  Color _getManejoColor(String tipo) {
    String tipoLower = tipo.toLowerCase();
    if (tipoLower.contains('diagnóstico')) return AppTheme.statusDiagnostico;
    if (tipoLower.contains('inseminação')) return AppTheme.statusPrenhe;
    if (tipoLower.contains('lavado')) return Colors.teal;
    if (tipoLower.contains('controle folicular')) return Colors.purple;
    if (tipoLower.contains('transferência')) return Colors.orange;
    if (tipoLower.contains('coleta')) return Colors.blueGrey;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final username = _authService.currentUserNotifier.value?.username;
    final bool isAdmin = username == 'admin' || username == 'Bruna';
    final currentUser = _authService.currentUserNotifier.value;
    final filteredManejos = _getFilteredManejos();
    final manejosByData =
        groupBy(filteredManejos, (Manejo m) => DateUtils.dateOnly(m.dataAgendada));

    final sortedDates = manejosByData.keys.toList()
      ..sort((a, b) {
        final today = DateUtils.dateOnly(DateTime.now());
        if (DateUtils.isSameDay(a, today)) return -1;
        if (DateUtils.isSameDay(b, today)) return 1;
        return a.compareTo(b);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text("AGENDA"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: "Sincronizar Dados",
            onPressed: _manualSync,
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: "Gerenciar Usuários",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ManageUsersScreen()),
                );
              },
            ),
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: GestureDetector(
                onTap: () => showUserProfileModal(context),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.lightGrey,
                  backgroundImage: (currentUser.photoUrl != null &&
                          currentUser.photoUrl!.isNotEmpty)
                      ? FileImage(File(currentUser.photoUrl!)) as ImageProvider
                      : null,
                  child: (currentUser.photoUrl == null ||
                          currentUser.photoUrl!.isEmpty)
                      ? const Icon(Icons.person, color: AppTheme.darkGreen)
                      : null,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAgenda,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(_getGreeting(),
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            _buildFilterBar(),
            Expanded(
              child: filteredManejos.isEmpty
                  ? const Center(child: Text("Nenhum agendamento encontrado."))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: sortedDates.length,
                      itemBuilder: (context, index) {
                        final date = sortedDates[index];
                        final manejosDoDia = manejosByData[date]!;
                        return _buildDayGroup(date, manejosDoDia);
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _animation,
        child: FadeTransition(
          opacity: _animation,
          child: FloatingActionButton(onPressed: () => _showAddAgendamentoModal(context),
          child: const Icon(Icons.add),
          ),
        )
      ),
    );
  }

  Widget _buildFilterBar() {
    final availableDates = _allManejos
        .map((m) => DateUtils.dateOnly(m.dataAgendada))
        .toSet()
        .toList();
    availableDates.sort((a, b) => a.compareTo(b));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
                hintText: 'Buscar por nome da égua ou propriedade'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilterChip(
                label: const Text("Hoje"),
                selected: _isTodayFilterActive,
                onSelected: (selected) {
                  setState(() {
                    _isTodayFilterActive = selected;
                    if (selected) {
                      _selectedDate = null;
                    }
                  });
                },
                selectedColor: AppTheme.brown.withOpacity(0.3),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text("Minhas tarefas"),
                selected: _myTasksFilterActive,
                onSelected: (selected) {
                  setState(() {
                    _myTasksFilterActive = selected;
                  });
                },
                selectedColor: AppTheme.brown.withOpacity(0.3),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DateTime>(
                  value: _selectedDate,
                  hint: const Text("Data", style: TextStyle(fontSize: 14)),
                  isExpanded: true,
                  decoration: InputDecoration(
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      suffixIcon: _selectedDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () => setState(() {
                                    _selectedDate = null;
                                  }))
                          : null),
                  items: availableDates
                      .map((date) => DropdownMenuItem(
                            value: date,
                            child: Tooltip(
                              message: DateFormat("dd/MM/yyyy - EEEE", 'pt_BR')
                                  .format(date),
                              child: Text(
                                DateFormat("dd/MM/yyyy", 'pt_BR').format(date),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: (date) => setState(() {
                    _selectedDate = date;
                    if (date != null) _isTodayFilterActive = false;
                  }),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
  
  Widget _buildDayGroup(DateTime day, List<Manejo> manejos) {
    final bool isToday = DateUtils.isSameDay(day, DateTime.now());
    String title = DateFormat("EEEE, dd 'de' MMMM", 'pt_BR').format(day).toUpperCase();
    if (isToday) title = "HOJE, ${DateFormat("dd 'de' MMMM", 'pt_BR').format(day).toUpperCase()}";

    final currentUserId = _authService.currentUserNotifier.value?.uid;
    final meusManejos = manejos.where((m) => m.responsavelId == currentUserId).toList();
    final outrosManejos = manejos.where((m) => m.responsavelId != currentUserId).toList();

    final manejosPorPropriedadeMeus = groupBy(meusManejos, (m) => m.propriedadeId);
    final manejosPorPropriedadeOutros = groupBy(outrosManejos, (m) => m.propriedadeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
          child: Text(
            title,
            style: TextStyle(
                color: isToday ? AppTheme.darkText : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 14),
          ),
        ),
        
        if (meusManejos.isNotEmpty && !_myTasksFilterActive) ...[
           const Padding(
            padding: EdgeInsets.only(top: 8.0, bottom: 4.0),
            child: Text(
              "MEUS AGENDAMENTOS",
              style: TextStyle(color: AppTheme.darkGreen, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          ...manejosPorPropriedadeMeus.entries.map((entry) {
            final propriedade = _allPropriedades[entry.key];
            return _buildPropriedadeGroup(propriedade, entry.value);
          }).toList(),
        ],

        if(meusManejos.isNotEmpty && _myTasksFilterActive)
         ...manejosPorPropriedadeMeus.entries.map((entry) {
            final propriedade = _allPropriedades[entry.key];
            return _buildPropriedadeGroup(propriedade, entry.value);
          }).toList(),

        if (meusManejos.isNotEmpty && outrosManejos.isNotEmpty && !_myTasksFilterActive) ...[
          const Divider(height: 20),
          const Padding(
            padding: EdgeInsets.only(top: 4.0, bottom: 4.0),
            child: Text(
              "OUTROS AGENDAMENTOS",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],

        if (outrosManejos.isNotEmpty && !_myTasksFilterActive)
         ...manejosPorPropriedadeOutros.entries.map((entry) {
            final propriedade = _allPropriedades[entry.key];
            return _buildPropriedadeGroup(propriedade, entry.value);
          }).toList(),
      ],
    );
  }

  Widget _buildPropriedadeGroup(Propriedade? propriedade, List<Manejo> manejos) {
    if (propriedade == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: Text(propriedade.nome.toUpperCase(),
              style: const TextStyle(
                  color: AppTheme.brown,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ),
        ...manejos
            .map((manejo) => _buildAgendaCard(manejo, _allEguas[manejo.eguaId]))
            .toList(),
      ],
    );
  }

  Widget _buildAgendaCard(Manejo manejo, Egua? egua) {
    final styleColor = _getManejoColor(manejo.tipo);
    final responsavelNome = _allUsers[manejo.responsavelId]?.nome ?? '...';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showConfirmationModal(context, manejo, egua),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: styleColor,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(manejo.tipo.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Text(egua?.nome ?? "Égua não encontrada",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (egua != null)
                Text("RP: ${egua.rp}",
                    style: TextStyle(color: Colors.grey[700], fontSize: 14)),
              const SizedBox(height: 8),
              Text("Responsável: $responsavelNome",
                  style: TextStyle(color: Colors.grey[700], fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  void _setupFirebaseListener() {
    final collectionRef = FirebaseFirestore.instance.collection('manejos');
    _manejosSubscription = collectionRef.snapshots().listen(
    (querySnapshot) {
      if (querySnapshot.docChanges.isNotEmpty) {
       print(">> Detecção de mudança no Firebase! Iniciando _autoSync()...");
       _autoSync();
      }
    },
    
    onError: (error) {
      print("Erro ao ouvir as atualizações do Firebase: $error");
      },
    );
  }

  void _showAddAgendamentoModal(BuildContext context) async {
    final currentUser = _authService.currentUserNotifier.value;
    if (currentUser == null) return;

    final formKey = GlobalKey<FormState>();

    final TextEditingController propSearchController = TextEditingController();
    Propriedade? propriedadeSelecionada;
    List<Propriedade> _allPropsWithEguas = [];
    List<Propriedade> _filteredProps = [];
    bool _showPropList = false;

    Egua? eguaSelecionada;
    DateTime? dataSelecionada;
    String? tipoManejoSelecionado;
    final detalhesController = TextEditingController();
    final tiposDeManejo = [
      "Controle Folicular", "Inseminação", "Lavado", "Diagnóstico",
      "Transferência de Embrião", "Coleta de Embrião", "Outros Manejos"
    ];

    final allEguas = await SQLiteHelper.instance.getAllEguas();
    final propriedadeIdsComEguas = allEguas.map((e) => e.propriedadeId).toSet();
    _allPropsWithEguas = (await SQLiteHelper.instance.readAllPropriedades())
        .where((p) => propriedadeIdsComEguas.contains(p.id))
        .toList();
    _filteredProps = _allPropsWithEguas;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          void filterProps(String query) {
            setModalState(() {
              _filteredProps = _allPropsWithEguas
                  .where((prop) =>
                      prop.nome.toLowerCase().contains(query.toLowerCase()))
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
                    Text("Agendar Manejo",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: 30, thickness: 1),
                    TextFormField(
                      controller: propSearchController,
                      readOnly: propriedadeSelecionada != null,
                      decoration: InputDecoration(
                        labelText: "Propriedade",
                        hintText: "Busque pelo nome da propriedade",
                        prefixIcon: const Icon(Icons.home_work_outlined),
                        suffixIcon: propriedadeSelecionada != null
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setModalState(() {
                                    propriedadeSelecionada = null;
                                    propSearchController.clear();
                                    eguaSelecionada = null;
                                    _showPropList = true;
                                    _filteredProps = _allPropsWithEguas;
                                  });
                                },
                              )
                            : const Icon(Icons.search),
                      ),
                      onChanged: filterProps,
                      onTap: () => setModalState(() => _showPropList = true),
                      validator: (v) => propriedadeSelecionada == null
                          ? "Selecione uma propriedade"
                          : null,
                    ),
                    if (_showPropList && propriedadeSelecionada == null)
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: AppTheme.pageBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.lightGrey)
                        ),
                        child: ListView.builder(
                          itemCount: _filteredProps.length,
                          itemBuilder: (context, index) {
                            final prop = _filteredProps[index];
                            return ListTile(
                              title: Text(prop.nome),
                              onTap: () {
                                setModalState(() {
                                  propriedadeSelecionada = prop;
                                  propSearchController.text = prop.nome;
                                  eguaSelecionada = null;
                                  _showPropList = false;
                                  FocusScope.of(context).unfocus();
                                });
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 15),

                    if (propriedadeSelecionada != null)
                      FutureBuilder<List<Egua>>(
                        future: SQLiteHelper.instance
                            .readEguasByPropriedade(propriedadeSelecionada!.id),
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
                            hint: const Text("Selecione a Égua"),
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

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: "Data do Manejo",
                              prefixIcon: const Icon(Icons.calendar_today_outlined),
                              hintText: dataSelecionada == null
                                  ? 'Toque para selecionar'
                                  : DateFormat('dd/MM/yyyy')
                                      .format(dataSelecionada!),
                            ),
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030));
                              if (pickedDate != null) {
                                setModalState(() => dataSelecionada = pickedDate);
                              }
                            },
                            validator: (v) =>
                                dataSelecionada == null ? "Selecione a data" : null,
                            controller: TextEditingController(
                                text: dataSelecionada == null
                                    ? ''
                                    : DateFormat('dd/MM/yyyy').format(dataSelecionada!),
                              ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: tipoManejoSelecionado,
                      decoration: const InputDecoration(
                        labelText: "Tipo de Manejo",
                        prefixIcon: Icon(Icons.edit_note_outlined),
                      ),
                      hint: const Text("Selecione o Tipo"),
                      items: tiposDeManejo
                          .map((tipo) =>
                              DropdownMenuItem(value: tipo, child: Text(tipo)))
                          .toList(),
                      onChanged: (val) =>
                          setModalState(() => tipoManejoSelecionado = val),
                      validator: (v) => v == null ? "Selecione o tipo" : null,
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                        controller: detalhesController,
                        decoration: const InputDecoration(
                            labelText: "Detalhes/Observações",
                            prefixIcon: Icon(Icons.comment_outlined)),
                        maxLines: 2),
                    const SizedBox(height: 30),

                    // --- Botão de Agendar ---
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text("AGENDAR"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.darkGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final novoManejo = Manejo(
                              id: const Uuid().v4(),
                              tipo: tipoManejoSelecionado!,
                              dataAgendada: dataSelecionada!,
                              detalhes: {'descricao': detalhesController.text},
                              eguaId: eguaSelecionada!.id,
                              propriedadeId: propriedadeSelecionada!.id,
                              responsavelId: currentUser.uid,
                            );
                            await SQLiteHelper.instance
                                .createManejo(novoManejo);
                            if (mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text("Manejo agendado com sucesso!"),
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

  void _showConfirmationModal(BuildContext context, Manejo manejo, Egua? egua) {
    final responsavelNome = _allUsers[manejo.responsavelId]?.nome ?? 'Desconhecido';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
               if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Data do manejo reagendada!"),
                    backgroundColor: Colors.green));
              }
              _autoSync();
            }
          }

          void deletarLocal() async {
            Navigator.of(ctx).pop();
            showDialog(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                title: const Text("Excluir Agendamento"),
                content: Text(
                    "Tem certeza que deseja excluir o manejo de '${manejo.tipo}' para a égua ${egua?.nome ?? 'desconhecida'}? Esta ação não pode ser desfeita."),
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
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text("Agendamento excluído."),
                              backgroundColor: Colors.red[700]));
                          _autoSync();
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
                                _showEditObservacaoModal(context, manejo);
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
                                    leading: Icon(Icons.edit_note_outlined),
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
                  Text("Tipo: ${manejo.tipo}",
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color.fromARGB(255, 110, 110, 110))),
                  const Divider(height: 30),
                  
                  _buildDetailRow(
                      Icons.calendar_today_outlined,
                      "Data Agendada",
                      DateFormat('EEEE, dd/MM/yyyy', 'pt_BR')
                          .format(manejo.dataAgendada)),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                      Icons.home_work_outlined, "Propriedade", _allPropriedades[manejo.propriedadeId]?.nome ?? '...'),
                  const SizedBox(height: 16),
                   Row(
                     children: [
                       Expanded(
                         child: _buildDetailRow(
                            Icons.female_outlined, "Égua", egua?.nome ?? '...'),
                       ),
                       if(egua != null)
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, color: AppTheme.darkGreen),
                          tooltip: "Ver detalhes da égua",
                          onPressed: (){
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EguaDetailsScreen(egua: egua),
                                ),
                              );
                          },
                        )
                     ],
                   ),
                  const SizedBox(height: 16),
                  _buildDetailRow(Icons.person_outline, "Responsável", responsavelNome),
                  const SizedBox(height: 16),
                  _buildDetailRow(Icons.comment_outlined, "Observação Inicial", textoObservacao),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text("CONCLUIR MANEJO"),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showMarkAsCompleteModal(context, manejo, egua);
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppTheme.darkGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)
                            )
                          ),
                    ),
                  )
                ],
              ),
            ),
          );
      },
    );
  }

  void _showEditObservacaoModal(BuildContext mainContext, Manejo manejo) {
    final formKey = GlobalKey<FormState>();
    final obsController =
        TextEditingController(text: manejo.detalhes['descricao'] ?? '');

    // Fecha o modal de confirmação antes de abrir o de edição
    Navigator.of(mainContext).pop(); 

    showModalBottomSheet(
      context: mainContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text("Observação atualizada!"),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _autoSync();
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

  void _showMarkAsCompleteModal(BuildContext context, Manejo manejo, Egua? egua) async {
    final currentUser = _authService.currentUserNotifier.value;
    if (currentUser == null) return;

    final formKey = GlobalKey<FormState>();
    final obsController = TextEditingController(text: manejo.detalhes['observacao']);

    final garanhaoController = TextEditingController(text: egua?.cobertura);
    DateTime? dataHoraInseminacao;
    final litrosController = TextEditingController();
    String? ovarioDirOp;
    String? ovarioEsqOp;
    final ovarioDirTamanhoController = TextEditingController();
    final ovarioEsqTamanhoController = TextEditingController();
    String? edemaSelecionado;
    final uteroController = TextEditingController();
    String? resultadoDiagnostico;
    final diasPrenheController = TextEditingController();
    String? idadeEmbriaoSelecionada;
    
    // --- Variáveis para seleção da Doadora ---
    Propriedade? propDoadoraSelecionada;
    Egua? doadoraSelecionada;
    final propDoadoraSearchController = TextEditingController();
    final allEguas = await SQLiteHelper.instance.getAllEguas();
    final propIdsComEguas = allEguas.map((e) => e.propriedadeId).toSet();
    List<Propriedade> _allPropsDoadora = (await SQLiteHelper.instance.readAllPropriedades())
        .where((p) => propIdsComEguas.contains(p.id))
        .toList();
    List<Propriedade> _filteredPropsDoadora = _allPropsDoadora;
    bool _showPropDoadoraList = false;
    // --- Fim das variáveis da Doadora ---

    final avaliacaoUterinaController = TextEditingController();
    Medicamento? medicamentoSelecionado;
    String? inducaoSelecionada;
    DateTime? dataHoraInducao;
    final medicamentoSearchController = TextEditingController();
    List<Medicamento> _filteredMedicamentos = [];
    bool _showMedicamentoList = false;
    final todosMedicamentos = await SQLiteHelper.instance.readAllMedicamentos();
    _filteredMedicamentos = todosMedicamentos;
    DateTime dataFinalManejo = manejo.dataAgendada;
    final List<AppUser> allUsersList = await SQLiteHelper.instance.getAllUsers();
    AppUser? concluidoPorSelecionado = allUsersList.firstWhere(
        (u) => u.uid == currentUser.uid,
        orElse: () => allUsersList.first);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
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

          void filterPropsDoadora(String query) {
            setModalState(() {
              _filteredPropsDoadora = _allPropsDoadora
                  .where((prop) =>
                      prop.nome.toLowerCase().contains(query.toLowerCase()))
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
                    if (egua != null)
                      Text("Égua: ${egua.nome}",
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
                    if (manejo.tipo != 'Outros Manejos')
                      const Divider(height: 30, thickness: 1),

                    ..._buildSpecificForm(
                      context: context,
                      tipo: manejo.tipo,
                      setModalState: setModalState,
                      onDataHoraInseminacaoChange: (val) => setModalState(() => dataHoraInseminacao = val),
                      onMedicamentoChange: (val) => setModalState(() => medicamentoSelecionado = val),
                      onOvarioDirChange: (val) => setModalState(() => ovarioDirOp = val),
                      onOvarioEsqChange: (val) => setModalState(() => ovarioEsqOp = val),
                      onEdemaChange: (val) => setModalState(() => edemaSelecionado = val),
                      onIdadeEmbriaoChange: (val) => setModalState(() => idadeEmbriaoSelecionada = val),
                      onDoadoraChange: (val) => setModalState(() => doadoraSelecionada = val),
                      onResultadoChange: (val) => setModalState(() => resultadoDiagnostico = val),
                      garanhaoController: garanhaoController,
                      dataHoraInseminacao: dataHoraInseminacao,
                      litrosController: litrosController,
                      medicamentoSelecionado: medicamentoSelecionado,
                      allMeds: todosMedicamentos,
                      ovarioDirOp: ovarioDirOp,
                      ovarioEsqOp: ovarioEsqOp,
                      ovarioDirTamanhoController: ovarioDirTamanhoController,
                      ovarioEsqTamanhoController: ovarioEsqTamanhoController,
                      edemaSelecionado: edemaSelecionado,
                      uteroController: uteroController,
                      idadeEmbriao: idadeEmbriaoSelecionada,
                      doadoraSelecionada: doadoraSelecionada,
                      avaliacaoUterinaController: avaliacaoUterinaController,
                      resultadoDiagnostico: resultadoDiagnostico,
                      diasPrenheController: diasPrenheController,
                      propDoadoraSelecionada: propDoadoraSelecionada,
                      propDoadoraSearchController: propDoadoraSearchController,
                      filteredPropsDoadora: _filteredPropsDoadora,
                      showPropDoadoraList: _showPropDoadoraList,
                      onPropDoadoraChange: (val) => setModalState(() => propDoadoraSelecionada = val),
                      onFilterPropsDoadora: filterPropsDoadora,
                      onShowPropDoadoraListChange: (val) => setModalState(() => _showPropDoadoraList = val),
                      allPropsDoadora: _allPropsDoadora
                    ),
                    
                    const SizedBox(height: 15),

                    if (manejo.tipo == 'Controle Folicular') ...[
                      const Divider(height: 20, thickness: 1),
                      Text("Indução", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: medicamentoSearchController,
                        readOnly: medicamentoSelecionado != null,
                        decoration: InputDecoration(
                          labelText: "Medicamento para Indução",
                          prefixIcon: const Icon(Icons.vaccines_outlined),
                          suffixIcon: medicamentoSelecionado != null
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setModalState(() {
                                    medicamentoSelecionado = null;
                                    medicamentoSearchController.clear();
                                  });
                                },
                              )
                            : const Icon(Icons.search),
                        ),
                        onChanged: filterMedicamentos,
                        onTap: () => setModalState(() => _showMedicamentoList = true),
                      ),
                      if (_showMedicamentoList && medicamentoSelecionado == null)
                        Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300)),
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
                      const SizedBox(height: 15),

                      DropdownButtonFormField<String>(
                        value: inducaoSelecionada,
                        decoration: const InputDecoration(labelText: "Tipo de Indução", prefixIcon: Icon(Icons.healing_outlined)),
                        items: ["HCG", "DESLO", "HCG+DESLO"]
                            .map((label) => DropdownMenuItem(child: Text(label), value: label))
                            .toList(),
                        onChanged: (value) => setModalState(() => inducaoSelecionada = value),
                      ),
                      const SizedBox(height: 15),

                      TextFormField(
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: "Data e Hora da Indução",
                          prefixIcon: const Icon(Icons.schedule_outlined),
                          hintText: dataHoraInducao == null ? 'Toque para selecionar' : DateFormat('dd/MM/yyyy HH:mm').format(dataHoraInducao!),
                        ),
                        onTap: () async {
                          final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                          if (date == null) return;
                          final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                          if (time == null) return;
                          setModalState(() {
                            dataHoraInducao = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                          });
                          // ignore: unused_label
                          validator: (v) {
                          if (inducaoSelecionada != null && dataHoraInducao == null) {
                            return "Campo obrigatório";
                          }
                          return null;
                          };
                        },
                      ),
                    ],

                    if (manejo.tipo != 'Outros Manejos')
                      const Divider(height: 30, thickness: 1),

                    Text("Finalização", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),

                    DropdownButtonFormField<AppUser>(
                      value: concluidoPorSelecionado,
                      decoration: const InputDecoration(labelText: "Concluído por", prefixIcon: Icon(Icons.person_outline)),
                      items: allUsersList
                          .map((user) => DropdownMenuItem(
                              value: user, child: Text(user.nome)))
                          .toList(),
                      onChanged: (user) => setModalState(() => concluidoPorSelecionado = user),
                      validator: (v) => v == null ? "Selecione um responsável" : null,
                    ),
                    const SizedBox(height: 15),

                     TextFormField(
                      readOnly: true,
                      decoration: InputDecoration(
                          labelText: "Data da Conclusão",
                          prefixIcon: const Icon(Icons.event_available_outlined),
                          hintText: DateFormat('dd/MM/yyyy').format(dataFinalManejo)),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: dataFinalManejo,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030));
                        if (pickedDate != null) {
                          setModalState(() => dataFinalManejo = pickedDate);
                        }
                      },
                        controller: TextEditingController(text: DateFormat('dd/MM/yyyy').format(dataFinalManejo)),
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                        controller: obsController,
                        decoration: const InputDecoration(
                            labelText: "Observações Finais", prefixIcon: Icon(Icons.comment_outlined)),
                        maxLines: 3),
                    
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text("SALVAR CONCLUSÃO"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.darkGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))
                        ),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final Map<String, dynamic> detalhes = manejo.detalhes;
                            detalhes['observacao'] = obsController.text;

                            if (manejo.tipo == 'Controle Folicular') {
                               manejo.medicamentoId = medicamentoSelecionado?.id;
                               manejo.inducao = inducaoSelecionada;
                               manejo.dataHoraInducao = dataHoraInducao;
                            }
                            
                            if (manejo.tipo == 'Diagnóstico') {
                              detalhes['resultado'] = resultadoDiagnostico;
                            if (resultadoDiagnostico == 'Prenhe') {
                              final dias = int.tryParse(diasPrenheController.text) ?? 0;
                              detalhes['diasPrenhe'] = dias;
                              if (egua != null) {
                                final eguaAtualizada = egua.copyWith(
                                  statusReprodutivo: 'Prenhe',
                                  diasPrenhe: dias,
                                  cobertura: garanhaoController.text,
                                  statusSync: 'pending_update'
                                );
                                await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                              }
                            } else if (egua != null) {
                              final eguaAtualizada = egua.copyWith(
                                  statusReprodutivo: 'Vazia',
                                  diasPrenhe: 0,
                                  statusSync: 'pending_update'
                                );
                              await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                            }
                            } else if (manejo.tipo == 'Inseminação') {
                              detalhes['garanhao'] = garanhaoController.text;
                              detalhes['dataHora'] = dataHoraInseminacao?.toIso8601String();
                            } else if (manejo.tipo == 'Lavado') {
                              detalhes['litros'] = litrosController.text;
                              detalhes['medicamento'] = medicamentoSelecionado?.nome;
                            } else if (manejo.tipo == 'Controle Folicular') {
                              detalhes['ovarioDireito'] = ovarioDirOp;
                              detalhes['ovarioDireitoTamanho'] = ovarioDirTamanhoController.text;
                              detalhes['ovarioEsquerdo'] = ovarioEsqOp;
                              detalhes['ovarioEsquerdoTamanho'] = ovarioEsqTamanhoController.text;
                              detalhes['edema'] = edemaSelecionado;
                              detalhes['utero'] = uteroController.text;
                            } else if (manejo.tipo == 'Coleta de Embrião') {
                              detalhes['idadeEmbriao'] = idadeEmbriaoSelecionada;
                            } else if (manejo.tipo == 'Transferência de Embrião') {
                              detalhes['doadoraId'] = doadoraSelecionada?.id;
                              detalhes['doadoraNome'] = doadoraSelecionada?.nome;
                              detalhes['doadoraPropriedadeId'] = propDoadoraSelecionada?.id;
                              detalhes['idadeEmbriao'] = idadeEmbriaoSelecionada;
                              detalhes['avaliacaoUterina'] = avaliacaoUterinaController.text;
                            }

                            manejo.status = 'Concluído';
                            manejo.statusSync = 'pending_update';
                            manejo.detalhes = detalhes;
                            manejo.dataAgendada = dataFinalManejo;
                            manejo.concluidoPorId = concluidoPorSelecionado?.uid;

                            await SQLiteHelper.instance.updateManejo(manejo);

                            if (mounted) {
                              _autoSync();
                              Navigator.of(ctx).pop();
                              if (egua != null) {
                                Navigator.push( // Usando push em vez de pushReplacement
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EguaDetailsScreen(egua: egua),
                                  ),
                                );
                              }
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

  List<Widget> _buildSpecificForm({
    required BuildContext context,
    required String tipo,
    required StateSetter setModalState,
    required TextEditingController garanhaoController,
    required DateTime? dataHoraInseminacao,
    required Function(DateTime?) onDataHoraInseminacaoChange,
    required TextEditingController litrosController,
    required Medicamento? medicamentoSelecionado,
    required List<Medicamento> allMeds,
    required Function(Medicamento?) onMedicamentoChange,
    required String? ovarioDirOp,
    required String? ovarioEsqOp,
    required TextEditingController ovarioDirTamanhoController,
    required TextEditingController ovarioEsqTamanhoController,
    required Function(String?) onOvarioDirChange,
    required Function(String?) onOvarioEsqChange,
    required String? edemaSelecionado,
    required TextEditingController uteroController,
    required Function(String?) onEdemaChange,
    required String? idadeEmbriao,
    required Egua? doadoraSelecionada,
    required TextEditingController avaliacaoUterinaController,
    required Function(String?) onIdadeEmbriaoChange,
    required Function(Egua?) onDoadoraChange,
    required String? resultadoDiagnostico,
    required TextEditingController diasPrenheController,
    required Function(String?) onResultadoChange,
    required Propriedade? propDoadoraSelecionada,
    required TextEditingController propDoadoraSearchController,
    required Function(Propriedade?) onPropDoadoraChange,
    required List<Propriedade> filteredPropsDoadora,
    required bool showPropDoadoraList,
    required Function(String) onFilterPropsDoadora,
    required Function(bool) onShowPropDoadoraListChange,
    required List<Propriedade> allPropsDoadora,
  }) {
    final ovarioOptions = ["CL", "OV", "PEQ", "FL"];
    final idadeEmbriaoOptions = ['D6', 'D7', 'D8', 'D9', 'D10', 'D11'];
    switch (tipo) {
    case "Diagnóstico":
      return [
        DropdownButtonFormField<String>(
          value: resultadoDiagnostico,
          hint: const Text("Resultado do Diagnóstico"),
          items: ["Indeterminado", "Prenhe", "Vazia"]
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
            decoration: const InputDecoration(labelText: "Cobertura"),
            validator: (v) => v!.isEmpty ? "Informe a cobertura" : null,
          ),
        ]
      ];
      case "Inseminação":
        return [
          TextFormField(
              controller: garanhaoController,
              decoration: const InputDecoration(labelText: "Garanhão", prefixIcon: Icon(Icons.male_outlined))),
          const SizedBox(height: 15),
          TextFormField(
            readOnly: true,
            decoration: InputDecoration(
                labelText: "Data/Hora da Inseminação",
                prefixIcon: const Icon(Icons.schedule_outlined),
                hintText: dataHoraInseminacao == null
                    ? 'Toque para selecionar'
                    : DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                        .format(dataHoraInseminacao)),
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
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                        TextButton(
                          child: Text("OK"),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    );
                  },
                );
              if (time == null) return;
              onDataHoraInseminacaoChange(DateTime(
                  date.year, date.month, date.day, time!.hour, time!.minute));
            },
          ),
        ];
      case "Lavado":
        return [
          TextFormField(
              controller: litrosController,
              decoration: const InputDecoration(labelText: "Litros", prefixIcon: Icon(Icons.water_drop_outlined)),
              keyboardType: TextInputType.number),
          const SizedBox(height: 15),
          DropdownButtonFormField<Medicamento>(
            value: medicamentoSelecionado,
            decoration: const InputDecoration(labelText: "Medicamento", prefixIcon: Icon(Icons.vaccines_outlined)),
            items: allMeds
                .map((m) => DropdownMenuItem(value: m, child: Text(m.nome)))
                .toList(),
            onChanged: (val) => setModalState(() => onMedicamentoChange(val)),
          )
        ];
      case "Controle Folicular":
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: ovarioDirOp,
                  decoration: const InputDecoration(labelText: "Ovário Direito"),
                  items: ovarioOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                  onChanged: (val) => setModalState(() => onOvarioDirChange(val)),
                ),
              ),
              if (ovarioDirOp == 'FL') ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: ovarioDirTamanhoController,
                    decoration: const InputDecoration(labelText: "Tamanho", suffixText: "mm"),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ]
            ],
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: ovarioEsqOp,
                  decoration: const InputDecoration(labelText: "Ovário Esquerdo"),
                  items: ovarioOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                  onChanged: (val) => setModalState(() => onOvarioEsqChange(val)),
                ),
              ),
              if (ovarioEsqOp == 'FL') ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: ovarioEsqTamanhoController,
                    decoration: const InputDecoration(labelText: "Tamanho", suffixText: "mm"),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ]
            ],
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: edemaSelecionado,
            decoration: const InputDecoration(labelText: "Edema"),
            items: ['1', '1-2', '2', '2-3', '3', '3-4', '4', '4-5', '5']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) => setModalState(() => onEdemaChange(val)),
          ),
          const SizedBox(height: 15),
          TextFormField(
              controller: uteroController,
              decoration: const InputDecoration(labelText: "Útero")),
        ];
      case "Transferência de Embrião":
        return [
          Text("Dados da Doadora", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextFormField(
            controller: propDoadoraSearchController,
            readOnly: propDoadoraSelecionada != null,
            decoration: InputDecoration(
              labelText: "Propriedade da Doadora",
              prefixIcon: const Icon(Icons.home_work_outlined),
              suffixIcon: propDoadoraSelecionada != null
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setModalState(() {
                        onPropDoadoraChange(null);
                        propDoadoraSearchController.clear();
                        onDoadoraChange(null);
                        onShowPropDoadoraListChange(true);
                      });
                    },
                  )
                : const Icon(Icons.search),
            ),
            onChanged: onFilterPropsDoadora,
            onTap: () => setModalState(() => onShowPropDoadoraListChange(true)),
            validator: (v) => propDoadoraSelecionada == null ? "Selecione a propriedade" : null,
          ),
          if (showPropDoadoraList && propDoadoraSelecionada == null)
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300)),
              child: ListView.builder(
                itemCount: filteredPropsDoadora.length,
                itemBuilder: (context, index) {
                  final prop = filteredPropsDoadora[index];
                  return ListTile(
                    title: Text(prop.nome),
                    onTap: () {
                      setModalState(() {
                        onPropDoadoraChange(prop);
                        propDoadoraSearchController.text = prop.nome;
                        onDoadoraChange(null);
                        onShowPropDoadoraListChange(false);
                        FocusScope.of(context).unfocus();
                      });
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 15),
          if (propDoadoraSelecionada != null)
            FutureBuilder<List<Egua>>(
              future: SQLiteHelper.instance.readEguasByPropriedade(propDoadoraSelecionada.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                return DropdownButtonFormField<Egua>(
                  value: doadoraSelecionada,
                  decoration: const InputDecoration(labelText: "Égua Doadora", prefixIcon: Icon(Icons.female_outlined)),
                  items: snapshot.data!.map((e) => DropdownMenuItem(value: e, child: Text(e.nome))).toList(),
                  onChanged: (val) => setModalState(() => onDoadoraChange(val)),
                  validator: (v) => v == null ? "Selecione a égua doadora" : null,
                );
              },
            ),
          const SizedBox(height: 15),
          const Divider(),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: idadeEmbriao,
            decoration: const InputDecoration(labelText: "Idade do Embrião", prefixIcon: Icon(Icons.hourglass_bottom_outlined)),
            items: idadeEmbriaoOptions
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) => setModalState(() => onIdadeEmbriaoChange(val)),
          ),
          const SizedBox(height: 15),
          TextFormField(
              controller: avaliacaoUterinaController,
              decoration:
                  const InputDecoration(labelText: "Avaliação Uterina", prefixIcon: Icon(Icons.notes_outlined))),
        ];
      case "Coleta de Embrião":
        return [
          DropdownButtonFormField<String>(
            value: idadeEmbriao,
            decoration: const InputDecoration(labelText: "Idade do Embrião", prefixIcon: Icon(Icons.hourglass_bottom_outlined)),
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