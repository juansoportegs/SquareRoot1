import 'card_model.dart';

enum GameStatus { waiting, playing, finished }

class ChatMessage {
  final String senderName;
  final String text;
  final String time;

  ChatMessage({
    required this.senderName,
    required this.text,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'senderName': senderName,
        'text': text,
        'time': time,
      };

  factory ChatMessage.fromJson(Map<dynamic, dynamic> json) {
    return ChatMessage(
      senderName: json['senderName'] ?? 'Anónimo',
      text: json['text'] ?? '',
      time: json['time'] ?? '',
    );
  }
}

class Player {
  final String id;
  final String name;
  final List<GameCard> hand;
  final bool isHost;
  final bool hasSaidUno;

  Player({
    required this.id,
    required this.name,
    required this.hand,
    this.isHost = false,
    this.hasSaidUno = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hand': hand.map((c) => c.toJson()).toList(),
        'isHost': isHost,
        'hasSaidUno': hasSaidUno,
      };

  factory Player.fromJson(Map<dynamic, dynamic> json) {
    var rawHand = json['hand'] as List<dynamic>? ?? [];
    List<GameCard> loadedHand = rawHand
        .map((c) => GameCard.fromJson(Map<String, dynamic>.from(c)))
        .toList();

    return Player(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      hand: loadedHand,
      isHost: json['isHost'] ?? false,
      hasSaidUno: json['hasSaidUno'] ?? false,
    );
  }
}

class GameRoom {
  final String code;
  final String hostId;
  final GameStatus status;
  final List<Player> players;
  final List<GameCard> discardPile;
  final List<GameCard> deck;
  final int currentTurnIndex;
  final CardColor activeColor;
  final int pendingDrawCount;
  final bool isClockwise;
  final Map<String, int> scores;
  final List<ChatMessage> messages;

  GameRoom({
    required this.code,
    required this.hostId,
    required this.status,
    required this.players,
    required this.discardPile,
    required this.deck,
    required this.currentTurnIndex,
    required this.activeColor,
    required this.pendingDrawCount,
    required this.isClockwise,
    required this.scores,
    this.messages = const [],
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'hostId': hostId,
        'status': status.name,
        'players': players.map((p) => p.toJson()).toList(),
        'discardPile': discardPile.map((c) => c.toJson()).toList(),
        'deck': deck.map((c) => c.toJson()).toList(),
        'currentTurnIndex': currentTurnIndex,
        'activeColor': activeColor.name,
        'pendingDrawCount': pendingDrawCount,
        'isClockwise': isClockwise,
        'scores': scores,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory GameRoom.fromJson(Map<dynamic, dynamic> json) {
    var rawPlayers = json['players'] as List<dynamic>? ?? [];
    List<Player> loadedPlayers = rawPlayers
        .map((p) => Player.fromJson(Map<String, dynamic>.from(p)))
        .toList();

    var rawDiscard = json['discardPile'] as List<dynamic>? ?? [];
    List<GameCard> loadedDiscard = rawDiscard
        .map((c) => GameCard.fromJson(Map<String, dynamic>.from(c)))
        .toList();

    var rawDeck = json['deck'] as List<dynamic>? ?? [];
    List<GameCard> loadedDeck = rawDeck
        .map((c) => GameCard.fromJson(Map<String, dynamic>.from(c)))
        .toList();

    var rawScores = json['scores'] as Map<dynamic, dynamic>? ?? {};
    Map<String, int> loadedScores = rawScores.map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    );

    var rawMessages = json['messages'] as List<dynamic>? ?? [];
    List<ChatMessage> loadedMessages = rawMessages
        .map((m) => ChatMessage.fromJson(Map<dynamic, dynamic>.from(m)))
        .toList();

    GameStatus parsedStatus = GameStatus.waiting;
    if (json['status'] == 'playing') parsedStatus = GameStatus.playing;
    if (json['status'] == 'finished') parsedStatus = GameStatus.finished;

    CardColor parsedColor = CardColor.red;
    try {
      parsedColor = CardColor.values.byName(json['activeColor'] ?? 'red');
    } catch (_) {}

    return GameRoom(
      code: json['code'] ?? '',
      hostId: json['hostId'] ?? '',
      status: parsedStatus,
      players: loadedPlayers,
      discardPile: loadedDiscard,
      deck: loadedDeck,
      currentTurnIndex: json['currentTurnIndex'] ?? 0,
      activeColor: parsedColor,
      pendingDrawCount: json['pendingDrawCount'] ?? 0,
      isClockwise: json['isClockwise'] ?? true,
      scores: loadedScores,
      messages: loadedMessages,
    );
  }
}