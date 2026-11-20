/*******************************************************************************
  BluetoothReceiver
  -----------------
  Encapsula un puerto Serial (típicamente un puerto COM virtual creado por el
  emparejamiento Bluetooth con el ESP32). Permite:
    - Abrir el puerto con el baudrate indicado.
    - Saber, dentro de serialEvent(Serial), a qué receptor pertenece el evento
      (necesario porque en este proyecto hay dos puertos activos: MPU6050 y ECG).
    - Leer una línea completa terminada en '\n'.
*******************************************************************************/

class BluetoothReceiver {

  Serial puerto;
  String nombrePuerto;

  BluetoothReceiver(PApplet parent, String nombrePuerto, int baudRate) {
    this.nombrePuerto = nombrePuerto;
    try {
      this.puerto = new Serial(parent, nombrePuerto, baudRate);
      this.puerto.bufferUntil('\n');
    } catch (Exception e) {
      // Puerto inexistente / ocupado / chaleco no emparejado: el sketch sigue
      // abierto mostrando "sin datos" en vez de cerrarse con un error.
      this.puerto = null;
      println("No se pudo abrir " + nombrePuerto + ": " + e.getMessage());
      println("Revisar el puerto COM en la lista impresa arriba y en PilotoVestMonitor.pde (setup).");
    }
  }

  boolean conectado() {
    return puerto != null;
  }

  // Compara por referencia de objeto: el Serial que llega a serialEvent()
  // es exactamente la misma instancia que abrimos aquí.
  boolean matches(Serial otro) {
    return puerto != null && this.puerto == otro;
  }

  // Devuelve la línea recibida (sin el '\n'), o null si todavía no hay datos.
  String readLine() {
    if (puerto == null) return null;
    return puerto.readStringUntil('\n');
  }
}
