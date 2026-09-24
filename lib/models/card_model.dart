// lib/models/card_model.dart
enum CardColor { red, blue, green, yellow, wild }

enum CardType { number, skip, reverse, plusTwo, wild, plusFour }

class GameCard {
  final String id;
  final CardColor color;
  final CardType type;
  final int? number; // Solo para cartas numéricas (1 a 9)

  GameCard({
    required this.id,
    required this.color,
    required this.type,
    this.number,
  });

  /// Devuelve la ruta completa con 'assets/' para que Android y Web las carguen sin errores
  String get assetPath {
    String colorStr = '';
    switch (color) {
      case CardColor.red:
        colorStr = 'rojo';
        break;
      case CardColor.blue:
        colorStr = 'azul';
        break;
      case CardColor.green:
        colorStr = 'verde';
        break;
      case CardColor.yellow:
        colorStr = 'amarillo';
        break;
      case CardColor.wild:
        colorStr = 'negro';
        break;
    }

    // 1. Cartas numéricas (1 al 9)
    if (type == CardType.number) {
      return 'assets/$number$colorStr.png';
    }
    
    // 2. Cartas de +2
    if (type == CardType.plusTwo) {
      return 'assets/+2$colorStr.png';
    }
    
    // 3. Carta de +4
    if (type == CardType.plusFour) {
      return 'assets/+4negro.png';
    }
    
    // 4. Cartas de prohibido / Skip
    if (type == CardType.skip) {
      return 'assets/pro$colorStr.png';
    }
    
    // 5. Cartas de cambiar el orden / Reverse
    if (type == CardType.reverse) {
      return 'assets/swap$colorStr.png';
    }
    
    // 6. Comodín de cambio de color
    if (type == CardType.wild) {
      return 'assets/swapcolornegro.png';
    }

    return 'assets/icon.png';
  }

  bool canBePlayedOn(GameCard topDiscard, CardColor activeColor, int pendingDrawCount) {
    if (pendingDrawCount > 0) {
      if (topDiscard.type == CardType.plusTwo) {
        return type == CardType.plusTwo || type == CardType.plusFour;
      }
      if (topDiscard.type == CardType.plusFour) {
        return type == CardType.plusFour || type == CardType.plusTwo;
      }
    }

    if (color == CardColor.wild) return true;
    if (color == activeColor) return true;
    if (type == topDiscard.type && type != CardType.number) return true;
    if (type == CardType.number && topDiscard.type == CardType.number) {
      return number == topDiscard.number;
    }

    return false;
  }

  bool get isDrawCard => type == CardType.plusTwo || type == CardType.plusFour;

  int get drawAmount {
    if (type == CardType.plusTwo) return 2;
    if (type == CardType.plusFour) return 4;
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'color': color.name,
      'type': type.name,
      if (number != null) 'number': number,
    };
  }

  factory GameCard.fromJson(Map<String, dynamic> json) {
    return GameCard(
      id: json['id'] as String,
      color: CardColor.values.byName(json['color'] as String),
      type: CardType.values.byName(json['type'] as String),
      number: json['number'] as int?,
    );
  }
}