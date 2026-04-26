## Devlog — Whitechapel 1888
### Sesión de desarrollo — 4 de Abril de 2026

---

**Auditoría del proyecto**

Sesión iniciada con una auditoría técnica completa del código. Se compararon los análisis de dos IAs (Claude y GPT) identificando bugs críticos, deuda técnica y prioridades. Los hallazgos principales coincidieron en estructura general aunque con matices distintos en severidad y causa.

---

**Bugs corregidos**

**Dialogic singleton check incorrecto**
`Engine.has_singleton("Dialogic")` devolvía siempre `false` porque Dialogic 2 es un autoload normal, no un engine singleton. Corregido a `get_tree().root.has_node("Dialogic")`. Esto hacía que `_sync_dialogic_variables()` nunca ejecutara nada.

**Hostal siempre abierto en diálogos**
`npc_service.gd` sobreescribía la variable `hostel.hostel_open` con `true` incondicionalmente después de que `_sync_dialogic_variables()` la calculaba correctamente según la hora. Eliminadas las líneas redundantes.

**Medicina duraba 2 minutos en lugar de 2 días**
`medicina_timer` acumulaba delta en segundos y se dividía por `DEGRADACION_INTERVALO` (60), dando 120 segundos reales en lugar de 2 días de juego. Corregido dividiendo por `DEGRADACION_INTERVALO * 24.0`.

**Equipamiento no se restauraba al cargar partida**
El flujo de `_apply_stats` en `save_manager.gd` hacía `unequip()` → borraba el bolsillo → restauraba el bolsillo sin los items equipados → intentaba `equip()` sin encontrarlos. Rediseñado con `restore_equipped_from_save()` que escribe directamente en `_equipped` sin pasar por el bolsillo. También se añadió guardado de `horas_restantes` del perfume activo.

**Bonus de perfume aplicado dos veces al cargar**
Al guardar, `higiene`, `nervios` y `sex_appeal_bonus` se guardaban con los bonuses del perfume ya aplicados. Al cargar, `restore_equipped_from_save` los volvía a aplicar. Corregido restando los bonuses antes de serializar.

**Pickups con ñ en nombre de archivo**
`sueño-down.tres` y `sueño-up.tres` estaban codificados como `sue#U00f1o-down.tres` en el sistema de archivos. Renombrados a `sueno-down.tres` y actualizadas las referencias en escenas y en el enum de `pickup.gd`.

---

**Sistema de tienda — mejoras y fixes**

- Añadido fade in/out del overlay oscuro y animación de escala (center → out con TRANS_BACK) al abrir y cerrar el shop
- Corregido flash visual del panel apareciendo en esquina antes de centrarse: panel empieza con `modulate.a = 0` y el overlay se inserta con `move_child(_overlay, 0)` para quedar detrás del panel
- Corregido bug de `max_stack`: el botón `+` ahora descuenta lo ya poseído en el inventario del máximo permitido
- Añadido mensaje de error `SHOP_MAX_STACK` cuando se intenta añadir más del límite
- Corregida validación en `_on_buy_pressed` que usaba `usos_max` como cantidad a añadir en lugar de `item_entry["qty"]`

---

**Sistema de inventario — bolso**

- Reducidos slots base de 12 a 6
- Añadido campo `amplia_slots: bool` a `ItemData`
- Creado item `equip-bolso.tres` con `equip_slot = BODY`, `max_stack = 1`, `amplia_slots = true`
- `InventoryManager` gestiona `_slots_activos` (6 base, 12 con bolso)
- Al equipar el bolso, `_apply_effects` activa los 6 slots extra; al desequipar los limpia
- Al cargar partida, `restore_equipped_from_save` activa los slots antes de aplicar bonuses
- Journal página 3 muestra slots dinámicamente con `get_slots_activos()`
- Slots 7-12 (del bolso) se muestran con tono rojizo para distinguirlos visualmente

---

**Máquina de estados global (StateManager)**

Nuevo autoload `StateManager` con estados: `MENU`, `GAMEPLAY`, `PAUSED`, `JOURNAL`, `DIALOG`, `SLEEPING`, `SHOP`, `TRANSITIONING`.

- Gestión centralizada del ratón: visible en MENU/PAUSED/JOURNAL/SHOP, oculto en GAMEPLAY/DIALOG/SLEEPING/TRANSITIONING
- `GameManager`, `SleepManager`, `PauseMenu`, `NPCService` y `PlayerInteraction` actualizados para usar StateManager
- `MainMenu` entra en estado MENU al arrancar y sale al iniciar partida
- `PauseMenu` sale de PAUSED al cerrar
- DIALOG integrado en `player_interaction.gd`: entra al iniciar diálogo, sale al terminar

---

**Bug crítico — shop bloqueado tras equipar bolso desde journal**

Bug complejo que tardó varias horas en resolver. Al equipar el bolso desde la página 3 del journal (que vive en un SubViewport del addon PageFlip2D) y cerrar el journal, el shop subsiguiente aparecía correctamente pero no recibía clicks.

**Causa raíz:** El SubViewport del PageFlip2D seguía procesando input aunque el journal estuviera cerrado e invisible. Godot no desactiva el input de SubViewports al ocultar el nodo padre.

**Fix:** En `journal.gd`, al cerrar, se desactiva explícitamente el input del PageFlip2D y de todos sus SubViewports (`gui_disable_input = true`, `process_mode = DISABLED`, desactivación de todos los métodos de input). También se libera el foco de todos los SubViewports con `gui_release_focus()`. En `game_manager.gd`, se espera `await _journal.close()` antes de salir del estado JOURNAL, garantizando que el journal termina de cerrarse antes de que el shop pueda abrirse.

Fix encontrado con ayuda de GPT tras análisis conjunto.

---

**Frases de perfume — sistema de rotación**

Sustituido el sistema aleatorio (que repetía frases) por un shuffle al inicio de cada ciclo. Las 6 frases se barajan al principio y se recorren en orden, garantizando que no se repite ninguna hasta haber mostrado todas. Frases añadidas al CSV de traducciones en español e inglés.

---

**Estado del proyecto al final de la sesión**

- Shop funcional en todas las situaciones probadas
- Bolso implementado y funcionando (slots, equip, save/load)
- StateManager integrado en todos los sistemas principales
- DIALOG state activo — no se puede mover ni interactuar durante diálogos
- Bugs de save/load de stats con perfume resueltos
- Logs de debug activos en save_manager (`_log_stats`) y game_manager (clicks)