import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class InvitationService {
  final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://uno-stack-2by2-default-rtdb.europe-west1.firebasedatabase.app',
  ).ref();

  Future<bool> sendGameInvitation(String targetEmail, String roomCode) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      String safeTargetKey = AuthService.safeUserKey(targetEmail);
      String senderName = currentUser.displayName ?? 'Un jugador';

      DataSnapshot snapshot = await _dbRef.child('users/$safeTargetKey').get();

      if (!snapshot.exists) {
        debugPrint('El usuario no está registrado en la app.');
        return false;
      }

      await _dbRef.child('invitations/$safeTargetKey').set({
        'senderName': senderName,
        'roomCode': roomCode,
        'timestamp': ServerValue.timestamp,
      });

      return true;
    } catch (e) {
      debugPrint('Error al enviar la invitación: $e');
      return false;
    }
  }

  Future<bool> sendGameInvitationByNick(String nick, String roomCode) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      String normalizedNick = AuthService.normalizeNick(nick);
      if (normalizedNick.isEmpty) return false;

      // El nick único resuelve al safeKey del usuario desde el índice nicks/
      DataSnapshot nickSnapshot = await _dbRef.child('nicks/$normalizedNick').get();
      if (!nickSnapshot.exists || nickSnapshot.value == null) {
        debugPrint('El nick no existe: $nick');
        return false;
      }

      String safeTargetKey = (nickSnapshot.value as String);
      String senderName = currentUser.displayName ?? 'Un jugador';

      await _dbRef.child('invitations/$safeTargetKey').set({
        'senderName': senderName,
        'roomCode': roomCode,
        'timestamp': ServerValue.timestamp,
      });

      return true;
    } catch (e) {
      debugPrint('Error al enviar la invitación por nick: $e');
      return false;
    }
  }
}