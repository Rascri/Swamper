
#include "BluetoothSerial.h"
#include <Wire.h>
#include <MPU6050_light.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// =====================================================
// BLUETOOTH
// =====================================================
BluetoothSerial SerialBT;

// =====================================================
// MPU6050
// =====================================================
MPU6050 mpu(Wire);

#define MPU_SDA 21
#define MPU_SCL 22

bool mpuOk = false;

// =====================================================
// ECG - AD8232
// =====================================================
#define ECG_PIN 33
#define LO_PLUS 16
#define LO_MINUS 17

const uint16_t SAMPLE_RATE_ECG = 250;
const uint32_t SAMPLE_US_ECG = 1000000UL / SAMPLE_RATE_ECG;

uint32_t lastSampleECG = 0;

// =====================================================
// MUESTREO MPU6050
// =====================================================
const uint16_t SAMPLE_RATE_MPU = 100;
const uint32_t SAMPLE_US_MPU = 1000000UL / SAMPLE_RATE_MPU;

uint32_t lastSampleMPU = 0;

// =====================================================
// TEMPERATURA - DS18B20
// DATA conectado a GPIO18
// =====================================================
#define TEMP_PIN 18

OneWire oneWire(TEMP_PIN);
DallasTemperature tempSensor(&oneWire);

const uint32_t TEMP_INTERVAL_MS = 1000;
const uint32_t TEMP_CONVERSION_MS = 750;  // Resolución de 12 bits

uint32_t tempRequestTime = 0;
uint32_t lastTempRequest = 0;

bool tempConversionPending = false;

// =====================================================
// INICIAR CONVERSIÓN DE TEMPERATURA
// =====================================================
void iniciarConversionTemperatura() {
  tempSensor.requestTemperatures();

  tempRequestTime = millis();
  lastTempRequest = tempRequestTime;

  tempConversionPending = true;
}

// =====================================================
// PROCESAR TEMPERATURA
// =====================================================
void gestionarTemperatura() {
  uint32_t ahora = millis();

  // Comprobar si terminó la conversión iniciada.
  if (tempConversionPending &&
      (uint32_t)(ahora - tempRequestTime) >= TEMP_CONVERSION_MS) {

    float temperatura = tempSensor.getTempCByIndex(0);

    if (temperatura != DEVICE_DISCONNECTED_C &&
        !isnan(temperatura) &&
        temperatura >= -55.0 &&
        temperatura <= 125.0) {

      // Protocolo Bluetooth: T,<temperatura en Celsius>
      SerialBT.print("T,");
      SerialBT.println(temperatura, 2);

      // Depuración por USB del ESP32
      Serial.print("T,");
      Serial.println(temperatura, 2);

    } else {
      // Sensor desconectado o lectura inválida
      SerialBT.println("T,!");
      Serial.println("ERROR: lectura DS18B20 invalida");
    }

    tempConversionPending = false;
  }

  // Iniciar la siguiente conversión cuando corresponda.
  if (!tempConversionPending &&
      (uint32_t)(ahora - lastTempRequest) >= TEMP_INTERVAL_MS) {

    iniciarConversionTemperatura();
  }
}

// =====================================================
// SETUP
// =====================================================
void setup() {
  Serial.begin(115200);

  // Bluetooth clásico SPP
  SerialBT.begin("SWAMPER");

  // ADC del ESP32
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Detección de electrodos del AD8232
  pinMode(LO_PLUS, INPUT);
  pinMode(LO_MINUS, INPUT);

  // Inicialización del bus I2C y MPU6050
  Wire.begin(MPU_SDA, MPU_SCL);

  byte status = mpu.begin();
  mpuOk = (status == 0);

  if (mpuOk) {
    Serial.println(
      "MPU6050 detectado. Mantener el chaleco quieto."
    );

    mpu.calcOffsets(true, true);

    Serial.println("Offsets del MPU6050 listos.");
  } else {
    Serial.println(
      "ERROR: no se detecto el MPU6050."
    );
  }

  // Inicialización del DS18B20
  tempSensor.begin();

  // La conversión no debe bloquear el programa.
  tempSensor.setWaitForConversion(false);

  // Resolución de 12 bits: hasta 750 ms de conversión.
  tempSensor.setResolution(12);

  // Iniciar la primera conversión sin esperar su resultado.
  iniciarConversionTemperatura();

  // Inicializar temporizadores de muestreo.
  lastSampleECG = micros();
  lastSampleMPU = micros();

  Serial.println("Sistema de adquisicion iniciado.");
}

// =====================================================
// LOOP
// =====================================================
void loop() {
  // Actualizar el MPU con la mayor frecuencia posible.
  if (mpuOk) {
    mpu.update();
  }

  uint32_t ahora = micros();

  // ECG: 250 Hz
  if ((uint32_t)(ahora - lastSampleECG) >= SAMPLE_US_ECG) {
    lastSampleECG += SAMPLE_US_ECG;
    muestrearECG();
  }

  // MPU6050: 100 Hz
  if (mpuOk &&
      (uint32_t)(ahora - lastSampleMPU) >= SAMPLE_US_MPU) {

    lastSampleMPU += SAMPLE_US_MPU;
    muestrearMPU();
  }

  // Temperatura: conversión y lectura no bloqueantes.
  gestionarTemperatura();
}

// =====================================================
// ECG
// Formato: E,<valor_ADC>
// Electrodos desconectados: E,!
// =====================================================
void muestrearECG() {
  if (digitalRead(LO_PLUS) || digitalRead(LO_MINUS)) {
    SerialBT.println("E,!");
    Serial.println("E,!");
    return;
  }

  int ecg = analogRead(ECG_PIN);

  SerialBT.print("E,");
  SerialBT.println(ecg);

  Serial.print("E,");
  Serial.println(ecg);
}

// =====================================================
// MPU6050
// Formato:
// M,timestamp,ax,ay,az,gx,gy,gz
// Aceleración: g
// Velocidad angular: grados/segundo
// =====================================================
void muestrearMPU() {
  SerialBT.print("M,");
  SerialBT.print(millis());
  SerialBT.print(",");

  SerialBT.print(mpu.getAccX(), 4);
  SerialBT.print(",");

  SerialBT.print(mpu.getAccY(), 4);
  SerialBT.print(",");

  SerialBT.print(mpu.getAccZ(), 4);
  SerialBT.print(",");

  SerialBT.print(mpu.getGyroX(), 3);
  SerialBT.print(",");

  SerialBT.print(mpu.getGyroY(), 3);
  SerialBT.print(",");

  SerialBT.println(mpu.getGyroZ(), 3);
}