import 'package:flutter_test/flutter_test.dart';
import 'package:uno_stack/main.dart';

void main() {
  testWidgets('UnoStackGame smoke test', (WidgetTester tester) async {
    // Construir nuestra aplicación y disparar un cuadro.
    await tester.pumpWidget(const UnoStackGameApp());

    // Verificar que aparece el título y el botón principal de la HomeScreen.
    expect(find.text('Uno Stack Game'), findsOneWidget);
    expect(find.text('Iniciar Partida de Prueba'), findsOneWidget);
  });
}