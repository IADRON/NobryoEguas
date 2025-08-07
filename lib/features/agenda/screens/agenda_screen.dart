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
import 'package:nobryo_final/core/models/peao_model.dart';
import 'package:nobryo_final/core/models/user_model.dart';
import 'package:nobryo_final/core/services/notification_service.dart';
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
  Map<String, Peao> _allPeoes = {};

  late SyncService _syncServiceInstance;
  final AuthService _authService = AuthService();
  StreamSubscription? _manejosSubscription;

  late AnimationController _animationController;
  // ignore: unused_field
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _refreshAgenda();
    _searchController.addListener(() => setState(() {}));
    _setupFirebaseListener();
    
    _syncServiceInstance = Provider.of<SyncService>(context, listen: false);
    _syncServiceInstance.addListener(_refreshAgenda);

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
    _syncServiceInstance.removeListener(_refreshAgenda);
    super.dispose();
  }

  Future<void> _refreshAgenda() async {
    final rescheduledCount = await SQLiteHelper.instance.updateOverdueStatus();

    if (rescheduledCount > 0 && mounted) {
      _autoSync();
    }

    final results = await Future.wait([
      SQLiteHelper.instance.readAllManejos(),
      SQLiteHelper.instance.readAllPropriedades(),
      SQLiteHelper.instance.getAllEguas(),
      SQLiteHelper.instance.getAllUsers(),
      SQLiteHelper.instance.readAllPeoes(),
    ]);

    if (mounted) {
      setState(() {
        _allManejos = results[0] as List<Manejo>;
        final propriedades = results[1] as List<Propriedade>;
        final eguas = results[2] as List<Egua>;
        final users = results[3] as List<AppUser>;
        final peoes = results[4] as List<Peao>;

        _allPropriedades = {for (var p in propriedades) p.id: p};
        _allEguas = {for (var e in eguas) e.id: e};
        _allUsers = {for (var u in users) u.uid: u};
        _allPeoes = {for (var p in peoes) p.id: p};
      });
    }
  }

  Future<void> _autoSync() async {
    await _syncServiceInstance.syncData(isManual: false);
    if (mounted) {}
    await _refreshAgenda();
  }

  Future<void> _manualSync() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const LoadingScreen(),
    );

    final bool online = await _syncServiceInstance.syncData(isManual: true);
    
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

    Widget _buildControleFolicularInputs({
      required StateSetter setModalState,
      required List<String> ovarioDirOp,
      required Function(String) onOvarioDirToggle,
      required TextEditingController ovarioDirTamanhoController,
      required List<String> ovarioEsqOp,
      required Function(String) onOvarioEsqToggle,
      required TextEditingController ovarioEsqTamanhoController,
      required String? edemaSelecionado,
      required Function(String?) onEdemaChange,
      required TextEditingController uteroController,
  }) {
      final ovarioOptions = ["CL", "OV", "PEQ", "FL"];

      Widget buildChipGroup(
          List<String> selectedOptions, Function(String) onToggle) {
        return Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: ovarioOptions.map((option) {
            return FilterChip(
              label: Text(option),
              selected: selectedOptions.contains(option),
              onSelected: (isSelected) {
                onToggle(option);
              },
              selectedColor: AppTheme.darkGreen.withOpacity(0.2),
              checkmarkColor: AppTheme.darkGreen,
            );
          }).toList(),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text("Dados do Controle Folicular",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 15),
          const Text("Ovário Direito",
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: buildChipGroup(ovarioDirOp, onOvarioDirToggle),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: ovarioDirTamanhoController,
                  decoration: const InputDecoration(labelText: "Tamanho (mm)"),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text("Ovário Esquerdo",
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: buildChipGroup(ovarioEsqOp, onOvarioEsqToggle),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: ovarioEsqTamanhoController,
                  decoration: const InputDecoration(labelText: "Tamanho (mm)"),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
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
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setModalState(() {
                        edemaSelecionado = null;
                      });
                    },
                  )
                : null,
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
                labelText: "Útero", prefixIcon: Icon(Icons.notes_outlined)),
          ),
        ],
      );
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAgendamentoModal(context),
        child: const Icon(Icons.add),
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
    manejos.sort((a, b) {
      if (a.isAtrasado && !b.isAtrasado) return -1;
      if (!a.isAtrasado && b.isAtrasado) return 1;
      return a.dataAgendada.compareTo(b.dataAgendada);
    });
    
    final Propriedade? propriedadePai = propriedade.parentId != null ? _allPropriedades[propriedade.parentId] : null;
    final String nomeExibido = propriedadePai != null ? '${propriedadePai.nome.toUpperCase()} / ${propriedade.nome}' : propriedade.nome.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: Text(nomeExibido,
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
    final bool showTime =
        manejo.dataAgendada.hour != 0 || manejo.dataAgendada.minute != 0;

    String responsavelNome = '...';
    if (manejo.responsavelId != null) {
      responsavelNome =
          _allUsers[manejo.responsavelId]?.nome ?? 'Usuário desconhecido';
    } else if (manejo.responsavelPeaoId != null) {
      responsavelNome =
          _allPeoes[manejo.responsavelPeaoId]?.nome ?? 'Peão desconhecido';
    }

    final bool isPendente = manejo.isAtrasado && manejo.status != 'Concluído';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showConfirmationModal(context, manejo, egua),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (egua != null && egua.photoPath != null && egua.photoPath!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: CircleAvatar(
                    radius: 25,
                    backgroundImage: FileImage(File(egua.photoPath!)),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(egua?.nome ?? "Égua não encontrada",
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        if (showTime)
                          Text(
                            DateFormat('HH:mm', 'pt_BR').format(manejo.dataAgendada),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkGreen),
                          ),
                      ],
                    ),
                    if (egua != null)
                      if (egua.rp.isNotEmpty) ...[
                        Text("RP: ${egua.rp}",
                            style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                      ] else ...[
                        Text("Pelagem: ${egua.pelagem}",
                            style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                      ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "Responsável: $responsavelNome",
                            style: TextStyle(color: Colors.grey[700], fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPendente)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red[700],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "PENDENTE",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
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
        propriedade: propriedade,
        egua: egua,
        preselectedType: "Inseminação",
        preselectedDate: inseminationDate,
      );
      NotificationService().scheduleNotification(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        'Lembrete de Inseminação',
        ' passaram 36 horas desde a indução da égua ${egua.nome}.',
        inseminationDate,
      );
    }
  }

  void _promptForDiagnosticScheduleOnInsemination(
    BuildContext context,
    Propriedade propriedade,
    Egua egua,
    DateTime inseminationDate,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Agendar Diagnóstico?"),
          content: Text(
            "A égua ${egua.nome} foi inseminada. Deseja agendar o diagnóstico para 14 dias a partir de agora?",
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Não"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text("Sim"),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    ).then((confirm) {
      if (confirm == true && mounted) {
        final diagnosticDate = inseminationDate.add(const Duration(days: 14));

        _showAddAgendamentoModal(
          context,
          propriedade: propriedade,
          egua: egua,
          preselectedType: "Diagnóstico",
          preselectedDate: diagnosticDate,
        );

        NotificationService().scheduleNotification(
          DateTime.now().millisecondsSinceEpoch.remainder(100000),
          'Lembrete de Diagnóstico',
          'Hoje é o dia do diagnóstico de prenhez da égua ${egua.nome}.',
          diagnosticDate,
        );
      }
    });
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
      NotificationService().scheduleNotification(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        'Controle Folicular',
        'O folículo da égua atingiu o tamanho ideal de 33mm.',
        scheduledDate,
      );
    }
  }

  void _showAddAgendamentoModal(BuildContext context,
      {Propriedade? propriedade,
      Egua? egua,
      DateTime? preselectedDate,
      String? preselectedType}) async {
    final currentUser = _authService.currentUserNotifier.value;
    if (currentUser == null) return;

    final allUsersList = await SQLiteHelper.instance.getAllUsers();

    final formKey = GlobalKey<FormState>();

    Propriedade? propriedadeMaeSelecionada = propriedade;
    Propriedade? loteSelecionado;
    final TextEditingController propSearchController =
        TextEditingController(text: propriedadeMaeSelecionada?.nome ?? '');

    List<Propriedade> _allTopLevelProps = [];
    List<Propriedade> _filteredProps = [];
    bool _showPropList = false;

    Egua? eguaSelecionada = egua;
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
    List<Peao> peoesDaPropriedade = [];
    if (propriedadeMaeSelecionada != null) {
      peoesDaPropriedade = await SQLiteHelper.instance
          .readPeoesByPropriedade(propriedadeMaeSelecionada.id);
    }

    _allTopLevelProps = await SQLiteHelper.instance.readTopLevelPropriedades();
    _filteredProps = _allTopLevelProps;

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
              _filteredProps = _allTopLevelProps
                  .where((prop) =>
                      prop.nome.toLowerCase().contains(query.toLowerCase()))
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
                child: Text("Dono",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppTheme.brown)),
              ),
            );
            cabanhaItems.add(
              DropdownMenuItem<dynamic>(
                value: propriedadeMaeSelecionada!.dono,
                child: Text(propriedadeMaeSelecionada!.dono),
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
                    Text("Agendar Manejo",
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: 30, thickness: 1),
                    TextFormField(
                      controller: propSearchController,
                      readOnly: propriedadeMaeSelecionada != null,
                      decoration: InputDecoration(
                        labelText: "Propriedade",
                        hintText: "Busque pelo nome da propriedade",
                        prefixIcon: const Icon(Icons.home_work_outlined),
                        suffixIcon: propriedadeMaeSelecionada != null
                            ? null
                            : const Icon(Icons.search),
                      ),
                      onChanged: filterProps,
                      onTap: () => setModalState(() => _showPropList = true),
                      validator: (v) => propriedadeMaeSelecionada == null
                          ? "Selecione uma propriedade"
                          : null,
                    ),
                    if (_showPropList && propriedadeMaeSelecionada == null)
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                            color: AppTheme.pageBackground,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.lightGrey)),
                        child: ListView.builder(
                          itemCount: _filteredProps.length,
                          itemBuilder: (context, index) {
                            final prop = _filteredProps[index];
                            return ListTile(
                              title: Text(prop.nome),
                              onTap: () async {
                                List<Peao> peoes = await SQLiteHelper.instance
                                    .readPeoesByPropriedade(prop.id);

                                setModalState(() {
                                  propriedadeMaeSelecionada = prop;
                                  propSearchController.text = prop.nome;
                                  eguaSelecionada = null;
                                  loteSelecionado = null;
                                  peoesDaPropriedade = peoes;
                                  _showPropList = false;
                                  FocusScope.of(context).unfocus();
                                });
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 15),
                    if (propriedadeMaeSelecionada != null &&
                        propriedadeMaeSelecionada!.hasLotes)
                      FutureBuilder<List<Propriedade>>(
                        future: SQLiteHelper.instance
                            .readSubPropriedades(propriedadeMaeSelecionada!.id),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            children: [
                              DropdownButtonFormField<Propriedade>(
                                value: loteSelecionado,
                                decoration: InputDecoration(
                                  labelText: "Lote",
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                  suffixIcon: loteSelecionado != null
                                    ? IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          setModalState(() {
                                            loteSelecionado = null;
                                            eguaSelecionada = null;
                                          });
                                        },
                                      )
                                    : null,
                                ),
                                hint: const Text("Selecione o Lote"),
                                items: snapshot.data!
                                    .map((lote) => DropdownMenuItem(
                                        value: lote, child: Text(lote.nome)))
                                    .toList(),
                                onChanged: (lote) => setModalState(() {
                                  loteSelecionado = lote;
                                  eguaSelecionada = null;
                                }),
                              ),
                              const SizedBox(height: 15),
                            ],
                          );
                        },
                      ),
                    if (propriedadeMaeSelecionada != null)
                      FutureBuilder<List<Egua>>(
                        future: () async {
                          if (loteSelecionado != null) {
                            return SQLiteHelper.instance
                                .readEguasByPropriedade(loteSelecionado!.id);
                          }
                          if (!propriedadeMaeSelecionada!.hasLotes) {
                            return SQLiteHelper.instance
                                .readEguasByPropriedade(
                                    propriedadeMaeSelecionada!.id);
                          }
                          final subPropriedades = await SQLiteHelper.instance
                              .readSubPropriedades(
                                  propriedadeMaeSelecionada!.id);
                          final allPropIds = [
                            propriedadeMaeSelecionada!.id,
                            ...subPropriedades.map((p) => p.id)
                          ];

                          List<Egua> eguasDaPropriedade = [];
                          for (final propId in allPropIds) {
                            final eguasDoLote = await SQLiteHelper.instance
                                .readEguasByPropriedade(propId);
                            eguasDaPropriedade.addAll(eguasDoLote);
                          }
                          return eguasDaPropriedade;
                        }(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator()));
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(
                                child: Text(
                                    "Nenhuma égua encontrada para a seleção atual."));
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
                            validator: (v) =>
                                v == null ? "Selecione uma égua" : null,
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
                            controller: TextEditingController(
                              text: dataSelecionada == null
                                  ? ''
                                  : DateFormat('dd/MM/yyyy')
                                      .format(dataSelecionada!),
                            ),
                            decoration: const InputDecoration(
                              labelText: "Data do Manejo",
                              prefixIcon: Icon(Icons.calendar_today_outlined),
                              hintText: 'Toque para selecionar',
                            ),
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      dataSelecionada ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030));
                              if (pickedDate != null) {
                                setModalState(
                                    () => dataSelecionada = pickedDate);
                              }
                            },
                            validator: (v) => dataSelecionada == null
                                ? "Selecione a data"
                                : null,
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
                          .map((tipo) => DropdownMenuItem(
                              value: tipo, child: Text(tipo)))
                          .toList(),
                      onChanged: (val) =>
                          setModalState(() => tipoManejoSelecionado = val),
                      validator: (v) => v == null ? "Selecione o tipo" : null,
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
                          prefixIcon: Icon(Icons.person_outline)),
                      items: isVeterinario ? veterinarioItems : cabanhaItems,
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => responsavelSelecionado = value);
                        }
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
                        label: const Text("AGENDAR"),
                        style: ElevatedButton.styleFrom(
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
                              propriedadeId: loteSelecionado?.id ??
                                  eguaSelecionada!.propriedadeId,
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
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(
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

void _showEditAgendamentoModal(BuildContext context, {required Manejo manejo}) async {
  final currentUser = _authService.currentUserNotifier.value;
  if (currentUser == null) return;

  final allUsersList = await SQLiteHelper.instance.getAllUsers();
  final formKey = GlobalKey<FormState>();

  final Egua? egua = _allEguas[manejo.eguaId];
  Propriedade? lote = _allPropriedades[manejo.propriedadeId];
  final Propriedade? propriedadeMae = lote?.parentId != null ? _allPropriedades[lote!.parentId] : lote;

  Propriedade? loteSelecionado = lote?.parentId != null ? lote : null;
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
                  
                  TextFormField(
                    initialValue: propriedadeMae?.nome ?? '',
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: "Propriedade",
                      prefixIcon: Icon(Icons.home_work_outlined),
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  if (propriedadeMae != null && propriedadeMae.hasLotes)
                    FutureBuilder<List<Propriedade>>(
                      future: SQLiteHelper.instance.readSubPropriedades(propriedadeMae.id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        if (loteSelecionado != null && !snapshot.data!.any((l) => l.id == loteSelecionado!.id)) {
                             loteSelecionado = null;
                        }

                        return Column(
                          children: [
                            DropdownButtonFormField<Propriedade>(
                              value: loteSelecionado,
                              decoration: InputDecoration(
                                labelText: "Lote",
                                prefixIcon: Icon(Icons.location_on_outlined),
                                suffixIcon: loteSelecionado != null
                                  ? IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        setModalState(() {
                                          loteSelecionado = null;
                                          eguaSelecionada = null;
                                        });
                                      },
                                    )
                                  : null,
                              ),
                              hint: const Text("Selecione o Lote"),
                              items: snapshot.data!
                                  .map((lote) => DropdownMenuItem(
                                      value: lote, child: Text(lote.nome)))
                                  .toList(),
                              onChanged: (lote) =>
                                  setModalState(() {
                                    loteSelecionado = lote;
                                    eguaSelecionada = null;
                                  }),
                            ),
                            const SizedBox(height: 15),
                          ],
                        );
                      },
                    ),

                  // ALTERADO: Busca de Éguas Condicional na Edição
                  if (propriedadeMae != null)
                    FutureBuilder<List<Egua>>(
                      future: () async {
                        if (loteSelecionado != null) {
                          return SQLiteHelper.instance.readEguasByPropriedade(loteSelecionado!.id);
                        }
                        if (!propriedadeMae.hasLotes) {
                          return SQLiteHelper.instance.readEguasByPropriedade(propriedadeMae.id);
                        }
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
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(child: Text("Nenhuma égua encontrada."));
                        }
                        if (eguaSelecionada != null && !snapshot.data!.any((e) => e.id == eguaSelecionada!.id)) {
                          eguaSelecionada = null;
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
                            propriedadeId: loteSelecionado?.id ?? eguaSelecionada!.propriedadeId,
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
          )
        );
      },
    ),
  );
}

  void _showConfirmationModal(BuildContext context, Manejo manejo, Egua? egua) {
    String responsavelNome = '...';
    if (manejo.responsavelId != null) {
      responsavelNome = _allUsers[manejo.responsavelId]?.nome ?? 'Desconhecido';
    } else if (manejo.responsavelPeaoId != null) {
      responsavelNome = _allPeoes[manejo.responsavelPeaoId]?.nome ?? 'Desconhecido';
    }
    
    final Propriedade? lote = _allPropriedades[manejo.propriedadeId];
    final Propriedade? propriedadePai = lote?.parentId != null ? _allPropriedades[lote!.parentId] : null;

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
                            if (value == 'edit') {
                                _showEditAgendamentoModal(context, manejo: manejo);
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
                                    leading: Icon(Icons.edit_note_outlined),
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
                      Icons.home_work_outlined, "Propriedade", propriedadePai?.nome ?? lote?.nome ?? '...'),
                  
                  if(propriedadePai != null) ...[
                      const SizedBox(height: 16),
                    _buildDetailRow(Icons.location_on_outlined, "Lote", lote?.nome ?? '...'),
                  ],

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
                            onPressed: () async {
                               final Propriedade? loteDaEgua = _allPropriedades[egua.propriedadeId];
                               final String propriedadeMaeId = loteDaEgua?.parentId ?? egua.propriedadeId;
                               Navigator.push(
                                 context,
                                 MaterialPageRoute(
                                   builder: (context) => EguaDetailsScreen(
                                     egua: egua,
                                     propriedadeMaeId: propriedadeMaeId,
                                   ),
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

  void _showMarkAsCompleteModal(BuildContext context, Manejo manejo, Egua? egua) async {
    final currentUser = _authService.currentUserNotifier.value;
    if (currentUser == null || egua == null) return;

    final Propriedade? lote = _allPropriedades[egua.propriedadeId];
    final String propriedadeMaeId = lote?.parentId ?? egua.propriedadeId;
    final Propriedade? propriedadeMaeSelecionada = _allPropriedades[propriedadeMaeId]; 

    bool isVeterinario = true;

    final allUsersList = await SQLiteHelper.instance.getAllUsers();
    final peoesDaPropriedade = await SQLiteHelper.instance.readPeoesByPropriedade(propriedadeMaeId);

    final formKey = GlobalKey<FormState>();
    final obsController = TextEditingController(text: manejo.detalhes['observacao']);

    final garanhaoController = TextEditingController(text: egua.cobertura);
    String? tipoSememSelecionado;
    DateTime? dataHoraInseminacao;
    final litrosController = TextEditingController();
    List<String> ovarioDirOp = [];
    List<String> ovarioEsqOp = [];
    final ovarioDirTamanhoController = TextEditingController();
    final ovarioEsqTamanhoController = TextEditingController();
    String? edemaSelecionado;
    final uteroController = TextEditingController();
    String? idadeEmbriaoSelecionada;
    
    Egua? doadoraSelecionada;
    final avaliacaoUterinaController = TextEditingController();
    String? resultadoDiagnostico;
    final diasPrenheController = TextEditingController();
    Medicamento? medicamentoSelecionado;
    String? inducaoSelecionada;
    DateTime? dataHoraInducao;
    final medicamentoSearchController = TextEditingController();
    final todosMedicamentos = await SQLiteHelper.instance.readAllMedicamentos();
    List<Medicamento> _filteredMedicamentos = todosMedicamentos;
    bool _showMedicamentoList = false;
    DateTime dataFinalManejo = manejo.dataAgendada;
    
    dynamic concluidoPorSelecionado = allUsersList.firstWhere((u) => u.uid == currentUser.uid, orElse: () => allUsersList.first);
    bool _incluirControleFolicular = false;

    Propriedade? propDoadoraSelecionada;
    final propDoadoraSearchController = TextEditingController();
    final allPropsDoadora = await SQLiteHelper.instance.readAllPropriedades();
    List<Propriedade> _filteredPropsDoadora = allPropsDoadora;
    bool _showPropDoadoraList = false;

    String? sexoPotro;
    final pelagemController = TextEditingController();
    DateTime? dataHoraParto;
    final observacoesPartoController = TextEditingController();
    bool partoComSucesso = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

          void filterPropsDoadora(String query) {
            setModalState(() {
              _filteredPropsDoadora = allPropsDoadora
                  .where((prop) =>
                      prop.nome.toLowerCase().contains(query.toLowerCase()))
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
                child: Text("Dono",
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
                    Text("Égua: ${egua.nome}",
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
                    if (manejo.tipo != 'Outros Manejos')
                      const Divider(height: 30, thickness: 1),

                    ..._buildSpecificForm(
                      context: context,
                      egua: egua,
                      tipo: manejo.tipo,
                      setModalState: setModalState,
                      onDataHoraInseminacaoChange: (val) => setModalState(() => dataHoraInseminacao = val),
                      onMedicamentoChange: (val) => setModalState(() => medicamentoSelecionado = val),
                      onOvarioDirToggle: (option) {
                        setModalState(() {
                          if (ovarioDirOp.contains(option)) {
                            ovarioDirOp.remove(option);
                          } else {
                            ovarioDirOp.add(option);
                          }
                        });
                      },
                      onOvarioEsqToggle: (option) {
                        setModalState(() {
                          if (ovarioEsqOp.contains(option)) {
                            ovarioEsqOp.remove(option);
                          } else {
                            ovarioEsqOp.add(option);
                          }
                        });
                      },
                      onEdemaChange: (val) => setModalState(() => edemaSelecionado = val),
                      onIdadeEmbriaoChange: (val) => setModalState(() => idadeEmbriaoSelecionada = val),
                      onDoadoraChange: (val) => setModalState(() => doadoraSelecionada = val),
                      onResultadoChange: (val) => setModalState(() => resultadoDiagnostico = val),
                      onTipoSememChange: (val) => setModalState(() => tipoSememSelecionado = val),
                      garanhaoController: garanhaoController,
                      tipoSememSelecionado: tipoSememSelecionado,
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
                      sexoPotro: sexoPotro,
                      onSexoPotroChange: (val) => setModalState(() => sexoPotro = val),
                      pelagemController: pelagemController,
                      dataHoraParto: dataHoraParto,
                      onDataHoraPartoChange: (val) => setModalState(() => dataHoraParto = val),
                      observacoesPartoController: observacoesPartoController,
                      partoComSucesso: partoComSucesso,
                      onPartoComSucessoChange: (val) => setModalState(() => partoComSucesso = val),
                      propDoadoraSelecionada: propDoadoraSelecionada,
                      propDoadoraSearchController: propDoadoraSearchController,
                      filteredPropsDoadora: _filteredPropsDoadora,
                      showPropDoadoraList: _showPropDoadoraList,
                      onPropDoadoraChange: (val) => setModalState(() => propDoadoraSelecionada = val),
                      onFilterPropsDoadora: filterPropsDoadora,
                      onShowPropDoadoraListChange: (val) => setModalState(() => _showPropDoadoraList = val),
                      allPropsDoadora: allPropsDoadora,
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
                          onOvarioDirToggle: (option) {
                            setModalState(() {
                              if (ovarioDirOp.contains(option)) {
                                ovarioDirOp.remove(option);
                              } else {
                                ovarioDirOp.add(option);
                              }
                            });
                          },
                          ovarioDirTamanhoController: ovarioDirTamanhoController,
                          ovarioEsqOp: ovarioEsqOp,
                          onOvarioEsqToggle: (option) {
                            setModalState(() {
                              if (ovarioEsqOp.contains(option)) {
                                ovarioEsqOp.remove(option);
                              } else {
                                ovarioEsqOp.add(option);
                              }
                            });
                          },
                          ovarioEsqTamanhoController: ovarioEsqTamanhoController,
                          edemaSelecionado: edemaSelecionado,
                          onEdemaChange: (val) => setModalState(() => edemaSelecionado = val),
                          uteroController: uteroController,
                        ),
                    ],
                    
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
                        decoration: InputDecoration(
                          labelText: "Tipo de Indução", 
                          prefixIcon: Icon(Icons.healing_outlined),
                          suffixIcon: inducaoSelecionada != null
                              ? IconButton(
                                  icon: const Icon(Icons.close),
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
                          prefixIcon: Icon(Icons.schedule_outlined),
                          hintText: 'Toque para selecionar',
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
                            setModalState(() {
                              dataHoraInducao = DateTime(date.year, date.month, date.day, time!.hour, time!.minute);
                            });
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
                    
                    if (manejo.tipo != 'Outros Manejos')
                      const Divider(height: 30, thickness: 1),

                    Text("Finalização", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                    const SizedBox(height: 15),

                      TextFormField(
                        readOnly: true,
                        controller: TextEditingController(
                          text: DateFormat('dd/MM/yyyy').format(dataFinalManejo)
                        ),
                        decoration: const InputDecoration(
                            labelText: "Data da Conclusão",
                            prefixIcon: Icon(Icons.event_available_outlined),
                            hintText: 'Toque para selecionar a data'),
                        validator: (v) => v == null ? "Obrigatório" : null,
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))
                        ),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final Map<String, dynamic> detalhes = manejo.detalhes;
                            detalhes['observacao'] = obsController.text;
                            detalhes['dataHoraConclusao'] = DateTime.now().toIso8601String();

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
                            }
                            
                            if (manejo.tipo == 'Diagnóstico') {
                              detalhes['resultado'] = resultadoDiagnostico;
                            if (resultadoDiagnostico == 'Prenhe') {
                              final dias = int.tryParse(diasPrenheController.text) ?? 0;
                              detalhes['diasPrenhe'] = dias;
                                final eguaAtualizada = egua.copyWith(
                                  statusReprodutivo: 'Prenhe',
                                  diasPrenhe: dias,
                                  cobertura: garanhaoController.text,
                                  statusSync: 'pending_update'
                                );
                                await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                            } else if (resultadoDiagnostico == 'Pariu') {
                                detalhes['sexoPotro'] = sexoPotro;
                                detalhes['pelagemPotro'] = pelagemController.text;
                                detalhes['dataHoraParto'] = dataHoraParto?.toIso8601String();
                                detalhes['observacoesParto'] = observacoesPartoController.text;

                                 final eguaAtualizada = egua.copyWith(
                                   statusReprodutivo: 'Vazia',
                                   dataParto: dataHoraParto,
                                   sexoPotro: sexoPotro,
                                   statusSync: 'pending_update'
                                 );
                                 await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                              }
                              final eguaAtualizada = egua.copyWith(
                                  statusReprodutivo: 'Vazia',
                                  diasPrenhe: 0,
                                  statusSync: 'pending_update'
                                );
                              await SQLiteHelper.instance.updateEgua(eguaAtualizada);
                            } else if (manejo.tipo == 'Inseminação') {
                              detalhes['garanhao'] = garanhaoController.text;
                              detalhes['tipoSemem'] = tipoSememSelecionado;
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
                            manejo.dataConclusao = DateTime.now();
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
                              _autoSync();
                              Navigator.of(ctx).pop();
                            }

                            if (manejo.tipo == 'Controle Folicular' && dataHoraInducao != null) {
                              final Propriedade? prop = _allPropriedades[propriedadeMaeId];
                              if (prop != null) {
                                await _promptForInseminationScheduleOnInduction(context, egua, prop, dataHoraInducao!);
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
                              final Propriedade? propriedade = _allPropriedades[egua.propriedadeId];
                              if (propriedade != null) {
                                _promptForDiagnosticScheduleOnInsemination(
                                    context,
                                    propriedade,
                                    egua,
                                    dataHoraInseminacao ?? dataFinalManejo,
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
      );
      },
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
    required Egua egua,
    required String tipo,
    required StateSetter setModalState,
    required TextEditingController garanhaoController,
    String? tipoSememSelecionado,
    required Function(String?) onTipoSememChange,
    required DateTime? dataHoraInseminacao,
    required Function(DateTime?) onDataHoraInseminacaoChange,
    required TextEditingController litrosController,
    required Medicamento? medicamentoSelecionado,
    required Function(Medicamento?) onMedicamentoChange,
    required List<Medicamento> allMeds,
    required List<String> ovarioDirOp,
    required Function(String) onOvarioDirToggle,
    required List<String> ovarioEsqOp,
    required Function(String) onOvarioEsqToggle,
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
    required Propriedade? propDoadoraSelecionada,
    required TextEditingController propDoadoraSearchController,
    required Function(Propriedade?) onPropDoadoraChange,
    required List<Propriedade> filteredPropsDoadora,
    required bool showPropDoadoraList,
    required Function(String) onFilterPropsDoadora,
    required Function(bool) onShowPropDoadoraListChange,
    required List<Propriedade> allPropsDoadora,
    String? sexoPotro,
    required Function(String?) onSexoPotroChange,
    required TextEditingController pelagemController,
    DateTime? dataHoraParto,
    required Function(DateTime?) onDataHoraPartoChange,
    required TextEditingController observacoesPartoController,
    required bool partoComSucesso,
    required Function(bool) onPartoComSucessoChange,
  }) {
    final idadeEmbriaoOptions = ['D6', 'D7', 'D8', 'D9', 'D10', 'D11'];
    final tiposSemem = ['Refrigerado', 'Congelado', 'A Fresco', 'Monta Natural'];

    switch (tipo) {
      case "Diagnóstico":
        final List<String> diagnosticoItems = ["Indeterminado", "Prenhe", "Vazia"];
          if (egua.statusReprodutivo.toLowerCase() == 'prenhe' && egua.categoria != 'Doadora') {
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
                  labelText: "Garanhão", prefixIcon: Icon(Icons.male_outlined))),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: tipoSememSelecionado,
            decoration: InputDecoration(
                labelText: "Tipo de Sêmen",
                prefixIcon: Icon(Icons.science_outlined)),
            hint: const Text("Selecione o tipo"),
            items: tiposSemem
                .map((tipo) => DropdownMenuItem(value: tipo, child: Text(tipo)))
                .toList(),
            onChanged: (val) => setModalState(() => onTipoSememChange(val)),
            validator: (v) => v == null ? "Selecione o tipo de sêmen" : null,
          ),
          const SizedBox(height: 15),
          TextFormField(
            readOnly: true,
            controller: TextEditingController(
              text: dataHoraInseminacao == null
                  ? ''
                  : DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                      .format(dataHoraInseminacao),
            ),
            decoration: const InputDecoration(
                labelText: "Data/Hora da Inseminação",
                prefixIcon: Icon(Icons.schedule_outlined),
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
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                      TextButton(
                        child: const Text("OK"),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
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
                  labelText: "Litros", prefixIcon: Icon(Icons.water_drop_outlined)),
              keyboardType: TextInputType.number),
          const SizedBox(height: 15),
          DropdownButtonFormField<Medicamento>(
            value: medicamentoSelecionado,
            decoration: const InputDecoration(
                labelText: "Medicamento",
                prefixIcon: Icon(Icons.vaccines_outlined)),
            items: allMeds
                .map((m) => DropdownMenuItem(value: m, child: Text(m.nome)))
                .toList(),
            onChanged: (val) => setModalState(() => onMedicamentoChange(val)),
          )
        ];
      case "Controle Folicular":
        return [
          _buildControleFolicularInputs(
            setModalState: setModalState,
            ovarioDirOp: ovarioDirOp,
            onOvarioDirToggle: onOvarioDirToggle,
            ovarioDirTamanhoController: ovarioDirTamanhoController,
            ovarioEsqOp: ovarioEsqOp,
            onOvarioEsqToggle: onOvarioEsqToggle,
            ovarioEsqTamanhoController: ovarioEsqTamanhoController,
            edemaSelecionado: edemaSelecionado,
            onEdemaChange: onEdemaChange,
            uteroController: uteroController,
          )
        ];
      case "Transferência de Embrião":
        return [
          Text("Dados da Doadora",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextFormField(
            controller: propDoadoraSearchController,
            readOnly: propDoadoraSelecionada != null,
            decoration: InputDecoration(
              labelText: "Propriedade da Doadora",
              prefixIcon: const Icon(Icons.home_work_outlined),
              suffixIcon: propDoadoraSelecionada != null
                  ? null
                  : const Icon(Icons.search),
            ),
            onChanged: onFilterPropsDoadora,
            onTap: () => setModalState(() => onShowPropDoadoraListChange(true)),
            validator: (v) =>
                propDoadoraSelecionada == null ? "Selecione a propriedade" : null,
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
              future: SQLiteHelper.instance
                  .readEguasByPropriedade(propDoadoraSelecionada.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                return DropdownButtonFormField<Egua>(
                  value: doadoraSelecionada,
                  decoration: const InputDecoration(
                      labelText: "Égua Doadora",
                      prefixIcon: Icon(Icons.female_outlined)),
                  items: snapshot.data!
                      .map((e) => DropdownMenuItem(value: e, child: Text(e.nome)))
                      .toList(),
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
            decoration: const InputDecoration(
                labelText: "Idade do Embrião",
                prefixIcon: Icon(Icons.hourglass_bottom_outlined)),
            items: idadeEmbriaoOptions
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) => setModalState(() => onIdadeEmbriaoChange(val)),
          ),
          const SizedBox(height: 15),
          TextFormField(
              controller: avaliacaoUterinaController,
              decoration: const InputDecoration(
                  labelText: "Avaliação Uterina",
                  prefixIcon: Icon(Icons.notes_outlined))),
        ];
      case "Coleta de Embrião":
        return [
          DropdownButtonFormField<String>(
            value: idadeEmbriao,
            decoration: const InputDecoration(
                labelText: "Idade do Embrião",
                prefixIcon: Icon(Icons.hourglass_bottom_outlined)),
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