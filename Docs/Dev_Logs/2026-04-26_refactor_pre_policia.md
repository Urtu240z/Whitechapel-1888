# Devlog técnico — Refactorización y limpieza pre-policía

**Proyecto:** Whitechapel 1888  
**Motor:** Godot 4.6.2  
**Fecha:** 26 de abril de 2026  
**Tipo de documento:** Devlog técnico / documentación interna  
**Estado:** Refactorización aplicada y pendiente de pruebas generales de estabilidad

---

## 1. Contexto

Después de una refactorización general del proyecto, se realizó una pasada de limpieza técnica para preparar la base del juego antes de introducir sistemas más transversales, especialmente el futuro sistema de policía.

El objetivo principal fue reducir acoplamientos, centralizar responsabilidades y evitar que sistemas como diálogos, transiciones, edificios, escondites, sueño, actos con clientes o cambios de escena pudieran pisarse entre sí.

La policía será un sistema sensible porque tocará muchas partes del proyecto:

- player;
- NPCs;
- detección;
- escondites;
- interiores y exteriores;
- estados globales;
- audio;
- cámara;
- tiempo;
- transiciones;
- posibles consecuencias jugables.

Por eso, antes de crear `PoliceManager`, `NPCPolice` o componentes de detección, se decidió cerrar primero varias costuras de arquitectura.

---

## 2. Objetivos de esta limpieza

Los objetivos concretos fueron:

1. Centralizar el bloqueo/desbloqueo del player.
2. Evitar dobles diálogos o señales duplicadas en NPCs.
3. Integrar los portales de escena con el sistema común de interacción.
4. Asegurar que el tiempo del juego obedece al estado global.
5. Blindar flujos delicados como sueño y acto con cliente.
6. Preparar una API mínima de detección para futuros sistemas de policía.
7. Normalizar HideZones como sistema útil para ocultación/detección.
8. Corregir problemas de audio entre exteriores, interiores y ClientService.
9. Sacar código antiguo archivado fuera de `res://` para evitar conflictos.

---

## 3. Limpiezas y refactors aplicados

### 3.1. `_Archive` movido fuera de `res://`

Se movió la carpeta `_Archive` fuera del árbol principal del proyecto Godot.

Esto evita que Godot indexe scripts antiguos, especialmente si contienen `class_name`, clases duplicadas o dependencias ya reemplazadas por la arquitectura nueva.

**Motivo:** evitar conflictos silenciosos, autocompletados confusos o clases antiguas disponibles accidentalmente.

---

### 3.2. Bloqueo del player centralizado en `PlayerManager`

Se eliminaron llamadas directas desde otros scripts a:

```gdscript
player.disable_movement()
player.enable_movement()
```

El bloqueo del player ahora pasa por `PlayerManager`, usando razones de bloqueo.

Ejemplos de razones añadidas o normalizadas:

```gdscript
"npc_client_dialog"
"npc_client_distance_warning"
"npc_client_distance_cancel"
"npc_companion_dialog"
"legacy_npc_dialog"
```

**Ventaja:** varios sistemas pueden bloquear al player al mismo tiempo sin que uno de ellos lo desbloquee por error mientras otro todavía necesita mantenerlo bloqueado.

Esto es importante para:

- diálogos;
- advertencias de clientes;
- transiciones;
- sueño;
- ClientService;
- futuro sistema de policía;
- carga de partida.

---

### 3.3. Guardias de diálogo en Client y Companion

Se añadieron guardias internas para impedir dobles diálogos en:

```text
Scripts/NPC/Client/npc_client.gd
Scripts/NPC/Companion/npc_companion.gd
```

Se añadió una variable tipo:

```gdscript
var _dialog_active: bool = false
```

Con esto, si el jugador pulsa interactuar varias veces muy rápido o si un área dispara la interacción dos veces, el NPC no abre múltiples conversaciones ni duplica señales.

También se corrigió un punto peligroso en `NPCClient`: `Dialogic.timeline_ended` ahora se conecta antes de llamar a `Dialogic.start()`, evitando que diálogos muy cortos puedan terminar antes de que la señal esté conectada.

---

### 3.4. Diálogos legacy más seguros

Se revisó el flujo de interacción antiguo en:

```text
Scripts/Player/player_interaction.gd
```

Se añadió una guardia para evitar diálogos legacy duplicados:

```gdscript
var _legacy_dialog_active: bool = false
```

También se centralizó la limpieza al terminar el diálogo, asegurando que se restaura correctamente:

- estado global;
- movimiento del player;
- estado del NPC;
- bloqueo de facing;
- input posterior al diálogo.

Esto afecta principalmente a NPCs antiguos o ambientales que todavía usen el flujo anterior.

---

### 3.5. `ScenePortal` integrado con `InteractionManager`

Los portales de escena dejaron de depender de `_unhandled_input()` propio cuando requieren interacción.

Ahora funcionan así:

- `require_interact = false`: portal automático al entrar en el área.
- `require_interact = true`: portal registrado en `InteractionManager` y activado con la acción común de interactuar.

Se añadió prioridad específica:

```gdscript
PORTAL = 8
```

Orden de prioridades actual aproximado:

```text
BUILDING  = 10
HIDE_ZONE = 9
PORTAL    = 8
NPC       = 5
PICKUP    = 1
```

**Resultado:** buildings, NPCs, portales y escondites pasan por un sistema de interacción más coherente.

---

### 3.6. Salida de interiores sin necesidad de moverse

Se corrigió un problema al entrar en interiores: si el player aparecía directamente dentro del `ExitArea`, Godot no siempre disparaba `body_entered`. Por eso, después de entrar en un edificio, no se podía salir pulsando F hasta salir y volver a entrar en el área.

Se añadió una resincronización manual tras el spawn interior/exterior para detectar si el player ya está dentro del área de entrada o salida y registrar la interacción correcta.

**Resultado:** ahora se puede entrar en un edificio y salir directamente pulsando F sin tener que mover al personaje.

---

### 3.7. `DayNightManager` obedece a `StateManager`

El avance del tiempo ahora no depende únicamente de una variable interna de pausa, sino también de:

```gdscript
StateManager.can_advance_time()
```

Esto permite que el reloj se detenga correctamente en estados como:

- pausa;
- journal;
- shop;
- transition;
- client service;
- cutscene;
- debug menu;
- game over.

El tiempo sigue avanzando solamente en los estados permitidos por el `StateManager`.

**Nota:** durante el sueño, el tiempo no avanza de forma automática; lo controla manualmente `SleepManager` mediante avances por hora.

---

### 3.8. Pulido de SleepScreen

Se blindó el flujo de sueño para evitar cierres bruscos o dobles inputs.

Problema detectado: el jugador podía pulsar “despertar” mientras el fade inicial todavía estaba activo. Eso podía provocar que la pantalla de sueño desapareciera sin fade o que una transición rechazara otra.

Se añadieron guardias internas para:

- bloquear botones durante fades;
- impedir doble finalización;
- evitar inputs mientras la pantalla se está cerrando;
- pausar/reanudar correctamente el flujo visual.

---

### 3.9. Pulido de Client Transition y minijuego

Se corrigió un problema con el acto de cliente: pulsar F durante la transición podía saltar la animación de forma insegura, reiniciar pistas del `AnimationPlayer`, duplicar audio o hacer que el primer input del minijuego se consumiera incorrectamente.

Cambio aplicado:

- por ahora, la animación principal de transición no se puede saltar con F;
- el minijuego tiene un pequeño cooldown inicial de input;
- el minijuego no puede emitir finalización dos veces;
- se centralizó mejor la parada de audio de la transición.

**Nota de diseño:** esto no impide que en el futuro se añada un skip seguro. La forma correcta sería crear un método específico tipo `_skip_intro_safely()` en lugar de hacer un `seek()` bruto del `AnimationPlayer`.

---

### 3.10. API pre-policía en `PlayerManager`

Se añadieron métodos para que sistemas futuros, especialmente policía, puedan consultar el estado del player sin inspeccionar nodos internos.

API añadida:

```gdscript
PlayerManager.is_player_hidden()
PlayerManager.is_player_inside_building()
PlayerManager.get_active_building()
PlayerManager.can_player_be_detected()
PlayerManager.get_detection_position()
```

También se añadió una señal:

```gdscript
signal player_detection_state_changed(can_be_detected: bool)
```

**Objetivo:** que la policía pueda preguntar al `PlayerManager` si Nell es detectable, si está escondida o si está dentro de un edificio, sin acoplarse a HideZones, LevelRoot o nodos concretos de escena.

---

### 3.11. HideZone preparada para detección

`HideZone` se normalizó como sistema útil para ocultación y futura detección policial.

Se añadió:

```gdscript
class_name HideZone
```

Y grupo:

```gdscript
hide_zone
```

También se añadieron métodos como:

```gdscript
is_player_inside()
is_player_hidden_here()
get_hide_strength()
blocks_detection()
can_hide_player()
```

Y exports relacionados con detección/interacción:

```gdscript
hide_strength
blocks_police_detection
allow_client_service
interaction_label
exit_interaction_label
interaction_priority
```

**Resultado:** los escondites ya no son solo una interacción local, sino una pieza que puede consultar un futuro sistema de policía.

---

### 3.12. Corrección de audio interior/exterior tras ClientService

Se detectó un bug al hacer acto con cliente en HideZone: al volver del minijuego, podía seguir sonando la música correcta del mundo exterior, pero además activarse música interior de un edificio.

Causa probable:

- los audios interiores estaban en grupos globales de música/ambiente;
- `WorldAudioManager` podía restaurarlos al volver del acto con cliente;
- al usar `AudioStreamPlayer` normal en interiores, ya no dependían de la distancia y se escuchaban aunque el interior estuviera desplazado.

Corrección aplicada:

- los audios interiores de buildings quedan marcados como audio interior;
- el sistema sabe qué building controla ese audio;
- `WorldAudioManager` ignora interiores inactivos al restaurar audio global;
- `ClientServiceManager` fuerza sincronización de audio interior antes/después del acto.

**Resultado:** al volver de un acto con cliente en exterior/HideZone, solo debe restaurarse el audio exterior. Los interiores solo deben sonar cuando el player esté realmente dentro.

---

## 4. Estado actual del proyecto después de esta pasada

El proyecto queda en un estado más estable para seguir desarrollando contenido y preparar policía.

Resumen de estado:

```text
✅ _Archive fuera de res://
✅ Player locks centralizados en PlayerManager
✅ Client / Companion con guardia de diálogo
✅ Legacy dialogs más seguros
✅ ScenePortal integrado con InteractionManager
✅ Salida de interiores sin necesidad de moverse
✅ DayNightManager obedeciendo StateManager
✅ SleepScreen más blindada
✅ Client Transition más segura
✅ API pre-policía añadida en PlayerManager
✅ HideZone preparada para detección
✅ Audio interior/exterior corregido tras ClientService
```

---

## 5. Pruebas recomendadas

Antes de crear policía, se recomienda hacer una pasada de estabilidad con estas pruebas:

1. Entrar y salir varias veces de edificios.
2. Entrar en un edificio y salir directamente sin mover al player.
3. Abrir/cerrar journal dentro y fuera de edificios.
4. Abrir/cerrar pause menu.
5. Hablar con Client varias veces, pulsando F rápido.
6. Hablar con Companion varias veces, pulsando F rápido.
7. Probar NPC legacy/ambiental si todavía existe alguno.
8. Hacer acto con cliente en HideZone.
9. Confirmar que al volver del acto no suena audio interior incorrecto.
10. Dormir en Lodge.
11. Interrumpir sueño, seguir durmiendo y salir.
12. Cambiar de escena con ScenePortal automático y con F.
13. Guardar y cargar partida.
14. Confirmar que el player no queda bloqueado ni desbloqueado incorrectamente.
15. Confirmar que el tiempo no avanza en pause, journal, debug, transición o client service.

---

## 6. Próximo paso recomendado

Después de validar esta limpieza, el siguiente bloque lógico sería crear el prototipo mínimo de policía.

No conviene empezar con un sistema policial completo. La primera versión debería ser pequeña:

```text
PoliceManager básico
NPCPolice mínimo
PoliceSenseComponent
Patrulla simple
Detección simple
Sospecha básica
Persecución básica
Pérdida de detección al esconderse
```

Primera meta jugable:

```text
policía patrulla
↓
te detecta si eres visible
↓
sube sospecha
↓
te persigue
↓
te pierde si entras en HideZone o edificio seguro
↓
si te alcanza, aplica una consecuencia simple
```

No introducir todavía:

- arrestos complejos;
- sistema judicial;
- crímenes detallados;
- reputación legal avanzada;
- policía entrando en todos los edificios;
- sobornos complejos;
- persecuciones multi-NPC.

---

## 7. Decisiones pendientes

Antes o durante la implementación de policía habrá que decidir:

1. ¿La policía puede entrar en interiores?
2. ¿Todos los edificios son refugio seguro o solo algunos?
3. ¿Qué ocurre si Nell entra en un edificio mientras la persiguen?
4. ¿La policía espera fuera, pierde sospecha o fuerza la entrada?
5. ¿Qué consecuencia tiene ser atrapada?
6. ¿La sospecha baja con el tiempo?
7. ¿El journal debe pausar siempre el tiempo?
8. ¿Los diálogos deben permitir avance de tiempo o congelarlo?
9. ¿La policía detecta por distancia circular, cono visual o raycast con obstáculos?
10. ¿HideZone bloquea detección totalmente o reduce probabilidad?

---

## 8. Nota de arquitectura

La regla principal a mantener a partir de ahora:

> Los sistemas nuevos no deben saltarse los managers existentes.

Especialmente:

- no bloquear/desbloquear el player directamente;
- no cambiar estados globales sin `StateManager`;
- no restaurar audio sin `WorldAudioManager`;
- no consultar nodos internos del player desde policía;
- no hacer interacciones fuera de `InteractionManager` salvo casos muy justificados;
- no meter lógica de policía dentro de `enter_building.gd` o `hide_zone.gd` más allá de exponer información.

Esto debería evitar que la policía ensucie sistemas que ahora han quedado bastante más limpios.
