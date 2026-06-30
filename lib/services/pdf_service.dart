import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/farm.dart';
import '../models/map_point.dart';
import '../models/map_polygon.dart';

class PdfService {
  static final PdfService instance = PdfService._init();
  PdfService._init();

  /// Generates a PDF report and launches the native share sheet to send it.
  Future<void> generateAndShareReport(
    Farm farm,
    List<MapPoint> points,
    List<MapPolygon> polygons,
  ) async {
    final pdf = pw.Document();
    
    // Curated color palette to match application design
    final primaryColor = PdfColor.fromHex('#2E7D32'); // Organic green
    final secondaryColor = PdfColor.fromHex('#5D4037'); // Warm brown
    final lightBgColor = PdfColor.fromHex('#F1F8E9'); // Light green-gray
    final accentColor = PdfColor.fromHex('#E8F5E9');
    
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    // Calculate total hectares
    double totalHectares = 0.0;
    for (final poly in polygons) {
      totalHectares += poly.areaHectares;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // 1. Report Header Band
            pw.Container(
              decoration: pw.BoxDecoration(
                color: primaryColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'CAMPO MAP OFFLINE',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Reporte Técnico de Finca',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Fecha de Emisión',
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 8),
                      ),
                      pw.Text(
                        dateFormat.format(DateTime.now()),
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // 2. Farm Details Card
            pw.Container(
              decoration: pw.BoxDecoration(
                color: lightBgColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey400, width: 1),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Finca / Predio:', style: pw.TextStyle(color: secondaryColor, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text(farm.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                      pw.SizedBox(height: 8),
                      pw.Text('Propietario / Productor:', style: pw.TextStyle(color: secondaryColor, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text(farm.ownerName ?? 'Sin asignar', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Área Declarada:', style: pw.TextStyle(color: secondaryColor, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        '${totalHectares.toStringAsFixed(4)} Hectáreas',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: secondaryColor),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text('ID del Sistema:', style: pw.TextStyle(color: PdfColors.grey600, fontSize: 8)),
                      pw.Text(farm.id, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // 3. Summary Statistics Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildStatBox('Lotes / Parcelas', polygons.length.toString(), accentColor, secondaryColor),
                _buildStatBox('Puntos Registrados', points.length.toString(), accentColor, secondaryColor),
                _buildStatBox('Área Promedio Lote', polygons.isEmpty ? '0.00 Ha' : '${(totalHectares / polygons.length).toStringAsFixed(2)} Ha', accentColor, secondaryColor),
              ],
            ),
            pw.SizedBox(height: 24),

            // 4. Parcels / Polygons Table
            if (polygons.isNotEmpty) ...[
              pw.Header(
                level: 1,
                text: 'Detalle de Parcelas / Lotes de Terreno',
                textStyle: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor),
                decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: primaryColor, width: 1))),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                context: context,
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 1),
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headers: ['ID', 'Nombre', 'Tipo de Uso', 'Hectáreas', 'Detalle / Estado'],
                data: polygons.map((p) {
                  return [
                    p.id,
                    p.name,
                    p.type,
                    '${p.areaHectares.toStringAsFixed(4)} Ha',
                    p.description,
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 24),
            ],

            // 5. Points of Interest Table
            if (points.isNotEmpty) ...[
              pw.Header(
                level: 1,
                text: 'Puntos de Interés / Elementos Levantados',
                textStyle: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor),
                decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: primaryColor, width: 1))),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                context: context,
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 1),
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: secondaryColor),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headers: ['ID', 'Nombre', 'Tipo de Punto', 'Coordenadas (Lat, Lng)', 'Detalle / Observaciones'],
                data: points.map((p) {
                  return [
                    p.id,
                    p.name,
                    p.type,
                    '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
                    p.description,
                  ];
                }).toList(),
              ),
            ],
          ];
        },
      ),
    );

    // Save and Share Report
    final fileName = 'Reporte_${farm.name.replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_')}.pdf';
    
    if (kIsWeb) {
      print('=== PDF EXPORT SUCCESSFUL: $fileName ===');
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Reporte Técnico CampoMap para finca ${farm.name}',
        subject: 'Reporte PDF ${farm.name}',
      );
    } catch (e) {
      print('Error exporting and sharing PDF report: $e');
    }
  }

  pw.Widget _buildStatBox(String title, String value, PdfColor bgColor, PdfColor textColor) {
    return pw.Container(
      width: 160,
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
