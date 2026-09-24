import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/card_model.dart';
import '../models/room_model.dart';
import '../widgets/card_widget.dart';
import '../widgets/uno_bubble_alert.dart';
import '../logic/game_rules.dart';
import '../services/invitation_service.dart';

class GameScreen extends StatefulWidget {
  final String roomCode;
  final String playerName;
  final bool isHost;

  const GameScreen({
    super.key,
    required this.roomCode,
    required this.playerName,
    required this.isHost,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final DatabaseReference _dbRef;
  late final String _cleanRoomCode;
  late String _playerId;
  GameRoom? _currentRoom;
  bool _isLoading = true;
  String? _errorMessage;

  Timer? _unoTimer;
  int _unoSecondsRemaining = 10;
  int _accusedDrawnCount = 2;

  Timer? _rematchTimer;
  bool _rematchTimerRunning = false;
  int _rematchSecondsRemaining = 30;
  bool _isLeavingRoom = false;

  bool _hasDrawnThisTurn = false;
  int? _lastTurnIndex;

  OverlayEntry? _currentBubble;

  final TextEditingController _chatController = TextEditingController();

  void showUnoBubble(String message, {Color color = Colors.amber}) {
    _currentBubble?.remove();

    _currentBubble = OverlayEntry(
      builder: (context) => UnoBubbleAlert(
        message: message,
        accentColor: color,
        onTap: () {
          _currentBubble?.remove();
          _currentBubble = null;
        },
      ),
    );

    Overlay.of(context).insert(_currentBubble!);

    Future.delayed(const Duration(milliseconds: 3500), () {
      _currentBubble?.remove();
      _currentBubble = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _cleanRoomCode = widget.roomCode.trim().toUpperCase();
    _playerId = DateTime.now().millisecondsSinceEpoch.toString();

    _dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://uno-stack-2by2-default-rtdb.europe-west1.firebasedatabase.app/',
    ).ref('rooms');

    _setupRoom();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _unoTimer?.cancel();
    _rematchTimer?.cancel();
    _currentBubble?.remove();
    super.dispose();
  }

  Future<void> _setupRoom() async {
    final roomRef = _dbRef.child(_cleanRoomCode);

    try {
      if (widget.isHost) {
        final initialDeck = _generateOfficialDeck();
        _shuffleDeck(initialDeck);

        final hostPlayer = Player(
          id: _playerId,
          name: widget.playerName,
          hand: [],
          isHost: true,
          hasSaidUno: false,
        );

        final room = GameRoom(
          code: _cleanRoomCode,
          hostId: _playerId,
          status: GameStatus.waiting,
          players: [hostPlayer],
          discardPile: [],
          deck: initialDeck,
          currentTurnIndex: 0,
          activeColor: CardColor.red,
          pendingDrawCount: 0,
          isClockwise: true,
          scores: {_playerId: 0},
          messages: [],
        );

        await roomRef.set(room.toJson());
      } else {
        final snapshot = await roomRef.get();
        if (snapshot.exists && snapshot.value != null) {
          final rawData = Map<String, dynamic>.from(snapshot.value as Map);
          final roomData = GameRoom.fromJson(rawData);
          final updatedPlayers = List<Player>.from(roomData.players);
          final scores = Map<String, int>.from(roomData.scores);

          if (!updatedPlayers.any((p) => p.id == _playerId)) {
            updatedPlayers.add(Player(
              id: _playerId,
              name: widget.playerName,
              hand: [],
              isHost: false,
              hasSaidUno: false,
            ));
            scores[_playerId] = 0;
          }

          await roomRef.child('players').set(updatedPlayers.map((p) => p.toJson()).toList());
          await roomRef.child('scores').set(scores);
        } else {
          setState(() {
            _errorMessage = 'La sala $_cleanRoomCode no existe. Revisa el código.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al conectar con la sala: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendChatMessage(String text) async {
    if (_currentRoom == null || text.trim().isEmpty) return;

    final trimmedText = text.trim();
    _chatController.clear();

    final timeNow = TimeOfDay.fromDateTime(DateTime.now()).format(context);
    final newMsg = ChatMessage(
      senderName: widget.playerName,
      text: trimmedText,
      time: timeNow,
    );

    await _dbRef.child(_cleanRoomCode).child('messages').runTransaction((current) {
      final List<dynamic> rawList = current is List ? List<dynamic>.from(current) : <dynamic>[];
      final List<Map<String, dynamic>> safeList = rawList
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      safeList.add(newMsg.toJson());
      return Transaction.success(safeList);
    });
  }

  Widget _buildChatWidget({double height = 170}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 14, color: Colors.amber),
                SizedBox(width: 6),
                Text(
                  'Chat de la Sala',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(8),
              itemCount: _currentRoom?.messages.length ?? 0,
              itemBuilder: (context, index) {
                final msg = _currentRoom!.messages.reversed.toList()[index];
                final isMe = msg.senderName == widget.playerName;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.0),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13),
                      children: [
                        TextSpan(
                          text: '[${msg.time}] ',
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                        TextSpan(
                          text: '${msg.senderName}: ',
                          style: TextStyle(
                            color: isMe ? Colors.greenAccent : Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: msg.text,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _sendChatMessage,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                  icon: const Icon(Icons.send, color: Colors.amber, size: 20),
                  onPressed: () => _sendChatMessage(_chatController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<GameCard> _generateOfficialDeck() {
    List<GameCard> cards = [];
    int idCounter = 1;

    final standardColors = [
      CardColor.red,
      CardColor.blue,
      CardColor.green,
      CardColor.yellow,
    ];

    for (var color in standardColors) {
      for (int i = 1; i <= 9; i++) {
        cards.add(GameCard(id: '${idCounter++}', color: color, type: CardType.number, number: i));
        cards.add(GameCard(id: '${idCounter++}', color: color, type: CardType.number, number: i));
      }

      for (int i = 0; i < 2; i++) {
        cards.add(GameCard(id: '${idCounter++}', color: color, type: CardType.plusTwo));
        cards.add(GameCard(id: '${idCounter++}', color: color, type: CardType.skip));
        cards.add(GameCard(id: '${idCounter++}', color: color, type: CardType.reverse));
      }
    }

    for (int i = 0; i < 4; i++) {
      cards.add(GameCard(id: '${idCounter++}', color: CardColor.wild, type: CardType.wild));
      cards.add(GameCard(id: '${idCounter++}', color: CardColor.wild, type: CardType.plusFour));
    }

    return cards;
  }

  void _shuffleDeck(List<GameCard> deckToShuffle) {
    final secureRandom = Random.secure();
    for (int i = deckToShuffle.length - 1; i > 0; i--) {
      int j = secureRandom.nextInt(i + 1);
      var temp = deckToShuffle[i];
      deckToShuffle[i] = deckToShuffle[j];
      deckToShuffle[j] = temp;
    }
  }

  Future<void> _startGame() async {
    if (_currentRoom == null || _currentRoom!.players.length < 2) return;

    final deck = _generateOfficialDeck();
    _shuffleDeck(deck);

    final players = List<Player>.from(_currentRoom!.players);

    for (var player in players) {
      List<GameCard> hand = [];
      for (int i = 0; i < 7; i++) {
        if (deck.isNotEmpty) {
          hand.add(deck.removeLast());
        }
      }
      players[players.indexOf(player)] = Player(
        id: player.id,
        name: player.name,
        hand: hand,
        isHost: player.isHost,
        hasSaidUno: false,
      );
    }

    List<GameCard> discardPile = [];
    int initialDiscardIndex = deck.lastIndexWhere((c) => c.type == CardType.number);
    if (initialDiscardIndex != -1) {
      discardPile.add(deck.removeAt(initialDiscardIndex));
    } else {
      discardPile.add(deck.removeLast());
    }

    CardColor activeColor = discardPile.last.color == CardColor.wild
        ? CardColor.red
        : discardPile.last.color;

    final randomStartIndex = Random().nextInt(players.length);

    final updatedRoom = GameRoom(
      code: _currentRoom!.code,
      hostId: _currentRoom!.hostId,
      status: GameStatus.playing,
      players: players,
      discardPile: discardPile,
      deck: deck,
      currentTurnIndex: randomStartIndex,
      activeColor: activeColor,
      pendingDrawCount: 0,
      isClockwise: true,
      scores: _currentRoom!.scores,
      messages: _currentRoom!.messages,
      rematchReady: [],
    );

    await _dbRef.child(_cleanRoomCode).set(updatedRoom.toJson());
  }

  Future<void> _requestRematch() async {
    _rematchTimer?.cancel();
    setState(() {
      _rematchTimerRunning = false;
      _rematchSecondsRemaining = 30;
      _hasDrawnThisTurn = false;
    });
    await _startGame();
  }

  Future<void> _voteRematch() async {
    if (_currentRoom == null) return;
    final roomRef = _dbRef.child(_cleanRoomCode);
    await roomRef.child('rematchReady').runTransaction((current) {
      List<String> ids = current is List
          ? List<String>.from(current.map((e) => e.toString()))
          : <String>[];
      if (!ids.contains(_playerId)) ids.add(_playerId);
      return Transaction.success(ids);
    });
  }

  void _startRematchCountdown() {
    if (_rematchTimerRunning) return;
    setState(() {
      _rematchTimerRunning = true;
      _rematchSecondsRemaining = 30;
    });
    _rematchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _rematchSecondsRemaining--;
      });
      if (_rematchSecondsRemaining <= 0) {
        timer.cancel();
        _rematchTimerRunning = false;
        _deleteRoom();
      }
    });
  }

  Future<void> _deleteRoom() async {
    if (_isLeavingRoom) return;
    _isLeavingRoom = true;
    _rematchTimer?.cancel();
    await _dbRef.child(_cleanRoomCode).remove();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _checkUnoState(List<Player> players) {
    final myPlayer = players.firstWhere((p) => p.id == _playerId, orElse: () => Player(id: '', name: '', hand: []));

    if (myPlayer.hand.length == 1 && !myPlayer.hasSaidUno) {
      if (_unoTimer == null || !(_unoTimer?.isActive ?? false)) {
        _unoSecondsRemaining = 10;
        _unoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_unoSecondsRemaining > 0) {
            if (mounted) {
              setState(() {
                _unoSecondsRemaining--;
              });
            }
          } else {
            timer.cancel();
          }
        });
      }
    } else if (myPlayer.hand.length != 1 && myPlayer.hasSaidUno) {
      _resetUnoStateIfNeeded(myPlayer.hand.length);
    }
  }

  Future<void> _resetUnoStateIfNeeded(int currentHandLength) async {
    if (_currentRoom == null) return;
    final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == _playerId);
    if (playerIndex == -1) return;

    final myPlayer = _currentRoom!.players[playerIndex];
    if (currentHandLength != 1 && myPlayer.hasSaidUno) {
      await _dbRef
          .child(_cleanRoomCode)
          .child('players')
          .child('$playerIndex')
          .child('hasSaidUno')
          .set(false);
    }
  }

  Future<void> _pressUnoButton() async {
    if (_currentRoom == null) return;
    _unoTimer?.cancel();

    final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == _playerId);
    if (playerIndex == -1) return;

    await _dbRef
        .child(_cleanRoomCode)
        .child('players')
        .child('$playerIndex')
        .child('hasSaidUno')
        .set(true);

    if (!mounted) return;
    showUnoBubble('¡Has cantado UNO! 🗣️', color: Colors.green);
  }

  Future<void> _accusePlayer(Player targetPlayer) async {
    if (_currentRoom == null) return;

    if (targetPlayer.hand.length != 1 || targetPlayer.hasSaidUno) {
      showUnoBubble('¡Acusación inválida! Ya cantó o no tiene 1 carta.', color: Colors.red);
      return;
    }

    try {
      final result = await _dbRef.child(_cleanRoomCode).runTransaction((current) {
        if (current == null) return Transaction.abort();

        final currentRoom = GameRoom.fromJson(Map<String, dynamic>.from(current as Map));
        final players = List<Player>.from(currentRoom.players);
        final targetIndex = players.indexWhere((p) => p.id == targetPlayer.id);

        if (targetIndex == -1) return Transaction.abort();

        final serverTarget = players[targetIndex];
        if (serverTarget.hand.length != 1 || serverTarget.hasSaidUno) {
          return Transaction.abort();
        }

        final deck = List<GameCard>.from(currentRoom.deck);
        final discardPile = List<GameCard>.from(currentRoom.discardPile);
        final targetHand = List<GameCard>.from(serverTarget.hand);

        int drawn = 0;
        for (int i = 0; i < 2; i++) {
          if (deck.isEmpty && discardPile.length > 1) {
            final topCard = discardPile.removeLast();
            deck.addAll(discardPile);
            _shuffleDeck(deck);
            discardPile.clear();
            discardPile.add(topCard);
          }
          if (deck.isNotEmpty) {
            targetHand.add(deck.removeLast());
            drawn++;
          }
        }

        players[targetIndex] = Player(
          id: serverTarget.id,
          name: serverTarget.name,
          hand: targetHand,
          isHost: serverTarget.isHost,
          hasSaidUno: false,
        );

        final updatedRoom = GameRoom(
          code: currentRoom.code,
          hostId: currentRoom.hostId,
          status: currentRoom.status,
          players: players,
          discardPile: discardPile,
          deck: deck,
          currentTurnIndex: currentRoom.currentTurnIndex,
          activeColor: currentRoom.activeColor,
          pendingDrawCount: currentRoom.pendingDrawCount,
          isClockwise: currentRoom.isClockwise,
          scores: currentRoom.scores,
          messages: currentRoom.messages,
          rematchReady: currentRoom.rematchReady,
        );

        _accusedDrawnCount = drawn;
        return Transaction.success(updatedRoom.toJson());
      });

      if (!mounted) return;
      if (result.committed && result.snapshot.value != null) {
        showUnoBubble(
          '¡Acusación exitosa! ${targetPlayer.name} recibe $_accusedDrawnCount cartas.',
          color: Colors.orange,
        );
      } else {
        showUnoBubble('¡Acusación inválida! Ya cantó o no tiene 1 carta.', color: Colors.red);
      }
    } catch (_) {
      if (!mounted) return;
      showUnoBubble('No se pudo acusar. Inténtalo de nuevo.', color: Colors.red);
    }
  }

  int _getNextTurnIndex(int current, int totalPlayers, bool isClockwise, int step) {
    if (totalPlayers == 2) {
      return (current + step) % totalPlayers;
    }
    if (isClockwise) {
      return (current + step) % totalPlayers;
    } else {
      return (current - step + totalPlayers) % totalPlayers;
    }
  }

  bool _canPlayCard(GameCard card) {
    if (_currentRoom == null) return false;
    final topCard = _currentRoom!.discardPile.last;

    return GameRules.isValidMove(
      playedCard: card,
      topCard: topCard,
      currentColor: _currentRoom!.activeColor,
      pendingDrawCards: _currentRoom!.pendingDrawCount,
    );
  }

  Future<void> _playCard(GameCard card) async {
    if (_currentRoom == null) return;

    final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == _playerId);
    if (playerIndex != _currentRoom!.currentTurnIndex) return;

    if (!_canPlayCard(card)) {
      if (_currentRoom!.pendingDrawCount > 0) {
        _handlePendingDrawPenalty();
        return;
      }
      showUnoBubble('Esta carta no se puede jugar sobre la mesa.', color: Colors.redAccent);
      return;
    }

    final myPlayer = _currentRoom!.players[playerIndex];
    bool canStackMultiple = card.type == CardType.number;

    List<GameCard> identicalCards = [];
    if (canStackMultiple) {
      identicalCards = myPlayer.hand.where((c) =>
        c.id != card.id &&
        c.color == card.color &&
        c.type == CardType.number &&
        c.number == card.number
      ).toList();
    }

    if (identicalCards.isNotEmpty) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1B1B2F),
          title: const Text('¡Cartas iguales detectadas!', style: TextStyle(color: Colors.white)),
          content: const Text('¿Deseas jugar una sola carta o las 2 cartas idénticas simultáneamente?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _processPlay([card]);
              },
              child: const Text('Jugar 1', style: TextStyle(color: Colors.amber)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _processPlay([card, identicalCards.first]);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Jugar las 2 juntas'),
            ),
          ],
        ),
      );
    } else {
      _processPlay([card]);
    }
  }

  Future<void> _handlePendingDrawPenalty() async {
    final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == _playerId);
    final deck = List<GameCard>.from(_currentRoom!.deck);
    final discardPile = List<GameCard>.from(_currentRoom!.discardPile);
    final players = List<Player>.from(_currentRoom!.players);
    final myPlayer = players[playerIndex];
    final myHand = List<GameCard>.from(myPlayer.hand);

    int countToDraw = _currentRoom!.pendingDrawCount;
    for (int i = 0; i < countToDraw; i++) {
      if (deck.isEmpty && discardPile.length > 1) {
        final topCard = discardPile.removeLast();
        deck.addAll(discardPile);
        _shuffleDeck(deck);
        discardPile.clear();
        discardPile.add(topCard);
      }
      if (deck.isNotEmpty) {
        myHand.add(deck.removeLast());
      }
    }

    players[playerIndex] = Player(
      id: myPlayer.id,
      name: myPlayer.name,
      hand: myHand,
      isHost: myPlayer.isHost,
      hasSaidUno: false,
    );

    int nextTurn = _getNextTurnIndex(_currentRoom!.currentTurnIndex, players.length, _currentRoom!.isClockwise, 1);

    final updatedRoom = GameRoom(
      code: _currentRoom!.code,
      hostId: _currentRoom!.hostId,
      status: _currentRoom!.status,
      players: players,
      discardPile: discardPile,
      deck: deck,
      currentTurnIndex: nextTurn,
      activeColor: _currentRoom!.activeColor,
      pendingDrawCount: 0,
      isClockwise: _currentRoom!.isClockwise,
      scores: _currentRoom!.scores,
      messages: _currentRoom!.messages,
      rematchReady: _currentRoom!.rematchReady,
    );

    await _dbRef.child(_cleanRoomCode).set(updatedRoom.toJson());

    if (!mounted) return;
    showUnoBubble('¡Te has comido $countToDraw cartas acumuladas!', color: Colors.red.shade700);
  }

  Future<void> _processPlay(List<GameCard> cardsToPlay) async {
    final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == _playerId);
    final players = List<Player>.from(_currentRoom!.players);
    final myPlayer = players[playerIndex];

    final updatedHand = List<GameCard>.from(myPlayer.hand);
    for (var c in cardsToPlay) {
      updatedHand.removeWhere((card) => card.id == c.id);
    }

    players[playerIndex] = Player(
      id: myPlayer.id,
      name: myPlayer.name,
      hand: updatedHand,
      isHost: myPlayer.isHost,
      hasSaidUno: updatedHand.length == 1 ? myPlayer.hasSaidUno : false,
    );

    final discardPile = List<GameCard>.from(_currentRoom!.discardPile)..addAll(cardsToPlay);
    int newPendingDraw = _currentRoom!.pendingDrawCount;
    bool newIsClockwise = _currentRoom!.isClockwise;
    int step = 1;

    for (var card in cardsToPlay) {
      if (card.type == CardType.plusTwo) {
        newPendingDraw += 2;
      } else if (card.type == CardType.plusFour) {
        newPendingDraw += 4;
      } else if (card.type == CardType.skip) {
        step += 1;
      } else if (card.type == CardType.reverse) {
        if (players.length > 2) {
          newIsClockwise = !newIsClockwise;
        } else {
          step += 1;
        }
      }
    }

    final lastCard = cardsToPlay.last;
    if (lastCard.color == CardColor.wild) {
      _showColorPicker((selectedColor) async {
        await _finalizeCardPlay(players, discardPile, updatedHand, playerIndex, lastCard, selectedColor, newPendingDraw, newIsClockwise, step);
      });
    } else {
      await _finalizeCardPlay(players, discardPile, updatedHand, playerIndex, lastCard, lastCard.color, newPendingDraw, newIsClockwise, step);
    }
  }

  Future<void> _finalizeCardPlay(
    List<Player> players,
    List<GameCard> discardPile,
    List<GameCard> updatedHand,
    int playerIndex,
    GameCard lastCard,
    CardColor chosenColor,
    int newPendingDraw,
    bool newIsClockwise,
    int step,
  ) async {
    final actualHandLength = players[playerIndex].hand.length;
    
    GameStatus status = _currentRoom!.status;
    final scores = Map<String, int>.from(_currentRoom!.scores);

    if (actualHandLength == 0) {
      status = GameStatus.finished;
      scores[_playerId] = (scores[_playerId] ?? 0) + 1;
    }

    int nextTurn = _getNextTurnIndex(_currentRoom!.currentTurnIndex, players.length, newIsClockwise, step);

    final updatedRoom = GameRoom(
      code: _currentRoom!.code,
      hostId: _currentRoom!.hostId,
      status: status,
      players: players,
      discardPile: discardPile,
      deck: _currentRoom!.deck,
      currentTurnIndex: nextTurn,
      activeColor: chosenColor,
      pendingDrawCount: newPendingDraw,
      isClockwise: newIsClockwise,
      scores: scores,
      messages: _currentRoom!.messages,
      rematchReady: _currentRoom!.rematchReady,
    );

    await _dbRef.child(_cleanRoomCode).set(updatedRoom.toJson());
  }

  Future<void> _drawCard() async {
    if (_currentRoom == null) return;
    final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == _playerId);
    if (playerIndex != _currentRoom!.currentTurnIndex) return;

    if (_currentRoom!.pendingDrawCount > 0) {
      await _handlePendingDrawPenalty();
      return;
    }

    final deck = List<GameCard>.from(_currentRoom!.deck);
    final discardPile = List<GameCard>.from(_currentRoom!.discardPile);
    final players = List<Player>.from(_currentRoom!.players);
    final myPlayer = players[playerIndex];
    final myHand = List<GameCard>.from(myPlayer.hand);

    if (deck.isEmpty) {
      if (discardPile.length > 1) {
        final topCard = discardPile.removeLast();
        deck.addAll(discardPile);
        _shuffleDeck(deck);
        discardPile.clear();
        discardPile.add(topCard);
      } else {
        showUnoBubble('No hay más cartas para robar.', color: Colors.orange);
        return;
      }
    }

    final drawnCard = deck.removeLast();
    myHand.add(drawnCard);

    players[playerIndex] = Player(
      id: myPlayer.id,
      name: myPlayer.name,
      hand: myHand,
      isHost: myPlayer.isHost,
      hasSaidUno: false,
    );

    bool canPlayDrawn = _canPlayCard(drawnCard);
    int nextTurn;
    if (canPlayDrawn) {
      setState(() {
        _hasDrawnThisTurn = true;
      });
      nextTurn = _currentRoom!.currentTurnIndex;
      showUnoBubble('¡Robaste carta jugable! Juega o pasa turno.', color: Colors.green);
    } else {
      nextTurn = _getNextTurnIndex(_currentRoom!.currentTurnIndex, players.length, _currentRoom!.isClockwise, 1);
      showUnoBubble('Carta no jugable. Turno pasado automáticamente.', color: Colors.blueGrey);
    }

    final updatedRoom = GameRoom(
      code: _currentRoom!.code,
      hostId: _currentRoom!.hostId,
      status: _currentRoom!.status,
      players: players,
      discardPile: discardPile,
      deck: deck,
      currentTurnIndex: nextTurn,
      activeColor: _currentRoom!.activeColor,
      pendingDrawCount: 0,
      isClockwise: _currentRoom!.isClockwise,
      scores: _currentRoom!.scores,
      messages: _currentRoom!.messages,
      rematchReady: _currentRoom!.rematchReady,
    );

    await _dbRef.child(_cleanRoomCode).set(updatedRoom.toJson());
  }

  Future<void> _passTurn() async {
    if (_currentRoom == null) return;
    final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == _playerId);
    if (playerIndex != _currentRoom!.currentTurnIndex) return;

    if (_currentRoom!.pendingDrawCount > 0) {
      await _handlePendingDrawPenalty();
      return;
    }

    final myPlayer = _currentRoom!.players[playerIndex];
    bool hasPlayableCard = myPlayer.hand.any((c) => _canPlayCard(c));

    if (hasPlayableCard && !_hasDrawnThisTurn) {
      showUnoBubble('¡Tienes cartas jugables! Debes jugarlas.', color: Colors.redAccent);
      return;
    }

    if (!hasPlayableCard && !_hasDrawnThisTurn) {
      showUnoBubble('Debes robar una carta antes de pasar.', color: Colors.redAccent);
      return;
    }

    int nextTurn = _getNextTurnIndex(_currentRoom!.currentTurnIndex, _currentRoom!.players.length, _currentRoom!.isClockwise, 1);

    final updatedRoom = GameRoom(
      code: _currentRoom!.code,
      hostId: _currentRoom!.hostId,
      status: _currentRoom!.status,
      players: _currentRoom!.players,
      discardPile: _currentRoom!.discardPile,
      deck: _currentRoom!.deck,
      currentTurnIndex: nextTurn,
      activeColor: _currentRoom!.activeColor,
      pendingDrawCount: _currentRoom!.pendingDrawCount,
      isClockwise: _currentRoom!.isClockwise,
      scores: _currentRoom!.scores,
      messages: _currentRoom!.messages,
      rematchReady: _currentRoom!.rematchReady,
    );

    await _dbRef.child(_cleanRoomCode).set(updatedRoom.toJson());
  }

  void _showInviteModal() {
    final TextEditingController nickController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B2F),
        title: const Text('Invitar a un amigo', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nickController,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(
            labelText: 'Nick del amigo',
            labelStyle: TextStyle(color: Colors.white60),
            prefixIcon: Icon(Icons.tag, color: Colors.amber),
            helperText: 'El nick único que eligió al iniciar sesión.',
            helperStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              String nick = nickController.text.trim();
              if (nick.isEmpty) return;

              bool success = await InvitationService().sendGameInvitationByNick(nick, _cleanRoomCode);

              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? '¡Invitación enviada a $nick!'
                        : 'No se encontró ese nick o el usuario está desconectado si aún no tiene nick.',
                  ),
                  backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Enviar invitación'),
          ),
        ],
      ),
    );
  }

  void _confirmEndGame() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B2F),
        title: const Text('¿Finalizar partida?', style: TextStyle(color: Colors.white)),
        content: const Text('Esto terminará la partida actual para todos los jugadores.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (_currentRoom != null) {
                final updatedRoom = GameRoom(
                  code: _currentRoom!.code,
                  hostId: _currentRoom!.hostId,
                  status: GameStatus.finished,
                  players: _currentRoom!.players,
                  discardPile: _currentRoom!.discardPile,
                  deck: _currentRoom!.deck,
                  currentTurnIndex: _currentRoom!.currentTurnIndex,
                  activeColor: _currentRoom!.activeColor,
                  pendingDrawCount: _currentRoom!.pendingDrawCount,
                  isClockwise: _currentRoom!.isClockwise,
                  scores: _currentRoom!.scores,
                  messages: _currentRoom!.messages,
                  rematchReady: _currentRoom!.rematchReady,
                );
                await _dbRef.child(_cleanRoomCode).set(updatedRoom.toJson());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('FINALIZAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(Function(CardColor) onColorSelected) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B2F),
          title: const Text('Elige un color', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _colorOption(Colors.red.shade700, CardColor.red, onColorSelected, dialogContext),
              _colorOption(Colors.blue.shade700, CardColor.blue, onColorSelected, dialogContext),
              _colorOption(Colors.green.shade700, CardColor.green, onColorSelected, dialogContext),
              _colorOption(Colors.amber.shade700, CardColor.yellow, onColorSelected, dialogContext),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  Widget _colorOption(Color color, CardColor cardColor, Function(CardColor) onColorSelected, BuildContext dialogContext) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(dialogContext);
        onColorSelected(cardColor);
      },
      child: CircleAvatar(
        backgroundColor: color,
        radius: 25,
      ),
    );
  }

  Widget _buildGameOverUI() {
    final room = _currentRoom!;
    final winner = room.players.firstWhere(
      (p) => p.hand.isEmpty,
      orElse: () => room.players.first,
    );
    final isWinner = winner.id == _playerId;

    int myWins = room.scores[_playerId] ?? 0;
    int rivalWins = 0;
    room.scores.forEach((id, score) {
      if (id != _playerId) rivalWins = score;
    });

    final iVoted = room.rematchReady.contains(_playerId);
    final allReady = room.players.isNotEmpty &&
        room.players.every((p) => room.rematchReady.contains(p.id));

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isWinner ? '🎉 ¡VICTORIA! 🎉' : '😢 ¡DERROTA! 😢',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isWinner ? '¡Has ganado la partida!' : '${winner.name} se ha llevado la victoria.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 15),
            Text(
              'Marcador en Sala:\nTú: $myWins | Rival: $rivalWins',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber),
            ),
            const SizedBox(height: 24),
            if (allReady)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '¡Todos confirmaron la revancha! Reiniciando...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                ),
              )
            else ...[
              Text(
                iVoted
                    ? 'Esperando a que el rival confirme la revancha...'
                    : '¿Quieres una revancha? Ambos debéis confirmar.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                'La sala se cerrará en $_rematchSecondsRemaining s si no hay acuerdo.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: _deleteRoom,
                  icon: const Icon(Icons.exit_to_app, color: Colors.white60),
                  label: const Text('SALIR', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: iVoted || allReady ? null : _voteRematch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    disabledBackgroundColor: Colors.green.withValues(alpha: 0.4),
                  ),
                  child: Text(
                    allReady
                        ? 'REVANCHA ✓'
                        : (iVoted ? 'ESPERANDO...' : '¡REVANCHA!'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sala: $_cleanRoomCode'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B1B2F),
        foregroundColor: Colors.white,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                'Tú: ${_currentRoom?.scores[_playerId] ?? 0} pts',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amber),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
            tooltip: 'Finalizar partida',
            onPressed: _confirmEndGame,
          ),
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
        child: _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 18), textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('VOLVER AL MENÚ'),
                      ),
                    ],
                  ),
                ),
              )
            : StreamBuilder<DatabaseEvent>(
                stream: _dbRef.child(_cleanRoomCode).onValue,
                builder: (context, snapshot) {
                  if (_isLoading || !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.amber));
                  }

                  if (snapshot.data?.snapshot.value == null) {
                    if (!_isLeavingRoom && _currentRoom != null) {
                      _isLeavingRoom = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        Navigator.pop(context);
                      });
                    }
                    return const Center(child: CircularProgressIndicator(color: Colors.amber));
                  }

                  final rawData = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
                  _currentRoom = GameRoom.fromJson(rawData);

                  if (_lastTurnIndex != _currentRoom!.currentTurnIndex) {
                    _lastTurnIndex = _currentRoom!.currentTurnIndex;
                    _hasDrawnThisTurn = false;
                  }

                  final isFinished = _currentRoom!.status == GameStatus.finished;
                  if (isFinished) {
                    final allReady = _currentRoom!.players.isNotEmpty &&
                        _currentRoom!.players.every((p) => _currentRoom!.rematchReady.contains(p.id));
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (!_rematchTimerRunning) {
                        _startRematchCountdown();
                      }
                      if (allReady && widget.isHost && !_isLeavingRoom) {
                        _requestRematch();
                      }
                    });
                  } else {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _checkUnoState(_currentRoom!.players);
                    });
                  }

                  if (_currentRoom!.status == GameStatus.waiting) {
                    return _buildLobbyUI();
                  }

                  if (isFinished) {
                    return _buildGameOverUI();
                  }

                  return _buildGameUI();
                },
              ),
      ),
    );
  }

  Widget _buildLobbyUI() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.group, color: Colors.amber),
                const SizedBox(width: 10),
                Text(
                  'Sala de Espera (Código: $_cleanRoomCode)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _currentRoom!.players.length,
                itemBuilder: (context, index) {
                  final player = _currentRoom!.players[index];
                  return Card(
                    color: Colors.white.withValues(alpha: 0.05),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.amber,
                        child: Text(player.name[0].toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(player.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: player.isHost
                          ? const Chip(label: Text('Host'), backgroundColor: Colors.redAccent, labelStyle: TextStyle(color: Colors.white))
                          : const Chip(label: Text('Jugador'), backgroundColor: Colors.blueAccent, labelStyle: TextStyle(color: Colors.white)),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 15),
          _buildChatWidget(height: 160),
          const SizedBox(height: 15),
          if (widget.isHost) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _showInviteModal,
                icon: const Icon(Icons.share, color: Colors.amber),
                label: const Text(
                  'INVITAR AMIGO POR CORREO',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amber),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.isHost)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _currentRoom!.players.length >= 2 ? _startGame : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _currentRoom!.players.length >= 2
                      ? 'INICIAR PARTIDA'
                      : 'ESPERANDO MÁS JUGADORES (MÍN. 2)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGameUI() {
    final myPlayer = _currentRoom!.players.firstWhere(
      (p) => p.id == _playerId,
      orElse: () => Player(id: '', name: '', hand: []),
    );

    final currentTurnPlayer = _currentRoom!.players[_currentRoom!.currentTurnIndex];
    final isMyTurn = currentTurnPlayer.id == _playerId;
    
    final needsUno = myPlayer.hand.length == 1 && !myPlayer.hasSaidUno;
    
    bool hasPlayableCard = myPlayer.hand.any((c) => _canPlayCard(c));
    bool hasPendingDraws = (_currentRoom!.pendingDrawCount > 0);

    bool canPass = isMyTurn && !hasPendingDraws && (!hasPlayableCard && _hasDrawnThisTurn);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.black.withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isMyTurn ? '¡ES TU TURNO!' : 'Turno de: ${currentTurnPlayer.name}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isMyTurn ? Colors.greenAccent : Colors.white70,
                ),
              ),
              Row(
                children: [
                  const Text('Color: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: _getFlutterColor(_currentRoom!.activeColor),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (hasPendingDraws)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.red.shade900,
            child: Text(
              '¡ACUMULADO DE ROBO: +${_currentRoom!.pendingDrawCount}!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
            ),
          ),

        if (needsUno)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            color: Colors.amber.shade800,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '¡TIENES 1 CARTA! Canta UNO en: ${_unoSecondsRemaining}s',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 15),
                ElevatedButton(
                  onPressed: _pressUnoButton,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2)),
                  child: const Text('¡UNO!'),
                ),
              ],
            ),
          ),

        // Lista compacta de rivales
        SizedBox(
          height: 55,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: _currentRoom!.players.where((p) => p.id != _playerId).map((rival) {
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.lightBlueAccent, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${rival.name}: ${rival.hand.length} 🃏',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    if (rival.hand.length == 1) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _accusePlayer(rival),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)),
                          child: const Text('¡ACUSAR!', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        // Zona central: Mazo de robar y carta descartada
        Expanded(
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: isMyTurn ? _drawCard : null,
                  child: Container(
                    width: 75,
                    height: 110,
                    decoration: BoxDecoration(
                      color: isMyTurn ? Colors.blueGrey.shade800 : Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMyTurn ? Colors.greenAccent : Colors.white24,
                        width: isMyTurn ? 3 : 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                        const SizedBox(height: 4),
                        Text(
                          hasPendingDraws ? 'COMER +${_currentRoom!.pendingDrawCount}' : 'ROBAR',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Colors.white),
                        ),
                        Text('(${_currentRoom!.deck.length})', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 25),
                if (_currentRoom!.discardPile.isNotEmpty)
                  CardWidget(card: _currentRoom!.discardPile.last),
              ],
            ),
          ),
        ),

        // CHAT AMPLIADO
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: _buildChatWidget(height: 170),
        ),

        // Botón de estado de turno / pasar con ALTO CONTRASTE
        if (isMyTurn && !hasPendingDraws)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amberAccent, width: 1),
              ),
              child: ElevatedButton.icon(
                onPressed: canPass ? _passTurn : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canPass ? Colors.orange.shade800 : Colors.blueGrey.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                icon: const Icon(Icons.info_outline, size: 18, color: Colors.white),
                label: Text(
                  hasPlayableCard && !_hasDrawnThisTurn
                      ? 'DEBES JUGAR CARTA'
                      : (!_hasDrawnThisTurn ? 'DEBES ROBAR CARTA' : 'PASAR TURNO'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ),

        if (isMyTurn && hasPendingDraws)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '¡Pulsa en ROBAR para comerte las ${_currentRoom!.pendingDrawCount} cartas!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),

        // Mano del jugador (TODAS LAS CARTAS CON EL MISMO BRILLO/OPACIDAD)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tu Mano (${myPlayer.hand.length}):',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 115,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: myPlayer.hand.length,
            itemBuilder: (context, index) {
              final card = myPlayer.hand[index];

              return GestureDetector(
                onTap: isMyTurn ? () => _playCard(card) : null,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: CardWidget(card: card), // Sin opacidad reducida, todas se ven igual
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Color _getFlutterColor(CardColor color) {
    switch (color) {
      case CardColor.red:
        return Colors.red.shade700;
      case CardColor.blue:
        return Colors.blue.shade700;
      case CardColor.green:
        return Colors.green.shade700;
      case CardColor.yellow:
        return Colors.amber.shade700;
      case CardColor.wild:
        return Colors.grey.shade900;
    }
  }
}