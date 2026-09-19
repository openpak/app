import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openpak/theme.dart';
import 'package:openpak/widgets.dart';

import 'localized.dart';

Widget wrap(Widget child) =>
    localizedApp(theme: openPakLight(), home: Scaffold(body: child));

void main() {
  // The tint is what a person reads first, so each state has to reach the row
  // as a different colour — an online friend and an offline one looking alike
  // would defeat the whole shape.
  testWidgets('each state tints the row differently', (tester) async {
    final seen = <RowState, Color>{};
    for (final state in RowState.values) {
      await tester.pumpWidget(
        wrap(StateRow(name: 'Leia', pill: 'Online', state: state)),
      );
      final box = tester.widget<Container>(
        find.ancestor(of: find.text('Leia'), matching: find.byType(Container)).last,
      );
      seen[state] = ((box.decoration as BoxDecoration).color)!;
    }
    expect(seen.values.toSet().length, RowState.values.length,
        reason: 'two states share a tint: $seen');
  });

  testWidgets('the row shows its name and its pill', (tester) async {
    await tester.pumpWidget(
      wrap(const StateRow(name: 'Stardew Valley', pill: '2 players', state: RowState.ok)),
    );
    expect(find.text('Stardew Valley'), findsOneWidget);
    expect(find.text('2 players'), findsOneWidget);
  });

  testWidgets('a long name is truncated rather than overflowing', (tester) async {
    await tester.pumpWidget(
      wrap(StateRow(name: 'A' * 200, pill: 'Offline', state: RowState.idle)),
    );
    // No overflow error is the assertion; a row that overflows paints a yellow
    // stripe on a real phone.
    expect(tester.takeException(), isNull);
  });
}
