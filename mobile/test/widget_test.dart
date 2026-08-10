import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('FantaEventiApp loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FantaEventiApp(isLoggedIn: false));
    expect(find.text('Fanta Eventi 2.0'), findsOneWidget);
  });
}
