import '../models/card_model.dart';

class GameRules {
  /// Valida si se puede jugar [playedCard] sobre [topCard].
  /// [pendingDrawCards] es el acumulado actual de robo (+2 / +4).
  static bool isValidMove({
    required GameCard playedCard,
    required GameCard topCard,
    required CardColor currentColor,
    required int pendingDrawCards,
  }) {
    // REGLA DE STACKEO ACTIVO:
    // Si hay un castigo acumulado (>0), SOLO se puede responder con cartas de robo.
    if (pendingDrawCards > 0) {
      if (!playedCard.isDrawCard) return false;

      // Opcional avanzado: Si la carta acumulada en juego es un +2, 
      // puedes estancar con otro +2 o un +4. Si es un +4, idealmente solo con +4 o según tus reglas.
      // Aquí permitimos que cualquier carta de robo responda si cumple el principio de stackeo.
      
      // Si la carta jugada es un Comodín +4, siempre se puede usar para stackear.
      if (playedCard.type == CardType.plusFour) return true;

      // Si es un +2, solo puede responder si la carta superior también es un +2 (o un +4).
      if (playedCard.type == CardType.plusTwo && topCard.isDrawCard) {
        return true;
      }

      return false;
    }

    // REGLA NORMAL (sin stackeo pendiente):
    // 1. Carta comodín / cambio de color o +4 libre siempre es válida.
    if (playedCard.color == CardColor.wild || playedCard.type == CardType.plusFour) {
      return true;
    }

    // 2. Coincidencia por color actual.
    if (playedCard.color == currentColor) return true;

    // 3. Coincidencia por tipo de carta especial (ej: Bloqueo sobre Bloqueo, Cambio sobre Cambio).
    if (playedCard.type == topCard.type && playedCard.type != CardType.number) {
      return true;
    }

    // 4. Coincidencia por número exacto.
    if (playedCard.type == CardType.number &&
        topCard.type == CardType.number &&
        playedCard.number == topCard.number) {
      return true;
    }

    return false;
  }
}