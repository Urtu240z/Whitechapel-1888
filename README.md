A ver, quiero crearme un poco un planning de tareas para ir haciendo, porque voy saltando de una a otra si sentido solo por lo que me viene a la cabeza en este momento. 
O una especie de GDD, asi que necesito tu ayuda... 

El juego: Whitechapel 1888 

Tipo de juego: Sidescroller 2d de supervivencia, hide and seek, gestion, terror, drama y con mapas isometricos. 

Historia: Eres Eleanor (Ellie-Nell-Nellie) una mujer nacida en el año 1861 a las afueras de Londres, que se casa con Thomas Finch, Son dos personas de clase baja que viven en una granja arrendada, donde cultivan sus alimentos y venden para subsistir. La vida es dura, pero son felices con sus destinos. En 1879 nace su hija Emily. 
La granja queda entre Ongar y Epping (Essex), unos 35 km al noreste de Londres, justo más allá del río Lea. 
Thomas era un hombre decente y trabajador, pero incapaz de mantener a flote la granja arrendada a unos terratenientes, viendo cómo su familia se hundía poco a poco. 
El alcohol fue su manera de silenciar el ruido interno debido a cada visita de los acreedores y los precios del grano cayendo debido al mas barato trigo americano. 
El alcohol no transformo la bondad de Thomas, pero si la acalló, y fue rompiendo un hombre que siempre tenia una sonrisa.
Lo encontro Nell una mañana colgando de una biga de madera del establo.
Nell tiene que luchar entre la terrible devastacion de perder a su motor vital y alma gemela, y la IRA y el pensamiento de que Thomas ha sido un COBARDE, por irse de este mundo dejandolas a las dos solas, sin pensar que podian hacer para arreglar las cosas.
Es un duelo muy extraño de GRITOS y LAGRIMAS.

La muerte, un acto de “liberación” mal entendida, en una sociedad donde pedir ayuda no existía.
El sucidio, se ocultaba bajo diagnósticos como “muerte accidental” o “locura pasajera” y Nell queda con culpa, vergüenza social y estigma religioso (en la época, los suicidas no se enterraban en suelo consagrado)

Entonces, cuando Thomas murió, el trigo ya no pagaba ni la harina que comían.
El hombre del molino habló de Londres: “allí hay fábricas, allí pagan.”
Ella no soñaba con nada, solo quería un techo y leche para Emily.
El tren olía a carbón y promesas.
A los tres meses, el hombre ya no estaba, y la niña tosía en una cama alquilada a dos chelines la noche.

Desde Epping Station (abierta en 1865) se podía cargar mercancía hacia los mercados de Spitalfields o Smithfield en Londres.






Siguientes pasos:

- Crear Timer o sistema dia/noche.
- Crear escenas con placeholders para los distintos locales.
  - Preparar tilemaps, para hacer fondos.
- Crear pickups en los locales con el sistema económico
- poner clientes aleatorios por el escenario, pero falta darle una vuelta al sistema de algoritmo


/ (raíz del proyecto)
├── Scenes/
│    ├── Interiors/
│    │    ├── Taberna.tscn
│    │    ├── Hostal.tscn
│    │    └── Baño.tscn
│    ├── Exteriors/
│    │    ├── CallePrincipal.tscn
│    │    └── Mercado.tscn
│    ├── UI/
│    │    ├── UI_Comer.tscn
│    │    ├── UI_Hud.tscn
│    │    └── UI_Dialogo.tscn
│    └── Pickups/
│         ├── Comida.tscn
│         ├── Vino.tscn
│         └── Rata.tscn
├── Scripts/
│    ├── Autoload/         ← scripts que serán singletons
│    │    ├── PlayerStats.gd
│    │    └── GameManager.gd
│    ├── Player/
│    │    └── Player.gd
│    ├── NPC/
│    │    └── Tabernero.gd
│    ├── Pickup/
│    │    └── Pickup.gd
│    ├── UI/
│    │    └── UI_Comer.gd
│    │    └── UI_Hud.gd
│    └── ScenesLogic/
│         └── TabernaLogic.gd
├── Assets/   ← gráficos, sonidos, fuentes
│    ├── Sprites/
│    ├── Audio/
│    └── Fonts/
├── project.godot
└── … otros archivos (README, .gitignore, etc.)



Perfecto, entonces ahora... Viene la parte divertida.
Quiero que el personaje tenga unos atributos que suban o bajen dependiendo de cosas externas.
Quiero que tenga digamos un valor que no se que como llamarle... Sex appeal quizas ( teniendo en cuenta que es una prostituta en whitechapel en 1888)
Este valor subira dependiendo de otras variables, estres, felicidad, nervios, comida, higiene, sueño, alcohol, laudano, entonces tengo que ver que porcentaje aportan al sex appeal cada uno, algunos suman otros restan, pero el objetivo final del valor sex appeal es conseguir mejores clientes que puedan generar mas dinero, y EN GENERAL, en el corto plazo poder seguir pagando un hostal, comida, etc. Sino dormiremos en la calle. Y EL OBJETIVO FINAL, es tener suficiente economia para poder huir del sistema al campo y vivir tranquila.

💰 Precios típicos en Whitechapel (1888)

(en peniques y chelines; 12 peniques = 1 chelín)

Una comida barata en un “doss house” (albergue obrero):

Pan y té: 1 o 2 peniques

Pan con un poco de queso o tocino: 2–3 peniques

Guiso barato (“pea soup” o “stew”): 2–4 peniques

Una comida completa en una taberna o café barato:

Plato de carne con patatas o pan: 6 peniques (½ chelín)

Té o cerveza pequeña: 1 penique

Comida callejera (muy común):

Tarta de anguila o pastel de carne: 1–2 peniques

Patatas asadas o gachas de avena: menos de 1 penique

💵 Para ponerlo en perspectiva

Un obrero no especializado ganaba entre 3 y 5 chelines al día (36–60 peniques).
Una prostituta o trabajadora ocasional podía ganar 4–8 peniques por cliente, a veces menos.
Un alojamiento nocturno en un “doss house” costaba 4 peniques por una cama, o 2 peniques por un sitio para dormir sentado.

🍽️ Ejemplo de un día “barato” en Whitechapel

Desayuno: Pan y té (2 peniques)

Almuerzo: Sopa de guisantes y pan (3 peniques)

Cena: Pastel de carne y una taza de té (3 peniques)
👉 Total del día: 8 peniques, casi el 20% del salario diario de un obrero.

¿Quieres que te haga una tabla o recree un menú típico de un comedor barato de Whitechapel en 1888 (con precios y descripciones)? Podría ser útil si estás escribiendo una historia o guion.

Tú dijiste:
Si quiero una tabla con todos los costes de una prostituta de esa epoca, con gastos y ganancias
ChatGPT Plus

Perfecto — puedo ayudarte con eso de manera histórica y contextual, sin contenido explícito, centrándonos en los aspectos económicos y sociales del oficio en Whitechapel en 1888.

La información disponible proviene de informes policiales, registros de trabajo social (como los de Charles Booth y Henry Mayhew) y testimonios contemporáneos.

Aquí tienes una tabla orientativa con gastos y ganancias semanales aproximadas de una prostituta de clase baja o “casual prostitute” del East End en 1888:

💸 Economía típica de una prostituta pobre en Whitechapel, 1888
Concepto	Descripción	Costo o ingreso estimado (peniques/chelines)	Frecuencia	Comentarios
Ganancia por cliente	Promedio de pago por servicio	4–8 peniques (a veces hasta 1 chelín)	Por cliente	Muy variable; muchas mujeres cobraban lo justo para pagar alojamiento y comida.
Clientes por noche	2–5 (en noches buenas)	—	Diario	En malas noches, ninguno.
Ingreso diario estimado	Basado en 3 clientes de 6 peniques cada uno	18 peniques (1 chelín y 6 peniques)	Diario	Lo suficiente para comida, cama y algo de alcohol.
Alojamiento (“doss house”)	Cama básica en casa de alojamiento	4 peniques	Diario	Alternativa: “sit-up” (2 peniques) sin cama.
Comida	Pan, té, sopa, algo de carne	6–8 peniques	Diario	Comida pobre, de taberna o puesto callejero.
Ropa / lavado	Limpieza y reparación de ropa	1–2 chelines	Semanal	Necesario para mantener apariencia mínima.
Alcohol (gin, beer)	Bebida para soportar el trabajo	3–6 peniques	Diario	Consumo muy común; a veces excesivo.
Ganancia semanal bruta	Basada en 5 días “buenos” de trabajo	7–10 chelines	Semanal	Variable según suerte, enfermedad o arrestos.
Gasto semanal total	Suma de comida, alojamiento, etc.	5–7 chelines	Semanal	Dejando poco o nada de ahorro.
Ahorro o saldo neto	(Ingreso – gastos)	1–3 chelines	Semanal	Solo si no había días sin clientes o enfermedad.
🧾 Resumen

La mayoría vivía día a día, sin capacidad de ahorro.

Muchas alternaban el trabajo sexual con limpieza, costura o venta ambulante.

Enfermedad, alcoholismo o violencia reducían drásticamente las ganancias.

El motivo principal de dedicarse a ello era la pobreza extrema.

¿Quieres que te prepare esta misma tabla convertida a valores modernos (por ejemplo, cuánto equivaldría hoy en libras o euros)? Eso puede ayudarte a visualizar mejor las proporciones económicas.



LA HORA APREMIA.
A cierta hora la posibilidad de coger hostal se dificulta. o mas CARO? falta info
