# Auditoría técnica — Whitechapel 1888 (Godot 4.6)

Alcance revisado:
- Scripts, escenas, recursos `.tres/.res`, `project.godot`.
- No se han evaluado assets ni addons por petición.

## Resumen ejecutivo

El proyecto tiene una base buena para iterar rápido: modularización básica del player/NPC, autoloads claros y varios sistemas ya separados por responsabilidad práctica. Pero ahora mismo arrastra **tres problemas estructurales** y **varios bugs concretos** que explican por qué algunas cosas se comportan de forma “rara” aunque el sistema parezca bien montado.

Lo más delicado está en:
1. **Tiempo / estados asíncronos** (`PlayerStats`, `SleepManager`, `SaveManager`).
2. **Transiciones globales** (`SceneManager` usado por métodos internos desde muchos sitios).
3. **Acoplamiento fuerte entre escena, player y UI** (`GameManager`, `PlayerManager`, journal, pausa, guardado).

## Hallazgos críticos

### 1) La medicina dura 2 minutos reales, no 2 días de juego
- `Scripts/Managers/player_stats.gd:34-37`
- `Scripts/Managers/player_stats.gd:119-126`

`MEDICINA_DURACION_DIAS = 2.0`, pero el tiempo se calcula así:

```gdscript
var dias_jugados = medicina_timer / DEGRADACION_INTERVALO
if dias_jugados >= MEDICINA_DURACION_DIAS:
```

Como `DEGRADACION_INTERVALO = 60.0`, realmente se apaga a los **120 segundos reales**, no a 2 días jugables.

**Impacto:** rompe el balance de enfermedad y hace que el jugador perciba la medicina como inconsistente.

---

### 2) Los pickups con `ñ` pueden fallar por nombre de archivo codificado
- `Scripts/Core/pickup.gd:47-51`
- `Scenes/Test/Prueba_Mecanicas.tscn:254,259`
- Archivos reales: `Data/Pickups/sue#U00f1o-down.tres`, `Data/Pickups/sue#U00f1o-up.tres`

El código busca:

```gdscript
var pickup_path := "res://Data/Pickups/%s.tres" % pickup_type
```

pero el `pickup_type` en escena es `"sueño-down"`, mientras el archivo físico del proyecto está como `sue#U00f1o-down.tres`.

**Impacto:** esos pickups pueden no cargar `data` y fallar silenciosamente fuera de los casos “cliente/cure”.

---

### 3) `SceneManager` no es la fuente real del estado de transición
- `Scripts/Managers/scene_manager.gd:47-60, 66-84`
- `Scripts/Core/enter_building.gd:147,180,214,236`
- `Scripts/Managers/player_manager.gd:67,77`
- `Scripts/Managers/save_manager.gd:89-102`
- `Scripts/Managers/sleep_manager.gd:100,156,239,246,334,341`

Muchos sistemas llaman a `SceneManager._fade_out()` / `_fade_in()` directamente, pero esas funciones **no marcan** `_is_transitioning = true`.

Luego `GameManager` decide si puede abrir pausa/journal preguntando a `SceneManager.is_transitioning()`, pero ese flag **no cubre** la mayoría de transiciones reales.

Además `SaveManager` llega a tocar internals del singleton:

```gdscript
SceneManager._blocking.visible = false
SceneManager._is_transitioning = false
```

**Impacto:** bloqueos globales inconsistentes, condiciones de carrera y bugs difíciles de reproducir durante fade, carga, sueño o entrada/salida de edificios.

## Hallazgos altos

### 4) `PlayerManager` dice ser persistente, pero la arquitectura real no lo es
- `Scripts/Managers/player_manager.gd:3-10, 28-36`
- Escenas con player embebido: `Scenes/Exteriors/Streets.tscn`, `Scenes/Story/Intro_Game.tscn`, `Scenes/Test/Prueba_Mecanicas.tscn`, etc.

El comentario del manager dice “mantener la instancia del player entre escenas”, pero en la práctica las escenas cargan su propio `Player.tscn`. O sea: el sistema es **mixto**.

**Riesgo:**
- comportamiento distinto según la escena tenga o no player embebido,
- más difícil razonar guardado/carga,
- más fácil romper referencias globales si una escena futura no incluye player.

---

### 5) `PlayerStats.actualizar_stats()` es async, pero se usa muchas veces como si fuera síncrono
- `Scripts/Managers/player_stats.gd:428-441`
- Llamadas no esperadas en:
  - `Scripts/Managers/inventory_manager.gd:132,140`
  - `Scripts/Managers/save_manager.gd:268`
  - `Scripts/Core/pickup.gd:105`

La función hace esto:

```gdscript
await get_tree().process_frame
stats_updated.emit()
```

Eso convierte la actualización en un flujo no atómico. Hay varios sitios donde se llama sin `await`, como si el estado y las señales ya hubieran quedado completamente aplicadas.

**Impacto:** estados visuales y lógicos pueden actualizarse un frame más tarde de lo esperado; complica guardado, UI y efectos.

---

### 6) `pickup.gd` mezcla compra, consumo y mutación directa de stats
- `Scripts/Core/pickup.gd:91-115`

Aquí se hace:
1. comprobar dinero,
2. llamar a `PlayerStats.gastar_dinero()` (async),
3. modificar stats a mano,
4. llamar a `PlayerStats.actualizar_stats()`.

Eso duplica lógica que ya existe en `InventoryManager` / `PlayerStats` y deja caminos diferentes para “aplicar un item”.

**Impacto:** mantenimiento difícil y riesgo de desincronizar economía/estado/efectos según el tipo de pickup.

---

### 7) `GameConfig` no es realmente la fuente única de configuración
- `Scripts/Data/game_config.gd`
- `Scripts/Managers/player_stats.gd`
- `Scripts/Managers/sleep_manager.gd`
- `Data/Game/game_config.tres`

Hay valores de economía y objetivo repetidos en varios sitios (`coste_hostal`, medicina, dinero objetivo, etc.).

Además, `Data/Game/game_config.tres` solo sobreescribe `horas_max_calle = 24.0`, mientras el script tiene por defecto `8.0`.

**Impacto:** tuning imprevisible y bugs de diseño por “doble verdad”.

---

### 8) `EffectsManager` probablemente renderiza por encima de UI importante
- `Scripts/Managers/effects_manager.gd:44-67`

Se crea un `CanvasLayer` en `layer = 10`. Menús, journal y otros overlays usan capas por defecto o inferiores.

**Riesgo:** blur, viñeta o disease overlay pueden quedar por encima del pause menu, journal o fades y ensuciar la UX.

## Hallazgos medios

### 9) Detección de Dialogic dudosa
- `Scripts/Managers/player_stats.gd:450-457`

```gdscript
if not Engine.has_singleton("Dialogic"):
    return
```

Eso es sospechoso para un autoload/plugin como Dialogic. El código puede no sincronizar nunca variables si esa comprobación no corresponde al tipo real de singleton.

**Impacto:** variables de Dialogic podrían no refrescarse aunque `stats_updated` dispare.

---

### 10) `MainMenu` no reaplica textos al cambiar idioma
- `Scripts/UI/main_menu.gd:180-188`

Cambias locale con `TranslationServer.set_locale(...)`, pero no reconstruyes interfaz ni actualizas labels existentes.

**Impacto:** el selector de idioma puede parecer roto o incompleto hasta recargar la escena.

---

### 11) Navegación izquierda/derecha en `MainMenu` está incompleta
- `Scripts/UI/main_menu.gd:35-41`

Se llama a `get_focus_neighbor(SIDE_LEFT/RIGHT)` pero no se hace `grab_focus()` sobre el vecino devuelto.

**Impacto:** navegación horizontal probablemente no funciona.

---

### 12) `GameManager` aún tiene hotkeys de debug de guardado/carga en producción
- `Scripts/Managers/game_manager.gd:25-32`

F6 guarda y F7 carga directamente.

**Impacto:** riesgo de comportamiento inesperado durante tests o builds jugables.

---

### 13) UI antigua y backups dentro del proyecto activo
- `Scenes/Player/Player_Backup.tscn`
- `Scenes/UI/Journal_Old.tscn`
- `Scripts/UI/journal_old.gd`
- `Scripts/_Archive/Level.gd`

**Impacto:** ruido de mantenimiento, búsqueda más lenta y riesgo de editar el archivo equivocado.

---

### 14) Escenas muy grandes y difíciles de mantener manualmente
- `Scenes/UI/Journal.tscn` (~3252 líneas)
- `Scenes/Player/Player.tscn` (~2558 líneas)
- `Scenes/NPC/NPC_Charger.tscn` (~1365 líneas)

Esto no implica error por sí solo, pero sí aumenta:
- conflictos de merge,
- dificultad para revisar cambios,
- fragilidad al tocar nodos profundos a mano.

## Fortalezas reales del proyecto

1. **Modularidad razonable en player/NPC.**
   - `player_controller`, `player_movement`, `player_animation`, `player_audio`, `player_interaction`.
   - `npc_main`, `npc_movement`, `npc_animation`, `npc_conversation`, `npc_audio`.

2. **Sistema de edificios mejor de lo normal.**
   - Buena separación entre `building.gd` y `enter_building.gd`.
   - Restauración interior en save/load bastante bien pensada.

3. **Guardado/carga ya contempla interior/exterior, outfit, inventario y equipamiento.**
   - La dirección va bien aunque aún necesita limpieza arquitectónica.

4. **Buen uso de autoloads para avanzar rápido.**
   - El problema no es usarlos, sino que ya están empezando a mezclarse con internals y responsabilidades cruzadas.

## Prioridad de arreglos recomendada

### Prioridad 1
- Corregir duración de medicina en `PlayerStats`.
- Normalizar nombres de pickups con `ñ`.
- Encapsular transiciones en API pública única de `SceneManager`.

### Prioridad 2
- Decidir una sola arquitectura para el player:
  - o persistente real,
  - o instanciado por escena, pero no híbrido.
- Hacer `actualizar_stats()` síncrona o separar claramente:
  - aplicar estado,
  - emitir señales diferidas.

### Prioridad 3
- Unificar aplicación de items/pickups/inventario.
- Convertir `GameConfig` en fuente única real.
- Limpiar backups y escenas antiguas.

## Veredicto

**Estado general: prometedor pero frágil.**

No veo un proyecto caótico ni “mal hecho”; de hecho tiene bastante estructura para ser un proyecto vivo y en iteración. Pero ya ha llegado al punto en que **los bugs más molestos no van a salir de una línea rota**, sino de la combinación de:
- autoloads globales,
- escenas con mucha lógica embebida,
- async no centralizado,
- y transiciones manejadas desde varios sitios.

Si corriges los 3 críticos y haces una pasada de consolidación en `SceneManager + PlayerStats + PlayerManager`, el proyecto gana mucha estabilidad de golpe.
