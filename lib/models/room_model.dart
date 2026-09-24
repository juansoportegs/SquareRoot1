// lib/models/room_model.dart
import 'card_model.dart';

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'hand': hand.map((c) => c.toJson()).toList(),
      'isHost': isHost,
      'hasSaidUno': hasSaidUno,
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      hand: (json['hand'] as List<dynamic>?)
              ?.map((c) => GameCard.fromJson(Map<String, dynamic>.from(c)))
              .toList() ??
          [],
      isHost: json['isHost'] as bool? ?? false,
      hasSaidUno: json['hasSaidUno'] as bool? ?? false,
    );
  }
}

enum GameStatus { waiting, playing, finished }

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
  });

  Map<String, dynamic> toJson() {
    return {
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
    };
  }

  factory GameRoom.fromJson(Map<String, dynamic> json) {
    return GameRoom(
      code: json['code'] as String,
      hostId: json['hostId'] as String,
      status: GameStatus.values.byName(json['status'] as String),
      players: (json['players'] as List<dynamic>?)
              ?.map((p) => Player.fromJson(Map<String, dynamic>.from(p)))
              .toList() ??
          [],
      discardPile: (json['discardPile'] as List<dynamic>?)
              ?.map((c) => GameCard.fromJson(Map<String, dynamic>.from(c)))
              .toList() ??
          [],
      deck: (json['deck'] as List<dynamic>?)
              ?.map((c) => GameCard.fromJson(Map<String, dynamic>.from(c)))
              .toList() ??
          [],
      currentTurnIndex: json['currentTurnIndex'] as int? ?? 0,
      activeColor: CardColor.values.byName(json['activeColor'] as String? ?? 'red'),
      pendingDrawCount: json['pendingDrawCount'] as int? ?? 0,
      isClockwise: json['isClockwise'] as bool? ?? true,
      scores: Map<String, int>.from(json['scores'] ?? {}),
    );
  }
}