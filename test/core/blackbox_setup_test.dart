import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/flutter_blackbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlackBox setup & store resetting', () {
    tearDown(() {
      BlackBox.dispose();
    });

    test('setup clears all stores on re-initialisation', () {
      // 1. Initial setup
      BlackBox.setup(enabled: true);

      // 2. Add some mock data into various stores
      BlackBox.log('Test log');
      BlackBox.instance.navigationStore.onPush('/route', null);
      BlackBox.instance.rebuildStore.record('WidgetA');
      BlackBox.logSocketEvent('my_event', 'my_data');

      // Verify they are populated
      expect(BlackBox.instance.logStore.entries, isNotEmpty);
      expect(BlackBox.instance.navigationStore.currentStack, isNotEmpty);
      expect(BlackBox.instance.rebuildStore.counts, isNotEmpty);
      expect(BlackBox.instance.socketStore.events, isNotEmpty);

      // 3. Call setup again
      BlackBox.setup(enabled: true);

      // 4. Verify they are all cleared
      expect(BlackBox.instance.logStore.entries, isEmpty);
      expect(BlackBox.instance.navigationStore.currentStack, isEmpty);
      expect(BlackBox.instance.rebuildStore.counts, isEmpty);
      expect(BlackBox.instance.socketStore.events, isEmpty);
    });
  });
}
