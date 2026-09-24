import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  Future<void> initNotifications() async {
    // 1. Solicitar permisos de notificación (especialmente necesario en iOS y Android 13+)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('Usuario autorizó las notificaciones');

      // 2. Obtener el Token FCM único de este dispositivo
      String? token = await _firebaseMessaging.getToken();
      debugPrint('FCM Token: $token');

      // 3. Guardar el token asociado al usuario actual en la Realtime Database
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null && token != null) {
        // Limpiamos el correo o usamos el UID como clave segura
        String safeUserKey = AuthService.safeUserKey(user.email ?? user.uid);
        await _dbRef.child('users/$safeUserKey/fcmToken').set(token);
      }
    } else {
      debugPrint('El usuario denegó los permisos de notificación');
    }

    // 4. Escuchar notificaciones cuando la app está abierta en primer plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Notificación recibida en primer plano: ${message.notification?.title}');
    });
  }
}