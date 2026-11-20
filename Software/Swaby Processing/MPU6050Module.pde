/*******************************************************************************
  MPU6050Module
  -------------
  Recibe muestras crudas (ax,ay,az en g; gx,gy,gz en °/s; timestamp en ms) y
  calcula, usando SIEMPRE el deltaTime real entre muestras (no se asume una
  frecuencia fija):

    - Pitch y Roll absolutos, mediante filtro complementario (acelerómetro +
      integración del giroscopio).
    - Pitch y Roll relativos a una referencia de calibración (ver
      CalibrationManager).
    - Magnitud de aceleración total (para detección de impacto).
    - Magnitud del giroscopio total (para detectar movimiento/inmovilidad).

  Convención de ejes asumida (ajustar signos si el montaje físico difiere):
    pitchAcc = atan2(-ax, sqrt(ay² + az²))
    rollAcc  = atan2( ay, az)
*******************************************************************************/

class MPU6050Module {

  // ── Últimos valores crudos recibidos ──────────────────────────────────────
  float ax, ay, az;
  float gx, gy, gz;

  // ── Control de tiempo ─────────────────────────────────────────────────────
  long  ultimoTimestamp = -1;
  float deltaTime = 0.01; // segundos; valor inicial razonable hasta la 2da muestra

  // ── Orientación ────────────────────────────────────────────────────────────
  float pitch = 0;
  float roll  = 0;

  float pitchRef = 0; // fijado por CalibrationManager
  float rollRef  = 0;

  float pitchRel = 0;
  float rollRel  = 0;

  // ── Magnitudes ─────────────────────────────────────────────────────────────
  float accelMag = 1.0; // en reposo debería rondar 1g
  float gyroMag  = 0.0; // en reposo debería rondar 0°/s

  // ── Vigencia de los datos (para distinguir "quieto" de "sin datos") ────────
  int ultimaMuestraMillis = -1000000;
  final int TIMEOUT_MPU_MS = 1000;

  // ── Parámetro del filtro complementario ────────────────────────────────────
  // Cerca de 1.0 -> confía más en el giroscopio (suave, pero deriva con el tiempo)
  // Más bajo     -> confía más en el acelerómetro (más ruidoso, sin deriva)
  final float ALPHA_COMPLEMENTARIO = 0.98;

  // Límites de seguridad para deltaTime: evita saltos irreales si se pierde
  // algún paquete Bluetooth o el ESP32 se reconecta.
  final float DT_MIN = 0.001; // 1 ms
  final float DT_MAX = 0.5;   // 500 ms

  void update(long timestamp, float ax, float ay, float az,
              float gx, float gy, float gz) {

    this.ax = ax; this.ay = ay; this.az = az;
    this.gx = gx; this.gy = gy; this.gz = gz;

    // ── Cálculo de deltaTime real ────────────────────────────────────────────
    if (ultimoTimestamp < 0) {
      deltaTime = 0.01; // primera muestra: no hay referencia previa
    } else {
      deltaTime = (timestamp - ultimoTimestamp) / 1000.0;
      deltaTime = constrain(deltaTime, DT_MIN, DT_MAX);
    }
    ultimoTimestamp = timestamp;
    ultimaMuestraMillis = millis();

    // ── Ángulos derivados únicamente del acelerómetro (ruidosos, sin deriva) ──
    float pitchAcc = degrees(atan2(-ax, sqrt(ay * ay + az * az)));
    float rollAcc  = degrees(atan2(ay, az));

    // ── Filtro complementario: combina integración del giroscopio (suave) ────
    //    con la referencia absoluta del acelerómetro (corrige la deriva) ──────
    // Equivale a alpha*giro + (1-alpha)*acc, pero corrigiendo con la diferencia
    // angular envuelta a ±180°: el roll pasa de +180 a -180 cuando el piloto
    // queda boca abajo y la fórmula original lo "arrastraba" por el lado largo.
    float pitchGiro = pitch + gy * deltaTime;
    float rollGiro  = roll  + gx * deltaTime;
    pitch = normalizarAngulo(pitchGiro + (1 - ALPHA_COMPLEMENTARIO) * diferenciaAngular(pitchAcc, pitchGiro));
    roll  = normalizarAngulo(rollGiro  + (1 - ALPHA_COMPLEMENTARIO) * diferenciaAngular(rollAcc,  rollGiro));

    // ── Valores relativos a la calibración (también envueltos a ±180°) ───────
    pitchRel = diferenciaAngular(pitch, pitchRef);
    rollRel  = diferenciaAngular(roll,  rollRef);

    // ── Magnitudes (para impacto e inmovilidad) ───────────────────────────────
    accelMag = sqrt(ax * ax + ay * ay + az * az);
    gyroMag  = sqrt(gx * gx + gy * gy + gz * gz);

    // Pico desde la última lectura: draw() corre a ~60 Hz y las muestras llegan
    // a 100 Hz, así que leer solo accelMag perdería golpes de 1-2 muestras.
    synchronized (this) {
      accelMagPico = max(accelMagPico, accelMag);
    }
  }

  // Máxima magnitud de aceleración desde la llamada anterior (y reinicia el pico).
  synchronized float consumirPicoAccel() {
    float p = accelMagPico;
    accelMagPico = accelMag;
    return p;
  }

  float accelMagPico = 1.0;

  // Diferencia a - b envuelta al rango [-180, 180]
  float diferenciaAngular(float a, float b) {
    float d = (a - b) % 360;
    if (d > 180)  d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  float normalizarAngulo(float a) {
    return diferenciaAngular(a, 0);
  }

  // true si llegaron muestras del MPU6050 recientemente
  boolean datosRecientes() {
    return millis() - ultimaMuestraMillis < TIMEOUT_MPU_MS;
  }

  // Establece la referencia de calibración (llamado por CalibrationManager)
  void setReferencia(float pitchRef, float rollRef) {
    this.pitchRef = pitchRef;
    this.rollRef  = rollRef;
  }
}
