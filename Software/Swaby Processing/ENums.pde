/*******************************************************************************
  Enumeraciones compartidas por varios módulos.
  Se separan en su propio archivo para que cualquier clase pueda referenciarlas
  sin depender del orden de las pestañas.
*******************************************************************************/

// Estado de postura del piloto (basado en pitch/roll relativos a la calibración)
enum EstadoPostura {
  NORMAL,
  INCLINACION_LEVE,
  INCLINACION_PRONUNCIADA,
  POSTURA_INCOMPATIBLE
}

// Estado de la máquina de accidente
enum EstadoAccidente {
  MONITOREANDO,      // operación normal, esperando un impacto
  EVALUANDO_IMPACTO, // impacto detectado, ventana de análisis en curso
  CAIDA              // caída detectada; se limpia sola al recuperar postura normal
}

// Nivel de actividad estimado a partir del MPU6050 (ver ActivityMonitor)
enum NivelActividad {
  SIN_DATOS, // no llegan muestras del MPU6050
  REPOSO,    // sin movimiento significativo
  LIGERA,
  ELEVADA
}
