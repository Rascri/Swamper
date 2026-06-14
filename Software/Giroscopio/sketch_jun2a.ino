#include <Wire.h>
#include <MPU6050.h>
#include <math.h>

MPU6050 mpu;

// =========================================================
// ESCALAS DEL SENSOR
// =========================================================
const float ACCEL_ESCALA = 16384.0f; // ±2g  → 16384 LSB/g
const float GYRO_ESCALA  = 131.0f;   // ±250°/s → 131 LSB/°/s

// =========================================================
// UMBRALES — ajustar según pruebas reales
// =========================================================

// Postura (en grados respecto al eje vertical)
const float ANGULO_PARADO    = 35.0f; // < 35° = PARADO
const float ANGULO_INCLINADO = 65.0f; // 35-65° = INCLINADO, >65° = ACOSTADO

// Actividad (magnitud del giroscopio en °/s, filtrada)
const float ACT_QUIETO  = 15.0f;
const float ACT_LEVE    = 80.0f;

// Detección de caída
const float LIBRE_MIN    = 0.40f;  // g — por debajo = caída libre
const float IMPACTO_MIN  = 2.50f;  // g — pico de impacto
const unsigned long VENTANA_IMPACTO_MS = 600; // ms para esperar impacto

// Detección de desmayo
const float GIRO_DESMAYO_MAX          = 40.0f;  // °/s — rotación "lenta/laxa"
const unsigned long TIEMPO_COLAPSO_MS = 3000;   // ms máx de transición parado→acostado
const unsigned long COLAPSO_MIN_MS    = 1000;   // ms mín para confirmar desmayo (vs caída)

// Inactividad
const unsigned long TIEMPO_INACTIVIDAD_S = 300; // segundos sin movimiento

// =========================================================
// TIPOS
// =========================================================
enum Postura   { PARADO, INCLINADO, ACOSTADO };
enum Actividad { QUIETO, LEVE, INTENSO };

// Estados de la máquina de eventos
enum Evento {
  EV_NORMAL,
  EV_CAIDA_LIBRE,    // accel cayó — esperando impacto
  EV_CAIDA,          // ⚠ impacto confirmado tras caída libre
  EV_COLAPSO_LENTO,  // persona inclinándose despacio — candidato desmayo
  EV_DESMAYO         // ⚠ llegó a horizontal lentamente
};

// =========================================================
// VARIABLES GLOBALES
// =========================================================
Postura   estadoPostura   = PARADO;
Actividad estadoActividad = QUIETO;
Evento    estadoEvento    = EV_NORMAL;

float movPromedio    = 0.0f;
float accelPromedio  = 1.0f; // 1g en reposo

unsigned long ultimoMovimiento  = 0;
unsigned long inicioCaidaLibre  = 0;
unsigned long inicioColapso     = 0;

float anguloAnterior = 0.0f;

// =========================================================
// HELPERS
// =========================================================

// Ángulo entre el vector gravedad y el eje Y del sensor
// 0° = sensor vertical (parado), 90° = acostado
float calcularAngulo(float ax, float ay, float az) {
  float mag = sqrt(ax*ax + ay*ay + az*az);
  if (mag < 0.01f) return 0;
  return acos(constrain(ay / mag, -1.0f, 1.0f)) * 57.2958f;
}

const char* nombreEvento(Evento e) {
  switch (e) {
    case EV_NORMAL:       return "NORMAL";
    case EV_CAIDA_LIBRE:  return "CAIDA LIBRE...";
    case EV_CAIDA:        return ">>> CAIDA <<<";
    case EV_COLAPSO_LENTO:return "COLAPSO LENTO...";
    case EV_DESMAYO:      return ">>> DESMAYO <<<";
  }
  return "?";
}

// =========================================================
// SETUP
// =========================================================
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);

  mpu.initialize();
  mpu.setFullScaleAccelRange(MPU6050_ACCEL_FS_2);  // ±2g
  mpu.setFullScaleGyroRange(MPU6050_GYRO_FS_250);  // ±250°/s

  if (!mpu.testConnection()) {
    Serial.println("ERROR: MPU6050 no detectado");
    while (1);
  }

  Serial.println("MPU6050 OK");
  ultimoMovimiento = millis();
}

// =========================================================
// LOOP
// =========================================================
void loop() {
  int16_t axR, ayR, azR, gxR, gyR, gzR;
  mpu.getMotion6(&axR, &ayR, &azR, &gxR, &gyR, &gzR);

  // Convertir a unidades reales
  float ax = axR / ACCEL_ESCALA; // en g
  float ay = ayR / ACCEL_ESCALA;
  float az = azR / ACCEL_ESCALA;
  float Gx = gxR / GYRO_ESCALA;  // en °/s
  float Gy = gyR / GYRO_ESCALA;
  float Gz = gzR / GYRO_ESCALA;

  // Magnitudes
  float accelMag = sqrt(ax*ax + ay*ay + az*az); // ~1g en reposo
  float gyroMag  = sqrt(Gx*Gx + Gy*Gy + Gz*Gz); // ~0 en reposo

  // Ángulo de inclinación respecto a la vertical
  float angulo = calcularAngulo(ax, ay, az);

  // Filtros exponenciales
  movPromedio   = movPromedio   * 0.85f + gyroMag  * 0.15f;
  accelPromedio = accelPromedio * 0.85f + accelMag  * 0.15f;

  unsigned long ahora = millis();

  // =====================
  // POSTURA
  // =====================
  if (angulo < ANGULO_PARADO) {
    estadoPostura = PARADO;
  } else if (angulo < ANGULO_INCLINADO) {
    estadoPostura = INCLINADO;
  } else {
    estadoPostura = ACOSTADO;
  }

  // =====================
  // ACTIVIDAD
  // =====================
  if (movPromedio < ACT_QUIETO) {
    estadoActividad = QUIETO;
  } else if (movPromedio < ACT_LEVE) {
    estadoActividad = LEVE;
    ultimoMovimiento = ahora;
  } else {
    estadoActividad = INTENSO;
    ultimoMovimiento = ahora;
  }

  // =====================
  // MAQUINA DE ESTADOS
  // =====================
  switch (estadoEvento) {

    case EV_NORMAL:
      // Caída libre: accel total cae bruscamente
      if (accelMag < LIBRE_MIN) {
        estadoEvento     = EV_CAIDA_LIBRE;
        inicioCaidaLibre = ahora;
      }
      // Colapso lento: giro bajo y ángulo va creciendo hacia horizontal
      else if (gyroMag < GIRO_DESMAYO_MAX
               && estadoPostura != ACOSTADO
               && (angulo - anguloAnterior) > 0.3f) {
        estadoEvento  = EV_COLAPSO_LENTO;
        inicioColapso = ahora;
      }
      break;

    case EV_CAIDA_LIBRE:
      if (accelMag > IMPACTO_MIN) {
        // Impacto → caída confirmada
        estadoEvento = EV_CAIDA;
      } else if (ahora - inicioCaidaLibre > VENTANA_IMPACTO_MS) {
        // No hubo impacto en tiempo → falsa alarma
        estadoEvento = EV_NORMAL;
      }
      break;

    case EV_CAIDA:
      // Recuperación: parado y moviéndose
      if (estadoPostura == PARADO && estadoActividad != QUIETO) {
        estadoEvento     = EV_NORMAL;
        ultimoMovimiento = ahora;
      }
      break;

    case EV_COLAPSO_LENTO:
      if (estadoPostura == ACOSTADO && movPromedio < ACT_QUIETO) {
        unsigned long duracion = ahora - inicioColapso;
        if (duracion >= COLAPSO_MIN_MS) {
          // Transición lenta → desmayo
          estadoEvento = EV_DESMAYO;
        } else {
          // Llegó muy rápido → fue caída, no desmayo
          estadoEvento = EV_CAIDA;
        }
      }
      // Movimiento intenso → no era colapso
      else if (estadoActividad == INTENSO) {
        estadoEvento = EV_NORMAL;
      }
      // Timeout: no llegó a horizontal en el tiempo esperado
      else if (ahora - inicioColapso > TIEMPO_COLAPSO_MS && estadoPostura != ACOSTADO) {
        estadoEvento = EV_NORMAL;
      }
      break;

    case EV_DESMAYO:
      // Recuperación: parado y moviéndose
      if (estadoPostura == PARADO && estadoActividad != QUIETO) {
        estadoEvento     = EV_NORMAL;
        ultimoMovimiento = ahora;
      }
      break;
  }

  // =====================
  // INACTIVIDAD
  // =====================
  unsigned long tiempoQuieto = (ahora - ultimoMovimiento) / 1000;

  // =====================
  // SERIAL
  // =====================
  Serial.println("--------------------------------");
  Serial.print("Angulo:      "); Serial.print(angulo, 1);    Serial.println(" deg");
  Serial.print("Accel mag:   "); Serial.print(accelMag, 3);  Serial.println(" g");
  Serial.print("Gyro mag:    "); Serial.print(gyroMag, 1);   Serial.println(" deg/s");
  Serial.print("Postura:     ");
  Serial.println(estadoPostura == PARADO ? "PARADO" : estadoPostura == INCLINADO ? "INCLINADO" : "ACOSTADO");
  Serial.print("Actividad:   ");
  Serial.println(estadoActividad == QUIETO ? "QUIETO" : estadoActividad == LEVE ? "LEVE" : "INTENSO");
  Serial.print("Evento:      "); Serial.println(nombreEvento(estadoEvento));
  Serial.print("Sin mover:   "); Serial.print(tiempoQuieto); Serial.println(" s");

  if (tiempoQuieto > TIEMPO_INACTIVIDAD_S)
    Serial.println("ALERTA: inactividad prolongada");

  anguloAnterior = angulo;

  delay(300); // 10 Hz — mínimo recomendado para detectar caídas
}