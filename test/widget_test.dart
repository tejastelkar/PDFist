import 'package:flutter_test/flutter_test.dart';
import 'package:pdfo/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PDFistApp());
    expect(find.byType(PDFistApp), findsOneWidget);
  });
}
