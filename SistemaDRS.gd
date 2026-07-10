extends Node3D

# ==========================================
# CONSTANTES Y LEY DE CONTROL PID
# ==========================================
var Kp: float = 0.03
var Ki: float = 0.015
var Kd: float = 0.005
var SP_ms: float = 16.67
var integral: float = 0.0
var prev_error: float = 0.0

# ==========================================
# VARIABLES DE LA PLANTA (Configuración)
# ==========================================
var cant_obj_cada_instancia: int = 4 # Densidad nominal de objetos instanciados

# ==========================================
# CONFIGURACIÓN GRÁFICA (fija — hardware de referencia)
# ==========================================
var distancia_horizonte: float = 500.0
var segmentos_esfera_base: int = 32
var anillos_esfera_base: int = 16
var segmentos_esfera_densa: int = 128
var anillos_esfera_densa: int = 64

var mat_edificio_compartido: StandardMaterial3D
var mat_esfera_compartida: StandardMaterial3D

# ==========================================
# PERTURBACIÓN ESPACIAL p(t)
# ==========================================
var p_amplitud: float = 8.0  
var p_duracion: float = 4.0  
var p_valor_actual: float = 0.0  
var p_activa: bool = false
var thermal_throttling: bool = false

var p_z_inicio: float = 1.0 
var p_z_fin: float = 1.0
var p_programada_en_horizonte: bool = false

# ==========================================
# PERTURBACIÓN DE ACCESO A DISCO (stall SSD) — un solo disparo, con rampa
# ==========================================
var stall_activo: bool = false
var stall_temporizador: float = 0.0
var stall_duracion: float = 0.6      # s (coherente con el orden de magnitud del Escenario B del informe)
var stall_rampa: float = 0.2         # s de subida y de bajada
var stall_amplitud_ms: float = 100.0 # ms de retardo artificial en el pico

# Motivo de la perturbación vigente, usado para el log de tiempos de establecimiento
var ultima_perturbacion: String = "Transitorio de Arranque"

var nodo_ciudad: Node3D
var piso_plano: MeshInstance3D
var luz_sol: DirectionalLight3D
var entorno: WorldEnvironment
var ultima_pos_z_generacion: float = 0.0

# Filtros HMI y Planta
var pv_frametime_filtrado: float = 16.66 # NUEVO: Filtro Pasa-bajos de Planta
var ui_frametime_suavizado: float = 16.66
var ui_error_suavizado: float = 0.0
var ui_controlador_suavizado: float = 1.0

var grabando_csv: bool = false
var archivo_csv: FileAccess
var tiempo_absoluto: float = 0.0
var timer_muestreo: float = 0.0

# ==========================================
# MÉTRICAS DE ESTABILIZACIÓN (Tiempo ts)
# ==========================================
var ts_cronometro: float = 0.0
var ts_tiempo_en_banda: float = 0.0
var ts_registrado: float = 0.0
var ts_calculando: bool = true 
var ts_archivo_historial: FileAccess

# Referencias
var label_stats: RichTextLabel
var osc_rect: VBoxContainer
@onready var camara = $Camera3D

func _ready():
	Engine.max_fps = 60
	
	ts_archivo_historial = FileAccess.open("user://tiempos_establecimiento_ts.txt", FileAccess.WRITE)
	ts_archivo_historial.store_string("=== HISTORIAL DE TIEMPOS DE ESTABLECIMIENTO (ts) ===\n")
	ts_archivo_historial.store_string("Banda de Tolerancia: +/- 5% (15.83 ms - 17.50 ms)\n\n")
	
	entorno = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.65, 0.85) 
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.6, 0.7)
	env.fog_density = 0.002 
	entorno.environment = env
	add_child(entorno)
	
	luz_sol = DirectionalLight3D.new()
	luz_sol.rotation_degrees = Vector3(-80, 0, 0)
	luz_sol.shadow_enabled = true
	luz_sol.directional_shadow_max_distance = 600.0 
	add_child(luz_sol)
	
	piso_plano = MeshInstance3D.new()
	var mesh_piso = PlaneMesh.new()
	mesh_piso.size = Vector2(2500, 2500)
	piso_plano.mesh = mesh_piso
	var mat_piso = StandardMaterial3D.new()
	mat_piso.albedo_color = Color(0.12, 0.18, 0.12)
	mat_piso.roughness = 1.0 
	mat_piso.specular = 0.0 
	piso_plano.material_override = mat_piso
	add_child(piso_plano)
	
	nodo_ciudad = Node3D.new()
	add_child(nodo_ciudad)
	ultima_pos_z_generacion = camara.global_position.z
	
	mat_edificio_compartido = StandardMaterial3D.new()
	mat_edificio_compartido.roughness = 0.8
	mat_edificio_compartido.albedo_color = Color(0.3, 0.3, 0.35)
	
	mat_esfera_compartida = StandardMaterial3D.new()
	mat_esfera_compartida.roughness = 0.8
	mat_esfera_compartida.albedo_color = Color(0.85, 0.9, 0.95)
	
	_construir_interfaz_dinamica()

func _process(delta: float):
	var pv_frametime_crudo = delta * 1000.0 
	
	# === FILTRO PASA-BAJOS DE PLANTA ===
	# Amortigua los saltos estocásticos de 1 frame de la CPU
	pv_frametime_filtrado = lerp(pv_frametime_filtrado, pv_frametime_crudo, 0.3)
	
	piso_plano.global_position.z = camara.global_position.z
	piso_plano.global_position.x = camara.global_position.x
	
	if p_programada_en_horizonte:
		if camara.global_position.z <= p_z_inicio and camara.global_position.z >= p_z_fin:
			if not p_activa:
				p_activa = true
				ultima_perturbacion = "Alta Carga (Zona Densa)"
				ts_cronometro = 0.0
				ts_tiempo_en_banda = 0.0
				ts_calculando = true
			p_valor_actual = p_amplitud
		else:
			p_valor_actual = 0.0
			if camara.global_position.z < p_z_fin:
				p_activa = false
				p_programada_en_horizonte = false
	else:
		p_valor_actual = 0.0
		p_activa = false

	if thermal_throttling: OS.delay_msec(4)

	if stall_activo:
		stall_temporizador += delta
		var delay_ms = 0.0
		if stall_temporizador < stall_rampa:
			delay_ms = stall_amplitud_ms * (stall_temporizador / stall_rampa)
		elif stall_temporizador > (stall_duracion - stall_rampa):
			delay_ms = stall_amplitud_ms * max(0.0, (stall_duracion - stall_temporizador) / stall_rampa)
		else:
			delay_ms = stall_amplitud_ms
		OS.delay_msec(int(round(delay_ms)))
		if stall_temporizador >= stall_duracion:
			stall_activo = false
	
	# ---------------------------------------------------------
	# LAZO PID MEJORADO CONTRA OSCILACIONES Y WINDUP
	# ---------------------------------------------------------
	var error = pv_frametime_filtrado - SP_ms
	
	# Banda Muerta (Deadband) Ampliada a 1.0ms
	if abs(error) < SP_ms*0.05: 
		error = 0.0 
	
	var derivativa = (error - prev_error) / delta
	var integral_potencial = integral + (error * delta)
	
	# === SOLUCIÓN: PURGA INTEGRAL DIRECTA ===
	# Ya no falseamos la variable 'error'. En su lugar, descargamos 
	# suavemente la memoria matemática del acumulador integral.
	var escala_actual = get_viewport().scaling_3d_scale
	if error == 0.0 and escala_actual < 1.0 and not p_activa:
		integral_potencial = max(0.0, integral_potencial - (2.0 * delta))
		
		
	var accion_P = Kp * error
	var accion_I = Ki * integral_potencial
	var accion_D = Kd * derivativa
	var u_t = accion_P + accion_I + accion_D 
	
	var mv_escala_objetivo = 1.0 - u_t
	var mv_escala_saturada = clamp(mv_escala_objetivo, 0.5, 1.0)
	
	if mv_escala_objetivo == mv_escala_saturada:
		integral = integral_potencial
		
	get_viewport().scaling_3d_scale = mv_escala_saturada
	prev_error = error

	# ---------------------------------------------------------
	# GENERACIÓN Y CULLING
	# ---------------------------------------------------------
	if camara.global_position.z < ultima_pos_z_generacion - 20.0:
		ultima_pos_z_generacion = camara.global_position.z
		
		var z_horizonte = camara.global_position.z - distancia_horizonte
		var horizonte_en_zona_densa = (z_horizonte <= p_z_inicio and z_horizonte >= p_z_fin)
		var cantidad_a_generar = int(p_amplitud*cant_obj_cada_instancia) if horizonte_en_zona_densa else cant_obj_cada_instancia
		
		for i in range(cantidad_a_generar):
			var z_rand = randf_range(z_horizonte - 10, z_horizonte + 10)
			_instanciar_objeto(z_rand, horizonte_en_zona_densa)
		
	for child in nodo_ciudad.get_children():
		if child.global_position.z > camara.global_position.z + distancia_horizonte:
			child.queue_free()

	# ---------------------------------------------------------
	# MÉTRICAS DE ESTABLECIMIENTO (ts)
	# ---------------------------------------------------------
	if ts_calculando:
		ts_cronometro += delta
		var error_porcentual = abs((pv_frametime_filtrado - SP_ms) / SP_ms)
		
		if error_porcentual <= 0.05:
			ts_tiempo_en_banda += delta
			if ts_tiempo_en_banda >= 1.5:
				ts_calculando = false
				ts_registrado = ts_cronometro - 1.5 
				
				var motivo = ultima_perturbacion
				
				var log_txt = "[%.1f s] Kp:%.3f Ki:%.3f Kd:%.3f | %s -> Estabilizado en: %.2f segundos.\n" % [tiempo_absoluto, Kp, Ki, Kd, motivo, ts_registrado]
				ts_archivo_historial.store_string(log_txt)
				ts_archivo_historial.flush() 
				print("✔️ ts guardado: ", ts_registrado, "s")
		else:
			ts_tiempo_en_banda = 0.0 

	ui_frametime_suavizado = lerp(ui_frametime_suavizado, pv_frametime_crudo, 0.1)
	ui_error_suavizado = lerp(ui_error_suavizado, error, 0.1)
	if abs(ui_error_suavizado) < 0.01: ui_error_suavizado = 0.0
	ui_controlador_suavizado = lerp(ui_controlador_suavizado, mv_escala_saturada, 0.1)
	if abs(1.0 - ui_controlador_suavizado) < 0.005: ui_controlador_suavizado = 1.0

	tiempo_absoluto += delta 
	
	if label_stats and osc_rect:
		_actualizar_hmi_texto()
		var perturbaciones_activas = {
			"geo": p_programada_en_horizonte,
			"thermal": thermal_throttling,
			"disco": stall_activo
		}
		osc_rect.actualizar_graficos(SP_ms, ui_frametime_suavizado, pv_frametime_filtrado, ui_error_suavizado, ui_controlador_suavizado, perturbaciones_activas)
		
	if grabando_csv:
		timer_muestreo += delta
		if timer_muestreo >= 0.1:
			timer_muestreo = 0.0
			var linea = "%.2f,%.2f,%.2f,%.2f,%.4f,%.2f,%.3f,%.3f,%.3f\n" % [tiempo_absoluto, SP_ms, ui_frametime_suavizado, ui_error_suavizado, ui_controlador_suavizado, p_valor_actual, Kp, Ki, Kd]
			archivo_csv.store_string(linea)

func _on_disparar_pulso():
	if not p_programada_en_horizonte:
		var velocidad = camara.velocidad_crucero if "velocidad_crucero" in camara else 35.0
		var longitud_zona = p_duracion * velocidad
		
		p_z_inicio = camara.global_position.z - distancia_horizonte 
		p_z_fin = p_z_inicio - longitud_zona
		p_programada_en_horizonte = true

func _on_disparar_stall_disco():
	if stall_activo:
		return
	stall_activo = true
	stall_temporizador = 0.0
	ultima_perturbacion = "Acceso a Disco (Stall SSD)"
	ts_cronometro = 0.0
	ts_tiempo_en_banda = 0.0
	ts_calculando = true

func _instanciar_objeto(z_pos: float, es_zona_densa: bool):
	var instancia = MeshInstance3D.new()
	
	var es_edificio = randf() > 0.4 
	
	if es_edificio:
		var mesh = BoxMesh.new()
		var alto = randf_range(20, 80)
		mesh.size = Vector3(randf_range(10, 20), alto, randf_range(10, 20))
		instancia.mesh = mesh
		instancia.position = Vector3(randf_range(-200, 200), alto / 2.0, z_pos)
		instancia.set_surface_override_material(0, mat_edificio_compartido)
	else:
		var mesh = SphereMesh.new()
		mesh.radial_segments = segmentos_esfera_densa if es_zona_densa else segmentos_esfera_base
		mesh.rings = anillos_esfera_densa if es_zona_densa else anillos_esfera_base
		mesh.radius = randf_range(10, 18)
		mesh.height = mesh.radius * randf_range(0.8,1.2)
		instancia.mesh = mesh
		instancia.position = Vector3(randf_range(-200, 200), randf_range(90, 120), z_pos)
		instancia.set_surface_override_material(0, mat_esfera_compartida)
		
	instancia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	nodo_ciudad.add_child(instancia)

# ==========================================
# INTERFAZ
# ==========================================

func _construir_interfaz_dinamica():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var hbox_main = HBoxContainer.new()
	hbox_main.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(hbox_main)
	
	var zona_vuelo = Control.new()
	zona_vuelo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_main.add_child(zona_vuelo) 
	
	var panel_scada = PanelContainer.new()
	panel_scada.custom_minimum_size = Vector2(480, 0)
	panel_scada.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox_main.add_child(panel_scada)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	panel_scada.add_child(margin)
	
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 15)
	scroll.add_child(vbox)
	
	var hbox_sys = HBoxContainer.new()
	
	var btn_reset = Button.new()
	btn_reset.text = "🔄 Reiniciar Sim."
	btn_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_reset.pressed.connect(func(): get_tree().reload_current_scene())
	hbox_sys.add_child(btn_reset)
	
	var btn_csv = Button.new()
	btn_csv.text = "⏺ Grabar CSV"
	btn_csv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_csv.pressed.connect(_on_toggle_csv)
	hbox_sys.add_child(btn_csv)
	
	var btn_salir = Button.new()
	btn_salir.text = "❌ Salir"
	btn_salir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_salir.pressed.connect(func(): get_tree().quit())
	hbox_sys.add_child(btn_salir)
	
	vbox.add_child(hbox_sys)
	
	label_stats = RichTextLabel.new()
	label_stats.bbcode_enabled = true
	label_stats.custom_minimum_size = Vector2(0, 180)
	vbox.add_child(label_stats)
	
	var crear_slider = func(texto, val_min, val_max, step, val_inicial, callback):
		var h = HBoxContainer.new()
		var l = Label.new(); l.text = texto; l.custom_minimum_size = Vector2(110, 0)
		var s = HSlider.new(); s.min_value = val_min; s.max_value = val_max; s.step = step; s.value = val_inicial
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v = Label.new(); v.text = str(val_inicial); v.custom_minimum_size = Vector2(50, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.value_changed.connect(func(val): v.text = str(val); callback.call(val))
		h.add_child(l); h.add_child(s); h.add_child(v)
		vbox.add_child(h)

	crear_slider.call("Kp (Prop)", 0.0, 0.1, 0.001, Kp, func(val): Kp = val)
	crear_slider.call("Ki (Integ)", 0.0, 0.05, 0.001, Ki, func(val): Ki = val)
	crear_slider.call("Kd (Deriv)", 0.0, 0.02, 0.001, Kd, func(val): Kd = val)
	crear_slider.call("Densidad (obj/f)", 1.0, 12.0, 1.0, cant_obj_cada_instancia, func(val): cant_obj_cada_instancia = val)
	crear_slider.call("Amp. Pert.", 0.0, 20.0, 1.0, p_amplitud, func(val): p_amplitud = val)
	crear_slider.call("Duración Pert. (s)", 1.0, 15.0, 1.0, p_duracion, func(val): p_duracion = val)
	
	var btn_pulso = Button.new()
	btn_pulso.text = "⚡ DISPARAR ALTA CARGA (Zona Densa)"
	btn_pulso.custom_minimum_size = Vector2(0, 45)
	btn_pulso.pressed.connect(_on_disparar_pulso)
	vbox.add_child(btn_pulso)
	
	var btn_th = Button.new()
	btn_th.text = "🔥 TOGGLE THERMAL THROTTLING"
	btn_th.custom_minimum_size = Vector2(0, 45)
	btn_th.pressed.connect(func(): 
		thermal_throttling = !thermal_throttling
		if thermal_throttling:
			ultima_perturbacion = "Thermal Throttling"
		ts_cronometro = 0.0
		ts_tiempo_en_banda = 0.0
		ts_calculando = true
	)
	vbox.add_child(btn_th)

	var btn_stall = Button.new()
	btn_stall.text = "💾 DISPARAR ACCESO A DISCO"
	btn_stall.custom_minimum_size = Vector2(0, 45)
	btn_stall.pressed.connect(_on_disparar_stall_disco)
	vbox.add_child(btn_stall)
	
	osc_rect = VBoxContainer.new()
	osc_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	osc_rect.set_script(load("res://MultiOsciloscopio.gd"))
	vbox.add_child(osc_rect)

func _actualizar_hmi_texto():
	var txt = "[font_size=16][b]Sistema de Control de FrameTime mediante Escalado Dinámico de Resolución para Simuladores de Vuelo[/b][/font_size]\n"
	txt += "Por: Ignacio Pereda\n"
	txt += "Valor de Referencia (VR): [color=green]16.66 ms[/color]\n"
	txt += "Medición: [color=orange]%.2f ms[/color]\n" % ui_frametime_suavizado
	txt += "Señal de Error (e): [color=magenta]%+.2f ms[/color]\n" % ui_error_suavizado
	txt += "Actuador Escala (MV): [color=cyan]%.2f x[/color]\n" % ui_controlador_suavizado
	txt += "--------------------------------------\n"
	
	if ts_calculando:
		txt += "Tiempo Establecimiento (ts): [color=yellow]Calculando...[/color]\n"
	else:
		txt += "Tiempo Establecimiento (ts): [color=green]%.2f seg[/color]\n" % ts_registrado
	
	txt += "Zona de Perturbación: %s\n" % ("[color=yellow]ATRAVESANDO[/color]" if p_activa else "Despejado")
	txt += "Thermal Throttling: %s\n" % ("[color=red]ACTIVO[/color]" if thermal_throttling else "Inactivo")
	txt += "Acceso a Disco: %s\n" % ("[color=#bf5fff]ACTIVO[/color]" if stall_activo else "Inactivo")
	
	if grabando_csv:
		txt += "\n[color=green]► GRABANDO DATOS TELEMÉTRICOS (%.1f s)[/color]" % tiempo_absoluto
		
	label_stats.text = txt

func _on_toggle_csv():
	grabando_csv = !grabando_csv
	if grabando_csv:
		archivo_csv = FileAccess.open("user://telemetria_drs.csv", FileAccess.WRITE)
		archivo_csv.store_string("Tiempo_s,SP_ms,PV_FrameTime_ms,Error_ms,MV_Escala,Perturbacion_pt,Kp,Ki,Kd\n")
		timer_muestreo = 0.0
		print("GRABANDO EN: ", OS.get_user_data_dir(), "/telemetria_drs.csv")
	else:
		archivo_csv.close()
		print("Grabación detenida y guardada.")
