extends VBoxContainer

var max_puntos = 150
var pantalla_grafico: ColorRect

var datos = {
	"VR":   {"hist": [], "val": 0.0, "min": 10.0, "max": 35.0, "color": Color.GREEN, "on": true, "name": "VR", "unit": "ms"},
	"Sal":   {"hist": [], "val": 0.0, "min": 10.0, "max": 35.0, "color": Color.RED, "on": true, "name": "Sal", "unit": "ms"},
	"Med":  {"hist": [], "val": 0.0, "min": 10.0, "max": 35.0, "color": Color.ORANGE, "on": true, "name": "Med", "unit": "ms"},
	"Err":  {"hist": [], "val": 0.0, "min": -10.0, "max": 15.0, "color": Color.MAGENTA, "on": true, "name": "Err", "unit": "ms"},
	"MV": {"hist": [], "val": 0.0, "min": 0.4,  "max": 1.1,  "color": Color.CYAN, "on": true, "name": "MV", "unit": "x"},
	"Pert": {"hist": [], "val": 0.0, "min": 0.0,  "max": 20.0, "color": Color.YELLOW, "on": true, "name": "p(t)", "unit": "obj"}
}

var lineas = {}
var labels = {}

func _ready():
	pantalla_grafico = ColorRect.new()
	pantalla_grafico.color = Color(0.05, 0.05, 0.05)
	pantalla_grafico.custom_minimum_size = Vector2(0, 300)
	pantalla_grafico.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pantalla_grafico.clip_contents = true 
	add_child(pantalla_grafico)
	
	var leyenda = GridContainer.new()
	leyenda.columns = 3 
	add_child(leyenda)
	
	for key in datos.keys():
		var info = datos[key]
		
		var line = Line2D.new()
		line.width = 2.0
		line.default_color = info.color
		pantalla_grafico.add_child(line)
		lineas[key] = line
		
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
		
		var check = CheckBox.new()
		check.button_pressed = true
		check.toggled.connect(func(toggled_on): 
			datos[key].on = toggled_on
			lineas[key].visible = toggled_on
		)
		hbox.add_child(check)
		
		var lbl = RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
		lbl.custom_minimum_size = Vector2(90, 25)
		hbox.add_child(lbl)
		labels[key] = lbl
		
		leyenda.add_child(hbox)

func actualizar_graficos(sp, med, pv, err, ctrl, pert):
	datos["VR"].val = sp
	datos["Med"].val = med
	datos["Sal"].val = pv
	datos["Err"].val = err
	datos["MV"].val = ctrl
	datos["Pert"].val = pert
	
	var ancho_pantalla = pantalla_grafico.size.x
	var alto_pantalla = pantalla_grafico.size.y
	
	for key in datos.keys():
		var info = datos[key]
		
		info.hist.append(info.val)
		if info.hist.size() > max_puntos:
			info.hist.pop_front()
			
		var color_hex = info.color.to_html(false)
		labels[key].text = "[color=#%s][b]%s:[/b] %.2f %s[/color]" % [color_hex, info.name, info.val, info.unit]
		
		if info.on and ancho_pantalla > 0:
			lineas[key].clear_points()
			var paso_x = ancho_pantalla / float(max_puntos - 1)
			
			for i in range(info.hist.size()):
				var x = i * paso_x
				var val_clamp = clamp(info.hist[i], info.min, info.max)
				var y = alto_pantalla - ((val_clamp - info.min) / (info.max - info.min)) * alto_pantalla
				lineas[key].add_point(Vector2(x, y))
