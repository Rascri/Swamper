/*******************************************************************************
  AccidentStateMachine
  --------------------
  Detector de caída simple. Solo informa "caída sí / no"; no bloquea ni
  altera el ECG ni ninguna otra lectura.

  1) MONITOREANDO      : espera un impacto.
  2) EVALUANDO_IMPACTO : ventana de VENTANA_EVALUACION_MS tras el impacto.
                         Al cerrarla, es caída si hay al menos 2 de 3 evidencias:
                           - el impacto (siempre cuenta)
                           - cambio brusco de orientación (> UMBRAL_CAMBIO_ORIENTACION)
                           - postura final PRONUNCIADA o INCOMPATIBLE
  3) CAIDA             : se mantiene mientras la postura siga alterada. Cuando la
                         postura vuelve a NORMAL / LEVE y se sostiene
                         RECUPERACION_MS, el estado vuelve solo a MONITOREANDO.
*******************************************************************************/

class AccidentStateMachine {

  EstadoAccidente estado = EstadoAccidente.MONITOREANDO;

  final int   VENTANA_EVALUACION_MS = 2000;
  final float UMBRAL_CAMBIO_ORIENTACION = 45; // grados
  final int   RECUPERACION_MS = 3000;         // postura normal sostenida => fin de la caída

  int   tiempoInicioEvaluacion;
  int   tiempoInicioRecuperacion;
  float pitchRelAlImpacto, rollRelAlImpacto;
  boolean cambioOrientacionDetectado;

  void actualizar(boolean impactoDetectado, float pitchRel, float rollRel,
                  EstadoPostura posturaActual) {

    boolean posturaAlterada = posturaActual == EstadoPostura.INCLINACION_PRONUNCIADA ||
                              posturaActual == EstadoPostura.POSTURA_INCOMPATIBLE;

    switch (estado) {

      case MONITOREANDO:
        if (impactoDetectado) {
          estado = EstadoAccidente.EVALUANDO_IMPACTO;
          tiempoInicioEvaluacion = millis();
          pitchRelAlImpacto = pitchRel;
          rollRelAlImpacto  = rollRel;
          cambioOrientacionDetectado = false;
        }
        break;

      case EVALUANDO_IMPACTO:
        if (abs(pitchRel - pitchRelAlImpacto) > UMBRAL_CAMBIO_ORIENTACION ||
            abs(rollRel  - rollRelAlImpacto)  > UMBRAL_CAMBIO_ORIENTACION) {
          cambioOrientacionDetectado = true;
        }

        if (millis() - tiempoInicioEvaluacion >= VENTANA_EVALUACION_MS) {
          int evidencias = 1; // el impacto siempre cuenta
          if (cambioOrientacionDetectado) evidencias++;
          if (posturaAlterada) evidencias++;

          if (evidencias >= 2) {
            estado = EstadoAccidente.CAIDA;
            tiempoInicioRecuperacion = millis();
            println("CAÍDA detectada (evidencias=" + evidencias + ")");
          } else {
            estado = EstadoAccidente.MONITOREANDO;
          }
        }
        break;

      case CAIDA:
        // Si la postura sigue alterada, se reinicia el conteo de recuperación.
        if (posturaAlterada) tiempoInicioRecuperacion = millis();
        else if (millis() - tiempoInicioRecuperacion >= RECUPERACION_MS) {
          estado = EstadoAccidente.MONITOREANDO;
          println("Postura normal sostenida: fin de la caída.");
        }
        break;
    }
  }

  boolean hayCaida() {
    return estado == EstadoAccidente.CAIDA;
  }

  // Reinicio manual (pruebas)
  void reset() {
    estado = EstadoAccidente.MONITOREANDO;
    cambioOrientacionDetectado = false;
  }
}
