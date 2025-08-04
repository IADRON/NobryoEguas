class Temporada {
  final String id;
  String nome;
  DateTime dataInicio;
  DateTime dataFim;

  Temporada({
    required this.id,
    required this.nome,
    required this.dataInicio,
    required this.dataFim,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'dataInicio': dataInicio.toIso8601String(),
      'dataFim': dataFim.toIso8601String(),
    };
  }

  factory Temporada.fromMap(Map<String, dynamic> map) {
    return Temporada(
      id: map['id'],
      nome: map['nome'],
      dataInicio: DateTime.parse(map['dataInicio']),
      dataFim: DateTime.parse(map['dataFim']),
    );
  }
}