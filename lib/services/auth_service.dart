import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  static String safeUserKey(String? email) {
    return email?.trim().toLowerCase().replaceAll('.', ',') ?? '';
  }

  static String normalizeNick(String nick) {
    return nick.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  static bool isValidNick(String nick) {
    final normalized = normalizeNick(nick);
    if (normalized.isEmpty) return false;
    return RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(normalized);
  }

  Future<String?> getUserNick(String safeUserKey) async {
    final snapshot = await _dbRef.child('users/$safeUserKey/nick').get();
    if (snapshot.exists && snapshot.value is String) {
      return snapshot.value as String;
    }
    return null;
  }

  Future<bool> claimNick(String nick, String safeUserKey) async {
    if (!isValidNick(nick)) return false;
    final normalized = normalizeNick(nick);

    // El nodo nicks/<normalizedNick> actúa como índice único: solo un
    // usuario puede reclamarlo. Si ya existe, se aborta la transacción.
    final nickRef = _dbRef.child('nicks/$normalized');
    final result = await nickRef.runTransaction((current) {
      if (current != null) return Transaction.abort();
      return Transaction.success(safeUserKey);
    });

    if (!result.committed) return false;

    await _dbRef.child('users/$safeUserKey').update({'nick': normalized});
    return true;
  }
  
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

      // 5. Si el login es exitoso, guardamos el nombre y email en la BD
      if (userCredential.user != null) {
        String safeUserKey = AuthService.safeUserKey(userCredential.user!.email ?? userCredential.user!.uid);
        await _dbRef.child('users/$safeUserKey/name').set(userCredential.user!.displayName ?? 'Jugador');
        await _dbRef.child('users/$safeUserKey/email').set(userCredential.user!.email ?? '');

        // FCM solo en plataformas soportadas; nunca debe bloquear el login
        final supportedForFcm = defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS;
        if (supportedForFcm) {
          try {
            String? token = await FirebaseMessaging.instance.getToken();
            if (token != null) {
              await _dbRef.child('users/$safeUserKey/fcmToken').set(token);
            }
          } catch (e) {
            debugPrint('Error al obtener el token FCM: $e');
          }
        } else {
          debugPrint('FCM no soportado en ${defaultTargetPlatform.name}, se omite.');
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