import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nobryo_eguas/core/models/egua_model.dart';
import 'package:nobryo_eguas/core/models/manejo_model.dart';
import 'package:nobryo_eguas/core/models/propriedade_model.dart';
import 'package:open_file/open_file.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ExportService {

  Future<void> exportarPropriedadeParaPdf(
    Propriedade propriedade,
    Map<Egua, List<Manejo>> dadosCompletos,
    BuildContext context,
  ) async {
    try {
      final pdf = pw.Document();
      final fontData = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
      final fontBoldData = await rootBundle.load("assets/fonts/Roboto-Bold.ttf");
      final font = pw.Font.ttf(fontData);
      final fontBold = pw.Font.ttf(fontBoldData);

      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            margin: const pw.EdgeInsets.all(32),
            theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          ),
          header: (pw.Context ctx) => pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Histórico Completo - Propriedade: ${propriedade.nome}',
              style: pw.Theme.of(ctx).defaultTextStyle.copyWith(color: PdfColors.grey),
            ),
          ),
          build: (pw.Context ctx) {
            List<pw.Widget> widgets = [];
            widgets.add(pw.Text(
              'Histórico Completo da Propriedade',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24),
            ));
            
            // ALTERAÇÃO: Adiciona contagem de deslocamentos somente se for a propriedade principal
            if (propriedade.parentId == null) {
              widgets.add(pw.SizedBox(height: 8));
              widgets.add(pw.Text(
                'Deslocamentos: ${propriedade.deslocamentos}',
                style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
              ));
            }

            widgets.add(pw.Divider(thickness: 2, height: 30));

            if (dadosCompletos.values.every((list) => list.isEmpty)) {
              widgets.add(pw.Text("Nenhum dado de manejo encontrado para esta propriedade."));
              return widgets;
            }

            dadosCompletos.forEach((egua, manejos) {
              if (manejos.isNotEmpty) {
                if (widgets.length > 2) {
                   widgets.add(pw.SizedBox(height: 20));
                }
                widgets.add(pw.Header(
                  level: 1,
                  text: 'Égua: ${egua.nome} (RP: ${egua.rp})',
                ));
                
                for (final manejo in manejos) {
                  widgets.add(_blocoDeManejoPdf(manejo));
                }
              }
            });
            return widgets;
          },
        ),
      );

      final bytes = await pdf.save();
      final filePath = await _salvarArquivo(bytes, propriedade.nome, 'pdf');
      _abrirArquivo(filePath, "PDF", context);
    } catch (e) {
      _mostrarErro("PDF da Propriedade", e, context);
    }
  }

  Future<void> exportarPropriedadeParaExcel(
    Propriedade propriedade,
    Map<Egua, List<Manejo>> dadosCompletos,
    BuildContext context,
  ) async {
    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];
      
      sheet.cell(CellIndex.indexByString("A1")).value = "Histórico Completo - Propriedade: ${propriedade.nome}";
      sheet.merge(CellIndex.indexByString("A1"), CellIndex.indexByString("F1"));

      // ALTERAÇÃO: Adiciona contagem de deslocamentos somente se for a propriedade principal
      if (propriedade.parentId == null) {
        sheet.cell(CellIndex.indexByString("A2")).value = "Deslocamentos: ${propriedade.deslocamentos}";
        sheet.merge(CellIndex.indexByString("A2"), CellIndex.indexByString("F2"));
      }

      final headers = ["Égua", "RP", "Data", "Tipo de Manejo", "Detalhes", "Observações"];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3));
        cell.value = headers[i];
        cell.cellStyle = CellStyle(bold: true, backgroundColorHex: "#FF4CAF50", fontColorHex: "#FFFFFFFF", textWrapping: TextWrapping.WrapText);
      }

      int rowIndex = 4;
      dadosCompletos.forEach((egua, manejos) {
        for (final manejo in manejos) {
          final detalhesString = _getFormattedDetalhesExcel(manejo.detalhes);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = egua.nome;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = egua.proprietario;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value = egua.rp;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = DateFormat('dd/MM/yyyy').format(manejo.dataAgendada);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value = manejo.tipo;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value = detalhesString;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value = manejo.detalhes['observacao'] ?? '';
          rowIndex++;
        }
      });
      
      for(var i=0; i<headers.length; i++) {
        sheet.setColAutoFit(i);
      }

      final List<int>? bytes = excel.save();
      if (bytes != null) {
        final filePath = await _salvarArquivo(bytes, propriedade.nome, 'xlsx');
        _abrirArquivo(filePath, "Excel", context);
      } else {
        throw Exception("Falha ao gerar os bytes do arquivo Excel.");
      }
    } catch (e) {
      _mostrarErro("Excel da Propriedade", e, context);
    }
  }

  Future<void> exportarParaPdf(Egua egua, List<Manejo> historico, BuildContext context) async {
    try {
      final pdf = pw.Document();
      final fontData = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
      final fontBoldData = await rootBundle.load("assets/fonts/Roboto-Bold.ttf");
      final font = pw.Font.ttf(fontData);
      final fontBold = pw.Font.ttf(fontBoldData);

      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            margin: const pw.EdgeInsets.all(32),
            theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          ),
          header: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 3.0 * PdfPageFormat.mm),
              padding: const pw.EdgeInsets.only(bottom: 3.0 * PdfPageFormat.mm),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey700)),
              ),
              child: pw.Text('Histórico de Égua - Nobryo', style: pw.Theme.of(context).defaultTextStyle.copyWith(color: PdfColors.grey)),
            );
          },
          build: (pw.Context context) => _construirConteudoPdfEgua(egua, historico),
        ),
      );

      final bytes = await pdf.save();
      final filePath = await _salvarArquivo(bytes, egua.nome, 'pdf');
      _abrirArquivo(filePath, "PDF", context);
    } catch (e) {
      _mostrarErro("PDF", e, context);
    }
  }
  
  Future<void> exportarParaExcel(Egua egua, List<Manejo> historico, BuildContext context) async {
    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];
      _adicionarCabecalhosExcelEgua(sheet, egua);
      _adicionarDadosExcelEgua(sheet, historico);
      sheet.setColAutoFit(0);
      sheet.setColAutoFit(1);
      sheet.setColAutoFit(2);
      sheet.setColAutoFit(3);

      final List<int>? bytes = excel.save();

      if (bytes != null) {
        final filePath = await _salvarArquivo(bytes, egua.nome, 'xlsx');
        _abrirArquivo(filePath, "Excel", context);
      } else {
        throw Exception("Falha ao gerar os bytes do arquivo Excel.");
      }
    } catch (e) {
      _mostrarErro("Excel", e, context);
    }
  }

  Future<String> _salvarArquivo(List<int> bytes, String nomeArquivo, String extensao) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final sanitizedName = nomeArquivo.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    final filePath = "${directory.path}/Historico_${sanitizedName}_$timestamp.$extensao";
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  }

  void _abrirArquivo(String filePath, String tipo, BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Arquivo $tipo gerado! Abrindo..."),
      backgroundColor: Colors.green,
    ));
    final openResult = await OpenFile.open(filePath);
    if (openResult.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Não foi possível encontrar um app para abrir o arquivo. Erro: ${openResult.message}"),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 7),
      ));
    }
  }

  void _mostrarErro(String tipo, Object e, BuildContext context) {
    print("Erro ao exportar para $tipo: $e");
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Erro ao exportar para $tipo: $e"),
      backgroundColor: Colors.red,
    ));
  }
  
  List<pw.Widget> _construirConteudoPdfEgua(Egua egua, List<Manejo> historico) {
    List<pw.Widget> widgets = [];
    widgets.add(pw.Text('Histórico de Manejos - ${egua.nome}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)));
    widgets.add(pw.SizedBox(height: 16));
    widgets.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _infoPdf('RP:', egua.rp),
      _infoPdf('Pelagem:', egua.pelagem),
      _infoPdf('Status:', egua.statusReprodutivo),
    ]));
    widgets.add(pw.SizedBox(height: 24));
    widgets.add(pw.Text('Manejos Realizados', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)));
    widgets.add(pw.Divider(height: 10, thickness: 1));
    for (final manejo in historico) {
      widgets.add(_blocoDeManejoPdf(manejo));
    }
    return widgets;
  }
  
  pw.Widget _blocoDeManejoPdf(Manejo manejo) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(5)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('${DateFormat('dd/MM/yyyy').format(manejo.dataAgendada)} - ${manejo.tipo}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        _buildDetalhesPdf(manejo.detalhes),
      ]),
    );
  }

  pw.Widget _infoPdf(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2, bottom: 2),
      child: pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TextSpan(text: ' $value'),
      ])),
    );
  }
  
  void _adicionarCabecalhosExcelEgua(Sheet sheet, Egua egua) {
    sheet.merge(CellIndex.indexByString("A1"), CellIndex.indexByString("D1"));
    final cellTitle = sheet.cell(CellIndex.indexByString("A1"));
    cellTitle.value = "Histórico de Manejos - ${egua.nome}";
    cellTitle.cellStyle = CellStyle(bold: true, fontSize: 16, verticalAlign: VerticalAlign.Center);
    sheet.cell(CellIndex.indexByString("A3")).value = "Proprietário:";
    sheet.cell(CellIndex.indexByString("B3")).value = egua.proprietario;
    sheet.cell(CellIndex.indexByString("A4")).value = "RP:";
    sheet.cell(CellIndex.indexByString("B4")).value = egua.rp;
    sheet.cell(CellIndex.indexByString("A5")).value = "Pelagem:";
    sheet.cell(CellIndex.indexByString("B5")).value = egua.pelagem;
    sheet.cell(CellIndex.indexByString("A6")).value = "Status Atual:";
    sheet.cell(CellIndex.indexByString("B6")).value = egua.statusReprodutivo;
    final headers = ["Data", "Tipo de Manejo", "Detalhes", "Observações"];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 7));
      cell.value = headers[i];
      cell.cellStyle = CellStyle(bold: true, backgroundColorHex: "#FF796043", fontColorHex: "#FFFFFFFF", textWrapping: TextWrapping.WrapText);
    }
  }

  void _adicionarDadosExcelEgua(Sheet sheet, List<Manejo> historico) {
    for (var i = 0; i < historico.length; i++) {
      final manejo = historico[i];
      final rowIndex = i + 8;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = DateFormat('dd/MM/yyyy').format(manejo.dataAgendada);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = manejo.tipo;
      final detalhesString = _getFormattedDetalhesExcel(manejo.detalhes);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value = detalhesString;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = manejo.detalhes['observacao'] ?? '';
    }
  }

  pw.Widget _buildDetalhesPdf(Map<String, dynamic> detalhes) {
    const labelMap = {
      'resultado': 'Resultado', 'diasPrenhe': 'Dias de Prenhez', 'garanhao': 'Garanhão',
      'dataHora': 'Data/Hora da Inseminação', 'litros': 'Litros', 'medicamento': 'Medicamento',
      'ovarioDireito': 'Ovário Direito', 'ovarioDireitoTamanho': 'Tamanho Ov. Direito',
      'ovarioEsquerdo': 'Ovário Esquerdo', 'ovarioEsquerdoTamanho': 'Tamanho Ov. Esquerdo',
      'edema': 'Edema', 'utero': 'Útero', 'idadeEmbriao': 'Idade do Embrião',
      'doadora': 'Doadora', 'avaliacaoUterina': 'Avaliação Uterina', 'observacao': 'Observação',
    };

    String formatValue(dynamic value) {
      if (value is String) {
        try {
          final dt = DateTime.parse(value);
          return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dt);
        } catch (e) {
          return value;
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

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: detailEntries.map((entry) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2.0),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: "${labelMap[entry.key]}: ",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: formatValue(entry.value)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _getFormattedDetalhesExcel(Map<String, dynamic> detalhes) {
    const labelMap = {
      'resultado': 'Resultado', 'diasPrenhe': 'Dias de Prenhez', 'garanhao': 'Garanhão',
      'dataHora': 'Data/Hora da Inseminação', 'litros': 'Litros', 'medicamento': 'Medicamento',
      'ovarioDireito': 'Ovário Direito', 'ovarioDireitoTamanho': 'Tamanho Ov. Direito',
      'ovarioEsquerdo': 'Ovário Esquerdo', 'ovarioEsquerdoTamanho': 'Tamanho Ov. Esquerdo',
      'edema': 'Edema', 'utero': 'Útero', 'idadeEmbriao': 'Idade do Embrião',
      'doadora': 'Doadora', 'avaliacaoUterina': 'Avaliação Uterina',
    };
    
    String formatValue(dynamic value) {
      if (value is String) {
        try {
          final dt = DateTime.parse(value);
          return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dt);
        } catch (e) {
          return value;
        }
      }
      return value.toString();
    }

    final detailEntries = detalhes.entries
        .where((entry) =>
            entry.value != null &&
            entry.value.toString().isNotEmpty &&
            labelMap.containsKey(entry.key))
        .map((entry) => "${labelMap[entry.key]}: ${formatValue(entry.value)}")
        .join('\n');

    return detailEntries;
  }
}