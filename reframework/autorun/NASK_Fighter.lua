-- ============================================================================
--  NASK FIGHTER  ·  Modo Foto para Street Fighter 6
--  HUD in-game (estilo do modo foto da Bayonetta) por cima do REFramework.
--  v2.0: tudo próprio (NASK_Fighter/core.lua e keys.lua), só com o REFramework.
--  Banner nítido pelo plugin reframework-d2d (cursey, MIT).
-- ============================================================================

local VERSION = "2.6.32"
local CFG_FILE = "NASK_Fighter.json"

-- ---------------------------------------------------------------------------
-- Configuração
-- ---------------------------------------------------------------------------
local defaults = {
	open_on_start = true,
	layout_applied = false,
	opacity = 0.78,
	accent = 1,             -- 1 roxo, 2 lilás, 3 rosa
	header_quality = 3,     -- 1 desligada, 2 normal, 3 alta
	cursor_mode = 5,        -- 1 sempre, 2 só com o HUD aberto, 3 nunca, 4 só em cima do HUD, 5 automático
	photo_dir = "",         -- vazio = pasta padrão (Imagens\NASK Fighter)
	gallery = {},
	block_mouse_hover = true,
	hide_hud_with_ui = false,
	vs_walk_off = false,
	panels = {},
	light_gizmo = true,
	light_gizmo_op = 1,     -- 1 mover, 2 girar, 3 ambos
	light_lines = true,
	banner = 0,             -- 0 = NASK padrão, 1..5 = nask_banner_N.png
	banner_text_on = true,
	banner_fade = true,
	banner_dark = 0.35,     -- escurecer embaixo do banner (texto legível)
	glass_dark = 0.20,      -- escurecer o fundo de vidro
	bg_blur = 24, bg_dark = 40,
	user_bg_src = "", user_banner_src = "",
	banner_title = "NASK FIGHTER",
	banner_sub = "MODO FOTO  ·  STREET FIGHTER 6",
	tab = 1,
	stick = { deadzone = 0.12, curve = 1.8, sens = 1.0 },
	move_stick = true,
	roll_step = 90.0,
	no_distort = true,      -- sem distorção de lente na câmera livre
	poses = {},
	style = 3,              -- 1 Dark, 2 Light, 3 NASK (vidro com foto)
	theme_v = 0,
	vpreview = false,       -- preview vertical (overlay 9:16, laterais pretas)
	open_mode = 1,          -- tecla do HUD abre: 1 Base, 2 Portátil
	glass_bg = 1,           -- fundo do tema NASK (nask_glass_N: 1, 3, 4, 7; 8 = seu fundo)
	last_disp_w = 0, last_disp_h = 0,
	mmdk_nokeys = true,     -- tira as teclas do MMDK ao iniciar (aba Animações)
	mmdk_keys_bak = {},     -- teclas originais do MMDK, para devolver
}

local function deep_fill(t, d)
	for k, v in pairs(d) do
		if t[k] == nil then
			if type(v) == "table" then t[k] = {} ; deep_fill(t[k], v) else t[k] = v end
		elseif type(v) == "table" and type(t[k]) == "table" then
			deep_fill(t[k], v)
		end
	end
	return t
end

local cfg = deep_fill(json.load_file(CFG_FILE) or {}, defaults)
local function save_cfg() json.dump_file(CFG_FILE, cfg) end
-- efeitos do jogo nunca começam desligados
cfg.vs_walk_off = false
if not cfg.cursor_v17 then cfg.light_gizmo_op = 1; cfg.cursor_v17 = true end
if not cfg.cursor_v18 then cfg.cursor_mode = 5; cfg.cursor_v18 = true; save_cfg() end

-- Núcleo e teclas próprios do NASK Fighter
local imgui = require("NASK_Fighter/lang").ui   -- imgui com tradução (ver lang.lua)
local keys = require("NASK_Fighter/keys")
local NASK_FC = require("NASK_Fighter/core")
-- idiomas (carregado junto com o script; o require depois não acha a pasta autorun)
pcall(function() NASK_FC.lang = require("NASK_Fighter/lang") end)
if not NASK_FC.lang then
	NASK_FC.lang = { t = function(x) return x end, run = function(f, ...) return xpcall(f, debug.traceback, ...) end,
		dl = function(d) return d end, set = function() end, LANGS = { { id = "pt", name = "Português (Brasil)" } }, lang = "pt" }
end

keys.define("NASK Abrir HUD", "Home")
keys.define("NASK Girar Esquerda", "OEM_COMMA")
keys.define("NASK Girar Direita", "OEM_PERIOD")
keys.define("NASK Zerar Inclinacao", "V")
keys.define("NASK Foto", "Scroll")
keys.define("NASK Portatil", "F3")
keys.define("NASK Preview Vertical", "Prior")
keys.define("NASK Abrir MMDK", "M")


-- ---------------------------------------------------------------------------
-- Tema: branco fosco -> acrílico semitransparente
-- ---------------------------------------------------------------------------
local title_font, sub_font = nil, nil
local last_errors = {}
local shown_error = nil
local report_error
local function rgba(r, g, b, a)
	a = math.floor(math.max(0, math.min(1, a)) * 255 + 0.5)
	return (a << 24) | (b << 16) | (g << 8) | r
end

local ACCENTS = {
	{ name = "Roxo",  c = { 124, 77, 230 } },
	{ name = "Lilás", c = { 150, 110, 235 } },
	{ name = "Rosa",  c = { 214, 74, 170 } },
}

-- tema Pedra (v2.6.2): degradê rosa -> lilás do PSD "Novo Projeto"
local function accent(a)
	if (cfg.style == 4 or cfg.style == 5) then return rgba(206, 160, 228, a or 1.0) end
	local c = ACCENTS[cfg.accent] or ACCENTS[1]
	return rgba(c.c[1], c.c[2], c.c[3], a or 1.0)
end

local INK   = rgba(38, 30, 56, 1.0)     -- texto principal
local MUTED = rgba(104, 94, 128, 1.0)   -- texto secundário
local WARN  = rgba(200, 60, 60, 1.0)
local WHITE = rgba(255, 255, 255, 1.0)

-- Vidro = cartão de vidro escuro do PSD de referência (preenchimento escuro
-- translúcido, brilho branco fraco, borda clara de 1 px, texto branco).
-- Acrílico = tema branco antigo.
if (cfg.theme_v or 0) < 215 then cfg.style = 2; cfg.theme_v = 215 end
cfg.vpreview = false
local function glass() return cfg.style == 1 or cfg.style == 3 or cfg.style == 4 or cfg.style == 5 end
local BG_RGB = { 247, 246, 251 }
local function apply_palette()
	if (cfg.style == 4 or cfg.style == 5) then
		-- vidro fosco frio (pedras molhadas), texto branco
		INK, MUTED, WARN = rgba(250, 248, 252, 1.0), rgba(214, 206, 228, 1.0), rgba(255, 140, 150, 1.0)
		BG_RGB = { 54, 70, 82 }
	elseif glass() then
		INK, MUTED, WARN = rgba(246, 244, 250, 1.0), rgba(196, 189, 212, 1.0), rgba(255, 120, 120, 1.0)
		BG_RGB = { 40, 34, 52 }
	else
		INK, MUTED, WARN = rgba(38, 30, 56, 1.0), rgba(104, 94, 128, 1.0), rgba(200, 60, 60, 1.0)
		BG_RGB = { 247, 246, 251 }
	end
end
local function bg_col(a) return rgba(BG_RGB[1], BG_RGB[2], BG_RGB[3], a) end

local Col = {
	Text = 0, TextDisabled = 1, WindowBg = 2, ChildBg = 3, PopupBg = 4, Border = 5, BorderShadow = 6,
	FrameBg = 7, FrameBgHovered = 8, FrameBgActive = 9,
	TitleBg = 10, TitleBgActive = 11,
	ScrollbarBg = 14, ScrollbarGrab = 15, ScrollbarGrabHovered = 16, ScrollbarGrabActive = 17,
	CheckMark = 18, SliderGrab = 19, SliderGrabActive = 20,
	Button = 21, ButtonHovered = 22, ButtonActive = 23,
	Header = 24, HeaderHovered = 25, HeaderActive = 26,
	Separator = 27, ResizeGrip = 30, ResizeGripHovered = 31, ResizeGripActive = 32,
}
local Var = {
	WindowPadding = 2, WindowRounding = 3, WindowBorderSize = 4,
	ChildRounding = 7, FramePadding = 11, FrameRounding = 12, FrameBorderSize = 13,
	ItemSpacing = 14, ScrollbarSize = 18, ScrollbarRounding = 19, GrabMinSize = 20, GrabRounding = 21,
}

local pushed_colors, pushed_vars = 0, 0
local function pc(idx, col)
	if pcall(imgui.push_style_color, idx, col) then pushed_colors = pushed_colors + 1 end
end
local function pv(idx, val)
	if pcall(imgui.push_style_var, idx, val) then pushed_vars = pushed_vars + 1 end
end

-- Imagem nítida via plugin reframework-d2d (desenhada por baixo do HUD).
-- Sem o plugin, cai na versão em grade acima.
local HEADER_ASPECT = 3605 / 908
local BANNER_SLOTS = 5
-- banners que já vêm no pacote (ficam nos índices 101, 102, 103)
local BANNER_PRESETS = { "Elena", "C. Viper & Elena", "Manon", "Grafite neon", "Beco grafitado", "Estou te assistindo" }
local d2d_imgs, d2d_rect, d2d_ready = { banners = {}, thumbs = {} }, nil, false
local gal_draw = {}      -- miniaturas a desenhar neste frame (x, y, w, h, key)
-- modo foto Portátil (janela simplificada com o cartão de vidro do PSD)
local port = { open = false, rect = nil, dof_rect = nil, hovered = false, glass_rects = {} }
-- corpo dos painéis abertos. No tema Nery: um pouco mais escuro, sem moldura, com
-- uma linha só em cima que vai até o fim do HUD sumindo (no lugar do retângulo).
port.rect_h, port.rect_stack, port.rect_n = {}, {}, 0
function port.rect_begin()
	if cfg.style ~= 4 then imgui.begin_rect() return end
	port.rect_n = port.rect_n + 1
	local n = port.rect_n
	local p = imgui.get_cursor_screen_pos()
	local cp = imgui.get_cursor_pos()
	local wx0 = p.x - 6
	local wx1 = p.x - cp.x + imgui.get_window_size().x - 4
	local h = port.rect_h[n] or 0
	pcall(function()
		local dl = imgui.get_window_draw_list()
		if h > 0 then
			dl:add_rect_filled(Vector2f.new(wx0, p.y - 6), Vector2f.new(wx1, p.y + h + 4), rgba(14, 20, 30, 0.16), 10, 0)
		end
		local a, b = rgba(255, 255, 255, 0.45), rgba(255, 255, 255, 0)
		dl:add_rect_filled_multi_color(Vector2f.new(wx0 + 4, p.y - 6), Vector2f.new(wx1, p.y - 5), a, b, b, a)
	end)
	table.insert(port.rect_stack, { n = n, y0 = p.y })
	imgui.indent(4)
end
function port.rect_end()
	if cfg.style ~= 4 then imgui.end_rect(2) return end
	imgui.unindent(4)
	local top = table.remove(port.rect_stack)
	if top then port.rect_h[top.n] = imgui.get_cursor_screen_pos().y - top.y0 end
end
port.GLASS_IDS = { 1, 3, 4, 7, 9, 10 }
port.GLASS_NAMES = { "Rosa e lilás", "Verde e azul", "A.K.I.", "Chun-Li", "Grafite neon", "Beco grafitado" }
-- "Seu fundo": a imagem da pessoa preenche a janela inteira, como os fundos prontos
-- (o tutorial pede a proporção do HUD, 800 x 1126, para não esticar).
function port.blur_image(img, g)
	d2d.image(img, g.x, g.y, g.w, g.h, g.a or 1.0)
end
-- estilo Vidro: textura de vidro fosco (do PSD) com degradê de desfoque
function port.glass_tex()
	return cfg.style == 3 and d2d_ready and cfg.d2d_on ~= false and d2d_imgs.glass ~= nil and (d2d_imgs.glass[cfg.glass_bg or 1] or d2d_imgs.glass[1]) ~= nil
end

-- imagens do NASK ficam em reframework/images/NASK_Fighter/ (o d2d só lê da pasta images)
function port.img(name)
	local ok, img = pcall(d2d.Image.new, "NASK_Fighter/" .. name)
	if ok and img then return img end
	ok, img = pcall(d2d.Image.new, name)
	return ok and img or nil
end

if d2d and d2d.register then
	d2d.register(function()
		d2d_imgs.banners = {}
		d2d_imgs.thumbs = {}
		for i, e in ipairs(cfg.gallery or {}) do
			if i > 80 then break end
			if e.thumb and e.thumb:find("^nask_thumbs/") then
				pcall(function() d2d_imgs.thumbs[e.thumb] = d2d.Image.new(e.thumb) end)
			end
		end
		pcall(function() d2d_imgs.small = port.img("nask_header_528.png") end)
		pcall(function() d2d_imgs.big = port.img("nask_header_1056.png") end)
		for i = 1, BANNER_SLOTS do
			pcall(function()
				local img = port.img("nask_banner_" .. i .. ".png")
				local w, h = img:size()
				if w and h and w > 0 and h > 0 then d2d_imgs.banners[i] = { img = img, w = w, h = h } end
			end)
		end
		for i = 1, #BANNER_PRESETS do
			pcall(function()
				local img = port.img("nask_preset_" .. i .. ".png")
				local w, h = img:size()
				if w and h and w > 0 and h > 0 then d2d_imgs.banners[100 + i] = { img = img, w = w, h = h } end
			end)
		end
		d2d_imgs.glass = {}
		for _, i in ipairs(port.GLASS_IDS) do
			pcall(function() d2d_imgs.glass[i] = port.img("nask_glass_" .. i .. ".png") end)
		end
		pcall(function() d2d_imgs.glass[8] = port.img("nask_glass_user.png") end)
		pcall(function()
			local img = port.img("nask_banner_user.png")
			local w, h = img:size()
			if w and h and w > 0 and h > 0 then d2d_imgs.banners[200] = { img = img, w = w, h = h } end
		end)
		pcall(function() d2d_imgs.profile = port.img("nask_profile.png") end)
		for _, nm in ipairs({ "card", "pill", "img" }) do
			pcall(function() d2d_imgs["port_" .. nm] = port.img("nask_port_" .. nm .. ".png") end)
		end
		d2d_ready = (d2d_imgs.small ~= nil or d2d_imgs.big ~= nil)
	end, function()
		-- imagens desligadas (REFramework que desenha o d2d por cima do ImGui)
		if cfg.d2d_on == false then return end
		-- barras pretas do preview vertical (primeiro: tudo o resto fica por cima)
		local vb = port.vp_bars
		if vb then
			d2d.fill_rect(0, 0, vb.x0, vb.h, 0xFF000000)
			d2d.fill_rect(vb.x0 + vb.w, 0, vb.dw - vb.x0 - vb.w, vb.h, 0xFF000000)
			d2d.outline_rect(vb.x0, 0, vb.w, vb.h, 1, 0x50FFFFFF)
		end
		-- fundo de vidro das janelas (estilo Vidro), por baixo de tudo
		local gi = d2d_imgs.glass and (d2d_imgs.glass[cfg.glass_bg or 1] or d2d_imgs.glass[1])
		if gi then
			if cfg.glass_bg == 8 then
				for _, g in ipairs(port.glass_rects) do port.blur_image(gi, g) end
			else
				for _, g in ipairs(port.glass_rects) do d2d.image(gi, g.x, g.y, g.w, g.h, g.a or 1.0) end
			end
		end
		-- cartão do Portátil (vidro), pílula e imagem dentro dela
		local dr = port.dof_rect
		if dr and d2d_imgs.port_pill then d2d.image(d2d_imgs.port_pill, dr.x, dr.y, dr.w, dr.h) end
		local pr = port.rect
		if pr then
			if d2d_imgs.port_card then d2d.image(d2d_imgs.port_card, pr.x, pr.y, pr.w, pr.h) end
			local pw = pr.w * 0.785
			local ph = pw / 3.19
			local px, py = pr.x + (pr.w - pw) * 0.5, pr.y + pr.h * 0.071
			if d2d_imgs.port_pill then d2d.image(d2d_imgs.port_pill, px, py, pw, ph) end
			if d2d_imgs.port_img then d2d.image(d2d_imgs.port_img, px + pw * 0.016, py + ph * 0.05, pw * 0.968, ph * 0.90) end
		end
		local r = d2d_rect
		if not r then return end
		local b = (cfg.banner or 0) > 0 and d2d_imgs.banners[cfg.banner]
		local img = (b and b.img) or (r.w <= 700 and d2d_imgs.small) or d2d_imgs.big or d2d_imgs.small
		if img then d2d.image(img, r.x, r.y, r.w, r.h) end
		for _, g in ipairs(gal_draw) do
			local t = d2d_imgs.thumbs[g.key]
			if t then d2d.image(t, g.x, g.y, g.w, g.h) end
		end
		local pf = port.profile_draw
		if pf and d2d_imgs.profile then d2d.image(d2d_imgs.profile, pf.x, pf.y, pf.w, pf.h) end
	end)
end
-- faz o d2d rodar as funções de init de novo (carrega imagens novas)
local function d2d_reload()
	if d2d and d2d.register then pcall(d2d.register, function() end, function() end) end
end

local function header_aspect()
	local b = d2d_ready and (cfg.banner or 0) > 0 and d2d_imgs.banners[cfg.banner]
	if b then return b.w / b.h end
	return HEADER_ASPECT
end
local function use_d2d() return d2d_ready and cfg.d2d_on ~= false and cfg.header_quality > 1 end


local function window_bg(a)
	return bg_col((a or 1.0) * cfg.opacity)
end

local function push_theme()
	apply_palette()
	pushed_colors, pushed_vars = 0, 0
	NASK_FC.font_pushed = false
	if NASK_FC.lang_needs_font() then
		NASK_FC.font_pushed = pcall(imgui.push_font, NASK_FC.fonts.main)
	end
	local g = glass()
	local W = function(al) return rgba(255, 255, 255, al) end
	pc(Col.WindowBg,             (use_d2d() or port.glass_tex()) and rgba(0, 0, 0, 0) or window_bg())
	pc(Col.ChildBg,              rgba(255, 255, 255, 0.0))
	pc(Col.PopupBg,              g and rgba(40, 36, 52, 0.97) or rgba(250, 249, 253, 0.97))
	pc(Col.Border,               g and W(0.42) or W(0.85))
	pc(Col.BorderShadow,         rgba(0, 0, 0, 0.0))
	pc(Col.Text,                 INK)
	pc(Col.TextDisabled,         g and rgba(150, 144, 170, 1.0) or rgba(150, 142, 170, 1.0))
	pc(Col.FrameBg,              g and W(0.09) or W(0.62))
	pc(Col.FrameBgHovered,       g and W(0.16) or rgba(238, 232, 255, 0.85))
	pc(Col.FrameBgActive,        accent(g and 0.40 or 0.22))
	pc(Col.TitleBg,              window_bg())
	pc(Col.TitleBgActive,        window_bg())
	pc(Col.ScrollbarBg,          rgba(0, 0, 0, 0.0))
	pc(Col.ScrollbarGrab,        g and W(0.22) or accent(0.30))
	pc(Col.ScrollbarGrabHovered, g and W(0.35) or accent(0.50))
	pc(Col.ScrollbarGrabActive,  accent(0.70))
	pc(Col.CheckMark,            g and WHITE or accent(1.0))
	pc(Col.SliderGrab,           accent(0.85))
	pc(Col.SliderGrabActive,     accent(1.0))
	pc(Col.Button,               g and W(0.08) or W(0.70))
	pc(Col.ButtonHovered,        g and W(0.18) or accent(0.18))
	pc(Col.ButtonActive,         accent(g and 0.55 or 0.35))
	pc(Col.Header,               g and W(0.07) or accent(0.14))
	pc(Col.HeaderHovered,        g and W(0.14) or accent(0.24))
	pc(Col.HeaderActive,         accent(g and 0.45 or 0.34))
	pc(Col.Separator,            g and W(0.18) or rgba(120, 100, 170, 0.22))
	pc(Col.ResizeGrip,           (cfg.style == 4) and rgba(0, 0, 0, 0) or (g and W(0.10) or accent(0.15)))
	pc(Col.ResizeGripHovered,    (cfg.style == 4) and accent(0.25) or accent(0.40))
	pc(Col.ResizeGripActive,     accent(0.70))

	pv(Var.WindowRounding, 14.0)
	pv(Var.WindowBorderSize, 1.0)
	pv(Var.ChildRounding, 10.0)
	pv(Var.FrameRounding, glass() and 10.0 or 8.0)
	pv(Var.FrameBorderSize, 1.0)
	pv(Var.GrabRounding, 8.0)
	pv(Var.ScrollbarRounding, 8.0)
	pv(Var.ScrollbarSize, 9.0)
	pv(Var.GrabMinSize, 12.0)
	pv(Var.WindowPadding, Vector2f.new(14, 12))
	pv(Var.FramePadding, Vector2f.new(9, 5))
	pv(Var.ItemSpacing, Vector2f.new(8, 7))
end

local function pop_theme()
	if pushed_vars > 0 then pcall(imgui.pop_style_var, pushed_vars) end
	if pushed_colors > 0 then pcall(imgui.pop_style_color, pushed_colors) end
	pushed_colors, pushed_vars = 0, 0
	if NASK_FC.font_pushed then pcall(imgui.pop_font); NASK_FC.font_pushed = false end
end

pcall(function() title_font = imgui.load_font(nil, 26) end)
pcall(function() port.font = imgui.load_font("NASK_Oswald-Bold.ttf", 30) end)
pcall(function() sub_font = imgui.load_font(nil, 15) end)
NASK_FC.fonts = { base_title = title_font, base_sub = sub_font }
-- (japonês/russo precisariam de outra fonte; por enquanto só português e inglês)
function NASK_FC.lang_needs_font() return false end
function NASK_FC.apply_lang_fonts() end
NASK_FC.lang.set(cfg.lang or "en")   -- primeira vez: inglês (até escolher no seletor)
NASK_FC.apply_lang_fonts()

-- Imagem do cabeçalho (pré-convertida em grade de degradês)
local header = nil
pcall(function() header = require("NASK_Fighter/header") end)

local hv1, hv2 = Vector2f.new(0, 0), Vector2f.new(0, 0)
local header_ok = true
local function draw_header_image(dl, x, y, w)
	local g = header and header[(cfg.header_quality == 3) and "alta" or "normal"]
	if not g or not header_ok then return 0 end
	local s = w / g.w
	local d = g.d
	local add = dl.add_rect_filled_multi_color
	header_ok = pcall(function()
		for i = 1, #d, 8 do
			hv1.x = x + d[i] * s;     hv1.y = y + d[i + 1] * s
			hv2.x = x + d[i + 2] * s; hv2.y = y + d[i + 3] * s
			add(dl, hv1, hv2, d[i + 4], d[i + 5], d[i + 6], d[i + 7])
		end
	end)
	return g.h * s
end


-- Listas de desenho. REFramework antigo (v1.5.9 com ImGui 1.90) não tem
-- get_window_draw_list / get_foreground_draw_list; nesse caso o HUD usa um
-- substituto feito com as funções draw.* (desenham atrás das janelas do ImGui).
local HAS_DL = imgui.get_window_draw_list ~= nil
local HAS_FG = imgui.get_foreground_draw_list ~= nil

local shim = {}
local function shim_tri(a, b, c, col)
	draw.filled_quad(a.x, a.y, b.x, b.y, c.x, c.y, c.x, c.y, col)
end
local function shim_pie(cx, cy, r, a0, a1, col)
	local n = 6
	for k = 0, n - 1 do
		local t0 = a0 + (a1 - a0) * k / n
		local t1 = a0 + (a1 - a0) * (k + 1) / n
		draw.filled_quad(cx, cy, cx + math.cos(t0) * r, cy + math.sin(t0) * r,
			cx + math.cos(t1) * r, cy + math.sin(t1) * r, cx + math.cos(t1) * r, cy + math.sin(t1) * r, col)
	end
end
function shim.add_rect_filled(self, a, b, col, r, flags)
	local x0, y0, x1, y1 = a.x, a.y, b.x, b.y
	if x1 <= x0 or y1 <= y0 then return end
	r = math.min(r or 0, (x1 - x0) * 0.5, (y1 - y0) * 0.5)
	if r <= 0.5 then draw.filled_rect(x0, y0, x1 - x0, y1 - y0, col) return end
	flags = flags or 0
	if (flags & 0xF0) == 0 then flags = 0xF0 end
	local tl, tr, bl, br = (flags & 16) ~= 0, (flags & 32) ~= 0, (flags & 64) ~= 0, (flags & 128) ~= 0
	local PI = math.pi
	-- faixa de cima
	local ax, bx = x0 + (tl and r or 0), x1 - (tr and r or 0)
	draw.filled_rect(ax, y0, bx - ax, r, col)
	if tl then shim_pie(x0 + r, y0 + r, r, PI, PI * 1.5, col) end
	if tr then shim_pie(x1 - r, y0 + r, r, PI * 1.5, PI * 2, col) end
	-- meio
	if y1 - r > y0 + r then draw.filled_rect(x0, y0 + r, x1 - x0, (y1 - r) - (y0 + r), col) end
	-- faixa de baixo
	ax, bx = x0 + (bl and r or 0), x1 - (br and r or 0)
	draw.filled_rect(ax, y1 - r, bx - ax, r, col)
	if bl then shim_pie(x0 + r, y1 - r, r, PI * 0.5, PI, col) end
	if br then shim_pie(x1 - r, y1 - r, r, 0, PI * 0.5, col) end
end
local function lerp_col(c1, c2, t)
	local out = 0
	for sh = 0, 24, 8 do
		local a, b = (c1 >> sh) & 0xFF, (c2 >> sh) & 0xFF
		out = out | (math.floor(a + (b - a) * t + 0.5) << sh)
	end
	return out
end
function shim.add_rect_filled_multi_color(self, a, b, c_tl, c_tr, c_br, c_bl)
	local n = 10
	local h = (b.y - a.y) / n
	if h <= 0 then return end
	for k = 0, n - 1 do
		local col = lerp_col(c_tl, c_bl, (k + 0.5) / n)
		if (col >> 24) > 0 then draw.filled_rect(a.x, a.y + h * k, b.x - a.x, h + 0.5, col) end
	end
end
function shim.add_text(self, p, col, text) draw.text(text, p.x, p.y, col) end
function shim.add_rect(self, a, b, col) draw.outline_rect(a.x, a.y, b.x - a.x, b.y - a.y, col) end
function shim.add_triangle_filled(self, a, b, c, col) shim_tri(a, b, c, col) end
function shim.add_triangle(self, a, b, c, col)
	draw.line(a.x, a.y, b.x, b.y, col); draw.line(b.x, b.y, c.x, c.y, col); draw.line(c.x, c.y, a.x, a.y, col)
end
function shim.add_quad_filled(self, a, b, c, d, col)
	draw.filled_quad(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y, col)
end

shim._path = {}
function shim.path_clear(self) self._path = {} end
function shim.path_line_to(self, p) table.insert(self._path, { p.x, p.y }) end
function shim.path_arc_to(self, c, r, a0, a1, n)
	n = n or 10
	for k = 0, n do
		local t = a0 + (a1 - a0) * k / n
		table.insert(self._path, { c.x + math.cos(t) * r, c.y + math.sin(t) * r })
	end
end
function shim.path_fill_concave(self, col)
	local pts = self._path
	self._path = {}
	local n = #pts
	if n < 3 then return end
	local area = 0
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		area = area + a[1] * b[2] - b[1] * a[2]
	end
	local sgn = area >= 0 and 1 or -1
	local idx = {}
	for i = 1, n do idx[i] = i end
	local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
	local guard = 0
	while #idx > 3 and guard < 4000 do
		guard = guard + 1
		local found = false
		for i = 1, #idx do
			local ia, ib, ic = idx[(i - 2) % #idx + 1], idx[i], idx[i % #idx + 1]
			local A, B, Cc = pts[ia], pts[ib], pts[ic]
			if cross(A, B, Cc) * sgn > 0 then
				local inside = false
				for _, j in ipairs(idx) do
					if j ~= ia and j ~= ib and j ~= ic then
						local P = pts[j]
						if cross(A, B, P) * sgn >= 0 and cross(B, Cc, P) * sgn >= 0 and cross(Cc, A, P) * sgn >= 0 then inside = true break end
					end
				end
				if not inside then
					draw.filled_quad(A[1], A[2], B[1], B[2], Cc[1], Cc[2], Cc[1], Cc[2], col)
					table.remove(idx, i)
					found = true
					break
				end
			end
		end
		if not found then break end
	end
	if #idx == 3 then
		local A, B, Cc = pts[idx[1]], pts[idx[2]], pts[idx[3]]
		draw.filled_quad(A[1], A[2], B[1], B[2], Cc[1], Cc[2], Cc[1], Cc[2], col)
	end
end
function shim.add_line(self, a, b, col) draw.line(a.x, a.y, b.x, b.y, col) end

local function window_dl()
	if HAS_DL then return NASK_FC.lang.dl(imgui.get_window_draw_list()) end
	return NASK_FC.lang.dl(shim)
end
local function front_dl()
	if HAS_FG then return NASK_FC.lang.dl(imgui.get_foreground_draw_list()) end
	return NASK_FC.lang.dl(shim)
end

-- Botão colorido (abas e toggles)
local function colored_button(label, active, size)
	local n = 0
	if active then
		if pcall(imgui.push_style_color, Col.Button, accent(0.92)) then n = n + 1 end
		if pcall(imgui.push_style_color, Col.ButtonHovered, accent(1.0)) then n = n + 1 end
		if pcall(imgui.push_style_color, Col.Text, WHITE) then n = n + 1 end
	end
	local clicked = imgui.button(label, size)
	if n > 0 then imgui.pop_style_color(n) end
	return clicked
end

local function tooltip(text)
	if imgui.is_item_hovered() then imgui.set_tooltip(text) end
end

-- botão de vidro (pílula translúcida com borda clara); active = aceso na cor de destaque
local function glass_button(id, label, active, w, h)
	local p = imgui.get_cursor_screen_pos()
	local clicked = imgui.invisible_button(id, Vector2f.new(w, h))
	local hov = imgui.is_item_hovered()
	local held = imgui.is_item_active()
	pcall(function()
		local dl = window_dl()
		local a, b = Vector2f.new(p.x, p.y), Vector2f.new(p.x + w, p.y + h)
		local r = h * 0.5
		local g = glass()
		-- corpo: vidro (véu claro fraco) ou aceso na cor de destaque
		local body
		if active then body = accent(held and 0.85 or (hov and 0.75 or 0.62))
		elseif g then body = rgba(255, 255, 255, held and 0.20 or (hov and 0.14 or 0.08))
		else body = rgba(120, 112, 140, held and 0.42 or (hov and 0.34 or 0.26)) end
		dl:add_rect_filled(a, b, body, r, 0)
		-- brilho na metade de cima
		dl:add_rect_filled(Vector2f.new(a.x + 2, a.y + 2), Vector2f.new(b.x - 2, a.y + h * 0.5), rgba(255, 255, 255, g and 0.07 or 0.25), r - 2, 48)
		-- contorno claro (como o botão do PSD)
		dl:add_rect(a, b, rgba(255, 255, 255, g and 0.85 or 0.95), r, 0, 1.2)
		-- texto
		if sub_font then imgui.push_font(sub_font) end
		local ts = imgui.calc_text_size(label)
		dl:add_text(Vector2f.new(p.x + (w - ts.x) * 0.5, p.y + (h - ts.y) * 0.5), (active or g) and WHITE or INK, label)
		if sub_font then imgui.pop_font() end
	end)
	return clicked
end

-- ícone de teclado com legenda em cima; devolve true no clique
local function keyboard_button(id, caption, w, h)
	local p = imgui.get_cursor_screen_pos()
	local clicked = imgui.invisible_button(id, Vector2f.new(w, h))
	local hov = imgui.is_item_hovered()
	pcall(function()
		local dl = window_dl()
		local col = hov and accent(1.0) or INK
		local ts = imgui.calc_text_size(caption)
		dl:add_text(Vector2f.new(p.x + (w - ts.x) * 0.5, p.y), hov and accent(1.0) or MUTED, caption)
		-- teclado
		local kw, kh = math.min(w - 8, 58), 26
		local kx, ky = p.x + (w - kw) * 0.5, p.y + ts.y + 4
		dl:add_rect_filled(Vector2f.new(kx, ky), Vector2f.new(kx + kw, ky + kh), rgba(255, 255, 255, hov and 0.16 or 0.08), 6, 0)
		dl:add_rect(Vector2f.new(kx, ky), Vector2f.new(kx + kw, ky + kh), col, 6, 0, 1.3)
		local cols, s = 6, (kw - 10) / 6
		for row = 0, 1 do
			for k = 0, cols - 1 do
				local x0 = kx + 5 + k * s
				local y0 = ky + 4 + row * 7
				dl:add_rect_filled(Vector2f.new(x0 + 1, y0), Vector2f.new(x0 + s - 1, y0 + 5), col, 1.2, 0)
			end
		end
		dl:add_rect_filled(Vector2f.new(kx + 5 + s, ky + 18), Vector2f.new(kx + kw - 5 - s, ky + 22), col, 1.2, 0)
	end)
	return clicked
end

-- ícone de câmera com legenda em cima (abre o Portátil)
function port.camera_button(id, caption, w, h)
	local p = imgui.get_cursor_screen_pos()
	local clicked = imgui.invisible_button(id, Vector2f.new(w, h))
	local hov = imgui.is_item_hovered()
	pcall(function()
		local dl = window_dl()
		local col = (hov or port.open) and accent(1.0) or INK
		local ts = imgui.calc_text_size(caption)
		dl:add_text(Vector2f.new(p.x + (w - ts.x) * 0.5, p.y), (hov or port.open) and accent(1.0) or MUTED, caption)
		local cw, ch = 40, 26
		local cx, cy = p.x + (w - cw) * 0.5, p.y + ts.y + 4
		dl:add_rect_filled(Vector2f.new(cx + 9, cy - 3), Vector2f.new(cx + 19, cy + 2), col, 1.5, 0)
		dl:add_rect_filled(Vector2f.new(cx, cy), Vector2f.new(cx + cw, cy + ch), rgba(255, 255, 255, hov and 0.16 or 0.08), 6, 0)
		dl:add_rect(Vector2f.new(cx, cy), Vector2f.new(cx + cw, cy + ch), col, 6, 0, 1.3)
		dl:add_circle(Vector2f.new(cx + cw * 0.5, cy + ch * 0.54), 7.5, col, 20, 1.6)
		dl:add_circle_filled(Vector2f.new(cx + cw * 0.5, cy + ch * 0.54), 3.0, col, 12)
		dl:add_circle_filled(Vector2f.new(cx + cw - 6, cy + 5), 1.6, col, 8)
	end)
	return clicked
end

-- Limpar imagem (usado pela aba Modo Foto e pelo Portátil)
function port.set_clean(clean)
	if clean then
		nask_clean_prev_vs = cfg.vs_walk_off
		cfg.vs_walk_off = true
	else
		cfg.vs_walk_off = nask_clean_prev_vs or false
	end
	save_cfg()
	NASK_FC.set_clean(clean)
end

-- Preview vertical: centraliza a faixa 9:16 (imagem em pé) e cobre as laterais de preto.
-- A rotação da imagem e o DOF ficam em core.lua (set_vpreview / vp_dof_apply).
function port.draw_vpreview()
	local d = imgui.get_display_size()
	local h = d.y
	local w = h * 9 / 16
	local x0 = (d.x - w) * 0.5
	if x0 <= 0 then return end
	-- com o d2d, as barras vão na mesma camada das imagens e ANTES delas,
	-- assim não cobrem o banner do HUD
	if use_d2d() then
		port.vp_bars = { x0 = x0, w = w, h = h, dw = d.x }
		return
	end
	local black = 0xFF000000
	draw.filled_rect(0, 0, x0, h, black)
	draw.filled_rect(x0 + w, 0, d.x - x0 - w, h, black)
	draw.outline_rect(x0, 0, w, h, 0x50FFFFFF)
end

-- opção do Portátil: texto grande; aceso = branco com risco de luz, apagado = translúcido
function port.option(id, label, on, cx, cy)
	if port.font then imgui.push_font(port.font) end
	local ts = imgui.calc_text_size(label)
	local x, y = cx - ts.x * 0.5, cy - ts.y * 0.5
	imgui.set_cursor_pos(Vector2f.new(x, y))
	local p = imgui.get_cursor_screen_pos()
	local clicked = imgui.invisible_button(id, Vector2f.new(ts.x, ts.y))
	local hov = imgui.is_item_hovered()
	pcall(function()
		local dl = window_dl()
		local col = on and rgba(255, 255, 255, 1.0) or rgba(255, 255, 255, hov and 0.80 or 0.48)
		dl:add_text(Vector2f.new(p.x + 1, p.y + 2), rgba(0, 0, 0, 0.25), label)
		dl:add_text(p, col, label)
		if on then
			dl:add_line(Vector2f.new(p.x + ts.x * 0.2, p.y + ts.y + 2), Vector2f.new(p.x + ts.x * 0.8, p.y + ts.y + 2), accent(1.0), 3.0)
		end
	end)
	if port.font then imgui.pop_font() end
	return clicked
end

function port.dof_slider(label, key, lo, hi, fmt, y, ws)
	local v = NASK_FC.dof_value(key)
	if not v then return end
	imgui.set_cursor_pos(Vector2f.new(ws.x * 0.14, y))
	imgui.push_item_width(ws.x * 0.50)
	-- arraste fino (0.01 por pixel, como no HUD); Ctrl+clique digita o valor
	local ch, nv = imgui.drag_float("##pd" .. key, v, 0.01, lo, hi, fmt)
	imgui.pop_item_width()
	if ch then NASK_FC.set_dof_value(key, nv) end
	imgui.same_line()
	imgui.text_colored(label, rgba(255, 255, 255, 0.85))
end

function port.draw()
	local dof_on = NASK_FC.get_dof()
	local W, H = 400, dof_on and 536 or 380
	local disp = imgui.get_display_size()
	imgui.set_next_window_pos(Vector2f.new(40, math.max(40, disp.y * 0.5 - H * 0.5)), 4)
	imgui.set_next_window_size(Vector2f.new(W, H), 1)
	imgui.push_style_color(Col.WindowBg, 0)
	imgui.push_style_color(Col.Border, 0)
	imgui.push_style_var(Var.WindowPadding, Vector2f.new(0, 0))
	-- 1 sem título, 2 sem redimensionar, 8 sem rolagem, 32 sem recolher
	imgui.begin_window("NASK Portatil##port", nil, 1 | 2 | 8 | 32)
	local ok, err = pcall(function()
		local wp, ws = imgui.get_window_pos(), imgui.get_window_size()
		port.rect = { x = wp.x, y = wp.y, w = ws.x, h = 380 }
		port.dof_rect = nil
		local cx = ws.x * 0.5
		if port.option("##p2x", "2x QUALITY", NASK_FC.get_hi_quality(), ws.x * 0.27, 380 * 0.47) then
			NASK_FC.set_hi_quality(not NASK_FC.get_hi_quality())
		end
		if port.option("##pcl", "CLEAN SCREEN", NASK_FC.clean == true, ws.x * 0.73, 380 * 0.47) then
			port.set_clean(not (NASK_FC.clean == true))
		end
		if port.option("##pvp", "VERTICAL PREVIEW", cfg.vpreview == true, cx, 380 * 0.62) then
			cfg.vpreview = not cfg.vpreview; save_cfg()
		end
		if port.option("##pdof", "DOF", dof_on, cx, 380 * 0.77) then
			NASK_FC.set_dof(not dof_on)
		end
		-- sliders pequenos do DOF numa pílula de vidro embaixo do cartão
		if dof_on and ws.y > 400 then
			local ph = 146
			port.dof_rect = { x = wp.x + 6, y = wp.y + 386, w = ws.x - 12, h = ph }
			imgui.push_style_color(Col.FrameBg, rgba(255, 255, 255, 0.14))
			imgui.push_style_color(Col.FrameBgHovered, rgba(255, 255, 255, 0.22))
			imgui.push_style_color(Col.FrameBgActive, rgba(255, 255, 255, 0.30))
			imgui.push_style_color(Col.SliderGrab, rgba(255, 255, 255, 0.95))
			imgui.push_style_color(Col.SliderGrabActive, accent(1.0))
			imgui.push_style_color(Col.Text, rgba(255, 255, 255, 1.0))
			port.dof_slider("Sensor Size", "sensor", 0.0, 100000.0, "%.3f", 386 + 22, ws)
			port.dof_slider("Focus Distance", "focus", 0.0, 100000.0, "%.3f", 386 + 58, ws)
			port.dof_slider("FNumber", "fnum", 0.0, 100000.0, "%.3f", 386 + 94, ws)
			imgui.pop_style_color(6)
		end
		-- fechar (canto de cima)
		imgui.set_cursor_pos(Vector2f.new(ws.x - 30, 8))
		if imgui.small_button("×##pclose") then port.open = false end
		local m = imgui.get_mouse()
		port.hovered = m and m.x >= wp.x and m.y >= wp.y and m.x <= wp.x + ws.x and m.y <= wp.y + ws.y or false
	end)
	imgui.end_window()
	imgui.pop_style_var(1)
	imgui.pop_style_color(2)
	if not ok then report_error("portátil", err) end
end

-- coloca itens numa linha (ou mais) centralizados.
-- items = { { w = largura, draw = function() ... end }, ... }
local function centered_row(items, gap)
	gap = gap or 14
	local avail = imgui.get_window_size().x - 2 * 14
	local rows, cur, cw = {}, {}, 0
	for _, it in ipairs(items) do
		local add = (#cur > 0 and gap or 0) + it.w
		if #cur > 0 and cw + add > avail then
			table.insert(rows, { items = cur, w = cw }); cur, cw = {}, 0; add = it.w
		end
		table.insert(cur, it); cw = cw + add
	end
	if #cur > 0 then table.insert(rows, { items = cur, w = cw }) end
	for _, row in ipairs(rows) do
		local y = imgui.get_cursor_pos().y
		local x = math.max(14, 14 + (avail - row.w) * 0.5)
		for i, it in ipairs(row.items) do
			if i > 1 then imgui.same_line() end
			imgui.set_cursor_pos(Vector2f.new(x, y))
			it.draw()
			x = x + it.w + gap
		end
	end
end

-- largura de uma caixa de seleção com texto
local function check_w(label)
	local t = imgui.calc_text_size((label:gsub("##.*$", "")))
	return t.y + 10 + 6 + t.x
end

local function section(title)
	imgui.spacing()
	imgui.text_colored(title, accent(1.0))
	imgui.separator()
end

local function hint(text) imgui.text_colored(text, MUTED) end

local function keyname(action) return keys.name_of(action) end

-- campo de texto: enquanto digita, as teclas do modo foto ficam bloqueadas
local function input(label, value, flags)
	local ch, v = imgui.input_text(label, value or "", flags or 0)
	if imgui.is_item_active() then keys.block(3) end
	return ch, v
end

-- ---------------------------------------------------------------------------
-- Cursor próprio (desenhado por cima de tudo)
-- ---------------------------------------------------------------------------
local cv1, cv2, cv3 = Vector2f.new(0, 0), Vector2f.new(0, 0), Vector2f.new(0, 0)
local function draw_cursor()
	local m = imgui.get_mouse()
	if not m or m.x < -10000 or m.y < -10000 then return end
	pcall(function()
		local dl = front_dl()
		cv1.x, cv1.y = m.x, m.y
		cv2.x, cv2.y = m.x, m.y + 19
		cv3.x, cv3.y = m.x + 13, m.y + 14
		dl:add_triangle_filled(cv1, cv2, cv3, WHITE)
		dl:add_triangle(cv1, cv2, cv3, accent(1.0), 1.6)
	end)
end

-- ---------------------------------------------------------------------------
-- Estado
-- ---------------------------------------------------------------------------
local hud_open = cfg.open_on_start
local nask_hide_game_cursor = false
local nask_clean_prev_vs = nil
local hovered = false
local TABS = { "Modo Foto", "Poser", "Luzes", "Console", "Galeria", "Animações", "HUD", "NASK" }
local TAB_GAL = 5
local keys_win = { open = false }


local function req(name)
	if NASK_FC then NASK_FC.req[name] = true end
end

local function sync_bridge()
	if not NASK_FC then return end
	NASK_FC.stick = cfg.stick
	NASK_FC.move_stick = cfg.move_stick
	NASK_FC.block_mouse = hud_open and cfg.block_mouse_hover and hovered
end

local changed


-- ---------------------------------------------------------------------------
-- Utilidades de cena
-- ---------------------------------------------------------------------------
local FIGHTERS = {
	[1] = "Ryu", [2] = "Luke", [3] = "Kimberly", [4] = "Chun-Li", [5] = "Manon",
	[6] = "Zangief", [7] = "JP", [8] = "Dhalsim", [9] = "Cammy", [10] = "Ken",
	[11] = "Dee Jay", [12] = "Lily", [13] = "A.K.I.", [14] = "Rashid", [15] = "Blanka",
	[16] = "Juri", [17] = "Marisa", [18] = "Guile", [19] = "Ed", [20] = "E. Honda",
	[21] = "Jamie", [22] = "Akuma", [25] = "Sagat", [26] = "M. Bison", [27] = "Terry",
	[28] = "Mai", [29] = "Elena", [30] = "C. Viper", [31] = "Alex", [32] = "Ingrid",
	[33] = "Yasmine",
}

local function current_scene()
	return sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
end

-- GameObjects que têm malha (estão sendo desenhados)
local function rendered_objects()
	local out = {}
	local arr = current_scene():call("findComponents(System.Type)", sdk.typeof("via.render.Mesh"))
	for _, mesh in ipairs(arr and arr:get_elements() or {}) do
		local go = mesh:call("get_GameObject")
		if go then table.insert(out, { go = go, mesh = mesh, name = go:call("get_Name") or "" }) end
	end
	return out
end

local function set_visible(go, vis)
	pcall(function() go:call("set_DrawSelf", vis) end)
end

-- O jogo reativa objetos/materiais todo frame durante a luta; o que o usuário
-- escondeu fica guardado aqui e é reaplicado depois do update do jogo.
local forced_vis, forced_mat, forced_comp = {}, {}, {}
local function addr(o) local ok, a = pcall(o.get_address, o); return ok and a or tostring(o) end
local function force_visible(go, vis)
	set_visible(go, vis)
	if vis then forced_vis[addr(go)] = nil else forced_vis[addr(go)] = go end
end
local function force_material(mesh, id, on)
	pcall(mesh.call, mesh, "setMaterialsEnable", id, on)
	local k = addr(mesh)
	forced_mat[k] = forced_mat[k] or { mesh = mesh, ids = {} }
	forced_mat[k].ids[id] = (not on) and true or nil
end
local function force_comp_enabled(comp, on)
	pcall(comp.call, comp, "set_Enabled", on)
	if on then forced_comp[addr(comp)] = nil else forced_comp[addr(comp)] = comp end
end
local function apply_forced()
	for k, go in pairs(forced_vis) do
		if not pcall(function() if go:call("get_DrawSelf") then go:call("set_DrawSelf", false) end end) then forced_vis[k] = nil end
	end
	for k, m in pairs(forced_mat) do
		local ok = pcall(function()
			for id in pairs(m.ids) do
				if m.mesh:call("getMaterialsEnable", id) then m.mesh:call("setMaterialsEnable", id, false) end
			end
		end)
		if not ok then forced_mat[k] = nil end
	end
	for k, c in pairs(forced_comp) do
		if not pcall(function() if c:call("get_Enabled") then c:call("set_Enabled", false) end end) then forced_comp[k] = nil end
	end
end
re.on_application_entry("PrepareRendering", apply_forced)
re.on_application_entry("BeginRendering", apply_forced)


-- ---------------------------------------------------------------------------
-- Luzes NASK: soltas da câmera, com gizmo e indicadores
-- ---------------------------------------------------------------------------
local nlights = { list = {}, sel = 0, counter = 0, gizmo_until = 0 }
local pending_xf = {}

local function nask_create_resource(resource_type, resource_path)
	local res = sdk.create_resource(resource_type, resource_path)
	if not res then return end
	res = res:add_ref()
	local holder = sdk.create_instance(resource_type .. "Holder", true)
	if holder then
		holder = holder:add_ref()
		holder:call(".ctor()")
		holder:write_qword(0x10, res:get_address())
		return holder
	end
end

local function cam_pos_rot()
	local cam = sdk.get_primary_camera()
	local cgo = cam and cam:call("get_GameObject")
	local cx = cgo and cgo:call("get_Transform")
	if not cx then return nil end
	local j = cx:call("getJointByName", "Camera")
	if j then return j:call("get_Position"), j:call("get_Rotation") end
	return cx:call("get_Position"), cx:call("get_Rotation")
end

local shadow_apply, shadow_has_fields
do
-- v2.6.0: ajuste fino da sombra das luzes (bias). Com bias baixo a sombra marca
-- cada detalhe da malha do personagem (shadow acne / listras). Os campos variam
-- por versão do motor, então o NASK só mexe nos que existirem nesta luz.
local SH_BIAS = { "ShadowBias", "ShadowDepthBias", "ShadowSlopeBias", "ShadowNormalBias" }
local SH_SOFT = { "ShadowVariance", "ShadowBlur", "ShadowBlurAmount" }
local sh_logged = false
local function sh_read(c, f)
	local ok, v = pcall(c.call, c, "get_" .. f)
	if ok and type(v) == "number" then return v end
end
local function shadow_capture(L)
	if L.sh0 then return end
	local c = L.light
	L.sh0 = {}
	local found = {}
	-- v2.6.22: procura no tipo da luz todo campo numérico de sombra com "bias",
	-- "variance", "blur" ou "softness" (os nomes mudam entre versões do motor)
	pcall(function()
		local t = c:get_type_definition()
		local seen = {}
		while t do
			for _, m in ipairs(t:get_methods()) do
				local n = m:get_name()
				local l = n:lower()
				if n:sub(1, 4) == "set_" and m:get_num_params() == 1 and not seen[n] then
					local fld = n:sub(5)
					local fl = fld:lower()
					local kind
					if fl:find("bias") then kind = "bias"
					elseif fl:find("shadow") and (fl:find("variance") or fl:find("blur") or fl:find("soft")) then kind = "soft" end
					if kind then
						seen[n] = true
						local v = sh_read(c, fld)
						if v then
							L.sh0[fld] = v
							L.shk = L.shk or {}
							L.shk[fld] = kind
							table.insert(found, fld .. "=" .. string.format("%.5f", v))
						end
					end
				end
			end
			t = t:get_parent_type()
			if t and t:get_full_name():find("^via%.Component") then break end
		end
	end)
	local v = sh_read(c, "ShadowNearPlane"); if v then L.sh0.ShadowNearPlane = v end
	sh_logged = (type(sh_logged) == "table") and sh_logged or {}
	if not sh_logged[L.kind] then
		sh_logged[L.kind] = true
		pcall(log.info, "[NASK] campos de sombra (" .. (L.kind == 1 and "Spot" or "Point") .. "): " .. (#found > 0 and table.concat(found, ", ") or "nenhum"))
	end
end
function shadow_apply(L)
	shadow_capture(L)
	local c, b = L.light, L.sh0
	-- v2.6.23: o jogo cria as luzes com bias 0 (o log mostrou), então multiplicar não
	-- fazia nada. Agora são valores diretos. ShadowLodBias e ShadowOccluderMaxSlopeBias
	-- não são o bias da sombra e ficam como estão.
	local bias = L.sh_b or 0.02
	local slope = L.sh_slope or 2.0
	local soft = L.sh_soft or 1.5
	if b.ShadowBias then pcall(c.call, c, "set_ShadowBias", bias) end
	if b.ShadowDepthBias then pcall(c.call, c, "set_ShadowDepthBias", bias) end
	if b.ShadowNormalBias then pcall(c.call, c, "set_ShadowNormalBias", bias) end
	if b.ShadowSlopeBias then pcall(c.call, c, "set_ShadowSlopeBias", slope) end
	if b.ShadowVariance then
		local v0 = (b.ShadowVariance > 1e-6) and b.ShadowVariance or 0.004
		pcall(c.call, c, "set_ShadowVariance", v0 * soft)
	end
end
function shadow_has_fields(L)
	shadow_capture(L)
	return next(L.sh0) ~= nil
end
end

local function light_apply(L)
	local c = L.light
	pcall(c.call, c, "setImportantLevel", 0)            -- não deixa o jogo cortar a luz
	pcall(c.call, c, "set_UsingSameIntensity", false)
	pcall(c.call, c, "set_VolumetricScatteringIntensity", L.volumetric or 0.0)
	pcall(c.call, c, "set_Enabled", L.enabled)
	pcall(c.call, c, "set_Color", L.color)
	pcall(c.call, c, "set_Intensity", L.intensity)
	pcall(c.call, c, "set_Radius", L.radius)
	pcall(c.call, c, "set_ShadowEnable", L.shadows)
	pcall(shadow_apply, L)
	if L.kind == 1 then
		pcall(c.call, c, "set_Cone", L.cone)
		pcall(c.call, c, "set_Spread", L.spread)
	end
	pcall(function() L.go:call("set_DrawSelf", L.enabled) end)
	pcall(c.call, c, "update")
end

local function create_light(kind, copy_from)
	nlights.msg = nil
	local ok, err = pcall(function()
		local o = NASK_FC.create_light(kind)
		if not o or not o.light then error("o jogo não criou a luz") end
		nlights.counter = nlights.counter + 1
		local L = {
			name = (kind == 1 and "Spot " or "Point ") .. nlights.counter, go = o.gameobj, light = o.light, xform = o.xform, kind = kind,
			enabled = true, shadows = true,
			color = copy_from and copy_from.color or Vector3f.new(1, 1, 1),
			intensity = copy_from and copy_from.intensity or ((kind == 1) and 5000.0 or 300.0),
			radius = copy_from and copy_from.radius or ((kind == 1) and 6.0 or 3.0),
			cone = copy_from and copy_from.cone or 60.0,
			spread = copy_from and copy_from.spread or 15.0,
			volumetric = copy_from and copy_from.volumetric or 0.0,
			sh_b = copy_from and copy_from.sh_b or 0.02,
			sh_slope = copy_from and copy_from.sh_slope or 2.0,
			sh_soft = copy_from and copy_from.sh_soft or 1.5,
		}
		if kind == 1 then pcall(function() L.light:set_Texture(nask_create_resource("via.render.TextureResource", "systems/rendering/nullwhite.tex")) end) end
		light_apply(L)
		if copy_from then
			table.insert(pending_xf, { xform = L.xform, pos = copy_from.xform:call("get_Position"), rot = copy_from.xform:call("get_Rotation") })
		elseif o.pos and o.rot then
			table.insert(pending_xf, { xform = L.xform, pos = o.pos, rot = o.rot })
		end
		table.insert(nlights.list, L)
		nlights.sel = #nlights.list
	end)
	if not ok then nlights.msg = "Erro ao criar luz: " .. tostring(err) end
end

local lg
local function light_valid(L)
	local ok, v = pcall(function() return L.xform:call("get_Valid") end)
	return ok and v ~= false
end

local function delete_light(i)
	local L = nlights.list[i]
	if L then pcall(function() L.go:call("destroy", L.go) end) end
	table.remove(nlights.list, i)
	if nlights.sel > #nlights.list then nlights.sel = #nlights.list end
end

-- posição/rotação de luzes novas precisa ser aplicada no UpdateMotion
re.on_application_entry("UpdateMotion", function()
	for _, L in ipairs(nlights.list) do
		if L.follow then
			local pos, rot = cam_pos_rot()
			if pos then pcall(function() L.xform:call("set_Position", pos); L.xform:call("set_Rotation", rot) end) end
		end
	end
	if #pending_xf == 0 then return end
	local list = pending_xf
	pending_xf = {}
	for _, p in ipairs(list) do
		pcall(function()
			p.xform:call("set_Position", p.pos)
			p.xform:call("set_Rotation", p.rot)
		end)
		p.release = true
	end
	nlights.release = list
end)

local function ui_lights()
	nlights.ui_t = os.clock()
	section("LUZES")
	local dl_on = NASK_FC.get_disable_lights()
	changed, dl_on = imgui.checkbox("Disable Lights", dl_on)
	if changed then NASK_FC.set_disable_lights(dl_on) end
	tooltip("Desliga todas as luzes do cenário (menos as luzes da câmera)")
	if imgui.button("+ Spot") then create_light(1) end
	tooltip("Luz direcional (cone). Nasce na posição da câmera, apontando para onde ela olha.")
	imgui.same_line()
	if imgui.button("+ Point") then create_light(2) end
	tooltip("Luz pontual (ilumina em todas as direções). Nasce 1,5 m à frente da câmera, fraca;\naumente a intensidade aos poucos.")
	imgui.same_line()
	changed, cfg.light_gizmo = imgui.checkbox("Gizmo", cfg.light_gizmo); if changed then save_cfg() end
	imgui.same_line()
	imgui.push_item_width(90)
	changed, cfg.light_gizmo_op = imgui.combo("##gop", cfg.light_gizmo_op, { "Mover", "Girar", "Ambos" }); if changed then save_cfg() end
	imgui.pop_item_width()
	tooltip("Mover: arraste as setas (X vermelho, Y verde, Z azul) ou o quadrado do centro\n(move na tela, mantendo a distância).\nGirar (Spot): arraste a bolinha da ponta para apontar a luz para onde o mouse está.")
	imgui.same_line()
	changed, cfg.light_lines = imgui.checkbox("Indicadores", cfg.light_lines); if changed then save_cfg() end
	tooltip("Mostra de onde a luz vem, a direção e o alcance (cone/esfera).\nSó aparece com o HUD aberto, não sai na foto.")
	if nlights.msg then imgui.text_colored(nlights.msg, WARN) end

	for i = #nlights.list, 1, -1 do
		if not light_valid(nlights.list[i]) then table.remove(nlights.list, i) end
	end
	if nlights.sel > #nlights.list then nlights.sel = #nlights.list end
	if #nlights.list == 0 then hint("Nenhuma luz criada.") return end

	for i, L in ipairs(nlights.list) do
		imgui.push_id("nl" .. i)
		changed, L.enabled = imgui.checkbox("##on", L.enabled)
		if changed then light_apply(L) end
		imgui.same_line()
		if colored_button("Editar##e" .. i, nlights.sel == i, Vector2f.new(60, 0)) then nlights.sel = i end
		imgui.same_line()
		if imgui.button("Mover para câmera") then
			local pos, rot = cam_pos_rot()
			if pos then table.insert(pending_xf, { xform = L.xform, pos = pos, rot = rot }) end
		end
		tooltip("Leva a luz para a posição e direção da câmera (uma vez)")
		imgui.same_line()
		if imgui.button("Duplicar") then create_light(L.kind, L) end
		imgui.same_line()
		if imgui.button("Excluir") then delete_light(i); imgui.pop_id(); return end
		imgui.same_line()
		imgui.text(L.name)
		imgui.pop_id()
	end

	local L = nlights.list[nlights.sel]
	if not L then return end
	imgui.spacing()
	port.rect_begin()
	imgui.text_colored(L.name, accent(1.0))
	local any = false
	changed, L.color = imgui.color_edit3("Cor", L.color, 17301504); any = any or changed
	imgui.push_item_width(-120)
	changed, L.intensity = imgui.drag_float("Intensidade", L.intensity, (L.kind == 1) and 25.0 or 2.0, 0.0, 200000.0, "%.0f"); any = any or changed
	changed, L.radius = imgui.slider_float("Alcance", L.radius, 0.1, 40.0, "%.2f m"); any = any or changed
	if L.kind == 1 then
		changed, L.cone = imgui.slider_float("Abertura", L.cone, 1.0, 170.0, "%.0f°"); any = any or changed
		changed, L.spread = imgui.slider_float("Suavidade da borda", L.spread, 0.0, 100.0, "%.0f"); any = any or changed
	end
	imgui.pop_item_width()
	imgui.push_item_width(-120)
	changed, L.volumetric = imgui.slider_float("Névoa da luz", L.volumetric or 0.0, 0.0, 50.0, "%.1f"); any = any or changed
	imgui.pop_item_width()
	tooltip("Brilho da luz na névoa volumétrica. Valores altos clareiam a tela toda.")
	changed, L.shadows = imgui.checkbox("Sombras", L.shadows); any = any or changed
	imgui.same_line()
	changed, L.follow = imgui.checkbox("Seguir câmera", L.follow == true)
	tooltip("Enquanto marcado, a luz anda junto com a câmera livre.\nVoe até onde quiser a luz e desmarque para soltá-la ali.")
	do
		local has = false
		pcall(function() has = shadow_has_fields(L) end)
		imgui.begin_disabled(not L.shadows)
		if has then
			imgui.push_item_width(-120)
			changed, L.sh_b = imgui.slider_float("Bias da sombra", L.sh_b or 0.02, 0.0, 0.2, "%.3f"); any = any or changed
			tooltip("Afasta a sombra da superfície. Suba se aparecer o relevo da malha, listras ou\npontinhos na pele/roupa. Alto demais: a sombra descola do objeto (fica \"flutuando\").")
			changed, L.sh_slope = imgui.slider_float("Bias de inclinação", L.sh_slope or 2.0, 0.0, 10.0, "%.2f"); any = any or changed
			tooltip("Mesmo efeito, mas mais forte nas superfícies inclinadas em relação à luz\n(onde o serrilhado da malha mais aparece).")
			changed, L.sh_soft = imgui.slider_float("Suavidade da sombra", L.sh_soft or 1.5, 0.2, 10.0, "%.1fx"); any = any or changed
			tooltip("Borda da sombra mais macia também esconde o serrilhado da malha.")
			imgui.pop_item_width()
			if imgui.button("Padrão##shd") then L.sh_b, L.sh_slope, L.sh_soft = 0.02, 2.0, 1.5; any = true end
		else
			hint("Esta luz não expõe ajuste de bias no jogo.")
		end
		imgui.end_disabled()
	end
	if any then light_apply(L) end

	section("POSIÇÃO LIVRE")
	hint("Use o gizmo na tela, o 'Seguir câmera' ou os campos abaixo (arraste ou Ctrl+clique para digitar).")
	local pos = L.xform:call("get_Position")
	changed, pos = imgui.drag_float3("Posição", pos, 0.01, -10000, 10000)
	if changed then L.xform:call("set_Position", pos) end
	if L.kind == 1 then
		-- direção como "para onde aponta": horizontal (yaw) e vertical (pitch), sem gimbal
		local d = lg.q_rot(L.xform:call("get_Rotation"), { 0, 0, -1 })
		local yaw = math.deg(math.atan(d[1], -d[3]))
		local pitch = math.deg(math.asin(math.max(-1, math.min(1, d[2]))))
		imgui.push_item_width(-120)
		local c1, c2
		c1, yaw = imgui.drag_float("Direção horizontal", yaw, 0.25, -180, 180, "%.1f°")
		c2, pitch = imgui.drag_float("Direção vertical", pitch, 0.25, -89.9, 89.9, "%.1f°")
		imgui.pop_item_width()
		if c1 or c2 then
			local y, pt = math.rad(yaw), math.rad(pitch)
			local nd = { math.sin(y) * math.cos(pt), math.sin(pt), -math.cos(y) * math.cos(pt) }
			L.xform:call("set_Rotation", lg.look_quat(nd))
		end
		if imgui.button("Apontar para onde a câmera olha") then
			local _, crot = cam_pos_rot()
			if crot then L.xform:call("set_Rotation", lg.look_quat(lg.q_rot(crot, { 0, 0, -1 }))) end
		end
	end
	port.rect_end()
end

-- ---------------------------------------------------------------------------
-- v2.6.0: projeção e gizmo próprios para as luzes
-- O world_to_screen/ImGuizmo do REFramework usa a matriz de câmera de antes da
-- câmera livre/FOV do NASK serem aplicados, então o ponto e o gizmo ficavam
-- deslocados. Aqui a projeção sai da câmera do jogo no momento do desenho.
-- ---------------------------------------------------------------------------
local draw_lights
do
lg = {}
local function v3(v) return { v.x, v.y, v.z } end
local function vadd(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function vsub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function vmul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
local function vdot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function vcross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function vlen(a) return math.sqrt(vdot(a, a)) end
local function vnorm(a) local l = vlen(a); if l < 1e-9 then return { 0, 0, -1 } end; return vmul(a, 1 / l) end
-- gira o vetor v pelo quaternion q (w,x,y,z)
function lg.q_rot(q, v)
	local qv = { q.x, q.y, q.z }
	local t = vmul(vcross(qv, v), 2)
	return vadd(vadd(v, vmul(t, q.w)), vcross(qv, t))
end
local function q_conj(q) return { w = q.w, x = -q.x, y = -q.y, z = -q.z } end
-- quaternion que faz o -Z local apontar para dir (luz/câmera do RE olham para -Z)
function lg.look_quat(dir)
	local z = vmul(vnorm(dir), -1)
	local up = (math.abs(z[2]) > 0.999) and { 0, 0, 1 } or { 0, 1, 0 }
	local x = vnorm(vcross(up, z))
	local y = vcross(z, x)
	local m00, m11, m22 = x[1], y[2], z[3]
	local tr = m00 + m11 + m22
	local w, qx, qy, qz
	if tr > 0 then
		local k = math.sqrt(tr + 1) * 2
		w = 0.25 * k; qx = (y[3] - z[2]) / k; qy = (z[1] - x[3]) / k; qz = (x[2] - y[1]) / k
	elseif m00 > m11 and m00 > m22 then
		local k = math.sqrt(1 + m00 - m11 - m22) * 2
		w = (y[3] - z[2]) / k; qx = 0.25 * k; qy = (y[1] + x[2]) / k; qz = (z[1] + x[3]) / k
	elseif m11 > m22 then
		local k = math.sqrt(1 + m11 - m00 - m22) * 2
		w = (z[1] - x[3]) / k; qx = (y[1] + x[2]) / k; qy = 0.25 * k; qz = (z[2] + y[3]) / k
	else
		local k = math.sqrt(1 + m22 - m00 - m11) * 2
		w = (x[2] - y[1]) / k; qx = (z[1] + x[3]) / k; qy = (z[2] + y[3]) / k; qz = 0.25 * k
	end
	return Quaternion.new(w, qx, qy, qz)
end
-- câmera do momento (posição, rotação, FOV vertical, tela)
local function lg_cam()
	local c = sdk.get_primary_camera()
	local pos, rot = cam_pos_rot()
	if not c or not pos then return nil end
	local ok, fov = pcall(c.call, c, "get_FOV")
	if not ok or not fov or fov <= 0 then return nil end
	local d = imgui.get_display_size()
	return { p = v3(pos), q = rot, ic = q_conj(rot), t = math.tan(math.rad(fov) * 0.5), W = d.x, H = d.y, asp = d.x / d.y }
end
local function lg_w2s(C, w)
	local l = lg.q_rot(C.ic, vsub(w, C.p))
	if l[3] > -0.02 then return nil end
	local x = (l[1] / -l[3]) / (C.t * C.asp)
	local y = (l[2] / -l[3]) / C.t
	return { x = (x * 0.5 + 0.5) * C.W, y = (0.5 - y * 0.5) * C.H }
end
local function lg_ray(C, mx, my)
	local x = (mx / C.W) * 2 - 1
	local y = 1 - (my / C.H) * 2
	return vnorm(lg.q_rot(C.q, { x * C.t * C.asp, y * C.t, -1 }))
end
local function seg_dist(px, py, a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	local l2 = dx * dx + dy * dy
	local t = (l2 > 0) and math.max(0, math.min(1, ((px - a.x) * dx + (py - a.y) * dy) / l2)) or 0
	local cx, cy = a.x + dx * t, a.y + dy * t
	return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end
local function lmb_down() local ok, v = pcall(reframework.is_key_down, reframework, 0x01); return ok and v end
nlights.drag = nil

-- v2.6.20: gizmo para mover o personagem inteiro (aba Poser)
-- A luta reposiciona o lutador a cada frame, então o NASK guarda só o deslocamento
-- e o soma à posição que o jogo der, logo antes de desenhar.
port.cmove = {}
function port.cmove_apply()
	for _, e in pairs(port.cmove) do
		if e.on and e.allowed ~= false and (e.off[1] ~= 0 or e.off[2] ~= 0 or e.off[3] ~= 0) then
			pcall(function()
				local cur = v3(e.xf:call("get_Position"))
				local base = cur
				if e.last then
					local dl_ = vlen(vsub(cur, e.last))
					if dl_ < 1e-4 then
						base = e.base                      -- ninguém mexeu: mantém
					elseif e.base and dl_ < vlen(vsub(cur, e.base)) then
						-- o jogo andou A PARTIR da posição que o NASK pôs (menus, root
						-- motion): o deslocamento já está embutido, não soma de novo
						base = vsub(cur, e.off)
					end
				end
				local np = vadd(base, e.off)
				e.xf:call("set_Position", Vector3f.new(np[1], np[2], np[3]))
				e.base, e.last = base, np
			end)
		end
	end
end
function port.cmove_gizmo(show)
	local m = imgui.get_mouse()
	local down = lmb_down()
	if not down then port.cmove_drag = nil end
	if not show then return end
	local C = lg_cam()
	if not C then return end
	for k, e in pairs(port.cmove) do
		pcall(function()
			if not (e.on and e.gizmo and k == (port.poser and port.poser.sel_pk)) then return end
			local pos = v3(e.xf:call("get_Position"))
			local sp = lg_w2s(C, pos)
			if not sp then return end
			local len = vlen(vsub(pos, C.p)) * 0.14
			local AX = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
			local AXC = { rgba(235, 70, 70, 1), rgba(90, 210, 90, 1), rgba(80, 140, 255, 1) }
			local ends = {}
			for i = 1, 3 do ends[i] = lg_w2s(C, vadd(pos, vmul(AX[i], len))) end
			local hot
			local dg = port.cmove_drag
			if m and not hovered and not dg then
				if math.sqrt((m.x - sp.x) ^ 2 + (m.y - sp.y) ^ 2) < 10 then hot = "plane"
				else
					for i = 1, 3 do if ends[i] and seg_dist(m.x, m.y, sp, ends[i]) < 7 then hot = "axis" .. i break end end
				end
			end
			if hot and down and not dg then
				port.cmove_drag = { k = k, h = hot, mx = m.x, my = m.y, off0 = { e.off[1], e.off[2], e.off[3] }, pos0 = pos,
					depth = vdot(vsub(pos, C.p), lg.q_rot(C.q, { 0, 0, -1 })) }
				dg = port.cmove_drag
			end
			if dg and dg.k == k and m then
				nlights.gizmo_until = os.clock() + 0.25
				local delta
				if dg.h:sub(1, 4) == "axis" then
					local i = tonumber(dg.h:sub(5))
					local a = lg_w2s(C, dg.pos0)
					local b = lg_w2s(C, vadd(dg.pos0, vmul(AX[i], len)))
					if a and b then
						local dx, dy = b.x - a.x, b.y - a.y
						local l2 = dx * dx + dy * dy
						if l2 > 4 then delta = vmul(AX[i], ((m.x - dg.mx) * dx + (m.y - dg.my) * dy) / l2 * len) end
					end
				else
					local fwd = lg.q_rot(C.q, { 0, 0, -1 })
					local r0, r1 = lg_ray(C, dg.mx, dg.my), lg_ray(C, m.x, m.y)
					local p0 = vadd(C.p, vmul(r0, dg.depth / math.max(1e-4, vdot(r0, fwd))))
					local p1 = vadd(C.p, vmul(r1, dg.depth / math.max(1e-4, vdot(r1, fwd))))
					delta = vsub(p1, p0)
				end
				if delta then e.off = vadd(dg.off0, delta) end
			end
			local act = (dg and dg.k == k and dg.h) or hot
			for i = 1, 3 do
				if ends[i] then
					local c = (act == "axis" .. i) and rgba(255, 230, 90, 1) or AXC[i]
					draw.line(sp.x, sp.y, ends[i].x, ends[i].y, c)
					draw.line(sp.x + 1, sp.y, ends[i].x + 1, ends[i].y, c)
					draw.filled_circle(ends[i].x, ends[i].y, 5, c, 12)
				end
			end
			draw.outline_rect(sp.x - 7, sp.y - 7, 14, 14, (act == "plane") and rgba(255, 230, 90, 1) or WHITE)
		end)
	end
end
-- aplica depois da lógica da luta e de novo antes de desenhar (a luta reescreve a
-- posição do lutador todo frame; só no fim do frame não dava tempo de valer)
for _, ev in ipairs({ "LateUpdateBehavior", "UpdateMotion", "LateUpdateMotion", "PrepareRendering" }) do
	pcall(re.on_application_entry, ev, function() pcall(port.cmove_apply) end)
end
re.on_pre_application_entry("BeginRendering", function() pcall(port.cmove_apply) end)

-- v2.6.25: "distorção 2D" dos lutadores
-- O SF6 corrige a projeção dos lutadores no shader para parecerem 2D na câmera da
-- luta (parâmetro de material "FixProjection_Switch" = 1). Com a câmera livre longe
-- do centro isso os deixa esticados. Com o Modo Foto ligado o NASK põe 0 nas malhas
-- dos lutadores e devolve o valor original ao sair.
-- (Parâmetro do RE Engine Lua Freecam: todos os créditos disso vão para o alphaZomega.)
port.fp = { t = -10, saved = {}, active = false }
local function fp_meshes()
	local list = {}
	pcall(function()
		local arr = current_scene():call("findComponents(System.Type)", sdk.typeof("via.render.Mesh"))
		for _, m in ipairs(arr and arr:get_elements() or {}) do
			pcall(function()
				-- sobe até achar um objeto de lutador (esfXXX)
				local xf = m:call("get_GameObject"):call("get_Transform")
				for _ = 1, 10 do
					if not xf then break end
					local g = xf:call("get_GameObject")
					if g and NASK_FC.code_of(g) then table.insert(list, m) break end
					xf = xf:call("get_Parent")
				end
			end)
		end
	end)
	return list
end
local function fp_set(mesh, value, remember)
	local n = mesh:call("get_MaterialNum") or 0
	for mi = 0, n - 1 do
		local vn = mesh:call("getMaterialVariableNum", mi) or 0
		for vi = 0, vn - 1 do
			if mesh:call("getMaterialVariableName", mi, vi) == "FixProjection_Switch" then
				local k = addr(mesh) .. ":" .. mi .. ":" .. vi
				if remember and port.fp.saved[k] == nil then
					local ok, v0 = pcall(mesh.call, mesh, "getMaterialFloat", mi, vi)
					port.fp.saved[k] = { mesh = mesh, mi = mi, vi = vi, v = (ok and type(v0) == "number") and v0 or 1.0 }
				end
				mesh:call("setMaterialFloat", mi, vi, value)
			end
		end
	end
end
-- v2.6.31: sobreposição dos lutadores
-- Na luta o jogo desenha um lutador sempre "por cima" do outro (prioridade de
-- stencil nas malhas). Com a câmera livre isso faz o de trás aparecer na frente.
-- Com o Modo Foto ligado o NASK desliga essa prioridade e devolve ao sair.
-- (Também um parâmetro do RE Engine Lua Freecam: créditos ao alphaZomega.)
port.ov = { saved = {}, active = false }
function port.fp_tick()
	local P, O = port.fp, port.ov
	local want2d = NASK_FC.on and cfg.no_2d ~= false
	local wantov = NASK_FC.on and cfg.fix_overlap ~= false
	if not want2d and P.active then
		for _, it in pairs(P.saved) do pcall(it.mesh.call, it.mesh, "setMaterialFloat", it.mi, it.vi, it.v) end
		P.saved, P.active = {}, false
	end
	if not wantov and O.active then
		for _, it in pairs(O.saved) do pcall(it.mesh.call, it.mesh, "set_UseStencilValuePriority", it.v) end
		O.saved, O.active = {}, false
	end
	if not want2d and not wantov then return end
	-- a prioridade de sobreposição o jogo repõe todo frame: aplica sempre na lista
	-- guardada (a lista de malhas é refeita a cada segundo)
	if wantov and O.list then
		for _, m in ipairs(O.list) do pcall(m.call, m, "set_UseStencilValuePriority", false) end
	end
	-- reaplica a cada segundo (o jogo pode trocar/recriar malhas, ex.: troca de roupa)
	if (P.active or O.active) and os.clock() - P.t < 1.0 then return end
	P.t = os.clock()
	local meshes = fp_meshes()
	O.list = meshes
	for _, m in ipairs(meshes) do
		if want2d then pcall(fp_set, m, 0.0, true) end
		if wantov then
			pcall(function()
				local k = addr(m)
				if O.saved[k] == nil then O.saved[k] = { mesh = m, v = m:call("get_UseStencilValuePriority") } end
				m:call("set_UseStencilValuePriority", false)
			end)
		end
	end
	P.active, O.active = want2d, wantov
end
re.on_pre_application_entry("BeginRendering", function() pcall(port.fp_tick) end)
-- a sobreposição também antes da preparação do desenho (o jogo pode repor no meio do frame)
pcall(re.on_application_entry, "PrepareRendering", function()
	if port.ov.active and port.ov.list then
		for _, m in ipairs(port.ov.list) do pcall(m.call, m, "set_UseStencilValuePriority", false) end
	end
end)

-- gizmo e indicadores (chamado todo frame)
function draw_lights(show_ui)
	if nlights.release then
		for _, p in ipairs(nlights.release) do pcall(p.xform.call, p.xform, "set_SameJointsConstraint", false) end
		nlights.release = nil
	end
	for _, L in ipairs(nlights.list) do pcall(light_apply, L) end
	if not show_ui or #nlights.list == 0 then nlights.drag = nil return end
	local C = lg_cam()
	if not C then return end
	local function line(a, b, col, th)
		draw.line(a.x, a.y, b.x, b.y, col)
		if th and th >= 3 then
			draw.line(a.x + 1, a.y, b.x + 1, b.y, col)
			draw.line(a.x, a.y + 1, b.x, b.y + 1, col)
		end
	end
	local m = imgui.get_mouse()
	local down = lmb_down()
	if not down then nlights.drag = nil end

	for i, L in ipairs(nlights.list) do
		pcall(function()
			if not L.enabled then return end
			local pos = v3(L.xform:call("get_Position"))
			local rot = L.xform:call("get_Rotation")
			local col = rgba(math.floor(L.color.x * 255), math.floor(L.color.y * 255), math.floor(L.color.z * 255), 1.0)
			local sel = (i == nlights.sel)
			local sp = lg_w2s(C, pos)
			if cfg.light_lines then
				if sp then
					draw.filled_circle(sp.x, sp.y, sel and 6 or 4, col, 16)
					draw.outline_circle(sp.x, sp.y, sel and 8 or 6, WHITE, 16)
					draw.text(L.name, sp.x + 12, sp.y - 8, WHITE)
				end
				if L.kind == 1 then
					local dir = lg.q_rot(rot, { 0, 0, -1 })
					local right = lg.q_rot(rot, { 1, 0, 0 })
					local up = lg.q_rot(rot, { 0, 1, 0 })
					local tip = vadd(pos, vmul(dir, L.radius))
					local r = L.radius * math.tan(math.rad(math.min(L.cone * 0.5, 80)))
					local ep = lg_w2s(C, tip)
					if sp and ep then line(sp, ep, col) end
					local prev
					for k = 0, 32 do
						local a = (k / 32) * math.pi * 2
						local w = vadd(tip, vadd(vmul(right, math.cos(a) * r), vmul(up, math.sin(a) * r)))
						local s2 = lg_w2s(C, w)
						if s2 then
							if prev then line(prev, s2, col) end
							if sp and (k % 8 == 0) then line(sp, s2, rgba(255, 255, 255, 0.45), 1.0) end
						end
						prev = s2
					end
				else
					-- três círculos (anéis XY, XZ, YZ) do alcance
					for ax = 1, 3 do
						local prev
						for k = 0, 40 do
							local a = (k / 40) * math.pi * 2
							local o = { 0, 0, 0 }
							o[(ax % 3) + 1] = math.cos(a) * L.radius
							o[((ax + 1) % 3) + 1] = math.sin(a) * L.radius
							local s2 = lg_w2s(C, vadd(pos, o))
							if s2 and prev then line(prev, s2, rgba(math.floor(L.color.x * 255), math.floor(L.color.y * 255), math.floor(L.color.z * 255), 0.55), 1.0) end
							prev = s2
						end
					end
				end
			end

			-- gizmo próprio (só na luz selecionada)
			if not (cfg.light_gizmo and sel and sp) then return end
			local dist = vlen(vsub(pos, C.p))
			local len = dist * 0.14
			local do_move = cfg.light_gizmo_op ~= 2
			local do_aim = cfg.light_gizmo_op ~= 1 and L.kind == 1
			local AX = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
			local AXC = { rgba(235, 70, 70, 1), rgba(90, 210, 90, 1), rgba(80, 140, 255, 1) }
			local handles = {}
			if do_move then
				for k = 1, 3 do
					local e = lg_w2s(C, vadd(pos, vmul(AX[k], len)))
					if e then table.insert(handles, { kind = "axis", k = k, a = sp, b = e }) end
				end
				table.insert(handles, { kind = "plane" })
			end
			local aim_pt
			if do_aim then
				local dir = lg.q_rot(rot, { 0, 0, -1 })
				aim_pt = lg_w2s(C, vadd(pos, vmul(dir, len * 1.6)))
				if aim_pt then table.insert(handles, { kind = "aim" }) end
			end

			-- qual alça está sob o mouse
			local hot
			if m and not hovered and not nlights.drag then
				if aim_pt and math.sqrt((m.x - aim_pt.x) ^ 2 + (m.y - aim_pt.y) ^ 2) < 11 then hot = "aim"
				elseif do_move and math.sqrt((m.x - sp.x) ^ 2 + (m.y - sp.y) ^ 2) < 10 then hot = "plane"
				else
					for _, h in ipairs(handles) do
						if h.kind == "axis" and seg_dist(m.x, m.y, h.a, h.b) < 7 then hot = "axis" .. h.k break end
					end
				end
			end
			-- começa o arraste
			if hot and down and not nlights.drag then
				local ray = lg_ray(C, m.x, m.y)
				nlights.drag = { i = i, h = hot, start_pos = pos, mx = m.x, my = m.y, depth = vdot(vsub(pos, C.p), lg.q_rot(C.q, { 0, 0, -1 })) }
			end
			local dg = nlights.drag
			if dg and dg.i == i and m then
				nlights.gizmo_until = os.clock() + 0.25
				if dg.h:sub(1, 4) == "axis" then
					-- move pelo eixo: projeta o mouse na reta do eixo na tela
					local k = tonumber(dg.h:sub(5))
					local a = lg_w2s(C, dg.start_pos)
					local b = lg_w2s(C, vadd(dg.start_pos, vmul(AX[k], len)))
					if a and b then
						local dx, dy = b.x - a.x, b.y - a.y
						local l2 = dx * dx + dy * dy
						if l2 > 4 then
							local t = ((m.x - dg.mx) * dx + (m.y - dg.my) * dy) / l2
							L.xform:call("set_Position", Vector3f.new(table.unpack(vadd(dg.start_pos, vmul(AX[k], t * len)))))
						end
					end
				elseif dg.h == "plane" then
					-- move no plano da tela, na mesma profundidade
					local fwd = lg.q_rot(C.q, { 0, 0, -1 })
					local r0 = lg_ray(C, dg.mx, dg.my)
					local r1 = lg_ray(C, m.x, m.y)
					local p0 = vadd(C.p, vmul(r0, dg.depth / math.max(1e-4, vdot(r0, fwd))))
					local p1 = vadd(C.p, vmul(r1, dg.depth / math.max(1e-4, vdot(r1, fwd))))
					L.xform:call("set_Position", Vector3f.new(table.unpack(vadd(dg.start_pos, vsub(p1, p0)))))
				elseif dg.h == "aim" then
					-- aponta a luz para o ponto sob o mouse, na profundidade da alça
					local fwd = lg.q_rot(C.q, { 0, 0, -1 })
					local r1 = lg_ray(C, m.x, m.y)
					local tdepth = math.max(0.05, dg.depth)
					local target = vadd(C.p, vmul(r1, tdepth / math.max(1e-4, vdot(r1, fwd))))
					local d = vsub(target, pos)
					if vlen(d) > 1e-3 then L.xform:call("set_Rotation", lg.look_quat(d)) end
				end
			end

			-- desenho das alças
			local active = dg and dg.i == i and dg.h or hot
			if do_move then
				for _, h in ipairs(handles) do
					if h.kind == "axis" then
						local hl = (active == "axis" .. h.k)
						line(h.a, h.b, hl and rgba(255, 230, 90, 1) or AXC[h.k], hl and 4 or 3)
						draw.filled_circle(h.b.x, h.b.y, hl and 6 or 5, hl and rgba(255, 230, 90, 1) or AXC[h.k], 12)
					end
				end
				draw.outline_rect(sp.x - 7, sp.y - 7, 14, 14, (active == "plane") and rgba(255, 230, 90, 1) or WHITE)
			end
			if aim_pt then
				local hl = (active == "aim")
				line(sp, aim_pt, rgba(255, 255, 255, 0.6), 1.5)
				draw.filled_circle(aim_pt.x, aim_pt.y, hl and 9 or 7, hl and rgba(255, 230, 90, 1) or accent(1.0), 16)
				draw.outline_circle(aim_pt.x, aim_pt.y, hl and 11 or 9, WHITE, 16)
			end
		end)
	end
end
end

-- ---------------------------------------------------------------------------
-- Inspetor de objeto (usado em Personagem e Console)
-- ---------------------------------------------------------------------------
local function each_child(xform, fn, depth, budget)
	depth = depth or 0
	budget = budget or { n = 0 }
	if depth > 6 or budget.n > 400 then return end
	local ok, c = pcall(xform.call, xform, "get_Child")
	while ok and c do
		budget.n = budget.n + 1
		if fn(c, depth) ~= false then each_child(c, fn, depth + 1, budget) end
		ok, c = pcall(c.call, c, "get_Next")
	end
end
port.each_child = each_child

local function mesh_path_of(go)
	local ok, p = pcall(function()
		local m = go:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
		local r = m and m:call("getMesh")
		local str = r and r:call("ToString()")
		return str and (str:match("^.+%[@?(.+)%]") or str)
	end)
	return ok and p or nil
end

-- descobre o lutador pelo caminho dos modelos (ex.: .../esf030/...)
local function fighter_of(go, xform)
	local counts, best, bestn, sample = {}, nil, 0, nil
	local function look(g)
		local p = mesh_path_of(g)
		if p then
			local code = p:match("[Ee][Ss][Ff](%d%d%d)")
			if code and code ~= "000" then
				counts[code] = (counts[code] or 0) + 1
				if counts[code] > bestn then best, bestn, sample = code, counts[code], p end
			end
		end
	end
	look(go)
	if xform then each_child(xform, function(c) pcall(function() look(c:call("get_GameObject")) end) end) end
	return best, sample
end

local function component_label(comp)
	local ok, n = pcall(function() return comp:get_type_definition():get_full_name() end)
	return ok and n or "Componente"
end

-- peças (malhas) do personagem: todos os filhos com malha, sem filtrar pelo nome
-- do material (óculos, acessórios e afins têm materiais sem o código esfXXX),
-- mais objetos soltos na cena com o mesmo nome-base (ex.: esf001v00_xx)
local parts_cache = {}
local function collect_parts(go, xform)
	local parts, seen = {}, {}
	local function add(pgo)
		local mesh = pgo:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
		if not mesh then return end
		local k = addr(mesh)
		if seen[k] then return end
		local n = mesh:call("get_MaterialNum") or 0
		if n == 0 then return end
		seen[k] = true
		local mats = {}
		for m = 0, n - 1 do
			table.insert(mats, { id = m, name = mesh:call("getMaterialName", m) or ("mat " .. m) })
		end
		table.insert(parts, { go = pgo, mesh = mesh, mats = mats, name = pgo:call("get_Name") or "?" })
	end
	pcall(add, go)
	each_child(xform, function(c)
		local ok, cgo = pcall(c.call, c, "get_GameObject")
		if ok and cgo then pcall(add, cgo) end
	end, 0, { n = -2000 })
	pcall(function()
		local base = (go:call("get_Name") or ""):match("^(esf%d+v%d+)")
		if not base then return end
		local arr = current_scene():call("findComponents(System.Type)", sdk.typeof("via.render.Mesh"))
		for _, m in ipairs(arr and arr:get_elements() or {}) do
			pcall(function()
				local mg = m:call("get_GameObject")
				local nm = mg:call("get_Name") or ""
				if nm:sub(1, #base) == base then add(mg) end
			end)
		end
	end)
	table.sort(parts, function(a, b) return a.name < b.name end)
	return parts
end

local function ui_parts(go, xform, fid)
	local key = addr(xform)
	local pc = parts_cache[key]
	if not pc or imgui.button("Procurar peças de novo") then
		pc = collect_parts(go, xform)
		parts_cache[key] = pc
	end
	if #pc == 0 then hint("Nenhuma peça com material encontrada.") return end
	for i, part in ipairs(pc) do
		imgui.push_id("pt" .. i)
		pcall(function()
			local vis = part.go:call("get_DrawSelf")
			local ch, nv = imgui.checkbox("##pv", vis)
			if ch then force_visible(part.go, nv) end
			tooltip("Mostrar / ocultar a peça inteira")
			imgui.same_line()
			if NASK_FC.fresh and NASK_FC.fresh("pn" .. part.name) then pcall(imgui.set_next_item_open, false, 1) end
			if imgui.tree_node(part.name .. string.format("  (%d)", #part.mats) .. "##pn") then
				for k, mt in ipairs(part.mats) do
					local on = part.mesh:call("getMaterialsEnable", mt.id)
					if (k - 1) % 2 ~= 0 then imgui.same_line() end
					changed, on = imgui.checkbox(mt.name .. "##m" .. mt.id, on)
					if changed then force_material(part.mesh, mt.id, on) end
				end
				imgui.tree_pop()
			end
		end)
		imgui.pop_id()
	end
end

-- tree_node que lembra o próprio estado e começa ABERTO
local tree_state = {}
local function open_tree(label, key, default_open)
	local want = tree_state[key]
	if want == nil then want = false end
	imgui.set_next_item_open(want, 1)
	local open = imgui.tree_node(label)
	tree_state[key] = open
	return open
end

-- Pausa de pose: desliga só a ANIMAÇÃO (via.motion.Motion) do personagem.
-- O jogo e a física continuam rodando; o Poser grava os ossos e, no frame seguinte,
-- cabelo/roupa/correntes são calculados em cima da pose nova.
local PHYS_TYPES = { "via.motion.Chain", "via.dynamics.GpuCloth", "via.havok.HavokCloth" }
-- ajustes automáticos de ossos (olhar para o oponente, IK de pés/mãos/coluna).
-- Com a animação congelada eles se acumulam a cada frame (ex.: a cabeça vai descendo),
-- então também ficam desligados durante a pausa de pose.
local PROC_TYPES = {
	"via.motion.IkLookAt", "via.motion.IkLookAt2", "via.motion.IkMultiLookAt2",
	"via.motion.IkLeg", "via.motion.IkLeg2", "via.motion.IkLegSpine", "via.motion.IkSpine",
	"via.motion.IkSpineBend", "via.motion.IkHand", "via.motion.IkHand2", "via.motion.IkMultiBone",
	"via.motion.IkBodyRig", "via.motion.IkNboneCCD", "via.motion.IkJacobian",
	"app.bLookAtController", "app.PBFacialLookAt", "app.HatoLookAtTrack", "app.IkBodyProgEffector",
	"app.battle.PBIk", "app.battle.PBIk2BoneController", "app.battle.PBIkLegArm",
}
local pose_hold = {}

-- elementos de um array do jogo (System.Array / via.Joint[]), de vários jeitos
local function array_list(arr)
	if not arr then return {} end
	local ok, list = pcall(function() return arr:get_elements() end)
	if ok and type(list) == "table" and #list > 0 then return list end
	local out = {}
	pcall(function()
		local n = arr:get_size()
		for i = 0, n - 1 do
			local e = arr:get_element(i)
			if e then table.insert(out, e) end
		end
	end)
	if #out > 0 then return out end
	pcall(function()
		local n = arr:call("get_Count") or arr:call("get_Length") or 0
		for i = 0, n - 1 do
			local e = arr:call("get_Item", i)
			if e then table.insert(out, e) end
		end
	end)
	return out
end
port.array_list = array_list

-- código do lutador pelo nome do objeto (esf030_... -> "030")
NASK_FC.code_of = function(go)
	local ok, n = pcall(go.call, go, "get_Name")
	return ok and type(n) == "string" and n:lower():match("^esf(%d%d%d)") or nil
end
-- filtro de filhos: devolve uma função que diz se o galho é de outro lutador
NASK_FC.other_char = function(go)
	local own = NASK_FC.code_of(go)
	if not own then return function() return false end end
	return function(cxf)
		local ok, cgo = pcall(cxf.call, cxf, "get_GameObject")
		local c = ok and cgo and NASK_FC.code_of(cgo)
		return c ~= nil and c ~= own
	end
end

local function collect_comps(go, xform, types)
	local out = {}
	local function each(g)
		for _, tn in ipairs(types) do
			pcall(function()
				local t = sdk.typeof(tn)
				local c = t and g:call("getComponent(System.Type)", t)
				if c then table.insert(out, c) end
			end)
		end
	end
	each(go)
	local other = NASK_FC.other_char(go)
	each_child(xform, function(c)
		if other(c) then return false end
		local ok, cgo = pcall(c.call, c, "get_GameObject")
		if ok and cgo then each(cgo) end
	end)
	return out
end

-- ---------------------------------------------------------------------------
-- Poser NASK
--  * Livre: mexe nos ossos a qualquer momento (com o jogo rodando ou no F1).
--    As edições são aplicadas no fim do frame (PrepareRendering), por cima da
--    animação, então aparecem sempre. A física não acompanha nesse modo.
--  * Com a "Pausa de pose": a animação congela e a pose (com as edições) é
--    aplicada ANTES da animação/física (pre-UpdateMotion), aí cabelo, roupa e
--    correntes seguem a pose.
-- ---------------------------------------------------------------------------
local function qaxis(x, y, z, deg)
	local a = math.rad(deg) * 0.5
	local sn = math.sin(a)
	return Quaternion.new(math.cos(a), x * sn, y * sn, z * sn)
end
local function qconj(q) return Quaternion.new(q.w, -q.x, -q.y, -q.z) end
local function qsame(a, b)
	if not a or not b then return false end
	return math.abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z) > 0.999999
end
local function vsame(a, b)
	if not a or not b then return false end
	return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z) < 1e-5
end

local posers = {}   -- endereço do transform -> { skels, skel_i, edits, xform, held }

-- esqueletos do objeto e dos filhos (o principal é o que tem mais ossos)
local function build_skels(go, xform)
	local skels, seen = {}, {}
	local function snap(xf)
		local k = addr(xf)
		if seen[k] then return end
		seen[k] = true
		local ok, arr = pcall(xf.call, xf, "get_Joints")
		local list = ok and array_list(arr) or {}
		local js = {}
		for _, j in ipairs(list) do
			pcall(function() table.insert(js, { j = j, a = addr(j), name = j:call("get_Name") or "?" }) end)
		end
		if #js > 0 then table.insert(skels, { xf = xf, k = k, joints = js }) end
	end
	local anim = {}
	for _, m in ipairs(collect_comps(go, xform, { "via.motion.Motion" })) do
		pcall(function()
			local xf = m:call("get_GameObject"):call("get_Transform")
			anim[addr(xf)] = true
			snap(xf)
		end)
	end
	snap(xform)
	local other = NASK_FC.other_char(go)
	each_child(xform, function(c)
		if other(c) then return false end
		pcall(snap, c)
	end)
	for _, sk in ipairs(skels) do sk.anim = anim[sk.k] == true end
	-- o esqueleto com a animação vem primeiro; depois o que tem mais ossos
	table.sort(skels, function(a, b)
		if a.anim ~= b.anim then return a.anim end
		return #a.joints > #b.joints
	end)
	return skels
end

local function poser_of(go, xform)
	local pk = addr(xform)
	local pz = posers[pk]
	if not pz then
		pz = { skels = build_skels(go, xform), skel_i = 1, edits = {}, xform = xform, go = go }
		posers[pk] = pz
	end
	return pz
end

-- rotação/posição final de um osso editado a partir de uma base
local function edit_target(t, base_r, base_p)
	local r = t.gr or base_r
	if (t.ex or 0) ~= 0 or (t.ey or 0) ~= 0 or (t.ez or 0) ~= 0 then
		r = r * qaxis(1, 0, 0, t.ex or 0) * qaxis(0, 1, 0, t.ey or 0) * qaxis(0, 0, 1, t.ez or 0)
	end
	local p = t.ap or base_p
	if t.op then p = p + t.op end
	return r:normalized(), p
end

-- aplica as edições de um poser.
-- held_full = true: também recoloca os ossos não editados na pose base (pausa de pose)
local function apply_poser(pz, held_full)
	-- no F1 a animação não anda: a base fica fixa (não relê o osso, não acumula nem perde)
	local frozen = NASK_FC.is_scene_frozen()
	for _, sk in ipairs(pz.skels) do
		for _, e in ipairs(sk.joints) do
			local t = pz.edits[e.name]
			if t or held_full then
				pcall(function()
					local br, bp
					if pz.held and e.r then
						br, bp = e.r, e.p
					elseif t then
						-- base = pose da animação neste frame; se o jogo não reescreveu o osso
						-- (pausado), continua usando a base anterior (não acumula)
						if frozen and e.br and e.bp then
							br, bp = e.br, e.bp
						else
							local cr, cp = e.j:call("get_LocalRotation"), e.j:call("get_LocalPosition")
							br = (e.lr and qsame(cr, e.lr) and e.br) or cr
							bp = (e.lp and vsame(cp, e.lp) and e.bp) or cp
							e.br, e.bp = br, bp
						end
					else
						return
					end
					if t then
						local r, p = edit_target(t, br, bp)
						e.j:call("set_LocalRotation", r)
						e.j:call("set_LocalPosition", p)
						e.lr, e.lp = r, p
					else
						e.j:call("set_LocalRotation", br)
						e.j:call("set_LocalPosition", bp)
						if e.s then e.j:call("set_LocalScale", e.s) end
					end
				end)
			end
		end
	end
end

-- antes da animação/física: pausa de pose (pose base inteira + edições)
re.on_pre_application_entry("UpdateMotion", function()
	for _, pz in pairs(posers) do
		if pz.held then apply_poser(pz, true) end
	end
	-- v2.5.3: o IK/olhar dos OUTROS lutadores precisa estar desligado DURANTE o update
	-- do jogo (não só no fim do frame), senão ele roda e segue os ossos do personagem
	-- em pausa de pose.
	if next(pose_hold) then pcall(NASK_FC.pose_others_enforce) end
end)
-- fim do frame: edições aparecem sempre (também no F1)
re.on_application_entry("PrepareRendering", function()
	for pk, pz in pairs(posers) do
		if next(pz.edits) then
			local ok = pcall(apply_poser, pz, false)
			if not ok then posers[pk] = nil end
		end
	end
end)

-- Com a pausa de pose, a pose é gravada ANTES da animação/IK do frame. Os outros
-- lutadores olham/miram no corpo deste (olhar para o oponente, IK de mãos/coluna),
-- então a cabeça e o corpo deles acompanhavam cada osso mexido. Enquanto houver
-- pausa de pose, esses ajustes dos OUTROS ficam desligados; voltam ao soltar.
NASK_FC.pose_others = NASK_FC.pose_others or { comps = {}, t = -10 }

-- desliga de novo (antes do update) o que já está na lista dos "outros"
function NASK_FC.pose_others_enforce()
	for k, it in pairs(NASK_FC.pose_others.comps) do
		if not pcall(function() if it.c:call("get_Enabled") then it.c:call("set_Enabled", false) end end) then
			NASK_FC.pose_others.comps[k] = nil
		end
	end
end

-- tipos de ajuste automático de ossos que o jogo pode ter além da lista PROC_TYPES
local function is_ik_type_name(tn)
	if not tn then return false end
	return tn:find("LookAt", 1, true) or tn:find("Aim", 1, true) or tn:find("%.Ik%u") or tn:find("%.PBIk") or false
end
local ik_logged = {}

-- procura, nos OUTROS lutadores (raiz esfXXX e filhos), componentes de IK/olhar
-- que a lista fixa PROC_TYPES não cobre
local function scan_other_fighters_ik(po, own, own_motion)
	local scene = current_scene()
	local mt = sdk.typeof("via.motion.Motion")
	if not scene or not mt then return end
	local arr = scene:call("findComponents(System.Type)", mt)
	local roots, seen = {}, {}
	for _, m in ipairs(arr and arr:get_elements() or {}) do
		pcall(function()
			if own_motion[addr(m)] then return end
			local go = m:call("get_GameObject")
			if not go or not NASK_FC.code_of(go) then return end
			local xf = go:call("get_Transform")
			-- sobe até a raiz do lutador (enquanto o pai também for esfXXX)
			for _ = 1, 8 do
				local par = xf:call("get_Parent")
				local pgo = par and par:call("get_GameObject")
				if pgo and NASK_FC.code_of(pgo) then xf, go = par, pgo else break end
			end
			local k = addr(xf)
			if not seen[k] then seen[k] = true; table.insert(roots, { go = go, xf = xf }) end
		end)
	end
	local function grab(g)
		local ok, carr = pcall(g.call, g, "get_Components")
		for _, c in ipairs(ok and array_list(carr) or {}) do
			pcall(function()
				local tn = c:get_type_definition():get_full_name()
				local k = addr(c)
				if is_ik_type_name(tn) and not own[k] and not po.comps[k] then
					local ok2, en = pcall(c.call, c, "get_Enabled")
					po.comps[k] = { c = c, was = (not ok2) or en }
					force_comp_enabled(c, false)
					if not ik_logged[tn] then
						ik_logged[tn] = true
						pcall(log.info, "[NASK] IK/olhar de outro lutador desligado: " .. tn)
					end
				end
			end)
		end
	end
	for _, r in ipairs(roots) do
		pcall(grab, r.go)
		each_child(r.xf, function(c)
			local ok, cgo = pcall(c.call, c, "get_GameObject")
			if ok and cgo then pcall(grab, cgo) end
		end)
	end
end

function NASK_FC.pose_others_tick(force)
	local po = NASK_FC.pose_others
	local any = next(pose_hold) ~= nil
	if not any then
		if next(po.comps) then
			for k, it in pairs(po.comps) do
				if it.was then force_comp_enabled(it.c, true) else forced_comp[k] = nil end
			end
			po.comps = {}
		end
		return
	end
	local now = os.clock()
	if not force and now - po.t < 1.0 then return end
	po.t = now
	-- componentes dos próprios personagens em pausa de pose (já tratados lá)
	local own = {}
	for _, h in pairs(pose_hold) do
		for _, c in ipairs(h.procs or {}) do own[addr(c)] = true end
	end
	local scene = current_scene()
	if not scene then return end
	for _, tn in ipairs(PROC_TYPES) do
		pcall(function()
			local t = sdk.typeof(tn)
			if not t then return end
			local arr = scene:call("findComponents(System.Type)", t)
			for _, c in ipairs(arr and arr:get_elements() or {}) do
				local k = addr(c)
				if not own[k] and not po.comps[k] then
					local ok, en = pcall(c.call, c, "get_Enabled")
					po.comps[k] = { c = c, was = (not ok) or en }
					force_comp_enabled(c, false)
				end
			end
		end)
	end
	-- varredura extra por nome de tipo (IK/olhar que PROC_TYPES não conhece)
	local own_motion = {}
	for _, h in pairs(pose_hold) do
		for _, m in ipairs(h.motions or {}) do own_motion[addr(m)] = true end
	end
	pcall(scan_other_fighters_ik, po, own, own_motion)
	pcall(NASK_FC.pose_others_enforce)
end

local function set_pose_hold(go, xform, on)
	local pk = addr(xform)
	local pz = poser_of(go, xform)
	if on then
		local motions = collect_comps(go, xform, { "via.motion.Motion" })
		local procs = collect_comps(go, xform, PROC_TYPES)
		local was = {}
		for _, c in ipairs(procs) do
			local ok, en = pcall(c.call, c, "get_Enabled")
			was[addr(c)] = (not ok) or en
		end
		for _, m in ipairs(motions) do force_comp_enabled(m, false) end
		for _, c in ipairs(procs) do force_comp_enabled(c, false) end
		-- garante que a física está ligada
		for _, c in ipairs(collect_comps(go, xform, PHYS_TYPES)) do force_comp_enabled(c, true) end
		if #pz.skels == 0 then pz.skels = build_skels(go, xform) end
		-- pose base = pose atual SEM as edições (as edições continuam por cima)
		for _, sk in ipairs(pz.skels) do
			for _, e in ipairs(sk.joints) do
				pcall(function()
					local t = pz.edits[e.name]
					e.r = (t and e.br) or e.j:call("get_LocalRotation")
					e.p = (t and e.bp) or e.j:call("get_LocalPosition")
					e.s = e.j:call("get_LocalScale")
				end)
			end
		end
		pz.held = true
		-- se este personagem estava na lista dos "outros", devolve o controle a ele
		for _, c in ipairs(procs) do NASK_FC.pose_others.comps[addr(c)] = nil end
		pose_hold[pk] = { motions = motions, procs = procs, was = was }
		pcall(NASK_FC.pose_others_tick, true)
	else
		local h = pose_hold[pk] or {}
		for _, m in ipairs(h.motions or {}) do force_comp_enabled(m, true) end
		for _, c in ipairs(h.procs or {}) do
			if (h.was or {})[addr(c)] ~= false then force_comp_enabled(c, true) else forced_comp[addr(c)] = nil end
		end
		pose_hold[pk] = nil
		pz.held = false
		pcall(NASK_FC.pose_others_tick, true)
		-- as edições passam a ficar por cima da animação de novo
		for _, sk in ipairs(pz.skels) do for _, e in ipairs(sk.joints) do e.lr, e.lp = nil, nil end end
	end
end

-- estado da UI do Poser
local poser = { filter = "", sel = nil, sel_pk = nil, gizmo = true, gizmo_op = 1, pose_name = "", msg = nil }
port.poser = poser

local function main_joints(pz)
	local sk = pz.skels and pz.skels[pz.skel_i or 1]
	return sk and sk.joints or {}
end

local function joint_by_addr(pz, a)
	for _, e in ipairs(main_joints(pz)) do if e.a == a then return e end end
	return nil
end

local function edit_of(pz, e, create)
	local t = pz.edits[e.name]
	if not t and create then
		t = { ex = 0, ey = 0, ez = 0 }
		pz.edits[e.name] = t
	end
	return t
end

-- zera a edição sem apagá-la: o osso volta para a base (animação ou pausa de pose)
-- e continua pronto para mexer de novo
local function clear_edit(pz, e)
	local t = pz.edits[e.name]
	if not t then return end
	t.ex, t.ey, t.ez = 0, 0, 0
	t.op, t.gr, t.ap = nil, nil, nil
end

local function edit_is_zero(t)
	return t and (t.ex or 0) == 0 and (t.ey or 0) == 0 and (t.ez or 0) == 0 and not t.op and not t.gr and not t.ap
end

local function safe_name(n)
	n = (n or ""):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return n
end

local function pose_save(pz, name)
	local out = { name = name, joints = {} }
	for _, e in ipairs(main_joints(pz)) do
		pcall(function()
			local r, p = e.j:call("get_LocalRotation"), e.j:call("get_LocalPosition")
			if pz.edits[e.name] and e.lr then r, p = e.lr, e.lp end
			out.joints[e.name] = { r = { r.w, r.x, r.y, r.z }, p = { p.x, p.y, p.z } }
		end)
	end
	json.dump_file("NASK_Fighter\\pose_" .. name .. ".json", out)
	local known = false
	for _, n in ipairs(cfg.poses) do if n == name then known = true end end
	if not known then table.insert(cfg.poses, name); table.sort(cfg.poses); save_cfg() end
end

local function pose_load(pz, name)
	local d = json.load_file("NASK_Fighter\\pose_" .. name .. ".json")
	if not d or not d.joints then return false end
	local n = 0
	for _, e in ipairs(main_joints(pz)) do
		local j = d.joints[e.name]
		if j and j.r and j.p then
			local t = edit_of(pz, e, true)
			t.ex, t.ey, t.ez, t.op = 0, 0, 0, nil
			t.gr = Quaternion.new(j.r[1], j.r[2], j.r[3], j.r[4]):normalized()
			t.ap = Vector3f.new(j.p[1], j.p[2], j.p[3])
			n = n + 1
		end
	end
	return n > 0
end

local function ui_poser(go, xform, pk)
	poser.ui_t, poser.ui_pk = os.clock(), pk
	local pz = poser_of(go, xform)
	if #pz.skels == 0 then
		hint("Nenhum osso encontrado neste objeto nem nos filhos dele.")
		if imgui.button("Procurar de novo") then pz.skels = build_skels(go, xform) end
		return
	end
	if not pz.held then
		hint("Tem cabelo/roupa com física? Marque \"Pausa de pose\" para a física seguir a pose.")
	end
	-- mover o personagem inteiro (gizmo)
	do
		local e = port.cmove[pk]
		if not e then
			local root = xform
			pcall(function()
				for _ = 1, 8 do
					local par = root:call("get_Parent")
					local pgo = par and par:call("get_GameObject")
					if pgo and NASK_FC.code_of(pgo) then root = par else break end
				end
			end)
			e = { xf = root, off = { 0, 0, 0 }, on = false, gizmo = true }
			port.cmove[pk] = e
		end
		-- v2.6.29: só para lutadores da luta (P1/P2). No VS walk e nos menus o jogo
		-- move o personagem de outro jeito e o gizmo o quebrava.
		local in_battle = false
		pcall(function()
			local pbm = sdk.find_type_definition("gBattle"):get_field("PBManager"):get_data()
			local rg = e.xf:call("get_GameObject")
			for i = 0, 1 do
				local pb = pbm.Players[i]
				local go = pb and pb:get_GameObject()
				if go and rg and addr(go) == addr(rg) then in_battle = true end
			end
		end)
		e.allowed = in_battle
		if not in_battle then
			if e.on then e.on = false; e.off = { 0, 0, 0 } end
			imgui.begin_disabled(true)
			imgui.checkbox("Mover personagem##cm" .. pk, false)
			imgui.end_disabled()
			tooltip("Só na luta ou no treino. No VS walk e nos menus o jogo controla a posição do personagem.")
			goto cm_done
		end
		local ch
		ch, e.on = imgui.checkbox("Mover personagem##cm" .. pk, e.on)
		if ch then poser.sel_pk = pk end
		tooltip("Mostra um gizmo no pé do personagem: arraste as setas (X vermelho, Y verde, Z azul)\nou o quadrado (move na tela). Funciona melhor com o jogo pausado.")
		if e.on then
			imgui.same_line()
			if imgui.button("Voltar ao lugar##cmr" .. pk) then e.off = { 0, 0, 0 } end
			imgui.same_line()
			imgui.text_colored(string.format("%.2f  %.2f  %.2f", e.off[1], e.off[2], e.off[3]), MUTED)
		end
		::cm_done::
	end
	local joints = main_joints(pz)
	if poser.sel_pk ~= pk then poser.sel, poser.sel_pk = nil, pk end

	-- lista de ossos
	imgui.push_item_width(-110)
	changed, poser.filter = input("Procurar osso##pf", poser.filter)
	imgui.pop_item_width()
	local f = poser.filter:lower()
	imgui.begin_child_window("##bones" .. tostring(pk), Vector2f.new(-1, 170), true, 0)
	for _, e in ipairs(joints) do
		if f == "" or e.name:lower():find(f, 1, true) then
			local te = pz.edits[e.name]
			local mark = (te and not edit_is_zero(te)) and "* " or ""
			if colored_button(mark .. e.name .. "##b" .. e.a, poser.sel == e.a, Vector2f.new(-1, 0)) then poser.sel = e.a end
		end
	end
	imgui.end_child_window()

	-- osso selecionado
	local e = poser.sel and joint_by_addr(pz, poser.sel)
	if e then
		imgui.text_colored(e.name, accent(1.0))
		local t = edit_of(pz, e, false)
		local rot = Vector3f.new(t and t.ex or 0, t and t.ey or 0, t and t.ez or 0)
		local c1, nr = imgui.drag_float3("Girar (°)", rot, 0.4, -360, 360)
		if c1 then
			t = edit_of(pz, e, true)
			t.ex, t.ey, t.ez = nr.x, nr.y, nr.z
		end
		tooltip("Gira o osso nos eixos X / Y / Z dele (arraste ou Ctrl+clique para digitar)")
		local off = (t and t.op) or Vector3f.new(0, 0, 0)
		local c2, no = imgui.drag_float3("Mover (m)", off, 0.002, -5, 5)
		if c2 then
			t = edit_of(pz, e, true)
			t.op = no
		end
		if imgui.button("Zerar osso") then clear_edit(pz, e) end
		imgui.same_line()
		if imgui.button("Zerar todos os ossos") then
			for _, t in pairs(pz.edits) do t.ex, t.ey, t.ez, t.op, t.gr, t.ap = 0, 0, 0, nil, nil, nil end
		end
		imgui.same_line()
		changed, poser.gizmo = imgui.checkbox("Gizmo no osso", poser.gizmo)
		imgui.same_line()
		imgui.push_item_width(90)
		changed, poser.gizmo_op = imgui.combo("##pgop", poser.gizmo_op, { "Girar", "Mover" })
		imgui.pop_item_width()
	else
		hint("Escolha um osso na lista.")
	end

	-- poses salvas
	section("POSES SALVAS")
	imgui.push_item_width(-170)
	changed, poser.pose_name = input("##posename", poser.pose_name)
	imgui.pop_item_width()
	imgui.same_line()
	if imgui.button("Salvar pose") then
		local n = safe_name(poser.pose_name)
		if n == "" then n = os.date("pose %d-%m %H%M%S") end
		pose_save(pz, n)
		poser.msg = "Pose salva: " .. n
	end
	tooltip("Salva a pose inteira (todos os ossos) em reframework/data/NASK_Fighter")
	if poser.msg then hint(poser.msg) end
	for i, n in ipairs(cfg.poses) do
		imgui.push_id("pz" .. i)
		if imgui.button("Carregar") then
			poser.msg = pose_load(pz, n) and ("Pose carregada: " .. n) or ("Não consegui carregar: " .. n)
		end
		imgui.same_line()
		if imgui.button("Tirar") then table.remove(cfg.poses, i); save_cfg(); imgui.pop_id(); return end
		tooltip("Tira da lista (o arquivo continua na pasta)")
		imgui.same_line()
		imgui.text(n)
		imgui.pop_id()
	end
end

-- gizmo do osso selecionado (chamado todo frame com o HUD aberto)
local function draw_poser_gizmo(show)
	if not show or not poser.gizmo or not poser.sel or not poser.sel_pk then return end
	-- com "Mover personagem" ligado, só o gizmo de mover aparece (os dois juntos brigavam)
	local cm = port.cmove and port.cmove[poser.sel_pk]
	if cm and cm.on then return end
	local pz = posers[poser.sel_pk]
	local e = pz and joint_by_addr(pz, poser.sel)
	if not e then return end
	pcall(function()
		local wp, wr = e.j:call("get_Position"), e.j:call("get_Rotation")
		local mat = wr:to_mat4()
		mat[3] = Vector4f.new(wp.x, wp.y, wp.z, 1.0)
		local ops = imgui.ImGuizmoOperation
		local op = ops and (poser.gizmo_op == 2 and ops.TRANSLATE or ops.ROTATE) or nil
		local ch, m2 = draw.gizmo(e.a, mat, op)
		if not ch then return end
		nlights.gizmo_until = os.clock() + 0.25
		local par = e.j:call("get_Parent")
		local pr = par and par:call("get_Rotation") or pz.xform:call("get_Rotation")
		local pp = par and par:call("get_Position") or pz.xform:call("get_Position")
		local t = edit_of(pz, e, true)
		if poser.gizmo_op == 2 then
			local np = m2[3]:to_vec3()
			t.ap, t.op = qconj(pr) * (np - pp), nil
		else
			local q = m2:to_quat()
			if q.x == q.x then
				t.gr = (qconj(pr) * q):normalized()
				t.ex, t.ey, t.ez = 0, 0, 0
			end
		end
	end)
end

local function inspect_object(go, xform, id, fid)
	imgui.push_id("insp" .. tostring(id))
	local pk = addr(xform)
	local on = pose_hold[pk] ~= nil
	changed, on = imgui.checkbox("Pausa de pose (física acompanha)", on)
	if changed then set_pose_hold(go, xform, on) end
	tooltip("Congela a animação deste personagem e faz a física (cabelo, roupa, correntes)\nseguir a pose do Poser. O jogo continua rodando.\nEnquanto estiver ligada, o olhar e o IK dos outros lutadores ficam desligados\npara eles não acompanharem a pose deste.\nNão use junto com o F1 / Jogo Pausado (que congela a física também).")
	if pose_hold[pk] then
		imgui.same_line()
		local pz = posers[pk]
		local nj = 0
		for _, sk in ipairs(pz and pz.skels or {}) do nj = nj + #sk.joints end
		hint(string.format("(%d osso(s) na pose base)", nj))
		if imgui.button("Usar a pose atual como base") then set_pose_hold(go, xform, false); set_pose_hold(go, xform, true) end
		tooltip("Guarda de novo a pose da animação como está agora (as edições do Poser continuam por cima).")
		if NASK_FC.is_scene_frozen() then
			imgui.text_colored("O jogo está pausado (F1): a física fica parada. Despause para ela acompanhar.", WARN)
		end
	end
	if open_tree("Poser", "poser" .. tostring(id), false) then
		ui_poser(go, xform, pk)
		imgui.tree_pop()
	end
	if open_tree("Materiais e Pedaços", "mats" .. tostring(id), false) then
		ui_parts(go, xform, fid)
		imgui.tree_pop()
	end
	imgui.pop_id()
end

-- ---------------------------------------------------------------------------
-- Luzes do cenário (Console > Luzes): via.Transform para mover + cor
-- As mudanças ficam guardadas e são reaplicadas todo frame (o jogo reposiciona).
-- ---------------------------------------------------------------------------
local slights = { edits = {}, gizmo = nil }

local function slight_edit(comp, xf)
	local k = addr(comp)
	local e = slights.edits[k]
	if not e then
		e = { comp = comp, xf = xf }
		pcall(function()
			e.o_pos, e.o_rot = xf:call("get_Position"), xf:call("get_Rotation")
			e.o_color, e.o_int = comp:call("get_Color"), comp:call("get_Intensity")
			e.o_rad = comp:call("get_Radius")
		end)
		slights.edits[k] = e
	end
	return e
end

local function slight_restore(k)
	local e = slights.edits[k]
	if not e then return end
	pcall(function()
		if e.o_pos then e.xf:call("set_Position", e.o_pos); e.xf:call("set_Rotation", e.o_rot) end
		if e.o_color then e.comp:call("set_Color", e.o_color) end
		if e.o_int then e.comp:call("set_Intensity", e.o_int) end
		if e.o_rad then e.comp:call("set_Radius", e.o_rad) end
	end)
	slights.edits[k] = nil
	if slights.gizmo == k then slights.gizmo = nil end
end

local function slights_apply_xf()
	for k, e in pairs(slights.edits) do
		local ok = pcall(function()
			if e.pos then e.xf:call("set_Position", e.pos) end
			if e.rot then e.xf:call("set_Rotation", e.rot) end
		end)
		if not ok then slights.edits[k] = nil end
	end
end
local function slights_apply_light()
	for _, e in pairs(slights.edits) do
		pcall(function()
			if e.color then e.comp:call("set_Color", e.color) end
			if e.int then e.comp:call("set_Intensity", e.int) end
			if e.rad then e.comp:call("set_Radius", e.rad) end
		end)
	end
end
re.on_application_entry("UpdateMotion", slights_apply_xf)
re.on_application_entry("PrepareRendering", function() slights_apply_xf(); slights_apply_light() end)

local function ui_scene_light(r, id)
	slights.ui_t = os.clock()
	local comp, xf = r.comp, r.xform
	local k = addr(comp)
	local e = slights.edits[k]
	imgui.push_id("sl" .. tostring(id))
	hint(component_label(comp))

	if open_tree("via.Transform", "slxf" .. k, true) then
		local pos = xf:call("get_Position")
		local c1, np = imgui.drag_float3("Posição", pos, 0.01, -10000, 10000)
		if c1 then e = slight_edit(comp, xf); e.pos = np end
		local eul = xf:call("get_EulerAngle")
		local deg = Vector3f.new(math.deg(eul.x), math.deg(eul.y), math.deg(eul.z))
		local c2, nd = imgui.drag_float3("Rotação (°)", deg, 0.5, -360, 360)
		if c2 then
			e = slight_edit(comp, xf)
			xf:call("set_EulerAngle", Vector3f.new(math.rad(nd.x), math.rad(nd.y), math.rad(nd.z)))
			e.rot = xf:call("get_Rotation")
		end
		if imgui.button("Mover para câmera") then
			local p, q = NASK_FC.cam_pos_rot()
			if p then e = slight_edit(comp, xf); e.pos, e.rot = p, q end
		end
		tooltip("Leva a luz para a posição e direção da câmera")
		imgui.same_line()
		local gz = slights.gizmo == k
		changed, gz = imgui.checkbox("Gizmo", gz)
		if changed then slights.gizmo = gz and k or nil; if gz then slight_edit(comp, xf) end end
		tooltip("Mover/girar a luz direto na tela (use o modo do gizmo de Extras > Luzes)")
		imgui.tree_pop()
	end

	if open_tree("Luz", "sllt" .. k, true) then
		pcall(function()
			local col = comp:call("get_Color")
			if col then
				local c, nc = imgui.color_edit3("Cor", Vector3f.new(col.x, col.y, col.z), 17301504)
				if c then e = slight_edit(comp, xf); e.color = nc; comp:call("set_Color", nc) end
				tooltip("Clique no quadrado para abrir o seletor de cor")
			end
		end)
		pcall(function()
			local it = comp:call("get_Intensity")
			if it then
				local c, v = imgui.drag_float("Intensidade", it, math.max(0.5, it * 0.01), 0, 1000000, "%.1f")
				if c then e = slight_edit(comp, xf); e.int = v end
			end
		end)
		pcall(function()
			local rad = comp:call("get_Radius")
			if rad then
				local c, v = imgui.drag_float("Alcance", rad, 0.02, 0, 1000, "%.2f m")
				if c then e = slight_edit(comp, xf); e.rad = v end
			end
		end)
		imgui.tree_pop()
	end

	if slights.edits[k] then
		if imgui.button("Voltar ao original") then slight_restore(k) end
		tooltip("Desfaz posição, rotação, cor, intensidade e alcance desta luz")
	end
	imgui.pop_id()
end

-- gizmo da luz do cenário escolhida (todo frame com o HUD aberto)
local function draw_slight_gizmo(show)
	local k = slights.gizmo
	local e = k and slights.edits[k]
	if not show or not e then return end
	pcall(function()
		local mat = e.xf:call("get_WorldMatrix")
		mat[3].w = 1.0
		local ops = imgui.ImGuizmoOperation
		local op = ops and ((cfg.light_gizmo_op == 1 and ops.TRANSLATE) or (cfg.light_gizmo_op == 2 and ops.ROTATE)) or nil
		local ch, m2 = draw.gizmo(k, mat, op)
		if ch then
			local q = m2:to_quat()
			if q.x == q.x then e.pos, e.rot = m2[3]:to_vec3(), q end
			nlights.gizmo_until = os.clock() + 0.25
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Aba: Modo Foto
-- ---------------------------------------------------------------------------
-- Mover cenário / luzes do cenário ------------------------------------------
-- Os dois são independentes: dá para ligar um, o outro ou os dois.
-- As luzes que fazem parte do cenário seguem o cenário e depois o próprio ajuste.
local function stage_group() return { items = nil, off = Vector3f.new(0, 0, 0), yaw = 0.0, scale = 1.0, msg = nil } end
local stage = { stage = stage_group(), lights = stage_group() }

local function stage_collect(only_lights)
	local items = {}
	local scene = current_scene()
	local prefix = NASK_FC and NASK_FC.stage_folder_prefix and NASK_FC.stage_folder_prefix()
	if only_lights then
		local arr = scene:call("findComponents(System.Type)", sdk.typeof("via.render.Light"))
		local set = {}
		for _, l in ipairs(arr and arr:get_elements() or {}) do
			local go = l:call("get_GameObject")
			local nm = (go and go:call("get_Name") or ""):lower()
			if not nm:find("^nask") and not nm:find("^freecam") and not nm:find("^esf") then
				set[addr(go:call("get_Transform"))] = go:call("get_Transform")
			end
		end
		for k, xf in pairs(set) do
			local par = xf:call("get_Parent")
			local inside = false
			while par do
				if set[addr(par)] then inside = true break end
				par = par:call("get_Parent")
			end
			if not inside then
				local ok, path = pcall(function() return xf:call("get_GameObject"):call("get_Folder"):call("get_Path") end)
				table.insert(items, { xf = xf, in_stage = (prefix ~= nil and ok and path and path:find(prefix, 1, true) ~= nil) or false })
			end
		end
	else
		if not prefix then return nil, "Só funciona dentro de uma luta/treino." end
		local arr = scene:call("findComponents(System.Type)", sdk.typeof("via.Transform"))
		for _, xf in ipairs(arr and arr:get_elements() or {}) do
			if not xf:call("get_Parent") then
				local ok, path = pcall(function() return xf:call("get_GameObject"):call("get_Folder"):call("get_Path") end)
				if ok and path and path:find(prefix, 1, true) then table.insert(items, { xf = xf }) end
			end
		end
	end
	for _, it in ipairs(items) do
		it.pos = it.xf:call("get_Position"); it.rot = it.xf:call("get_Rotation"); it.scl = it.xf:call("get_LocalScale")
	end
	if #items == 0 then return nil, "Nenhum objeto encontrado." end
	return items
end

local function group_quat(g)
	local a = math.rad(g.yaw) * 0.5
	return Quaternion.new(math.cos(a), 0, math.sin(a), 0)
end

local function stage_restore(which)
	local g = stage[which]
	for _, it in ipairs(g.items or {}) do
		pcall(function()
			it.xf:call("set_Position", it.pos); it.xf:call("set_Rotation", it.rot); it.xf:call("set_LocalScale", it.scl)
		end)
	end
	stage[which] = stage_group()
end

local function stage_apply()
	local S, L = stage.stage, stage.lights
	local qs = S.items and group_quat(S)
	if S.items then
		for _, it in ipairs(S.items) do
			pcall(function()
				it.xf:call("set_Position", (qs * it.pos) * S.scale + S.off)
				it.xf:call("set_Rotation", (qs * it.rot):normalized())
				it.xf:call("set_LocalScale", it.scl * S.scale)
			end)
		end
	end
	if L.items then
		local ql = group_quat(L)
		for _, it in ipairs(L.items) do
			pcall(function()
				local p, r = it.pos, it.rot
				-- luz do cenário com o cenário movido: parte da posição já movida
				if qs and it.in_stage then p, r = (qs * p) * S.scale + S.off, qs * r end
				it.xf:call("set_Position", (ql * p) * L.scale + L.off)
				it.xf:call("set_Rotation", (ql * r):normalized())
			end)
		end
	end
end

local function ui_stage_group(which, label)
	local g = stage[which]
	local on = g.items ~= nil
	local ch, nv = imgui.checkbox(label .. "##stg_" .. which, on)
	if ch then
		if nv then
			local items, err = stage_collect(which == "lights")
			if items then g.items = items; g.msg = #items .. " objeto(s)" else g.msg = err end
		else
			stage_restore(which)
		end
		g = stage[which]
	end
	if g.msg then imgui.same_line(); hint(g.msg) end
	if g.items then
		imgui.indent(14)
		local c1
		c1, g.off = imgui.drag_float3("Posição##stp_" .. which, g.off, 0.01, -1000, 1000)
		c1, g.yaw = imgui.slider_float("Girar##sty_" .. which, g.yaw, -180, 180, "%.1f°")
		c1, g.scale = imgui.slider_float("Escala##sts_" .. which, g.scale, 0.1, 5.0, "%.2f")
		if imgui.button("Voltar ao original##str_" .. which) then
			g.off, g.yaw, g.scale = Vector3f.new(0, 0, 0), 0.0, 1.0
		end
		imgui.unindent(14)
	end
end

local function ui_stage_move()
	ui_stage_group("stage", "Mover cenário")
	ui_stage_group("lights", "Mover luzes do cenário")
	hint("Um não desliga o outro. Desmarcar devolve tudo ao lugar.")
end

re.on_application_entry("UpdateMotion", function()
	if stage.stage.items or stage.lights.items then stage_apply() end
end)

local ui_photo_settings_ref = nil
-- barra de vidro clicável com o título no centro (abre/fecha)
local function glass_header(id, title, open, h)
	h = h or 32
	local W = imgui.get_window_size().x - 28
	imgui.set_cursor_pos(Vector2f.new(14, imgui.get_cursor_pos().y))
	local p = imgui.get_cursor_screen_pos()
	local clicked = imgui.invisible_button(id, Vector2f.new(W, h))
	local hov = imgui.is_item_hovered()
	pcall(function()
		local dl = window_dl()
		local a, b = Vector2f.new(p.x, p.y), Vector2f.new(p.x + W, p.y + h)
		local g = glass()
		local r = 10
		if cfg.style == 4 then
			local mx = a.x + W * 0.5
			local k = hov and 1.25 or 1.0
			local side, mid = rgba(240, 226, 233, 0.07 * k), rgba(244, 228, 238, 0.42 * k)
			-- pontas arredondadas (na cor da ponta) + degradê no meio
			local ra, rb = Vector2f.new(a.x + r, a.y), Vector2f.new(b.x - r, b.y)
			dl:add_rect_filled(a, Vector2f.new(a.x + r, b.y), side, r, 80)
			dl:add_rect_filled(Vector2f.new(b.x - r, a.y), b, side, r, 160)
			dl:add_rect_filled_multi_color(ra, Vector2f.new(mx, b.y), side, mid, mid, side)
			dl:add_rect_filled_multi_color(Vector2f.new(mx, a.y), rb, mid, side, side, mid)
			local hs, hm = rgba(255, 255, 255, 0), rgba(255, 255, 255, 0.22)
			dl:add_rect_filled_multi_color(ra, Vector2f.new(mx, a.y + h * 0.45), hs, hm, hs, hs)
			dl:add_rect_filled_multi_color(Vector2f.new(mx, a.y), Vector2f.new(rb.x, a.y + h * 0.45), hm, hs, hs, hs)
			dl:add_rect(a, b, rgba(255, 255, 255, hov and 0.30 or 0.16), r, 0, 1.0)
			if open then
				local pa, pb = rgba(238, 168, 214, 0), rgba(238, 168, 214, 0.95)
				dl:add_rect_filled_multi_color(Vector2f.new(a.x + W * 0.2, b.y - 2), Vector2f.new(mx, b.y), pa, pb, pb, pa)
				local la, lb = rgba(170, 158, 236, 0.95), rgba(170, 158, 236, 0)
				dl:add_rect_filled_multi_color(Vector2f.new(mx, b.y - 2), Vector2f.new(b.x - W * 0.2, b.y), la, lb, lb, la)
			end
			if sub_font then imgui.push_font(sub_font) end
			local ts = imgui.calc_text_size(title)
			dl:add_text(Vector2f.new(p.x + (W - ts.x) * 0.5, p.y + (h - ts.y) * 0.5), rgba(250, 248, 252, 1.0), title)
			if sub_font then imgui.pop_font() end
			return
		end
		dl:add_rect_filled(a, b, g and rgba(255, 255, 255, hov and 0.16 or 0.09) or accent(hov and 0.24 or 0.14), r, 0)
		-- reflexo de vidro na metade de cima, na largura toda da barra (cantos de cima arredondados)
		dl:add_rect_filled(Vector2f.new(a.x + 1, a.y + 1), Vector2f.new(b.x - 1, a.y + h * 0.5), rgba(255, 255, 255, g and 0.08 or 0.30), r - 1, 48)
		dl:add_rect(a, b, rgba(255, 255, 255, open and 0.55 or 0.32), r, 0, 1.0)
		if open then
			-- linha de luz embaixo quando aberto
			dl:add_line(Vector2f.new(a.x + W * 0.3, b.y - 1), Vector2f.new(b.x - W * 0.3, b.y - 1), accent(0.9), 2.0)
		end
		if sub_font then imgui.push_font(sub_font) end
		local ts = imgui.calc_text_size(title)
		local tx, ty = p.x + (W - ts.x) * 0.5, p.y + (h - ts.y) * 0.5
		dl:add_text(Vector2f.new(tx, ty), INK, title)
		if sub_font then imgui.pop_font() end
	end)
	return clicked
end

local function panel(title, key)
	imgui.spacing()
	cfg.panels = cfg.panels or {}
	if cfg.panels[key] == nil then cfg.panels[key] = false end
	if glass_header("##pnl_" .. key, title, cfg.panels[key]) then
		cfg.panels[key] = not cfg.panels[key]
		save_cfg()
	end
	if cfg.panels[key] then imgui.spacing() end
	return cfg.panels[key]
end


local function tab_modo_foto()
	local on = NASK_FC.on == true
	local cap_txt = "Atalhos"
	local W = imgui.get_window_size().x
	local kbw = math.max(imgui.calc_text_size("Portátil").x + 6, imgui.calc_text_size(cap_txt).x + 6, 62)
	local kbh = imgui.calc_text_size(cap_txt).y + 4 + 26
	local gap = 16
	-- o botão fica no centro da janela; o teclado vai no espaço à direita dele
	local bw = math.min(300, W - 2 * (kbw + gap) - 28)
	local bx = (W - bw) * 0.5
	local y = imgui.get_cursor_pos().y + 2
	imgui.set_cursor_pos(Vector2f.new(bx, y + (kbh - 40) * 0.5))
	if glass_button("##modofoto", on and "MODO FOTO: LIGADO" or "MODO FOTO: DESLIGADO", on, bw, 40) then
		req("toggle_freecam")
	end
	tooltip("Tecla: " .. keyname("Activate FreeCam"))
	imgui.same_line()
	imgui.set_cursor_pos(Vector2f.new(bx + bw + gap, y))
	if keyboard_button("##kbd", cap_txt, kbw, kbh) then keys_win.open = not keys_win.open end
	imgui.same_line()
	imgui.set_cursor_pos(Vector2f.new(bx - gap - kbw, y))
	if port.camera_button("##portbtn", "Portátil", kbw, kbh) then
		port.open = not port.open
		if port.open then hud_open = false end
	end
	tooltip("Modo foto Portátil (simplificado). Tecla: " .. keyname("NASK Portatil"))
	tooltip("Configurar atalhos (teclado, controle e mouse)")
	imgui.set_cursor_pos(Vector2f.new(14, y + math.max(kbh, 40) + 8))

	local items = {}
	local function add(label, draw) table.insert(items, { w = check_w(label), draw = draw }) end
	add("Hide UI", function()
		changed, NASK_FC.hide_ui = imgui.checkbox("Hide UI", NASK_FC.hide_ui == true)
		tooltip("Esconde a UI do jogo. Tecla: " .. keyname("Hide UI"))
	end)
	add("Limpar imagem", function()
		local clean = NASK_FC.clean == true
		changed, clean = imgui.checkbox("Limpar imagem", clean)
		if changed then port.set_clean(clean) end
		tooltip("Desliga Custom LUT, Vignette, Color Correction e os efeitos do VS Walk.\nDesmarcar volta tudo como estava.")
	end)
	add("2x Quality", function()
		local hq_top = NASK_FC.get_hi_quality()
		changed, hq_top = imgui.checkbox("2x Quality##top", hq_top)
		if changed then NASK_FC.set_hi_quality(hq_top) end
		tooltip("Atalho do 2x Quality (também fica em Visual Settings)")
	end)
	add("Preview vertical", function()
		changed, cfg.vpreview = imgui.checkbox("Preview vertical##top", cfg.vpreview == true); if changed then save_cfg() end
		tooltip("Gira a imagem da tela 90° para você ver a foto vertical em pé, sem virar o pescoço.\nFunciona com ou sem o Modo Foto. A foto continua saindo como está na câmera e o DOF não muda.\nSe girar para o lado errado, use \"Inverter giro do preview\" em Controle da Câmera.")
	end)
	add("Greenscreen", function()
		local gs_on = NASK_FC.get_greenscreen()
		changed, gs_on = imgui.checkbox("Greenscreen##top", gs_on)
		if changed then NASK_FC.set_greenscreen(gs_on) end
		tooltip("Fundo verde atrás dos lutadores (a cor fica em Extras).\nFunciona melhor no estágio Training Room.")
	end)
	centered_row(items, 16)
	imgui.spacing()

	-- Visual Settings ------------------------------------------------------
	if panel("Visual Settings", "visual") then
		port.rect_begin()
		changed, cfg.vs_walk_off = imgui.checkbox("Desativar Efeitos do VS Walk", cfg.vs_walk_off)
		if changed then save_cfg() end
		tooltip("Desliga o LDRPostProcess da câmera (efeitos da entrada/VS)")
		imgui.same_line()
		local hq = NASK_FC.get_hi_quality()
		changed, hq = imgui.checkbox("2x Quality", hq)
		if changed then NASK_FC.set_hi_quality(hq) end
		tooltip("Renderiza no dobro da resolução e reduz (mais nitidez, mais pesado)")
		NASK_FC.ui_visual()
		port.rect_end()
	end

	-- Extras ---------------------------------------------------------------
	if panel("Extras", "extras") then
		port.rect_begin()
		ui_lights()
		section("RAY TRACING E GREENSCREEN")
		NASK_FC.ui_extras()
		section("LUTADORES")
		NASK_FC.ui_fighter_fx()
		section("CENÁRIO")
		NASK_FC.ui_stage_display()
		imgui.spacing()
		ui_stage_move()
		port.rect_end()
	end

	-- Controle da Câmera ---------------------------------------------------
	if panel("Controle da Câmera", "camera") then
	port.rect_begin()
	section("LENTE")
	local fov = NASK_FC.get_fov()
	if fov then
		imgui.push_item_width(-90)
		changed, fov = imgui.slider_float("FOV", fov, 5.0, 120.0, "%.1f°")
		imgui.pop_item_width()
		if changed then NASK_FC.set_fov(fov) end
		imgui.same_line()
		if imgui.button("Reset##fov") then NASK_FC.reset_fov() end
		hint("Zoom: " .. keyname("Zoom In") .. " / " .. keyname("Zoom Out"))
	else
		hint("Câmera ainda não encontrada.")
	end
	if imgui.checkbox("Travar câmera", NASK_FC.is_cam_frozen()) then req("freeze_cam") end
	tooltip("Tecla: " .. keyname("Freeze Camera"))
	changed, cfg.no_distort = imgui.checkbox("Sem distorção de lente", cfg.no_distort ~= false); if changed then save_cfg() end
	changed, cfg.no_2d = imgui.checkbox("Sem distorção 2D dos lutadores", cfg.no_2d ~= false); if changed then save_cfg() end
	tooltip("O SF6 deforma os lutadores para parecerem 2D na câmera da luta; com a câmera livre\nlonge do centro eles ficam esticados. Liga sozinho com o Modo Foto e volta ao sair.")
	changed, cfg.fix_overlap = imgui.checkbox("Corrigir sobreposição dos lutadores", cfg.fix_overlap ~= false); if changed then save_cfg() end
	tooltip("Na luta o jogo desenha um lutador sempre por cima do outro. Com a câmera livre\nisso faz o de trás aparecer na frente. Liga sozinho com o Modo Foto e volta ao sair.")
	changed, cfg.vp_flip = imgui.checkbox("Inverter giro do preview", cfg.vp_flip == true); if changed then save_cfg() end
	tooltip("Gira o Preview vertical para o outro lado.")
	tooltip("Desliga a distorção de lente da câmera do jogo enquanto o Modo Foto está ligado,\npara os personagens e o cenário não ficarem esticados de perto.\nSe ainda esticar nas bordas, é a perspectiva do FOV aberto: baixe o FOV.")

	section("INCLINAÇÃO")
	local step = math.rad(cfg.roll_step)
	imgui.begin_disabled(not on)
	if imgui.button("<< " .. math.floor(cfg.roll_step) .. "°", Vector2f.new(96, 0)) then NASK_FC.pending_roll = -step end
	tooltip("Tecla: " .. keyname("NASK Girar Esquerda"))
	imgui.same_line()
	if imgui.button("Zerar", Vector2f.new(96, 0)) then NASK_FC.reset_roll = true end
	tooltip("Tecla: " .. keyname("NASK Zerar Inclinacao"))
	imgui.same_line()
	if imgui.button(math.floor(cfg.roll_step) .. "° >>", Vector2f.new(96, 0)) then NASK_FC.pending_roll = step end
	tooltip("Tecla: " .. keyname("NASK Girar Direita"))
	imgui.end_disabled()
	hint("Inclinar fino: " .. keyname("Roll Left") .. " / " .. keyname("Roll Right") .. "  (com o Modo Foto ligado)")

	section("MOVIMENTO")
	imgui.push_item_width(-150)
	local st = NASK_FC.settings
	changed, st.move_speed = imgui.slider_float("Vel. movimento", st.move_speed, 0.2, 15.0, "%.1f m/s")
	if changed then NASK_FC.save() end
	changed, st.rot_speed = imgui.slider_float("Vel. rotação", st.rot_speed, 0.1, 3.0, "%.2f")
	if changed then NASK_FC.save() end
	imgui.pop_item_width()
	hint(keyname("CModifier") .. " = rápido   ·   " .. keyname("CModifier3") .. " = lento")

	section("CONTROLE")
	imgui.push_item_width(-150)
	changed, cfg.stick.deadzone = imgui.slider_float("Zona morta", cfg.stick.deadzone, 0.0, 0.40, "%.2f"); if changed then save_cfg() end
	tooltip("Ignora toques leves no analógico (evita a câmera pular).")
	changed, cfg.stick.curve = imgui.slider_float("Curva", cfg.stick.curve, 1.0, 3.5, "%.2f"); if changed then save_cfg() end
	tooltip("Maior = mais precisão no começo do curso do analógico.")
	changed, cfg.stick.sens = imgui.slider_float("Sensibilidade", cfg.stick.sens, 0.1, 2.5, "%.2f"); if changed then save_cfg() end
	imgui.pop_item_width()
	changed, NASK_FC.settings.invert_pad = imgui.checkbox("Inverter Y do analógico", NASK_FC.settings.invert_pad)
	if changed then NASK_FC.save() end
	imgui.same_line()
	changed, cfg.move_stick = imgui.checkbox("Analógico esq. move a câmera", cfg.move_stick); if changed then save_cfg() end
	imgui.spacing()
	port.rect_end()
	end

	-- Pasta das fotos (com um respiro em cima)
	imgui.spacing(); imgui.spacing(); imgui.spacing()
	if ui_photo_settings_ref then ui_photo_settings_ref() end
end

-- ---------------------------------------------------------------------------
-- Aba: Console
-- ---------------------------------------------------------------------------
local qs = { text = "", mode = 1, results = nil, msg = nil }
local qs_render
local LIGHT_TYPES = { "via.render.Light", "via.render.SpotLight", "via.render.PointLight", "via.render.ProjectionSpotLight",
	"via.render.DirectionalLight", "via.render.AreaLight", "via.render.CapsuleSpotLight", "via.render.IESLight",
	"via.render.IESLightSpot", "via.render.IESPointLight", "via.render.SkyLight", "via.render.AtmosphericDirectionalLight",
	"via.render.BeautyDirectionalLight" }
local QS_MODES = { "Nome contém", "Personagens (esf)", "NPCs / figurantes", "Luzes (via.render.Light)" }
local NPC_PATTERNS = { "npc", "mob", "crowd", "audience", "people", "human", "esm%d", "esn%d", "ch%d%d%d", "chr", "wpl", "om11000" }

local function is_npc_name(lname)
	if lname:find("esf%d%d%d") then return false end
	for _, p in ipairs(NPC_PATTERNS) do
		if lname:find(p) then return true end
	end
	return false
end

local function qs_search(st)
	local qs = st or qs
	qs.results, qs.msg = {}, nil
	local ok, err = pcall(function()
		local term = qs.text:lower()
		local seen = {}
		local function add(go, name, comp)
			if go and not seen[go] then
				seen[go] = true
				table.insert(qs.results, { name = name, go = go, xform = go:call("get_Transform"), comp = comp })
			end
		end
		if qs.mode == 4 then
			-- todos os tipos de luz (cada um separado: a busca pela classe base não traz todos)
			local seen_c = {}
			for _, tn in ipairs(LIGHT_TYPES) do
				pcall(function()
					local arr = current_scene():call("findComponents(System.Type)", sdk.typeof(tn))
					for _, comp in ipairs(arr and arr:get_elements() or {}) do
						local k = addr(comp)
						if not seen_c[k] and #qs.results < 600 then
							seen_c[k] = true
							pcall(function()
								local go = comp:call("get_GameObject")
								local name = go and go:call("get_Name") or ""
								if term == "" or name:lower():find(term, 1, true) then
									local ok, full = pcall(function() return comp:get_type_definition():get_full_name() end)
									local short = ((ok and full) or ""):gsub("^via%.render%.", ""):gsub("Light$", "")
									local act = false
									pcall(function() act = comp:call("get_Enabled") == true and go:call("get_DrawSelf") == true end)
									table.insert(qs.results, { name = name, label = name, ltype = (short ~= "" and short or "Light"),
										active = act, go = go, xform = go:call("get_Transform"), comp = comp })
								end
							end)
						end
					end
				end)
			end
		elseif qs.mode == 3 then
			-- NPCs: objetos desenhados com nome de figurante (sem esf)
			for _, o in ipairs(rendered_objects()) do
				local lname = o.name:lower()
				if is_npc_name(lname) and (term == "" or lname:find(term, 1, true)) then add(o.go, o.name) end
				if #qs.results >= 300 then break end
			end
		else
			local arr = current_scene():call("findComponents(System.Type)", sdk.typeof("via.Transform"))
			for _, xf in ipairs(arr and arr:get_elements() or {}) do
				local go = xf:call("get_GameObject")
				local name = go and go:call("get_Name") or ""
				local lname = name:lower()
				local hit = (term == "" or lname:find(term, 1, true))
				if qs.mode == 2 then
					hit = hit and lname:find("^esf") and not lname:find("light")
				end
				if hit then add(go, name) end
				if #qs.results >= 300 then break end
			end
		end
		table.sort(qs.results, function(x, y) return x.name < y.name end)
		if qs.mode == 4 then
			-- luzes: por tipo; dentro do tipo, as ligadas primeiro
			table.sort(qs.results, function(x, y)
				if x.ltype ~= y.ltype then return x.ltype < y.ltype end
				if x.active ~= y.active then return x.active end
				return x.name < y.name
			end)
		end
		if qs.mode == 2 then
			for _, r in ipairs(qs.results) do
				local code = fighter_of(r.go, r.xform)
				if code then
					r.fid = tonumber(code)
					r.label = string.format("%s (esf%s)", FIGHTERS[r.fid] or "Desconhecido", code)
				end
			end
			-- v2.6.24: lutador do Jogador 1 sempre no topo (depois o Jogador 2)
			local pl = {}
			pcall(function()
				local pbm = sdk.find_type_definition("gBattle"):get_field("PBManager"):get_data()
				for i = 0, 1 do
					local pb = pbm.Players[i]
					local go = pb and pb:get_GameObject()
					if go then pl[addr(go)] = i + 1 end
				end
			end)
			for _, r in ipairs(qs.results) do
				pcall(function()
					local xf = r.xform or r.go:call("get_Transform")
					for _ = 1, 10 do
						if not xf then break end
						local g = xf:call("get_GameObject")
						local k = g and pl[addr(g)]
						if k then r.pnum = k break end
						xf = xf:call("get_Parent")
					end
				end)
			end
			-- o número do jogador vale para o lutador inteiro (todas as peças dele),
			-- senão as peças sem número viravam um 2º grupo do mesmo lutador
			local gp = {}
			for _, r in ipairs(qs.results) do
				if r.fid and r.pnum and (gp[r.fid] == nil or r.pnum < gp[r.fid]) then gp[r.fid] = r.pnum end
			end
			for _, r in ipairs(qs.results) do
				if r.fid then r.pnum = gp[r.fid] end
				if r.pnum and r.label then r.label = "P" .. r.pnum .. "  ·  " .. r.label end
			end
			-- depois, pelo número do lutador (Luke esf002 antes de C. Viper esf030)
			table.sort(qs.results, function(x, y)
				local pa, pb = x.pnum or 9, y.pnum or 9
				if pa ~= pb then return pa < pb end
				local a, b = x.fid or 9999, y.fid or 9999
				if a ~= b then return a < b end
				return x.name < y.name
			end)
		end
	end)
	if not ok then qs.msg = "Erro na busca: " .. tostring(err) end
end

qs_render = function(st, pre)
	if st.msg then imgui.text_colored(st.msg, WARN) end
	if st.results then
		hint(#st.results .. " resultado(s)" .. (#st.results >= 600 and " (limite 600)" or ""))
		if #st.results > 0 then
			if imgui.button("Ocultar todos") then
				-- guarda como cada um estava, para "Mostrar todos" devolver igual
				st.snap = st.snap or {}
				for _, r in ipairs(st.results) do
					pcall(function()
						-- (só registra; esconde no laço de baixo, depois de registrar tudo)
						local k = addr(r.go) .. (r.comp and ("/" .. addr(r.comp)) or "")
						if st.snap[k] == nil then
							st.snap[k] = { go = r.go, comp = r.comp, draw = r.go:call("get_DrawSelf"),
								en = r.comp and r.comp:call("get_Enabled") }
						end
					end)
				end
				for _, r in ipairs(st.results) do force_visible(r.go, false) end
			end
			imgui.same_line()
			if imgui.button("Mostrar todos") then
				for _, r in ipairs(st.results) do force_visible(r.go, true) end
				-- luzes: além do DrawSelf, religa o componente e força o jogo a atualizar
				for _, sn in pairs(st.snap or {}) do
					pcall(function()
						force_visible(sn.go, sn.draw ~= false)
						if sn.comp then
							force_comp_enabled(sn.comp, sn.en ~= false)
							pcall(sn.comp.call, sn.comp, "update")
						end
					end)
				end
				for _, r in ipairs(st.results) do
					if r.comp then
						pcall(function()
							if r.go:call("get_DrawSelf") and r.comp:call("get_Enabled") then r.comp:call("update") end
						end)
					end
				end
				st.snap = nil
			end
		end
		local last_group = nil
		local group_open = true
		st.open = st.open or {}
		for i, r in ipairs(st.results) do
			-- personagens: uma aba de vidro por lutador (C. Viper, Luke...);
			-- outras pesquisas: separador quando muda o nome
			local grp = r.fid or (r.comp and ("L:" .. (r.ltype or "Light"))) or r.label or r.name
			if r.comp then
				if grp ~= last_group then
					local cnt, on = 0, 0
					for _, q in ipairs(st.results) do
						if q.comp and q.ltype == r.ltype then cnt = cnt + 1; if q.active then on = on + 1 end end
					end
					imgui.spacing()
					local title = string.format("%s  ·  %d  (%d ligada%s)", r.ltype or "Light", cnt, on, on == 1 and "" or "s")
					if glass_header(pre .. "##lt" .. (r.ltype or ""), title, st.open[grp] == true, 34) then st.open[grp] = not st.open[grp] end
					group_open = st.open[grp] == true
					if group_open then imgui.spacing() end
				end
			elseif r.fid then
				if grp ~= last_group then
					local nm = (FIGHTERS[r.fid] or "Personagem") .. string.format("  (esf%03d)", r.fid)
					local cnt = 0
					for _, q in ipairs(st.results) do if q.fid == r.fid then cnt = cnt + 1 end end
					if cnt > 1 then nm = nm .. "  ·  " .. cnt end
					imgui.spacing()
					if glass_header(pre .. "##fg" .. r.fid, nm, st.open[r.fid] == true, 34) then st.open[r.fid] = not st.open[r.fid] end
					group_open = st.open[r.fid] == true
					if group_open then imgui.spacing() end
				end
			else
				group_open = true
				if last_group ~= nil and grp ~= last_group then
					imgui.spacing(); imgui.separator(); imgui.spacing()
				end
			end
			last_group = grp
			if group_open then
			imgui.push_id(pre .. i)
			local ok = pcall(function()
				local vis = r.go:call("get_DrawSelf")
				changed, vis = imgui.checkbox("##vis", vis)
				if changed then force_visible(r.go, vis) end
				tooltip("Mostrar / ocultar")
				if r.comp then
					imgui.same_line()
					local en = r.comp:call("get_Enabled")
					changed, en = imgui.checkbox("##en", en)
					if changed then force_comp_enabled(r.comp, en) end
					tooltip("Luz ligada / desligada")
				end
				imgui.same_line()
				local open = open_tree((r.label or r.name) .. "##r" .. i, pre .. "res" .. addr(r.go), false)
				if r.label then tooltip("Objeto: " .. r.name) end
				if open then
					if r.comp then ui_scene_light(r, i)
					elseif st.body then st.body(r, pre .. i)
					else inspect_object(r.go, r.xform, pre .. i, r.fid) end
					imgui.tree_pop()
				end
			end)
			if not ok then imgui.text_colored(r.name .. " (objeto não existe mais)", MUTED) end
			imgui.pop_id()
			end
		end
	end
end

local function tab_console()
	section("PESQUISA")
	imgui.push_item_width(-240)
	changed, qs.text = input("##qs_text", qs.text)
	imgui.pop_item_width()
	imgui.same_line()
	imgui.push_item_width(150)
	changed, qs.mode = imgui.combo("##qs_mode", qs.mode, QS_MODES)
	imgui.pop_item_width()
	imgui.same_line()
	if imgui.button("Buscar") then qs_search() end
	qs_render(qs, "qs")
end

-- abas que se atualizam sozinhas: Poser (personagens na tela) e Luzes
qs.poser = { text = "", mode = 2, results = nil, open = {}, t = -10 }
qs.lights = { text = "", mode = 4, results = nil, open = {}, t = -10 }
qs.auto = function(st, title, empty)
	if os.clock() - st.t > 2.0 then st.t = os.clock(); qs_search(st) end
	section(title)
	if st.mode == 4 then hint("Ache as luzes que procura na cena desativando e ativando nas checkbox abaixo.") end
	if st.results and #st.results == 0 then hint(empty) return end
	qs_render(st, title)
end

-- ---------------------------------------------------------------------------
-- Fotos (plugin nask_capture.dll) e Galeria
-- ---------------------------------------------------------------------------
local cap = { id = 0, pending = nil, pick = nil, hide = 0, msg = nil, msg_t = 0, status = nil, status_t = -100, preview = nil, thumbs = {} }

local function cap_status()
	if os.clock() - cap.status_t > 3 then
		cap.status = json.load_file("NASK_Fighter\\status.json")
		cap.status_t = os.clock()
	end
	return cap.status
end

local function cap_request(t)
	cap.id = cap.id + 1
	t.id = math.floor(os.time() % 100000) * 100 + cap.id
	json.dump_file("NASK_Fighter\\request.json", t)
	return t.id
end

local function cap_say(m) cap.msg, cap.msg_t = m, os.clock() end

local take_photo
function port.take_photo() if take_photo then take_photo() end end
take_photo = function()
	port.last_shot_t = os.clock()
	if not cap_status() then cap_say("Plugin de fotos (nask_capture.dll) não carregado.") return end
	if cap.pending then return end
	cap.hide = 4   -- esconde HUD/banner por alguns frames antes de capturar
end

local function photo_dir_label()
	if cfg.photo_dir and cfg.photo_dir ~= "" then return cfg.photo_dir end
	local st = cap_status()
	return st and st.default_dir or "(pasta padrão)"
end

local function cap_tick()
	if cap.hide > 0 then
		cap.hide = cap.hide - 1
		if cap.hide == 0 then
			cap.pending = cap_request({ cmd = "capture", dir = cfg.photo_dir or "" })
			cap.pending_t = os.clock()
			cap_say("Salvando foto...")
		end
	end
	if (cap.pending or cap.pick or cap.file or cap.img) and os.clock() - (cap.poll_t or 0) > 0.2 then
		cap.poll_t = os.clock()
		local r = json.load_file("NASK_Fighter\\result.json")
		if r and cap.pending and r.id == cap.pending then
			cap.pending = nil
			if r.ok then
				table.insert(cfg.gallery, 1, { name = r.name, path = r.path, w = r.w, h = r.h, thumb = r.thumb, t = os.date("%d/%m/%Y %H:%M") })
				while #cfg.gallery > 200 do table.remove(cfg.gallery) end
				save_cfg()
				d2d_reload()
				cap_say("Foto salva: " .. (r.name or ""))
			else
				cap_say("Erro na foto: " .. (r.err or "?"))
			end
		elseif r and cap.pick and r.id == cap.pick then
			cap.pick = nil
			if r.ok and r.path then cfg.photo_dir = r.path; save_cfg() end
		elseif r and cap.file and r.id == cap.file then
			cap.file = nil
			if r.ok and r.path then cfg[cap.file_key or "user_bg_src"] = r.path; save_cfg() end
		elseif r and cap.img and r.id == cap.img then
			cap.img = nil
			if r.ok then
				if cap.img_kind == "bg" then cfg.style = 3; cfg.glass_bg = 8 else cfg.banner = 200; cfg.header_quality = 3 end
				save_cfg()
				d2d_reload()
				cap_say(cap.img_kind == "bg" and "Fundo pronto!" or "Banner pronto!")
			else
				cap_say("Erro: " .. (r.err or "?"))
			end
		end
		if cap.img and os.clock() - (cap.img_t or 0) > 20 then
			cap.img = nil
			cap_say("O plugin não respondeu (atualize o nask_capture.dll).")
		end
		if cap.pending and os.clock() - (cap.pending_t or 0) > 10 then
			cap.pending = nil
			cap_say("O plugin não respondeu. Confira se o nask_capture.dll está em reframework/plugins.")
		end
	end
end

local function open_path(path)
	if path and path ~= "" then cap_request({ cmd = "open", path = path }) end
end

local function ui_photo_settings()
	local st = cap_status()
	if not st then
		imgui.text_colored("Plugin de fotos não encontrado: coloque o nask_capture.dll em reframework/plugins.", WARN)
	end
	-- título pequeno centralizado
	do
		local t = "Pasta das fotos (PNG)"
		local tw = imgui.calc_text_size(t).x
		imgui.set_cursor_pos(Vector2f.new((imgui.get_window_size().x - tw) * 0.5, imgui.get_cursor_pos().y))
		imgui.text_colored(t, MUTED)
	end
	-- o campo já mostra a pasta em uso (a padrão quando nenhuma foi escolhida)
	imgui.push_item_width(-1)
	local shown = ((cfg.photo_dir or "") ~= "") and cfg.photo_dir or photo_dir_label()
	local ch, v = input("##photo_dir", shown)
	imgui.pop_item_width()
	if ch then cfg.photo_dir = (v == photo_dir_label()) and "" or v; save_cfg() end
	tooltip(((cfg.photo_dir or "") == "") and "Pasta padrão. Digite outro caminho ou use \"Escolher pasta...\"" or "Pasta escolhida")
	local shot = "Tirar foto (" .. keyname("NASK Foto") .. ")"
	local function bw(t) return imgui.calc_text_size(t).x + 18 end
	centered_row({
		{ w = bw("Escolher pasta..."), draw = function()
			if imgui.button("Escolher pasta...") then cap.pick = cap_request({ cmd = "pick_dir" }) end
			tooltip("Abre a janela do Windows para escolher a pasta.\nEm tela cheia exclusiva ela pode abrir atrás do jogo.")
		end },
		{ w = bw("Usar padrão"), draw = function() if imgui.button("Usar padrão") then cfg.photo_dir = ""; save_cfg() end end },
		{ w = bw("Abrir pasta"), draw = function() if imgui.button("Abrir pasta") then open_path(photo_dir_label()) end end },
		{ w = bw(shot), draw = function() if colored_button(shot, true) then take_photo() end end },
	}, 8)
	if cap.msg and os.clock() - cap.msg_t < 6 then
		local tw = imgui.calc_text_size(cap.msg).x
		imgui.set_cursor_pos(Vector2f.new(math.max(14, (imgui.get_window_size().x - tw) * 0.5), imgui.get_cursor_pos().y))
		hint(cap.msg)
	end
end

ui_photo_settings_ref = ui_photo_settings
local gal = { page = 1, rects = {}, prev_rects = {}, reload_t = -100, sel = {}, confirm = false, msg = nil }

-- Apaga arquivos do PC mandando para a Lixeira. O Lua do REFramework não pode apagar
-- fora da pasta dele, então o NASK grava um .vbs na pasta de dados e pede para o
-- plugin de fotos abri-lo (mesmo comando "open" usado em "Abrir pasta").
function gal.vbs_str(str)
	local parts, buf = {}, {}
	for _, cp in utf8.codes(str) do
		if cp < 128 and cp ~= 34 then
			table.insert(buf, utf8.char(cp))
		else
			if #buf > 0 then table.insert(parts, '"' .. table.concat(buf) .. '"'); buf = {} end
			table.insert(parts, "ChrW(" .. cp .. ")")
		end
	end
	if #buf > 0 then table.insert(parts, '"' .. table.concat(buf) .. '"') end
	if #parts == 0 then return '""' end
	return table.concat(parts, " & ")
end
function gal.delete_from_pc(entries)
	local L = {
		"On Error Resume Next",
		"Set fso = CreateObject(\"Scripting.FileSystemObject\")",
		"Set sh = CreateObject(\"Shell.Application\")",
		"Set bin = sh.Namespace(10)",
		"me_ = WScript.ScriptFullName",
		"game = fso.GetParentFolderName(fso.GetParentFolderName(fso.GetParentFolderName(fso.GetParentFolderName(me_))))",
		"Sub Lixo(p)",
		"  If fso.FileExists(p) Then",
		"    bin.MoveHere p",
		"    WScript.Sleep 300",
		"  End If",
		"End Sub",
	}
	for _, e in ipairs(entries) do
		if e.path and e.path ~= "" then table.insert(L, "Lixo " .. gal.vbs_str(e.path)) end
		if e.thumb and e.thumb:find("^nask_thumbs/") then
			local rel = "reframework\\images\\NASK_Fighter\\" .. e.thumb:gsub("/", "\\")
			table.insert(L, "t = game & \"\\\" & " .. gal.vbs_str(rel))
			table.insert(L, "If fso.FileExists(t) Then fso.DeleteFile t, True")
		end
	end
	table.insert(L, "WScript.Sleep 1500")
	table.insert(L, "fso.DeleteFile me_, True")
	local ok = pcall(fs.write, "NASK_Fighter\\nask_apagar.vbs", table.concat(L, "\r\n") .. "\r\n")
	if not ok then return false end
	cap_request({ cmd = "open", path = "reframework\\data\\NASK_Fighter\\nask_apagar.vbs" })
	return true
end
function gal.remove_selected(also_pc)
	local keep, removed = {}, {}
	for _, e in ipairs(cfg.gallery) do
		if gal.sel[e.path or e.name or ""] then table.insert(removed, e) else table.insert(keep, e) end
	end
	cfg.gallery = keep
	save_cfg()
	gal.sel, gal.confirm = {}, false
	if also_pc and #removed > 0 then
		gal.msg = gal.delete_from_pc(removed) and (#removed .. " foto(s) enviada(s) para a Lixeira.") or "Não consegui apagar do PC (tirei só da galeria)."
	else
		gal.msg = #removed .. " foto(s) tirada(s) da galeria (os arquivos continuam na pasta)."
	end
	gal.msg_t = os.clock()
end

local function tab_galeria()
	section("GALERIA")
	if not cap_status() then imgui.text_colored("Plugin de fotos não encontrado (nask_capture.dll).", WARN) end
	if #cfg.gallery == 0 then hint("Nenhuma foto ainda. Aperte " .. keyname("NASK Foto") .. " para tirar uma.") return end
	local per_page, cols = 6, 2
	local pages = math.max(1, math.ceil(#cfg.gallery / per_page))
	if gal.page > pages then gal.page = pages end
	if imgui.button("<##gp") and gal.page > 1 then gal.page = gal.page - 1 end
	imgui.same_line()
	imgui.text(string.format("Página %d de %d  ·  %d foto(s)", gal.page, pages, #cfg.gallery))
	imgui.same_line()
	if imgui.button(">##gn") and gal.page < pages then gal.page = gal.page + 1 end
	imgui.same_line()
	if imgui.button("Abrir pasta##gal") then open_path(photo_dir_label()) end
	if not use_d2d() then hint("Sem o plugin d2d não há prévia; clique no nome para abrir a foto.") end

	local avail = imgui.get_window_size().x - 30
	local gap = 10
	local cw = math.floor((avail - gap) / cols)
	local ch = math.floor(cw * 9 / 16)
	local first = (gal.page - 1) * per_page + 1
	local missing = false
	for i = first, math.min(#cfg.gallery, first + per_page - 1) do
		local e = cfg.gallery[i]
		local col = (i - first) % cols
		if col > 0 then imgui.same_line() end
		imgui.begin_group()
		local p = imgui.get_cursor_screen_pos()
		local n = 0
		for _, idx in ipairs({ Col.Button, Col.ButtonHovered, Col.ButtonActive }) do
			if pcall(imgui.push_style_color, idx, rgba(0, 0, 0, 0)) then n = n + 1 end
		end
		local has_png = e.thumb and e.thumb:find("^nask_thumbs/")
		if imgui.button("##th" .. i, Vector2f.new(cw, ch)) then open_path(e.path) end
		if n > 0 then imgui.pop_style_color(n) end
		local hov = imgui.is_item_hovered()
		tooltip((e.name or "") .. "\nClique para abrir")
		if use_d2d() and has_png then
			table.insert(gal.rects, { x = p.x, y = p.y, w = cw, h = ch, key = e.thumb })
			if not d2d_imgs.thumbs[e.thumb] then missing = true end
		else
			pcall(function()
				local dl = window_dl()
				dl:add_rect_filled(p, Vector2f.new(p.x + cw, p.y + ch), rgba(230, 226, 240, 0.9), 8.0, 0)
				dl:add_text(Vector2f.new(p.x + 10, p.y + ch * 0.5 - 7), MUTED, "sem prévia")
			end)
		end
		if hov then pcall(function()
			window_dl():add_rect(p, Vector2f.new(p.x + cw, p.y + ch), accent(1.0), 8.0, 0, 2.0)
		end) end
		local key = e.path or e.name or ""
		local sel = gal.sel[key] == true
		local chs, nv = imgui.checkbox("##gs" .. i, sel)
		if chs then gal.sel[key] = nv or nil end
		imgui.same_line()
		hint(e.t or "")
		imgui.end_group()
	end
	if missing and os.clock() - gal.reload_t > 2 then gal.reload_t = os.clock(); d2d_reload() end
	imgui.spacing()
	local nsel = 0
	for k in pairs(gal.sel) do
		local still = false
		for _, e in ipairs(cfg.gallery) do if (e.path or e.name or "") == k then still = true break end end
		if still then nsel = nsel + 1 else gal.sel[k] = nil end
	end
	if imgui.button("Selecionar página##gsp") then
		for i = first, math.min(#cfg.gallery, first + per_page - 1) do
			local e = cfg.gallery[i]; gal.sel[e.path or e.name or ""] = true
		end
	end
	imgui.same_line()
	if imgui.button("Limpar seleção##gsc") then gal.sel = {}; gal.confirm = false end
	imgui.same_line()
	imgui.begin_disabled(nsel == 0)
	if colored_button("Remover selecionadas (" .. nsel .. ")##grm", gal.confirm, Vector2f.new(0, 0)) then gal.confirm = not gal.confirm end
	imgui.end_disabled()
	if nsel == 0 then gal.confirm = false end
	if gal.confirm then
		imgui.spacing()
		pcall(function()
			local p = imgui.get_cursor_screen_pos()
			local w = imgui.get_window_size().x - 28
			window_dl():add_rect_filled(p, Vector2f.new(p.x + w, p.y + 74), rgba(200, 40, 40, 0.22), 8.0, 0)
			window_dl():add_rect(p, Vector2f.new(p.x + w, p.y + 74), rgba(255, 110, 110, 0.95), 8.0, 0, 1.6)
			local cp = imgui.get_cursor_pos(); imgui.set_cursor_pos(Vector2f.new(cp.x + 10, cp.y + 8))
		end)
		imgui.text_colored(string.format("Remover %d foto(s). Apagar também do PC?", nsel), WARN)
		if imgui.button("Só da galeria##grg") then gal.remove_selected(false) end
		tooltip("Tira da lista; os arquivos continuam na pasta.")
		imgui.same_line()
		if imgui.button("Da galeria e do PC (Lixeira)##grp") then gal.remove_selected(true) end
		tooltip("Manda os arquivos para a Lixeira do Windows (dá para recuperar de lá).")
		imgui.same_line()
		if imgui.button("Cancelar##grc") then gal.confirm = false end
		imgui.spacing()
	end
	if gal.msg and os.clock() - (gal.msg_t or 0) < 6 then hint(gal.msg) end
	imgui.spacing()
	hint("As fotos ficam na pasta; 'Limpar lista' não apaga os arquivos.")
	if imgui.button("Limpar lista da galeria") then cfg.gallery = {}; gal.sel = {}; save_cfg() end
end

-- ---------------------------------------------------------------------------
-- Aba: HUD (banner)
-- ---------------------------------------------------------------------------
local tab_nask_ref = function() end
local function tab_hud()
	if panel("Banner", "hud_banner") then
		local names = { "NASK (padrão)" }
		local map = { 0 }
		if d2d_imgs.banners[200] then
			table.insert(names, "Seu banner")
			table.insert(map, 200)
		end
		for i, nm in ipairs(BANNER_PRESETS) do
			if d2d_imgs.banners[100 + i] then
				table.insert(names, i .. " - " .. nm)
				table.insert(map, 100 + i)
			end
		end
		for i = 1, BANNER_SLOTS do
			local b = d2d_imgs.banners[i]
			if b then
				table.insert(names, string.format("nask_banner_%d.png  (%dx%d)", i, b.w, b.h))
				table.insert(map, i)
			end
		end
		local cur = 1
		for i, v in ipairs(map) do if v == cfg.banner then cur = i end end
		imgui.push_item_width(-170)
		changed, cur = imgui.combo("Imagem", cur, names)
		if changed then cfg.banner = map[cur]; save_cfg() end
		local bon = cfg.header_quality > 1
		changed, bon = imgui.checkbox("Mostrar banner", bon)
		if changed then cfg.header_quality = bon and 3 or 1; save_cfg() end
		imgui.same_line()
		changed, cfg.banner_text_on = imgui.checkbox("Mostrar título", cfg.banner_text_on); if changed then save_cfg() end
		imgui.same_line()
		changed, cfg.banner_fade = imgui.checkbox("Degradê embaixo", cfg.banner_fade); if changed then save_cfg() end
		if not d2d_ready then
			imgui.text_colored("Plugin d2d não carregou: só o banner padrão (aproximado) funciona.", WARN)
		end
		changed, cfg.banner_dark = imgui.slider_float("Escurecer embaixo", cfg.banner_dark or 0, 0.0, 0.9, "%.2f"); if changed then save_cfg() end
		tooltip("Escurece a parte de baixo do banner para o título ficar legível em imagens claras.")
		changed, cfg.banner_title = input("Título", cfg.banner_title); if changed then save_cfg() end
		changed, cfg.banner_sub = input("Subtítulo", cfg.banner_sub); if changed then save_cfg() end
		-- cores do título e do subtítulo (vazio = padrão do tema)
		local function color_opt(label, key, def)
			local c = cfg[key] or def
			local ch, v = imgui.color_edit3(label, Vector3f.new(c[1], c[2], c[3]), 0)
			if ch then cfg[key] = { v.x, v.y, v.z }; save_cfg() end
		end
		color_opt("Cor do título", "title_rgb", { 1.0, 1.0, 1.0 })
		color_opt("Cor do subtítulo", "sub_rgb", { 0.81, 0.63, 0.89 })
		if (cfg.title_rgb or cfg.sub_rgb) and imgui.button("Cores padrão##tcol") then cfg.title_rgb, cfg.sub_rgb = nil, nil; save_cfg() end
		imgui.pop_item_width()
		imgui.spacing()
		centered_row({
			{ w = imgui.calc_text_size("Coloque seu banner").x + 18, draw = function()
				if colored_button("Coloque seu banner", port.tut == "banner") then port.tut = (port.tut == "banner") and nil or "banner" end
			end },
		}, 10)
	end
	tab_nask_ref()
end

-- janela de tutorial: "Coloque seu banner" / "Coloque seu fundo"
function port.draw_tut()
	local kind = port.tut
	local disp = imgui.get_display_size()
	imgui.set_next_window_pos(Vector2f.new(disp.x * 0.5 - 250, 90), 4)
	imgui.set_next_window_size(Vector2f.new(520, 300), 1)
	push_theme()
	imgui.begin_window("NASK Tutorial##tut", nil, 1 | 2 | 32)
	local ok, err = pcall(function()
		local wp, ws = imgui.get_window_pos(), imgui.get_window_size()
		local dl = window_dl()
		if port.glass_tex() then
			table.insert(port.glass_rects, { x = wp.x, y = wp.y, w = ws.x, h = ws.y, a = 1.0 })
			dl:add_rect_filled(wp, Vector2f.new(wp.x + ws.x, wp.y + ws.y), rgba(10, 8, 16, cfg.glass_dark or 0.2), 14, 0)
		else
			dl:add_rect_filled(wp, Vector2f.new(wp.x + ws.x, wp.y + ws.y), window_bg(), 14, 0)
		end
		dl:add_rect(wp, Vector2f.new(wp.x + ws.x, wp.y + ws.y), rgba(255, 255, 255, 0.45), 14, 0, 1.0)
		if sub_font then imgui.push_font(sub_font) end
		imgui.text_colored(kind == "bg" and "COLOQUE SEU FUNDO" or "COLOQUE SEU BANNER", accent(1.0))
		if sub_font then imgui.pop_font() end
		imgui.same_line()
		imgui.set_cursor_pos(Vector2f.new(ws.x - 40, 10))
		if imgui.button("×##tclose") then port.tut = nil end
		imgui.separator()
		imgui.spacing()
		local file = kind == "bg" and "nask_glass_user.png" or "nask_banner_user.png"
		if kind == "bg" then
			imgui.text("1. Use uma imagem vertical na proporção do HUD: 800 x 1126")
			imgui.text("   (ou 1600 x 2252). Outra proporção fica esticada.")
			hint("   Dica: envie a imagem já desfocada (desfoque gaussiano de uns 25 px\n   no editor) e um pouco escura, para o texto do HUD ficar legível.")
		else
			imgui.text("1. Escolha uma imagem larga (ideal 2112 x 528, proporção 4:1).")
		end
		imgui.text("2. Salve como PNG com este nome:")
		imgui.text_colored("      " .. file, accent(1.0))
		imgui.text("3. Coloque nesta pasta:")
		imgui.text_colored("      <pasta do SF6>\\reframework\\images\\NASK_Fighter\\", accent(1.0))
		imgui.text("4. Clique em \"Recarregar imagens\" aqui embaixo.")
		imgui.spacing()
		if colored_button("Recarregar imagens##treload", true) then
			d2d_reload()
			port.tut_msg = "Imagens recarregadas."
		end
		imgui.same_line()
		if imgui.button("Abrir a pasta##topen") then
			cap_request({ cmd = "open", path = "reframework\\images\\NASK_Fighter" })
		end
		tooltip("Abre a pasta reframework\\images\\NASK_Fighter no Windows (precisa do nask_capture.dll)")
		local loaded = (kind == "bg") and (d2d_imgs.glass and d2d_imgs.glass[8]) or (d2d_imgs.banners and d2d_imgs.banners[200])
		imgui.same_line()
		imgui.text_colored(loaded and "Imagem encontrada!" or "Ainda não encontrada", loaded and accent(1.0) or MUTED)
		if loaded and imgui.button(kind == "bg" and "Usar agora##tuse" or "Usar agora##tuse2") then
			if kind == "bg" then cfg.style = 3; cfg.glass_bg = 8 else cfg.banner = 200; cfg.header_quality = 3 end
			save_cfg()
		end
		if port.tut_msg then hint(port.tut_msg) end
		local m = imgui.get_mouse()
		port.tut_hovered = m and m.x >= wp.x and m.y >= wp.y and m.x <= wp.x + ws.x and m.y <= wp.y + ws.y or false
	end)
	imgui.end_window()
	pop_theme()
	if not ok then report_error("tutorial", err) end
end

local ACTIONS = {
	{ "Activate FreeCam", "Modo Foto liga/desliga" },
	{ "Cam Forward", "Frente" }, { "Cam Backward", "Trás" },
	{ "Cam Left", "Esquerda" }, { "Cam Right", "Direita" },
	{ "Cam Up", "Sobe" }, { "Cam Down", "Desce" },
	{ "Zoom In", "Zoom +" }, { "Zoom Out", "Zoom -" }, { "Reset Zoom", "Zerar zoom" },
	{ "Roll Left", "Inclinar <" }, { "Roll Right", "Inclinar >" },
	{ "NASK Girar Esquerda", "Girar 90° <" }, { "NASK Girar Direita", "Girar 90° >" },
	{ "NASK Zerar Inclinacao", "Zerar inclinação" },
	{ "Freeze Time & Scene", "Pausar tudo" }, { "Freeze Time", "Pausar luta" },
	{ "Skip Frame", "Avançar frame" }, { "Freeze Camera", "Travar câmera" },
	{ "Hide UI", "Esconder UI" }, { "2x Quality", "2x Quality" },
	{ "NASK Foto", "Tirar foto" }, { "NASK Abrir HUD", "Abrir/fechar este HUD" },
	{ "NASK Portatil", "Abrir/fechar o modo foto Portátil" },
	{ "NASK Preview Vertical", "Preview vertical" },
	{ "NASK Abrir MMDK", "Abrir/fechar o MMDK" },
	{ "CModifier", "Segurar = rápido" }, { "CModifier3", "Segurar = lento" },
}

local function ui_keys()
	hint("Clique no botão e aperte a tecla, o botão do controle ou do mouse.\nEsc cancela, Backspace deixa sem tecla.")
	imgui.spacing()
	if imgui.button("Limpar todas teclas##kclear") then keys.clear_all() end
	tooltip("Deixa todas as ações sem tecla. Depois é só escolher as que quiser.")
	imgui.same_line()
	if imgui.button("Restaurar padrão##kdef") then keys.reset_defaults() end
	tooltip("Volta todas as teclas para o padrão do NASK.")
	imgui.spacing()
	section("TECLADO E MOUSE")
	for _, a in ipairs(ACTIONS) do
		imgui.push_id("ka" .. a[1])
		keys.setter(a[1], a[2])
		imgui.pop_id()
	end
	imgui.spacing()
	section("CONTROLE")
	hint("Um botão do controle para cada ação, além da tecla de cima (as duas funcionam).\nOs analógicos já movem e giram a câmera no Modo Foto.")
	imgui.spacing()
	for _, a in ipairs(ACTIONS) do
		imgui.push_id("kp" .. a[1])
		keys.setter(a[1], a[2], nil, 2)
		imgui.pop_id()
	end
end

-- janela própria (sem banner) para os atalhos
local function draw_keys_window()
	local disp = imgui.get_display_size()
	imgui.set_next_window_pos(Vector2f.new(disp.x * 0.5 - 260, 80), 4)
	imgui.set_next_window_size(Vector2f.new(520, math.min(640, disp.y - 140)), 4)
	push_theme()
	-- 1 = sem barra de título, 32 = sem recolher
	imgui.begin_window("Atalhos NASK##keys", nil, 1 | 32)
	pcall(function()
		local wpos, wsize = imgui.get_window_pos(), imgui.get_window_size()
		local dl = window_dl()
		local wx2, wy2 = wpos.x + wsize.x, wpos.y + wsize.y
		if port.glass_tex() then
			table.insert(port.glass_rects, { x = wpos.x, y = wpos.y, w = wsize.x, h = wsize.y, a = 0.85 + 0.15 * cfg.opacity })
		else
			dl:add_rect_filled(Vector2f.new(wpos.x, wpos.y), Vector2f.new(wx2, wy2), window_bg(), 14.0, 0)
		end
		if glass() and not port.glass_tex() then
			dl:add_rect_filled_multi_color(Vector2f.new(wpos.x + 1, wpos.y + 14), Vector2f.new(wx2 - 1, wy2 - 14),
				rgba(255, 255, 255, 0.10), rgba(255, 255, 255, 0.05), rgba(255, 255, 255, 0.015), rgba(255, 255, 255, 0.04))
			dl:add_rect(Vector2f.new(wpos.x + 0.5, wpos.y + 0.5), Vector2f.new(wx2 - 0.5, wy2 - 0.5), rgba(255, 255, 255, 0.30), 14.0, 0, 1.0)
		end
		keys_win.pos, keys_win.size = wpos, wsize
	end)
	if title_font then imgui.push_font(sub_font or title_font) end
	imgui.text_colored("CONFIGURAR ATALHOS", accent(1.0))
	if title_font then imgui.pop_font() end
	imgui.same_line()
	imgui.set_cursor_pos(Vector2f.new(imgui.get_window_size().x - 40, 10))
	if imgui.button("×##kclose") then keys_win.open = false end
	imgui.separator()
	imgui.begin_child_window("##keys_body", nil, false, 0)
	local ok, err = xpcall(ui_keys, debug.traceback)
	if not ok then report_error("atalhos", err) end
	imgui.end_child_window()
	imgui.end_window()
	pop_theme()
	local m = imgui.get_mouse()
	local p, sz = keys_win.pos, keys_win.size
	keys_win.hovered = p and m and m.x >= p.x and m.y >= p.y and m.x <= p.x + sz.x and m.y <= p.y + sz.y or false
end

local function tab_nask()
	if panel("Tema", "hud_tema") then
		imgui.push_item_width(-170)
		changed, cfg.style = imgui.combo("Tema", cfg.style, { "Dark", "Light", "NASK", "Nery" }); if changed then save_cfg() end
		if cfg.style == 4 or cfg.style == 5 then hint("Nery: vidro fosco, abas numa barra com degradê rosa/lilás e a foto na bolinha de baixo.\nNão sou designer, mas eu tentei, ok!") end
		if cfg.style == 4 then
			local rows = cfg.tab_rows or 2
			changed, rows = imgui.combo("Linhas das abas", rows, { "1 linha", "2 linhas" })
			if changed then cfg.tab_rows = rows; save_cfg() end
			tooltip("Com 1 linha, se os nomes não couberem a barra usa 2 linhas sozinha.")
		end
		if cfg.style == 3 then
			local ids, names = {}, {}
			for i, id in ipairs(port.GLASS_IDS) do ids[i] = id; names[i] = port.GLASS_NAMES[i] end
			if d2d_imgs.glass and d2d_imgs.glass[8] then ids[#ids + 1] = 8; names[#names + 1] = "Seu fundo" end
			local cur = 1
			for i, id in ipairs(ids) do if id == cfg.glass_bg then cur = i end end
			changed, cur = imgui.combo("Fundo", cur, names)
			if changed then cfg.glass_bg = ids[cur]; save_cfg() end
			if not port.glass_tex() then imgui.text_colored("Fundo do tema não carregado (precisa do plugin d2d e das imagens nask_glass).", WARN) end
			changed, cfg.glass_dark = imgui.slider_float("Escurecer o fundo", cfg.glass_dark or 0, 0.0, 0.85, "%.2f"); if changed then save_cfg() end
			tooltip("Escurece o fundo atrás das opções para o texto ficar legível.")
		end
		changed, cfg.opacity = imgui.slider_float("Opacidade", cfg.opacity, 0.35, 1.0, "%.2f"); if changed then save_cfg() end
		local names = {}
		for i, a in ipairs(ACCENTS) do names[i] = a.name end
		changed, cfg.accent = imgui.combo("Cor de destaque", cfg.accent, names); if changed then save_cfg() end
		imgui.pop_item_width()
		imgui.spacing()
		centered_row({
			{ w = imgui.calc_text_size("Coloque seu fundo").x + 18, draw = function()
				if colored_button("Coloque seu fundo", port.tut == "bg") then port.tut = (port.tut == "bg") and nil or "bg" end
			end },
		}, 10)
	end
	if panel("Comportamento", "hud_comp") then
		imgui.push_item_width(-170)
		do
			local names, cur = {}, 1
			for i, l in ipairs(NASK_FC.lang.LANGS) do names[i] = l.name; if l.id == cfg.lang then cur = i end end
			local chl, nl = imgui.combo("Idioma / Language", cur, names)
			if chl then NASK_FC.set_lang(NASK_FC.lang.LANGS[nl].id) end
		end
		changed, cfg.open_on_start = imgui.checkbox("Abrir o HUD ao iniciar o jogo", cfg.open_on_start); if changed then save_cfg() end
		changed, cfg.open_mode = imgui.combo("Tecla do HUD abre", cfg.open_mode or 1, { "Base (HUD completo)", "Portátil" }); if changed then save_cfg() end
		tooltip("O que a tecla " .. keyname("NASK Abrir HUD") .. " (e o início do jogo) abre: o HUD completo ou o modo Portátil.\nO ícone de câmera e a tecla do Portátil continuam funcionando.")
		changed, cfg.block_mouse_hover = imgui.checkbox("Mouse sobre o HUD não gira a câmera", cfg.block_mouse_hover); if changed then save_cfg() end
		changed, cfg.hide_hud_with_ui = imgui.checkbox("Esconder este HUD junto com a UI do jogo", cfg.hide_hud_with_ui); if changed then save_cfg() end
		changed, cfg.cursor_mode = imgui.combo("Cursor do HUD", cfg.cursor_mode, { "Sempre visível", "Só com o HUD aberto", "Nunca", "Só em cima do HUD", "Automático" }); if changed then save_cfg() end
		tooltip("A seta do jogo fica por baixo do HUD; a seta do HUD aparece por cima dele.")
		changed, cfg.roll_step = imgui.slider_float("Passo do giro", cfg.roll_step, 15.0, 90.0, "%.0f°"); if changed then save_cfg() end
		tooltip("Quantos graus a câmera gira a cada toque nas teclas de girar (, e .).\n90° = deita a câmera de uma vez para foto vertical.")
		imgui.pop_item_width()
	end
	if panel("Abas", "hud_abas") then
		hint("Desmarque as abas que você não usa. A aba HUD fica sempre visível.")
		cfg.hidden_tabs = type(cfg.hidden_tabs) == "table" and cfg.hidden_tabs or {}
		local col = 0
		for i, name in ipairs(TABS) do
			if name ~= "HUD" then
				if col % 3 ~= 0 then imgui.same_line(14 + (col % 3) * 200) end
				local vis = not cfg.hidden_tabs[name]
				local ch, v = imgui.checkbox(name .. "##vis" .. i, vis)
				if ch then cfg.hidden_tabs[name] = (not v) or nil; save_cfg() end
				col = col + 1
			end
		end
	end
end

-- Aba NASK: créditos e redes
NASK_FC.links = { x = "https://x.com/Kazamanagato", x_user = "@Kazamanagato", discord = "Neryrocker" }
-- aba Dicas (troca com a aba NASK pelo botão no topo)
port.TIPS = {
	"Uma ótima dica para conseguir a melhor foto possível é sempre tentar capturar a imagem quando o modelo do personagem está renderizado na qualidade máxima: momentos como a tela de seleção de personagem, o VS walk, a intro, uma sequência de CA3 (Critical Art 3) ou a pose de vitória.",
	"Eu gosto de fazer fotos da C. Viper durante o CA3, pois gosto da iluminação. Ache a melhor para o seu personagem; algumas intros têm uma boa iluminação, por exemplo.",
	"Meu método é entrar no jogo em 4K e, depois de ajustar toda a foto, aperto o 2x, que mata totalmente meu FPS, porém tenho a melhor qualidade possível. Depois do print, eu desativo o 2x.",
	"Você pode usar o MMDK durante as intros, pois elas já contam como gameplay e têm o boneco bem renderizado: basta pausar durante a intro e abrir o MMDK. Ele também funciona durante CAs e win poses; esses momentos são perfeitos para abri-lo, definir uma animação e criar uma pose/foto a partir dela.",
	"Com o DOF ativo, cuidado para não exagerar na potência: ao mexer a câmera, você pode deixar o DOF muito forte na tela e causar muita perda de performance. Use com cautela.",
	"O MMDK é curioso: você pode usar todos os grupos de animações do personagem rival se ele te der um CA. Basicamente, faça o boneco rival te acertar um CA, pause, abra o MMDK e os grupos de animações dele serão transferidos para o seu boneco. Assim você pode usar animações de outros personagens, legal, né?"
}
-- quebra o texto (já traduzido) em linhas que cabem na largura
function port.wrap(text, width)
	local lines, cur = {}, ""
	for word in text:gmatch("%S+") do
		local try = (cur == "") and word or (cur .. " " .. word)
		if imgui.calc_text_size(try).x > width and cur ~= "" then
			table.insert(lines, cur); cur = word
		else
			cur = try
		end
	end
	if cur ~= "" then table.insert(lines, cur) end
	return lines
end
function port.tips_toggle_button(ws)
	local lbl = cfg.nask_tips and "Mudar para NASK" or "Mudar para Dicas"
	local tw = imgui.calc_text_size(NASK_FC.lang and NASK_FC.lang.t and NASK_FC.lang.t(lbl) or lbl).x + 28
	imgui.set_cursor_pos(Vector2f.new(math.max(14, (ws.x - tw) * 0.5), imgui.get_cursor_pos().y + 4))
	if imgui.button(lbl .. "##tipsw", Vector2f.new(tw, 0)) then
		cfg.nask_tips = not cfg.nask_tips
		TABS[8] = cfg.nask_tips and "Dicas" or "NASK"
		save_cfg()
	end
	imgui.spacing()
end
function port.tab_tips()
	local ws = imgui.get_window_size()
	port.tips_toggle_button(ws)
	section("DICAS")
	local width = ws.x - 60
	for i, tip in ipairs(port.TIPS) do
		local t = (NASK_FC.lang and NASK_FC.lang.t) and NASK_FC.lang.t(tip) or tip
		local lines = port.wrap(t, width - 30)
		imgui.spacing()
		imgui.text_colored(tostring(i), accent(1.0))
		imgui.same_line()
		local x = imgui.get_cursor_pos().x + 6
		for j, ln in ipairs(lines) do
			if j > 1 then imgui.set_cursor_pos(Vector2f.new(x, imgui.get_cursor_pos().y)) else imgui.set_cursor_pos(Vector2f.new(x, imgui.get_cursor_pos().y)) end
			imgui.text_colored(ln, INK)
		end
		imgui.spacing()
		if i < #port.TIPS then imgui.separator() end
	end
	imgui.spacing()
end

function NASK_FC.tab_about()
	local ws = imgui.get_window_size()
	if cfg.nask_tips then return port.tab_tips() end
	port.tips_toggle_button(ws)
	local function center_text(t, col, font)
		if font then imgui.push_font(font) end
		imgui.set_cursor_pos(Vector2f.new(math.max(14, (ws.x - imgui.calc_text_size(t).x) * 0.5), imgui.get_cursor_pos().y))
		imgui.text_colored(t, col)
		if font then imgui.pop_font() end
	end
	imgui.spacing()
	-- foto em moldura de círculo (imagem pelo d2d; anel pelo ImGui, por cima)
	local D = 190
	local cx = (ws.x - D) * 0.5
	local cy = imgui.get_cursor_pos().y + 6
	imgui.set_cursor_pos(Vector2f.new(cx, cy))
	local sp = imgui.get_cursor_screen_pos()
	imgui.invisible_button("##nask_photo", Vector2f.new(D, D))
	port.profile_rect = { x = sp.x, y = sp.y, w = D, h = D }
	pcall(function()
		local dl = window_dl()
		local c = Vector2f.new(sp.x + D * 0.5, sp.y + D * 0.5)
		if not (use_d2d() and d2d_imgs.profile) then
			dl:add_circle_filled(c, D * 0.5, rgba(255, 255, 255, 0.08), 64)
		end
		-- anel largo exatamente na borda: esconde o serrilhado do recorte
		dl:add_circle(c, D * 0.5 + 0.5, window_bg(), 128, 4.0)
		dl:add_circle(c, D * 0.5 + 2.5, accent(0.95), 128, 3.0)
		dl:add_circle(c, D * 0.5 + 8, rgba(255, 255, 255, 0.25), 128, 1.2)
	end)
	imgui.set_cursor_pos(Vector2f.new(14, cy + D + 16))
	center_text("Amanda Tri Nask", WHITE, title_font)
	imgui.spacing()
	-- X e Discord embaixo da foto
	local bw, bh = 250, 40
	local x0 = (ws.x - (bw * 2 + 12)) * 0.5
	local y = imgui.get_cursor_pos().y
	imgui.set_cursor_pos(Vector2f.new(x0, y))
	if glass_button("##nask_x", "X / Twitter  " .. NASK_FC.links.x_user, false, bw, bh) then
		open_path(NASK_FC.links.x)
		NASK_FC.links.msg, NASK_FC.links.msg_t = "Abrindo " .. NASK_FC.links.x .. " no navegador...", os.clock()
	end
	tooltip(NASK_FC.links.x)
	imgui.same_line()
	imgui.set_cursor_pos(Vector2f.new(x0 + bw + 12, y))
	if glass_button("##nask_dc", "Discord  " .. NASK_FC.links.discord, false, bw, bh) then
		local ok = pcall(imgui.set_clipboard_text, NASK_FC.links.discord)
		NASK_FC.links.msg = ok and ("\"" .. NASK_FC.links.discord .. "\" copiado. No Discord: Adicionar amigo e cole o nome.")
			or ("Discord: " .. NASK_FC.links.discord .. "  (adicione como amigo pelo nome)")
		NASK_FC.links.msg_t = os.clock()
	end
	tooltip("Copia o nome de usuário do Discord: " .. NASK_FC.links.discord)
	imgui.set_cursor_pos(Vector2f.new(14, y + bh + 14))
	-- legenda
	center_text("Gosto de fazer fotos em jogo, em especial de mulheres fodonas.", INK)
	if NASK_FC.links.msg and os.clock() - (NASK_FC.links.msg_t or 0) < 6 then
		imgui.spacing()
		center_text(NASK_FC.links.msg, accent(1.0))
	end
	imgui.spacing(); imgui.spacing(); imgui.spacing()
	section("NASK FIGHTER")
	imgui.text("v" .. VERSION .. "  ·  modo foto para Street Fighter 6")
	hint("Câmera, teclas, Poser, luzes e console próprios do NASK Fighter.\nREFramework: praydog (MIT)  ·  reframework-d2d: cursey (MIT)\nTirando as bibliotecas creditadas acima, tudo no NASK Fighter é original. As únicas coisas de outro mod\nsão dois parâmetros do Lua Freecam (distorção 2D e sobreposição dos lutadores): todos os créditos disso vão para o alphaZomega.\nFonte Oswald (OFL)  ·  stb_image_write (domínio público)")
	imgui.text_colored("Use só offline / modo treino.", rgba(200, 110, 20, 1))
end

tab_nask_ref = tab_nask
-- ---------------------------------------------------------------------------
-- Aba: Animações -> ponte para o MMDK (script de terceiros, instalado à parte)
-- O NASK não traz nada do MMDK: só detecta se ele está carregado e abre a
-- janela "MMDK - Moveset Research" dele fora do menu do REFramework.
-- ---------------------------------------------------------------------------
NASK_FC.mmdk = NASK_FC.mmdk or { open = false }
function NASK_FC.mmdk.state()
	-- MMDK.lua cria as globais mmsettings / PlayerData; MMDK/tables.lua cria tbls
	if type(rawget(_G, "mmsettings")) ~= "table" or rawget(_G, "PlayerData") == nil then return "missing" end
	local t = rawget(_G, "tbls")
	if type(t) == "table" and type(t.characters) == "table" and t.characters[29] == nil then return "old" end
	return "ok"
end
-- A janela do MMDK só é desenhada com o menu Insert aberto (reframework:is_drawing_ui()).
-- Para abrir "separada", o NASK responde "sim" a essa pergunta só quando quem pergunta
-- é o MMDK.lua e o NASK pediu a janela. Os outros scripts continuam vendo o valor real.
function NASK_FC.mmdk.hook()
	if NASK_FC.mmdk.hooked then return end
	local orig = rawget(_G, "reframework")
	if orig == nil then return end
	NASK_FC.mmdk.orig = orig
	local proxy = setmetatable({}, { __index = function(_, k)
		if k == "is_drawing_ui" then
			return function()
				local real = orig:is_drawing_ui()
				if real or not NASK_FC.mmdk.open then return real end
				local info = debug and debug.getinfo and debug.getinfo(2, "S")
				local src = info and info.source and info.source:lower() or ""
				return src:find("[\\/]mmdk%.lua$") ~= nil
			end
		end
		local v = orig[k]
		if type(v) == "function" then return function(_, ...) return v(orig, ...) end end
		return v
	end })
	_G.reframework = proxy
	NASK_FC.mmdk.hooked = true
end
-- Teclas do MMDK: ficam no módulo Hotkeys/Hotkeys (compartilhado) e em mmsettings.hotkeys.
-- "[Not Bound]" é o valor que o próprio Hotkeys usa para "sem tecla".
function NASK_FC.mmdk.hk()
	local hk = package.loaded["Hotkeys/Hotkeys"]
	if type(hk) ~= "table" then
		for k, v in pairs(package.loaded) do
			if type(k) == "string" and k:lower():gsub("\\", "/") == "hotkeys/hotkeys" and type(v) == "table" then hk = v break end
		end
	end
	return type(hk) == "table" and type(hk.hotkeys) == "table" and hk or nil
end
function NASK_FC.mmdk.actions()
	local ms = rawget(_G, "mmsettings")
	local out = {}
	if type(ms) == "table" and type(ms.hotkeys) == "table" then
		for a in pairs(ms.hotkeys) do
			if type(a) == "string" and not a:find("_%$") then out[#out + 1] = a end
		end
	end
	return out
end
function NASK_FC.mmdk.set_keys(off, bak)
	local hk, ms = NASK_FC.mmdk.hk(), rawget(_G, "mmsettings")
	local acts = NASK_FC.mmdk.actions()
	if not hk or #acts == 0 then return false end
	local saved = false
	for _, a in ipairs(acts) do
		if off then
			local cur = hk.hotkeys[a]
			if cur and cur ~= "[Not Bound]" and cur ~= "[Press Input]" then
				bak[a], bak[a .. "_$"], bak[a .. "_$_$"] = cur, hk.hotkeys[a .. "_$"], hk.hotkeys[a .. "_$_$"]
				saved = true
			end
			hk.hotkeys[a] = "[Not Bound]"
			hk.hotkeys[a .. "_$"], hk.hotkeys[a .. "_$_$"] = nil, nil
		else
			local d = bak[a] or (type(hk.default_hotkeys) == "table" and hk.default_hotkeys[a])
			if d then hk.hotkeys[a] = d end
			hk.hotkeys[a .. "_$"], hk.hotkeys[a .. "_$_$"] = bak[a .. "_$"], bak[a .. "_$_$"]
		end
		ms.hotkeys[a] = hk.hotkeys[a]
	end
	-- limpa o cache de "apertou neste frame" do Hotkeys, se ele expõe
	for _, f in ipairs({ "hotkeys_down", "hotkeys_up", "hotkeys_trig" }) do
		if type(hk[f]) == "table" then for k in pairs(hk[f]) do hk[f][k] = nil end end
	end
	return true, saved
end
-- chamado todo frame: aplica uma vez quando o MMDK aparece / quando a opção muda
function NASK_FC.mmdk.keys_tick(c, save)
	local want = c.mmdk_nokeys == true
	if NASK_FC.mmdk.keys_off == want then return end
	if NASK_FC.mmdk.state() == "missing" then return end
	if not want and NASK_FC.mmdk.keys_off == nil then NASK_FC.mmdk.keys_off = false return end
	c.mmdk_keys_bak = type(c.mmdk_keys_bak) == "table" and c.mmdk_keys_bak or {}
	local ok, saved = NASK_FC.mmdk.set_keys(want, c.mmdk_keys_bak)
	if ok then
		NASK_FC.mmdk.keys_off = want
		if saved or not want then save() end
	end
end
function NASK_FC.mmdk.is_open()
	local ms = rawget(_G, "mmsettings")
	local o = NASK_FC.mmdk.open and type(ms) == "table" and ms.research_enabled == true
	if not o then NASK_FC.mmdk.open = false end
	return o
end
function NASK_FC.mmdk.toggle()
	local ms = rawget(_G, "mmsettings")
	if NASK_FC.mmdk.state() == "missing" or type(ms) ~= "table" then return end
	if NASK_FC.mmdk.is_open() then
		ms.research_enabled = false
		NASK_FC.mmdk.open = false
		-- volta o HUD se foi o MMDK que minimizou
		if port.mini_by_mmdk then port.mini = false; port.mini_by_mmdk = false end
	else
		NASK_FC.mmdk.hook()
		ms.research_enabled = true
		NASK_FC.mmdk.open = true
		-- v2.6.17: minimiza o HUD para a janela do MMDK não ficar atravessada nele
		if cfg.mmdk_minimize ~= false and not port.mini then port.mini = true; port.mini_by_mmdk = true end
	end
end
function NASK_FC.mmdk.tab()
	local st = NASK_FC.mmdk.state()
	section("ANIMAÇÕES")
	if st == "missing" then
		imgui.text_colored("Para usar os sliders de animações é necessário instalar e corrigir o MMDK,\nveja o tutorial na página do mod.", WARN)
		NASK_FC.mmdk.open = false
		return
	end
	if st == "old" then
		imgui.text_colored("MMDK encontrado, mas sem a correção: os lutadores novos (Elena, C. Viper...)\nnão estão na lista dele. Corrija o MMDK seguindo o tutorial na página do mod.", WARN)
		imgui.spacing()
	end
	local ms = rawget(_G, "mmsettings")
	local is_open = NASK_FC.mmdk.is_open()
	-- botão centralizado com a tecla ao lado
	local key_txt = "Tecla " .. keys.name_of("NASK Abrir MMDK")
	if keys.get("NASK Abrir MMDK") == "-" then key_txt = "Sem tecla" end
	local bw = 220
	local total = bw + 12 + imgui.calc_text_size(key_txt).x
	local ws = imgui.get_window_size()
	local cy = imgui.get_cursor_pos().y
	imgui.set_cursor_pos(Vector2f.new(math.max(14, (ws.x - total) * 0.5), cy))
	if colored_button(is_open and "Fechar o MMDK##mmdk" or "Abrir o MMDK##mmdk", is_open, Vector2f.new(bw, 0)) then
		NASK_FC.mmdk.toggle()
	end
	tooltip("Abre a janela \"MMDK - Moveset Research\" separada, sem precisar do menu Insert.")
	imgui.same_line()
	imgui.set_cursor_pos(Vector2f.new(imgui.get_cursor_pos().x + 4, cy + 3))
	imgui.text_colored(key_txt, MUTED)
	imgui.spacing()
	changed, cfg.mmdk_minimize = imgui.checkbox("Minimizar o HUD ao abrir o MMDK", cfg.mmdk_minimize ~= false); if changed then save_cfg() end
	tooltip("O HUD vira a pílula do canto enquanto o MMDK está aberto e volta ao fechar,\npara as duas janelas não ficarem uma em cima da outra.")
	hint("A janela do MMDK só aparece numa luta ou no treino.\nDentro dela: Speed e Frame são os sliders, a lista troca a animação e \"Pause\" congela.")
	local ch2, v2 = imgui.checkbox("Desativar as teclas do MMDK ao iniciar##mmdknk", cfg.mmdk_nokeys == true)
	if ch2 then cfg.mmdk_nokeys = v2; save_cfg() end
	tooltip("Deixa todas as teclas do MMDK sem tecla (F1, F2, Q, E, R, T, espaço, setas...),\npara não brigarem com o Modo Foto. Desmarcando, elas voltam como eram.\nOs botões da janela do MMDK continuam funcionando.")
	if type(ms.transparent_window) == "boolean" then
		local ch, v = imgui.checkbox("Janela do MMDK sem fundo##mmdktr", ms.transparent_window)
		if ch then ms.transparent_window = v end
	end
	imgui.spacing()
	hint("É recomendável mudar as hotkeys do MMDK para não gerar conflito.")

	-- aviso destacado: Pausa de pose (correção de física) trava o MMDK
	imgui.spacing()
	imgui.separator()
	imgui.spacing()
	local held = next(pose_hold) ~= nil
	pcall(function()
		local p = imgui.get_cursor_screen_pos()
		local w = imgui.get_window_size().x - 28
		local h = (port.warn_h or (held and 92 or 70)) + 6
		local dl = window_dl()
		dl:add_rect_filled(p, Vector2f.new(p.x + w, p.y + h), rgba(200, 40, 40, held and 0.38 or 0.22), 8.0, 0)
		dl:add_rect(p, Vector2f.new(p.x + w, p.y + h), rgba(255, 110, 110, 0.95), 8.0, 0, 1.6)
		local cp = imgui.get_cursor_pos(); imgui.set_cursor_pos(Vector2f.new(cp.x + 12, cp.y + 10))
	end)
	local wy0 = imgui.get_cursor_pos().y
	imgui.indent(12)
	imgui.text_colored("ATENÇÃO", WARN)
	imgui.text_colored("O MMDK não funciona com a \"Pausa de pose (física acompanha)\" ligada\nna aba Poser. Ligue essa opção só depois de já ter definido a pose\ne precisar corrigir a física, nunca antes.", WARN)
	if held then
		imgui.text_colored("A Pausa de pose está ligada agora: desligue-a para o MMDK funcionar.", WARN)
	end
	imgui.spacing()
	imgui.text_colored("Você pode alternar qual boneco será manipulado no MMDK marcando a checkbox\nno canto superior esquerdo da janela dele.", WARN)
	imgui.spacing()
	imgui.text_colored("Se a física da roupa estiver bugada/travada, clique em \"BAS_STD_Loop\"\nna lista da janela principal do MMDK para resetar a física.", WARN)
	imgui.unindent(12)
	port.warn_h = imgui.get_cursor_pos().y - wy0 + 6
	imgui.spacing()
	imgui.spacing()
end

local TAB_FN = { tab_modo_foto,
	function() qs.auto(qs.poser, "PERSONAGENS NA TELA", "Nenhum personagem na tela (entre numa luta ou no treino).") end,
	function() qs.auto(qs.lights, "LUZES DA CENA", "Nenhuma luz encontrada.") end,
	tab_console, tab_galeria, function() NASK_FC.mmdk.tab() end, tab_hud, function() NASK_FC.tab_about() end }
if (cfg.theme_v or 0) < 2250 then cfg.tab = 1; cfg.theme_v = 2250 end
-- 2.6.2: tema novo "Pedra" vira o tema ativo uma vez (dá para voltar em HUD > NASK > Tema)
if (cfg.theme_v or 0) < 2620 then cfg.style = 4; cfg.theme_v = 2620; save_cfg() end
if cfg.style == 5 then cfg.style = 4 end  -- "Pedra (anterior)" saiu na 2.6.6
-- 2.6.3: tema Pedra usa o banner da A.K.I. ("Estou te assistindo"), sem título por cima
if (cfg.theme_v or 0) < 2630 then
	if (cfg.style == 4 or cfg.style == 5) then cfg.banner = 106; cfg.header_quality = 3; cfg.banner_dark = 0 end
	cfg.theme_v = 2630; save_cfg()
end
-- 2.6.4: "Mostrar título" e "Degradê embaixo" ligados em todos os temas
if (cfg.theme_v or 0) < 2640 then cfg.banner_text_on = true; cfg.banner_fade = true; cfg.theme_v = math.max(cfg.theme_v or 0, 2640); save_cfg() end
-- 2.3.7: tema padrão NASK; fundos "Verde e roxo", "C. Viper" e "C. Viper 2" saíram
if (cfg.theme_v or 0) < 2370 then
	cfg.style = 3
	if cfg.glass_bg == 2 or cfg.glass_bg == 5 or cfg.glass_bg == 6 or cfg.glass_bg == nil then cfg.glass_bg = 1 end
	cfg.theme_v = math.max(cfg.theme_v or 0, 2370)
end
-- 2.3.3: aba Animações voltou (agora abre o MMDK). Quem veio da 2.3.2 (6 abas)
-- estava com Galeria/HUD uma posição antes.
if (cfg.theme_v or 0) < 2330 then
	if (cfg.theme_v or 0) >= 2320 and (cfg.tab or 1) >= 5 then cfg.tab = (cfg.tab or 1) + 1 end
	cfg.theme_v = 2330
end
if cfg.glass_bg == 2 or cfg.glass_bg == 5 or cfg.glass_bg == 6 then cfg.glass_bg = 1 end
if (cfg.tab or 1) > #TABS then cfg.tab = #TABS end
if (cfg.tab or 1) > #TABS then cfg.tab = 1 end
if cfg.nask_tips then TABS[8] = "Dicas" end
-- 2.6.7: Galeria e Animações trocaram de lugar
if (cfg.theme_v or 0) < 2670 then
	if cfg.tab == 5 then cfg.tab = 6 elseif cfg.tab == 6 then cfg.tab = 5 end
	cfg.theme_v = 2670; save_cfg()
end

-- ---------------------------------------------------------------------------
-- Janela
-- ---------------------------------------------------------------------------
-- anel (setor entre dois raios) e máscara de canto, para bordas arredondadas

local function corner_mask(dl, px, py, cx, cy, r, a0, a1, col)
	local n = math.max(8, math.floor(r / 4))
	local corner = Vector2f.new(px, py)
	for k = 0, n - 1 do
		local t0 = a0 + (a1 - a0) * k / n
		local t1 = a0 + (a1 - a0) * (k + 1) / n
		dl:add_triangle_filled(corner,
			Vector2f.new(cx + math.cos(t0) * r, cy + math.sin(t0) * r),
			Vector2f.new(cx + math.cos(t1) * r, cy + math.sin(t1) * r), col)
	end
end

-- preenche um retângulo deixando "buracos" (onde o d2d desenha as miniaturas)
local function fill_with_holes(dl, x0, y0, x1, y1, holes, col, R)
	local ys = { y0, y1 }
	for _, h in ipairs(holes) do
		table.insert(ys, math.max(y0, math.min(y1, h.y)))
		table.insert(ys, math.max(y0, math.min(y1, h.y + h.h)))
	end
	table.sort(ys)
	local maxb = y0
	for _, h in ipairs(holes) do maxb = math.max(maxb, h.y + h.h) end
	for i = 1, #ys - 1 do
		local a, b = ys[i], ys[i + 1]
		if b > a then
			local xs = {}
			for _, h in ipairs(holes) do
				if h.y < b and h.y + h.h > a then table.insert(xs, { h.x, h.x + h.w }) end
			end
			table.sort(xs, function(p, q) return p[1] < q[1] end)
			local cx = x0
			local last_band = (a >= maxb)
			if #xs == 0 then
				dl:add_rect_filled(Vector2f.new(x0, a), Vector2f.new(x1, b), col, last_band and R or 0.0, last_band and 192 or 0)
			else
				for _, iv in ipairs(xs) do
					if iv[1] > cx then dl:add_rect_filled(Vector2f.new(cx, a), Vector2f.new(iv[1], b), col, 0.0, 0) end
					cx = math.max(cx, iv[2])
				end
				if cx < x1 then dl:add_rect_filled(Vector2f.new(cx, a), Vector2f.new(x1, b), col, 0.0, 0) end
			end
		end
	end
	-- cantos arredondados das miniaturas
	for _, h in ipairs(holes) do
		local r = h.round or (12 * h.w / 320)
		corner_mask(dl, h.x, h.y, h.x + r, h.y + r, r, math.pi, math.pi * 1.5, col)
		corner_mask(dl, h.x + h.w, h.y, h.x + h.w - r, h.y + r, r, math.pi * 1.5, math.pi * 2, col)
		corner_mask(dl, h.x, h.y + h.h, h.x + r, h.y + h.h - r, r, math.pi * 0.5, math.pi, col)
		corner_mask(dl, h.x + h.w, h.y + h.h, h.x + h.w - r, h.y + h.h - r, r, 0, math.pi * 0.5, col)
	end
end

-- erros: aparecem na tela e ficam salvos para mandar
report_error = function(where, err)
	local msg = where .. ": " .. tostring(err)
	shown_error = msg
	if last_errors[where] == msg then return end
	last_errors[where] = msg
	pcall(function()
		local f = io.open("reframework/data/NASK_Fighter/erro.txt", "a")
		if f then f:write(os.date("%d/%m %H:%M:%S  ") .. msg .. "\n\n"); f:close() end
	end)
end
local draw_hud_body
local hud_last = nil
-- v2.6.7: a janela do MMDK abre ao lado do HUD (não em cima do banner).
-- Só posiciona quando ela aparece; depois você pode mover à vontade.
do
	local _bw = imgui.begin_window
	if _bw and not NASK_FC.mmdk_bw_wrapped then
		NASK_FC.mmdk_bw_wrapped = true
		imgui.begin_window = function(name, ...)
			if type(name) == "string" and name:find("^MMDK %- Moveset Research") and NASK_FC.mmdk and NASK_FC.mmdk.open and hud_last then
				local now = os.clock()
				if now - (port.mmdk_seen or -10) > 0.5 then port.mmdk_place_n = 4 end
				port.mmdk_seen = now
				if (port.mmdk_place_n or 0) > 0 then
				port.mmdk_place_n = port.mmdk_place_n - 1
				pcall(function()
					local d = imgui.get_display_size()
					local mw = 540
					local x = hud_last.x + hud_last.w + 12
					if x + mw > d.x then x = hud_last.x - mw - 12 end
					if x < 0 then x = math.max(0, math.min(d.x - mw, hud_last.x)); end
					local y = (x == hud_last.x) and (hud_last.y + hud_last.h + 12) or hud_last.y
					y = math.max(0, math.min(y, d.y - 200))
					imgui.set_next_window_pos(Vector2f.new(x, y), 1)
					if not port.mmdk_logged then
						port.mmdk_logged = true
						pcall(log.info, string.format("[NASK] MMDK posicionado ao lado do HUD em %d,%d", math.floor(x), math.floor(y)))
					end
				end)
				end
			end
			return _bw(name, ...)
		end
	end
end
-- HUD minimizado: só uma pílula no canto de cima, à direita. Clique restaura.
function port.draw_mini()
	local disp = imgui.get_display_size()
	local w, h = 196, 46
	imgui.set_next_window_pos(Vector2f.new(disp.x - w - 20, 16), 1)
	imgui.set_next_window_size(Vector2f.new(w, h), 1)
	push_theme()
	-- 1 sem título, 2 sem redimensionar, 4 sem mover, 8 sem rolagem, 32 sem recolher
	imgui.begin_window("NASK FIGHTER##mini", nil, 1 | 2 | 4 | 8 | 32)
	local ok, err = pcall(function()
		local wp, ws = imgui.get_window_pos(), imgui.get_window_size()
		local dl = window_dl()
		dl:add_rect_filled(Vector2f.new(wp.x, wp.y), Vector2f.new(wp.x + ws.x, wp.y + ws.y), window_bg(), 14.0, 0)
		if glass() then
			dl:add_rect(Vector2f.new(wp.x + 0.5, wp.y + 0.5), Vector2f.new(wp.x + ws.x - 0.5, wp.y + ws.y - 0.5), rgba(255, 255, 255, 0.30), 14.0, 0, 1.0)
		end
		imgui.set_cursor_pos(Vector2f.new(8, 8))
		if colored_button("NASK FIGHTER##restore", true, Vector2f.new(ws.x - 16, ws.y - 16)) then port.mini = false end
		tooltip("Abrir o HUD (" .. keyname("NASK Abrir HUD") .. " também abre)")
		local m = imgui.get_mouse()
		port.mini_hovered = m and m.x >= wp.x and m.y >= wp.y and m.x <= wp.x + ws.x and m.y <= wp.y + ws.y or false
	end)
	imgui.end_window()
	pop_theme()
	if not ok then error(err) end
end

-- ---------------------------------------------------------------------------
-- Tema Pedra (v2.6.2)
-- ---------------------------------------------------------------------------
port.PA, port.PB = { 238, 168, 214 }, { 170, 158, 236 }
function port.mix(a, b, t, al)
	return rgba(math.floor(a[1] + (b[1] - a[1]) * t), math.floor(a[2] + (b[2] - a[2]) * t), math.floor(a[3] + (b[3] - a[3]) * t), al)
end
-- barra logo abaixo do banner, com as abas lado a lado; a aberta fica preenchida
-- com o degradê rosa -> lilás
function port.pedra_tabs(dl, wpos, wsize, inset, header_h)
	local hid = type(cfg.hidden_tabs) == "table" and cfg.hidden_tabs or {}
	if hid[TABS[cfg.tab] or ""] and TABS[cfg.tab] ~= "HUD" then
		for i, name in ipairs(TABS) do if not hid[name] or name == "HUD" then cfg.tab = i; break end end
	end
	local items = {}
	for i, name in ipairs(TABS) do
		if not (hid[name] and name ~= "HUD") then table.insert(items, { i = i, name = name }) end
	end
	local x0, x1 = inset, wsize.x - inset
	local W = x1 - x0
	local bh = 38
	-- quantas linhas: cabe tudo numa só se cada texto couber no seu pedaço
	local maxw = 0
	for _, it in ipairs(items) do maxw = math.max(maxw, imgui.calc_text_size(it.name).x) end
	-- linhas da barra: escolha em HUD > Tema (1 ou 2). Com 1 linha, se os nomes
	-- não couberem, a barra passa para 2 sozinha.
	local want2 = (cfg.tab_rows or 2) == 2
	local nrows = ((want2 and #items > 4) or W / #items < maxw + 14) and 2 or 1
	local per = math.ceil(#items / nrows)
	local y0 = inset + header_h
	-- fundo da barra (vidro rosado claro, como no PSD)
	local ax, ay = wpos.x + x0, wpos.y + y0
	-- faixa como no PSD: quase transparente nas pontas, forte no meio
	local H2 = bh * nrows
	local side, mid = rgba(236, 220, 230, 0.18), rgba(240, 226, 233, 0.86)
	local mx = ax + W * 0.5
	dl:add_rect_filled_multi_color(Vector2f.new(ax, ay), Vector2f.new(mx, ay + H2), side, mid, mid, side)
	dl:add_rect_filled_multi_color(Vector2f.new(mx, ay), Vector2f.new(ax + W, ay + H2), mid, side, side, mid)
	local hs, hm = rgba(255, 255, 255, 0.0), rgba(255, 255, 255, 0.30)
	dl:add_rect_filled_multi_color(Vector2f.new(ax, ay), Vector2f.new(mx, ay + H2 * 0.45), hs, hm, hs, hs)
	dl:add_rect_filled_multi_color(Vector2f.new(mx, ay), Vector2f.new(ax + W, ay + H2 * 0.45), hm, hs, hs, hs)

	local n = 0
	for _, it in ipairs(items) do
		n = n + 1
		local row = math.floor((n - 1) / per)
		local col = (n - 1) % per
		local cnt = math.min(per, #items - row * per)
		local sw = W / cnt
		local sx = x0 + col * sw
		local sy = y0 + row * bh
		imgui.set_cursor_pos(Vector2f.new(sx, sy))
		local clicked = imgui.invisible_button("##ptab" .. it.i, Vector2f.new(sw, bh))
		local hov = imgui.is_item_hovered()
		local act = (cfg.tab == it.i)
		local px, py = wpos.x + sx, wpos.y + sy
		if act then
			dl:add_rect_filled_multi_color(Vector2f.new(px + 1, py + 1), Vector2f.new(px + sw - 1, py + bh - 1),
				port.mix(port.PA, port.PB, 0, 1.0), port.mix(port.PA, port.PB, 1, 1.0), port.mix(port.PA, port.PB, 1, 0.92), port.mix(port.PA, port.PB, 0, 0.92))
			dl:add_line(Vector2f.new(px + 1, py + 1.5), Vector2f.new(px + sw - 1, py + 1.5), rgba(255, 255, 255, 0.75), 1.0)
		elseif hov then
			dl:add_rect_filled(Vector2f.new(px + 1, py + 1), Vector2f.new(px + sw - 1, py + bh - 1), rgba(255, 255, 255, 0.30), 0, 0)
		end
		if col > 0 then
			dl:add_line(Vector2f.new(px, py + 8), Vector2f.new(px, py + bh - 8), rgba(120, 100, 140, 0.25), 1.0)
		end
		local ts = imgui.calc_text_size(it.name)
		dl:add_text(Vector2f.new(px + (sw - ts.x) * 0.5, py + (bh - ts.y) * 0.5), act and rgba(255, 255, 255, 1.0) or rgba(64, 54, 86, 1.0), it.name)
		if clicked then cfg.tab = it.i; save_cfg() end
	end
	imgui.set_cursor_pos(Vector2f.new(14, y0 + bh * nrows + 10))
end
-- espaço reservado embaixo para a bolinha do Portátil
function port.pedra_reserve(wsize)
	return math.floor(math.max(64, math.min(96, wsize.x * 0.11)))
end
-- parte de baixo do HUD: degradê rosa/branco em faixas diagonais desfocadas, que
-- sobe sumindo aos poucos. A imagem foi "assada" numa grade de cores (abaixo) e é
-- desenhada com retângulos de 4 cores, então fica lisa e não depende do d2d.
port.PEDRA_GRID = { nx = 16, ny = 14,
{{250,236,246,0},{250,236,246,0},{250,236,246,0},{250,236,246,0},{250,236,246,0},{250,236,246,0},{250,231,244,0},{247,215,238,0},{242,183,227,0},{237,150,215,0},{231,130,209,0},{223,127,209,0},{209,138,218,0},{196,153,228,0},{196,172,235,0},{215,198,240,0},{233,217,243,0}},
{{250,236,246,7},{250,236,246,7},{250,236,246,7},{250,236,246,7},{250,236,246,7},{250,236,246,7},{249,230,244,7},{246,212,237,7},{242,180,226,7},{236,148,214,7},{230,130,208,7},{222,128,210,7},{208,139,219,7},{194,154,229,7},{197,174,236,7},{217,199,241,7},{234,219,244,7}},
{{250,236,246,18},{250,236,246,18},{250,236,246,18},{250,236,246,18},{250,236,246,18},{250,235,246,18},{249,228,243,18},{246,207,235,18},{241,174,224,18},{235,144,213,18},{229,128,208,18},{220,129,211,18},{205,140,220,18},{193,156,230,18},{198,176,237,18},{219,202,241,18},{236,221,244,18}},
{{250,236,246,31},{250,236,246,31},{250,236,246,31},{250,236,246,31},{250,236,246,31},{250,234,245,31},{248,225,242,31},{245,200,233,31},{239,167,221,31},{234,140,211,31},{228,127,208,31},{217,130,212,31},{201,142,222,31},{191,158,232,31},{200,179,238,31},{222,206,242,31},{238,224,244,31}},
{{250,236,246,46},{250,236,246,46},{250,236,246,46},{250,236,246,46},{250,236,246,46},{250,233,245,46},{248,221,240,46},{244,194,231,46},{238,160,219,46},{233,136,210,46},{226,127,208,46},{213,132,214,46},{197,145,224,46},{190,161,233,46},{202,183,238,46},{225,209,242,46},{241,226,244,46}},
{{250,236,246,62},{250,236,246,62},{250,236,246,62},{250,236,246,62},{250,236,246,62},{249,232,244,62},{247,216,239,62},{243,187,228,62},{237,154,217,62},{232,133,209,62},{224,127,209,62},{209,134,216,62},{194,147,226,62},{190,163,234,62},{204,186,239,62},{228,212,243,62},{242,228,245,62}},
{{250,236,246,79},{250,236,246,79},{250,236,246,79},{250,236,246,79},{250,236,246,79},{249,229,243,79},{246,211,237,79},{242,180,226,79},{236,150,215,79},{231,133,210,79},{221,129,210,79},{206,137,218,79},{191,150,228,79},{190,166,235,79},{207,189,240,79},{230,215,243,79},{244,229,245,79}},
{{251,238,247,96},{251,238,247,96},{251,238,247,96},{250,237,247,96},{250,235,246,96},{248,226,242,96},{245,204,234,96},{240,174,223,96},{236,148,214,96},{230,135,210,96},{219,133,213,96},{202,141,221,96},{189,153,230,96},{191,169,236,96},{210,193,240,96},{233,218,243,96},{245,231,245,96}},
{{252,241,248,115},{252,241,248,115},{252,241,248,115},{251,240,248,115},{250,236,246,115},{248,222,241,115},{244,196,231,115},{239,168,221,115},{235,149,214,115},{230,140,212,115},{217,139,216,115},{199,145,224,115},{188,156,232,115},{193,172,237,115},{214,197,240,115},{236,220,244,115},{247,232,246,115}},
{{253,245,250,135},{253,245,250,135},{253,245,250,135},{253,244,250,135},{251,237,247,135},{248,219,240,135},{243,190,229,135},{238,164,219,135},{235,150,214,135},{229,145,214,135},{215,146,219,135},{197,151,227,135},{188,160,233,135},{197,177,238,135},{219,201,241,135},{239,222,244,135},{248,232,245,135}},
{{254,248,252,154},{254,248,252,154},{254,248,252,154},{254,247,251,154},{252,240,248,154},{248,219,241,154},{243,189,229,154},{238,163,219,154},{235,151,215,154},{227,149,216,154},{212,150,222,154},{195,155,229,154},{190,165,235,154},{204,184,238,154},{226,207,241,154},{243,225,244,154},{250,232,245,154}},
{{255,249,253,175},{255,249,253,175},{255,250,253,175},{255,249,253,175},{253,242,250,175},{249,222,242,175},{243,191,230,175},{238,164,219,175},{234,152,215,175},{225,151,217,175},{208,153,224,175},{193,159,231,175},{194,171,236,175},{212,192,239,175},{233,214,242,175},{246,227,244,175},{251,232,244,175}},
{{255,250,253,196},{255,250,253,196},{255,250,253,196},{255,250,253,196},{254,244,250,196},{250,225,243,196},{244,193,230,196},{238,165,220,196},{233,153,216,196},{222,152,219,196},{204,154,226,196},{192,161,232,196},{199,177,237,196},{220,200,240,196},{240,220,243,196},{249,229,244,196},{252,232,244,196}},
{{255,250,253,217},{255,250,253,217},{255,250,253,217},{255,250,253,217},{254,244,250,217},{250,225,243,217},{244,193,231,217},{238,165,220,217},{232,153,217,217},{219,152,220,217},{201,155,227,217},{192,163,233,217},{202,181,238,217},{225,205,241,217},{243,223,243,217},{251,231,244,217},{252,232,244,217}},
{{255,250,253,238},{255,250,253,238},{255,250,253,238},{255,249,253,238},{253,243,250,238},{249,224,243,238},{243,192,230,238},{238,164,219,238},{231,152,216,238},{218,152,220,238},{199,156,228,238},{191,163,234,238},{203,182,238,238},{227,207,241,238},{245,225,243,238},{251,231,244,238},{252,232,244,238}} }
function port.pedra_bottom(dl, wpos, wsize)
	local G = port.PEDRA_GRID
	local R = 14
	local x0, x1 = math.floor(wpos.x + 1), math.floor(wpos.x + wsize.x - 1)
	local yb = math.floor(wpos.y + wsize.y - 1)
	local H = math.floor(wsize.y * 0.48)
	local y0 = yb - H
	local ycut = yb - R
	local function col(j, i)
		local c = G[j + 1][i + 1]
		return rgba(c[1], c[2], c[3], c[4] / 255)
	end
	-- bordas das células em pixel inteiro e compartilhadas: sem sobreposição
	-- (a sobreposição somava a transparência e aparecia como linha)
	local XS, YS = {}, {}
	for i = 0, G.nx do XS[i] = math.floor(x0 + (x1 - x0) * i / G.nx + 0.5) end
	for j = 0, G.ny do YS[j] = math.floor(y0 + (ycut - y0) * j / G.ny + 0.5) end
	for j = 0, G.ny - 1 do
		for i = 0, G.nx - 1 do
			dl:add_rect_filled_multi_color(Vector2f.new(XS[i], YS[j]), Vector2f.new(XS[i + 1], YS[j + 1]),
				col(j, i), col(j, i + 1), col(j + 1, i + 1), col(j + 1, i))
		end
	end
	-- faixa final (altura do arredondamento): meio em degradê...
	for i = 0, G.nx - 1 do
		local ax, bx = math.max(x0 + R, XS[i]), math.min(x1 - R, XS[i + 1])
		if bx > ax then
			dl:add_rect_filled_multi_color(Vector2f.new(ax, ycut), Vector2f.new(bx, yb),
				col(G.ny, i), col(G.ny, i + 1), col(G.ny, i + 1), col(G.ny, i))
		end
	end
	-- ...e um quarto de círculo em cada ponta, igual ao canto da janela
	local function corner(cx, sign, c)
		dl:path_clear()
		dl:path_line_to(Vector2f.new(cx, ycut))
		for k = 0, 12 do
			local t = (k / 12) * math.pi * 0.5
			dl:path_line_to(Vector2f.new(cx + sign * math.sin(t) * R, ycut + math.cos(t) * R))
		end
		dl:path_line_to(Vector2f.new(cx + sign * R, ycut))
		dl:path_fill_concave(c)
	end
	corner(x0 + R, -1, col(G.ny, 0))
	corner(x1 - R, 1, col(G.ny, G.nx))
end

-- bolinha embaixo, no centro, num encaixe do vidro: abre o modo foto Portátil
function port.pedra_ball(dl, wpos, wsize)
	local reserve = port.pedra_reserve(wsize)
	local r = reserve * 0.34
	local cx = wpos.x + wsize.x * 0.5
	local cy = wpos.y + wsize.y - reserve * 0.5
	-- encaixe (arco escuro em volta, como o recorte do vidro no PSD)
	dl:add_circle_filled(Vector2f.new(cx, cy), r + 7, rgba(20, 30, 38, 0.38), 48)
	dl:add_circle(Vector2f.new(cx, cy), r + 7, rgba(230, 242, 246, 0.55), 48, 1.4)
	imgui.set_cursor_pos(Vector2f.new(wsize.x * 0.5 - r, wsize.y - reserve * 0.5 - r))
	local clicked = imgui.invisible_button("##pedra_ball", Vector2f.new(r * 2, r * 2))
	local hov = imgui.is_item_hovered()
	tooltip("Tirar foto. Tecla: " .. keyname("NASK Foto"))
	-- bola lilás clara, mais rosada com o mouse em cima
	local base = hov and { 236, 196, 226 } or { 214, 200, 218 }
	dl:add_circle_filled(Vector2f.new(cx, cy), r, rgba(base[1], base[2], base[3], 0.96), 48)
	dl:add_circle_filled(Vector2f.new(cx - r * 0.25, cy - r * 0.3), r * 0.55, rgba(255, 255, 255, 0.14), 32)
	dl:add_circle(Vector2f.new(cx, cy), r, rgba(255, 255, 255, 0.65), 48, 1.2)
	if imgui.is_item_active() then dl:add_circle_filled(Vector2f.new(cx, cy), r * 0.82, rgba(255, 255, 255, 0.35), 40) end
	if clicked then port.take_photo() end
end

local function draw_hud()
	port.rect_n, port.rect_stack = 0, {}
	local disp = imgui.get_display_size()
	local dw, dh = math.floor(disp.x), math.floor(disp.y)
	-- tamanho fixo na proporção dos fundos (800 x 1126); em telas menores encolhe
	-- inteiro, sem mudar a proporção (a imagem nunca estica)
	local hs = math.min(1.0, (dh - 80) / 1126, (dw - 40) / 800)
	local want_w, want_h = math.floor(800 * hs), math.floor(1126 * hs)
	-- mudou a resolução (ex.: 3K -> 1080p) ou a janela saiu da tela: volta ao tamanho certo
	local reset = (cfg.last_disp_w ~= dw or cfg.last_disp_h ~= dh)
	-- v2.6.3: a janela pode ir para fora da tela à vontade (antes ela era puxada de
	-- volta a cada frame enquanto você arrastava, e tremia). Só volta se sumir quase
	-- inteira, e só quando você solta o mouse.
	local lmb = false
	pcall(function() lmb = reframework:is_key_down(0x01) end)
	if hud_last and not lmb and (hud_last.y > dh - 4 or hud_last.x > dw - 4 or hud_last.x + hud_last.w < 4 or hud_last.y + hud_last.h < 4) then reset = true end
	if reset then
		cfg.last_disp_w, cfg.last_disp_h = dw, dh
		save_cfg()
		imgui.set_next_window_pos(Vector2f.new(math.max(10, dw - want_w - 40), math.max(10, (dh - want_h) * 0.5)), 1)
	else
		imgui.set_next_window_pos(Vector2f.new(math.max(10, dw - want_w - 40), math.max(10, (dh - want_h) * 0.5)), 4)
	end
	imgui.set_next_window_size(Vector2f.new(want_w, want_h), 1)

	push_theme()
	-- 1 = NoTitleBar, 2 = NoResize, 32 = NoCollapse
	imgui.begin_window("NASK FIGHTER##hud", nil, 1 | 2 | 32)
	local ok, err = xpcall(draw_hud_body, debug.traceback)
	if not ok then
		report_error("HUD", err)
		pcall(imgui.text_colored, "Erro no HUD (salvo em data/NASK_Fighter/erro.txt):", WARN)
		pcall(imgui.text, tostring(err))
	end
	imgui.end_window()
	pop_theme()
end

draw_hud_body = function()
	local wpos, wsize = imgui.get_window_pos(), imgui.get_window_size()
	hud_last = { x = wpos.x, y = wpos.y, w = wsize.x, h = wsize.y }
	local dl = window_dl()

	local inset = 6
	local hx, hy, hw = wpos.x + inset, wpos.y + inset, wsize.x - inset * 2
	local crisp = use_d2d()
	local header_h = 64
	if crisp then
		header_h = math.max(60, math.min(260, hw / header_aspect()))
		d2d_rect = { x = hx, y = hy, w = hw, h = header_h }
	end

	local okp, errp = pcall(function()
		local wx2, wy2 = wpos.x + wsize.x, wpos.y + wsize.y
		local R = 14.0
		local bg = window_bg()
		local yb = hy + header_h
		if port.glass_tex() then
			table.insert(port.glass_rects, { x = wpos.x, y = wpos.y, w = wsize.x, h = wsize.y, a = 0.85 + 0.15 * cfg.opacity })
			if (cfg.glass_dark or 0) > 0 then
				dl:add_rect_filled(Vector2f.new(wpos.x, yb), Vector2f.new(wx2, wy2), rgba(10, 8, 16, cfg.glass_dark), R, 192)
			end
		elseif crisp then
			-- moldura em volta da imagem como UM polígono (U invertido): sem emendas
			-- entre pedaços translúcidos, que apareciam como riscos/fundo nos cantos.
			-- A imagem tem cantos arredondados no próprio PNG (raio proporcional).
			local r = math.max(4, hw * 8 / 528)
			local pi = math.pi
			-- pontos montados aqui, sem repetidos (pontos duplicados estragam o
			-- preenchimento côncavo do ImGui e o banner ficava coberto de branco)
			local pts = {}
			local function pt(x, y)
				local l = pts[#pts]
				if l and math.abs(l[1] - x) < 0.05 and math.abs(l[2] - y) < 0.05 then return end
				pts[#pts + 1] = { x, y }
			end
			local function arc(cx, cy, rad, a0, a1, n)
				for k = 0, n do
					local t = a0 + (a1 - a0) * k / n
					pt(cx + math.cos(t) * rad, cy + math.sin(t) * rad)
				end
			end
			pt(wpos.x, yb)
			arc(wpos.x + R, wpos.y + R, R, pi, pi * 1.5, 12)
			arc(wx2 - R, wpos.y + R, R, pi * 1.5, pi * 2, 12)
			pt(wx2, yb)
			arc(hx + hw - r, yb - r, r, pi * 0.5, 0, 8)
			arc(hx + hw - r, hy + r, r, 0, -pi * 0.5, 8)
			arc(hx + r, hy + r, r, -pi * 0.5, -pi, 8)
			arc(hx + r, yb - r, r, pi, pi * 0.5, 8)
			if math.abs(pts[#pts][1] - pts[1][1]) < 0.05 and math.abs(pts[#pts][2] - pts[1][2]) < 0.05 then pts[#pts] = nil end
			dl:path_clear()
			for _, q in ipairs(pts) do dl:path_line_to(Vector2f.new(q[1], q[2])) end
			dl:path_fill_concave(bg)
			-- corpo (abaixo da imagem), com buracos para as miniaturas da galeria
			local holes = (cfg.tab == TAB_GAL) and gal.prev_rects or {}
			if port.profile_draw then local pf = port.profile_draw; holes = { { x = pf.x, y = pf.y, w = pf.w, h = pf.h, round = pf.w * 0.5 } } end
			if #holes == 0 then
				dl:add_rect_filled(Vector2f.new(wpos.x, yb), Vector2f.new(wx2, wy2), bg, R, 192)
			else
				fill_with_holes(dl, wpos.x, yb, wx2, wy2, holes, bg, R)
			end
		end
		local gy = yb
		if port.glass_tex() then
			dl:add_rect(Vector2f.new(wpos.x + 0.5, wpos.y + 0.5), Vector2f.new(wx2 - 0.5, wy2 - 0.5), rgba(255, 255, 255, 0.40), R, 0, 1.0)
			dl:add_line(Vector2f.new(wpos.x + R, wpos.y + 0.5), Vector2f.new(wx2 - R, wpos.y + 0.5), rgba(255, 255, 255, 0.85), 1.0)
		elseif (cfg.style == 4 or cfg.style == 5) then
			-- Pedra: vidro fosco claro, mais branco em cima, borda clara e fio de luz
			local gb = wy2 - R
			if gb > gy then
				dl:add_rect_filled_multi_color(Vector2f.new(wpos.x + 1, gy), Vector2f.new(wx2 - 1, gb),
					rgba(225, 238, 242, 0.20), rgba(225, 238, 242, 0.16),
					rgba(255, 250, 240, 0.10), rgba(255, 250, 240, 0.12))
			end
			dl:add_rect(Vector2f.new(wpos.x + 0.5, wpos.y + 0.5), Vector2f.new(wx2 - 0.5, wy2 - 0.5), rgba(235, 245, 248, 0.55), R, 0, 1.2)
			dl:add_line(Vector2f.new(wpos.x + R, wpos.y + 0.5), Vector2f.new(wx2 - R, wpos.y + 0.5), rgba(255, 255, 255, 0.90), 1.0)
		elseif glass() then
			-- vidro do PSD: véu branco muito fraco (mais forte em cima à esquerda),
			-- borda clara de 1 px e fio de luz no topo
			local gb = wy2 - R
			if gb > gy then
				dl:add_rect_filled_multi_color(Vector2f.new(wpos.x + 1, gy), Vector2f.new(wx2 - 1, gb),
					rgba(255, 255, 255, 0.10), rgba(255, 255, 255, 0.05),
					rgba(255, 255, 255, 0.015), rgba(255, 255, 255, 0.04))
			end
			dl:add_rect(Vector2f.new(wpos.x + 0.5, wpos.y + 0.5), Vector2f.new(wx2 - 0.5, wy2 - 0.5), rgba(255, 255, 255, 0.30), R, 0, 1.0)
			dl:add_line(Vector2f.new(wpos.x + R, wpos.y + 0.5), Vector2f.new(wx2 - R, wpos.y + 0.5), rgba(255, 255, 255, 0.85), 1.0)
		else
			-- acrílico: brilho branco suave abaixo do cabeçalho
			dl:add_rect_filled_multi_color(Vector2f.new(wpos.x, gy), Vector2f.new(wx2, gy + (wy2 - gy) * 0.5),
				rgba(255, 255, 255, 0.30 * cfg.opacity), rgba(255, 255, 255, 0.30 * cfg.opacity), rgba(255, 255, 255, 0), rgba(255, 255, 255, 0))
		end
	end)
	if not okp then report_error("fundo", errp) end

	if not crisp and cfg.header_quality > 1 then
		header_h = math.max(draw_header_image(dl, hx, hy, hw), 64)
	end
	local okp, errp = pcall(function()
		-- fade da imagem para o fundo branco + título
		if cfg.banner_fade then
			local fade_top = hy + header_h * 0.58
			dl:add_rect_filled_multi_color(Vector2f.new(hx, fade_top), Vector2f.new(hx + hw, hy + header_h + 1),
				bg_col(0), bg_col(0), bg_col(0.92 * math.max(0.6, cfg.opacity)), bg_col(0.92 * math.max(0.6, cfg.opacity)))
		end
		if (cfg.banner_dark or 0) > 0 then
			-- escurece a parte de baixo do banner para o título ficar legível
			local top = hy + header_h * 0.35
			local k = cfg.banner_dark
			dl:add_rect_filled_multi_color(Vector2f.new(hx, top), Vector2f.new(hx + hw, hy + header_h),
				rgba(8, 6, 14, 0), rgba(8, 6, 14, 0), rgba(8, 6, 14, k), rgba(8, 6, 14, k))
		end
		if cfg.banner_text_on then
			dl:add_rect_filled(Vector2f.new(hx + 10, hy + header_h - 2), Vector2f.new(hx + 110, hy + header_h), accent(1.0), 2.0, 0)
			if title_font then imgui.push_font(title_font) end
			dl:add_text(Vector2f.new(hx + 11, hy + header_h - 50), rgba(0, 0, 0, 0.45), cfg.banner_title or "")
			local tc = cfg.title_rgb
			dl:add_text(Vector2f.new(hx + 10, hy + header_h - 52), tc and rgba(math.floor(tc[1] * 255), math.floor(tc[2] * 255), math.floor(tc[3] * 255), 1.0) or INK, cfg.banner_title or "")
			if title_font then imgui.pop_font() end
			if sub_font then imgui.push_font(sub_font) end
			local sc = cfg.sub_rgb
			dl:add_text(Vector2f.new(hx + 12, hy + header_h - 22), sc and rgba(math.floor(sc[1] * 255), math.floor(sc[2] * 255), math.floor(sc[3] * 255), 1.0) or accent(1.0), cfg.banner_sub or "")
			if sub_font then imgui.pop_font() end
		end
	end)
	if not okp then report_error("fundo", errp) end

	-- botão fechar sobre a imagem
	imgui.set_cursor_pos(Vector2f.new(wsize.x - 72, inset + 6))
	if imgui.button("-##min") then port.mini = true end
	tooltip("Minimizar (fica no canto de cima, à direita)")
	imgui.set_cursor_pos(Vector2f.new(wsize.x - 40, inset + 6))
	if imgui.button("×##close") then hud_open = false end
	tooltip("Fechar (" .. keyname("NASK Abrir HUD") .. " reabre)")

	imgui.set_cursor_pos(Vector2f.new(14, inset + header_h + 10))

	if (cfg.style == 4 or cfg.style == 5) then
		port.pedra_tabs(dl, wpos, wsize, inset, header_h)
	else
	-- Abas centralizadas (quebram linha se não couberem; cada linha no centro)
	do
		local avail, gap = wsize.x - 28, 8
		local rows, cur, cw = {}, {}, 0
		local hid = type(cfg.hidden_tabs) == "table" and cfg.hidden_tabs or {}
		if hid[TABS[cfg.tab] or ""] and TABS[cfg.tab] ~= "HUD" then
			for i, name in ipairs(TABS) do if not hid[name] or name == "HUD" then cfg.tab = i; break end end
		end
		for i, name in ipairs(TABS) do
			if hid[name] and name ~= "HUD" then goto continue end
			local w = imgui.calc_text_size(name).x + 18
			local add = (#cur > 0 and gap or 0) + w
			if #cur > 0 and cw + add > avail then table.insert(rows, { items = cur, w = cw }); cur, cw = {}, 0; add = w end
			table.insert(cur, { i = i, name = name, w = w }); cw = cw + add
			::continue::
		end
		if #cur > 0 then table.insert(rows, { items = cur, w = cw }) end
		for _, row in ipairs(rows) do
			local y = imgui.get_cursor_pos().y
			local x = (wsize.x - row.w) * 0.5
			for k, it in ipairs(row.items) do
				if k > 1 then imgui.same_line() end
				imgui.set_cursor_pos(Vector2f.new(x, y))
				if colored_button(it.name .. "##tab" .. it.i, cfg.tab == it.i, Vector2f.new(it.w, 0)) then
					cfg.tab = it.i
					save_cfg()
				end
				x = x + it.w + gap
			end
		end
	end
	end
	imgui.spacing()

	if (cfg.style == 4 or cfg.style == 5) then
		local reserve = port.pedra_reserve(wsize)
		imgui.begin_child_window("##nask_body", Vector2f.new(0, -(reserve + 20)), false, 0)
	else
		imgui.begin_child_window("##nask_body", Vector2f.new(0, -24), false, 0)
	end
	local ok, err = xpcall(TAB_FN[cfg.tab] or tab_modo_foto, debug.traceback)
	if not ok then report_error("aba " .. tostring(cfg.tab), err); imgui.text_colored("Erro: " .. tostring(err), WARN) end
	imgui.end_child_window()
	if (cfg.style == 4 or cfg.style == 5) then pcall(port.pedra_bottom, dl, wpos, wsize); pcall(port.pedra_ball, dl, wpos, wsize) end
	-- aviso fixo no rodapé de todas as abas
	pcall(function()
		local txt = "Use só offline / modo treino. Não use online."
		if NASK_FC.lang and NASK_FC.lang.active and NASK_FC.lang.active() then txt = NASK_FC.lang.t(txt) end
		local ts = imgui.calc_text_size(txt)
		local fy = (cfg.style == 4 or cfg.style == 5) and (wsize.y - port.pedra_reserve(wsize) - 18) or (wsize.y - 22)
		local col = (cfg.style == 4 or cfg.style == 5) and rgba(255, 255, 255, 0.85) or WARN
		imgui.get_window_draw_list():add_text(Vector2f.new(wpos.x + (wsize.x - ts.x) * 0.5, wpos.y + fy), col, txt)
	end)

	local m = imgui.get_mouse()
	hovered = m and m.x >= wpos.x and m.y >= wpos.y and m.x <= wpos.x + wsize.x and m.y <= wpos.y + wsize.y or false
end

-- ---------------------------------------------------------------------------
-- Loop
-- ---------------------------------------------------------------------------
local frame_main
re.on_frame(function()
	local ok, err = NASK_FC.lang.run(frame_main)
	if not ok then report_error("frame", err) end
	if shown_error and hud_open then
		local err = shown_error
		pcall(function()
			local fl = front_dl()
			fl:add_rect_filled(Vector2f.new(20, 60), Vector2f.new(900, 200), bg_col(0.95), 10.0, 0)
			fl:add_text(Vector2f.new(30, 70), WARN, "NASK Fighter - erro (salvo em reframework/data/NASK_Fighter/erro.txt):")
			fl:add_text(Vector2f.new(30, 92), INK, tostring(err):sub(1, 900))
		end)
	end
end)

-- idioma
function NASK_FC.set_lang(id)
	cfg.lang = id
	NASK_FC.lang.set(id)
	NASK_FC.apply_lang_fonts()
	save_cfg()
end
-- primeira vez: escolher o idioma (janela no meio da tela)
function NASK_FC.draw_lang_pick()
	local disp = imgui.get_display_size()
	local w, h = 420, 220
	imgui.set_next_window_pos(Vector2f.new((disp.x - w) * 0.5, (disp.y - h) * 0.5), 1)
	imgui.set_next_window_size(Vector2f.new(w, h), 1)
	-- a lista mostra cada idioma na própria escrita: precisa da fonte Noto
	local pushed = NASK_FC.fonts.main and pcall(imgui.push_font, NASK_FC.fonts.main)
	push_theme()
	imgui.begin_window("NASK FIGHTER##langpick", nil, 1 | 2 | 4 | 8 | 32)
	local ok, err = pcall(function()
		local wp, ws = imgui.get_window_pos(), imgui.get_window_size()
		local dl = window_dl()
		dl:add_rect_filled(Vector2f.new(wp.x, wp.y), Vector2f.new(wp.x + ws.x, wp.y + ws.y), rgba(28, 22, 40, 0.97), 14.0, 0)
		dl:add_rect(Vector2f.new(wp.x + 0.5, wp.y + 0.5), Vector2f.new(wp.x + ws.x - 0.5, wp.y + ws.y - 0.5), accent(0.9), 14.0, 0, 1.5)
		local t1 = "NASK FIGHTER"
		if NASK_FC.fonts.title then imgui.push_font(NASK_FC.fonts.title) end
		imgui.set_cursor_pos(Vector2f.new((ws.x - imgui.calc_text_size(t1).x) * 0.5, 18))
		imgui.text_colored(t1, WHITE)
		if NASK_FC.fonts.title then imgui.pop_font() end
		local t2 = "Idioma  ·  Language"
		imgui.set_cursor_pos(Vector2f.new((ws.x - imgui.calc_text_size(t2).x) * 0.5, 56))
		imgui.text_colored(t2, MUTED)
		local y = 92
		for _, l in ipairs(NASK_FC.lang.LANGS) do
			imgui.set_cursor_pos(Vector2f.new(60, y))
			if glass_button("##lang_" .. l.id, l.name, false, ws.x - 120, 42) then NASK_FC.set_lang(l.id) end
			y = y + 50
		end
		local m = imgui.get_mouse()
		NASK_FC.lang_pick_hovered = m and m.x >= wp.x and m.y >= wp.y and m.x <= wp.x + ws.x and m.y <= wp.y + ws.y or false
	end)
	imgui.end_window()
	pop_theme()
	if pushed then imgui.pop_font() end
	if not ok then error(err) end
end

-- abre o HUD "limpo": painéis, abas de lutador/luz e árvores recolhidos
function NASK_FC.ui_reset()
	cfg.panels = cfg.panels or {}
	for k in pairs(cfg.panels) do cfg.panels[k] = false end
	for _, st in ipairs({ qs, qs.poser, qs.lights }) do
		if type(st) == "table" then st.open = {} end
	end
	for k in pairs(tree_state) do tree_state[k] = nil end
	NASK_FC.ui_gen = (NASK_FC.ui_gen or 0) + 1
	keys_win.open = false
	port.tut = nil
	port.mini = false
	save_cfg()
end

frame_main = function()
	if port.start == nil then
		port.start = true
		if cfg.open_mode == 2 and hud_open then hud_open = false; port.open = true end
	end
	if keys.pressed("NASK Abrir HUD") then
		if cfg.open_mode == 2 then
			port.open = not port.open
			if port.open then hud_open = false end
		elseif hud_open and port.mini then
			port.mini = false
		else
			hud_open = not hud_open
		end
	end
	if keys.pressed("NASK Portatil") then
		port.open = not port.open
		if port.open then hud_open = false end
	end

	local turn_l, turn_r, zero = keys.pressed("NASK Girar Esquerda"), keys.pressed("NASK Girar Direita"), keys.pressed("NASK Zerar Inclinacao")
	if NASK_FC.on then
		if turn_l then NASK_FC.pending_roll = -math.rad(cfg.roll_step) end
		if turn_r then NASK_FC.pending_roll = math.rad(cfg.roll_step) end
		if zero then NASK_FC.reset_roll = true end
	end

	pcall(NASK_FC.apply_ldr, cfg.vs_walk_off)
	pcall(NASK_FC.dof_tick)
	pcall(NASK_FC.clean_tick)
	pcall(NASK_FC.user_tick)

	d2d_rect = nil
	gal.prev_rects = gal.rects
	gal.rects = {}
	if keys.pressed("NASK Foto") then take_photo() end
	pcall(NASK_FC.mmdk.keys_tick, cfg, save_cfg)
	pcall(NASK_FC.pose_others_tick)
	if keys.pressed("NASK Abrir MMDK") then pcall(NASK_FC.mmdk.toggle) end
	-- MMDK fechado pelo X dele: o HUD volta também
	if port.mini_by_mmdk and not NASK_FC.mmdk.is_open() then port.mini = false; port.mini_by_mmdk = false end
	if keys.pressed("NASK Preview Vertical") then cfg.vpreview = not cfg.vpreview; save_cfg() end
	local hiding_for_photo = cap.hide > 0
	cap_tick()
	if hud_open and not port.was_open then pcall(NASK_FC.ui_reset) end
	port.was_open = hud_open
	local show = hud_open and not port.mini and not (cfg.hide_hud_with_ui and NASK_FC.hide_ui) and not hiding_for_photo
	local show_mini = hud_open and port.mini and not (cfg.hide_hud_with_ui and NASK_FC.hide_ui) and not hiding_for_photo
	port.rect, port.dof_rect, port.hovered = nil, nil, false
	port.glass_rects = {}
	-- preview vertical: gira a câmera só na tela; some na hora da foto (a foto sai deitada, como foi feita)
	local vp_on = cfg.vpreview == true and not hiding_for_photo and cap.pending == nil
	NASK_FC.vp_flip = cfg.vp_flip == true
	NASK_FC.no_distort = cfg.no_distort ~= false
	if NASK_FC.vpreview ~= vp_on then NASK_FC.set_vpreview(vp_on) end
	port.vp_bars = nil
	if vp_on then pcall(port.draw_vpreview) end
	local show_port = port.open and not hiding_for_photo
	if show_port then pcall(port.draw) end
	if show then
		draw_hud()
		if keys_win.open then
			local okk, errk = pcall(draw_keys_window)
			if not okk then report_error("janela de atalhos", errk) end
			hovered = hovered or keys_win.hovered
		end
		port.tut_hovered = false
		if port.tut then
			local okt, errt = pcall(port.draw_tut)
			if not okt then report_error("tutorial", errt) end
			hovered = hovered or port.tut_hovered
		end
	else
		hovered = false
	end
	if show_mini then
		local okm, errm = pcall(port.draw_mini)
		if not okm then report_error("HUD minimizado", errm) end
		hovered = port.mini_hovered == true
	end
	if show_port then hovered = hovered or port.hovered end
	gal_draw = (show and cfg.tab == TAB_GAL and use_d2d()) and gal.rects or {}
	port.profile_draw = (show and TABS[cfg.tab] == "NASK" and use_d2d()) and port.profile_rect or nil
	port.profile_rect = nil
	-- v2.6.1: gizmos só aparecem com o painel deles aberto na tela
	-- (Extras > Luzes, Poser com o lutador aberto, Luzes da cena)
	local function ui_seen(t) return t ~= nil and os.clock() - t < 0.2 end
	draw_lights(show and ui_seen(nlights.ui_t))
	draw_poser_gizmo(show and ui_seen(poser.ui_t) and poser.ui_pk == poser.sel_pk)
	draw_slight_gizmo(show and ui_seen(slights.ui_t))
	pcall(port.cmove_gizmo, show and ui_seen(poser.ui_t))
	sync_bridge()
	if NASK_FC and os.clock() < nlights.gizmo_until then NASK_FC.block_mouse = true end

	local show_lang = cfg.lang == nil and not hiding_for_photo
	if show_lang then
		local okl, errl = pcall(NASK_FC.draw_lang_pick)
		if not okl then report_error("idioma", errl) end
		hovered = hovered or NASK_FC.lang_pick_hovered == true
		show_mini = show_mini or true
	end
	_G.NASK_HUD_OPEN = show
	local ref_menu = reframework:is_drawing_ui()
	local want_cursor
	-- v2.5.8: a janela do MMDK aberta pelo NASK também conta como "HUD aberto"
	-- (antes a seta sumia quando só o MMDK estava na tela)
	local mmdk_open = NASK_FC.mmdk and NASK_FC.mmdk.open == true and not hiding_for_photo
	if cfg.cursor_mode == 5 then
		want_cursor = (show or show_port or show_mini or mmdk_open) and not ref_menu and not hiding_for_photo
	else
		want_cursor = cfg.cursor_mode == 1 or (cfg.cursor_mode == 2 and (show or show_mini or mmdk_open)) or (cfg.cursor_mode == 4 and ((show or show_mini) and hovered or mmdk_open))
	end
	if not HAS_FG then want_cursor = false end
	nask_hide_game_cursor = want_cursor and cfg.cursor_mode ~= 3
	if want_cursor then draw_cursor() end
	-- aviso rápido depois da foto (aparece mesmo com o HUD fechado; não sai na foto)
	if cap.msg and os.clock() - cap.msg_t < 2.5 and not hiding_for_photo then
		pcall(function()
			local dl = front_dl()
			dl:add_rect_filled(Vector2f.new(20, 20), Vector2f.new(40 + imgui.calc_text_size(cap.msg).x, 52), bg_col(0.92), 10.0, 0)
			dl:add_text(Vector2f.new(30, 28), INK, cap.msg)
		end)
	end
end

-- esconde a seta do próprio jogo enquanto o mouse está em cima do HUD
local gui_names = {}
re.on_pre_gui_draw_element(function(element, context)
	if not nask_hide_game_cursor then return true end
	local k = addr(element)
	local nm = gui_names[k]
	if nm == nil then
		local ok, go = pcall(element.call, element, "get_GameObject")
		nm = (ok and go and go:call("get_Name") or ""):lower()
		gui_names[k] = nm
	end
	if nm:find("cursor") or nm:find("pointer") then return false end
	return true
end)

re.on_draw_ui(function()
	NASK_FC.lang.run(function()
	if imgui.tree_node("NASK FIGHTER v" .. VERSION) then
		local names, cur = {}, 1
		for i, l in ipairs(NASK_FC.lang.LANGS) do names[i] = l.name; if l.id == cfg.lang then cur = i end end
		local chl, nl = imgui.combo("Idioma / Language", cur, names)
		if chl then NASK_FC.set_lang(NASK_FC.lang.LANGS[nl].id) end
		changed, hud_open = imgui.checkbox("Mostrar HUD (" .. keyname("NASK Abrir HUD") .. ")", hud_open)
		local on = cfg.d2d_on ~= false
		local ch, v = imgui.checkbox("Imagens do HUD (banner e fundo)", on)
		if ch then cfg.d2d_on = v; save_cfg() end
		if imgui.is_item_hovered() then
			imgui.set_tooltip("Desligue só se o HUD aparecer só com a imagem, sem botões nem abas,\ne o problema não for outro script com erro (ex.: MMDK desatualizado;\nveja em ScriptRunner).")
		end
		imgui.tree_pop()
	end
	end)
end)

re.on_script_reset(function()
	if NASK_FC then NASK_FC.block_mouse = false end
	if NASK_FC and NASK_FC.apply_ldr then pcall(NASK_FC.apply_ldr, false) end
end)
