/*******************************************************************************
  DetectorImpacto
  --------------
  Detecta picos de aceleración (impactos) usando la magnitud total del
  acelerómetro. Un impacto es únicamente un EVENTO puntual: no implica por
  sí mismo un accidente (eso lo decide AccidentStateMachine combinando más
  evidencia).

  Se aplica un período refractario para no contar múltiples veces el mismo
  impacto (rebotes / vibración tras el golpe).
*******************************************************************************/

class DetectorImpacto {

  // Magnitud de aceleración (en g) por encima de la cual se considera impacto.
  // En reposo la magnitud ronda 1g (gravedad); un golpe fuerte típicamente
  // supera 2.5g-3g en el pecho del piloto. Ajustar según pruebas de campo.
  final float UMBRAL_IMPACTO = 2.5;

  // Tiempo mínimo entre impactos consecutivos para no contar el mismo evento
  // varias veces por vibraciones posteriores al golpe.
  final int TIEMPO_REFRACTARIO = 500; // ms

  int ultimoImpactoMillis = -1000000;
  boolean impactoDetectado = false;

  void actualizar(float accelMag) {
    impactoDetectado = false;

    if (accelMag > UMBRAL_IMPACTO &&
        millis() - ultimoImpactoMillis > TIEMPO_REFRACTARIO) {

      impactoDetectado = true;
      ultimoImpactoMillis = millis();
      println("Impacto detectado. Magnitud=" + nf(accelMag, 1, 2) + "g");
    }
  }
}
