extends VBoxContainer

# ==========================================================
# MULTI-OSCILOSCOPIO
# ==========================================================
# Tres paneles independientes, cada uno con su propio eje vertical:
#   - FrameTime (VR/Sal/Med): comparten unidad (ms), se grafican
#     superpuestos en el mismo panel.
#   - Error: panel propio, con su propio rango (puede ser negativo).
#   - Actuador (escala de render s(k)): panel propio, rango [0.4, 1.1] x.
# Además, una fila de indicadores tipo LED —uno por cada perturbación—
# se enciende en el instante en que esa perturbación pasa a estar
# activa, y el fondo de los tres paneles se tiñe de un tono cálido
# mientras cualquier perturbación esté activa.
# ==========================================================

var max_puntos = 150

var paneles_config = [
	{ "titulo": "FrameTime (θₒ) — ms", "vars": ["VR", "Sal", "Med"] },
	{ "titulo": "Error e(k) — ms", "vars": ["Err"] },
	{ "titulo": "Actuador — Escala de Render s(k) — x", "vars": ["MV"] },
]

var datos = {
	"VR":  {"hist": [], "val": 0.0, "min": 10.0, "max": 35.0, "color": Color.GREEN,   "name": "VR (Setpoint)",   "unit": "ms"},
	"Sal": {"hist": [], "val": 0.0, "min": 10.0, "max": 35.0, "color": Color.RED,     "name": "Sal (θₒ real)",  "unit": "ms"},
	"Med": {"hist": [], "val": 0.0, "min": 10.0, "max": 35.0, "color": Color.ORANGE,  "name": "Med (filtrada)", "unit": "ms"},
	"Err": {"hist": [], "val": 0.0, "min": -10.0,"max": 15.0, "color": Color.MAGENTA, "name": "Error",          "unit": "ms"},
	"MV":  {"hist": [], "val": 0.0, "min": 0.4,  "max": 1.1,  "color": Color.CYAN,    "name": "Escala s(k)",    "unit": "x"},
}

# Identificadores esperados en el diccionario que llega por parámetro a
# actualizar_graficos(). Deben coincidir con las claves usadas en SistemaDRS.gd.
const PERTURBACIONES_INFO = {
	"geo":     {"nombre": "ALTA CARGA",       "color": Color(1.0, 0.65, 0.0)},
	"thermal": {"nombre": "THERMAL THROTTL.", "color": Color(1.0, 0.2, 0.2)},
	"disco":   {"nombre": "ACCESO A DISCO",   "color": Color(0.75, 0.35, 1.0)},
}

const COLOR_FONDO_NORMAL: Color = Color(0.05, 0.05, 0.05)
const COLOR_FONDO_ALERTA: Color = Color(0.17, 0.09, 0.03)

var lineas = {}
var labels = {}
var pantallas = {}   # panel_idx -> ColorRect
var leds = {}        # id de perturbación -> ColorRect

func _ready():
	# --- Fila de indicadores LED de perturbación activa ---
	var titulo_leds = Label.new()
	titulo_leds.text = "Perturbaciones:"
	titulo_leds.add_theme_font_size_override("font_size", 12)
	add_child(titulo_leds)

	var fila_leds = HBoxContainer.new()
	fila_leds.add_theme_constant_override("separation", 14)
	add_child(fila_leds)

	for id in PERTURBACIONES_INFO.keys():
		var info = PERTURBACIONES_INFO[id]
		var box = HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)

		var led = ColorRect.new()
		led.custom_minimum_size = Vector2(14, 14)
		led.color = info.color.darkened(0.8)
		box.add_child(led)
		leds[id] = led

		var lbl = Label.new()
		lbl.text = info.nombre
		lbl.add_theme_font_size_override("font_size", 11)
		box.add_child(lbl)

		fila_leds.add_child(box)

	var sep = HSeparator.new()
	add_child(sep)

	# --- Paneles independientes, uno por grupo de variables ---
	for panel_idx in range(paneles_config.size()):
		var conf = paneles_config[panel_idx]

		var titulo = Label.new()
		titulo.text = conf.titulo
		titulo.add_theme_font_size_override("font_size", 13)
		add_child(titulo)

		var pantalla = ColorRect.new()
		pantalla.color = COLOR_FONDO_NORMAL
		pantalla.custom_minimum_size = Vector2(0, 110)
		pantalla.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pantalla.clip_contents = true
		add_child(pantalla)
		pantallas[panel_idx] = pantalla

		var leyenda = VBoxContainer.new()
		leyenda.add_theme_constant_override("separation", 2)
		add_child(leyenda)

		for key in conf.vars:
			var info = datos[key]

			var line = Line2D.new()
			line.width = 2.0
			line.default_color = info.color
			pantalla.add_child(line)
			lineas[key] = line

			var lbl = RichTextLabel.new()
			lbl.bbcode_enabled = true
			lbl.fit_content = true
			lbl.scroll_active = false
			lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.custom_minimum_size = Vector2(0, 22)
			leyenda.add_child(lbl)
			labels[key] = lbl

		add_child(HSeparator.new())


# perturbaciones_activas: Dictionary con claves "geo", "thermal", "disco" -> bool
func actualizar_graficos(sp: float, med: float, pv: float, err: float, ctrl: float, perturbaciones_activas: Dictionary):
	datos["VR"].val = sp
	datos["Med"].val = med
	datos["Sal"].val = pv
	datos["Err"].val = err
	datos["MV"].val = ctrl

	# --- Actualizar LEDs y fondo de alerta ---
	var hay_perturbacion_activa = false
	for id in PERTURBACIONES_INFO.keys():
		var activa = perturbaciones_activas.get(id, false)
		if activa:
			hay_perturbacion_activa = true
		var info = PERTURBACIONES_INFO[id]
		if leds.has(id):
			leds[id].color = info.color if activa else info.color.darkened(0.8)

	var color_fondo = COLOR_FONDO_ALERTA if hay_perturbacion_activa else COLOR_FONDO_NORMAL
	for panel_idx in pantallas.keys():
		pantallas[panel_idx].color = color_fondo

	# --- Actualizar curvas ---
	for key in datos.keys():
		var info = datos[key]
		info.hist.append(info.val)
		if info.hist.size() > max_puntos:
			info.hist.pop_front()

		var color_hex = info.color.to_html(false)
		if labels.has(key):
			labels[key].text = "[color=#%s][b]%s:[/b] %.2f %s[/color]" % [color_hex, info.name, info.val, info.unit]

		if lineas.has(key):
			var pantalla: ColorRect = lineas[key].get_parent()
			var ancho_pantalla = pantalla.size.x
			var alto_pantalla = pantalla.size.y

			if ancho_pantalla > 0:
				lineas[key].clear_points()
				var paso_x = ancho_pantalla / float(max_puntos - 1)

				for i in range(info.hist.size()):
					var x = i * paso_x
					var val_clamp = clamp(info.hist[i], info.min, info.max)
					var y = alto_pantalla - ((val_clamp - info.min) / (info.max - info.min)) * alto_pantalla
					lineas[key].add_point(Vector2(x, y))
