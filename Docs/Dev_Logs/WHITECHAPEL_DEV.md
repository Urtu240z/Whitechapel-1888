# WHITECHAPEL 1888 — MASTER PROMPT
## Estado del proyecto a 3 de Abril de 2026

---

## CONTEXTO DEL JUEGO

Juego Godot 4.6, sidescroller 2D supervivencia/drama victoriano.
Protagonista: Eleanor "Nell", prostituta en Whitechapel, Londres, 1888.
Objetivo: ganar 200 chelines para escapar.

**Engine:** Godot 4.6.2 Standard
**Addons:** PageFlip2D (journal interactivo), Dialogic 2 (diálogos), SoupIK (rigging personajes)
**Idiomas:** Español / Inglés (sistema de traducción CSV activo)

---

## ARQUITECTURA — AUTOLOADS

SceneManager, GameManager, EffectsManager, SleepManager, PlayerManager,
SaveManager, DayNightManager, InventoryManager, InteractionManager,
PlayerStats, PhantomCameraManager, Dialogic

---

## SISTEMAS IMPLEMENTADOS Y FUNCIONANDO

### Stats del jugador (player_stats.gd)
- miedo, estres, felicidad, nervios, hambre, higiene, sueno, alcohol, laudano, salud, stamina, enfermedad, dinero
- sex_appeal calculado dinámicamente + sex_appeal_bonus (para perfumes)
- Degradación por tiempo, enfermedad progresiva, colapso por agotamiento
- Sistema de medicina activa

### Inventario posicional (inventory_manager.gd)
- 12 slots fijos
- Bolsillo + equipamiento separados
- Sistema de perfumes: usos (qty), timer de 16 horas, bonus temporales de stats
- Señal perfume_already_active con popup de humor negro
- Al usar ducha, quita el perfume activo
- Carga items de Data/Pickups/ y Data/Equip/
- Save/load completo del inventario

### Journal (PageFlip2D + SubViewport)
- Página 3: Inventario interactivo con menú contextual, fade al usar, mover entre slots
- Página 4: Equipamiento (slots visuales, sin desequipar desde UI todavía)
- Flechas/AD pasan página correctamente via BookAPI
- Menú se cierra al cerrar el journal

### Sistema de tienda (shop.gd + npc_service.gd + shop_item_data.gd)
- UI genérica reutilizable para cualquier vendedor
- Stock diario — fijo y variable (randomizado cada día)
- Stock se guarda/restaura con el save
- Stock visible y decremental en la UI mientras compras
- Límite de compra por max_stack del item
- Señales items_purchased y shop_closed

### NPCs de servicio
- NPCService: hostelero (Lodge), barman (Ten Bells), vendedora de perfumes (Streets)
- Orientación inicial configurable desde inspector
- Sistema de diálogo via Dialogic 2 con variables
- shop_name_key para nombre de tienda por NPC

### Save/Load
- 3 slots, formato JSON
- Guarda: stats, inventario, equipamiento, posición, interior/exterior, hora, stock de vendedores
- Restaura todo correctamente

### Sombra del jugador (player_shadow.gd)
- Sprite falso que sigue al farol más cercano (grupo street_lamp)
- Rotación suave con smoothstep, escala con proximidad
- Alpha directo según distancia
- Parámetros configurables desde MainPlayer exports

### Sistema de día/noche
- DayNightManager con señal hora_cambiada
- Iluminación ambiental con tween
- SleepManager integrado: hostal, calle, colapso forzado

### Cursor personalizado
- Mano victoriana 128x128 desde GameManager

---

## ARCHIVOS CLAVE

```
Scripts/Managers/player_stats.gd         — stats, economía, enfermedad, sex_appeal_bonus
Scripts/Managers/save_manager.gd         — save/load con shop_stocks
Scripts/Managers/inventory_manager.gd    — inventario + perfumes + equipamiento
Scripts/Managers/game_manager.gd         — input global, journal, cursor, journal_closed signal
Scripts/Managers/scene_manager.gd        — fade_out/fade_in públicos
Scripts/Managers/sleep_manager.gd        — sueño hostal/calle/colapso
Scripts/Managers/day_night_manager.gd    — ciclo día/noche
Scripts/UI/journal_page_3.gd             — inventario interactivo + popup perfume
Scripts/UI/shop.gd                       — UI tienda genérica
Scripts/Data/shop_item_data.gd           — Resource: item, max_qty, is_variable, variable_chance
Scripts/Data/item_data.gd                — ItemData con sección Equippable (duracion_horas, usos_max, sex_appeal_bonus, higiene_bonus, nervios_bonus, quita_perfume)
Scripts/Data/game_config.gd              — GameConfig Resource
Scripts/NPC/Service/npc_service.gd       — NPC servicio con shop modular + perfume_vendor
Scripts/NPC/Service/npc_service_animation.gd — animación con facing inicial via initialize(owner, facing_right)
Scripts/NPC/npc_conversation.gd          — usa PlayerManager para resolver player (no get_parent().get_parent())
Scripts/Player/player_shadow.gd          — sombra falsa
Scripts/Player/player_controller.gd      — MainPlayer con exports de shadow
Scenes/UI/Shop.tscn                      — escena tienda (CanvasLayer > Background > ShopPanel)
Data/Pickups/*.tres                      — items consumables
Data/Equip/*.tres                        — items equipables (perfumes)
Data/Game/game_config.tres               — valores de balance
Dialogues/barman.dtl                     — timeline barman
Dialogues/perfume_vendor.dtl             — timeline vendedora perfumes
```

---

## ITEMS EQUIPABLES CREADOS

### Perfumes (Data/Equip/)
| Nombre | ID | Coste | Sex Appeal | Higiene | Nervios | Variable |
|---|---|---|---|---|---|---|
| Bruma de Mayo | perfume-bruma-mayo | 24p | +10 | +20 | 0 | No |
| Susurro de Seda | perfume-susurro-seda | 36p | +15 | +15 | 0 | No |
| Jardín Secreto | perfume-jardin-secreto | 36p | +8 | +20 | -10 | Sí (60%) |
| Noche de Oriente | perfume-noche-oriente | 60p | +20 | +10 | 0 | Sí (50%) |
| Pecado Carmesí | perfume-pecado-carmesi | 96p | +30 | +5 | 0 | Sí (30%) |

Todos: duracion_horas=16, usos_max=3, max_stack=3

---

## VENDEDORES ACTIVOS

| NPC | service_id | Ubicación | Items |
|---|---|---|---|
| Hostelero | lodge_reception | Lodge_House | Habitación + sueño |
| Barman | barman | Bar_Bells | Bebidas + comida (fijos y variables) |
| Vendedora perfumes | perfume_vendor | Streets | 5 perfumes (2 fijos, 3 variables) |

---

## PENDIENTE — PRIORITARIO

### Inventario / Equipamiento
- [ ] Página 4 del journal — desequipar desde UI con menú contextual
- [ ] Drag and drop inventario (plan: CanvasLayer alto z-index, push_input coordenadas)
- [ ] Guardar/restaurar timer del perfume activo en el save

### Contenido
- [ ] Sistema de clientes como NPCs (actualmente son pickups en suelo)
- [ ] Más edificios y vendedores
- [ ] Más items equipables (ropa, accesorios)

### Sistemas por construir
- [ ] Sistema de policía
- [ ] Jack el Destripador
- [ ] Mapa en el journal
- [ ] Objetivos en el journal
- [ ] Cofre en habitación del hostal (storage temporal por día)

### Deuda técnica
- [ ] Player mixto persistente/incrustado — decidir modelo único
- [ ] Mover constantes de balance a GameConfig (cuando haya algo jugable para testear)
- [ ] Máquina de estados global (gameplay/paused/journal/dialog/sleeping/transitioning)
- [ ] Separar player_stats.gd en módulos (stats/core, economía, salud/enfermedad)

---

## CONVENCIONES DEL PROYECTO

- **Idioma del código:** Español para variables/funciones de dominio del juego, inglés para nombres de nodos/escenas
- **IDs de items:** kebab-case (`drink-cerveza`, `perfume-bruma-mayo`)
- **service_id:** snake_case (`barman`, `perfume_vendor`, `lodge_reception`)
- **Grupos Godot:** `npc_service`, `buildings`, `street_lamp`, `player`
- **Señales de journal:** `GameManager.journal_closed` para limpiar estado de páginas
- **Moneda:** peniques internamente, mostrar en chelines (÷12) en UI
- **Perfumes:** único en slot NECK_PERFUME, no reemplazable hasta ducharse
