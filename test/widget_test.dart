import 'package:flutter_test/flutter_test.dart';
import 'package:stop_snoozer/app/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const StopSnoozerApp());
    expect(find.byType(StopSnoozerApp), findsOneWidget);
  });
}
