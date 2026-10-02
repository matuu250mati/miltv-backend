import 'package:flutter_test/flutter_test.dart';
import 'package:miltv_universal/main.dart';

void main() {
  testWidgets('MILTV authentication screen is keyboard friendly', (tester) async {
    await tester.pumpWidget(const MiltvApp(cloudAuth: false));
    await tester.pump();
    expect(find.text('🔥 MILTV'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Crear una cuenta'), findsOneWidget);
  });
}
