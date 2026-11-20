/*******************************************************************************
  PilotVestUI
  -----------
  Dibuja el panel superior con todos los valores en tiempo real solicitados,
  el botón de calibración y el color de fondo según el estado del sistema:
    - Verde  -> funcionamiento normal
    - Amarillo -> advertencia (postura pronunciada/incompatible o evaluando impacto)
    - Rojo   -> accidente confirmado / esperando inmovilidad / alerta inmóvil

  Importante: solo se recolorea/redibuja el panel superior (0,0 a width,
  panelAltura). La franja del ECG (dibujada por ECGModule) permanece
  independiente para no romper su scroll incremental.
*******************************************************************************/

class PilotVestUI {

  int panelAltura;

  // Botón de calibración (esquina superior derecha del panel)
  int btnX, btnY, btnW = 170, btnH = 40;

  PilotVestUI(int panelAltura) {
    this.panelAltura = panelAltura;
    this.btnX = width - btnW - 20;
    this.btnY = 20;
  }

  void dibujar(MPU6050Module mpu, PostureClassifier postura, DetectorImpacto impacto,
               AccidentStateMachine accidente, ECGModule ecg, CalibrationManager calib,
               ActivityMonitor actividad, String textoTemp) {

    color fondo = obtenerColorFondo(postura.estadoActual, accidente.estado);
    noStroke();
    fill(fondo);
    rect(0, 0, width, panelAltura);

    fill(0);
    textSize(14);
    int x = 15;
    int y = 24;
    int lineHeight = 20;

    text("SWAMPER — MONITOR DE ACTIVIDAD", x, y); y += lineHeight + 6;

    text("Pitch: " + nf(mpu.pitch, 1, 2) + "°    Roll: " + nf(mpu.roll, 1, 2) + "°", x, y); y += lineHeight;
    text("Pitch relativo: " + nf(mpu.pitchRel, 1, 2) + "°    Roll relativo: " + nf(mpu.rollRel, 1, 2) + "°", x, y); y += lineHeight;
    text("Magnitud aceleración: " + nf(mpu.accelMag, 1, 3) + " g", x, y); y += lineHeight;
    text("Magnitud giroscopio: " + nf(mpu.gyroMag, 1, 2) + " °/s", x, y); y += lineHeight;
    text("Inclinación (módulo): " + nombrePostura(postura.estadoActual), x, y); y += lineHeight;
    text("Impacto detectado: " + (impacto.impactoDetectado ? "SÍ" : "no"), x, y); y += lineHeight;
    text("Caída: " + nombreAccidente(accidente.estado), x, y); y += lineHeight;
    text("ECG — BPM: " + ecg.BPM + "    Latidos: " + ecg.beatCounter, x, y); y += lineHeight;
    text("Calibración: " + estadoCalibracionTexto(calib), x, y); y += lineHeight + 4;

    if (accidente.hayCaida()) {
      fill(255);
      textSize(18);
      text("¡¡ CAÍDA DETECTADA !!", x, y);
    }

    dibujarBotonCalibracion(calib);
    dibujarActividad(actividad, textoTemp);
  }

  // Columna central del panel: temperatura, movimiento y actividad
  void dibujarActividad(ActivityMonitor act, String textoTemp) {
    int x = 520; // más a la derecha: el texto de "Posible caída" de la izquierda pisaba 480
    int y = 24;
    int lineHeight = 20;

    fill(0);
    textSize(14);
    text("Temperatura: " + textoTemp, x, y); y += lineHeight;
    text("Movimiento: " + (act.nivel == NivelActividad.SIN_DATOS ? "sin datos" :
                           act.nivel == NivelActividad.REPOSO ? "QUIETO" : "EN MOVIMIENTO"), x, y); y += lineHeight;
    text("Actividad: " + nombreNivel(act.nivel) + "  (índice " + nf(act.indice, 1, 3) + ")", x, y); y += lineHeight;
    int s = act.quietoMs() / 1000;
    text("Tiempo sin movimiento: " + (act.nivel == NivelActividad.SIN_DATOS ? "-" : nf(s / 60, 2) + ":" + nf(s % 60, 2)), x, y); y += lineHeight;
    text("Sin movimiento prolongado: " + (act.inactividadProlongada ? "SÍ" : "no"), x, y);
  }

  void dibujarBotonCalibracion(CalibrationManager calib) {
    fill(calib.calibrando ? color(150, 150, 30) : color(40, 60, 180));
    stroke(0);
    rect(btnX, btnY, btnW, btnH, 8);

    fill(255);
    noStroke();
    textAlign(CENTER, CENTER);
    textSize(14);
    text(calib.calibrando ? "Calibrando..." : "Calibrar", btnX + btnW / 2, btnY + btnH / 2);
    textAlign(LEFT, BASELINE);
  }

  boolean click(int mx, int my) {
    return mx >= btnX && mx <= btnX + btnW && my >= btnY && my <= btnY + btnH;
  }

  color obtenerColorFondo(EstadoPostura postura, EstadoAccidente accidente) {
    if (accidente == EstadoAccidente.CAIDA) {
      return color(210, 45, 45); // rojo
    }

    if (accidente == EstadoAccidente.EVALUANDO_IMPACTO ||
        postura == EstadoPostura.INCLINACION_PRONUNCIADA ||
        postura == EstadoPostura.POSTURA_INCOMPATIBLE) {
      return color(230, 195, 40); // amarillo
    }

    return color(90, 195, 100); // verde
  }

  String nombrePostura(EstadoPostura p) {
    switch (p) {
      case NORMAL: return "NORMAL";
      case INCLINACION_LEVE: return "INCLINACIÓN LEVE";
      case INCLINACION_PRONUNCIADA: return "INCLINACIÓN PRONUNCIADA";
      case POSTURA_INCOMPATIBLE: return "POSTURA INCOMPATIBLE";
    }
    return "-";
  }

  String nombreNivel(NivelActividad n) {
    switch (n) {
      case SIN_DATOS: return "sin datos";
      case REPOSO: return "REPOSO";
      case LIGERA: return "LIGERA";
      case ELEVADA: return "ELEVADA";
    }
    return "-";
  }

  String nombreAccidente(EstadoAccidente a) {
    switch (a) {
      case MONITOREANDO: return "monitoreando";
      case EVALUANDO_IMPACTO: return "evaluando impacto...";
      case CAIDA: return "CAÍDA DETECTADA";
    }
    return "-";
  }

  String estadoCalibracionTexto(CalibrationManager c) {
    if (c.calibrando) return "en progreso...";
    if (c.calibrado) return "OK";
    return "pendiente (presionar Calibrar)";
  }
}
