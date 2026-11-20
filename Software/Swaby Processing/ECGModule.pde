/*******************************************************************************
  ECGModule
  ---------
  Contiene, sin cambios en la lógica, el algoritmo original de detección de
  latidos (filtro pasa-altos + pasa-bajos en cascada, umbral y período
  refractario) encapsulado en una clase para integrarse con el resto del
  chaleco. Se agrega dibujarOnda(yOffset, altura) para poder ubicar la
  gráfica en una franja específica de la ventana compartida con el módulo
  de postura/accidente.
*******************************************************************************/

class ECGModule {

  // ── Parámetros de filtros (idénticos al proyecto original) ────────────────
  final float FS      = 250.0;
  final float ADC_MID = 2048.0;
  final float ADC_MAX = 4095.0;

  float alpha_HP, alpha_LP;
  float hp_prev_x, hp_prev_y, lp_prev_y;

  // ── Gráfica ─────────────────────────────────────────────────────────────
  int xPos = 1;
  float ultimaY = -1; // -1 indica "sin punto previo" (recién reiniciado)
  float inByte = 0;
  float filtered = 0;
  boolean beatDetected = false;

  // ── BPM ─────────────────────────────────────────────────────────────────
  int BPM = 0;
  int beat_old = 0;
  int beatCounter = 0;
  int refractoryPeriod = 400; // ms (rango sugerido original: 250-400)
  int lastBeatTime = 0;
  float threshold = 3500.0;
  boolean belowThreshold = true;

  ECGModule() {
    // Pasa-altos 0.5 Hz
    float FC_HP = 0.5;
    alpha_HP = 1.0 / (1.0 + TWO_PI * FC_HP / FS);
    hp_prev_x = ADC_MID;
    hp_prev_y = ADC_MID;

    // Pasa-bajos 40 Hz
    float FC_LP = 40.0;
    alpha_LP = (TWO_PI * FC_LP / FS) / (1.0 + TWO_PI * FC_LP / FS);
    lp_prev_y = ADC_MID;
  }

  // Procesa una línea recibida por el puerto Serie del ECG: o bien "!" (marca
  // de reinicio/desconexión) o bien un valor ADC en texto plano.
  void procesarLinea(String inString) {
    if (inString.equals("!")) {
      inByte = ADC_MID;
      filtered = ADC_MID;
      resetFiltros();
      encolar(filtered);
      return;
    }

    // float() de Processing NO lanza excepción: devuelve NaN si el texto no es
    // numérico. Un NaN que entre a los filtros IIR los contamina para siempre.
    float valor = float(inString.trim());
    if (Float.isNaN(valor)) {
      println("Dato ECG inválido, se ignora: " + inString);
      return;
    }
    inByte = valor;

    filtered = aplicarFiltros(inByte);
    encolar(filtered);

    if (filtered > threshold && belowThreshold &&
        millis() - lastBeatTime > refractoryPeriod) {

      beatDetected = true;
      beatCounter++;
      println("BEAT #" + beatCounter + " ADC=" + int(filtered));
      lastBeatTime = millis();
      calcularBPM();
      belowThreshold = false;

    } else if (filtered < threshold) {
      belowThreshold = true;
    }
  }

  // Muestras filtradas pendientes de enviar a la pantalla (las produce serialEvent,
  // las consume draw): hace falta cola porque llegan a 250 Hz y draw corre a ~60 Hz.
  final ArrayList<Integer> cola = new ArrayList<Integer>();

  void encolar(float v) {
    synchronized (cola) {
      if (cola.size() < 500) cola.add(constrain(round(v), 0, 4095));
    }
  }

  int[] vaciarCola() {
    synchronized (cola) {
      int[] r = new int[cola.size()];
      for (int i = 0; i < r.length; i++) r[i] = cola.get(i);
      cola.clear();
      return r;
    }
  }

  float aplicarFiltros(float x) {
    float y = x;

    // Pasa-altos
    float hp_out = alpha_HP * (hp_prev_y + y - hp_prev_x);
    hp_prev_x = y;
    hp_prev_y = hp_out;
    y = hp_out + ADC_MID;

    // Pasa-bajos
    float lp_out = alpha_LP * y + (1.0 - alpha_LP) * lp_prev_y;
    lp_prev_y = lp_out;
    y = lp_out;

    return y;
  }

  void resetFiltros() {
    hp_prev_x = ADC_MID;
    hp_prev_y = ADC_MID;
    lp_prev_y = ADC_MID;
  }

  void calcularBPM() {
    int beat_new = millis();
    int diff = beat_new - beat_old;

    // Validar rango fisiológico: 30-200 BPM -> 300ms-2000ms entre latidos
    if (diff < 300 || diff > 2000) {
      beat_old = beat_new;
      return;
    }

    float currentBPM = 60000.0 / diff;
    if (BPM == 0) BPM = int(currentBPM);
    else BPM = int(0.8 * BPM + 0.2 * currentBPM);

    beat_old = beat_new;
  }

  // Dibuja la onda ECG dentro de una franja horizontal de la ventana:
  // desde y=yOffset hasta y=yOffset+altura. La franja permanece blanca y el
  // trazo se dibuja incrementalmente (no se borra toda la ventana en cada
  // frame, igual que en el sketch original).
  void dibujarOnda(int yOffset, int altura) {
    float display = map(filtered, 0, ADC_MAX, 0, altura);
    // Con artefactos de movimiento (caída, golpe) la señal filtrada puede salir de
    // 0-4095: sin límite el trazo se dibujaría fuera de la franja (sobre el panel,
    // que se repinta cada frame, o fuera de la ventana) y parecería que se detuvo.
    float yNueva = constrain(yOffset + altura - display, yOffset, yOffset + altura - 1);

    stroke(200, 0, 0);
    if (ultimaY < 0) ultimaY = yNueva; // primer punto tras un reinicio
    line(xPos - 1, ultimaY, xPos, yNueva);
    ultimaY = yNueva;

    if (beatDetected) {
      stroke(0, 180, 0);
      line(xPos, yOffset, xPos, yOffset + altura);
      beatDetected = false;
    }

    if (xPos >= width) {
      xPos = 0;
      ultimaY = -1;
      noStroke();
      fill(255);
      rect(0, yOffset, width, altura); // limpia solo la franja del ECG
    } else {
      xPos++;
    }
  }
}
