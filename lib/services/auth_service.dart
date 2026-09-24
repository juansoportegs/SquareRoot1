import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  
  // Referencia a la base de datos usando la URL explícita para evitar conflictos web
  final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://uno-stack-2by2-default-rtdb.europe-west1.firebasedatabase.app',
  ).ref();

  // Método para iniciar sesión con Google
  Future<User?> signInWithGoogle() async {
    try {
      // 1. Abre la ventana emergente para elegir cuenta de Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // Si el usuario cancela, no hace nada

      // 2. Obtiene las credenciales de la cuenta seleccionada
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // 3. Crea la credencial de acceso compatible con Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Inicia sesión en Firebase usando las credenciales de Google
      final UserCredential userCredential = await _auth.signInWithCredential(credential);

      // 5. Si el login es exitoso, guardamos el token FCM y el nombre en la BD
      if (userCredential.user != null) {
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          String safeUserKey = userCredential.user!.email?.replaceAll('.', ',') ?? userCredential.user!.uid;
          await _dbRef.child('users/$safeUserKey/fcmToken').set(token);
          await _dbRef.child('users/$safeUserKey/name').set(userCredential.user!.displayName ?? 'Jugador');
          await _dbRef.child('users/$safeUserKey/email').set(userCredential.user!.email ?? '');
        }
      }

      return userCredential.user;
    } catch (e) {
      debugPrint('Error al iniciar sesión con Google: $e');
      return null;
    }
  }

  // Método para cerrar sesión
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}