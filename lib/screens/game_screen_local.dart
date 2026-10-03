import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../logic/game_rules.dart';
import '../widgets/card_widget.dart';

enum LocalPlayerType { human, ai }

class LocalPlayer {
  final String id;
  final String name;
  final List<GameCard> hand;
  final LocalPlayerType type;
  bool hasSaidUno;

  LocalPlayer({
    required this.id,
    required this.name,
    required this.hand,
    required this.type,
    this.hasSaidUno = false,
  });

  LocalPlayer copyWith({
    String? name,
    List<GameCard>? hand,
    bool? hasSaidUno,
  }) {
    return LocalPlayer(
      id: id,
      name: name ?? this.name,
      hand: hand ?? this.hand,
      type: type,
      hasSaidUno: hasSaidUno ?? this.hasSaidUno,
    );
  }
}

class GameScreenLocal extends StatefulWidget {
  final int aiCount;

  const GameScreenLocal({super.key, required this.aiCount});

  @override
  State<GameScreenLocal> createState() => _GameScreenLocalState();
}

class _GameScreenLocalState extends State<GameScreenLocal> {
  late List<LocalPlayer> _players;
  late List<GameCard> _deck;
  late List<GameCard> _discardPile;
  int _currentTurnIndex = 0;
  CardColor _activeColor = CardColor.red;
  int _pendingDrawCount = 0;
  bool _isClockwise = true;
  bool _hasDrawnThisTurn = false;
  bool _gameEnded = false;
  LocalPlayer? _winner;
  Timer? _aiTimer;
  OverlayEntry? _currentBubble;

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _currentBubble?.remove();
    super.dispose();
  }

  void _showBubble(String message, {Color color = Colors.amber}) {
    _currentBubble?.remove();
    _currentBubble = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 10,
        right: 10,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3)),
              ],
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_currentBubble!);
    Future.delayed(const Duration(milliseconds: 2500), () {
      _currentBubble?.remove();
      _currentBubble = null;
    });
  }

  List<GameCard> _generateDeck() {
    List<GameCard> cards = [];
    int idCounter = 1;
    final colors = [CardColor.red, CardColor.blue, CardColor.green, CardColor.yellow];
    for (var color in colors) {
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

  void _shuffleDeck(List<GameCard> deck) {
    deck.shuffle(Random());
  }

  void _refillDeckIfNeeded() {
    if (_deck.isEmpty && _discardPile.length > 1) {
      final top = _discardPile.removeLast();
      _deck.addAll(_discardPile);
      _discardPile.clear();
      _discardPile.add(top);
      _shuffleDeck(_deck);
    }
  }

  LocalPlayer get _currentPlayer => _players[_currentTurnIndex];
  LocalPlayer get _humanPlayer => _players.firstWhere((p) => p.type == LocalPlayerType.human);

  bool _canPlayCard(GameCard card) {
    if (_discardPile.isEmpty) return true;
    return GameRules.isValidMove(
      playedCard: card,
      topCard: _discardPile.last,
      currentColor: _activeColor,
      pendingDrawCards: _pendingDrawCount,
    );
  }

  void _endGame(LocalPlayer winner) {
    if (_gameEnded) return;
    setState(() {
      _gameEnded = true;
      _winner = winner;
    });
  }

  void _nextTurn() {
    if (_isClockwise) {
      _currentTurnIndex = (_currentTurnIndex + 1) % _players.length;
    } else {
      _currentTurnIndex = (_currentTurnIndex - 1 + _players.length) % _players.length;
    }
    _hasDrawnThisTurn = false;
    setState(() {});
    _checkAiTurn();
  }

  void _checkAiTurn() {
    if (_gameEnded) return;
    final player = _currentPlayer;
    if (player.type == LocalPlayerType.ai) {
      _aiTimer?.cancel();
      _aiTimer = Timer(const Duration(milliseconds: 800), () {
        _aiPlay();
      });
    }
  }

  void _aiPlay() {
    if (_gameEnded) return;
    final idx = _currentTurnIndex;
    var player = _players[idx];
    if (player.type != LocalPlayerType.ai) return;
    if (_pendingDrawCount > 0) {
      int drawn = 0;
      while (_pendingDrawCount > 0 && _deck.isNotEmpty) {
        _refillDeckIfNeeded();
        final card = _deck.removeLast();
        player = player.copyWith(hand: [...player.hand, card]);
        _pendingDrawCount--;
        drawn++;
      }
      _players[idx] = player;
      setState(() {});
      if (drawn > 0) _showBubble('${player.name} roba $drawn');
      _nextTurn();
      return;
    }
    final playable = player.hand.firstWhere(
      (c) => _canPlayCard(c),
      orElse: () => GameCard(id: '', color: CardColor.wild, type: CardType.wild),
    );
    if (playable.id.isNotEmpty) {
      final hand = List<GameCard>.from(player.hand);
      hand.remove(playable);
      _players[idx] = player.copyWith(hand: hand);
      _discardPile.add(playable);
      _applyCardEffect(playable, player);
      setState(() {});
      _checkEnd(player);
      if (!_gameEnded) _handleSpecialOrNext(playable);
      return;
    } else {
      _refillDeckIfNeeded();
      if (_deck.isNotEmpty) {
        final drawn = _deck.removeLast();
        _players[idx] = player.copyWith(hand: [...player.hand, drawn]);
        setState(() {});
        if (_canPlayCard(drawn)) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (_gameEnded || _currentTurnIndex != idx) return;
            final h2 = List<GameCard>.from(_players[idx].hand);
            h2.remove(drawn);
            _discardPile.add(drawn);
            _applyCardEffect(drawn, _players[idx]);
            setState(() {});
            _checkEnd(_players[idx]);
            if (!_gameEnded) _handleSpecialOrNext(drawn);
          });
        } else {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (_gameEnded) return;
            _nextTurn();
          });
        }
      } else {
        _nextTurn();
      }
    }
  }

  void _applyCardEffect(GameCard card, LocalPlayer player) {
    if (card.type == CardType.plusTwo) {
      _pendingDrawCount += 2;
      _activeColor = card.color == CardColor.wild ? _activeColor : card.color;
    } else if (card.type == CardType.plusFour) {
      _pendingDrawCount += 4;
      _activeColor = card.color == CardColor.wild ? _activeColor : card.color;
    } else if (card.type == CardType.skip) {
      _activeColor = card.color;
    } else if (card.type == CardType.reverse) {
      _isClockwise = !_isClockwise;
      _activeColor = card.color;
    } else if (card.type == CardType.wild) {
      if (player.type == LocalPlayerType.human) {
        _showColorPicker();
        return;
      } else {
        _activeColor = _randomColor();
      }
    } else {
      _activeColor = card.color;
    }
  }

  CardColor _randomColor() {
    final c = [CardColor.red, CardColor.blue, CardColor.green, CardColor.yellow];
    return c[Random().nextInt(c.length)];
  }

  void _handleSpecialOrNext(GameCard card) {
    if (card.type == CardType.skip) {
      _nextTurn();
      _nextTurn();
      return;
    }
    _nextTurn();
  }

  void _checkEnd(LocalPlayer player) {
    if (player.hand.isEmpty) {
      _endGame(player);
    }
  }

  void _drawCard() {
    if (_gameEnded) return;
    final player = _humanPlayer;
    if (_pendingDrawCount > 0) {
      int drawn = 0;
      while (_pendingDrawCount > 0 && _deck.isNotEmpty) {
        _refillDeckIfNeeded();
        final card = _deck.removeLast();
        final idx = _players.indexWhere((p) => p.id == player.id);
        _players[idx] = _players[idx].copyWith(hand: [..._players[idx].hand, card]);
        _pendingDrawCount--;
        drawn++;
      }
      setState(() {});
      if (drawn > 0) _showBubble('Has robado $drawn cartas');
      _nextTurn();
      return;
    }
    if (_hasDrawnThisTurn) return;
    _refillDeckIfNeeded();
    if (_deck.isNotEmpty) {
      final drawn = _deck.removeLast();
      final idx = _players.indexWhere((p) => p.id == player.id);
      _players[idx] = _players[idx].copyWith(hand: [..._players[idx].hand, drawn]);
      _hasDrawnThisTurn = true;
      setState(() {});
      if (_canPlayCard(drawn)) {
        _showBubble('Robaste carta jugable. Juega o pasa');
      }
    }
  }

  void _passTurn() {
    if (_gameEnded) return;
    if (_hasDrawnThisTurn && _pendingDrawCount == 0) {
      _nextTurn();
    }
  }

  void _playCard(GameCard card) {
    if (_gameEnded) return;
    final idx = _players.indexWhere((p) => p.id == _humanPlayer.id);
    var player = _players[idx];
    if (!_canPlayCard(card)) {
      _showBubble('No se puede jugar esa carta');
      return;
    }
    final hand = List<GameCard>.from(player.hand);
    hand.remove(card);
    _players[idx] = player.copyWith(hand: hand);
    _discardPile.add(card);
    _applyCardEffect(card, player);
    setState(() {});
    _checkEnd(_players[idx]);
    if (!_gameEnded) {
      _handleSpecialOrNext(card);
    }
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B2F),
        title: const Text('Elige un color', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _colorOption(Colors.red.shade700, CardColor.red),
            _colorOption(Colors.blue.shade700, CardColor.blue),
            _colorOption(Colors.green.shade700, CardColor.green),
            _colorOption(Colors.amber.shade700, CardColor.yellow),
          ],
        ),
      ),
    );
  }

  Widget _colorOption(Color color, CardColor cardColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
          onPressed: () {
            Navigator.pop(context);
            setState(() {
              _activeColor = cardColor;
            });
            _nextTurn();
          },
          child: const Text(''),
        ),
      ),
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

  void _initGame() {
    _deck = _generateDeck();
    _shuffleDeck(_deck);
    _discardPile = [];
    _players = [];
    _players.add(LocalPlayer(id: 'human', name: 'Tú', hand: [], type: LocalPlayerType.human));
    for (int i = 1; i <= widget.aiCount; i++) {
      _players.add(LocalPlayer(id: 'ai$i', name: 'IA $i', hand: [], type: LocalPlayerType.ai));
    }
    for (var player in _players) {
      List<GameCard> hand = [];
      for (int i = 0; i < 7; i++) {
        if (_deck.isNotEmpty) hand.add(_deck.removeLast());
      }
      final idx = _players.indexWhere((p) => p.id == player.id);
      if (idx >= 0) _players[idx] = player.copyWith(hand: hand);
    }
    int initialDiscardIndex = _deck.lastIndexWhere((c) => c.type == CardType.number);
    if (initialDiscardIndex != -1) {
      _discardPile.add(_deck.removeAt(initialDiscardIndex));
    } else if (_deck.isNotEmpty) {
      _discardPile.add(_deck.removeLast());
    }
    _activeColor = _discardPile.isNotEmpty && _discardPile.last.color == CardColor.wild ? CardColor.red : (_discardPile.isNotEmpty ? _discardPile.last.color : CardColor.red);
    _currentTurnIndex = Random().nextInt(_players.length);
    _pendingDrawCount = 0;
    _isClockwise = true;
    _hasDrawnThisTurn = false;
    _gameEnded = false;
    _winner = null;
    setState(() {});
    _checkAiTurn();
  }

  @override
  Widget build(BuildContext context) {
    if (_gameEnded && _winner != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Partida local'), backgroundColor: const Color(0xFF1B1B2F), foregroundColor: Colors.white),
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(image: AssetImage('assets/tapetegamescreen.png'), fit: BoxFit.cover),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('¡${_winner!.name} gana!', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _initGame, child: const Text('Reiniciar')),
              ],
            ),
          ),
        ),
      );
    }

    final human = _humanPlayer;
    final current = _currentPlayer;
    bool hasPlayableCard = human.hand.any((c) => _canPlayCard(c));
    bool hasPendingDraws = _pendingDrawCount > 0;
    bool canPass = current.id == human.id && !hasPendingDraws && (!hasPlayableCard && _hasDrawnThisTurn);

    return Scaffold(
      appBar: AppBar(title: const Text('Partida local'), backgroundColor: const Color(0xFF1B1B2F), foregroundColor: Colors.white),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/tapetegamescreen.png'), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.black.withValues(alpha: 0.4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(current.id == human.id ? '¡TU TURNO!' : 'Turno: ${current.name}', style: TextStyle(color: current.id == human.id ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.bold)),
                    Row(children: [const Text('Color: ', style: TextStyle(color: Colors.white)), CircleAvatar(radius: 8, backgroundColor: _getFlutterColor(_activeColor))]),
                  ],
                ),
              ),
              if (hasPendingDraws)
                Container(width: double.infinity, color: Colors.red.shade800, padding: const EdgeInsets.symmetric(vertical: 4), child: Text('Cartas a robar: $_pendingDrawCount', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(mainAxisAlignment: MainAxisAlignment.center, children: [GestureDetector(onTap: current.id == human.id ? _drawCard : null, child: Container(width: 70, height: 100, decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(8)), child: const Center(child: Text('ROBAR', style: TextStyle(color: Colors.white)))))]),
                    if (_discardPile.isNotEmpty) CardWidget(card: _discardPile.last),
                  ],
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: _players.where((p) => p.id != human.id).map((p) => Padding(padding: const EdgeInsets.only(right: 8), child: Chip(label: Text('${p.name}: ${p.hand.length}'), backgroundColor: Colors.black54, labelStyle: const TextStyle(color: Colors.white)))).toList()),
              ),
              if (current.id == human.id)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: ElevatedButton(onPressed: canPass ? _passTurn : null, child: Text(hasPlayableCard && !_hasDrawnThisTurn ? 'TIENES QUE JUGAR' : (!_hasDrawnThisTurn ? 'ROBA' : 'PASAR')))),
              Container(
                height: 120,
                padding: const EdgeInsets.all(4),
                child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: human.hand.length, itemBuilder: (context, i) {
                  final c = human.hand[i];
                  return GestureDetector(onTap: current.id == human.id ? () => _playCard(c) : null, child: CardWidget(card: c));
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
