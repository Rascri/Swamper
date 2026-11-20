/*******************************************************************************
  DisplayLink
  -----------
  Envía por USB al 2º ESP32 (pantalla + buzzer) lo que Processing ya calculó.
  El ESP32 #2 no procesa nada: solo dibuja y suena.

  Protocolo (texto, una línea por mensaje, 115200 baud):
    E,v1,v2,...                      muestras del ECG ya filtradas (0-4095), 250 Hz
    B                                latido detectado (el ESP32 suena el buzzer)
    S,bpm,temp,pitchRel,rollRel,accelMag,alerta,actividad     (5 Hz)
        temp      -> °C, o "-" si no hay lectura vigente
        alerta    -> 0 sin caída, 1 caída detectada
        actividad -> 0 sin datos, 1 reposo, 2 ligera, 3 elevada
*******************************************************************************/

class DisplayLink {

  Serial puerto;
  int beatsEnviados = 0;
  int ultimoEstadoMs = 0;
  final int ESTADO_CADA_MS = 200;
  final int MAX_MUESTRAS_POR_LINEA = 40;

  DisplayLink(PApplet parent, String nombrePuerto, int baudRate) {
    try {
      puerto = new Serial(parent, nombrePuerto, baudRate);
    } catch (Exception e) {
      puerto = null;
      println("No se pudo abrir la pantalla en " + nombrePuerto + ": " + e.getMessage());
    }
  }

  boolean matches(Serial otro) {
    return puerto != null && puerto == otro;
  }

  // Se llama una vez por frame (draw).
  void actualizar(ECGModule ecg, MPU6050Module mpu, PostureClassifier postura,
                  AccidentStateMachine accidente, ActivityMonitor actividad, float temperatura) {
    if (puerto == null) return;

    int[] muestras = ecg.vaciarCola();
    for (int i = 0; i < muestras.length; i += MAX_MUESTRAS_POR_LINEA) {
      StringBuilder sb = new StringBuilder("E");
      for (int j = i; j < min(i + MAX_MUESTRAS_POR_LINEA, muestras.length); j++) sb.append(',').append(muestras[j]);
      puerto.write(sb.append('\n').toString());
    }

    if (ecg.beatCounter != beatsEnviados) {
      beatsEnviados = ecg.beatCounter;
      puerto.write("B\n");
    }

    if (millis() - ultimoEstadoMs >= ESTADO_CADA_MS) {
      ultimoEstadoMs = millis();
      String temp = Float.isNaN(temperatura) ? "-" : nf(temperatura, 1, 1);
      puerto.write("S," + ecg.BPM + "," + temp + "," + nf(mpu.pitchRel, 1, 1) + "," + nf(mpu.rollRel, 1, 1) + "," +
                   nf(mpu.accelMag, 1, 2) + "," + nivelAlerta(postura.estadoActual, accidente.estado) + "," +
                   actividad.nivel.ordinal() + "\n");
    }
  }

  // 0 = sin caída, 1 = caída detectada (el ECG y el resto siguen igual)
  int nivelAlerta(EstadoPostura p, EstadoAccidente a) {
    return a == EstadoAccidente.CAIDA ? 1 : 0;
  }
}
