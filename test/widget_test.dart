import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppStorage.instance.init();

    await tester.pumpWidget(const TalutaluApp());
    await tester.pump();
    // Let the splash screen's staged Future.delayed sequence (~2.9s total)
    // fire before teardown, otherwise the binding reports pending timers.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
  });
}
