enum CardColor { red, blue, green, yellow, wild }

enum CardType {
  number,
  skip,       // Salto de turno
  reverse,    // Cambio de sentido
  drawTwo,    // +2
  wild,       // Cambio de color
  wildDrawFour // +4
}

class UNOCard {
  final CardColor color;
  final CardType type;
  final int? value; // Para cartas numéricas (0-9)

  UNOCard({
    required this.color,
    required this.type,
    this.value,
  });

  /// Determina si esta carta se puede jugar sobre la carta actual de la mesa
  /// teniendo en cuenta el color activo y el contador de acumulación (+2 / +4).
  bool canBePlayedOn(UNOCard topCard, CardColor activeColor, int pendingDrawCount) {
    // Si hay un castigo acumulado (+2 o +4)
    if (pendingDrawCount > 0) {
      if (topCard.type == CardType.drawTwo) {
        return type == CardType.drawTwo || type == CardType.wildDrawFour;
      }
      if (topCard.type == CardType.wildDrawFour) {
        return type == CardType.wildDrawFour || type == CardType.drawTwo;
      }
    }

    // Reglas normales de descarte
    if (type == CardType.wild || type == CardType.wildDrawFour) {
      return true;
    }
    if (color == activeColor) {
      return true;
    }
    if (type == CardType.number && topCard.type == CardType.number) {
      return value == topCard.value;
    }
    return type == topCard.type;
  }
}