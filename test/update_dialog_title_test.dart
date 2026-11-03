import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The downloading dialog's title stays on one line on a 360 dp phone (ROG 3), in the longest locale.
void main() {
  testWidgets('long update title stays on one line at 360 dp', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const text = 'A transferir a atualização…';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AlertDialog(
          title: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(text, maxLines: 1)),
          content: LinearProgressIndicator(),
        ),
      ),
    ));
    final box = tester.renderObject<RenderBox>(find.text(text));
    final line = TextPainter(text: const TextSpan(text: 'A'), textDirection: TextDirection.ltr)..layout();
    expect(box.size.height < line.height * 2 * 1.6, isTrue);
  });
}
