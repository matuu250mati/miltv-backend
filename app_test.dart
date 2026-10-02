import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:miltv_universal/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MILTV starts and exposes the authentication screen', (tester) async {
    await tester.pumpWidget(const MiltvApp(cloudAuth: false));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('🔥 MILTV'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Ingresar'), findsWidgets);
  });
}
