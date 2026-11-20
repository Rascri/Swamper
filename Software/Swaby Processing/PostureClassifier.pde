/*******************************************************************************
  PostureClassifier
  -----------------
  Clasifica la postura del piloto en 4 niveles usando la mayor inclinación
  relativa entre pitch y roll (max(|pitchRel|, |rollRel|)).

  Umbrales propuestos (grados), ajustables según pruebas de campo:
    NORMAL                : inclinación <= 15°
    INCLINACION_LEVE      : 15° - 35°
    INCLINACION_PRONUNCIADA: 35° - 60°
    POSTURA_INCOMPATIBLE  : > 60°  (ej: piloto caído / volcado)

  Para evitar oscilaciones por ruido se aplican dos mecanismos combinados:
    1) HISTÉRESIS: el umbral para "bajar" de un estado es más exigente que
       el umbral para "subir" (margen de HISTERESIS grados).
    2) DEBOUNCE TEMPORAL: un cambio de estado candidato solo se confirma si
       se mantiene estable durante TIEMPO_CONFIRMACION milisegundos.
*******************************************************************************/

class PostureClassifier {

  EstadoPostura estadoActual    = EstadoPostura.NORMAL;
  EstadoPostura estadoCandidato = EstadoPostura.NORMAL;
  int tiempoInicioCandidato = 0;

  final int TIEMPO_CONFIRMACION = 400; // ms que debe sostenerse el candidato

  // Umbrales de entrada (grados)
  final float UMBRAL_LEVE         = 15;
  final float UMBRAL_PRONUNCIADA  = 35;
  final float UMBRAL_INCOMPATIBLE = 60;

  // Margen de histéresis para volver a un estado "mejor"
  final float HISTERESIS = 5;

  void actualizar(float pitchRel, float rollRel) {
    float inclinacion = max(abs(pitchRel), abs(rollRel));
    EstadoPostura candidato = evaluarCandidato(inclinacion);

    if (candidato != estadoCandidato) {
      estadoCandidato = candidato;
      tiempoInicioCandidato = millis();
    }

    if (candidato != estadoActual &&
        millis() - tiempoInicioCandidato >= TIEMPO_CONFIRMACION) {
      estadoActual = candidato;
    }
  }

  // Determina el estado "crudo" según la inclinación actual y el estado
  // vigente (esto es lo que introduce la histéresis).
  EstadoPostura evaluarCandidato(float inclinacion) {
    switch (estadoActual) {

      case NORMAL:
        if (inclinacion > UMBRAL_INCOMPATIBLE)  return EstadoPostura.POSTURA_INCOMPATIBLE;
        if (inclinacion > UMBRAL_PRONUNCIADA)   return EstadoPostura.INCLINACION_PRONUNCIADA;
        if (inclinacion > UMBRAL_LEVE)          return EstadoPostura.INCLINACION_LEVE;
        return EstadoPostura.NORMAL;

      case INCLINACION_LEVE:
        if (inclinacion > UMBRAL_INCOMPATIBLE)  return EstadoPostura.POSTURA_INCOMPATIBLE;
        if (inclinacion > UMBRAL_PRONUNCIADA)   return EstadoPostura.INCLINACION_PRONUNCIADA;
        if (inclinacion < UMBRAL_LEVE - HISTERESIS) return EstadoPostura.NORMAL;
        return EstadoPostura.INCLINACION_LEVE;

      case INCLINACION_PRONUNCIADA:
        if (inclinacion > UMBRAL_INCOMPATIBLE)  return EstadoPostura.POSTURA_INCOMPATIBLE;
        if (inclinacion < UMBRAL_PRONUNCIADA - HISTERESIS) return EstadoPostura.INCLINACION_LEVE;
        return EstadoPostura.INCLINACION_PRONUNCIADA;

      case POSTURA_INCOMPATIBLE:
        if (inclinacion < UMBRAL_INCOMPATIBLE - HISTERESIS) return EstadoPostura.INCLINACION_PRONUNCIADA;
        return EstadoPostura.POSTURA_INCOMPATIBLE;
    }
    return EstadoPostura.NORMAL; // no debería alcanzarse
  }
}
