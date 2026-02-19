import 'package:flutter/material.dart';
import '../models/grid_model.dart';

class GridPainter extends CustomPainter {
  final GridModel grid;
  final double minTemp; // Pro barvovou škálu
  final double maxTemp; // Pro barvovou škálu
  final bool showTemperatureValues; // Zda zobrazovat číselné hodnoty
  final double zoomScale; // Aktuální měřítko (zoom)

  GridPainter({
    required this.grid,
    this.minTemp = 0,
    this.maxTemp = 30,
    this.showTemperatureValues = false,
    this.zoomScale = 1.0,
  }) : super(repaint: grid); // Optimalizace: překreslí se jen při změně gridu

  @override
  void paint(Canvas canvas, Size size) {
    // Dynamický výpočet velikosti buňky podle velikosti plátna
    final double cellSize = size.shortestSide / grid.gridSize;
    final paint = Paint();

    // Optimalizace: Vykreslení
    for (int y = 0; y < grid.gridSize; y++) {
      for (int x = 0; x < grid.gridSize; x++) {
        final cellRect = Rect.fromLTWH(
          x * cellSize,
          y * cellSize,
          cellSize,
          cellSize,
        );

        // 1. Získáme barvu materiálu
        final materialColor = grid.getMaterialAt(x, y).color;

        // 2. Vypočítáme barvu teploty
        final temp = grid.getTemperatureAt(x, y);
        final normalizedTemp = ((temp - minTemp) / (maxTemp - minTemp)).clamp(
          0.0,
          1.0,
        );

        Color tempOverlay;
        if (normalizedTemp < 0.5) {
          // Studená (modrá) -> Neutrální
          tempOverlay = Color.lerp(
            Colors.blue.shade800,
            Colors.transparent,
            normalizedTemp * 2,
          )!;
        } else {
          // Neutrální -> Horká (červená)
          tempOverlay = Color.lerp(
            Colors.transparent,
            Colors.red.shade800,
            (normalizedTemp - 0.5) * 2,
          )!;
        }

        // 3. Spojíme barvy (overlay přes materiál)
        final finalColor = Color.alphaBlend(
          tempOverlay.withValues(alpha: 0.5),
          materialColor,
        );

        paint.color = finalColor;
        canvas.drawRect(cellRect, paint);

        // 4. Vykreslení textu s teplotou (pokud je povoleno a buňka je dost velká)
        // Použijeme zoomScale pro rozhodnutí o viditelnosti, ale velikost písma může být fixní nebo škálovatelná
        if (showTemperatureValues && (cellSize * zoomScale) > 20) {
          final textSpan = TextSpan(
            text: temp.toStringAsFixed(1), // Jedno desetinné místo
            style: TextStyle(
              color: normalizedTemp > 0.5
                  ? Colors.white
                  : Colors.black, // Kontrastní barva
              fontSize:
                  cellSize *
                  0.4, // Velikost písma podle buňky (bude se škálovat s zoomem automaticky přes matici)
              fontWeight: FontWeight.bold,
            ),
          );
          final textPainter = TextPainter(
            text: textSpan,
            textDirection: TextDirection.ltr,
          );
          textPainter.layout(minWidth: 0, maxWidth: cellSize);
          final textOffset = Offset(
            (x * cellSize) + (cellSize - textPainter.width) / 2,
            (y * cellSize) + (cellSize - textPainter.height) / 2,
          );
          textPainter.paint(canvas, textOffset);
        }
      }
    }

    // Volitelně: vykreslit mřížku pro lepší vizualizaci buněk
    paint.color = Colors.black.withValues(alpha: 0.1);
    paint.strokeWidth = 1.0;

    // Kreslíme čáry pouze pokud je buňka dostatečně velká, aby to mělo smysl (i s ohledem na zoom)
    if ((cellSize * zoomScale) > 3.0) {
      for (int i = 0; i <= grid.gridSize; i++) {
        final pos = i * cellSize;
        canvas.drawLine(Offset(pos, 0), Offset(pos, size.height), paint);
        canvas.drawLine(Offset(0, pos), Offset(size.width, pos), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    // Díky super(repaint: grid) se toto volá méně často, ale pro jistotu:
    return oldDelegate.grid != grid ||
        oldDelegate.minTemp != minTemp ||
        oldDelegate.maxTemp != maxTemp ||
        oldDelegate.showTemperatureValues != showTemperatureValues ||
        oldDelegate.zoomScale != zoomScale;
  }
}
