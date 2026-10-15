@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/paper/basic_papers.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/core/skins/widgets/paper.dart';

/// Every ruling, on white and on dark paper. No text, so the image is the
/// same on every operating system.
void main() {
  testWidgets('paper patterns', (tester) async {
    tester.view
      ..physicalSize = const Size(1442, 632)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget sheet(PaperStyle paper) => Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 190,
        height: 300,
        child: CustomPaint(painter: PaperPainter(paper)),
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF8A8F99),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final color in [BasicPaperColor.white, BasicPaperColor.dark])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final pattern in PaperPattern.values)
                      sheet(basicPaper(pattern, color)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(ColoredBox).first,
      matchesGoldenFile('paper/patterns.png'),
    );
  });
}
