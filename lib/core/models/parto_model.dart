class Parto {
  final String id;
  final String eguaId;
  final DateTime dataHora;
  final String sexoPotro;
  final String pelagemPotro;
  final String observacoes;

  Parto({
    required this.id,
    required this.eguaId,
    required this.dataHora,
    required this.sexoPotro,
    required this.pelagemPotro,
    required this.observacoes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'eguaId': eguaId,
      'dataHora': dataHora.toIso8601String(),
      'sexoPotro': sexoPotro,
      'pelagemPotro': pelagemPotro,
      'observacoes': observacoes,
    };
  }

  factory Parto.fromMap(Map<String, dynamic> map) {
    return Parto(
      id: map['id'],
      eguaId: map['eguaId'],
      dataHora: DateTime.parse(map['dataHora']),
      sexoPotro: map['sexoPotro'],
      pelagemPotro: map['pelagemPotro'],
      observacoes: map['observacoes'],
    );
  }
}