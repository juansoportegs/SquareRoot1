import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Asegúrate de tener este archivo generado
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializamos Firebase pasando las opciones de la plataforma actual (Web, Android, etc.)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SquareRoot1App());
}

class SquareRoot1App extends StatelessWidget {
  const SquareRoot1App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raíz cuadrada de 1',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}