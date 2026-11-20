/*******************************************************************************
  ActivityMonitor
  ---------------
  Estima quietud, nivel de actividad e inactividad prolongada usando solo
  magnitudes del MPU6050 (aceleración dinámica y giroscopio), por lo que no
  depende de cómo esté orientado el sensor dentro del chaleco.

  Índice de actividad (en g-equivalentes): media exponencial (TAU_S) de
      max( |accelMag - 1 g| , gyroMag / GYRO_POR_G )
  Niveles REPOSO / LIGERA / ELEVADA según UMBRAL_LIGERA y UMBRAL_ELEVADA, con
  histéresis (para bajar de nivel el índice debe caer por debajo de
  umbral * HISTERESIS) y debounce (el cambio debe sostenerse CONFIRMACION_MS).

  IMPORTANTE: los umbrales son valores iniciales PROVISIONALES, no una
  clasificación validada. Hay que ajustarlos observando el índice (se muestra
  en pantalla) durante actividades reales con el chaleco puesto.

  "Sin movimiento prolongado" solo indica ausencia de movimiento durante
  INACTIVIDAD_MS: no permite inferir el estado de conciencia de la persona.
*******************************************************************************/

class ActivityMonitor {

  NivelActividad nivel = NivelActividad.SIN_DATOS;
  float indice = 0;
  boolean inactividadProlongada = false;

  // ── Parámetros configurables (valores iniciales provisionales) ────────────
  final float TAU_S          = 2.0;   // s: suavizado del índice
  final float GYRO_POR_G     = 200.0; // °/s que pesan como 1 g en el índice
  final float UMBRAL_LIGERA  = 0.04;  // índice a partir del cual hay actividad ligera
  final float UMBRAL_ELEVADA = 0.20;  // índice a partir del cual la actividad es elevada
  final float HISTERESIS     = 0.7;   // factor del umbral para bajar de nivel
  final int   CONFIRMACION_MS = 1000; // ms que debe sostenerse un cambio de nivel
  final int   INACTIVIDAD_MS  = 10 * 60 * 1000; // quietud continua = "sin movimiento prolongado"

  int ultimoMillis = 0;
  int inicioQuietudMillis = 0;
  NivelActividad candidato = NivelActividad.SIN_DATOS;
  int inicioCandidatoMillis = 0;

  // Se llama una vez por frame (draw).
  void actualizar(MPU6050Module mpu) {
    int ahora = millis();
    float dt = constrain((ahora - ultimoMillis) / 1000.0, 0, 0.5);
    ultimoMillis = ahora;

    if (!mpu.datosRecientes()) {
      nivel = NivelActividad.SIN_DATOS;
      candidato = NivelActividad.SIN_DATOS;
      inactividadProlongada = false;
      inicioQuietudMillis = ahora;
      return;
    }

    float instantaneo = max(abs(mpu.accelMag - 1.0), mpu.gyroMag / GYRO_POR_G);
    indice += (instantaneo - indice) * dt / (TAU_S + dt);

    NivelActividad c = evaluar(indice);
    if (c != candidato) {
      candidato = c;
      inicioCandidatoMillis = ahora;
    }
    if (c != nivel && ahora - inicioCandidatoMillis >= CONFIRMACION_MS) {
      nivel = c;
    }

    if (nivel != NivelActividad.REPOSO) inicioQuietudMillis = ahora;
    inactividadProlongada = nivel == NivelActividad.REPOSO &&
                            ahora - inicioQuietudMillis >= INACTIVIDAD_MS;
  }

  // Nivel "crudo" según el índice; la histéresis depende del nivel vigente.
  NivelActividad evaluar(float v) {
    boolean activo = (nivel == NivelActividad.LIGERA || nivel == NivelActividad.ELEVADA);
    if (v > UMBRAL_ELEVADA * (nivel == NivelActividad.ELEVADA ? HISTERESIS : 1)) return NivelActividad.ELEVADA;
    if (v > UMBRAL_LIGERA  * (activo ? HISTERESIS : 1))                          return NivelActividad.LIGERA;
    return NivelActividad.REPOSO;
  }

  // Milisegundos de quietud continua (0 si no está en reposo)
  int quietoMs() {
    return nivel == NivelActividad.REPOSO ? millis() - inicioQuietudMillis : 0;
  }
}
