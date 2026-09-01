# Swaby

## Descripción

**Swaby** es un proyecto investigativo orientado al desarrollo de un sistema portátil de monitoreo biomédico. El prototipo permite adquirir y visualizar en tiempo real información relacionada con la actividad cardíaca y el movimiento del usuario.

El sistema utiliza un **ESP32** como unidad principal de procesamiento, conectado a un sensor **AD8232** para la adquisición del electrocardiograma (ECG), un **DS18B20** para la medición de temperatura y un **MPU-6050** para el análisis de movimiento y postura.

Los datos obtenidos son procesados por el ESP32 y enviados mediante **Bluetooth** a una PC para su visualización y registro.

## Enfoque investigativo

El desarrollo de Swaby se planteó como un proyecto investigativo, además de la construcción de un prototipo funcional. Durante las pruebas se analizaron las condiciones necesarias para obtener una señal de ECG estable y las limitaciones del sistema.

Se comprobó que el ECG funciona correctamente cuando el usuario se encuentra en reposo, pero presenta importantes perturbaciones durante el movimiento. El principal problema identificado fue el ruido generado por la actividad y el movimiento muscular, que se superpone a la señal cardíaca y genera artefactos que dificultan su correcta interpretación.

A pesar del filtrado incorporado en el AD8232, filtrado por software y los recursos disponibles para el proyecto no fue posible eliminar estas interferencias de manera suficiente como para obtener una señal de ECG confiable durante el movimiento. Por este motivo, el monitoreo cardíaco se consideró funcional bajo condiciones de reposo, pero limitado durante la actividad física.

También se detectaron interferencias externas durante las primeras pruebas, relacionadas con la alimentación y la calidad de los electrodos. Estas fueron reducidas mediante el aislamiento de la fuente de alimentación utilizada en el laboratorio y el reemplazo de los electrodos por otros de mayor calidad.

## Software

El **ESP32** se encarga de adquirir los datos de los sensores y transmitirlos mediante Bluetooth.

Para la visualización y registro de los datos se desarrolló una aplicación en **Processing**, encargada de recibir la información enviada por el ESP32 y representarla de forma gráfica en tiempo real.

La aplicación permite visualizar principalmente:

* Señal de ECG y BPM en tiempo real.
* Datos de temperatura.
* Información proveniente del MPU-6050.

La comunicación entre el prototipo y la aplicación se realiza de forma inalámbrica mediante **Bluetooth**, permitiendo separar físicamente el sistema de adquisición de la interfaz de visualización.

## Estado del proyecto

El prototipo logró cumplir con el objetivo planteado, permitiendo la adquisición y visualización en tiempo real de las variables estudiadas.

El repositorio contiene el código, componentes, diagramas y documentación correspondiente al desarrollo de **Swaby**.
