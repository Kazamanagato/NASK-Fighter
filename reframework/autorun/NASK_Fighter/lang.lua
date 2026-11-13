-- NASK Fighter - idiomas
-- O código do HUD é escrito em português. Os arquivos do NASK usam "L.ui" no lugar
-- do imgui: é o mesmo imgui, mas as funções de texto passam por L.t(), que troca
-- o texto pelo do idioma escolhido. Os IDs depois de "##" ficam iguais.
local L = {}

L.LANGS = {
	{ id = "en", name = "English" },
	{ id = "pt", name = "Português (Brasil)" },
}
L.lang = "pt"
L.collect = nil          -- tabela: guarda os textos vistos (usado para gerar a tradução)

-- carregado junto com o script (um require depois, durante o jogo, não acha a pasta)
local data
do
	local ok, d = pcall(require, "NASK_Fighter/lang_data")
	data = (ok and type(d) == "table") and d or { words = {}, patterns = {} }
end
function L.set_data(d) data = d end
function L.loaded() return next(data.words) ~= nil end

local cache, ncache = {}, 0
function L.set(lang)
	local ok = false
	for _, l in ipairs(L.LANGS) do if l.id == lang then ok = true end end
	L.lang = ok and lang or "pt"
	cache, ncache = {}, 0
end

local frags
local function fragments()
	if frags then return frags end
	frags = {}
	for k in pairs(data.words) do
		if k:find("^%s") or k:find("%s$") or k:find("[%(:]$") or k:find("^[%)\"\n]") then
			table.insert(frags, k)
		end
	end
	table.sort(frags, function(a, b) return #a > #b end)
	return frags
end

-- traduz um texto (sem "##")
local function tr(s)
	if L.collect then L.collect[s] = true end
	if L.lang == "pt" then return s end
	local c = cache[s]
	if c then return c end
	local e = data.words[s]
	local out = e and e[L.lang]
	if not out then
		for _, p in ipairs(data.patterns) do
			local rep = p[L.lang]
			if rep and s:find(p.pat) then
				out = s:gsub(p.pat, rep)
				break
			end
		end
	end
	if not out then
		-- textos montados no código ("Tecla " .. tecla, "Abrir o HUD (" .. tecla .. " também abre)"):
		-- troca os pedaços conhecidos, do maior para o menor
		local r, hit = s, false
		for _, k in ipairs(fragments()) do
			local v = data.words[k][L.lang]
			if v then
				local i = r:find(k, 1, true)
				if i then
					r = r:sub(1, i - 1) .. v .. r:sub(i + #k)
					hit = true
				end
			end
		end
		if hit then out = r end
	end
	out = out or s
	-- textos com números mudam a cada frame: o cache não pode crescer sem fim
	ncache = ncache + 1
	if ncache > 3000 then cache, ncache = {}, 0 end
	cache[s] = out
	return out
end

function L.t(s)
	if type(s) ~= "string" or s == "" then return s end
	local a = s:find("##", 1, true)
	if a then
		local head = s:sub(1, a - 1)
		if head == "" then return s end
		return tr(head) .. s:sub(a)
	end
	return tr(s)
end

local function tlist(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = L.t(v) end
	return o
end

function L.active() return L.lang ~= "pt" or L.collect ~= nil end

-- funções do ImGui cujo 1º argumento é texto
local FIRST = {}
for _, n in ipairs({ "text", "text_colored", "button", "small_button", "checkbox", "slider_float", "slider_int",
	"drag_float", "drag_float2", "drag_float3", "drag_int", "input_text", "tree_node", "set_tooltip",
	"calc_text_size", "color_edit3", "color_edit4", "selectable", "radio_button", "text_wrapped",
	"bullet_text", "input_float", "input_int", "collapsing_header" }) do FIRST[n] = true end

-- campos com nome: com L.left_labels o nome vai à esquerda
local LEFT = {}
for _, n in ipairs({ "slider_float", "slider_int", "drag_float", "drag_float2", "drag_float3", "drag_int",
	"input_text", "input_float", "input_int", "color_edit3", "color_edit4", "combo" }) do LEFT[n] = true end
L.left_labels = true

-- imgui do NASK: igual ao imgui, com os textos traduzidos
local wrap = {}
L.ui = setmetatable({}, { __index = function(_, k)
	local real = _G.imgui
	local f = real and real[k]
	if type(f) ~= "function" then return f end
	local w = wrap[k]
	if w and w.f == f then return w.w end
	local fn
	if LEFT[k] then
		-- v2.6.19: nome do campo à esquerda (o ImGui põe à direita)
		fn = function(label, ...)
			if not L.left_labels or type(label) ~= "string" then
				if k == "combo" then
					local cur, items = ...
					if L.active() then return f(L.t(label), cur, tlist(items), select(3, ...)) end
				elseif L.active() then label = L.t(label) end
				return f(label, ...)
			end
			local a = label:find("##", 1, true)
			local vis = a and label:sub(1, a - 1) or label
			if vis == "" then
				if k == "combo" and L.active() then
					local cur, items = ...
					return f(label, cur, tlist(items), select(3, ...))
				end
				return f(label, ...)
			end
			local id = "##L" .. (a and label:sub(a + 2) or label)
			local txt = L.active() and L.t(vis) or vis
			local x0 = real.get_cursor_pos().x
			local ww = real.get_window_size().x
			local lw = math.min(150, math.max(90, ww * 0.26))
			pcall(real.align_text_to_frame_padding)
			real.text(txt)
			real.same_line()
			local cp = real.get_cursor_pos()
			real.set_cursor_pos(Vector2f.new(math.max(cp.x + 4, x0 + lw), cp.y))
			real.push_item_width(math.max(60, ww - real.get_cursor_pos().x - 18))
			local r
			if k == "combo" then
				local cur, items = ...
				r = table.pack(f(id, cur, L.active() and tlist(items) or items, select(3, ...)))
			else
				r = table.pack(f(id, ...))
			end
			real.pop_item_width()
			return table.unpack(r, 1, r.n)
		end
	elseif FIRST[k] then
		fn = function(a, ...)
			if L.active() then a = L.t(a) end
			return f(a, ...)
		end
	elseif k == "combo" then
		fn = function(label, cur, items, ...)
			if L.active() then return f(L.t(label), cur, tlist(items), ...) end
			return f(label, cur, items, ...)
		end
	else
		fn = f
	end
	wrap[k] = { f = f, w = fn }
	return fn
end, __newindex = function(_, k, v) _G.imgui[k] = v end })

-- compatibilidade: roda fn protegida
function L.run(fn, ...)
	return xpcall(fn, debug.traceback, ...)
end

-- draw list que traduz add_text
function L.dl(real)
	if not L.active() then return real end
	return setmetatable({}, { __index = function(_, k)
		local f = real[k]
		if type(f) ~= "function" then return f end
		if k == "add_text" then
			return function(_, p, c, s, ...) return f(real, p, c, L.t(s), ...) end
		end
		return function(_, ...) return f(real, ...) end
	end })
end

return L
