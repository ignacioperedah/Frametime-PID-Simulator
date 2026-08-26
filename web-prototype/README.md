# Simulador DRS (prototipo web) — `simulador_drs.html`

> **Nota:** esta es la **primera versión** del simulador — un prototipo 2D en HTML/JS
> hecho antes de portar el proyecto a Godot. El simulador actual, en 3D, vive en la
> raíz del repo (ver el [README principal](../README.md)). Este prototipo se conserva
> como referencia histórica del desarrollo.

Simulador interactivo del lazo de control PID de Escalado Dinámico de Resolución (DRS), desarrollado como parte del Trabajo Final Integrador "Sistema de Control de FrameTime mediante Escalado Dinámico de Resolución para Simuladores de Vuelo" (UTN-FRBA, Tecnologías de Automatización).

## Cómo abrirlo

No requiere instalación. Es un único archivo HTML:

1. Descargar `simulador_drs.html`.
2. Hacer doble clic para abrirlo — se abre directamente en el navegador predeterminado.
3. Si no abre automáticamente, hacer clic derecho → **Abrir con** → elegir un navegador (ver requisitos abajo).

Todo el HTML, CSS y JavaScript propio está embebido en el mismo archivo, pero **sí
necesita conexión a internet**: los gráficos se renderizan con la librería
[Plotly](https://plotly.com/javascript/), cargada desde su CDN (`cdn.plot.ly`). Sin
internet, la página abre pero los gráficos no van a aparecer.

## Requisitos

- **Navegador**: cualquier navegador moderno con soporte de JavaScript habilitado — Google Chrome, Microsoft Edge, Mozilla Firefox o similar (versiones de los últimos 3-4 años). No es compatible con Internet Explorer.
- **Hardware**: sin requerimientos especiales. Es una simulación matemática 2D (gráficos vectoriales sobre `<canvas>`), no renderiza 3D ni usa la GPU — corre fluido en cualquier notebook o PC, incluso de gama baja.
- **Pantalla**: pensado para pantallas de escritorio (resolución mínima recomendada 1280×720). En pantallas muy chicas los paneles de control y los gráficos pueden verse apretados.

## Qué hace

Simula, en tiempo discreto, el lazo cerrado completo descripto en el informe: la planta (relación cuadrática entre la escala de render y el FrameTime, con retardo de transporte), el regulador PID con Anti-Windup, y las tres perturbaciones documentadas (Alta Carga, Acceso a Disco, Thermal Throttling). Permite:

- Ajustar Kp, Ki y Kd en caliente con sliders.
- Disparar cada perturbación individualmente, con sus parámetros (amplitud, duración) también ajustables.
- Ver en tiempo real los gráficos de FrameTime, error y escala del actuador.
- Observar el indicador de estado de Calidad de Servicio (QoS).

## Si algo no funciona

- **La página se ve en blanco o sin gráficos**: verificar conexión a internet (se necesita para cargar Plotly desde el CDN) y que JavaScript esté habilitado en el navegador (viene habilitado por defecto; puede estar desactivado por alguna extensión o política corporativa).
- **Los gráficos no se actualizan**: recargar la página (F5). El estado no se guarda entre recargas — es esperable, cada apertura arranca desde cero.
- **Se ve desproporcionado o cortado**: probar en pantalla completa (F11) o en una ventana más ancha.
