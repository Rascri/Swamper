/*******************************************************************************
  CalibrationManager
  ------------------
  Al llamar iniciarCalibracion(), durante DURACION_MS milisegundos acumula
  las muestras de pitch/roll (absolutos) que van llegando en cada frame y,
  al finalizar la ventana, calcula el promedio y lo fija como referencia en
  el MPU6050Module. A partir de ese momento, pitchRel/rollRel = 0 en la
  postura de calibración.
*******************************************************************************/

class CalibrationManager {

  boolean calibrando = false;
  boolean calibrado   = false;

  int tiempoInicio;
  final int DURACION_MS = 2000; // ~2 segundos de muestreo

  float sumaPitch   = 0;
  float sumaSinRoll = 0;
  float sumaCosRoll = 0;
  int   muestras    = 0;

  void iniciarCalibracion() {
    calibrando = true;
    calibrado  = false;
    tiempoInicio = millis();
    sumaPitch   = 0;
    sumaSinRoll = 0;
    sumaCosRoll = 0;
    muestras    = 0;
    println("Calibración iniciada. Mantener postura de referencia...");
  }

  // Debe llamarse en cada frame (draw). Si no está calibrando, no hace nada.
  void actualizar(MPU6050Module mpu) {
    if (!calibrando) return;

    // Solo se acumulan muestras vigentes: si el MPU6050 no transmite, mpu.pitch/roll
    // son valores viejos y la calibración "exitosa" fijaría una referencia falsa.
    if (mpu.datosRecientes()) {
      sumaPitch += mpu.pitch;
      sumaSinRoll += sin(radians(mpu.roll));
      sumaCosRoll += cos(radians(mpu.roll));
      muestras++;
    }

    if (millis() - tiempoInicio >= DURACION_MS) {
      if (muestras > 0) {
        float pitchRef = sumaPitch / muestras;
        // Media circular: un promedio simple de roll cerca de ±180° da ~0°.
        float rollRef  = degrees(atan2(sumaSinRoll, sumaCosRoll));
        mpu.setReferencia(pitchRef, rollRef);
        println("Calibración completa -> pitchRef=" + nf(pitchRef, 1, 2) +
                "  rollRef=" + nf(rollRef, 1, 2) + "  (" + muestras + " muestras)");
      } else {
        println("Calibración fallida: no se recibieron muestras del MPU6050.");
      }
      calibrando = false;
      calibrado  = true;
    }
  }
}
