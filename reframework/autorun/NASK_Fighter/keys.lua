-- ============================================================================
--  NASK FIGHTER · keys.lua
--  Teclas, botões do controle e do mouse (só REFramework, sem scripts de terceiros)
--
--  Uso:
--    local keys = require("NASK_Fighter/keys")
--    keys.define("Minha Ação", "F1")       -- registra com a tecla padrão
--    if keys.pressed("Minha Ação") then ... end   -- apertou agora
--    if keys.down("Minha Ação") then ... end      -- está segurando
--    keys.setter("Minha Ação", "Rótulo")          -- botão de troca de tecla (imgui)
--
--  Ligações são texto: "F1" (teclado), "Pad:Decide" (controle), "Mouse:R" (mouse).
-- ============================================================================

if _G.__NASK_KEYS then return _G.__NASK_KEYS end

-- imgui com tradução (ver lang.lua)
local imgui = require("NASK_Fighter/lang").ui
local K = {}
_G.__NASK_KEYS = K

local FILE = "NASK_Fighter\\keys.json"
local UNBOUND = "-"

-- ---------------------------------------------------------------------------
-- Enumerações do jogo (nome -> valor)
-- ---------------------------------------------------------------------------
local function enum_fields(type_name)
	local out = {}
	pcall(function()
		local td = sdk.find_type_definition(type_name)
		for _, f in ipairs(td:get_fields()) do
			if f:is_static() then
				local ok, v = pcall(f.get_data, f, nil)
				if ok and type(v) == "number" then out[f:get_name()] = v end
			end
		end
	end)
	return out
end

K.kb_keys  = enum_fields("via.hid.KeyboardKey")
K.pad_btns = enum_fields("via.hid.GamePadButton")
K.mouse_btns = enum_fields("via.hid.MouseButton")

-- nomes alternativos (o nome exato muda entre jogos/versões)
local ALIASES = {
	OEM_COMMA  = { "OEM_COMMA", "OemComma", "Comma", "OEM_Comma" },
	OEM_PERIOD = { "OEM_PERIOD", "OemPeriod", "Period", "OEM_Period" },
	Scroll     = { "Scroll", "ScrollLock", "Scroll_Lock", "SCROLL", "ScrollLockKey" },
	LShift     = { "LShift", "LeftShift", "Shift", "LSHIFT" },
	LAlt       = { "LAlt", "LMenu", "LeftAlt", "Alt", "Menu", "LALT" },
	Escape     = { "Escape", "Esc", "ESCAPE" },
	Back       = { "Back", "BackSpace", "Backspace", "BACK" },
	Delete     = { "Delete", "Del", "DELETE" },
	Insert     = { "Insert", "Ins", "INSERT" },
	Prior      = { "Prior", "PageUp", "Page_Up", "PgUp", "PRIOR" },
	LControl   = { "LControl", "LeftControl", "LCtrl", "Control", "Ctrl", "LCONTROL" },
	Space      = { "Space", "SpaceBar", "Spacebar", "SPACE" },
}

local function resolve_kb(name)
	if K.kb_keys[name] then return name end
	for _, alt in ipairs(ALIASES[name] or {}) do
		if K.kb_keys[alt] then return alt end
	end
	-- sem diferenciar maiúsculas
	local ln = name:lower()
	for n in pairs(K.kb_keys) do if n:lower() == ln then return n end end
	return nil
end

-- devolve a ligação válida (ou UNBOUND)
function K.resolve(binding)
	if type(binding) ~= "string" or binding == "" or binding == UNBOUND or binding == "[Not Bound]" then return UNBOUND end
	local kind, name = binding:match("^(%a+):(.+)$")
	if kind == "Pad" then return K.pad_btns[name] and binding or UNBOUND end
	if kind == "Mouse" then return K.mouse_btns[name] and binding or UNBOUND end
	local n = resolve_kb(binding)
	if n then return n end
	-- pode estar salvo sem prefixo como botão do controle
	if K.pad_btns[binding] then return "Pad:" .. binding end
	return UNBOUND
end

-- ---------------------------------------------------------------------------
-- Dispositivos
-- ---------------------------------------------------------------------------
local function native(singleton_names, type_name, method, ...)
	local td = sdk.find_type_definition(type_name)
	if not td then return nil end
	for _, sn in ipairs(singleton_names) do
		local s = sdk.get_native_singleton(sn)
		if s then
			local ok, r = pcall(sdk.call_native_func, s, td, method, ...)
			if ok and r then return r end
		end
	end
	return nil
end

K.kb, K.pad, K.mouse = nil, nil, nil

local function refresh_devices()
	K.kb    = native({ "via.hid.Keyboard" }, "via.hid.Keyboard", "get_Device")
	K.pad   = native({ "via.hid.Gamepad", "via.hid.GamePad" }, "via.hid.GamePad", "getMergedDevice", 0)
	K.mouse = native({ "via.hid.Mouse" }, "via.hid.Mouse", "get_Device")
end

-- ---------------------------------------------------------------------------
-- Ações
-- ---------------------------------------------------------------------------
K.actions = {}       -- nome -> ligação atual
K.defaults = {}      -- nome -> ligação padrão
K.order = {}         -- ordem de registro
K.actions2 = {}      -- nome -> 2ª ligação (seção "Controle" dos atalhos)

-- versão do layout padrão: quando muda, as teclas voltam para o novo padrão uma vez
K.LAYOUT = 3
local saved = json.load_file(FILE) or {}
if saved.__layout ~= K.LAYOUT then saved = {} end

function K.save()
	local out = { __layout = K.LAYOUT }
	for a, b in pairs(K.actions) do out[a] = b end
	for a, b in pairs(K.actions2) do if b ~= UNBOUND then out["2:" .. a] = b end end
	json.dump_file(FILE, out)
end

function K.define(action, default)
	if K.defaults[action] == nil then table.insert(K.order, action) end
	K.defaults[action] = K.resolve(default)
	if K.actions[action] == nil then
		local s = saved[action]
		K.actions[action] = (s ~= nil) and K.resolve(s) or K.defaults[action]
	end
	if K.actions2[action] == nil then
		local s2 = saved["2:" .. action]
		K.actions2[action] = (s2 ~= nil) and K.resolve(s2) or UNBOUND
	end
end

function K.get(action) return K.actions[action] or UNBOUND end

function K.set(action, binding)
	K.actions[action] = K.resolve(binding)
	K.save()
end

function K.reset_defaults()
	for a, d in pairs(K.defaults) do K.actions[a] = d; K.actions2[a] = UNBOUND end
	K.save()
end

-- deixa todas as ações sem tecla
function K.clear_all()
	for a in pairs(K.defaults) do K.actions[a] = UNBOUND; K.actions2[a] = UNBOUND end
	K.save()
end

-- nome bonito para mostrar
local PRETTY = {
	OEM_COMMA = ",", OemComma = ",", Comma = ",", OEM_PERIOD = ".", OemPeriod = ".", Period = ".",
	Scroll = "Scroll Lock", ScrollLock = "Scroll Lock", LShift = "Shift", LAlt = "Alt", LMenu = "Alt",
	Prior = "Page Up", Next = "Page Down",
}
function K.label(binding)
	if not binding or binding == UNBOUND then return "-" end
	local kind, name = binding:match("^(%a+):(.+)$")
	if kind == "Pad" then return "Controle " .. name end
	if kind == "Mouse" then return "Mouse " .. name end
	return PRETTY[binding] or binding
end
function K.name_of(action) return K.label(K.get(action)) end
function K.get2(action) return K.actions2[action] or UNBOUND end

-- ---------------------------------------------------------------------------
-- Leitura (no UpdateHID, uma vez por frame do jogo)
-- ---------------------------------------------------------------------------
local state = {}        -- ligação -> { down = bool, t = momento em que apertou }
local read_t = {}       -- ação -> último momento em que pressed() devolveu true
local clock = 0         -- contador de frames de HID
K.block_until = -1      -- > clock: ignora as ações (ex.: digitando no HUD)

local function bit_on(mask, v)
	if not mask or not v then return false end
	local ok, r = pcall(function() return (math.tointeger(mask) & math.tointeger(v)) ~= 0 end)
	return ok and r
end

local function is_down(binding, pad_mask, mouse_mask)
	local kind, name = binding:match("^(%a+):(.+)$")
	if kind == "Pad" then return bit_on(pad_mask, K.pad_btns[name]) end
	if kind == "Mouse" then return bit_on(mouse_mask, K.mouse_btns[name]) end
	local v = K.kb_keys[binding]
	if not (v and K.kb) then return false end
	local ok, d = pcall(K.kb.call, K.kb, "isDown", v)
	return ok and d == true
end

-- captura de tecla nova (setter)
local capture = nil     -- { action = nome, since = clock }
local captured = nil    -- { action, binding }

local function poll_capture(pad_down_mask, mouse_down_mask)
	if not capture then return end
	if clock - capture.since < 3 then return end
	-- teclado: qualquer tecla que acabou de ser apertada
	if K.kb then
		for name, v in pairs(K.kb_keys) do
			local ok, t = pcall(K.kb.call, K.kb, "isTrigger", v)
			if ok and t then
				local esc, back = resolve_kb("Escape"), resolve_kb("Back")
				if name == esc then capture = nil return end
				if name == back then captured = { capture.action, UNBOUND }; capture = nil return end
				captured = { capture.action, name }; capture = nil
				return
			end
		end
	end
	-- controle: um botão só
	if pad_down_mask and pad_down_mask ~= 0 then
		for name, v in pairs(K.pad_btns) do
			if v ~= 0 and bit_on(pad_down_mask, v) and (math.tointeger(v) & (math.tointeger(v) - 1)) == 0 then
				captured = { capture.action, "Pad:" .. name }; capture = nil
				return
			end
		end
	end
	-- mouse (o clique esquerdo que abriu a captura é ignorado pelo atraso acima)
	if mouse_down_mask and mouse_down_mask ~= 0 then
		for name, v in pairs(K.mouse_btns) do
			if v ~= 0 and bit_on(mouse_down_mask, v) and name ~= "L" and name ~= "Left" then
				captured = { capture.action, "Mouse:" .. name }; capture = nil
				return
			end
		end
	end
end

re.on_pre_application_entry("UpdateHID", function()
	clock = clock + 1
	refresh_devices()
	local pad_mask, pad_down, mouse_mask, mouse_down
	if K.pad then
		pcall(function() pad_mask = K.pad:call("get_Button"); pad_down = K.pad:call("get_ButtonDown") end)
	end
	if K.mouse then
		pcall(function() mouse_mask = K.mouse:call("get_Button"); mouse_down = K.mouse:call("get_ButtonDown") end)
	end
	local now = os.clock()
	local seen = {}
	local all = {}
	for _, b in pairs(K.actions) do table.insert(all, b) end
	for _, b in pairs(K.actions2) do table.insert(all, b) end
	for _, b in ipairs(all) do
		if b ~= UNBOUND and not seen[b] then
			seen[b] = true
			local d = is_down(b, pad_mask, mouse_mask)
			local s = state[b]
			if not s then s = { down = false, t = -1 }; state[b] = s end
			if d and not s.down then s.t = now end
			s.down = d
		end
	end
	poll_capture(pad_down, mouse_down)
end)

local function blocked() return K.block_until >= clock end

-- bloqueia as ações por alguns frames (o HUD chama enquanto um campo de texto está ativo)
function K.block(frames) K.block_until = clock + (frames or 2) end

function K.down(action)
	if blocked() then return false end
	local b = K.actions[action]
	local s = b and state[b]
	if s ~= nil and s.down then return true end
	local b2 = K.actions2[action]
	local s2 = b2 and b2 ~= UNBOUND and state[b2]
	return s2 ~= nil and s2 ~= false and s2.down
end

-- true uma única vez por toque (para cada ação)
function K.pressed(action)
	local b = K.actions[action]
	local s = b and state[b]
	-- usa a ligação (teclado ou controle) apertada por último
	local b2 = K.actions2[action]
	local s2 = b2 and b2 ~= UNBOUND and state[b2] or nil
	if s2 and (not s or s2.t > s.t) then s = s2 end
	if not s or s.t < 0 then return false end
	if (read_t[action] or -1) >= s.t then return false end
	read_t[action] = s.t
	if blocked() then return false end
	return (os.clock() - s.t) < 0.5
end

-- analógicos (-1..1)
function K.axis_l()
	local ok, v = pcall(function() return K.pad and K.pad:call("get_RawAxisL") end)
	return ok and v or nil
end
function K.axis_r()
	local ok, v = pcall(function() return K.pad and K.pad:call("get_RawAxisR") end)
	return ok and v or nil
end

-- posição do mouse do jogo (pixels)
function K.mouse_pos()
	local ok, p = pcall(function()
		local pos = K.mouse:call("get_Position")
		return Vector2f.new(pos:get_field("x"), pos:get_field("y"))
	end)
	if ok and p then return p end
	local m = imgui.get_mouse()
	return m and Vector2f.new(m.x, m.y) or nil
end

-- ---------------------------------------------------------------------------
-- Botão de troca de tecla (imgui). Devolve true quando a ligação mudou.
-- ---------------------------------------------------------------------------
function K.setter(action, label, width, slot)
	local changed = false
	local key = (slot == 2) and ("2:" .. action) or action
	if captured and captured[1] == key then
		if slot == 2 then K.actions2[action] = K.resolve(captured[2]) else K.actions[action] = K.resolve(captured[2]) end
		captured = nil
		K.save()
		changed = true
	end
	local waiting = capture and capture.action == key
	local cur = (slot == 2) and K.label(K.get2(action)) or K.name_of(action)
	local txt = waiting and ((slot == 2) and "Aperte um botão do controle... (Esc cancela, Backspace limpa)" or "Aperte uma tecla... (Esc cancela, Backspace limpa)") or cur
	if imgui.button(txt .. "##ks_" .. key, Vector2f.new(width or 230, 0)) then
		if waiting then capture = nil else capture = { action = key, since = clock } end
	end
	imgui.same_line()
	imgui.text(label or action)
	return changed
end

function K.capturing() return capture ~= nil end

return K
