# Devlog — Whitechapel 1888

**Fecha:** 2026-04-06  
**Sesión:** Tiempo, sueño, salud, journal, hostal y pantalla de sueño

---

## Objetivo de la sesión

Estabilizar el núcleo del sistema de tiempo y sueño, mejorar la claridad del sistema de salud, hacer el journal más legible para el jugador y detectar bugs en el flujo del hostal y en la pantalla de sueño.

---

## 1. Sistema de tiempo

### Problema detectado
El sistema de tiempo no era robusto. Mezclaba varias ideas a la vez:
- hora visual
- tiempo acumulado
- día actual
- avance manual durante el sueño

Eso causaba incoherencias en día/hora, especialmente con sueño, journal y save/load.

### Cambios realizados
- Se rehizo `day_night_manager.gd`.
- El juego sigue empezando a las **08:00**.
- El **día ahora cambia a las 00:00**, no a las 08:00.
- Se dejó HUD y journal leyendo correctamente del reloj actualizado.

### Resultado
- El día cambia donde debe.
- HUD y journal muestran bien el día y la hora.
- El sistema se volvió mucho más coherente para dormir, guardar y cargar.

---

## 2. Sueño / SleepManager

### Problema detectado
El sueño estaba usando la misma velocidad que el reloj normal del juego. Si una hora del juego duraba 60 segundos reales, dormir una noche era exageradamente lento.

### Cambios realizados
- Se separó la velocidad del sueño de la velocidad normal del juego.
- Se añadió configuración específica para el sueño:
  - `duracion_hora_sueno_segundos`
- También se pasaron al recurso de configuración:
  - `hora_apertura_hostal`
  - `hora_cierre_hostal`

### Decisión de diseño
El hostal queda configurado así:
- abre a las **22:00**
- cierra a las **08:00**

### Resultado
- El sueño ya no depende del ritmo del reloj general.
- Se puede balancear desde config sin tocar código.

---

## 3. Limpieza de `sleep_manager.gd`

### Cambios realizados
Se reorganizó el script para reducir repeticiones:
- helper público `is_hostel_open()`
- helper público `get_hostel_hours_until_close()`
- helper interno para crear el timer del sueño

### Resultado
- menos lógica duplicada
- horario del hostal centralizado
- flujo de sueño más limpio y más fácil de mantener

---

## 4. Bug del hostal cobrando cuando ya no quedaba tiempo

### Problema detectado
Si el jugador intentaba alquilar una habitación a las **07:45**, el juego mostraba el mensaje de que no quedaba tiempo suficiente para dormir, **pero ya había cobrado**.

### Localización del bug
El cobro no venía de `SleepManager`, sino de:
- `npc_service.gd`

### Causa
El flujo hacía esto:
1. cobrar
2. llamar a `SleepManager`
3. `SleepManager` detectaba que ya no quedaba tiempo

### Decisión correcta
El orden debe ser:
1. comprobar si el hostal está abierto
2. comprobar si queda al menos 1 hora
3. solo entonces cobrar
4. iniciar el flujo de sueño

### Resultado
Se dejó claro que el cobro debe ocurrir **después de validar**, no antes.

---

## 5. Dialogic y lógica del hostal

### Problema detectado
Aunque el hostal estuviera técnicamente abierto, si quedaba menos de 1 hora, **Dialogic no debería ni ofrecer la habitación**.

### Solución planteada
Se añadió el concepto de una nueva variable Dialogic:
- `hostel.hostel_can_rent`

Esta variable indica:
- que el hostal está abierto
- y además que queda tiempo suficiente para alquilar habitación

### Sincronización
Se añadió una forma segura de refrescar variables justo antes de abrir el timeline:
- `PlayerStats.sync_dialogic_variables_now()`

Y se determinó que el lugar correcto para llamarlo es:
- `prepare_dialogic_variables()` en `npc_service.gd`

### Problema adicional
Dialogic daba error porque la variable nueva no existía todavía.

### Solución
Hay que crearla en Dialogic, dentro del grupo `hostel`, como bool:
- `hostel_can_rent = false`

---

## 6. Bug de arranque con Dialogic

### Problema detectado
`PlayerStats` intentaba sincronizar variables con Dialogic demasiado pronto al arrancar el juego.

### Explicación simple
Dialogic ya existía, pero su parte de variables todavía no estaba lista. Era como intentar dejar un papel en una mesa que aún no habían montado.

### Cambios realizados
- comprobación de que existe `Dialogic`
- comprobación de que existe `Dialogic/VAR`
- retraso de la primera sincronización con `call_deferred()`

### Resultado
El juego deja de petar al iniciar por culpa de Dialogic.

---

## 7. Sistema de salud

### Problema detectado
La salud dependía de demasiados factores a la vez y resultaba poco clara para el jugador. Aunque fuera “lógico” internamente, no era fácil entender por qué subía o bajaba.

### Decisión de diseño
Simplificar el sistema.

### Nuevo criterio
La salud:
- **baja por**:
  - hambre
  - higiene
  - enfermedad
- **sube por**:
  - sueño
  - felicidad

Ya no afectan directamente a salud por hora:
- estrés
- nervios
- alcohol
- láudano

Esos se reservan mejor para otros sistemas:
- sex appeal
- narrativa
- eventos
- control del personaje

### Resultado
El sistema queda más justo y más legible para el jugador.

---

## 8. Separación entre daño instantáneo y desgaste por tiempo

### Cambios realizados
Se dejó clara la diferencia entre:
- **daño instantáneo** → golpes, agresiones, eventos (`damage_health`)
- **desgaste por tiempo** → hambre, suciedad, enfermedad (`actualizar_salud` por tick horario)

### Resultado
La salud ya no baja por cualquier refresco de stats. Baja por el tiempo cuando toca, y por eventos solo cuando debe.

---

## 9. `GameConfig` ampliado

### Cambios realizados
Se reorganizó `game_config.gd` para meter balance de salud en grupos exportados.

### Se pasó a config
- umbrales de hambre
- umbrales de higiene
- umbrales de enfermedad
- daño por hora
- recuperación por sueño
- recuperación por felicidad
- enfermedad crítica / terminal

### Resultado
Se puede balancear salud desde `game_config.tres` sin tocar el script.

---

## 10. Journal Page 2

### Problemas detectados
- hambre estaba visualmente invertida
- estrés y nervios bajos seguían viéndose rojos
- el jugador no entendía bien por qué la salud bajaba

### Cambios realizados
- hambre dejó de ir invertida
- color de barras por valor real:
  - stats negativos bajos → verde
  - stats negativos altos → rojo
- se añadió la idea de `LabelWarnings`

### Mensajes previstos
Ejemplos:
- “El hambre está dañando tu salud.”
- “La mala higiene está dañando tu salud.”
- “La enfermedad está dañando tu salud.”
- “El descanso ayuda a recuperar salud.”

### Resultado
El journal ahora comunica mejor el estado del personaje.

---

## 11. Debug Menu

### Cambios realizados
Se integró un menú de debug dentro del proyecto:
- centrado
- más grande
- con ratón visible al abrir
- accesible desde una acción de input

### Utilidad
Sirve para:
- adelantar horas
- fijar hora concreta
- guardar/cargar
- probar salud, sueño y reloj

### Resultado
Herramienta útil para QA rápido del sistema temporal y de stats.

---

## 12. Sleep screen — bugs visuales

### Problema detectado
En la pantalla de sueño:
- la luna/sol a veces parecía ir hacia atrás
- la barra de progreso llegaba a 100, luego caía y volvía a subir

### Causa
La animación usaba la **hora del reloj** para mover elementos que deberían depender del **progreso del sueño**.

Eso rompe especialmente al cruzar medianoche o al pulsar “seguir durmiendo”.

### Decisión correcta
- la **hora** se usa solo para el texto
- el **progreso** se usa para:
  - barra
  - movimiento visual del astro
  - sensación de avance del sueño

### Resultado
Se dejó claro cómo debe rehacerse la pantalla de sueño para evitar esos saltos raros.

---

## 13. Dirección artística para la pantalla de sueño

### Idea principal
Crear una pantalla atmosférica basada en:
- skyline panorámico de Whitechapel 1888
- cielo nocturno rojizo y contaminado
- luna
- chimeneas
- humo
- niebla
- sensación de que la ciudad sigue viva mientras el jugador duerme

### Objetivo
Que la pantalla se sienta como una transición narrativa, no como un simple loading screen.

---

## 14. IA para la imagen y el movimiento

### Nano Banana
Se redactó un prompt para una **imagen panorámica principal** del skyline de Whitechapel 1888, con:
- cielo rojizo
- luna
- tejados y chimeneas
- atmósfera de East End victoriano

### Firefly
Se redactó un prompt para **animar esa imagen** con movimiento sutil:
- humo
- niebla
- nubes rojizas
- ventanas de gas temblando ligeramente
- transición suave hacia el amanecer

### Resultado
Ya existe base creativa para producir la pantalla de sueño visualmente.

---

## 15. Shader acuarela / pinceladas

### Idea
Aplicar un shader sobre el vídeo para darle un acabado:
- acuarelado
- pictórico
- sucio / atmosférico
- con sensación de pinceladas apareciendo

### Problema detectado
Salió un error de shader con `mat2(...)`.

### Solución
Se corrigió usando la sintaxis compatible con Godot:
- `mat2(vec2(...), vec2(...))`

### Resultado
Queda encaminado el postproceso artístico para el vídeo.

---

## Conclusión de la sesión

Hoy se avanzó mucho en lo estructural y en lo visual:
- el tiempo quedó mucho más coherente
- el sueño quedó separado del reloj normal
- la salud pasó a ser más justa y comprensible
- el journal comunica mejor
- se localizó el bug real del hostal cobrando antes de validar
- se definió mejor la dirección artística de la pantalla de sueño

El siguiente foco natural es:
1. cerrar bien el flujo del hostal/Dialogic
2. terminar de pulir la pantalla de sueño
3. seguir consolidando config y balance

---

## Próximos pasos recomendados

1. Crear en Dialogic la variable `hostel.hostel_can_rent`
2. Ajustar el timeline del recepcionista para no ofrecer habitación si queda menos de 1 hora
3. Asegurar que el cobro de la habitación ocurre solo después de validar
4. Rehacer la animación del sleep screen para que use progreso en vez de hora
5. Integrar la imagen/vídeo atmosférico de Whitechapel para la pantalla de sueño
