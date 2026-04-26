Claro. Te dejo un **devlog limpio y útil** para retomar mañana.

# Devlog — hoy

## Objetivo del día

Montar el flujo de servicio con cliente:

* hablar con cliente
* elegir acto
* transición propia
* minijuego de timing
* volver al mapa
* congelando el resto del mundo mientras dura la escena

Y además empezar una base de **HUD superior** con hora y stats.

---

## 1) Flujo de cliente: ya funciona

### Flujo final conseguido

Desde `Streets` o cualquier escena con cliente:

1. hablas con cliente
2. eliges acto, por ejemplo `Oral`
3. fade global de la escena actual a negro
4. se instancia `Client_Transition.tscn`
5. corre su animación
6. corre el minijuego
7. termina en negro
8. se destruye la transición
9. vuelve la escena original con fade de negro a transparente

### Importante

No se cambia realmente de escena del mundo.
La transición se monta **encima**, y luego se vuelve al gameplay normal.

---

## 2) Minijuego de cliente: ya funciona

### Idea implementada

* minijuego de timing con ida y vuelta
* siempre se gana
* si fallas, se hace más fácil
* cuanto más fácil acaba siendo, peor satisfacción / menor recompensa

### Además

* se puede **saltar la animación con F**
* al saltarla, entra directo al minijuego

---

## 3) Mundo congelado durante el servicio: ya funciona

### Lo que se consiguió

Mientras corre `ClientTransition` + minijuego:

* NPCs parados
* tiempo parado
* partículas del mundo paradas
* lógica del mapa parada
* escena del mundo oculta
* audio del mundo apagándose con fade

### Cómo

* `get_tree().paused = true`
* `ClientTransition` corre con `PROCESS_MODE_WHEN_PAUSED`
* el mundo se oculta temporalmente
* al volver:

  * se reanuda el árbol
  * se vuelve a mostrar el mundo
  * vuelve el audio con fade

---

## 4) Manager nuevo de audio del mundo

### Creado

`WorldAudioManager`

### Función

Gestiona:

* `fade_out_world_audio()`
* `fade_in_world_audio()`
* pause/resume del audio del mundo

### Sistema usado

Por grupos globales en Godot:

* `world_music`
* `world_ambience`

### Importante

Sirve para cualquier escena del proyecto que tenga clientes, no solo `Streets`.

---

## 5) Manager nuevo del servicio con cliente

### Creado

`ClientServiceManager`

### Función

Orquesta todo el flujo:

* entrar al estado de servicio
* fade out audio
* fade a negro
* pausar mundo
* instanciar `ClientTransition`
* esperar resultado
* restaurar mundo
* fade in audio
* fade visual final
* devolver control al jugador

---

## 6) Máquina de estados: integrado

### Estado nuevo

Se añadió:

* `CLIENT_SERVICE`

### Estado actual

Ahora el servicio con cliente ya no es un parche, sino un estado real del juego.

### Ajustes hechos

`StateManager`:

* ya conoce `CLIENT_SERVICE`
* puede entrar desde `DIALOG` o `GAMEPLAY`
* oculta ratón en ese estado

### Falta fina

Se comentó que lo ideal es que la salida de `CLIENT_SERVICE` sea con `exit(CLIENT_SERVICE)` en vez de `force_gameplay()`, pero no recuerdo si al final quedó ya cambiado o sigue con `force_gameplay()`.
**Revisar mañana**.

---

## 7) GameManager blindado

### Se protegió para `CLIENT_SERVICE`

Durante el servicio no se puede:

* abrir pausa
* abrir journal
* disparar input global raro

### Funciones blindadas

En `game_manager.gd` se protegieron:

* `_input()`
* `_handle_cancel()`
* `toggle_journal()`
* `_open_pause_menu()`
* `_open_journal()`

---

## 8) `client_transition.gd`: arreglado

### Problema que había

El script estaba tocando `Overlay` (`visible`, `color.a`) y rompía la animación del `AnimationPlayer`.

### Solución

Se dejó claro:

* el `Overlay` lo controla solo la animación
* el script no toca su alpha ni visibilidad
* el script solo controla:

  * inicio
  * salto con F
  * entrada al minijuego
  * emisión de resultado final

---

## 9) HUD: base creada

### Escena creada

`res://Scenes/UI/HUD.tscn`

### Script creado

`res://Scripts/UI/hud.gd`

### Situación actual

El HUD ya existe y se puede poner como hijo directo del root de `Streets`, porque es `CanvasLayer`.

### Problemas detectados

* visualmente es feo todavía
* el reloj de sol (`SundialClock`) aún no está hecho
* la hora del HUD estaba mal porque leía `PlayerStats.tiempo_acumulado`, que en realidad es `null`

### Fuente real del tiempo

La hora real del juego sale de:

* `DayNightManager.hora_actual`
* `DayNightManager.tiempo_acumulado`

---

## 10) Inconsistencia detectada en el sistema de tiempo

### `DayNightManager`

Lleva la hora real correctamente:

* empieza en 8:00
* avanza con `CONFIG.duracion_hora_segundos`

### `Journal`

Problema actual:

* no se actualiza continuamente al abrirlo
* la hora queda fija hasta que pasa otra cosa en escena
* solo se refresca cuando ocurre algún evento que dispara `_update()`

### Causa probable

`JournalPage1` solo se actualiza cuando:

* `PlayerStats.stats_updated` emite señal

Pero **la hora depende de `DayNightManager`**, no de `PlayerStats`.

### Resultado

Hay inconsistencias:

* HUD y Journal no estaban leyendo lo mismo
* y además el Journal no escucha los cambios de hora en vivo

---

# Archivos importantes tocados / creados hoy

## Nuevos o clave

* `world_audio_manager.gd`
* `client_service_manager.gd`
* `hud.gd`

## Tocadas

* `state_manager.gd`
* `game_manager.gd`
* `npc_client.gd`
* `client_transition.gd`
* `client_minigame.gd`

## Escenas

* `Client_Transition.tscn`
* `HUD.tscn`

---

# Estado actual del proyecto al acabar hoy

## Funciona

* transición con cliente
* minijuego
* salto de animación con F
* congelación del mundo
* fade de audio del mundo
* retorno correcto al mapa
* base de HUD creada

## Pendiente / sucio

* HUD visualmente feo
* `SundialClock` no hecho
* Journal no actualiza la hora en tiempo real
* posible inconsistencia en cálculo de día entre HUD / Journal / DayNightManager
* revisar si `CLIENT_SERVICE` sale con `exit()` o con `force_gameplay()`

---

# Plan recomendado para mañana

## Prioridad 1

**Arreglar el tiempo de forma coherente**

Objetivo:

* que HUD y Journal lean del mismo sistema
* que la hora del Journal se actualice en vivo
* que el día se calcule igual en todas partes

### Lo más probable

Conectar el journal a:

* `DayNightManager.hora_cambiada`
  o actualizarlo de otra forma periódica/controlada

---

## Prioridad 2

**Mejorar el HUD**

* ordenar layout
* decidir qué stats dejar arriba
* hacer el `SundialClock`
* mejorar tipografía, márgenes y composición

---

## Prioridad 3

**Pulir StateManager / ClientService**

* confirmar salida normal con `exit(CLIENT_SERVICE)`
* dejar `force_gameplay()` solo para emergencias

---

# Nota final para mañana

Lo más importante que descubrimos hoy es esto:

> **El tiempo real del juego lo lleva `DayNightManager`, no `PlayerStats`.**

Y el bug del journal seguramente viene de que:

> **se refresca por cambios de stats, no por cambios de hora.**

Mañana yo empezaría por ahí.
