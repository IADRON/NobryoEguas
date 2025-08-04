import 'package:nobryo_final/core/models/egua_model.dart';
  import 'package:nobryo_final/core/models/manejo_model.dart';
  import 'package:nobryo_final/core/models/medicamento_model.dart';
  import 'package:nobryo_final/core/models/peao_model.dart';
  import 'package:nobryo_final/core/models/propriedade_model.dart';
  import 'package:nobryo_final/core/models/user_model.dart';
  import 'package:path/path.dart';
  import 'package:sqflite/sqflite.dart';

  class SQLiteHelper {
    static final SQLiteHelper instance = SQLiteHelper._init();
    static Database? _database;

    SQLiteHelper._init();

    Future<Database> get database async {
      if (_database != null) return _database!;
      _database = await _initDB('nobryo.db');
      return _database!;
    }

    Future<Database> _initDB(String filePath) async {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);

      return await openDatabase(
        path,
        version: 23,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );
    }

    Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
      if (oldVersion < 7) {
        await db.execute('ALTER TABLE users ADD COLUMN photoUrl TEXT');
      }
      if (oldVersion < 8) {
        await db.execute('ALTER TABLE manejos ADD COLUMN responsavelId TEXT');
        await db.execute('ALTER TABLE manejos ADD COLUMN concluidoPorId TEXT');
      }
      if (oldVersion < 9) {
        await db
            .execute('ALTER TABLE eguas ADD COLUMN isDeleted INTEGER DEFAULT 0 NOT NULL');
      }
      if (oldVersion < 10) {
        await db.execute(
            'ALTER TABLE propriedades ADD COLUMN isDeleted INTEGER DEFAULT 0 NOT NULL');
      }
      if (oldVersion < 13) {
        final columns = await db.rawQuery('PRAGMA table_info(users)');
        final hasUsernameColumn =
            columns.any((col) => col['name'] == 'username');
        if (!hasUsernameColumn) {
          await db.execute('ALTER TABLE users RENAME TO _users_old_temp');
          await _createUsersTable(db);
          final oldUsers = await db.query('_users_old_temp');
          for (final userMap in oldUsers) {
            final email = userMap['email'] as String?;
            if (email != 'admin' && email != 'Bruna') {
              await db.insert('users', {
                'uid': userMap['uid'],
                'nome': userMap['nome'],
                'username': userMap['email'],
                'password': userMap['password'],
                'crmv': userMap['crmv'],
                'statusSync': 'synced',
                'photoUrl': userMap['photoUrl'],
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
          await db.execute('DROP TABLE _users_old_temp');
        } else {
          await _createUsersTable(db);
        }
      }
      if (oldVersion < 14) {
        await db
            .execute('ALTER TABLE users ADD COLUMN isDeleted INTEGER DEFAULT 0 NOT NULL');
        await _createPeoesTable(db);
      }
      if (oldVersion < 15) {
        await db.execute(
            "ALTER TABLE eguas ADD COLUMN categoria TEXT NOT NULL DEFAULT 'Matriz'");
      }
      if (oldVersion < 16) {
        await db.execute("ALTER TABLE propriedades ADD COLUMN parentId TEXT");
      }
      if (oldVersion < 17) {
        await db.execute(
            'ALTER TABLE eguas ADD COLUMN orderIndex INTEGER NOT NULL DEFAULT 0');
      }
      if (oldVersion < 18) {
        await db.execute('ALTER TABLE manejos ADD COLUMN responsavelPeaoId TEXT');
        await db.execute('ALTER TABLE manejos ADD COLUMN concluidoPorPeaoId TEXT');
      }
      if (oldVersion < 19) {
          await db.execute('DROP TABLE IF EXISTS manejos');
          await _createManejosTable(db);
      }
      if (oldVersion < 20) {
        await db.execute('ALTER TABLE propriedades ADD COLUMN deslocamentos INTEGER DEFAULT 0 NOT NULL');
      }

      if (oldVersion < 21) {
        if (!await _columnExists(db, 'manejos', 'isAtrasado')) {
          await db.execute('ALTER TABLE manejos ADD COLUMN isAtrasado INTEGER DEFAULT 0 NOT NULL');
        }
      }
      if (oldVersion < 22) {
        await db.execute('ALTER TABLE propriedades ADD COLUMN hasLotes INTEGER DEFAULT 1 NOT NULL');
      }
      if (oldVersion < 23) {
        await _createPartosTable(db);
        await _createTemporadaTable(db);
        await db.execute('ALTER TABLE manejos ADD COLUM dataConclusao DATETIME');
      }
    }

    Future<bool> _columnExists(Database db, String tableName, String columnName) async {
      final result = await db.rawQuery('PRAGMA table_info($tableName)');
      return result.any((col) => col['name'] == columnName);
    }

    Future _createDB(Database db, int version) async {
      await _createUsersTable(db);
      await _createPropriedadesTable(db);
      await _createEguasTable(db);
      await _createManejosTable(db);
      await _createMedicamentosTable(db);
      await _createPeoesTable(db);
      await _createPartosTable(db);
      await _createTemporadaTable(db);
    }

    Future<void> _createUsersTable(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          uid TEXT PRIMARY KEY,
          nome TEXT NOT NULL,
          username TEXT NOT NULL UNIQUE,
          password TEXT NOT NULL,
          crmv TEXT NOT NULL,
          statusSync TEXT NOT NULL,
          photoUrl TEXT,
          isDeleted INTEGER DEFAULT 0 NOT NULL
        )
      ''');

      final adminUser = AppUser(
          uid: 'admin_uid_01',
          nome: 'Administrador',
          username: 'admin',
          crmv: '0000',
          password: '000000',
          statusSync: 'synced');
      await db.insert('users', adminUser.toMapForDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);

      final brunaUser = AppUser(
          uid: 'bruna_uid_02',
          nome: 'Bruna',
          username: 'Bruna',
          crmv: '1111',
          password: '111111',
          statusSync: 'synced');
      await db.insert('users', brunaUser.toMapForDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<void> _createPropriedadesTable(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS propriedades (
          id TEXT PRIMARY KEY, firebaseId TEXT, nome TEXT NOT NULL,
          dono TEXT NOT NULL, parentId TEXT, 
          deslocamentos INTEGER DEFAULT 0 NOT NULL,
          hasLotes INTEGER DEFAULT 1 NOT NULL,
          statusSync TEXT NOT NULL,
          isDeleted INTEGER DEFAULT 0 NOT NULL
        )
      ''');
    }

    Future<void> _createEguasTable(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS eguas (
          id TEXT PRIMARY KEY, firebaseId TEXT, nome TEXT NOT NULL, rp TEXT NOT NULL, pelagem TEXT NOT NULL, cobertura TEXT,
          dataParto TEXT, sexoPotro TEXT, statusReprodutivo TEXT NOT NULL, diasPrenhe INTEGER,
          observacao TEXT, propriedadeId TEXT NOT NULL, statusSync TEXT NOT NULL,
          isDeleted INTEGER DEFAULT 0 NOT NULL,
          categoria TEXT NOT NULL DEFAULT 'Matriz',
          orderIndex INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (propriedadeId) REFERENCES propriedades (id) ON DELETE CASCADE
        )
      ''');
    }

    Future<void> _createManejosTable(Database db) async {
      await db.execute('''
          CREATE TABLE IF NOT EXISTS manejos (
            id TEXT PRIMARY KEY,
            firebaseId TEXT,
            tipo TEXT NOT NULL,
            dataAgendada TEXT NOT NULL,
            status TEXT NOT NULL,
            detalhes TEXT NOT NULL,
            eguaId TEXT NOT NULL,
            propriedadeId TEXT NOT NULL,
            responsavelId TEXT, 
            concluidoPorId TEXT,
            responsavelPeaoId TEXT,
            concluidoPorPeaoId TEXT,
            statusSync TEXT NOT NULL,
            isDeleted INTEGER DEFAULT 0 NOT NULL,
            medicamentoId TEXT,
            inducao TEXT,
            dataHoraInducao TEXT,
            isAtrasado INTEGER DEFAULT 0 NOT NULL,
            FOREIGN KEY (eguaId) REFERENCES eguas (id) ON DELETE CASCADE,
            FOREIGN KEY (responsavelId) REFERENCES users (uid),
            FOREIGN KEY (concluidoPorId) REFERENCES users (uid)
          )
        ''');
    }

    Future<void> _createMedicamentosTable(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS medicamentos (
          id TEXT PRIMARY KEY, firebaseId TEXT, nome TEXT NOT NULL, descricao TEXT,
          statusSync TEXT NOT NULL, isDeleted INTEGER DEFAULT 0 NOT NULL
        )
      ''');
    }

    Future<void> _createPeoesTable(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS peoes (
          id TEXT PRIMARY KEY,
          nome TEXT NOT NULL,
          funcao TEXT NOT NULL,
          propriedadeId TEXT NOT NULL,
          isDeleted INTEGER DEFAULT 0 NOT NULL,
          FOREIGN KEY (propriedadeId) REFERENCES propriedades (id) ON DELETE CASCADE
        )
      ''');
    }

    Future<void> _createPartosTable(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS partos (
          id TEXT PRIMARY KEY,
          eguaId TEXT NOT NULL,
          dataHora TEXT NOT NULL,
          sexoPotro TEXT NOT NULL,
          pelagemPotro TEXT NOT NULL,
          observacoes TEXT,
          FOREIGN KEY (eguaId) REFERENCES eguas (id) ON DELETE CASCADE
        )
      ''');
    }

    Future<void> _createTemporadaTable(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS temporadas (
          id TEXT PRIMARY KEY,
          nome TEXT NOT NULL,
          dataInicio TEXT NOT NULL,
          dataFim TEXT NOT NULL,
        )
      ''');
    }

    Future<void> createUser(AppUser user) async {
      final db = await instance.database;
      await db.insert('users', user.toMapForDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<List<Peao>> readAllPeoes() async {
      final db = await instance.database;
      final result = await db.query('peoes', where: 'isDeleted = 0');
      return result.map((json) => Peao.fromMap(json)).toList();
    }

    Future<AppUser?> getUserByUsernameAndPassword(
        String username, String password) async {
      final db = await instance.database;
      final result = await db.query('users',
          where: 'username = ? AND password = ?',
          whereArgs: [username, password],
          limit: 1);
      if (result.isNotEmpty) {
        return AppUser.fromDbMap(result.first);
      }
      return null;
    }

    Future<List<AppUser>> getAllUsers() async {
      final db = await instance.database;
      final result =
          await db.query('users', where: 'isDeleted = 0', orderBy: 'nome ASC');
      return result.map((json) => AppUser.fromDbMap(json)).toList();
    }

    Future<AppUser?> getUserByUsername(String username) async {
      final db = await instance.database;
      final result = await db
          .query('users', where: 'username = ?', whereArgs: [username], limit: 1);
      if (result.isNotEmpty) {
        return AppUser.fromDbMap(result.first);
      }
      return null;
    }

    Future<int> updateUser(AppUser user) async {
      final db = await instance.database;
      return db.update('users', user.toMapForDb(),
          where: 'uid = ?', whereArgs: [user.uid]);
    }

    Future<List<AppUser>> getUnsyncedUsers() async {
      final db = await instance.database;
      final result =
          await db.query('users', where: 'statusSync != ?', whereArgs: ['synced']);
      return result.map((json) => AppUser.fromDbMap(json)).toList();
    }

    Future<void> createPropriedade(Propriedade propriedade) async {
      final db = await instance.database;
      await db.insert('propriedades', propriedade.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<List<Propriedade>> readAllPropriedades() async {
      final db = await instance.database;
      final result = await db.query('propriedades',
          where: 'isDeleted = 0', orderBy: 'nome ASC');
      return result.map((json) => Propriedade.fromMap(json)).toList();
    }

    Future<List<Propriedade>> readTopLevelPropriedades() async {
      final db = await instance.database;
      final result = await db.query('propriedades',
          where: 'isDeleted = 0 AND parentId IS NULL', orderBy: 'nome ASC');
      return result.map((json) => Propriedade.fromMap(json)).toList();
    }

    Future<List<Propriedade>> readSubPropriedades(String parentId) async {
      final db = await instance.database;
      final result = await db.query('propriedades',
          where: 'isDeleted = 0 AND parentId = ?',
          whereArgs: [parentId],
          orderBy: 'nome ASC');
      return result.map((json) => Propriedade.fromMap(json)).toList();
    }

    Future<Propriedade?> readPropriedade(String id) async {
      final db = await instance.database;
      final maps = await db.query('propriedades',
          where: 'id = ? AND isDeleted = 0', whereArgs: [id], limit: 1);
      if (maps.isNotEmpty) {
        return Propriedade.fromMap(maps.first);
      }
      return null;
    }

    Future<String?> findPropriedadeIdByFirebaseId(String firebaseId) async {
      final db = await instance.database;
      final result = await db.query('propriedades',
          columns: ['id'], where: 'firebaseId = ?', whereArgs: [firebaseId], limit: 1);
      if (result.isNotEmpty) {
        return result.first['id'] as String?;
      }
      return null;
    }

    Future<List<Propriedade>> getUnsyncedPropriedades() async {
      final db = await instance.database;
      final result = await db.query('propriedades',
          where: 'statusSync != ? AND isDeleted = 0', whereArgs: ['synced']);
      return result.map((json) => Propriedade.fromMap(json)).toList();
    }

    Future<int> updatePropriedade(Propriedade propriedade) async {
      final db = await instance.database;
      return db.update('propriedades', propriedade.toMap(),
          where: 'id = ?', whereArgs: [propriedade.id]);
    }

    Future<int> softDeletePropriedade(String id) async {
      final db = await instance.database;
      return db.update('propriedades', {'isDeleted': 1, 'statusSync': 'pending_delete'},
          where: 'id = ?', whereArgs: [id]);
    }

    Future<List<Propriedade>> getDeletedPropriedades() async {
      final db = await instance.database;
      final result = await db.query('propriedades', where: 'isDeleted = 1');
      return result.map((json) => Propriedade.fromMap(json)).toList();
    }

    Future<int> permanentlyDeletePropriedade(String id) async {
      final db = await instance.database;
      return db.delete('propriedades', where: 'id = ?', whereArgs: [id]);
    }

    Future<void> createEgua(Egua egua) async {
      final db = await instance.database;
      await db.insert('eguas', egua.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<Egua?> getEguaById(String id) async {
      final db = await instance.database;
      final maps = await db.query('eguas',
          where: 'id = ? AND isDeleted = 0', whereArgs: [id], limit: 1);
      if (maps.isNotEmpty) {
        return Egua.fromMap(maps.first);
      }
      return null;
    }

    Future<List<Egua>> readEguasByPropriedade(String propriedadeId) async {
      final db = await instance.database;
      final result = await db.query('eguas',
          where: 'propriedadeId = ? AND isDeleted = 0',
          whereArgs: [propriedadeId],
          orderBy: 'orderIndex ASC, nome ASC');
      return result.map((json) => Egua.fromMap(json)).toList();
    }
    
    Future<void> updateEguasOrder(List<Egua> eguas) async {
      final db = await instance.database;
      final batch = db.batch();
      for (int i = 0; i < eguas.length; i++) {
        batch.update(
          'eguas',
          {'orderIndex': i},
          where: 'id = ?',
          whereArgs: [eguas[i].id],
        );
      }
      await batch.commit(noResult: true);
    }

    Future<List<Egua>> getAllEguas() async {
      final db = await instance.database;
      final result = await db.query('eguas', where: 'isDeleted = 0');
      return result.map((json) => Egua.fromMap(json)).toList();
    }

    Future<List<Egua>> getUnsyncedEguas() async {
      final db = await instance.database;
      final result = await db.query('eguas',
          where: 'statusSync != ? AND isDeleted = 0', whereArgs: ['synced']);
      return result.map((json) => Egua.fromMap(json)).toList();
    }

    Future<int> updateEgua(Egua egua) async {
      final db = await instance.database;
      return db.update('eguas', egua.toMap(), where: 'id = ?', whereArgs: [egua.id]);
    }

    Future<String?> findEguaIdByFirebaseId(String firebaseId) async {
      final db = await instance.database;
      final result = await db.query('eguas',
          columns: ['id'], where: 'firebaseId = ?', whereArgs: [firebaseId], limit: 1);
      if (result.isNotEmpty) {
        return result.first['id'] as String?;
      }
      return null;
    }

    Future<int> softDeleteEgua(String id) async {
      final db = await instance.database;
      return db.update('eguas', {'isDeleted': 1, 'statusSync': 'pending_delete'},
          where: 'id = ?', whereArgs: [id]);
    }

    Future<List<Egua>> getDeletedEguas() async {
      final db = await instance.database;
      final result = await db.query('eguas', where: 'isDeleted = 1');
      return result.map((json) => Egua.fromMap(json)).toList();
    }

    Future<int> permanentlyDeleteEgua(String id) async {
      final db = await instance.database;
      return db.delete('eguas', where: 'id = ?', whereArgs: [id]);
    }

    Future<void> createMedicamento(Medicamento medicamento) async {
      final db = await instance.database;
      await db.insert('medicamentos', medicamento.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<List<Medicamento>> readAllMedicamentos() async {
      final db = await instance.database;
      final result = await db.query('medicamentos',
          where: 'isDeleted = 0', orderBy: 'nome ASC');
      return result.map((json) => Medicamento.fromMap(json)).toList();
    }

    Future<List<Medicamento>> getUnsyncedMedicamentos() async {
      final db = await instance.database;
      final result = await db.query('medicamentos',
          where: 'statusSync != ? AND isDeleted = 0', whereArgs: ['synced']);
      return result.map((json) => Medicamento.fromMap(json)).toList();
    }

    Future<int> updateMedicamento(Medicamento medicamento) async {
      final db = await instance.database;
      return db.update('medicamentos', medicamento.toMap(),
          where: 'id = ?', whereArgs: [medicamento.id]);
    }

    Future<int> softDeleteMedicamento(String id) async {
      final db = await instance.database;
      return db.update(
          'medicamentos', {'isDeleted': 1, 'statusSync': 'pending_delete'},
          where: 'id = ?', whereArgs: [id]);
    }

    Future<List<Medicamento>> getDeletedMedicamentos() async {
      final db = await instance.database;
      final result = await db.query('medicamentos', where: 'isDeleted = 1');
      return result.map((json) => Medicamento.fromMap(json)).toList();
    }

    Future<int> permanentlyDeleteMedicamento(String id) async {
      final db = await instance.database;
      return db.delete('medicamentos', where: 'id = ?', whereArgs: [id]);
    }

    Future<void> createManejo(Manejo manejo) async {
      final db = await instance.database;
      await db.insert('manejos', manejo.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<List<Manejo>> readAllManejos() async {
      final db = await instance.database;
      final result = await db.query('manejos',
          where: 'isDeleted = 0 AND status = ?',
          whereArgs: ['Agendado'],
          orderBy: 'dataAgendada ASC');
      return result.map((json) => Manejo.fromMap(json)).toList();
    }

    Future<int> updateManejo(Manejo manejo) async {
      final db = await instance.database;
      return db.update('manejos', manejo.toMap(),
          where: 'id = ?', whereArgs: [manejo.id]);
    }

    Future<int> softDeleteManejo(String id) async {
      final db = await instance.database;
      return db.update('manejos', {'isDeleted': 1, 'statusSync': 'pending_delete'},
          where: 'id = ?', whereArgs: [id]);
    }

    Future<List<Manejo>> getUnsyncedManejos() async {
      final db = await instance.database;
      final result = await db.query('manejos',
          where: 'statusSync != ? AND isDeleted = 0', whereArgs: ['synced']);
      return result.map((json) => Manejo.fromMap(json)).toList();
    }

    Future<List<Manejo>> getDeletedManejos() async {
      final db = await instance.database;
      final result = await db.query('manejos', where: 'isDeleted = 1');
      return result.map((json) => Manejo.fromMap(json)).toList();
    }

    Future<int> permanentlyDeleteManejo(String id) async {
      final db = await instance.database;
      return db.delete('manejos', where: 'id = ?', whereArgs: [id]);
    }

    Future<List<Manejo>> readHistoricoByEgua(String eguaId) async {
      final db = await instance.database;
      final result = await db.query('manejos',
          where: 'eguaId = ? AND status = ? AND isDeleted = 0',
          whereArgs: [eguaId, 'Concluído'],
          orderBy: 'dataAgendada DESC');
      return result.map((json) => Manejo.fromMap(json)).toList();
    }

    Future<List<Manejo>> readAgendadosByEgua(String eguaId) async {
      final db = await instance.database;
      final result = await db.query('manejos',
          where: 'eguaId = ? AND status = ? AND isDeleted = 0',
          whereArgs: [eguaId, 'Agendado'],
          orderBy: 'dataAgendada ASC');
      return result.map((json) => Manejo.fromMap(json)).toList();
    }

    Future<List<Manejo>> getAllEguasManejos() async {
      final db = await instance.database;
      final result = await db.query('manejos');
      return result.map((json) => Manejo.fromMap(json)).toList();
    }

    Future<void> createPeao(Peao peao) async {
      final db = await instance.database;
      await db.insert('peoes', peao.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<List<Peao>> readPeoesByPropriedade(String propriedadeId) async {
      final db = await instance.database;
      final result = await db.query('peoes',
          where: 'propriedadeId = ? AND isDeleted = 0',
          whereArgs: [propriedadeId],
          orderBy: 'nome ASC');
      return result.map((json) => Peao.fromMap(json)).toList();
    }

    Future<int> updatePeao(Peao peao) async {
      final db = await instance.database;
      return db
          .update('peoes', peao.toMap(), where: 'id = ?', whereArgs: [peao.id]);
    }

    Future<int> softDeletePeao(String id) async {
      final db = await instance.database;
      return db.update('peoes', {'isDeleted': 1}, where: 'id = ?', whereArgs: [id]);
    }

    Future<bool> hasPendingManejosForPropriedade(String propriedadeId) async {
      final db = await instance.database;
      final result = await db.rawQuery('''
        SELECT 1
        FROM manejos 
        WHERE propriedadeId = ? 
        AND status = 'Agendado' 
        AND isDeleted = 0 
        LIMIT 1
      ''', [propriedadeId]);
      return result.isNotEmpty;
    }

    Future<bool> hasPendingManejosRecursive(String parentPropriedadeId) async {
      final db = await instance.database;
      
      final subPropriedades = await readSubPropriedades(parentPropriedadeId);
      final allPropriedadeIds = [parentPropriedadeId, ...subPropriedades.map((p) => p.id)];
      
      final placeholders = allPropriedadeIds.map((_) => '?').join(',');
      
      final result = await db.rawQuery('''
        SELECT 1
        FROM manejos
        WHERE propriedadeId IN ($placeholders)
        AND status = 'Agendado'
        AND isDeleted = 0
        LIMIT 1
      ''', allPropriedadeIds);

      return result.isNotEmpty;
    }

  Future<int> updateOverdueStatus() async {
    final db = await instance.database;
    final now = DateTime.now();

    // Usar apenas a data, sem as horas, para a comparação
    final today = DateTime(now.year, now.month, now.day);
    final todayString = today.toIso8601String().split('T').first;

    // Atualiza apenas os manejos que estão 'Agendado' e cuja data passou
    final count = await db.update(
      'manejos',
      {
        'isAtrasado': 1,
        'statusSync': 'pending_update' // Mantém a lógica de sincronização
      },
      where: 'status = ? AND dataAgendada < ? AND isAtrasado = 0', // Condição mais precisa
      whereArgs: ['Agendado', todayString], // Argumentos corretos
    );

    if (count > 0) {
      print("$count manejos foram marcados como atrasados.");
    }

    return count;
  }

  Future close() async {
    final db = await instance.database;
    _database = null;
    db.close();
  }
}