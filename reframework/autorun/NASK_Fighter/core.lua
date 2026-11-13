-- ============================================================================
--  NASK FIGHTER · core.lua
--  Câmera livre, pausa, Hide UI, visual, luzes e cenário.
--  Escrito do zero para o NASK Fighter; usa só a API do REFramework.
-- ============================================================================

if _G.__NASK_CORE then return _G.__NASK_CORE end

-- imgui com tradução (ver lang.lua)
local imgui = require("NASK_Fighter/lang").ui
local keys = require("NASK_Fighter/keys")

local C = {}
_G.__NASK_CORE = C

local FILE = "NASK_Fighter\\core.json"

-- ---------------------------------------------------------------------------
-- Configuração
-- ---------------------------------------------------------------------------
local DEFAULTS = {
	move_speed = 2.5,      -- metros por segundo
	rot_speed = 1.0,       -- multiplicador da rotação (mouse e analógico)
	invert_pad = false,
	luts = {},             -- caminhos de LUT já vistos no jogo
	dof_type = 2,          -- 1 Default, 2 Tessellation, 3 Lite, 4 Circular
	dof_quality = 3,       -- 1 Máxima, 2 Alta, 3 Leve
	dof_apply = true,
}

local function fill(t, d)
	for k, v in pairs(d) do
		if t[k] == nil then
			if type(v) == "table" then t[k] = {} ; fill(t[k], v) else t[k] = v end
		end
	end
	return t
end

C.settings = fill(json.load_file(FILE) or {}, DEFAULTS)
if not C.settings.dof_v264 then C.settings.dof_quality = 1; C.settings.dof_v264 = true end
if not C.settings.dof_v267 then C.settings.dof_quality = 3; C.settings.dof_v267 = true end
-- árvores que devem voltar fechadas quando o HUD abre (o HUD sobe C.ui_gen)
C.ui_gen, C.seen_gen = 0, {}
function C.fresh(id)
	if C.seen_gen[id] ~= C.ui_gen then C.seen_gen[id] = C.ui_gen; return true end
	return false
end
function C.save() json.dump_file(FILE, C.settings) end

-- Teclas (layout NASK, igual ao modo foto da Bayonetta)
local ACTIONS = {
	{ "Activate FreeCam", "Insert" },
	{ "Cam Forward", "W" }, { "Cam Backward", "S" }, { "Cam Left", "A" }, { "Cam Right", "D" },
	{ "Cam Up", "Space" }, { "Cam Down", "LControl" },
	{ "Zoom In", "Q" }, { "Zoom Out", "E" }, { "Reset Zoom", "R" },
	{ "Roll Left", "Z" }, { "Roll Right", "C" },
	{ "Freeze Time & Scene", "F1" }, { "Freeze Time", "F5" }, { "Skip Frame", "F2" },
	{ "Freeze Camera", "G" }, { "Hide UI", "Delete" }, { "2x Quality", "-" },
	{ "CModifier", "LShift" }, { "CModifier3", "LAlt" },
}
for _, a in ipairs(ACTIONS) do keys.define(a[1], a[2]) end

-- Estado
C.req = {}                -- pedidos do HUD (toggle_freecam, freeze_all, freeze_cam, hide_ui...)
C.stick = { deadzone = 0.12, curve = 1.8, sens = 1.0 }
C.move_stick = true
C.block_mouse = false
C.pending_roll = nil
C.reset_roll = nil
C.on = false
C.hide_ui = false
C.cam_frozen = false
C.clean = false

-- ---------------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------------
local function scene()
	return sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
end

local function getC(go, type_name)
	if not go then return nil end
	local t = sdk.typeof(type_name)
	if not t then return nil end
	local ok, c = pcall(go.call, go, "getComponent(System.Type)", t)
	return ok and c or nil
end

local function find_all(type_name)
	local out = {}
	pcall(function()
		local arr = scene():call("findComponents(System.Type)", sdk.typeof(type_name))
		for _, c in ipairs(arr and arr:get_elements() or {}) do table.insert(out, c) end
	end)
	return out
end

local app_td = sdk.find_type_definition("via.Application")
local function app_call(m, ...)
	return sdk.call_native_func(sdk.get_native_singleton("via.Application"), app_td, m, ...)
end
local function global_speed()
	local ok, s = pcall(app_call, "get_GlobalSpeed")
	return ok and s or 1.0
end

local renderer_td = sdk.find_type_definition("via.render.Renderer")
local function renderer_call(m, ...)
	return sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), renderer_td, m, ...)
end

local function addr(o) local ok, a = pcall(o.get_address, o); return ok and a or tostring(o) end

local function tip(text) if imgui.is_item_hovered() then imgui.set_tooltip(text) end end
local MUTED = 0xFF805E68

function C.pull()
	local r = C.req
	C.req = {}
	return r
end

-- recurso com "Holder" (texturas, LUTs)
function C.create_resource(resource_type, path)
	local res = path and sdk.create_resource(resource_type, path)
	if not res then return nil end
	res = res:add_ref()
	local holder = sdk.create_instance(resource_type .. "Holder", true)
	if not holder then return nil end
	holder = holder:add_ref()
	holder:call(".ctor()")
	holder:write_qword(0x10, res:get_address())
	return holder
end

-- ---------------------------------------------------------------------------
-- Quaternions (Quaternion.new(w, x, y, z))
-- ---------------------------------------------------------------------------
local function axis_quat(x, y, z, a)
	local s = math.sin(a * 0.5)
	return Quaternion.new(math.cos(a * 0.5), x * s, y * s, z * s)
end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

-- yaw (Y), pitch (X), roll (Z local)
local function cam_quat(yaw, pitch, roll)
	return (axis_quat(0, 1, 0, yaw) * axis_quat(1, 0, 0, pitch) * axis_quat(0, 0, 1, roll)):normalized()
end

local function quat_to_ypr(q)
	local f = q * Vector3f.new(0, 0, -1)
	local yaw = math.atan(-f.x, -f.z)
	local pitch = math.asin(math.max(-1, math.min(1, f.y)))
	local base = axis_quat(0, 1, 0, yaw) * axis_quat(1, 0, 0, pitch)
	local up = q * Vector3f.new(0, 1, 0)
	local up0 = base * Vector3f.new(0, 1, 0)
	local right0 = base * Vector3f.new(1, 0, 0)
	local roll = math.atan(-dot(up, right0), dot(up, up0))
	return yaw, pitch, roll
end

-- analógico: zona morta radial + curva
function C.shape_stick(v)
	if not v then return nil end
	local st = C.stick
	local m = math.sqrt(v.x * v.x + v.y * v.y)
	if m <= st.deadzone then return Vector2f.new(0, 0) end
	local n = math.min(1.0, (m - st.deadzone) / (1.0 - st.deadzone))
	n = (n ^ st.curve) * st.sens
	return Vector2f.new(v.x / m * n, v.y / m * n)
end
function C.left_stick() return C.shape_stick(keys.axis_l()) end

-- ---------------------------------------------------------------------------
-- Câmera
-- ---------------------------------------------------------------------------
local cam = { yaw = 0, pitch = 0, roll = 0, pos = nil, last_t = nil, last_mouse = nil, fov = nil, behaviors = {} }

local function cam_objects()
	local c = sdk.get_primary_camera()
	if not c then return nil end
	local go = c:call("get_GameObject")
	local xf = go and go:call("get_Transform")
	if not xf then return nil end
	local j = xf:call("getJointByName", "Camera")
	return c, go, xf, j
end

local function cam_get()
	local c, go, xf, j = cam_objects()
	if not c then return nil end
	local t = j or xf
	return t:call("get_Position"), t:call("get_Rotation"), c
end

local function cam_set(pos, rot)
	local c, go, xf, j = cam_objects()
	if not c then return end
	local t = j or xf
	pcall(function()
		t:call("set_Position", pos)
		t:call("set_Rotation", rot)
	end)
end

-- desliga a câmera da luta enquanto a câmera livre está ligada
local function hold_behaviors(on)
	if on then
		for _, b in ipairs(find_all("app.CameraBehavior")) do
			local ok, en = pcall(b.call, b, "get_Enabled")
			if ok and en then
				pcall(b.call, b, "set_Enabled", false)
				cam.behaviors[addr(b)] = b
			end
		end
	else
		for _, b in pairs(cam.behaviors) do pcall(b.call, b, "set_Enabled", true) end
		cam.behaviors = {}
	end
end

local function freecam_start()
	local pos, rot, cc = cam_get()
	if not pos then return false end
	-- v2.6.14: guarda a câmera do jogo para devolver ao sair (em CA/intro com o
	-- jogo pausado ninguém reescreve a câmera, e ela ficava presa no zoom/posição)
	cam.orig = { pos = pos, rot = rot }
	pcall(function() cam.orig.fov = cc:call("get_FOV") end)
	cam.pos = pos
	cam.yaw, cam.pitch, cam.roll = quat_to_ypr(rot)
	cam.last_t, cam.last_mouse = nil, nil
	C.on = true
	return true
end

local function freecam_stop()
	C.on = false
	hold_behaviors(false)
	cam.fov = nil
	local o = cam.orig
	cam.orig = nil
	if o then
		cam_set(o.pos, o.rot)
		if o.fov then
			local cc = sdk.get_primary_camera()
			if cc then pcall(cc.call, cc, "set_FOV", o.fov) end
		end
	end
end

-- prévia vertical (estado; a lógica fica mais abaixo)
C.vpreview = false
local vp = { base = nil }

function C.get_fov()
	if cam.fov then return cam.fov end
	if C.vpreview and vp.base then return vp.base end
	local c = sdk.get_primary_camera()
	local ok, v = pcall(function() return c:call("get_FOV") end)
	return ok and v or nil
end
function C.set_fov(v) cam.fov = v end
function C.reset_fov() cam.fov = nil end
function C.is_cam_frozen() return C.cam_frozen end

-- uma passada da câmera livre (entrada + aplicação)
local function freecam_update()
	if not C.on or not cam.pos then return end
	local now = os.clock()
	local dt = cam.last_t and math.min(0.1, now - cam.last_t) or 0
	cam.last_t = now

	local fast = keys.down("CModifier") and 3.0 or (keys.down("CModifier3") and 0.33 or 1.0)
	local s = C.settings

	if not C.cam_frozen then
		-- rotação: mouse
		local mp = keys.mouse_pos()
		if mp and cam.last_mouse and not C.block_mouse then
			local dx, dy = mp.x - cam.last_mouse.x, mp.y - cam.last_mouse.y
			if math.abs(dx) < 300 and math.abs(dy) < 300 then
				local k = 0.0025 * s.rot_speed * (fast == 1.0 and 1.0 or (fast > 1 and 1.6 or 0.4))
				cam.yaw = cam.yaw - dx * k
				cam.pitch = cam.pitch - dy * k
			end
		end
		cam.last_mouse = mp
		-- rotação: analógico direito
		local r = C.shape_stick(keys.axis_r())
		if r then
			local ry = s.invert_pad and -r.y or r.y
			cam.yaw = cam.yaw - r.x * 1.8 * s.rot_speed * dt
			cam.pitch = cam.pitch + ry * 1.4 * s.rot_speed * dt
		end
		local lim = math.rad(89)
		cam.pitch = math.max(-lim, math.min(lim, cam.pitch))

		-- inclinação
		if keys.down("Roll Left") then cam.roll = cam.roll - math.rad(40) * fast * dt end
		if keys.down("Roll Right") then cam.roll = cam.roll + math.rad(40) * fast * dt end
		if C.pending_roll then cam.roll = cam.roll + C.pending_roll; C.pending_roll = nil end
		if C.reset_roll then cam.roll = 0; C.reset_roll = nil end

		-- movimento
		local q = cam_quat(cam.yaw, cam.pitch, cam.roll)
		local fwd = q * Vector3f.new(0, 0, -1)
		local right = q * Vector3f.new(1, 0, 0)
		local mx, my, mz = 0, 0, 0
		if keys.down("Cam Forward") then mz = mz + 1 end
		if keys.down("Cam Backward") then mz = mz - 1 end
		if keys.down("Cam Right") then mx = mx + 1 end
		if keys.down("Cam Left") then mx = mx - 1 end
		if keys.down("Cam Up") then my = my + 1 end
		if keys.down("Cam Down") then my = my - 1 end
		if C.move_stick then
			local l = C.left_stick()
			if l then mx = mx + l.x; mz = mz + l.y end
		end
		if mx ~= 0 or my ~= 0 or mz ~= 0 then
			local v = s.move_speed * fast * dt
			cam.pos = cam.pos + fwd * (mz * v) + right * (mx * v) + Vector3f.new(0, my * v, 0)
		end

		-- zoom (FOV)
		local zin, zout = keys.down("Zoom In"), keys.down("Zoom Out")
		if zin or zout then
			local f = cam.fov or C.get_fov() or 45
			f = f + (zout and 1 or -1) * 25 * fast * dt
			cam.fov = math.max(3, math.min(130, f))
		end
	else
		C.pending_roll, C.reset_roll = nil, nil
		cam.last_mouse = keys.mouse_pos()
	end
end

-- Prévia vertical: com a câmera deitada 90° (foto vertical), desfaz o giro só
-- na tela e abre o FOV para que a faixa 9:16 do meio mostre exatamente a foto,
-- já em pé. A foto em si continua deitada (o giro volta ao desligar).
local function game_fov()
	local c = sdk.get_primary_camera()
	local ok, v = pcall(function() return c:call("get_FOV") end)
	return ok and v or nil
end
function C.set_vpreview(on)
	if on == C.vpreview then return end
	if on then
		vp.base = cam.fov or game_fov()
	elseif not cam.fov and vp.base then
		local c = sdk.get_primary_camera()
		if c then pcall(c.call, c, "set_FOV", vp.base) end
	end
	C.vpreview = on
end

local function freecam_apply()
	if not C.on or not cam.pos then return end
	local roll = cam.roll
	if C.vpreview then
		local q = math.rad(90)
		if math.abs(roll) < 1e-3 then
			roll = C.vp_flip and q or -q   -- câmera reta: gira a imagem 16:9 inteira
		else
			roll = roll - ((roll >= 0) and q or -q)
		end
	end
	cam_set(cam.pos, cam_quat(cam.yaw, cam.pitch, roll))
end

local function fov_apply()
	local f = cam.fov
	if C.vpreview then
		local base = cam.fov or vp.base
		if base then
			local d = imgui.get_display_size()
			local aspect = (d and d.y > 0) and (d.x / d.y) or (16 / 9)
			f = math.deg(2 * math.atan(math.tan(math.rad(base) * 0.5) * aspect))
		end
	end
	if not f then return end
	local c = sdk.get_primary_camera()
	if c then pcall(c.call, c, "set_FOV", f) end
end

-- v2.5.7: preview vertical SEM o Modo Foto (câmera do jogo/menu).
-- Gira a câmera do jogo 90° em volta do eixo da visão, só enquanto o preview está
-- ligado, para a imagem 16:9 aparecer em pé. A rotação original volta ao desligar.
C.vp_flip = false
local vr = { base = nil, last = nil }
local function q_same(a, b)
	if not a or not b then return false end
	return math.abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z) > 0.999999
end
local function vp_game_rotate()
	local c, go, xf, j = cam_objects()
	if not c then return end
	local t = j or xf
	if not C.vpreview or C.on then
		-- desligado (ou o Modo Foto assumiu): devolve a rotação original
		if vr.base then
			pcall(function()
				if q_same(t:call("get_Rotation"), vr.last) then t:call("set_Rotation", vr.base) end
			end)
			vr.base, vr.last = nil, nil
		end
		return
	end
	pcall(function()
		local cur = t:call("get_Rotation")
		-- se o jogo não reescreveu a câmera neste frame, usa a base guardada (não acumula)
		local base = (vr.last and q_same(cur, vr.last) and vr.base) or cur
		local a = math.rad(C.vp_flip and -90 or 90) * 0.5
		local rz = Quaternion.new(math.cos(a), 0, 0, math.sin(a))
		local r = (base * rz):normalized()
		t:call("set_Rotation", r)
		vr.base, vr.last = base, r
	end)
end

re.on_application_entry("PrepareRendering", function()
	if C.on then
		hold_behaviors(true)
		freecam_update()
		freecam_apply()
	end
	pcall(vp_game_rotate)
	fov_apply()
end)
re.on_pre_application_entry("BeginRendering", function()
	freecam_apply()
	pcall(vp_game_rotate)
	fov_apply()
end)

function C.toggle()
	if C.on then freecam_stop() else freecam_start() end
end

-- posição/rotação atual da câmera (para luzes)
function C.cam_pos_rot()
	local p, r = cam_get()
	return p, r
end

-- ---------------------------------------------------------------------------
-- Pausa
-- ---------------------------------------------------------------------------
local battle = { flow = nil, t = -10 }
local function battleflow()
	if os.clock() - battle.t > 1.0 or not battle.flow then
		battle.t = os.clock()
		local list = find_all("app.battle.bBattleFlow")
		battle.flow = list[1]
	end
	return battle.flow
end

function C.is_scene_frozen() return global_speed() < 0.001 end
function C.is_battle_frozen()
	local bf = battleflow()
	if not bf then return false end
	local ok, en = pcall(bf.call, bf, "get_Enabled")
	return ok and en == false
end

local skip = nil  -- avança 1 frame: { speed = velocidade anterior }

local function set_speed(v) pcall(app_call, "set_GlobalSpeed", v) end

local function toggle_freeze_all()
	local frozen = C.is_scene_frozen()
	set_speed(frozen and 1.0 or 0.00001)
	local bf = battleflow()
	if bf then pcall(bf.call, bf, "set_Enabled", frozen) end
end

local function toggle_freeze_battle()
	local bf = battleflow()
	if not bf then return end
	local ok, en = pcall(bf.call, bf, "get_Enabled")
	if ok then pcall(bf.call, bf, "set_Enabled", not en) end
end

local function skip_frame()
	local bf = battleflow()
	skip = { speed = C.is_scene_frozen(), battle = C.is_battle_frozen() }
	if skip.speed then set_speed(1.0) end
	if skip.battle and bf then pcall(bf.call, bf, "set_Enabled", true) end
end

-- volta a pausar no fim do frame seguinte (depois de animação e física)
re.on_application_entry("PrepareRendering", function()
	if not skip then return end
	local s = skip
	skip = nil
	if s.speed then set_speed(0.00001) end
	local bf = battleflow()
	if s.battle and bf then pcall(bf.call, bf, "set_Enabled", false) end
end)

-- ---------------------------------------------------------------------------
-- Hide UI (UI do jogo)
-- ---------------------------------------------------------------------------
re.on_pre_gui_draw_element(function(element, context)
	if C.hide_ui then return false end
	return true
end)

-- ---------------------------------------------------------------------------
-- 2x Quality
-- ---------------------------------------------------------------------------
local hq = { on = false, base = nil, upscale = nil }
function C.get_hi_quality() return hq.on end
function C.set_hi_quality(on)
	pcall(function()
		if hq.base == nil then hq.base = renderer_call("get_ImageQualityRate") or 1.0 end
		local rc = renderer_call("get_RenderConfig")
		if rc and hq.upscale == nil then hq.upscale = rc:call("get_UpscaleType") end
		renderer_call("set_ImageQualityRate", on and hq.base * 2.0 or hq.base)
		if rc and hq.upscale ~= nil then rc:call("set_UpscaleType", on and 0 or hq.upscale) end
	end)
	hq.on = on
end

-- ---------------------------------------------------------------------------
-- Disable Lights (luzes do cenário)
-- ---------------------------------------------------------------------------
local dl = { on = false, saved = {}, t = -10 }
local function is_our_light(go)
	local ok, n = pcall(go.call, go, "get_Name")
	return ok and n and n:find("^NASK") ~= nil
end
local function lights_pass()
	for _, tn in ipairs({ "via.render.Light", "via.render.LightProbes" }) do
		for _, l in ipairs(find_all(tn)) do
			pcall(function()
				local go = l:call("get_GameObject")
				if is_our_light(go) then return end
				local k = addr(l)
				if dl.on then
					-- luz e objeto guardados à parte: um objeto pode ter várias luzes, e a
					-- 2ª luz via o objeto já escondido pela 1ª (e devolvia "escondido")
					if dl.saved[k] == nil then dl.saved[k] = { c = l, en = l:call("get_Enabled") } end
					dl.gos = dl.gos or {}
					local gk = addr(go)
					if dl.gos[gk] == nil then dl.gos[gk] = { go = go, draw = go:call("get_DrawSelf") } end
					if l:call("get_Enabled") then l:call("set_Enabled", false) end
					if go:call("get_DrawSelf") then go:call("set_DrawSelf", false) end
				end
			end)
		end
	end
end
function C.get_disable_lights() return dl.on end
function C.set_disable_lights(on)
	dl.on = on
	if on then
		lights_pass()
	else
		for _, g in pairs(dl.gos or {}) do pcall(g.go.call, g.go, "set_DrawSelf", g.draw ~= false) end
		for _, s in pairs(dl.saved) do
			pcall(function()
				s.c:call("set_Enabled", s.en ~= false)
				pcall(s.c.call, s.c, "update")
			end)
		end
		dl.saved, dl.gos = {}, {}
	end
end

-- ---------------------------------------------------------------------------
-- Componentes visuais da câmera
-- ---------------------------------------------------------------------------
-- objeto que tem os efeitos de tela: normalmente a câmera principal; se ela não
-- tiver nenhum (alguns menus/cenas usam outra câmera), procura na cena o objeto
-- que tem os componentes de pós-processamento
local fx_go = { go = nil, t = -10, from = nil }
local function fx_object()
	local c = sdk.get_primary_camera()
	local go = c and c:call("get_GameObject")
	if go and (getC(go, "via.render.ToneMapping") or getC(go, "via.render.DepthOfField") or getC(go, "via.render.LDRPostProcess")) then
		fx_go.from = "câmera principal"
		return go
	end
	if os.clock() - fx_go.t > 1.0 then
		fx_go.t = os.clock()
		fx_go.go = nil
		for _, tn in ipairs({ "via.render.ToneMapping", "via.render.DepthOfField", "via.render.LDRPostProcess" }) do
			for _, comp in ipairs(find_all(tn)) do
				local ok, g = pcall(comp.call, comp, "get_GameObject")
				if ok and g then fx_go.go = g; break end
			end
			if fx_go.go then break end
		end
	end
	fx_go.from = fx_go.go and "outra câmera da cena" or nil
	return fx_go.go or go
end
C.fx_from = function() return fx_go.from end

local function cam_comps()
	local go = fx_object()
	if not go then return {} end
	local ldr = getC(go, "via.render.LDRPostProcess")
	local cc
	if ldr then pcall(function() cc = ldr:call("get_ColorCorrect") end) end
	return {
		go = go, ldr = ldr, cc = cc,
		dof = getC(go, "via.render.DepthOfField"),
		ssao = getC(go, "via.render.SSAOControl"),
		bloom = getC(go, "via.render.SoftBloom"),
		tonemap = getC(go, "via.render.ToneMapping"),
		filter = getC(go, "via.render.CustomFilter") or getC(go, "via.render.CustomFilterBeforeTransparent"),
		vol = getC(go, "via.render.VolumetricFogControl"),
		fog = getC(go, "via.render.Fog"),
		output = getC(go, "via.render.RenderOutput"),
		rt = getC(go, "via.render.ExperimentalRayTrace"),
	}
end

-- v2.6.0: distorção de lente desligada na câmera livre
-- O SF6 usa distorção de lente (LensDistortion) na câmera da luta. Com a câmera livre
-- perto dos personagens/cenário isso estica e entorta a imagem. Enquanto o Modo Foto
-- estiver ligado, a distorção fica desligada; ao sair, volta como estava.
C.no_distort = true
local dist_saved = {}
local dist_logged = false
local function distort_targets()
	local out = {}
	local cc = cam_comps()
	if cc.ldr then
		for _, m in ipairs({ "get_LensDistortion", "get_LensDistortionParam" }) do
			local ok, ld = pcall(cc.ldr.call, cc.ldr, m)
			if ok and ld then table.insert(out, ld) end
		end
	end
	if cc.go then
		for _, tn in ipairs({ "via.render.LensDistortion", "via.render.PaniniProjection" }) do
			local x = getC(cc.go, tn)
			if x then table.insert(out, x) end
		end
	end
	return out
end
local function distort_enforce()
	local want_off = C.on and C.no_distort
	if not want_off then
		if next(dist_saved) then
			for _, t in pairs(dist_saved) do pcall(t.call, t, "set_Enabled", true) end
			dist_saved = {}
		end
		return
	end
	for _, t in ipairs(distort_targets()) do
		local ok, en = pcall(t.call, t, "get_Enabled")
		if ok and en then
			pcall(t.call, t, "set_Enabled", false)
			dist_saved[tostring(t:get_address())] = t
			if not dist_logged then
				dist_logged = true
				pcall(log.info, "[NASK] distorção de lente desligada: " .. t:get_type_definition():get_full_name())
			end
		end
	end
end
re.on_application_entry("PrepareRendering", function() pcall(distort_enforce) end)
re.on_pre_application_entry("BeginRendering", function() pcall(distort_enforce) end)

-- Efeitos do VS Walk (LDRPostProcess)
local ldr_forced = false
function C.apply_ldr(off)
	local c = cam_comps()
	if not c.ldr then return end
	if off then
		if c.ldr:call("get_Enabled") then c.ldr:call("set_Enabled", false) end
		ldr_forced = true
	elseif ldr_forced then
		c.ldr:call("set_Enabled", true)
		ldr_forced = false
	end
end

-- DOF: descobre os setters do jogo e os valores reais do enum de tipo
local DOF_NAMES = { "Default", "Tessellation", "Lite", "Circular" }
local dof_info
function C.dof_info()
	if dof_info then return dof_info end
	local info = { values = {}, names = {} }
	pcall(function()
		local td = sdk.find_type_definition("via.render.DepthOfField")
		for _, m in ipairs(td:get_methods()) do
			local name = m:get_name()
			local l = name:lower()
			local np = m:get_num_params()
			if np == 1 and l:sub(1, 3) == "set" then
				local pt = m:get_param_types()[1]
				local ptn = pt and pt:get_full_name() or ""
				if l == "set_depthoffieldtype" or l == "setdepthoffieldtype" then info.type_setter, info.type_t = name, pt end
				if l:find("hdmode") or l:find("highdefinition") then info.hd, info.hd_bool = name, (ptn == "System.Boolean") end
				if l:find("sharpbokehintensitythreshold") then info.sharp = name end
				-- v2.6.3: qualidade/resolução do desfoque (o DOF ficava granulado)
				if l:find("quality") or l:find("resolution") or l:find("halfres") or l:find("fullres")
					or l:find("samplecount") or l:find("samplenum") or l:find("jitter") or l:find("noise") or l:find("lowres") then
					info.q = info.q or {}
					table.insert(info.q, { name = name, l = l, ptn = ptn, pt = pt })
				end
			elseif np == 0 and (l == "get_depthoffieldtype" or l == "getdepthoffieldtype") then
				info.type_getter = name
			end
		end
		-- valores do enum pelo NOME (não depende da ordem)
		local et = info.type_t or sdk.find_type_definition("via.render.DepthOfField.DepthOfFieldType")
			or sdk.find_type_definition("via.render.DepthOfFieldType")
		if et then
			for _, f in ipairs(et:get_fields()) do
				if f:is_static() then
					local ok, v = pcall(f.get_data, f, nil)
					local fl = f:get_name():lower()
					if ok and type(v) == "number" then
						info.names[v] = f:get_name()
						if fl:find("tess") then info.values[2] = v
						elseif fl:find("lite") then info.values[3] = v
						elseif fl:find("circ") then info.values[4] = v
						elseif fl:find("default") or fl:find("standard") or fl:find("normal") then info.values[1] = v end
					end
				end
			end
		end
	end)
	for i = 1, 4 do if info.values[i] == nil then info.values[i] = i - 1 end end
	dof_info = info
	return info
end

local function dof_want()
	return C.dof_info().values[C.settings.dof_type or 2]
end

local function dof_get_type(dof)
	local info = C.dof_info()
	local ok, v = pcall(dof.call, dof, info.type_getter or "get_DepthOfFieldType")
	if ok and v ~= nil then return v end
	return nil
end

local function dof_set_type(dof)
	local info = C.dof_info()
	local want = dof_want()
	if not pcall(dof.call, dof, info.type_setter or "set_DepthOfFieldType", want) then
		pcall(dof.call, dof, "setDepthOfFieldType", want)
	end
end

local sharp_default = nil
local function dof_extras(dof)
	local info = C.dof_info()
	local s = C.settings
	dof_set_type(dof)
	pcall(function()
		local q = s.dof_quality or 2
		if info.hd then
			local on = q <= 2
			if info.hd_bool then dof:call(info.hd, on) else dof:call(info.hd, on and 1 or 0) end
		end
		if info.sharp then
			if sharp_default == nil then
				local ok, v = pcall(dof.call, dof, (info.sharp:gsub("^set", "get")))
				if ok and type(v) == "number" and v > 0 then sharp_default = v end
			end
			if q == 1 then dof:call(info.sharp, 0.0) elseif sharp_default then dof:call(info.sharp, sharp_default) end
		end
	end)
	if (s.dof_quality or 2) <= 2 then pcall(C.dof_hq, dof, info) end
end

-- qualidade máxima nos campos que existirem: resolução cheia, mais amostras, sem
-- ruído/jitter (o ruído é o "granulado"). Só mexe no que o tipo do campo permite.
local dof_hq_logged = false
function C.dof_hq(dof, info)
	local done = {}
	for _, f in ipairs(info.q or {}) do
		pcall(function()
			local l, ptn = f.l, f.ptn
			if ptn == "System.Boolean" then
				local v
				if l:find("halfres") or l:find("lowres") or l:find("jitter") or l:find("noise") then v = false
				elseif l:find("fullres") or l:find("quality") then v = true end
				if v ~= nil then dof:call(f.name, v); table.insert(done, f.name .. "=" .. tostring(v)) end
			elseif f.pt and f.pt:is_value_type() and ptn ~= "System.Single" and ptn ~= "System.Double" and ptn:find("^System%.") == nil then
				-- enum: escolhe o valor de nome mais alto (High/Full/Max/Ultra/Best)
				local best, rank = nil, -1
				local order = { low = 0, half = 0, quarter = 0, medium = 1, middle = 1, normal = 1, default = 1, high = 2, full = 3, max = 4, ultra = 4, best = 4, highest = 4 }
				for _, fl in ipairs(f.pt:get_fields()) do
					if fl:is_static() then
						local ok, v = pcall(fl.get_data, fl, nil)
						local nm = fl:get_name():lower()
						if ok and type(v) == "number" then
							for key, r in pairs(order) do
								if nm:find(key, 1, true) and r > rank then best, rank = v, r end
							end
						end
					end
				end
				if best ~= nil and not (l:find("jitter") or l:find("noise")) then dof:call(f.name, best); table.insert(done, f.name .. "=" .. tostring(best)) end
			elseif ptn == "System.Int32" or ptn == "System.UInt32" then
				if l:find("samplecount") or l:find("samplenum") then dof:call(f.name, 64); table.insert(done, f.name .. "=64")
				elseif l:find("quality") then
					local ok, cur = pcall(dof.call, dof, (f.name:gsub("^set", "get")))
					if ok and type(cur) == "number" and cur < 3 then dof:call(f.name, 3); table.insert(done, f.name .. "=3") end
				end
			end
		end)
	end
	if not dof_hq_logged then
		dof_hq_logged = true
		local names = {}
		for _, f in ipairs(info.q or {}) do table.insert(names, f.name .. "(" .. f.ptn .. ")") end
		pcall(log.info, "[NASK] DOF campos de qualidade: " .. (#names > 0 and table.concat(names, ", ") or "nenhum") .. " | aplicado: " .. table.concat(done, ", "))
	end
end

-- todas as DOF da câmera (algumas câmeras têm mais de uma)
local function cam_dofs()
	local out = {}
	pcall(function()
		local go = sdk.get_primary_camera():call("get_GameObject")
		local arr = go:call("get_Components")
		for _, c in ipairs(arr and arr:get_elements() or {}) do
			local ok, n = pcall(function() return c:get_type_definition():get_full_name() end)
			if ok and n == "via.render.DepthOfField" then table.insert(out, c) end
		end
	end)
	if #out == 0 then
		local d = cam_comps().dof
		if d then out[1] = d end
	end
	return out
end

-- o jogo volta o tipo para o padrão ao trocar/atualizar a câmera: reaplica
-- logo antes de renderizar, todo frame em que estiver diferente
local dof_last = { t = -1, list = {} }
local function dof_enforce()
	if C.settings.dof_apply == false then return end
	local now = os.clock()
	if now - dof_last.t > 0.5 then dof_last.t = now; dof_last.list = cam_dofs() end
	local want = dof_want()
	for _, dof in ipairs(dof_last.list) do
		local ok, en = pcall(dof.call, dof, "get_Enabled")
		if ok and en then
			local cur = dof_get_type(dof)
			if cur ~= want then dof_extras(dof) end
		end
	end
end
function C.dof_tick() pcall(dof_enforce) end
re.on_application_entry("PrepareRendering", function() pcall(dof_enforce) end)
re.on_pre_application_entry("BeginRendering", function() pcall(dof_enforce) end)

-- tipo atual no jogo (para mostrar no HUD)
function C.dof_current_name()
	local dof = cam_comps().dof
	if not dof then return nil end
	local v = dof_get_type(dof)
	if v == nil then return "?" end
	local info = C.dof_info()
	return (info.names[v] or tostring(v))
end

-- Só o que o usuário mexeu é forçado (o jogo reativa coisas ao trocar de câmera)
local us = {}
local function force_user(c)
	pcall(function()
		if c.dof then
			if us.dof ~= nil then c.dof:call("set_Enabled", us.dof) end
			if c.dof:call("get_Enabled") then
				if us.sensor then c.dof:call("set_SensorSize", us.sensor) end
				if us.focus then c.dof:call("set_FocusDistance", us.focus) end
				if us.fnum then c.dof:call("set_FNumber", us.fnum) end
				if us.fixfov ~= nil then c.dof:call("set_EnableFixFOV", us.fixfov) end
				if us.fov then c.dof:call("set_FOV", us.fov) end
			end
		end
		if c.ssao and us.ssao ~= nil then c.ssao:call("set_Enabled", us.ssao) end
		if c.ssao and us.tssao ~= nil then c.ssao:call("setSSAOAlgorithm", us.tssao and 1 or 0) end
		if c.bloom and us.bloom ~= nil then c.bloom:call("set_Enabled", us.bloom) end
		if c.filter and us.filter ~= nil and (not C.clean or clean_free.filter) then c.filter:call("set_Enabled", us.filter) end
		if c.tonemap and us.vig ~= nil and (not C.clean or clean_free.vig) then c.tonemap:call("setVignetting", us.vig and 0 or 2) end
		if c.cc and us.cc ~= nil and (not C.clean or clean_free.cc) then c.cc:call("set_Enabled", us.cc) end
		if c.vol and us.vol ~= nil then c.vol:call("set_Enabled", us.vol) end
	end)
end

-- DOF no preview vertical (v2.5.6)
-- Abrir o FOV para o preview em pé mudaria o desfoque do DOF (ele deriva da FOV da
-- câmera). Enquanto o preview está ligado, a FOV que o DOF usa é fixada num valor que
-- dá o MESMO desfoque da foto de verdade (câmera deitada, FOV original):
--   o preview em pé mostra a largura da foto na altura da tela, e o desfoque do DOF
--   cresce com o quadrado da distância focal, então tan(F/2) = sqrt(aspecto) * tan(base/2).
-- Ao desligar (ou na hora da foto) os valores originais do DOF voltam exatamente.
local vpd = { saved = {}, list = {}, t = -1 }
local function vp_dof_restore()
	for k, s in pairs(vpd.saved) do
		pcall(function()
			s.dof:call("set_EnableFixFOV", s.fix)
			if s.fov then s.dof:call("set_FOV", s.fov) end
		end)
	end
	vpd.saved = {}
end
local function vp_dof_apply()
	if not C.vpreview then
		if next(vpd.saved) then vp_dof_restore() end
		return
	end
	-- se o usuário fixou FOV/EnableFixFOV do DOF por conta própria, respeita
	if us.fixfov ~= nil or us.fov then return end
	local base = cam.fov or vp.base
	if not base then return end
	local d = imgui.get_display_size()
	local aspect = (d and d.y > 0) and (d.x / d.y) or (16 / 9)
	local f = math.deg(2 * math.atan(math.sqrt(aspect) * math.tan(math.rad(base) * 0.5)))
	local now = os.clock()
	if now - vpd.t > 0.5 then vpd.t = now; vpd.list = cam_dofs() end
	for _, dof in ipairs(vpd.list) do
		pcall(function()
			local k = tostring(dof:get_address())
			if not vpd.saved[k] then
				local ok1, fix = pcall(dof.call, dof, "get_EnableFixFOV")
				local ok2, fv = pcall(dof.call, dof, "get_FOV")
				vpd.saved[k] = { dof = dof, fix = (ok1 and fix) or false, fov = ok2 and fv or nil }
			end
			dof:call("set_EnableFixFOV", true)
			dof:call("set_FOV", f)
		end)
	end
end
re.on_application_entry("PrepareRendering", function() pcall(vp_dof_apply) end)
re.on_pre_application_entry("BeginRendering", function() pcall(vp_dof_apply) end)

-- Greenscreen
local gs = { on = false, color = Vector3f.new(0, 1, 0) }
local function gs_apply(c)
	pcall(function()
		if c.output then c.output:call("set_RenderOutputID", 2) end
		if c.fog then
			c.fog:call("set_Enabled", true)
			c.fog:call("set_Intensity", 100.0)
			c.fog:call("set_HeightFalloff", 0.0)
			c.fog:call("set_InscatteringColor", gs.color)
		end
	end)
end
local function gs_off(c)
	pcall(function()
		if c.output then c.output:call("set_RenderOutputID", 1) end
		if c.fog then c.fog:call("set_Enabled", false) end
	end)
end

function C.user_tick()
	local c = cam_comps()
	if next(us) then force_user(c) end
	if gs.on then
		gs_apply(c)
		if C.gs_stage and os.clock() - (gs.st_t or 0) > 1.0 then gs.st_t = os.clock(); pcall(C.gs_stage, true) end
	end
	if dl.on and os.clock() - dl.t > 1.0 then dl.t = os.clock(); lights_pass() end
end
function C.reset_user() us = {} end

-- Limpar imagem: LUT, Vignette e Color Correction desligados
local clean_saved = nil
function C.set_clean(on)
	local c = cam_comps()
	if on and not C.clean then
		clean_saved = {}
		pcall(function()
			if c.filter then clean_saved.filter = c.filter:call("get_Enabled") end
			if c.tonemap then clean_saved.vig = c.tonemap:call("getVignetting") end
			if c.cc then clean_saved.cc = c.cc:call("get_Enabled") end
		end)
	elseif not on and C.clean and clean_saved then
		pcall(function()
			if c.filter and clean_saved.filter ~= nil then c.filter:call("set_Enabled", clean_saved.filter) end
			if c.tonemap and clean_saved.vig ~= nil then c.tonemap:call("setVignetting", clean_saved.vig) end
			if c.cc and clean_saved.cc ~= nil then c.cc:call("set_Enabled", clean_saved.cc) end
		end)
		clean_saved = nil
	end
	C.clean = on
	clean_free = {}
	C.clean_tick()
end
function C.clean_tick()
	if not C.clean then return end
	local c = cam_comps()
	pcall(function()
		if c.filter and not clean_free.filter and c.filter:call("get_Enabled") then c.filter:call("set_Enabled", false) end
		if c.tonemap and not clean_free.vig and c.tonemap:call("getVignetting") ~= 2 then c.tonemap:call("setVignetting", 2) end
		if c.cc and not clean_free.cc and c.cc:call("get_Enabled") then c.cc:call("set_Enabled", false) end
	end)
end

-- caixa de seleção que grava a escolha do usuário em "us"
local clean_free = {}   -- efeitos que o usuário mexeu com o "Limpar imagem" ligado
local function toggle(label, key, get, set)
	local ok, cur = pcall(get)
	cur = ok and cur == true
	local ch, v = imgui.checkbox(label, cur)
	if ch then
		us[key] = v
		if C.clean then clean_free[key] = true end
		pcall(set, v)
	end
	return v, ch
end

-- Visual Settings ------------------------------------------------------------
local lut_names, lut_idx = nil, nil
function C.ui_visual()
	local c = cam_comps()
	if not c.go then imgui.text("Câmera não encontrada.") return end
	local s = C.settings
	local changed, v
	if not (c.dof or c.ssao or c.bloom or c.filter or c.tonemap or c.cc or c.vol) then
		local ok, n = pcall(function() return c.go:call("get_Name") end)
		imgui.text_colored("Nenhum efeito visual encontrado na câmera atual (" .. tostring(ok and n or "?") .. ").\nNos menus o jogo usa uma câmera sem efeitos; entre numa luta ou no treino.", MUTED)
		return
	end

	-- DOF
	if c.dof then
		local dof = c.dof
		local on = toggle("DOF (profundidade de campo)", "dof",
			function() return dof:call("get_Enabled") end,
			function(x) dof:call("set_Enabled", x); if x then dof_extras(dof) end end)
		if on then
			imgui.indent(12)
			if C.fresh("dof_t") then pcall(imgui.set_next_item_open, false, 1) end
			if imgui.tree_node("Tipo do DOF##dof_t") then
				changed, s.dof_type = imgui.combo("Tipo", s.dof_type or 2, { "Default", "Tessellation", "Lite", "Circular" })
				if changed then s.dof_apply = true; dof_extras(dof); C.save() end
				tip("DepthOfFieldType (Tessellation = bokeh de melhor qualidade)")
				local cur = C.dof_current_name()
				if cur then imgui.text_colored("No jogo agora: " .. cur, MUTED) end
				changed, s.dof_quality = imgui.combo("Qualidade do bokeh", s.dof_quality or 2, { "Máxima (pesada)", "Alta", "Leve" })
				if changed then dof_extras(dof); C.save() end
				tip("Máxima: HD Mode + todo brilho vira bokeh (pesa muito de perto)\nAlta: HD Mode, bokeh padrão\nLeve: sem HD Mode (meia resolução), mais FPS")
				imgui.tree_pop()
			end
			if C.fresh("dof_c") then pcall(imgui.set_next_item_open, false, 1) end
			if imgui.tree_node("Configurações do DOF##dof_c") then
				pcall(function()
					changed, v = imgui.drag_float("Sensor Size", dof:call("get_SensorSize"), 0.01, 0, 100000)
					if changed then us.sensor = v; dof:call("set_SensorSize", v) end
					changed, v = imgui.drag_float("Focus Distance", dof:call("get_FocusDistance"), 0.01, 0, 100000)
					if changed then us.focus = v; dof:call("set_FocusDistance", v) end
					changed, v = imgui.drag_float("FNumber", dof:call("get_FNumber"), 0.01, 0, 100000)
					if changed then us.fnum = v; dof:call("set_FNumber", v) end
				end)
				imgui.tree_pop()
			end
			imgui.unindent(12)
		end
	end

	-- SSAO
	if c.ssao then
		local ssao = c.ssao
		local on = toggle("SSAO", "ssao", function() return ssao:call("get_Enabled") end, function(x) ssao:call("set_Enabled", x) end)
		if on then
			imgui.same_line()
			toggle("Temporal SSAO", "tssao", function() return ssao:call("getSSAOAlgorithm") == 1 end, function(x) ssao:call("setSSAOAlgorithm", x and 1 or 0) end)
		end
	end
	if c.bloom then
		local b = c.bloom
		toggle("Soft Bloom", "bloom", function() return b:call("get_Enabled") end, function(x) b:call("set_Enabled", x) end)
	end

	-- Custom Filter (LUT): só liga/desliga
	if c.filter then
		local f = c.filter
		toggle("Custom Filter (LUT)", "filter", function() return f:call("get_Enabled") end, function(x) f:call("set_Enabled", x) end)
	end
	if c.tonemap then
		local tm = c.tonemap
		toggle("Vignette", "vig", function() return tm:call("getVignetting") ~= 2 end, function(x) tm:call("setVignetting", x and 0 or 2) end)
	end
	if c.cc then
		local cc = c.cc
		imgui.same_line()
		toggle("Color Correction", "cc", function() return cc:call("get_Enabled") end, function(x) cc:call("set_Enabled", x) end)
	end
	if c.vol then
		local vol = c.vol
		toggle("Volumetric Fog", "vol", function() return vol:call("get_Enabled") end, function(x) vol:call("set_Enabled", x) end)
	end
	if next(us) then
		if imgui.button("Voltar tudo ao padrão do jogo") then us = {} end
		tip("Para de forçar as opções que você mudou (vale a partir da próxima câmera/cena)")
	end
end

-- Extras: Ray Tracing + Greenscreen --------------------------------------------
local rt_td = sdk.find_type_definition("via.render.ExperimentalRayTrace")
local rt_setup = nil
re.on_application_entry("PrepareRendering", function()
	if not rt_setup then return end
	local fn = rt_setup
	rt_setup = nil
	pcall(fn)
end)

local DOF_KEYS = { focus = "FocusDistance", fnum = "FNumber", sensor = "SensorSize" }
function C.dof_value(key)
	local d = cam_comps().dof
	local ok, v = pcall(function() return d:call("get_" .. DOF_KEYS[key]) end)
	return ok and v or nil
end
function C.set_dof_value(key, v)
	local d = cam_comps().dof
	if not d then return end
	us[key] = v
	pcall(d.call, d, "set_" .. DOF_KEYS[key], v)
end
function C.get_dof()
	local d = cam_comps().dof
	local ok, en = pcall(function() return d and d:call("get_Enabled") end)
	return ok and en == true
end
function C.set_dof(on)
	local d = cam_comps().dof
	if not d then return end
	us.dof = on
	pcall(d.call, d, "set_Enabled", on)
	if on then dof_extras(d) end
end
function C.get_greenscreen() return gs.on end
function C.set_greenscreen(on)
	local cc = cam_comps()
	gs.on = on
	if on then gs_apply(cc) else gs_off(cc) end
	-- v2.6.3: com o greenscreen o cenário some sozinho (fica só lutador + cor)
	if C.gs_stage then pcall(C.gs_stage, on) end
end

function C.ui_extras()
	local c = cam_comps()
	if not c.go then imgui.text("Câmera não encontrada.") return end
	local changed, v
	if rt_td then
		local on = false
		pcall(function() on = c.rt and c.rt:call("get_Enabled") or false end)
		changed, v = imgui.checkbox("Ray Tracing", on)
		if changed then
			if not c.rt and v then
				local go = c.go
				pcall(go.call, go, "createComponent(System.Type)", sdk.typeof("via.render.ExperimentalRayTrace"))
				rt_setup = function()
					local rt = getC(go, "via.render.ExperimentalRayTrace")
					rt:call("set_RaytracingMode", 6)
					rt:call("set_DenoiserDebugView", 1)
				end
			elseif c.rt then
				pcall(c.rt.call, c.rt, "set_Enabled", v)
			end
		end
		tip("Ray tracing experimental do RE Engine (pesado)")
		if c.rt and on then
			imgui.same_line()
			local refl = false
			pcall(function() refl = c.rt:call("get_DenoiserDebugView") == 0 end)
			changed, refl = imgui.checkbox("Reflexos RT", refl)
			if changed then pcall(c.rt.call, c.rt, "set_DenoiserDebugView", refl and 0 or 1) end
		end
	end
	if c.fog then
		local gon = gs.on
		changed, gon = imgui.checkbox("Greenscreen", gon)
		tip("Funciona melhor no estágio 'Training Room'")
		if changed then C.set_greenscreen(gon) end
		if gs.on then
			changed, gs.color = imgui.color_edit3("Cor do Greenscreen", gs.color, 17301504)
			pcall(C.ui_gs_parts)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lutadores: dano de luta e suor (parâmetros de material)
-- ---------------------------------------------------------------------------
local fx = { damage = nil, sweat = nil, slots = nil, t = -10 }

local function fighter_meshes()
	local out = {}
	for _, m in ipairs(find_all("via.render.Mesh")) do
		local ok, n = pcall(function() return m:call("get_GameObject"):call("get_Name") end)
		if ok and n and n:find("^esf0%d%dv") then table.insert(out, m) end
	end
	return out
end

-- (malha, material, variável) de cada parâmetro, para não procurar todo frame
local function fx_slots()
	if fx.slots and os.clock() - fx.t < 3.0 then return fx.slots end
	fx.t = os.clock()
	local slots = { DamageLevel = {}, Sweat_Rate = {} }
	for _, mesh in ipairs(fighter_meshes()) do
		pcall(function()
			for m = 0, mesh:call("get_MaterialNum") - 1 do
				for v = 0, mesh:call("getMaterialVariableNum", m) - 1 do
					local name = mesh:call("getMaterialVariableName", m, v)
					if slots[name] then table.insert(slots[name], { mesh, m, v }) end
				end
			end
		end)
	end
	fx.slots = slots
	return slots
end

local function fx_set(param, value)
	for _, sl in ipairs(fx_slots()[param] or {}) do
		pcall(sl[1].call, sl[1], "setMaterialFloat", sl[2], sl[3], value)
	end
end

re.on_application_entry("PrepareRendering", function()
	if fx.damage then fx_set("DamageLevel", fx.damage) end
	if fx.sweat then fx_set("Sweat_Rate", fx.sweat) end
end)

function C.ui_fighter_fx()
	local slots = fx_slots()
	if #slots.DamageLevel == 0 and #slots.Sweat_Rate == 0 then
		imgui.text_colored("Dano e suor só funcionam com os lutadores carregados (luta/treino).", MUTED)
		return
	end
	local changed, v
	changed, v = imgui.slider_float("Dano de luta", fx.damage or 0.0, 0, 1)
	if changed then fx.damage = v end
	changed, v = imgui.slider_float("Suor", fx.sweat or 0.0, 0, 1)
	if changed then fx.sweat = v end
	if fx.damage or fx.sweat then
		if imgui.button("Deixar o jogo controlar##fx") then fx.damage, fx.sweat = nil, nil end
	end
end

-- ---------------------------------------------------------------------------
-- Cenário
-- ---------------------------------------------------------------------------
local function stage_id()
	local bf = battleflow()
	if not bf then return nil end
	local ok, id = pcall(function() return bf:get_field("m_desc").Stage.StageId end)
	if not ok or not id then
		ok, id = pcall(function() return bf.m_desc.Stage.StageId end)
	end
	if not ok or type(id) ~= "number" then return nil end
	return string.format("%04d", math.floor(id * 0.01))
end

function C.stage_folder_prefix()
	local id = stage_id()
	return id and ("ess" .. id) or nil
end

-- partes do cenário que o greenscreen esconde. O padrão esconde só o que a névoa
-- verde não cobre (efeitos, detalhes e plateia); o céu/ambiente fica, senão o fundo
-- vazio sai branco em vez de verde. Cada parte pode ser ligada de volta no HUD.
local GS_PARTS = {
	{ k = "Env",   label = "Ambiente (céu/fundo)", folder = "_00_Env" },
	{ k = "Level", label = "Cenário (chão/estrutura)", folder = "_00_Level" },
	{ k = "VFX",   label = "Efeitos do cenário", folder = "_00_VFX" },
	{ k = "High",  label = "Detalhes (alta)", folder = "_00v_High" },
	{ k = "Crowd", label = "Plateia", folder = nil },
}
local GS_DEFAULT = { Env = false, Level = false, VFX = true, High = true, Crowd = true }
local function gs_hide_cfg()
	local s = C.settings
	if type(s.gs_hide) ~= "table" then s.gs_hide = {} end
	for k, v in pairs(GS_DEFAULT) do if s.gs_hide[k] == nil then s.gs_hide[k] = v end end
	return s.gs_hide
end
-- Esconde só o que se vê (malhas e efeitos) das pastas escolhidas. Antes a pasta
-- inteira sumia, e as luzes que estavam nela apagavam junto (mudava a iluminação
-- do lutador). Agora as luzes do cenário continuam acesas.
local gs_saved = {}
local gs_scan = { t = -10, list = {} }
local function gs_folder_paths(on)
	local sc = scene()
	local id = stage_id()
	local hide = gs_hide_cfg()
	local paths = {}
	for _, part in ipairs(GS_PARTS) do
		if on and hide[part.k] then
			pcall(function()
				local f = part.folder and id and sc:call("findFolder", "ess" .. id .. part.folder) or (not part.folder and sc:call("findFolder", "BillboardCrowd"))
				if f then table.insert(paths, f:call("get_Path")) end
			end)
		end
	end
	return paths
end
function C.gs_stage(on)
	local paths = gs_folder_paths(on)
	local keep = {}
	if #paths > 0 then
		if os.clock() - gs_scan.t > 1.0 then
			gs_scan.t = os.clock()
			gs_scan.list = {}
			for _, tn in ipairs({ "via.render.Mesh", "via.effect.EffectPlayer", "via.render.MeshDecal", "via.render.Decal" }) do
				for _, comp in ipairs(find_all(tn)) do
					pcall(function()
						local go = comp:call("get_GameObject")
						local f = go and go:call("get_Folder")
						local fp = f and f:call("get_Path")
						if fp then table.insert(gs_scan.list, { go = go, path = fp }) end
					end)
				end
			end
		end
		for _, it in ipairs(gs_scan.list) do
			for _, p in ipairs(paths) do
				if it.path == p or it.path:sub(1, #p + 1) == p .. "/" then
					pcall(function()
						local k = addr(it.go)
						keep[k] = true
						if gs_saved[k] == nil then gs_saved[k] = { go = it.go, v = it.go:call("get_DrawSelf") } end
						if it.go:call("get_DrawSelf") then it.go:call("set_DrawSelf", false) end
					end)
					break
				end
			end
		end
	end
	-- o que não deve mais ficar escondido volta como estava
	for k, sv in pairs(gs_saved) do
		if not keep[k] then pcall(sv.go.call, sv.go, "set_DrawSelf", sv.v ~= false); gs_saved[k] = nil end
	end
end
function C.ui_gs_parts()
	local hide = gs_hide_cfg()
	imgui.text("Esconder com o greenscreen:")
	for i, part in ipairs(GS_PARTS) do
		if i > 1 and (i - 1) % 2 == 1 then imgui.same_line() end
		local ch, v = imgui.checkbox(part.label .. "##gsp" .. part.k, hide[part.k] == true)
		if ch then hide[part.k] = v; C.save(); gs_scan.t = -10; pcall(C.gs_stage, gs.on) end
	end
end

function C.ui_stage_display()
	local id = stage_id()
	if not id then
		imgui.text_colored("Stage Display só funciona dentro de uma luta/treino.", MUTED)
		return
	end
	local sc = scene()
	pcall(function()
		local vfx = sc:call("findGameObject(System.String)", "NoParentEffects")
		if vfx then
			local ch, en = imgui.checkbox("Efeitos dos lutadores", vfx:call("get_DrawSelf"))
			if ch then vfx:call("set_DrawSelf", en) end
		end
	end)
	local labels = { Env = "Ambiente", Light = "Luzes do cenário", VFX = "Efeitos do cenário", Level = "Cenário (chão/estrutura)", High = "Detalhes (alta)" }
	for _, name in ipairs({ "Env", "Light", "VFX", "Level", "High" }) do
		pcall(function()
			local folder = sc:call("findFolder", "ess" .. id .. (name == "High" and "_00v_" or "_00_") .. name)
			if not folder then return end
			local ch, en = imgui.checkbox(labels[name] .. "##sd" .. name, folder:call("get_DrawSelf"))
			if ch then folder:call("set_DrawSelf", en) end
			if name == "Env" and en then
				local bb = sc:call("findFolder", "BillboardCrowd")
				if bb then
					imgui.same_line()
					local ch2, en2 = imgui.checkbox("Plateia", bb:call("get_DrawSelf"))
					if ch2 then bb:call("set_DrawSelf", en2) end
				end
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Luzes novas (o HUD controla as propriedades)
-- ---------------------------------------------------------------------------
local light_count = 0
function C.create_light(kind)
	light_count = light_count + 1
	local tn = (kind == 1) and "via.render.ProjectionSpotLight" or "via.render.PointLight"
	local name = string.format("NASK%sLight%d", kind == 1 and "Spot" or "Point", light_count)
	local go = sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, name)
	if not go then return nil end
	go = go:add_ref()
	local light = go:call("createComponent(System.Type)", sdk.typeof(tn))
	if not light then return nil end
	light:call(".ctor()")
	pcall(light.call, light, "set_Unit", 0)
	local xform = go:call("get_Transform")
	pcall(xform.call, xform, "set_SameJointsConstraint", true)
	local pos, rot = cam_get()
	if pos and rot and kind ~= 1 then pos = pos + rot * Vector3f.new(0, 0, -1.5) end
	return { gameobj = go, light = light, xform = xform, pos = pos, rot = rot }
end

-- ---------------------------------------------------------------------------
-- Teclas e pedidos do HUD (todo frame)
-- ---------------------------------------------------------------------------
re.on_frame(function()
	local r = C.pull()
	if r.toggle_freecam or keys.pressed("Activate FreeCam") then C.toggle() end
	if r.freeze_cam or keys.pressed("Freeze Camera") then C.cam_frozen = not C.cam_frozen end
	if r.hide_ui or keys.pressed("Hide UI") then C.hide_ui = not C.hide_ui end
	if r.freeze_all or keys.pressed("Freeze Time & Scene") then toggle_freeze_all() end
	if r.freeze_battle or keys.pressed("Freeze Time") then toggle_freeze_battle() end
	if r.skip_frame or keys.pressed("Skip Frame") then skip_frame() end
	if keys.pressed("2x Quality") then C.set_hi_quality(not hq.on) end
	if keys.pressed("Reset Zoom") then cam.fov = nil end
end)

re.on_script_reset(function()
	if C.on then freecam_stop() end
	if hq.on then C.set_hi_quality(false) end
	if dl.on then C.set_disable_lights(false) end
	if C.is_scene_frozen() then set_speed(1.0) end
	local bf = battle.flow
	if bf then pcall(bf.call, bf, "set_Enabled", true) end
	pcall(C.apply_ldr, false)
	if C.clean then C.set_clean(false) end
end)

-- ---------------------------------------------------------------------------
-- Edição: LUT, exposição, contraste, saturação, níveis, cor...
-- Os nomes exatos dos ajustes mudam entre jogos do RE Engine, então o NASK
-- descobre sozinho os pares get_/set_ de número (e de cor) dos componentes de
-- imagem da câmera e mostra os conhecidos com nome em português. O que você
-- mexe é reaplicado todo frame (o jogo volta os valores ao trocar de câmera).
-- ---------------------------------------------------------------------------
local ED = { cache = {}, edits = {}, orig = {}, lut = nil }
local ED_GROUPS = {
	{ "Luz", { { "exposure", "Exposição" }, { "ev", "Exposição (EV)" }, { "brightness", "Brilho" }, { "luminance", "Luminância" }, { "gain", "Ganho" } } },
	{ "Contraste e níveis", { { "contrast", "Contraste" }, { "gamma", "Gama" }, { "black", "Nível de preto" }, { "white", "Nível de branco" },
		{ "lift", "Sombras (lift)" }, { "toe", "Sombras (toe)" }, { "shoulder", "Altas luzes" }, { "level", "Níveis" }, { "middle", "Meios-tons" } } },
	{ "Cor", { { "saturation", "Saturação" }, { "vibrance", "Vibração" }, { "temperature", "Temperatura" }, { "tint", "Tonalidade" },
		{ "hue", "Matiz" }, { "color", "Cor" } } },
	{ "Efeitos", { { "grain", "Granulado" }, { "vignet", "Vinheta" }, { "bloom", "Bloom" }, { "sharp", "Nitidez" }, { "chromatic", "Aberração cromática" } } },
}
local FLOAT_T = { ["System.Single"] = true, ["System.Double"] = true }
local VEC_T = { ["via.vec3"] = true, ["via.Float3"] = true, ["via.vec4"] = true, ["via.Float4"] = true, ["via.Color"] = true }

-- pares get/set de um tipo (com os pais)
local function ed_props(type_name)
	if ED.cache[type_name] then return ED.cache[type_name] end
	local props = {}
	pcall(function()
		local td = sdk.find_type_definition(type_name)
		local getters, setters = {}, {}
		local guard = 0
		while td and guard < 6 do
			guard = guard + 1
			for _, m in ipairs(td:get_methods()) do
				local n = m:get_name()
				local np = m:get_num_params()
				if np == 0 and n:sub(1, 4) == "get_" then
					local rt = m:get_return_type()
					getters[n:sub(5)] = rt and rt:get_full_name() or ""
				elseif np == 1 and n:sub(1, 4) == "set_" then
					local pt = m:get_param_types()[1]
					setters[n:sub(5)] = pt and pt:get_full_name() or ""
				end
			end
			td = td:get_parent_type()
			if td and td:get_full_name() == "via.Component" then break end
		end
		for name, t in pairs(setters) do
			if getters[name] == t and (FLOAT_T[t] or VEC_T[t]) then
				table.insert(props, { name = name, t = t, vec = VEC_T[t] == true })
			end
		end
		table.sort(props, function(a, b) return a.name < b.name end)
	end)
	ED.cache[type_name] = props
	return props
end

local function ed_targets()
	local c = cam_comps()
	local out = {}
	local function add(label, obj, tn)
		if obj then table.insert(out, { label = label, obj = obj, tn = tn }) end
	end
	add("Tone Mapping", c.tonemap, "via.render.ToneMapping")
	add("Color Correction", c.cc, "via.render.LDRColorCorrect")
	add("Pós-processamento", c.ldr, "via.render.LDRPostProcess")
	pcall(function()
		local go = c.go
		for _, tn in ipairs({ "via.render.LDRFilmGrain", "via.render.LDRHazeFilter", "via.render.RetroFilm", "via.render.SoftBloom" }) do
			local comp = getC(go, tn)
			if comp then add(tn:gsub("^via%.render%.", ""), comp, tn) end
		end
	end)
	return out
end

local function ed_key(obj, name) return tostring(addr(obj)) .. ":" .. name end

local function ed_get(obj, name)
	local ok, v = pcall(obj.call, obj, "get_" .. name)
	return ok and v or nil
end

local function ed_set(obj, name, v)
	local k = ed_key(obj, name)
	if ED.orig[k] == nil then ED.orig[k] = { obj = obj, name = name, v = ed_get(obj, name) } end
	ED.edits[k] = { obj = obj, name = name, v = v }
	pcall(obj.call, obj, "set_" .. name, v)
end

local function ed_reset(k)
	local o = ED.orig[k]
	if o and o.v ~= nil then pcall(o.obj.call, o.obj, "set_" .. o.name, o.v) end
	ED.edits[k] = nil
end

function C.edit_tick()
	for k, e in pairs(ED.edits) do
		if not pcall(e.obj.call, e.obj, "set_" .. e.name, e.v) then ED.edits[k] = nil end
	end
end
re.on_application_entry("PrepareRendering", function() if next(ED.edits) then C.edit_tick() end end)

local function ed_label(name)
	local l = name:lower()
	for gi, g in ipairs(ED_GROUPS) do
		for _, kw in ipairs(g[2]) do
			-- "EV" só como sigla (senão "Level" viraria exposição)
			local hit = (kw[1] == "ev") and (name:find("EV") ~= nil) or (kw[1] ~= "ev" and l:find(kw[1], 1, true) ~= nil)
			if hit then return gi, kw[2] end
		end
	end
	return nil
end

local function ed_widget(obj, p, label)
	local k = ed_key(obj, p.name)
	local v = ed_get(obj, p.name)
	if v == nil then return end
	imgui.push_id(k)
	local ch, nv
	if p.vec then
		local col = Vector3f.new(v.x or 0, v.y or 0, v.z or 0)
		ch, nv = imgui.color_edit3(label, col, 17301504)
		if ch then
			if p.t == "via.vec4" or p.t == "via.Float4" or p.t == "via.Color" then nv = Vector4f.new(nv.x, nv.y, nv.z, v.w or 1.0) end
			ed_set(obj, p.name, nv)
		end
	else
		local speed = math.max(0.001, math.abs(v) * 0.01)
		ch, nv = imgui.drag_float(label, v, speed, -100000, 100000, "%.3f")
		if ch then ed_set(obj, p.name, nv) end
	end
	tip(p.name .. "  (arraste; Ctrl+clique digita)")
	if ED.edits[k] then
		imgui.same_line()
		if imgui.small_button("↺") then ed_reset(k) end
		tip("Voltar ao valor do jogo")
	end
	imgui.pop_id()
end

-- LUT (Custom Filter) com a lista dos LUTs que o jogo já usou
local function ed_lut(c)
	local f = c.filter
	if not f then return end
	local s = C.settings
	toggle("Custom Filter (LUT)", "filter", function() return f:call("get_Enabled") end, function(x) f:call("set_Enabled", x) end)
	pcall(function()
		local fs = f:call("getFilterShader", 0)
		if not fs then return end
		local res = fs:call("get_Filter")
		local path = res and res:call("get_ResourcePath")
		local known = false
		for _, pth in ipairs(s.luts) do if pth == path then known = true end end
		if path and not known then table.insert(s.luts, path); table.sort(s.luts); C.save() end
		if #s.luts == 0 then return end
		local names, cur = {}, 1
		for i, pth in ipairs(s.luts) do
			names[i] = (pth:match("([^/\\]+)$") or pth):gsub("%.%w+$", "")
			if pth == path then cur = i end
		end
		local ch, idx = imgui.combo("LUT", cur, names)
		if ch then
			local h = C.create_resource("via.render.MeshMaterialResource", s.luts[idx])
			if h then fs:call("set_Filter", h) end
		end
		tip("A lista cresce com os LUTs que o jogo usar (cenários, menus...)")
	end)
end

function C.ui_edit(section_fn)
	local c = cam_comps()
	if not c.go then imgui.text("Câmera não encontrada.") return end
	local sec = section_fn or function(t) imgui.text_colored(t, MUTED) end
	sec("LUT")
	ed_lut(c)
	local targets = ed_targets()
	if #targets == 0 then
		imgui.text_colored("Nenhum componente de imagem nesta câmera (entre numa luta/treino).", MUTED)
		return
	end
	-- ajustes conhecidos, por grupo
	local others = {}
	for gi, g in ipairs(ED_GROUPS) do
		local shown = false
		for _, t in ipairs(targets) do
			for _, p in ipairs(ed_props(t.tn)) do
				local pg, lab = ed_label(p.name)
				if pg == gi then
					if not shown then sec(g[1]:upper()); shown = true end
					ed_widget(t.obj, p, lab .. "  ·  " .. t.label)
				elseif pg == nil and gi == 1 then
					table.insert(others, { t = t, p = p })
				end
			end
		end
	end
	if next(ED.edits) then
		imgui.spacing()
		if imgui.button("Voltar tudo ao padrão do jogo##ed") then
			for k in pairs(ED.edits) do ed_reset(k) end
		end
	end
	-- o resto (avançado)
	if #others > 0 and C.fresh("edo") then pcall(imgui.set_next_item_open, false, 1) end
	if #others > 0 and imgui.tree_node("Outros ajustes (" .. #others .. ")##edo") then
		for _, o in ipairs(others) do ed_widget(o.t.obj, o.p, o.p.name .. "  ·  " .. o.t.label) end
		imgui.tree_pop()
	end
end


return C
