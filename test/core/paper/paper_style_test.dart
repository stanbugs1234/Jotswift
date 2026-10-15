import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/paper/basic_papers.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/paper_picker.dart';
import 'package:notely/features/shelf/cover_designs.dart';

void main() {
  group('PaperStyle', () {
    test('survives saving and loading', () {
      for (final paper in basicPapers) {
        expect(PaperStyle.fromMap(paper.toMap()), paper);
      }
    });

    test('a damaged paper is ignored instead of breaking the page', () {
      expect(PaperStyle.fromMap(null), isNull);
      expect(PaperStyle.fromMap('lined'), isNull);
      expect(
        PaperStyle.fromMap({
          'color': 0xFFFFFFFF,
          'lineColor': 0xFF000000,
          'pattern': 'hexagons',
          'spacing': 30,
        }),
        isNull,
      );
    });

    test('spacing is kept within the allowed range', () {
      final paper = PaperStyle.fromMap({
        'color': 0xFFFFFFFF,
        'lineColor': 0xFF000000,
        'pattern': 'grid',
        'spacing': 2,
      });
      expect(paper!.spacing, PaperStyle.minSpacing);
    });
  });

  group('basic papers', () {
    test('every pattern comes in every color', () {
      expect(
        basicPapers.length,
        PaperPattern.values.length * BasicPaperColor.values.length,
      );
    });

    test('only lined papers have a margin line', () {
      for (final paper in basicPapers) {
        final lined =
            paper.pattern == PaperPattern.lined ||
            paper.pattern == PaperPattern.narrowLined;
        expect(paper.marginColor != null, lined, reason: '${paper.pattern}');
      }
    });
  });

  group('Notebook', () {
    test('a notebook saved before covers existed becomes a color cover', () {
      final old = Notebook.fromMap('n1', {
        'title': 'School',
        'color': 0xFFC8553D,
        'createdAt': 1,
        'updatedAt': 2,
      });

      expect(old.cover, const NotebookCover.color(0xFFC8553D));
      expect(old.paper, isNull);
      expect(old.paperSize, PaperSize.letter);
      expect(old.orientation, PaperOrientation.portrait);
    });

    test('still saves the cover color for older app versions', () {
      final nb = const NewNotebook(
        title: 'Trip',
        cover: NotebookCover.photo('covers/n1.jpg', color: 0xFF1F8A99),
      ).build('n1', 0);

      final map = nb.toMap();
      expect(map['color'], 0xFF1F8A99);
      expect(Notebook.fromMap('n1', map).cover, nb.cover);
    });

    test('an art cover without its image falls back to its color', () {
      final cover = NotebookCover.fromMap({
        'kind': 'art',
        'color': 0xFF2E7D5B,
      }, fallbackColor: 0);
      expect(cover, const NotebookCover.color(0xFF2E7D5B));
    });

    test('unknown sizes fall back to letter portrait', () {
      final nb = Notebook.fromMap('n1', {
        'paperSize': 'scroll',
        'orientation': 'diagonal',
      });
      expect(nb.paperSize, PaperSize.letter);
      expect(nb.orientation, PaperOrientation.portrait);
    });
  });

  test('copyWith changes only what is given', () {
    const paper = PaperStyle(
      color: Color(0xFFFFFFFF),
      lineColor: Color(0xFFC9D6EA),
      pattern: PaperPattern.lined,
      spacing: 32,
    );
    expect(paper.copyWith(spacing: 40).spacing, 40);
    expect(paper.copyWith(spacing: 40).pattern, PaperPattern.lined);
  });

  group('PaperSize', () {
    test('Letter keeps the size pages had before sizes existed', () {
      expect(
        PaperSize.letter.dimensions(PaperOrientation.portrait),
        const Size(1404, 1872),
      );
    });

    test('landscape swaps width and height', () {
      final portrait = PaperSize.a4.dimensions(PaperOrientation.portrait);
      final landscape = PaperSize.a4.dimensions(PaperOrientation.landscape);
      expect(landscape, Size(portrait.height, portrait.width));
    });
  });

  group('PaperPicker.make', () {
    test('a basic color gives the same paper as the basic set', () {
      for (final pattern in PaperPattern.values) {
        expect(
          PaperPicker.make(pattern, BasicPaperColor.cream.color),
          basicPaper(pattern, BasicPaperColor.cream),
        );
      }
    });

    test('custom colors get ruling that can be seen', () {
      for (final color in const [Color(0xFFFFE0F0), Color(0xFF102040)]) {
        final paper = PaperPicker.make(PaperPattern.lined, color);
        expect(paper.lineColor, isNot(color));
        expect(paper.marginColor, isNotNull);
        expect(
          (paper.lineColor.computeLuminance() - color.computeLuminance()).abs(),
          greaterThan(0.02),
        );
      }
    });

    test('spacing follows the choice', () {
      final narrow = PaperPicker.make(
        PaperPattern.grid,
        BasicPaperColor.white.color,
        spacing: PaperSpacing.narrow,
      );
      expect(narrow.spacing, lessThan(defaultSpacing(PaperPattern.grid)));
    });
  });

  test('cover design ids are found again, unknown ones are not', () {
    for (final d in CoverDesign.values) {
      expect(CoverDesign.byId(d.id), d);
    }
    expect(CoverDesign.byId('design_hologram'), isNull);
    expect(CoverDesign.byId(null), isNull);
  });
}
