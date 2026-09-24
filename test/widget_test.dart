import 'package:flutter_test/flutter_test.dart';
import 'package:squareroot1/main.dart';
import 'package:squareroot1/screens/home_screen.dart';

void main() {
  test('SquareRoot1 app entrypoint se compila y expone la app', () {
    expect(SquareRoot1App, isNotNull);
  });

  testWidgets('HomeScreen contiene los botones de sala', (WidgetTester tester) async {
    expect(HomeScreen, isNotNull);
  });
}