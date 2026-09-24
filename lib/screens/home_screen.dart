import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'game_screen.dart';
import '../services/auth_service.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final AuthService _authService = AuthService();
  
  User? get currentUser => FirebaseAuth.instance.currentUser;
  StreamSubscription? _invitationSubscription;

  @override
  void initState() {
    super.initState();
    if (currentUser != null && currentUser!.displayName != null) {
      _nameController.text = currentUser!.displayName!;
    }
    _listenForInvitations();
  }

  void _listenForInvitations() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    String safeUserKey = AuthService.safeUserKey(user.email);
    _invitationSubscription = FirebaseDatabase.instance
        .ref()
        .child('invitations/$safeUserKey')
        .onValue
        .listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data != null) {
          String senderName = data['senderName'] ?? 'Alguien';
          String roomCode = data['roomCode'] ?? '';

          _showInvitationDialog(senderName, roomCode);
          event.snapshot.ref.remove();
        }
      }
    });
  }

  void _showInvitationDialog(String senderName, String roomCode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B2F),
        title: const Text('¡Invitación a partida!', style: TextStyle(color: Colors.white)),
        content: Text(
          '$senderName te ha invitado a unirte a su sala ($roomCode).',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Rechazar', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              Navigator.pop(context);
              _codeController.text = roomCode;
              _joinRoom();
            },
            child: const Text('Unirme', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    User? user = await _authService.signInWithGoogle();
    if (user != null) {
      setState(() {
        if (user.displayName != null) {
          _nameController.text = user.displayName!;
        }
      });
      _listenForInvitations();
      _showSnackBar('¡Bienvenido, ${user.displayName ?? 'Jugador'}!');
    }
  }

  Future<void> _handleSignOut() async {
    await _authService.signOut();
    _invitationSubscription?.cancel();
    setState(() {
      _nameController.clear();
    });
    _showSnackBar('Sesión cerrada');
  }

  void _createRoom() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('Por favor, introduce tu apodo o inicia sesión con Google.');
      return;
    }

    final roomCode = _generateRoomCode();
    _codeController.text = roomCode;
    _navigateToGame(roomCode: roomCode, playerName: name, isHost: true);
  }

  void _joinRoom() {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();

    if (name.isEmpty) {
      _showSnackBar('Por favor, introduce tu apodo o inicia sesión con Google.');
      return;
    }
    if (code.length != 4) {
      _showSnackBar('El código de la sala debe tener 4 caracteres.');
      return;
    }

    _navigateToGame(roomCode: code, playerName: name, isHost: false);
  }

  void _navigateToGame({
    required String roomCode,
    required String playerName,
    required bool isHost,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameScreen(
          roomCode: roomCode,
          playerName: playerName,
          isHost: isHost,
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.grey.shade900,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _invitationSubscription?.cancel();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B2F),
        elevation: 0,
        actions: [
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: currentUser!.photoURL != null
                        ? NetworkImage(currentUser!.photoURL!)
                        : null,
                    child: currentUser!.photoURL == null
                        ? const Icon(Icons.person, size: 16)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white70),
                    tooltip: 'Cerrar sesión',
                    onPressed: _handleSignOut,
                  ),
                ],
              ),
            )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1B1B2F),
              Color(0xFF162447),
              Color(0xFF1F4068),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTitleLetter('U', Colors.redAccent),
                    _buildTitleLetter('N', Colors.amber),
                    _buildTitleLetter('O', Colors.green),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pero con las reglas de verdad',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 36),

                if (currentUser == null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _handleGoogleSignIn,
                      icon: const Icon(Icons.g_mobiledata, size: 30, color: Colors.white),
                      label: const Text(
                        'Iniciar sesión con Google',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Nombre / Nick',
                          labelStyle: const TextStyle(color: Colors.white60),
                          prefixIcon: const Icon(Icons.person, color: Colors.amber),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _createRoom,
                          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                          label: const Text(
                            'CREAR SALA',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.2))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'O UNIRSE A UNA',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.2))),
                  ],
                ),

                const SizedBox(height: 28),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 4,
                        style: const TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Código de Sala (4 caracteres)',
                          labelStyle: const TextStyle(color: Colors.white60),
                          prefixIcon: const Icon(Icons.vpn_key, color: Colors.lightBlueAccent),
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _joinRoom,
                          icon: const Icon(Icons.login, color: Colors.white),
                          label: const Text(
                            'UNIRSE A SALA',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (currentUser != null) ...[
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleLetter(String letter, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}