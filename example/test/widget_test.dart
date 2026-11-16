import 'package:flutter_blackbox/flutter_blackbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blackbox_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('example renders and sends actions to BlackBox', (tester) async {
    BlackBox.setup(enabled: true);
    try {
      await tester.pumpWidget(const MyApp());

      expect(find.text('BlackBox Example'), findsOneWidget);
      expect(find.text('Log info message'), findsOneWidget);

      await tester.tap(find.text('Log info message'));
      await tester.pump();

      expect(
        BlackBox.instance.logStore.entries
            .any((entry) => entry.message == 'User opened home screen'),
        isTrue,
      );
    } finally {
      BlackBox.dispose();
    }
  });
}
