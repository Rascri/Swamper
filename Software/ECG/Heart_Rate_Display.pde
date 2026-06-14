/*******************************************************************************
  Heart_Rate_Display_Filtered_ESP32.pde

  Filtros:
  - Pasa alto IIR fc = 0.5Hz
  - Pasa bajo IIR fc = 40Hz
  - BPM con ventana deslizante de 10 latidos
*******************************************************************************/

import processing.serial.*;

Serial myPort;

// ─── Gráfica ─────────────────────────────────────────────────────────────────
int   xPos       = 1;
float height_old = 0;
float height_new = 0;
float inByte     = 0;
float filtered   = 0;

// ─── BPM ─────────────────────────────────────────────────────────────────────
int     BPM            = 0;
int     beat_old       = 0;
int     beatCounter    = 0;
final int BEAT_WIN     = 10;           // ventana de 10 latidos (era 500 con zeros)
float[] beats          = new float[BEAT_WIN];
int     beatIndex      = 0;
int     beatCount      = 0;            // cuántos latidos válidos hay en el array
int     refractoryPeriod = 250;
int     lastBeatTime   = 0;
float   threshold      = 2600.0;
boolean belowThreshold = true;
boolean beatDetected = false;

// ─── Parámetros de filtros ───────────────────────────────────────────────────
final float FS      = 250.0;
final float ADC_MID = 2048.0;
final float ADC_MAX = 4095.0;

// Pasa-altos IIR (fc = 0.5 Hz)
float alpha_HP;
float hp_prev_x, hp_prev_y;

// Pasa-bajos IIR (fc = 40 Hz)
float alpha_LP;
float lp_prev_y;

PFont font;

// ─────────────────────────────────────────────────────────────────────────────
void setup() {
  size(1000, 400);
  printArray(Serial.list());
  myPort = new Serial(this, "COM3", 115200);   // ← ajustar puerto
  myPort.bufferUntil('\n');
  background(0xFF);
  font = createFont("Arial", 12, true);
  textFont(font);

  // ── Calcular coeficientes AQUÍ para que cos/sin estén disponibles ──────────

// Pasa-altos 0.5 Hz
float FC_HP = 0.5;

alpha_HP = 1.0 / (1.0 + TWO_PI * FC_HP / FS);

hp_prev_x = ADC_MID;
hp_prev_y = ADC_MID;


// Pasa-bajos 40 Hz
float FC_LP = 40.0;

alpha_LP = (TWO_PI * FC_LP / FS) /
           (1.0 + TWO_PI * FC_LP / FS);

lp_prev_y = ADC_MID;

}

// ─────────────────────────────────────────────────────────────────────────────
void draw() {
  float display = map(filtered, 0, ADC_MAX, 0, height);
  height_new = height - display;
  line(xPos - 1, height_old, xPos, height_new);
  height_old = height_new;

  if (beatDetected) {
  stroke(0, 200, 0);
  line(xPos, 0, xPos, height);

  beatDetected = false;

  stroke(255,0,0);
}

  if (xPos >= width) {
    xPos = 0;
    background(0xFF);
    drawFilterStatus();
  } else {
    xPos++;
  }

  if (millis() % 128 == 0) {
    fill(0xFF);
    rect(0, 0, 260, 20);
    fill(0x00);
    textSize(13);
    text("BPM: " + BPM +
     "  Beats: " + beatCounter +
     "  TH: " + int(threshold),
     15, 14);
    drawFilterStatus();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
void drawFilterStatus() {
  fill(0xFF);
  rect(0, height - 22, width, 22);
  fill(60);
  textSize(11);

  text("[HP 0.5Hz]   [LP 40Hz]", 8, height - 7);
}

// ─────────────────────────────────────────────────────────────────────────────
void serialEvent(Serial myPort) {
  String inString = myPort.readStringUntil('\n');
  if (inString == null) return;
  inString = trim(inString);

  if (inString.equals("!")) {
    stroke(0, 0, 0xFF);
    inByte   = ADC_MID;
    filtered = ADC_MID;
    resetFilters();
  } else {
    stroke(0xFF, 0, 0);
    inByte   = float(inString);
    filtered = applyFilters(inByte);

if (filtered > threshold &&
    belowThreshold &&
    millis() - lastBeatTime > refractoryPeriod) {

  beatDetected = true;
  beatCounter++;

  println("BEAT #" + beatCounter +
          " ADC=" + int(filtered));

  lastBeatTime = millis();

  calculateBPM();

  belowThreshold = false;
}
else if (filtered < threshold) {
  belowThreshold = true;
}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
float applyFilters(float x) {

  float y = x;


  // Pasa altos
  float hp_out = alpha_HP * (hp_prev_y + y - hp_prev_x);
  hp_prev_x = y;
  hp_prev_y = hp_out;

  y = hp_out + ADC_MID;



  // Pasa bajos
  float lp_out = alpha_LP * y + (1.0 - alpha_LP) * lp_prev_y;
  lp_prev_y = lp_out;

  y = lp_out;


  return y;
}

// ─────────────────────────────────────────────────────────────────────────────
void resetFilters() {

  hp_prev_x = ADC_MID;
  hp_prev_y = ADC_MID;

  lp_prev_y = ADC_MID;

}

void calculateBPM() {
  int beat_new = millis();
  int diff     = beat_new - beat_old;

  // Validar rango fisiológico: 30–200 BPM → 300ms–2000ms entre latidos
  if (diff < 300 || diff > 2000) {
    beat_old = beat_new;
    return;
  }

  float currentBPM    = 60000.0 / diff;
  beats[beatIndex]    = currentBPM;
  beatIndex           = (beatIndex + 1) % BEAT_WIN;
  if (beatCount < BEAT_WIN) beatCount++;   // contar solo slots válidos

  float total = 0;
  for (int i = 0; i < beatCount; i++) total += beats[i];
  BPM      = int(total / beatCount);       // promedio solo sobre datos reales
  beat_old = beat_new;
}
