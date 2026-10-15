@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/shelf/cover_designs.dart';
import 'package:notely/features/shelf/cover_view.dart';

/// Every cover design in a light and a dark color, plus plain covers. No
/// text, so the image is the same on every operating system.
void main() {
  testWidgets('cover designs', (tester) async {
    tester.view
      ..physicalSize = const Size(840, 340)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget cover(NotebookCover c) => Padding(
      padding: const EdgeInsets.all(10),
      child: SizedBox(width: 100, child: CoverView(cover: c)),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: const Color(0xFFF4F5F7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final color in [0xFF2C4A7C, 0xFFF2EBDD])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      cover(NotebookCover.color(color)),
                      for (final d in CoverDesign.values)
                        cover(NotebookCover.art(d.id, color: color)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(ColoredBox).first,
      matchesGoldenFile('covers/designs.png'),
    );
  });
}
