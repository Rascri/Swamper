/*******************************************************************************

  CHALECO INTELIGENTE - DESAFÍOS ECO
  Monitor de postura, impacto y accidente (MPU6050) + Monitor cardíaco (ECG)

  ARQUITECTURA
  ------------
  El ESP32 NO contiene lógica: únicamente muestrea sensores y transmite datos
  crudos por Bluetooth (puerto serie virtual). Toda la inteligencia
  (filtros, clasificación de postura, detección de impacto y máquina de
  estados de accidente) vive en este sketch de Processing.

  El ESP32 usa una única conexión Bluetooth (BluetoothSerial, "SWAMPER"), así
  que ambos sensores comparten el mismo puerto serie virtual. Para separarlos
  cada línea llega con un prefijo:

    - "E,<valorADC>"  -> muestra del ECG (protocolo original, un valor por línea)
    - "E,!"           -> electrodos del ECG desconectados
    - "M,timestamp,ax,ay,az,gx,gy,gz" -> muestra del MPU6050, donde:
        timestamp -> milisegundos (long), tiempo del ESP32 (millis())
        ax,ay,az  -> aceleración en g (ya escalada en el ESP32)
        gx,gy,gz  -> velocidad angular en grados/segundo (ya escalada)
    - "T,<grados C>"  -> temperatura de la sonda (~1 Hz); "T,!" -> sin lectura

  No se asume una frecuencia de muestreo fija: el módulo del MPU6050 calcula
  su propio deltaTime a partir del timestamp recibido, aunque el ESP32 en la
  práctica los envíe a una tasa fija (100 Hz).

  CLASES
  ------
  - BluetoothReceiver     -> encapsula un puerto Serial (Bluetooth) y permite
                             identificar de qué puerto proviene cada evento.
  - MPU6050Module         -> filtro complementario, pitch/roll, magnitudes.
  - CalibrationManager    -> toma de referencia (pitch/roll = 0) al calibrar.
  - PostureClassifier     -> clasifica la postura con histéresis + debounce.
  - DetectorImpacto        -> detecta picos de aceleración (eventos aislados).
  - AccidentStateMachine  -> confirma accidente combinando varias evidencias
                             y luego vigila inmovilidad del piloto.
  - ActivityMonitor       -> quietud, nivel de actividad e inactividad (MPU6050).
  - ECGModule             -> BPM y filtrado del ECG (portado del proyecto
                             original, ahora encapsulado en una clase).
  - PilotVestUI           -> interfaz visual (paneles, colores, botón).

*******************************************************************************/

import processing.serial.*;

BluetoothReceiver btReceiver; // única conexión Bluetooth del ESP32 ("SWAMPER")

MPU6050Module        mpu;
CalibrationManager   calibracion;
PostureClassifier    postura;
DetectorImpacto       impacto;
AccidentStateMachine accidente;
ECGModule            ecg;
PilotVestUI          ui;
ActivityMonitor      actividad;
DisplayLink          pantalla;  // 2º ESP32 por cable USB (pantalla + buzzer)

// Layout de la ventana
final int PANEL_ALTURA = 300; // zona superior: texto + botón
final int CHART_ALTURA = 260; // zona inferior: onda ECG

// Temperatura ("T,<°C>" ~1 Hz; "T,!" = sonda sin lectura)
float temperatura = Float.NaN;               // NaN = sin lectura vigente
int ultimaTemperaturaMillis = 0;
final int   TEMP_TIMEOUT_MS = 5000;          // sin mensajes T válidos => "Sin lectura"
final float TEMP_MIN = -40, TEMP_MAX = 125;  // fuera de este rango = lectura inválida

volatile boolean listo = false;

void setup() {
  size(1000, 560);
  printArray(Serial.list());

  // ── Ajustar el puerto según el Administrador de dispositivos / sistema ──────
  // Es el puerto COM virtual que crea el emparejamiento Bluetooth con "SWAMPER".
  btReceiver = new BluetoothReceiver(this, "COM4", 115200);

  // Puerto USB del 2º ESP32 (otro COM distinto del Bluetooth; ver la lista impresa arriba).
  pantalla = new DisplayLink(this, "COM3", 115200);

  mpu         = new MPU6050Module();
  calibracion = new CalibrationManager();
  postura     = new PostureClassifier();
  impacto     = new DetectorImpacto();
  accidente   = new AccidentStateMachine();
  ecg         = new ECGModule();
  actividad   = new ActivityMonitor();
  ui          = new PilotVestUI(PANEL_ALTURA);

  background(255); // fondo blanco inicial; el panel superior se recolorea cada frame,
                    // la zona de la onda ECG se mantiene blanca (scroll incremental).
  listo = true;
}

void draw() {
  btReceiver.mantener(); // reconexión automática del Bluetooth

  // 1) Calibración (si está en curso, promedia muestras de pitch/roll)
  calibracion.actualizar(mpu);

  // 2) Clasificación de postura usando valores relativos (post-calibración)
  postura.actualizar(mpu.pitchRel, mpu.rollRel);

  // 3) Detección de impacto puntual (evento aislado, no implica accidente)
  impacto.actualizar(mpu.consumirPicoAccel()); // pico entre frames, no solo el último valor

  // 4) Máquina de estados de accidente (combina impacto + orientación + postura)
  accidente.actualizar(impacto.impactoDetectado, mpu.pitchRel, mpu.rollRel,
                        postura.estadoActual);

  // 4b) Quietud / nivel de actividad / inactividad prolongada
  actividad.actualizar(mpu);

  // 5) Interfaz: panel superior (texto, color de estado, botón)
  ui.dibujar(mpu, postura, impacto, accidente, ecg, calibracion, actividad, textoTemperatura());

  // 6) Onda ECG en la franja inferior (scroll incremental, no se borra por frame)
  ecg.dibujarOnda(PANEL_ALTURA, CHART_ALTURA);

  // 7) Datos hacia la pantalla OLED/buzzer del 2º ESP32
  pantalla.actualizar(ecg, mpu, postura, accidente, actividad, temperaturaVigente());
}

// ─────────────────────────────────────────────────────────────────────────────
void serialEvent(Serial puerto) {
  if (!listo || btReceiver == null) return;
  if (!btReceiver.matches(puerto)) return;

  // Processing dispara UN evento por ráfaga de bytes, no por línea: hay que
  // vaciar todas las líneas disponibles o se acumula retraso y el ECG se atrasa
  // hasta dejar de actualizarse.
  String linea;
  while ((linea = btReceiver.readLine()) != null) {
    try {
      linea = trim(linea);

      if (linea.startsWith("E,")) {
        ecg.procesarLinea(linea.substring(2));
      } else if (linea.startsWith("M,")) {
        procesarLineaMPU(linea.substring(2));
      } else if (linea.startsWith("T,")) {
        procesarLineaTemp(linea.substring(2));
      } else {
        println("Línea con prefijo desconocido, se ignora: " + linea);
      }
    } catch (Exception e) {
      e.printStackTrace(); // muestra archivo y línea exactos, y no desactiva serialEvent
    }
  }
}

// También al detener con el botón Stop del IDE (no siempre pasa por exit()).
void dispose() {
  if (btReceiver != null) btReceiver.cerrar();
  if (pantalla != null && pantalla.puerto != null) pantalla.puerto.stop();
  super.dispose();
}

// Libera los puertos COM al cerrar el sketch (si no, el siguiente arranque da "Port busy").
void exit() {
  if (btReceiver != null) btReceiver.cerrar();
  if (pantalla != null && pantalla.puerto != null) pantalla.puerto.stop();
  super.exit();
}

// Parsea "timestamp,ax,ay,az,gx,gy,gz" y actualiza el módulo del MPU6050
void procesarLineaMPU(String linea) {
  String[] partes = split(linea, ',');
  if (partes.length != 7) {
    println("Línea MPU descartada (formato inválido): " + linea);
    return;
  }

  try {
    long  timestamp = Long.parseLong(partes[0].trim());
    float ax = float(partes[1]);
    float ay = float(partes[2]);
    float az = float(partes[3]);
    float gx = float(partes[4]);
    float gy = float(partes[5]);
    float gz = float(partes[6]);

    if (Float.isNaN(ax + ay + az + gx + gy + gz)) { // float() devuelve NaN si no es numérico
      println("Línea MPU inválida, se ignora: " + linea);
      return;
    }

    mpu.update(timestamp, ax, ay, az, gx, gy, gz);
  } catch (Exception e) {
    println("Línea MPU inválida, se ignora: " + linea);
  }
}

// Parsea "<°C>" o "!". Acepta coma decimal. "!" borra la lectura; un dato inválido
// se ignora (si no llegan datos válidos, la lectura caduca por timeout).
void procesarLineaTemp(String dato) {
  dato = trim(dato).replace(',', '.');
  if (dato.equals("!")) {
    temperatura = Float.NaN;
    return;
  }
  float valor = float(dato); // NaN si no es numérico
  if (Float.isNaN(valor) || valor < TEMP_MIN || valor > TEMP_MAX) {
    println("Línea T inválida, se ignora: " + dato);
    return;
  }
  temperatura = valor;
  ultimaTemperaturaMillis = millis();
}

// Nunca muestra un valor caducado como si fuera actual
float temperaturaVigente() {
  boolean vigente = !Float.isNaN(temperatura) && millis() - ultimaTemperaturaMillis <= TEMP_TIMEOUT_MS;
  return vigente ? temperatura : Float.NaN;
}

String textoTemperatura() {
  float t = temperaturaVigente();
  return Float.isNaN(t) ? "Sin lectura" : nf(t, 1, 1) + " °C";
}

// ─────────────────────────────────────────────────────────────────────────────
void mousePressed() {
  if (ui.click(mouseX, mouseY)) {
    calibracion.iniciarCalibracion();
  }
}

void keyPressed() {
  switch (key) {
    case 'u': // subir umbral del ECG
      ecg.threshold += 50;
      println("Umbral ECG = " + ecg.threshold);
      break;
    case 'y': // bajar umbral del ECG
      ecg.threshold -= 50;
      println("Umbral ECG = " + ecg.threshold);
      break;
    case 'c': // atajo de teclado para calibrar (equivalente al botón)
      calibracion.iniciarCalibracion();
      break;
    case 'r': // reinicio manual de la máquina de estados de accidente (uso en pruebas)
      accidente.reset();
      println("Máquina de estados de accidente reiniciada manualmente.");
      break;
  }
}
