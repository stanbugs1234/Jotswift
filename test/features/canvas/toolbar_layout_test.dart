import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/canvas/toolbar_layout.dart';

void main() {
  test('a saved layout keeps its order and hides; new tools join the end', () {
    final layout = ToolbarLayout.fromJson({
      'order': ['lasso', 'pen', 'gone-in-a-later-version'],
      'hidden': ['lasso', 'pen'],
    });
    expect(layout.order.take(2), [ToolbarTool.lasso, ToolbarTool.pen]);
    expect(layout.order.toSet(), ToolbarTool.values.toSet());
    expect(layout.hidden, {ToolbarTool.lasso}, reason: 'the pen stays');
    expect(layout.shown.first, ToolbarTool.pen);

    final back = ToolbarLayout.fromJson(layout.toJson());
    expect(back.order, layout.order);
    expect(back.hidden, layout.hidden);
  });
}
