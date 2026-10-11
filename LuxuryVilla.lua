--[[
	LUXURY VILLA BUILDER  -  Roblox Studio command bar script
	==========================================================
	Builds a modern two-storey villa with a fully furnished interior, a pool,
	terraces, a landscaped garden, a carport and a car (about 3,600 parts).

	HOW TO USE
	  1. Open any place in Roblox Studio (the Baseplate template is perfect).
	  2. Open the command bar: View tab > Command Bar.
	  3. Paste this entire script into the command bar and press Enter.

	The villa appears on the ground in front of your camera, facing you.
	  * Ctrl+Z undoes the whole build in one step.
	  * Running the script again rebuilds the villa in the same spot.
	  * Press Play, walk up to any door and press E to open it.
	  * Tip: set Lighting > Technology to "Future" and try an evening
	    ClockTime (see CONFIG.ClockTime) to see every lamp glow.
]]

local CONFIG = {
	BuildInFrontOfCamera = true, -- false = build at Position / RotationY below
	Position = Vector3.new(0, 0, 0), -- ground position of the lot centre
	RotationY = 0, -- degrees
	ReplacePrevious = true, -- running again replaces the old villa (same spot)
	Lights = true, -- lamps, downlights and garden lights
	InteractiveDoors = true, -- doors open with a prompt (E) when you press Play
	ClockTime = nil, -- e.g. 18.3 for a sunset glow; nil leaves your Lighting alone
	HouseNumber = "27",
	Name = "LuxuryVilla",
}

------------------------------------------------------------------------------------------
-- Shortcuts
------------------------------------------------------------------------------------------
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local PI, rad = math.pi, math.rad
local UPRIGHT = ANG(0, 0, PI / 2) -- turns a cylinder (axis = X) upright
-- Furniture faces its local -Z. These yaw angles turn it to face a world direction.
local TO_FRONT, TO_BACK, TO_WEST, TO_EAST = 0, PI, PI / 2, -PI / 2
local rng = Random.new(27)

-- Key heights (studs). The house sits on a podium so the pool can be sunk into it.
local GROUND = 0.5 -- top of the lawn
local Y1, C1 = 4.5, 16.5 -- ground floor: floor / ceiling
local Y2, C2 = 18.5, 29.5 -- upper floor: floor / ceiling
local RT = 31 -- top of the roof slab

------------------------------------------------------------------------------------------
-- Materials and styles
------------------------------------------------------------------------------------------
local function material(name, fallback)
	local ok, m = pcall(function()
		return Enum.Material[name]
	end)
	if ok and m then
		return m
	end
	return Enum.Material[fallback]
end

local MAT = {
	smooth = Enum.Material.SmoothPlastic,
	plaster = material("Plaster", "SmoothPlastic"),
	wood = Enum.Material.Wood,
	planks = Enum.Material.WoodPlanks,
	marble = Enum.Material.Marble,
	slate = Enum.Material.Slate,
	concrete = Enum.Material.Concrete,
	limestone = Enum.Material.Limestone,
	pavement = Enum.Material.Pavement,
	pebble = Enum.Material.Pebble,
	glass = Enum.Material.Glass,
	metal = Enum.Material.Metal,
	neon = Enum.Material.Neon,
	fabric = Enum.Material.Fabric,
	carpet = material("Carpet", "Fabric"),
	leather = material("Leather", "SmoothPlastic"),
	tiles = material("CeramicTiles", "Slate"),
	rubber = material("Rubber", "SmoothPlastic"),
	grass = Enum.Material.Grass,
	ground = Enum.Material.Ground,
}

-- A style is { color, material, transparency, reflectance }
local function S(color, mat, transparency, reflectance)
	return { color, mat or MAT.smooth, transparency or 0, reflectance or 0 }
end

local COL = {
	linen = RGB(220, 213, 200),
	cream = RGB(242, 236, 224),
	white = RGB(250, 250, 248),
	navy = RGB(40, 54, 82),
	teal = RGB(46, 108, 116),
	sage = RGB(146, 166, 134),
	mustard = RGB(214, 162, 62),
	terracotta = RGB(188, 104, 72),
	blush = RGB(222, 182, 168),
	charcoal = RGB(66, 68, 72),
	olive = RGB(112, 116, 74),
	burgundy = RGB(122, 44, 52),
	warmLight = RGB(255, 214, 168),
}

local ST = {
	extWhite = S(RGB(238, 236, 231), MAT.plaster),
	intWall = S(RGB(245, 242, 236), MAT.plaster),
	ceiling = S(RGB(250, 249, 246)),
	cedar = S(RGB(160, 108, 68), MAT.planks),
	stoneDark = S(RGB(92, 90, 88), MAT.slate),
	stoneLight = S(RGB(224, 216, 202), MAT.limestone),
	coping = S(RGB(242, 238, 230)),
	frame = S(RGB(40, 42, 46)),
	glass = S(RGB(178, 208, 224), MAT.glass, 0.6, 0.05),
	frosted = S(RGB(232, 238, 240), MAT.glass, 0.2),
	foundation = S(RGB(74, 74, 76), MAT.concrete),
	floorOak = S(RGB(198, 162, 120), MAT.planks),
	floorStone = S(RGB(228, 224, 216), MAT.marble),
	floorTile = S(RGB(120, 120, 122), MAT.tiles),
	deck = S(RGB(142, 100, 66), MAT.planks),
	lawn = S(RGB(98, 148, 66), MAT.grass),
	soil = S(RGB(80, 60, 44), MAT.ground),
	pavement = S(RGB(172, 170, 164), MAT.pavement),
	gravel = S(RGB(198, 192, 182), MAT.pebble),
	hedge = S(RGB(54, 100, 52), MAT.grass),
	trunk = S(RGB(104, 78, 58), MAT.wood),
	blackMetal = S(RGB(30, 30, 33), MAT.metal),
	steel = S(RGB(188, 192, 196), MAT.metal, 0, 0.1),
	brass = S(RGB(200, 162, 92), MAT.metal, 0, 0.15),
	walnut = S(RGB(104, 70, 48), MAT.wood),
	oak = S(RGB(196, 158, 114), MAT.wood),
	teak = S(RGB(152, 106, 66), MAT.wood),
	ceramic = S(RGB(250, 250, 248), MAT.smooth, 0, 0.06),
	marbleTop = S(RGB(242, 240, 236), MAT.marble),
	cabinet = S(RGB(58, 74, 66)),
	carcass = S(RGB(36, 42, 40)),
	plinth = S(RGB(24, 24, 26)),
	blackGloss = S(RGB(16, 16, 18), MAT.smooth, 0, 0.2),
	lamp = S(RGB(255, 236, 210), MAT.neon),
	water = S(RGB(72, 174, 214), MAT.glass, 0.4, 0.1),
	bathWater = S(RGB(170, 214, 228), MAT.glass, 0.35, 0.1),
	poolTile = S(RGB(140, 206, 224), MAT.tiles),
	doorWood = S(RGB(122, 86, 58), MAT.wood),
	trim = S(RGB(247, 245, 241)),
	mirror = S(RGB(206, 214, 220), MAT.smooth, 0, 0.6),
	black = S(RGB(20, 20, 22)),
	white = S(RGB(250, 250, 250)),
	rubber = S(RGB(28, 28, 30), MAT.rubber),
}

------------------------------------------------------------------------------------------
-- Part helpers. All coordinates are in "house space" (front of the house = -Z) and are
-- converted to world space through ORIGIN when each part is created.
------------------------------------------------------------------------------------------
local ORIGIN = CF()
local partCount = 0
local pivots = {}

local function make(class, parent, size, cf, st, name)
	local p = Instance.new(class)
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = ORIGIN * cf
	p.Color = st[1]
	p.Material = st[2]
	p.Transparency = st[3]
	p.Reflectance = st[4]
	if st[3] > 0 or st[2] == MAT.neon then
		p.CastShadow = false
	end
	if name then
		p.Name = name
	end
	p.Parent = parent
	partCount += 1
	return p
end

local function box(parent, size, cf, st, name)
	return make("Part", parent, size, cf, st, name)
end

local function cyl(parent, length, diameter, cf, st, name) -- axis = local X of cf
	local p = make("Part", parent, V3(length, diameter, diameter), cf, st, name)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function vcyl(parent, height, diameter, cf, st, name) -- upright cylinder centred on cf
	return cyl(parent, height, diameter, cf * UPRIGHT, st, name)
end

local function ball(parent, diameter, cf, st, name)
	local p = make("Part", parent, V3(diameter, diameter, diameter), cf, st, name)
	p.Shape = Enum.PartType.Ball
	return p
end

local function wedge(parent, size, cf, st, name)
	return make("WedgePart", parent, size, cf, st, name)
end

local function seat(parent, size, cf, st)
	return make("Seat", parent, size, cf, st, "Seat")
end

-- Box spanning world-axis ranges (house space)
local function rect(parent, x1, x2, z1, z2, y1, y2, st, name)
	if x2 - x1 < 0.01 or z2 - z1 < 0.01 or y2 - y1 < 0.01 then
		return nil
	end
	return box(parent, V3(x2 - x1, y2 - y1, z2 - z1), CF((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), st, name)
end

-- Rectangle with a rectangular hole (4 boxes)
local function rectHole(parent, x1, x2, z1, z2, y1, y2, st, hx1, hx2, hz1, hz2, name)
	rect(parent, x1, x2, z1, hz1, y1, y2, st, name)
	rect(parent, x1, x2, hz2, z2, y1, y2, st, name)
	rect(parent, x1, hx1, hz1, hz2, y1, y2, st, name)
	rect(parent, hx2, x2, hz1, hz2, y1, y2, st, name)
end

-- Box spanning ranges in the local space of cf
local function lbox(parent, cf, x1, x2, y1, y2, z1, z2, st, name)
	return box(parent, V3(x2 - x1, y2 - y1, z2 - z1), cf * CF((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), st, name)
end

local function at(cf, x, y, z)
	return cf * CF(x, y, z)
end

-- A named Model. When cf is given it becomes the model's pivot (set after the build).
local function item(parent, name, cf)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	if cf then
		table.insert(pivots, { m, cf })
	end
	return m
end

local function addLight(class, part, o)
	if not CONFIG.Lights then
		return nil
	end
	local l = Instance.new(class)
	l.Color = o.color or COL.warmLight
	l.Brightness = o.brightness or 1
	l.Range = o.range or 12
	l.Shadows = o.shadows or false
	if o.face then
		l.Face = o.face
	end
	if o.angle then
		l.Angle = o.angle
	end
	l.Parent = part
	return l
end

-- Recessed ceiling downlight. The disc is an upright cylinder, so its local -X face
-- (NormalId.Left) points straight down.
local function downlight(parent, x, z, yCeil, range, brightness)
	local disc = vcyl(parent, 0.12, 0.9, CF(x, yCeil - 0.06, z), ST.lamp, "Downlight")
	addLight("SpotLight", disc, { face = Enum.NormalId.Left, angle = 110, range = range or 16, brightness = brightness or 1.1 })
	return disc
end

------------------------------------------------------------------------------------------
-- Walls, windows and doors.
-- Walls are axis aligned. axis "x" = wall runs along X at Z = c, axis "z" = runs along Z
-- at X = c. "s" is the coordinate along the wall, "n" an offset across it.
------------------------------------------------------------------------------------------
local function ap(parent, axis, c, s1, s2, y1, y2, n, d, st, name)
	local len, h = s2 - s1, y2 - y1
	if len < 0.01 or h < 0.01 then
		return nil
	end
	local s, y = (s1 + s2) / 2, (y1 + y2) / 2
	if axis == "x" then
		return box(parent, V3(len, h, d), CF(s, y, c + n), st, name)
	end
	return box(parent, V3(d, h, len), CF(c + n, y, s), st, name)
end

-- Solid wall from s=a..b, y1..y2, thickness t, with rectangular holes {s1, s2, y1, y2}
local function wall(parent, axis, c, a, b, y1, y2, t, st, holes, name)
	local list = {}
	for _, o in ipairs(holes or {}) do
		local s1, s2 = math.max(o[1], a), math.min(o[2], b)
		if s2 > s1 then
			table.insert(list, { s1, s2, math.max(o[3], y1), math.min(o[4], y2) })
		end
	end
	table.sort(list, function(u, v)
		return u[1] < v[1]
	end)
	local cur = a
	for _, o in ipairs(list) do
		ap(parent, axis, c, cur, o[1], y1, y2, 0, t, st, name)
		ap(parent, axis, c, o[1], o[2], y1, o[3], 0, t, st, name)
		ap(parent, axis, c, o[1], o[2], o[4], y2, 0, t, st, name)
		cur = o[2]
	end
	ap(parent, axis, c, cur, b, y1, y2, 0, t, st, name)
end

-- Framed glazing that fills an opening. c = wall centre line.
local function glazing(parent, axis, c, a, b, y1, y2, o)
	o = o or {}
	local fw, fd = o.fw or 0.3, o.fd or 0.5
	local fr, gl = o.frame or ST.frame, o.glass or ST.glass
	local panes = o.panes or math.max(1, math.floor((b - a) / 6 + 0.5))
	ap(parent, axis, c, a, b, y2 - fw, y2, 0, fd, fr, "Frame")
	ap(parent, axis, c, a, b, y1, y1 + fw, 0, fd, fr, "Frame")
	ap(parent, axis, c, a, a + fw, y1 + fw, y2 - fw, 0, fd, fr, "Frame")
	ap(parent, axis, c, b - fw, b, y1 + fw, y2 - fw, 0, fd, fr, "Frame")
	local w = (b - a - 2 * fw) / panes
	for i = 1, panes - 1 do
		local s = a + fw + w * i
		ap(parent, axis, c, s - fw / 2, s + fw / 2, y1 + fw, y2 - fw, 0, fd * 0.8, fr, "Mullion")
	end
	ap(parent, axis, c, a + fw, b - fw, y1 + fw, y2 - fw, 0, 0.12, gl, "Glass")
	if o.sill then -- o.sill = +1/-1, the exterior side
		ap(parent, axis, c, a - 0.15, b + 0.15, y1 - 0.2, y1 + 0.05, o.sill * 0.55, 0.5, ST.coping, "Sill")
	end
end

-- Registers a model as an interactive door for the door script.
local function makeDoor(model, root, label, attrs)
	model.PrimaryPart = root
	model:SetAttribute("Door", true)
	model:SetAttribute("Label", label)
	for k, v in pairs(attrs) do
		model:SetAttribute(k, v)
	end
end

-- Hinged interior door with casings and lever handles.
-- hinge = "a" or "b" (which end of the opening), swing = +1/-1 (side it opens toward).
local function casedOpening(parent, axis, c, a, b, y, h, t)
	for _, side in ipairs({ -1, 1 }) do
		local n = side * (t / 2 + 0.05)
		ap(parent, axis, c, a - 0.35, a, y, y + h + 0.35, n, 0.1, ST.trim, "Casing")
		ap(parent, axis, c, b, b + 0.35, y, y + h + 0.35, n, 0.1, ST.trim, "Casing")
		ap(parent, axis, c, a, b, y + h, y + h + 0.35, n, 0.1, ST.trim, "Casing")
	end
end

local function door(parent, axis, c, a, b, y, h, t, hinge, swing, label)
	casedOpening(parent, axis, c, a, b, y, h, t) -- the frame stays put
	local g = item(parent, label .. " Door") -- only the leaf and its handles swing
	local leaf = ap(g, axis, c, a + 0.05, b - 0.05, y + 0.03, y + h - 0.05, 0, 0.25, ST.doorWood, "Leaf")
	local hs = hinge == "a" and (b - 0.55) or (a + 0.55)
	for _, side in ipairs({ -1, 1 }) do
		local lever = hinge == "a" and -1 or 1 -- lever points back toward the hinge
		ap(g, axis, c, hs - 0.08, hs + 0.08, y + 3.35, y + 3.55, side * 0.2, 0.15, ST.brass, "Rose")
		local h1, h2 = hs, hs + lever * 0.6
		if h1 > h2 then
			h1, h2 = h2, h1
		end
		ap(g, axis, c, h1, h2, y + 3.4, y + 3.5, side * 0.3, 0.1, ST.brass, "Handle")
	end
	if CONFIG.InteractiveDoors then
		local half = (b - a - 0.1) / 2
		local hingeSign = hinge == "a" and -1 or 1
		local offset = axis == "x" and V3(hingeSign * half, 0, 0) or V3(0, 0, hingeSign * half)
		local sign = (axis == "x" and -1 or 1) * (hinge == "a" and 1 or -1) * swing
		makeDoor(g, leaf, label, { HingeOffset = offset, OpenAngle = 90 * sign })
	end
	return g
end

-- Glass sliding doors filling an opening: "F" = fixed panel, "<" / ">" = slides toward a / b
local function slidingDoors(parent, axis, c, a, b, y1, y2, pattern, label)
	local fw = 0.3
	ap(parent, axis, c, a, b, y2 - fw, y2, 0, 0.6, ST.frame, "Track")
	ap(parent, axis, c, a, b, y1, y1 + 0.12, 0, 0.6, ST.frame, "Track")
	ap(parent, axis, c, a, a + fw, y1, y2, 0, 0.6, ST.frame, "Frame")
	ap(parent, axis, c, b - fw, b, y1, y2, 0, 0.6, ST.frame, "Frame")
	local n = string.len(pattern)
	local w = (b - a - 2 * fw) / n
	for i = 1, n do
		local kind = pattern:sub(i, i)
		local s1, s2 = a + fw + w * (i - 1) - 0.1, a + fw + w * i + 0.1
		local nOff = kind == "F" and -0.14 or 0.14
		local g = kind == "F" and parent or item(parent, label)
		local py1, py2 = y1 + 0.12, y2 - fw
		ap(g, axis, c, s1, s2, py2 - 0.22, py2, nOff, 0.18, ST.frame, "PanelFrame")
		ap(g, axis, c, s1, s2, py1, py1 + 0.3, nOff, 0.18, ST.frame, "PanelFrame")
		ap(g, axis, c, s1, s1 + 0.22, py1, py2, nOff, 0.18, ST.frame, "PanelFrame")
		ap(g, axis, c, s2 - 0.22, s2, py1, py2, nOff, 0.18, ST.frame, "PanelFrame")
		local pane = ap(g, axis, c, s1 + 0.22, s2 - 0.22, py1 + 0.3, py2 - 0.22, nOff, 0.08, ST.glass, "Glass")
		if kind ~= "F" then
			local dir = kind == "<" and -1 or 1
			local hx = dir < 0 and (s2 - 0.45) or (s1 + 0.45)
			for _, side in ipairs({ -1, 1 }) do
				ap(g, axis, c, hx - 0.06, hx + 0.06, y1 + 3, y1 + 5.5, nOff + side * 0.17, 0.08, ST.blackMetal, "Handle")
			end
			if CONFIG.InteractiveDoors then
				local d = dir * (w - 0.3)
				makeDoor(g, pane, label, { SlideOffset = axis == "x" and V3(d, 0, 0) or V3(0, 0, d) })
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- SurfaceGui artwork: paintings, TV and monitor screens, signs.
------------------------------------------------------------------------------------------
local function surfaceGui(part, face, glow)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = glow and 0 or 1
	sg.Brightness = glow and 1.4 or 1
	sg.Parent = part
	return sg
end

-- Frame centred at (cx, cy) with size (w, h), all as fractions of the canvas
local function shape(parent, cx, cy, w, h, color, o)
	o = o or {}
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = o.alpha or 0
	f.BorderSizePixel = 0
	f.Rotation = o.rot or 0
	f.ZIndex = o.z or 1
	if o.round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(o.round, 0)
		c.Parent = f
	end
	if o.grad then
		local kps = {}
		for i, col in ipairs(o.grad) do
			kps[i] = ColorSequenceKeypoint.new((i - 1) / (#o.grad - 1), col)
		end
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(kps)
		g.Rotation = o.gradRot or 90
		g.Parent = f
	end
	f.Parent = parent
	return f
end

local function label(parent, text, color, fontName)
	local ok, font = pcall(function()
		return Enum.Font[fontName or "GothamBold"]
	end)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	t.Font = ok and font or Enum.Font.SourceSansBold
	t.Parent = parent
	return t
end

-- aspect = canvas width / height. Circle sizes are given relative to the canvas height.
local function drawTheme(part, face, aspect, theme, glow)
	local sg = surfaceGui(part, face, glow)
	local z = 0
	local function sh(cx, cy, w, h, col, o)
		o = o or {}
		z += 1
		o.z = z
		return shape(sg, cx, cy, w, h, col, o)
	end
	local function circle(cx, cy, d, col, o)
		o = o or {}
		o.round = 0.5
		return sh(cx, cy, d / aspect, d, col, o)
	end
	local function peak(cx, base, size, col) -- a rotated square that reads as a mountain
		return sh(cx, base, size / aspect, size, col, { rot = 45 })
	end
	if theme == "sunset" then
		sh(0.5, 0.5, 1, 1, Color3.new(1, 1, 1), { grad = { RGB(52, 60, 118), RGB(184, 98, 128), RGB(246, 164, 100), RGB(252, 220, 160) } })
		circle(0.63, 0.56, 0.26, RGB(255, 238, 200))
		peak(0.22, 0.98, 0.62, RGB(128, 86, 118))
		peak(0.78, 1.02, 0.7, RGB(118, 80, 112))
		peak(0.02, 1.0, 0.5, RGB(76, 54, 86))
		peak(0.46, 1.08, 0.56, RGB(70, 50, 82))
		sh(0.5, 0.89, 1, 0.22, Color3.new(1, 1, 1), { grad = { RGB(150, 112, 150), RGB(60, 56, 98) } })
		for i, w in ipairs({ 0.22, 0.15, 0.09 }) do
			sh(0.63, 0.8 + i * 0.04, w, 0.012, RGB(255, 228, 190), { alpha = 0.25, round = 0.5 })
		end
	elseif theme == "abstract" then
		sh(0.5, 0.5, 1, 1, RGB(243, 235, 220))
		circle(0.34, 0.42, 0.62, RGB(196, 108, 76))
		sh(0.7, 0.6, 0.2, 0.62, RGB(40, 54, 82), { round = 0.5 })
		sh(0.7, 0.8, 0.2, 0.3, RGB(40, 54, 82))
		circle(0.5, 1.0, 0.42, RGB(220, 168, 70))
		circle(0.84, 0.2, 0.14, RGB(146, 166, 134))
		sh(0.42, 0.86, 0.62, 0.008, RGB(30, 30, 30))
	elseif theme == "ocean" then
		sh(0.5, 0.5, 1, 1, Color3.new(1, 1, 1), { grad = { RGB(186, 214, 230), RGB(244, 238, 226) } })
		circle(0.28, 0.3, 0.16, RGB(252, 236, 206))
		sh(0.5, 0.8, 1, 0.42, Color3.new(1, 1, 1), { grad = { RGB(60, 112, 150), RGB(26, 58, 92) } })
		for _, w in ipairs({ { 0.3, 0.66, 0.3 }, { 0.72, 0.74, 0.36 }, { 0.42, 0.86, 0.42 }, { 0.8, 0.93, 0.28 } }) do
			sh(w[1], w[2], w[3], 0.018, RGB(240, 246, 250), { alpha = 0.3, round = 0.5 })
		end
		peak(0.7, 0.6, 0.05, RGB(250, 250, 250))
	elseif theme == "botanical" then
		sh(0.5, 0.5, 1, 1, RGB(238, 233, 222))
		circle(0.7, 0.32, 0.3, RGB(214, 170, 140))
		local leaves = { { 0.36, 0.5, -28, RGB(64, 100, 72) }, { 0.52, 0.45, 4, RGB(96, 132, 94) }, { 0.66, 0.56, 30, RGB(140, 160, 118) } }
		for _, l in ipairs(leaves) do
			sh(l[1], l[2], 0.16 / aspect * 1.6, 0.56, l[4], { rot = l[3], round = 0.5 })
		end
		sh(0.5, 0.86, 0.006, 0.3, RGB(60, 80, 60))
	elseif theme == "arches" then
		sh(0.5, 0.5, 1, 1, RGB(240, 228, 210))
		circle(0.74, 0.22, 0.16, RGB(214, 150, 92))
		local arches = { { 0.78, RGB(190, 104, 72) }, { 0.58, RGB(226, 176, 150) }, { 0.38, RGB(246, 236, 222) }, { 0.18, RGB(110, 120, 96) } }
		for _, a in ipairs(arches) do
			local w = a[1] / aspect
			sh(0.5, 1 - a[1] * 0.55, w, a[1] * 1.1, a[2], { round = 0.5 })
			sh(0.5, 1 - a[1] * 0.25, w, a[1] * 0.5, a[2])
		end
		sh(0.5, 0.985, 1, 0.03, RGB(70, 60, 50))
	elseif theme == "code" then
		sh(0.5, 0.5, 1, 1, RGB(28, 30, 38))
		sh(0.5, 0.04, 1, 0.08, RGB(44, 47, 58))
		local palette = { RGB(198, 120, 221), RGB(97, 175, 239), RGB(152, 195, 121), RGB(229, 192, 123), RGB(171, 178, 191), RGB(224, 108, 117) }
		for row = 1, 11 do
			local x = 0.06 + (row % 3 == 0 and 0.06 or 0) + (row % 5 == 0 and 0.06 or 0)
			for _ = 1, rng:NextInteger(1, 4) do
				local w = rng:NextNumber(0.05, 0.2)
				if x + w > 0.95 then
					break
				end
				sh(x + w / 2, 0.1 + row * 0.075, w, 0.03, palette[rng:NextInteger(1, #palette)], { round = 0.5 })
				x += w + 0.02
			end
		end
	elseif theme == "clock" then
		circle(0.5, 0.5, 0.98, RGB(250, 250, 248))
		for i = 0, 11 do
			local a = i * PI / 6
			local len = i % 3 == 0 and 0.1 or 0.05
			sh(0.5 + math.sin(a) * 0.4 / aspect, 0.5 - math.cos(a) * 0.4, 0.015, len, RGB(30, 30, 30), { rot = math.deg(a) })
		end
		sh(0.5 + math.sin(rad(300)) * 0.12, 0.5 - math.cos(rad(300)) * 0.12, 0.02, 0.26, RGB(30, 30, 30), { rot = 300 })
		sh(0.5 + math.sin(rad(60)) * 0.18, 0.5 - math.cos(rad(60)) * 0.18, 0.012, 0.38, RGB(30, 30, 30), { rot = 60 })
		circle(0.5, 0.5, 0.04, RGB(196, 108, 76))
	end
	return sg
end

------------------------------------------------------------------------------------------
-- Furniture. Every piece takes cf = centre of its footprint on the floor, facing local -Z,
-- and becomes its own Model so it can be moved around in Studio afterwards.
------------------------------------------------------------------------------------------
local F = {}

function F.sofa(parent, cf, L, o)
	o = o or {}
	local m = item(parent, o.name or "Sofa", cf)
	local fab = S(o.color or COL.linen, MAT.fabric)
	local D = 3.4
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			box(m, V3(0.3, 0.4, 0.3), at(cf, sx * (L / 2 - 0.45), 0.2, sz * (D / 2 - 0.45)), ST.blackMetal, "Leg")
		end
	end
	box(m, V3(L, 0.9, D), at(cf, 0, 0.85, 0), fab, "Base")
	box(m, V3(L, 1.9, 0.6), at(cf, 0, 2.25, D / 2 - 0.3), fab, "Back")
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.7, 1.0, D), at(cf, sx * (L / 2 - 0.35), 1.8, 0), fab, "Arm")
	end
	local inner = L - 1.4
	local n = math.max(1, math.floor(inner / 3.2 + 0.5))
	local w = inner / n
	for i = 1, n do
		local x = -inner / 2 + w * (i - 0.5)
		seat(m, V3(w - 0.08, 0.5, 2.6), at(cf, x, 1.55, -0.4), fab)
		box(m, V3(w - 0.12, 1.5, 0.55), at(cf, x, 2.4, 0.72) * ANG(rad(10), 0, 0), fab, "BackCushion")
	end
	if o.chaise then -- +1 = chaise at the local +X end, -1 = at the -X end
		local s = o.chaise
		local cz = -D / 2 - 1.6
		box(m, V3(3.2, 0.9, 3.2), at(cf, s * (L / 2 - 1.6), 0.85, cz), fab, "ChaiseBase")
		seat(m, V3(2.45, 0.5, 3.2), at(cf, s * (L / 2 - 1.95), 1.55, cz), fab)
		box(m, V3(0.7, 1.0, 3.2), at(cf, s * (L / 2 - 0.35), 1.8, cz), fab, "Arm")
		for _, x in ipairs({ L / 2 - 0.45, L / 2 - 2.75 }) do
			box(m, V3(0.3, 0.4, 0.3), at(cf, s * x, 0.2, -D / 2 - 2.75), ST.blackMetal, "Leg")
		end
	end
	local pc = o.pillows or { COL.mustard, COL.teal }
	for i, sx in ipairs({ -1, 1 }) do
		local c = pc[(i - 1) % #pc + 1]
		box(m, V3(1.5, 1.5, 0.45), at(cf, sx * (L / 2 - 1.6), 2.45, 0.3) * ANG(rad(12), sx * rad(-12), sx * rad(8)), S(c, MAT.fabric), "Pillow")
	end
	if o.throw then
		box(m, V3(1.8, 0.14, 2.7), at(cf, L / 2 - 2.6, 1.85, -0.35) * ANG(0, rad(6), 0), S(o.throw, MAT.fabric), "Throw")
	end
	return m
end

function F.armchair(parent, cf, color, pillow)
	return F.sofa(parent, cf, 4.2, { name = "Armchair", color = color, pillows = { pillow or COL.cream } })
end

function F.rug(parent, cf, w, d, main, border)
	local m = item(parent, "Rug", cf)
	box(m, V3(w, 0.05, d), at(cf, 0, 0.025, 0), S(border or COL.cream, MAT.carpet), "Rug")
	box(m, V3(w - 0.9, 0.06, d - 0.9), at(cf, 0, 0.03, 0), S(main or COL.linen, MAT.carpet), "Rug")
	return m
end

function F.vase(parent, cf, h, color, flowers)
	vcyl(parent, h, 0.55, at(cf, 0, h / 2, 0), S(color or COL.white, MAT.smooth, 0, 0.05), "Vase")
	for i = 1, 5 do
		local a = i * 1.26
		local stem = at(cf, 0, h, 0) * ANG(math.cos(a) * 0.35, 0, math.sin(a) * 0.35)
		box(parent, V3(0.05, 1.3, 0.05), stem * CF(0, 0.6, 0), S(RGB(76, 110, 60)), "Stem")
		if flowers then
			ball(parent, 0.4, stem * CF(0, 1.25, 0), S(flowers[(i - 1) % #flowers + 1]), "Flower")
		else
			box(parent, V3(0.35, 0.6, 0.06), stem * CF(0, 1.2, 0), S(RGB(90, 128, 70)), "Leaf")
		end
	end
end

function F.books(parent, cf, n)
	local y = 0
	local palette = { COL.navy, COL.terracotta, COL.cream, COL.sage, COL.charcoal, COL.mustard }
	for i = 1, n do
		local h = rng:NextNumber(0.12, 0.2)
		box(parent, V3(rng:NextNumber(1.1, 1.5), h, rng:NextNumber(0.8, 1.0)), at(cf, 0, y + h / 2, 0) * ANG(0, rng:NextNumber(-0.25, 0.25), 0), S(palette[rng:NextInteger(1, #palette)]), "Book")
		y += h
	end
end

function F.coffeeTable(parent, cf)
	local m = item(parent, "Coffee Table", cf)
	box(m, V3(6, 0.3, 3.2), at(cf, 0, 1.35, 0), ST.marbleTop, "Top")
	for _, x in ipairs({ -2.2, 2.2 }) do
		box(m, V3(0.5, 1.2, 2.6), at(cf, x, 0.6, 0), ST.walnut, "Leg")
	end
	box(m, V3(3.9, 0.2, 2.4), at(cf, 0, 0.35, 0), ST.walnut, "Shelf")
	F.books(m, at(cf, -1.6, 1.5, 0.2), 3)
	vcyl(m, 0.3, 1.6, at(cf, 1.3, 1.65, -0.3), ST.blackGloss, "Bowl")
	for i, c in ipairs({ RGB(240, 150, 40), RGB(120, 170, 60), RGB(200, 40, 40) }) do
		ball(m, 0.5, at(cf, 1.3 + math.cos(i * 2.1) * 0.3, 1.95, -0.3 + math.sin(i * 2.1) * 0.3), S(c), "Fruit")
	end
	F.vase(m, at(cf, 0.2, 1.5, 0.6), 0.9, COL.white, { RGB(250, 250, 250), RGB(240, 200, 210) })
	F.books(m, at(cf, 0, 0.45, 0), 2)
	return m
end

function F.sideTable(parent, cf, withLamp)
	local m = item(parent, "Side Table", cf)
	vcyl(m, 0.12, 1.4, at(cf, 0, 0.06, 0), ST.brass, "Base")
	vcyl(m, 1.9, 0.16, at(cf, 0, 1.0, 0), ST.brass, "Stem")
	vcyl(m, 0.15, 2.0, at(cf, 0, 2.0, 0), ST.marbleTop, "Top")
	if withLamp then
		F.tableLamp(m, at(cf, 0, 2.075, 0))
	else
		F.vase(m, at(cf, 0.3, 2.075, 0), 0.7, COL.terracotta)
	end
	return m
end

function F.tableLamp(parent, cf, base)
	local m = item(parent, "Table Lamp", cf)
	vcyl(m, 0.08, 0.7, at(cf, 0, 0.04, 0), ST.brass, "Base")
	ball(m, 0.75, at(cf, 0, 0.45, 0), S(base or RGB(216, 198, 172)), "Body")
	vcyl(m, 0.5, 0.08, at(cf, 0, 1.0, 0), ST.brass, "Stem")
	local shade = vcyl(m, 0.8, 1.3, at(cf, 0, 1.55, 0), S(RGB(246, 238, 222), MAT.fabric), "Shade")
	addLight("PointLight", shade, { range = 10, brightness = 0.7 })
	return m
end

function F.floorLamp(parent, cf)
	local m = item(parent, "Floor Lamp", cf)
	vcyl(m, 0.15, 1.4, at(cf, 0, 0.075, 0), ST.blackMetal, "Base")
	vcyl(m, 5.6, 0.14, at(cf, 0, 2.9, 0), ST.brass, "Pole")
	vcyl(m, 1.3, 1.9, at(cf, 0, 6.2, 0), S(RGB(246, 238, 222), MAT.fabric), "Shade")
	local glow = vcyl(m, 0.05, 1.7, at(cf, 0, 5.53, 0), ST.lamp, "Glow")
	addLight("PointLight", glow, { range = 14, brightness = 0.9 })
	return m
end

-- Potted plant. kind = "fig" | "snake" | "monstera" | "olive"
function F.plant(parent, cf, kind, s)
	s = s or 1
	local m = item(parent, "Plant", cf)
	local pots = { RGB(188, 104, 72), RGB(244, 242, 236), RGB(52, 52, 56), RGB(196, 184, 166) }
	local potH, potD = 1.6 * s, 1.7 * s
	vcyl(m, potH, potD, at(cf, 0, potH / 2, 0), S(pots[rng:NextInteger(1, #pots)]), "Pot")
	vcyl(m, 0.1, potD - 0.2 * s, at(cf, 0, potH - 0.03, 0), ST.soil, "Soil")
	local greens = { RGB(62, 112, 58), RGB(78, 128, 64), RGB(52, 96, 54), RGB(92, 140, 72) }
	local function green()
		return S(greens[rng:NextInteger(1, #greens)])
	end
	if kind == "snake" then
		for i = 1, 9 do
			local a = i * 2.39
			local h = rng:NextNumber(1.6, 2.8) * s
			local r = rng:NextNumber(0.1, 0.45) * s
			box(m, V3(0.35 * s, h, 0.08), at(cf, math.cos(a) * r, potH + h / 2, math.sin(a) * r) * ANG(rng:NextNumber(-0.15, 0.15), a, rng:NextNumber(-0.12, 0.12)), S(RGB(54, 92, 58)), "Leaf")
		end
	elseif kind == "monstera" then
		for i = 1, 8 do
			local a = i * 2.3
			local lean = rng:NextNumber(0.35, 0.9)
			local len = rng:NextNumber(1.4, 2.6) * s
			local base = at(cf, 0, potH, 0) * ANG(0, a, 0) * ANG(0, 0, -lean)
			box(m, V3(0.08, len, 0.08), base * CF(0, len / 2, 0), S(RGB(70, 110, 56)), "Stem")
			cyl(m, 0.06, rng:NextNumber(1.4, 2.0) * s, base * CF(0.2, len, 0) * ANG(0, 0, lean * 0.6 + 0.9), green(), "Leaf")
		end
	else
		local trunkH = (kind == "olive" and 3.4 or 3.0) * s
		vcyl(m, trunkH, 0.18 * s, at(cf, 0, potH + trunkH / 2, 0), ST.trunk, "Trunk")
		local leafCol = kind == "olive" and RGB(132, 150, 110) or nil
		for i = 1, 8 do
			local a = i * 2.4
			local r = rng:NextNumber(0.3, 0.8) * s
			local y = potH + trunkH * rng:NextNumber(0.6, 1.1)
			ball(m, rng:NextNumber(1.0, 1.5) * s, at(cf, math.cos(a) * r, y, math.sin(a) * r), leafCol and S(leafCol) or green(), "Leaves")
		end
	end
	return m
end

function F.bookshelf(parent, cf, w, h, frame)
	local m = item(parent, "Bookshelf", cf)
	frame = frame or ST.walnut
	local d = 1.4
	box(m, V3(w, h, 0.1), at(cf, 0, h / 2, d / 2 - 0.05), frame, "Back")
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.2, h, d), at(cf, sx * (w / 2 - 0.1), h / 2, 0), frame, "Side")
	end
	local shelves = math.max(2, math.floor(h / 2.2))
	local gap = (h - 0.2) / shelves
	for i = 0, shelves do
		box(m, V3(w - 0.4, 0.15, d - 0.1), at(cf, 0, 0.075 + i * gap, 0.05), frame, "Shelf")
	end
	local palette = { COL.navy, COL.terracotta, COL.mustard, COL.sage, COL.cream, COL.charcoal, COL.burgundy, COL.teal, RGB(196, 180, 150) }
	for i = 0, shelves - 1 do
		local y0 = 0.15 + i * gap
		local x = -w / 2 + 0.3
		while x < w / 2 - 0.8 do
			if rng:NextNumber() < 0.18 then
				if rng:NextNumber() < 0.5 then
					vcyl(m, gap * 0.45, 0.5, at(cf, x + 0.4, y0 + gap * 0.225, 0), S(palette[rng:NextInteger(1, #palette)], MAT.smooth, 0, 0.05), "Vase")
				else
					ball(m, 0.6, at(cf, x + 0.4, y0 + 0.3, 0), S(RGB(70, 120, 60)), "Plant")
				end
				x += 1.0
			else
				for _ = 1, rng:NextInteger(3, 8) do
					local bw = rng:NextNumber(0.16, 0.3)
					local bh = rng:NextNumber(gap * 0.55, gap * 0.8)
					if x + bw > w / 2 - 0.3 then
						break
					end
					box(m, V3(bw, bh, d * 0.7), at(cf, x + bw / 2, y0 + bh / 2, -0.05), S(palette[rng:NextInteger(1, #palette)]), "Book")
					x += bw + 0.01
				end
				x += rng:NextNumber(0.3, 0.9)
			end
		end
	end
	return m
end

-- Framed painting. cf = centre of the canvas, the front faces local -Z.
function F.art(parent, cf, w, h, theme, frameSt)
	local m = item(parent, "Painting", cf)
	local canvas = box(m, V3(w, h, 0.1), cf, S(RGB(245, 242, 235)), "Canvas")
	local t = 0.18
	frameSt = frameSt or ST.black
	box(m, V3(w + 2 * t, t, 0.25), at(cf, 0, h / 2 + t / 2, -0.03), frameSt, "Frame")
	box(m, V3(w + 2 * t, t, 0.25), at(cf, 0, -h / 2 - t / 2, -0.03), frameSt, "Frame")
	box(m, V3(t, h, 0.25), at(cf, -w / 2 - t / 2, 0, -0.03), frameSt, "Frame")
	box(m, V3(t, h, 0.25), at(cf, w / 2 + t / 2, 0, -0.03), frameSt, "Frame")
	drawTheme(canvas, Enum.NormalId.Front, w / h, theme, false)
	return m
end

function F.tv(parent, cf, w)
	local m = item(parent, "TV", cf)
	local h = w * 9 / 16
	local screen = box(m, V3(w, h, 0.25), cf, ST.blackGloss, "Screen")
	drawTheme(screen, Enum.NormalId.Front, w / h, "sunset", true)
	box(m, V3(w * 0.6, 0.35, 0.5), at(cf, 0, -h / 2 - 0.7, -0.1), ST.black, "Soundbar")
	return m
end

function F.pendant(parent, x, z, yCeil, drop, kind)
	local m = item(parent, "Pendant Light", CF(x, yCeil, z))
	vcyl(m, 0.1, 0.5, CF(x, yCeil - 0.05, z), ST.blackMetal, "Canopy")
	vcyl(m, drop, 0.05, CF(x, yCeil - drop / 2, z), ST.black, "Cord")
	local y = yCeil - drop
	if kind == "globe" then
		local g = ball(m, 1.3, CF(x, y - 0.6, z), ST.lamp, "Globe")
		addLight("PointLight", g, { range = 14, brightness = 0.9 })
	else
		vcyl(m, 0.25, 0.6, CF(x, y - 0.12, z), ST.brass, "Cap")
		vcyl(m, 0.7, 1.6, CF(x, y - 0.6, z), ST.brass, "Shade")
		local bulb = ball(m, 0.55, CF(x, y - 0.95, z), ST.lamp, "Bulb")
		addLight("PointLight", bulb, { range = 14, brightness = 0.9 })
	end
	return m
end

function F.linearPendant(parent, x, z, yCeil, drop, len)
	local m = item(parent, "Linear Pendant", CF(x, yCeil, z))
	for _, dx in ipairs({ -len / 2 + 0.6, len / 2 - 0.6 }) do
		vcyl(m, drop, 0.04, CF(x + dx, yCeil - drop / 2, z), ST.black, "Cable")
	end
	local y = yCeil - drop
	box(m, V3(len, 0.35, 0.6), CF(x, y - 0.175, z), ST.brass, "Body")
	local strip = box(m, V3(len - 0.3, 0.06, 0.4), CF(x, y - 0.37, z), ST.lamp, "LED")
	addLight("SurfaceLight", strip, { face = Enum.NormalId.Bottom, angle = 120, range = 14, brightness = 1.2 })
	return m
end

function F.chair(parent, cf, o)
	o = o or {}
	local m = item(parent, "Chair", cf)
	local frame = o.frame or ST.oak
	local fab = S(o.color or COL.linen, MAT.fabric)
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.18, 1.5, 0.18), at(cf, sx * 0.75, 0.75, -0.75), frame, "Leg")
		box(m, V3(0.18, 3.4, 0.18), at(cf, sx * 0.75, 1.7, 0.8) * ANG(rad(6), 0, 0), frame, "Leg")
	end
	seat(m, V3(1.8, 0.3, 1.8), at(cf, 0, 1.65, 0), fab)
	box(m, V3(1.6, 1.3, 0.2), at(cf, 0, 2.85, 0.9) * ANG(rad(6), 0, 0), fab, "Back")
	return m
end

function F.diningTable(parent, cf, L, W)
	local m = item(parent, "Dining Table", cf)
	box(m, V3(L, 0.3, W), at(cf, 0, 2.55, 0), ST.oak, "Top")
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.5, 2.4, W - 1.2), at(cf, sx * (L / 2 - 1.6), 1.2, 0), ST.walnut, "Leg")
		box(m, V3(1.4, 0.2, W - 1.0), at(cf, sx * (L / 2 - 1.6), 0.1, 0), ST.walnut, "Foot")
	end
	box(m, V3(L - 3.2, 0.3, 0.4), at(cf, 0, 2.2, 0), ST.walnut, "Stretcher")
	box(m, V3(L * 0.7, 0.04, 1.4), at(cf, 0, 2.72, 0), S(COL.linen, MAT.fabric), "Runner")
	F.vase(m, at(cf, -L * 0.18, 2.74, 0), 1.0, COL.white, { RGB(250, 250, 250), RGB(236, 196, 206), RGB(250, 226, 160) })
	F.vase(m, at(cf, L * 0.18, 2.74, 0), 0.8, COL.terracotta)
	for _, sx in ipairs({ -1, 1 }) do
		vcyl(m, 0.9, 0.18, at(cf, sx * 1.2, 3.19, 0), S(RGB(250, 246, 236)), "Candle")
		vcyl(m, 0.15, 0.5, at(cf, sx * 1.2, 2.8, 0), ST.brass, "Holder")
	end
	return m
end

function F.placeSetting(parent, cf)
	vcyl(parent, 0.05, 1.3, at(cf, 0, 0.025, 0), ST.ceramic, "Plate")
	vcyl(parent, 0.4, 0.3, at(cf, 0.9, 0.2, 0.55), S(RGB(220, 236, 240), MAT.glass, 0.5), "Glass")
	box(parent, V3(0.1, 0.03, 0.9), at(cf, -0.85, 0.015, 0), ST.steel, "Fork")
	box(parent, V3(0.1, 0.03, 0.9), at(cf, 0.85, 0.015, 0), ST.steel, "Knife")
end

function F.barStool(parent, cf)
	local m = item(parent, "Bar Stool", cf)
	vcyl(m, 0.1, 1.5, at(cf, 0, 0.05, 0), ST.brass, "Base")
	vcyl(m, 3.0, 0.16, at(cf, 0, 1.6, 0), ST.brass, "Pole")
	vcyl(m, 0.08, 1.3, at(cf, 0, 1.3, 0), ST.brass, "Footrest")
	vcyl(m, 0.4, 1.7, at(cf, 0, 3.25, 0), S(RGB(110, 74, 52), MAT.leather), "Cushion")
	local s = seat(m, V3(1.3, 0.45, 1.3), at(cf, 0, 3.25, 0), ST.black)
	s.Transparency = 1
	box(m, V3(1.5, 1.0, 0.15), at(cf, 0, 3.9, 0.75) * ANG(rad(8), 0, 0), S(RGB(110, 74, 52), MAT.leather), "Back")
	return m
end

-- Base cabinets along local X, front = local -Z, worktop at 3.0.
-- o.sink / o.cooktop / o.oven = local x positions of those appliances.
function F.counter(parent, cf, L, o)
	o = o or {}
	local m = item(parent, o.name or "Kitchen Counter", cf)
	local D, H = 2.4, 3.0
	box(m, V3(L, 0.45, D - 0.35), at(cf, 0, 0.225, 0.175), ST.plinth, "Plinth")
	box(m, V3(L, H - 0.7, D - 0.1), at(cf, 0, 0.45 + (H - 0.7) / 2, 0.05), ST.carcass, "Carcass")
	local n = math.max(1, math.floor(L / 2.4 + 0.5))
	local fw = L / n
	local fh = H - 0.78
	for i = 1, n do
		local x = -L / 2 + fw * (i - 0.5)
		if o.oven and math.abs(x - o.oven) < fw / 2 then
			box(m, V3(fw - 0.08, fh, 0.1), at(cf, x, 0.49 + fh / 2, -D / 2), ST.blackGloss, "Oven")
			box(m, V3(fw - 0.5, fh - 0.9, 0.04), at(cf, x, 0.49 + fh / 2 - 0.15, -D / 2 - 0.06), S(RGB(40, 40, 44), MAT.glass, 0.1, 0.3), "OvenWindow")
			box(m, V3(fw - 0.6, 0.1, 0.1), at(cf, x, 0.49 + fh - 0.3, -D / 2 - 0.15), ST.steel, "Handle")
		elseif i % 2 == 0 then
			for k = 0, 2 do
				local h = fh / 3
				box(m, V3(fw - 0.08, h - 0.06, 0.1), at(cf, x, 0.49 + h * k + h / 2, -D / 2), ST.cabinet, "Drawer")
				box(m, V3(fw * 0.4, 0.08, 0.08), at(cf, x, 0.49 + h * k + h - 0.25, -D / 2 - 0.09), ST.brass, "Handle")
			end
		else
			box(m, V3(fw - 0.08, fh, 0.1), at(cf, x, 0.49 + fh / 2, -D / 2), ST.cabinet, "Door")
			box(m, V3(fw * 0.4, 0.08, 0.08), at(cf, x, 0.49 + fh - 0.25, -D / 2 - 0.09), ST.brass, "Handle")
		end
	end
	local z1, z2 = -D / 2 - 0.15, D / 2
	if o.sink then
		local s1, s2 = o.sink - 1.3, o.sink + 1.3
		lbox(m, cf, -L / 2, s1, H - 0.25, H, z1, z2, ST.marbleTop, "Worktop")
		lbox(m, cf, s2, L / 2, H - 0.25, H, z1, z2, ST.marbleTop, "Worktop")
		lbox(m, cf, s1, s2, H - 0.25, H, z1, -0.75, ST.marbleTop, "Worktop")
		lbox(m, cf, s1, s2, H - 0.25, H, 0.65, z2, ST.marbleTop, "Worktop")
		lbox(m, cf, s1, s2, H - 0.32, H - 0.26, -0.75, 0.65, ST.steel, "Sink")
		vcyl(m, 1.6, 0.16, at(cf, o.sink, H + 0.8, 0.9), ST.blackMetal, "Faucet")
		cyl(m, 1.0, 0.14, at(cf, o.sink, H + 1.55, 0.45) * ANG(0, PI / 2, 0), ST.blackMetal, "Spout")
		vcyl(m, 0.3, 0.14, at(cf, o.sink, H + 1.4, -0.02), ST.blackMetal, "Spout")
	else
		lbox(m, cf, -L / 2, L / 2, H - 0.25, H, z1, z2, ST.marbleTop, "Worktop")
	end
	if o.cooktop then
		box(m, V3(2.8, 0.05, 1.9), at(cf, o.cooktop, H + 0.025, 0), ST.blackGloss, "Cooktop")
		for _, p in ipairs({ { -0.65, -0.45 }, { 0.65, -0.45 }, { -0.65, 0.45 }, { 0.65, 0.45 } }) do
			vcyl(m, 0.02, 0.75, at(cf, o.cooktop + p[1], H + 0.06, p[2]), S(RGB(70, 70, 74)), "Burner")
		end
	end
	return m
end

function F.island(parent, cf, L, W)
	local m = item(parent, "Kitchen Island", cf)
	local H = 3.0
	local bodyD = W - 1.3 -- seating overhang on the +Z side
	local bz = -W / 2 + bodyD / 2
	box(m, V3(L - 0.6, 0.45, bodyD - 0.35), at(cf, 0, 0.225, bz + 0.175), ST.plinth, "Plinth")
	box(m, V3(L - 0.6, H - 0.75, bodyD - 0.1), at(cf, 0, 0.45 + (H - 0.75) / 2, bz + 0.05), ST.carcass, "Carcass")
	local n = math.max(1, math.floor((L - 0.6) / 2.4 + 0.5))
	local fw = (L - 0.6) / n
	for i = 1, n do
		local x = -(L - 0.6) / 2 + fw * (i - 0.5)
		for k = 0, 1 do
			local h = (H - 0.8) / 2
			box(m, V3(fw - 0.08, h - 0.06, 0.1), at(cf, x, 0.49 + h * k + h / 2, -W / 2), ST.cabinet, "Drawer")
			box(m, V3(fw * 0.4, 0.08, 0.08), at(cf, x, 0.49 + h * k + h - 0.25, -W / 2 - 0.09), ST.brass, "Handle")
		end
	end
	box(m, V3(L, 0.3, W), at(cf, 0, H - 0.15, 0), ST.marbleTop, "Worktop")
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.3, H - 0.3, W), at(cf, sx * (L / 2 - 0.15), (H - 0.3) / 2, 0), ST.marbleTop, "Waterfall")
	end
	-- decor
	vcyl(m, 0.35, 1.8, at(cf, -L * 0.22, H + 0.175, -0.4), S(RGB(214, 196, 170)), "FruitBowl")
	for i, c in ipairs({ RGB(250, 196, 40), RGB(240, 140, 30), RGB(130, 180, 60), RGB(200, 40, 40) }) do
		ball(m, 0.5, at(cf, -L * 0.22 + math.cos(i * 1.6) * 0.35, H + 0.5, -0.4 + math.sin(i * 1.6) * 0.35), S(c), "Fruit")
	end
	F.vase(m, at(cf, L * 0.25, H, -0.6), 1.2, RGB(236, 232, 224), { RGB(250, 250, 250), RGB(230, 210, 240) })
	box(m, V3(1.6, 0.12, 1.1), at(cf, 0.6, H + 0.06, -0.6) * ANG(0, rad(10), 0), ST.oak, "CuttingBoard")
	return m
end

function F.fridge(parent, cf)
	local m = item(parent, "Fridge", cf)
	local w, h, d = 3.4, 9.0, 2.4
	box(m, V3(w, h, d - 0.1), at(cf, 0, h / 2, 0.05), ST.carcass, "Body")
	box(m, V3(w / 2 - 0.05, h * 0.62, 0.15), at(cf, -w / 4, h - h * 0.31 - 0.05, -d / 2), ST.steel, "Door")
	box(m, V3(w / 2 - 0.05, h * 0.62, 0.15), at(cf, w / 4, h - h * 0.31 - 0.05, -d / 2), ST.steel, "Door")
	box(m, V3(w - 0.05, h * 0.36, 0.15), at(cf, 0, h * 0.18 + 0.02, -d / 2), ST.steel, "Freezer")
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.12, 3.6, 0.12), at(cf, sx * 0.2, h * 0.62, -d / 2 - 0.2), ST.blackMetal, "Handle")
	end
	box(m, V3(2.2, 0.12, 0.12), at(cf, 0, h * 0.34, -d / 2 - 0.2), ST.blackMetal, "Handle")
	return m
end

-- Tall cabinet with a built-in oven and microwave
function F.ovenTower(parent, cf)
	local m = item(parent, "Oven Tower", cf)
	local w, h, d = 2.8, 9.0, 2.4
	box(m, V3(w, h, d - 0.1), at(cf, 0, h / 2, 0.05), ST.carcass, "Body")
	box(m, V3(w - 0.08, 2.9, 0.1), at(cf, 0, 1.5, -d / 2), ST.cabinet, "Door")
	box(m, V3(w - 0.08, 2.2, 0.1), at(cf, 0, 4.1, -d / 2), ST.blackGloss, "Oven")
	box(m, V3(w - 0.5, 1.3, 0.04), at(cf, 0, 3.95, -d / 2 - 0.06), S(RGB(40, 40, 44), MAT.glass, 0.1, 0.3), "OvenWindow")
	box(m, V3(w - 0.6, 0.1, 0.1), at(cf, 0, 4.95, -d / 2 - 0.14), ST.steel, "Handle")
	box(m, V3(w - 0.08, 1.3, 0.1), at(cf, 0, 5.95, -d / 2), ST.blackGloss, "Microwave")
	box(m, V3(w - 0.08, 2.3, 0.1), at(cf, 0, 7.8, -d / 2), ST.cabinet, "Door")
	box(m, V3(0.08, 0.9, 0.08), at(cf, w / 2 - 0.35, 1.7, -d / 2 - 0.09), ST.brass, "Handle")
	box(m, V3(0.08, 0.9, 0.08), at(cf, w / 2 - 0.35, 7.2, -d / 2 - 0.09), ST.brass, "Handle")
	return m
end

function F.pantry(parent, cf)
	local m = item(parent, "Pantry", cf)
	local w, h, d = 2.8, 9.0, 2.4
	box(m, V3(w, h, d - 0.1), at(cf, 0, h / 2, 0.05), ST.carcass, "Body")
	box(m, V3(w - 0.08, h - 0.1, 0.1), at(cf, 0, h / 2, -d / 2), ST.cabinet, "Door")
	box(m, V3(0.08, 2.4, 0.08), at(cf, -w / 2 + 0.35, 4.6, -d / 2 - 0.09), ST.brass, "Handle")
	return m
end

function F.rangeHood(parent, cf, yCeil)
	local m = item(parent, "Range Hood", cf)
	local hy = 7.2 -- underside of the hood above the floor
	box(m, V3(3.2, 0.6, 2.0), at(cf, 0, hy + 0.3, -0.2), ST.steel, "Hood")
	box(m, V3(1.4, yCeil - hy - 0.6, 1.2), at(cf, 0, (yCeil + hy + 0.6) / 2, 0.2), ST.steel, "Chimney")
	local led = box(m, V3(2.6, 0.04, 1.2), at(cf, 0, hy - 0.02, -0.2), ST.lamp, "Light")
	addLight("SpotLight", led, { face = Enum.NormalId.Bottom, angle = 90, range = 9, brightness = 0.8 })
	return m
end

function F.floatingShelf(parent, cf, w)
	local m = item(parent, "Shelf", cf)
	box(m, V3(w, 0.25, 1.0), at(cf, 0, 0, 0), ST.oak, "Shelf")
	local x = -w / 2 + 0.4
	while x < w / 2 - 0.4 do
		local r = rng:NextNumber()
		if r < 0.35 then
			for k = 0, 2 do
				vcyl(m, 0.06, 0.9, at(cf, x + 0.45, 0.155 + k * 0.07, 0), ST.ceramic, "Plate")
			end
			x += 1.1
		elseif r < 0.7 then
			local h = rng:NextNumber(0.6, 1.0)
			vcyl(m, h, 0.5, at(cf, x + 0.3, 0.125 + h / 2, 0), S(RGB(232, 236, 236), MAT.glass, 0.4), "Jar")
			vcyl(m, 0.12, 0.52, at(cf, x + 0.3, 0.185 + h, 0), ST.oak, "Lid")
			x += 0.7
		else
			vcyl(m, 0.5, 0.6, at(cf, x + 0.35, 0.375, 0), S(RGB(196, 110, 80)), "Pot")
			ball(m, 0.8, at(cf, x + 0.35, 0.85, 0), S(RGB(80, 130, 64)), "Herbs")
			x += 0.9
		end
	end
	return m
end

function F.piano(parent, cf)
	local m = item(parent, "Grand Piano", cf)
	local gloss = ST.blackGloss
	local y0, y1 = 2.2, 3.4
	local yc, hb = (y0 + y1) / 2, y1 - y0
	box(m, V3(5, hb, 3.6), at(cf, 0, yc, -1.2), gloss, "Body")
	box(m, V3(3, hb, 2.9), at(cf, -1, yc, 2.05), gloss, "Body")
	vcyl(m, hb, 4.0, at(cf, 0.5, yc, 0.6), gloss, "Body")
	vcyl(m, hb, 3.0, at(cf, -1.0, yc, 3.5), gloss, "Body")
	for _, p in ipairs({ { -2.1, -2.6 }, { 2.1, -2.6 }, { -1.0, 4.1 } }) do
		vcyl(m, y0, 0.45, at(cf, p[1], y0 / 2, p[2]), gloss, "Leg")
		vcyl(m, 0.15, 0.55, at(cf, p[1], 0.075, p[2]), ST.brass, "Caster")
	end
	-- keyboard
	box(m, V3(4.7, 0.5, 1.2), at(cf, 0, 2.25, -3.5), gloss, "KeyBed")
	box(m, V3(4.3, 0.14, 0.95), at(cf, 0, 2.57, -3.55), ST.white, "WhiteKeys")
	local unit = 4.3 / 35
	for octave = 0, 4 do
		for _, b in ipairs({ 1, 2, 4, 5, 6 }) do
			box(m, V3(0.07, 0.12, 0.55), at(cf, -2.15 + unit * (7 * octave + b), 2.69, -3.35), ST.black, "BlackKey")
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.2, 0.55, 1.2), at(cf, sx * 2.25, 2.62, -3.5), gloss, "Cheek")
	end
	box(m, V3(4.3, 0.35, 0.2), at(cf, 0, 2.8, -3.0), gloss, "Fallboard")
	box(m, V3(3.2, 1.0, 0.1), at(cf, 0, y1 + 0.55, -2.7) * ANG(rad(-14), 0, 0), gloss, "MusicDesk")
	box(m, V3(1.5, 0.95, 0.03), at(cf, -0.2, y1 + 0.58, -2.77) * ANG(rad(-14), 0, 0), ST.white, "SheetMusic")
	-- lid hinged along the straight (bass) side and propped open
	box(m, V3(4.9, 0.1, 6.8), at(cf, -2.5, y1 + 0.06, 1.2) * ANG(0, 0, rad(30)) * CF(2.45, 0, 0), gloss, "Lid")
	box(m, V3(0.08, 2.4, 0.08), at(cf, 1.6, y1 + 1.2, 1.4) * ANG(0, 0, rad(10)), gloss, "LidProp")
	-- pedals
	box(m, V3(0.9, 1.6, 0.2), at(cf, 0, 0.95, -2.6), gloss, "Lyre")
	for _, x in ipairs({ -0.3, 0, 0.3 }) do
		box(m, V3(0.12, 0.08, 0.45), at(cf, x, 0.25, -2.85), ST.brass, "Pedal")
	end
	-- bench
	local bench = at(cf, 0, 0, -5.0)
	seat(m, V3(3.0, 0.4, 1.3), at(bench, 0, 1.75, 0), S(RGB(20, 20, 22), MAT.leather))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			box(m, V3(0.2, 1.55, 0.2), at(bench, sx * 1.3, 0.775, sz * 0.5), gloss, "Leg")
		end
	end
	return m
end

-- Bed: W wide (local X), L long (local Z). Foot at local -Z, headboard at +Z.
function F.bed(parent, cf, W, L, o)
	o = o or {}
	local m = item(parent, "Bed", cf)
	local duvet = S(o.duvet or RGB(238, 234, 226), MAT.fabric)
	box(m, V3(W - 1, 0.35, L - 1), at(cf, 0, 0.175, 0), ST.plinth, "Plinth")
	box(m, V3(W + 0.4, 0.9, L + 0.2), at(cf, 0, 0.8, 0), o.frame or ST.walnut, "Frame")
	box(m, V3(W, 1.0, L - 0.2), at(cf, 0, 1.75, -0.1), ST.white, "Mattress")
	local dl = L * 0.72
	local dz = -L / 2 + dl / 2 - 0.15
	box(m, V3(W + 0.3, 0.25, dl), at(cf, 0, 2.35, dz), duvet, "Duvet")
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.15, 1.0, dl), at(cf, sx * (W / 2 + 0.07), 1.85, dz), duvet, "Duvet")
	end
	box(m, V3(W + 0.3, 1.0, 0.15), at(cf, 0, 1.85, -L / 2 - 0.22), duvet, "Duvet")
	box(m, V3(W + 0.45, 0.14, 2.0), at(cf, 0, 2.52, -L / 2 + 1.3), S(o.throw or COL.terracotta, MAT.fabric), "Throw")
	local pw = (W - 0.8) / 2
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(pw, 0.9, 1.3), at(cf, sx * (pw / 2 + 0.2), 2.75, L / 2 - 1.1) * ANG(rad(18), 0, 0), ST.white, "Pillow")
		box(m, V3(pw * 0.7, 0.75, 0.45), at(cf, sx * (pw / 2 + 0.2), 2.7, L / 2 - 2.0) * ANG(rad(12), 0, 0), S(o.accent or COL.sage, MAT.fabric), "Cushion")
	end
	box(m, V3(W + 2.2, 4.8, 0.5), at(cf, 0, 2.4, L / 2 + 0.25), S(o.headboard or COL.linen, MAT.fabric), "Headboard")
	return m
end

-- Wall-hung nightstand with a lamp. Back of the unit at local +Z.
function F.nightstand(parent, cf)
	local m = item(parent, "Nightstand", cf)
	box(m, V3(2.2, 1.2, 1.8), at(cf, 0, 1.6, 0), ST.walnut, "Body")
	box(m, V3(2.0, 0.5, 0.06), at(cf, 0, 1.75, -0.92), S(RGB(124, 86, 58), MAT.wood), "Drawer")
	box(m, V3(0.7, 0.07, 0.07), at(cf, 0, 1.72, -0.98), ST.brass, "Handle")
	F.tableLamp(m, at(cf, 0.35, 2.2, 0.15))
	F.books(m, at(cf, -0.45, 2.2, -0.15), 2)
	return m
end

function F.bench(parent, cf, w, color)
	local m = item(parent, "Bench", cf)
	seat(m, V3(w, 0.5, 1.6), at(cf, 0, 1.55, 0), S(color or COL.blush, MAT.fabric))
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.15, 1.3, 1.4), at(cf, sx * (w / 2 - 0.3), 0.65, 0), ST.brass, "Leg")
	end
	return m
end

-- Open wardrobe for a walk-in closet: hanging bays alternate with shelf bays.
function F.closet(parent, cf, w, h)
	local m = item(parent, "Wardrobe", cf)
	local D = 2.2
	box(m, V3(w, h, 0.1), at(cf, 0, h / 2, D / 2 - 0.05), ST.walnut, "Back")
	local bays = math.max(1, math.floor(w / 3.5 + 0.5))
	local bw = w / bays
	for i = 0, bays do
		box(m, V3(0.15, h, D), at(cf, -w / 2 + bw * i, h / 2, 0), ST.walnut, "Divider")
	end
	box(m, V3(w, 0.15, D), at(cf, 0, h - 0.075, 0), ST.walnut, "Top")
	box(m, V3(w, 0.4, D), at(cf, 0, 0.2, 0), ST.walnut, "Plinth")
	local clothes = { COL.navy, COL.cream, COL.charcoal, COL.blush, COL.sage, RGB(240, 240, 240), COL.terracotta, RGB(160, 140, 120), RGB(70, 90, 120) }
	for i = 1, bays do
		local x0 = -w / 2 + bw * (i - 1)
		local cx = x0 + bw / 2
		box(m, V3(bw - 0.15, 0.12, D - 0.1), at(cf, cx, h - 1.6, 0), ST.walnut, "Shelf")
		for k = 0, math.max(0, math.floor((bw - 0.3) / 1.15) - 1) do -- folded clothes on the top shelf
			box(m, V3(1.0, rng:NextNumber(0.4, 0.9), 1.4), at(cf, x0 + 0.75 + k * 1.15, h - 1.25, 0), S(clothes[rng:NextInteger(1, #clothes)], MAT.fabric), "Folded")
		end
		if i % 2 == 1 then
			local railY = h - 2.0
			cyl(m, bw - 0.15, 0.1, at(cf, cx, railY, 0), ST.brass, "Rail")
			local x = x0 + 0.35
			while x < x0 + bw - 0.3 do
				local len = rng:NextNumber(2.4, 3.8)
				box(m, V3(0.14, len, 1.6), at(cf, x, railY - len / 2 - 0.1, 0), S(clothes[rng:NextInteger(1, #clothes)], MAT.fabric), "Clothes")
				x += rng:NextNumber(0.2, 0.32)
			end
		else
			for k = 1, 3 do
				local sy = 0.4 + k * 1.4
				box(m, V3(bw - 0.15, 0.12, D - 0.1), at(cf, cx, sy, 0), ST.walnut, "Shelf")
				box(m, V3(1.1, 0.6, 1.4), at(cf, cx - 0.5, sy + 0.36, 0), S(clothes[rng:NextInteger(1, #clothes)], MAT.fabric), "Folded")
				box(m, V3(0.9, 0.45, 1.3), at(cf, cx + 0.7, sy + 0.285, 0), S(clothes[rng:NextInteger(1, #clothes)], MAT.fabric), "Folded")
			end
		end
		for k = 0, 1 do -- a pair of shoes
			box(m, V3(0.4, 0.35, 1.0), at(cf, cx - 0.3 + k * 0.5, 0.575, -0.2), S(k == 0 and COL.charcoal or COL.terracotta, MAT.leather), "Shoe")
		end
	end
	return m
end

function F.desk(parent, cf, w)
	local m = item(parent, "Desk", cf)
	box(m, V3(w, 0.2, 2.8), at(cf, 0, 2.6, 0), ST.oak, "Top")
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.15, 2.5, 2.4), at(cf, sx * (w / 2 - 0.4), 1.25, 0), ST.blackMetal, "Leg")
	end
	box(m, V3(w - 0.8, 0.8, 0.1), at(cf, 0, 2.1, 1.1), ST.blackMetal, "Panel")
	box(m, V3(1.0, 0.06, 0.7), at(cf, 0, 2.73, 0.65), ST.blackMetal, "MonitorBase")
	box(m, V3(0.15, 1.3, 0.12), at(cf, 0, 3.35, 0.8), ST.blackMetal, "MonitorArm")
	local screen = box(m, V3(3.6, 2.05, 0.12), at(cf, 0, 4.1, 0.66), ST.black, "Monitor")
	drawTheme(screen, Enum.NormalId.Front, 3.6 / 2.05, "code", true)
	box(m, V3(2.4, 0.08, 0.75), at(cf, -0.2, 2.74, -0.45), S(RGB(62, 64, 68)), "Keyboard")
	box(m, V3(0.32, 0.1, 0.5), at(cf, 1.6, 2.75, -0.45), S(RGB(62, 64, 68)), "Mouse")
	vcyl(m, 0.45, 0.35, at(cf, -w / 2 + 1.0, 2.925, -0.5), S(COL.terracotta), "Mug")
	F.books(m, at(cf, w / 2 - 1.1, 2.7, 0.4), 4)
	F.plant(m, at(cf, -w / 2 + 1.0, 2.7, 0.6), "snake", 0.45)
	-- desk lamp
	vcyl(m, 0.1, 0.7, at(cf, w / 2 - 1.0, 2.75, -0.4), ST.blackMetal, "LampBase")
	box(m, V3(0.08, 1.6, 0.08), at(cf, w / 2 - 1.0, 3.55, -0.2) * ANG(rad(-15), 0, 0), ST.blackMetal, "LampArm")
	local head = box(m, V3(0.5, 0.25, 0.8), at(cf, w / 2 - 1.0, 4.35, -0.45), ST.blackMetal, "LampHead")
	addLight("SpotLight", head, { face = Enum.NormalId.Bottom, angle = 70, range = 8, brightness = 0.8 })
	return m
end

function F.officeChair(parent, cf)
	local m = item(parent, "Desk Chair", cf)
	for i = 0, 4 do
		local a = i * 2 * PI / 5
		box(m, V3(0.18, 0.15, 1.1), at(cf, 0, 0.3, 0) * ANG(0, a, 0) * CF(0, 0, 0.55), ST.blackMetal, "Base")
		ball(m, 0.28, at(cf, 0, 0, 0) * ANG(0, a, 0) * CF(0, 0.14, 1.05), ST.black, "Wheel")
	end
	vcyl(m, 1.3, 0.25, at(cf, 0, 1.0, 0), ST.steel, "Lift")
	local fab = S(RGB(62, 64, 70), MAT.fabric)
	seat(m, V3(2.0, 0.35, 2.0), at(cf, 0, 1.82, 0), fab)
	box(m, V3(1.9, 2.3, 0.3), at(cf, 0, 3.2, 1.05) * ANG(rad(8), 0, 0), fab, "Back")
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.15, 0.7, 0.15), at(cf, sx * 0.95, 2.3, 0.2), ST.blackMetal, "ArmPost")
		box(m, V3(0.25, 0.12, 1.2), at(cf, sx * 0.95, 2.65, 0.1), ST.black, "ArmPad")
	end
	return m
end

-- Floating vanity, back against the wall at local z = +1
function F.vanity(parent, cf, w, sinks)
	local m = item(parent, "Vanity", cf)
	box(m, V3(w, 1.6, 2.0), at(cf, 0, 2.2, 0), ST.walnut, "Cabinet")
	box(m, V3(w + 0.1, 0.2, 2.1), at(cf, 0, 3.1, -0.05), ST.marbleTop, "Counter")
	box(m, V3(w - 0.2, 0.05, 0.06), at(cf, 0, 2.2, -1.01), S(RGB(70, 46, 30)), "Line")
	for i = 1, sinks or 1 do
		local x = -w / 2 + w * (i - 0.5) / (sinks or 1)
		vcyl(m, 0.5, 1.5, at(cf, x, 3.45, -0.1), ST.ceramic, "Basin")
		vcyl(m, 0.02, 1.25, at(cf, x, 3.71, -0.1), S(RGB(226, 230, 232)), "Bowl")
		vcyl(m, 1.0, 0.12, at(cf, x, 3.7, 0.75), ST.blackMetal, "Faucet")
		cyl(m, 0.75, 0.1, at(cf, x, 4.15, 0.42) * ANG(0, PI / 2, 0), ST.blackMetal, "Spout")
		box(m, V3(2.6, 3.4, 0.05), at(cf, x, 6.3, 0.95), ST.lamp, "MirrorGlow")
		local mirror = box(m, V3(2.4, 3.2, 0.1), at(cf, x, 6.3, 0.88), ST.mirror, "Mirror")
		addLight("PointLight", mirror, { range = 7, brightness = 0.5 })
		vcyl(m, 0.5, 0.3, at(cf, x + 1.0, 3.45, 0.5), S(RGB(214, 196, 170)), "Soap")
	end
	box(m, V3(1.2, 0.5, 1.0), at(cf, -w / 2 + 0.8, 3.45, 0.3), ST.white, "Towels")
	return m
end

-- Wall-hung toilet; wall at local z = +1.45
function F.toilet(parent, cf)
	local m = item(parent, "Toilet", cf)
	box(m, V3(1.4, 1.0, 1.0), at(cf, 0, 1.5, 0.45), ST.ceramic, "Bowl")
	vcyl(m, 1.0, 1.4, at(cf, 0, 1.5, -0.1), ST.ceramic, "Bowl")
	box(m, V3(1.45, 0.12, 1.1), at(cf, 0, 2.06, 0.4), ST.ceramic, "Seat")
	vcyl(m, 0.12, 1.45, at(cf, 0, 2.06, -0.12), ST.ceramic, "Seat")
	box(m, V3(2.6, 3.6, 0.5), at(cf, 0, 1.8, 1.2), S(RGB(214, 208, 198), MAT.tiles), "Ledge")
	box(m, V3(0.9, 0.55, 0.06), at(cf, 0, 3.0, 0.93), ST.steel, "Flush")
	F.plant(m, at(cf, 0.8, 3.6, 1.2), "snake", 0.3)
	return m
end

function F.bathtub(parent, cf, L, W)
	local m = item(parent, "Bathtub", cf)
	local H, t = 2.0, 0.3
	box(m, V3(L, H - 0.35, W), at(cf, 0, (H - 0.35) / 2, 0), ST.ceramic, "Tub")
	box(m, V3(L, 0.35, t), at(cf, 0, H - 0.175, -W / 2 + t / 2), ST.ceramic, "Rim")
	box(m, V3(L, 0.35, t), at(cf, 0, H - 0.175, W / 2 - t / 2), ST.ceramic, "Rim")
	box(m, V3(t, 0.35, W - 2 * t), at(cf, -L / 2 + t / 2, H - 0.175, 0), ST.ceramic, "Rim")
	box(m, V3(t, 0.35, W - 2 * t), at(cf, L / 2 - t / 2, H - 0.175, 0), ST.ceramic, "Rim")
	box(m, V3(L - 2 * t, 0.06, W - 2 * t), at(cf, 0, H - 0.25, 0), ST.bathWater, "Water")
	-- floor-standing tub filler at the +X end
	local fx = L / 2 + 0.7
	vcyl(m, 3.4, 0.16, at(cf, fx, 1.7, 0), ST.blackMetal, "Filler")
	cyl(m, 0.9, 0.12, at(cf, fx - 0.4, 3.4, 0), ST.blackMetal, "Spout")
	vcyl(m, 0.25, 0.12, at(cf, fx - 0.8, 3.25, 0), ST.blackMetal, "Spout")
	return m
end

function F.towelRail(parent, cf, color)
	local m = item(parent, "Towel Rail", cf)
	cyl(m, 2.2, 0.1, at(cf, 0, 4.2, 0), ST.brass, "Rail")
	box(m, V3(1.8, 2.6, 0.12), at(cf, 0, 2.95, 0), S(color or COL.cream, MAT.fabric), "Towel")
	return m
end

------------------------------------------------------------------------------------------
-- Outdoor pieces
------------------------------------------------------------------------------------------
-- Sun lounger: foot at local -Z, raised backrest at +Z
function F.lounger(parent, cf, towel)
	local m = item(parent, "Sun Lounger", cf)
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V3(0.2, 0.3, 6.6), at(cf, sx * 1.25, 1.0, 0), ST.teak, "Rail")
		for _, sz in ipairs({ -1, 1 }) do
			box(m, V3(0.25, 0.85, 0.25), at(cf, sx * 1.25, 0.425, sz * 3.0), ST.teak, "Leg")
		end
	end
	box(m, V3(2.5, 0.2, 6.4), at(cf, 0, 1.1, 0), ST.teak, "Bed")
	local cushion = S(RGB(238, 234, 226), MAT.fabric)
	seat(m, V3(2.4, 0.35, 4.2), at(cf, 0, 1.375, -1.0), cushion)
	local hinge = at(cf, 0, 1.2, 1.1) * ANG(rad(-40), 0, 0)
	box(m, V3(2.4, 0.35, 2.4), hinge * CF(0, 0.175, 1.2), cushion, "Backrest")
	box(m, V3(1.6, 0.45, 0.8), hinge * CF(0, 0.55, 1.6), cushion, "Pillow")
	if towel then
		box(m, V3(1.7, 0.06, 2.8), at(cf, 0, 1.58, -1.4), S(towel, MAT.fabric), "Towel")
	end
	return m
end

function F.parasol(parent, cf, color)
	local m = item(parent, "Parasol", cf)
	box(m, V3(1.6, 0.5, 1.6), at(cf, 0, 0.25, 0), ST.stoneDark, "Base")
	vcyl(m, 8.2, 0.22, at(cf, 0, 4.4, 0), ST.teak, "Pole")
	local fab = S(color or RGB(244, 240, 230), MAT.fabric)
	vcyl(m, 0.25, 10, at(cf, 0, 7.6, 0), fab, "Canopy")
	vcyl(m, 0.25, 7, at(cf, 0, 7.85, 0), fab, "Canopy")
	vcyl(m, 0.25, 4, at(cf, 0, 8.1, 0), fab, "Canopy")
	ball(m, 0.4, at(cf, 0, 8.4, 0), ST.teak, "Finial")
	return m
end

function F.tree(parent, cf, kind, s)
	s = s or 1
	local m = item(parent, "Tree", cf)
	local h = 8 * s
	vcyl(m, h, 1.0 * s, at(cf, 0, h / 2, 0), ST.trunk, "Trunk")
	for i = 1, 3 do
		local branch = at(cf, 0, h * 0.62, 0) * ANG(0, i * 2.1, 0) * ANG(0, 0, rad(-42))
		box(m, V3(0.45 * s, 3.4 * s, 0.45 * s), branch * CF(0, 1.6 * s, 0), ST.trunk, "Branch")
	end
	local cols
	if kind == "maple" then
		cols = { RGB(180, 60, 42), RGB(206, 96, 48), RGB(152, 42, 38) }
	elseif kind == "blossom" then
		cols = { RGB(240, 196, 210), RGB(250, 220, 228), RGB(226, 170, 190) }
	else
		cols = { RGB(70, 122, 58), RGB(88, 140, 66), RGB(58, 104, 50) }
	end
	for i = 1, 8 do
		local a = i * 2.4 + rng:NextNumber()
		local r = rng:NextNumber(1.8, 3.4) * s
		local y = h + rng:NextNumber(-1.2, 2.2) * s
		ball(m, rng:NextNumber(4.5, 6.5) * s, at(cf, math.cos(a) * r, y, math.sin(a) * r), S(cols[i % #cols + 1], MAT.grass), "Leaves")
	end
	ball(m, 6.5 * s, at(cf, 0, h + 2.6 * s, 0), S(cols[1], MAT.grass), "Leaves")
	return m
end

function F.cypress(parent, cf, s)
	s = s or 1
	local m = item(parent, "Cypress", cf)
	vcyl(m, 2 * s, 0.6 * s, at(cf, 0, s, 0), ST.trunk, "Trunk")
	for i = 0, 5 do
		local d = (3.4 - i * 0.45) * s
		ball(m, d, at(cf, 0, (2.5 + i * 2.1) * s, 0), S(i % 2 == 0 and RGB(46, 84, 48) or RGB(56, 96, 54), MAT.grass), "Leaves")
	end
	return m
end

function F.palm(parent, cf, s)
	s = s or 1
	local m = item(parent, "Palm Tree", cf)
	local c = cf
	local segH = 1.5 * s
	for i = 1, 9 do
		c = c * CF(0, segH / 2, 0)
		vcyl(m, segH + 0.1, (1.15 - i * 0.05) * s, c, S(i % 2 == 0 and RGB(132, 104, 76) or RGB(116, 90, 66), MAT.wood), "Trunk")
		c = c * CF(0, segH / 2, 0) * ANG(0, 0, rad(3.5))
	end
	for i = 1, 3 do
		ball(m, 0.7 * s, c * ANG(0, i * 2.1, 0) * CF(0.45 * s, -0.4 * s, 0), S(RGB(110, 84, 44)), "Coconut")
	end
	for i = 1, 10 do
		local fr = c * ANG(0, i * (2 * PI / 10) + 0.2, 0) * ANG(rad(20 + (i % 3) * 8), 0, 0)
		local col = S(i % 2 == 0 and RGB(76, 136, 60) or RGB(92, 150, 66))
		box(m, V3(1.4 * s, 0.1, 3.2 * s), fr * CF(0, 0, 1.6 * s), col, "Frond")
		box(m, V3(1.1 * s, 0.1, 3.0 * s), fr * CF(0, 0, 3.1 * s) * ANG(rad(28), 0, 0) * CF(0, 0, 1.4 * s), col, "Frond")
	end
	return m
end

function F.bush(parent, cf, s, flowers)
	s = s or 1
	local m = item(parent, "Bush", cf)
	local greens = { RGB(62, 112, 56), RGB(76, 126, 60), RGB(52, 98, 50) }
	for i = 1, 3 do
		local a = i * 2.1
		ball(m, rng:NextNumber(1.6, 2.4) * s, at(cf, math.cos(a) * 0.6 * s, 0.7 * s, math.sin(a) * 0.6 * s), S(greens[i], MAT.grass), "Leaves")
	end
	if flowers then
		for i = 1, 6 do
			local a = i * 1.05 + rng:NextNumber()
			ball(m, 0.42 * s, at(cf, math.cos(a) * 0.9 * s, (1.3 + rng:NextNumber(0, 0.5)) * s, math.sin(a) * 0.9 * s), S(flowers), "Flower")
		end
	end
	return m
end

function F.grass(parent, cf, s)
	s = s or 1
	local m = item(parent, "Ornamental Grass", cf)
	for i = 1, 9 do
		local a = i * 0.7
		box(m, V3(0.12, 2.2 * s, 0.12), at(cf, 0, 0, 0) * ANG(0, a, 0) * ANG(rad(12 + (i % 3) * 7), 0, 0) * CF(0, 1.1 * s, 0), S(RGB(170, 160, 110)), "Blade")
	end
	return m
end

function F.bollard(parent, cf)
	local m = item(parent, "Garden Light", cf)
	vcyl(m, 2.4, 0.5, at(cf, 0, 1.2, 0), ST.blackMetal, "Post")
	local lamp = vcyl(m, 0.3, 0.52, at(cf, 0, 2.15, 0), ST.lamp, "Lamp")
	vcyl(m, 0.15, 0.62, at(cf, 0, 2.475, 0), ST.blackMetal, "Cap")
	addLight("PointLight", lamp, { range = 11, brightness = 0.8 })
	return m
end

-- Small ground spotlight that lights up a tree or facade from below
function F.uplight(parent, cf)
	local m = item(parent, "Uplight", cf)
	box(m, V3(0.6, 0.4, 0.6), at(cf, 0, 0.2, 0), ST.blackMetal, "Housing")
	local lens = box(m, V3(0.45, 0.05, 0.45), at(cf, 0, 0.42, 0), ST.lamp, "Lens")
	addLight("SpotLight", lens, { face = Enum.NormalId.Top, angle = 50, range = 18, brightness = 1.2 })
	return m
end

function F.outdoorTable(parent, cf, L, W, chairs)
	local m = item(parent, "Outdoor Dining", cf)
	box(m, V3(L, 0.25, W), at(cf, 0, 2.55, 0), ST.teak, "Top")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			box(m, V3(0.3, 2.45, 0.3), at(cf, sx * (L / 2 - 0.5), 1.225, sz * (W / 2 - 0.5)), ST.teak, "Leg")
		end
	end
	local per = chairs or 3
	for i = 1, per do
		local x = -L / 2 + L * (i - 0.5) / per
		F.chair(m, at(cf, x, 0, -W / 2 - 1.3), { frame = ST.teak, color = RGB(236, 230, 218) })
		F.chair(m, at(cf, x, 0, W / 2 + 1.3) * ANG(0, PI, 0), { frame = ST.teak, color = RGB(236, 230, 218) })
	end
	F.vase(m, at(cf, 0, 2.675, 0), 0.8, RGB(236, 232, 224), { RGB(250, 250, 250), RGB(250, 220, 120) })
	return m
end

function F.car(parent, cf, color)
	local m = item(parent, "Car", cf)
	local paint = S(color or RGB(26, 46, 80), MAT.smooth, 0, 0.25)
	local tint = S(RGB(28, 34, 42), MAT.glass, 0.2, 0.3)
	box(m, V3(5.6, 0.4, 11), at(cf, 0, 0.9, 0), ST.black, "Underbody")
	box(m, V3(6.2, 1.7, 13.6), at(cf, 0, 2.05, 0), paint, "Body")
	wedge(m, V3(6.2, 0.5, 4.2), at(cf, 0, 3.15, -4.7), paint, "Hood")
	wedge(m, V3(5.6, 1.6, 2.2), at(cf, 0, 3.7, -1.5), tint, "Windshield")
	box(m, V3(5.6, 1.6, 3.6), at(cf, 0, 3.7, 1.4), tint, "Windows")
	box(m, V3(5.65, 0.2, 3.7), at(cf, 0, 4.6, 1.4), paint, "Roof")
	wedge(m, V3(5.6, 1.6, 1.8), at(cf, 0, 3.7, 4.1) * ANG(0, PI, 0), tint, "RearWindow")
	box(m, V3(6.2, 0.5, 1.8), at(cf, 0, 3.15, 5.9), paint, "Trunk")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local w = at(cf, sx * 2.95, 1.4, sz * 4.4)
			cyl(m, 1.0, 2.8, w, ST.rubber, "Tyre")
			cyl(m, 1.06, 1.9, w, ST.steel, "Rim")
		end
		box(m, V3(0.4, 0.3, 0.6), at(cf, sx * 3.25, 3.75, -1.6), paint, "Mirror")
		box(m, V3(0.08, 0.12, 0.6), at(cf, sx * 3.12, 2.65, 0.2), ST.steel, "DoorHandle")
		box(m, V3(0.08, 0.12, 0.6), at(cf, sx * 3.12, 2.65, 3.0), ST.steel, "DoorHandle")
	end
	for _, sx in ipairs({ -1, 1 }) do
		local hl = box(m, V3(1.5, 0.3, 0.1), at(cf, sx * 2.1, 2.55, -6.82), S(RGB(240, 248, 255), MAT.neon), "Headlight")
		addLight("SpotLight", hl, { face = Enum.NormalId.Front, angle = 45, range = 20, brightness = 1, color = RGB(235, 245, 255) })
	end
	box(m, V3(5.4, 0.25, 0.1), at(cf, 0, 2.6, 6.82), S(RGB(220, 30, 40), MAT.neon), "Taillight")
	box(m, V3(3.0, 0.6, 0.1), at(cf, 0, 1.75, -6.83), ST.black, "Grille")
	for _, z in ipairs({ -6.86, 6.86 }) do
		local plate = box(m, V3(1.8, 0.5, 0.05), at(cf, 0, 1.6, z), ST.white, "Plate")
		local sg = surfaceGui(plate, z < 0 and Enum.NormalId.Front or Enum.NormalId.Back, false)
		label(sg, "VILLA " .. CONFIG.HouseNumber, RGB(30, 30, 40), "GothamBold")
	end
	return m
end

------------------------------------------------------------------------------------------
-- STRUCTURE
-- Ground floor box: X -32..32, Z -20..20.   Upper floor box: X -36..24, Z -26..20
-- (it cantilevers 6 studs over the entrance and 4 over the west side).
-- Exterior walls = 0.4 outer skin + 0.6 inner skin, so outside and inside can differ.
------------------------------------------------------------------------------------------
local function buildStructure(house, doors)
	local s = item(house, "Structure")
	local win = item(house, "Windows")

	-- Podium and ground-floor finishes
	rect(s, -31.8, 31.8, -19.8, 19.8, 0, Y1 - 0.3, ST.foundation, "Foundation")
	local fy = Y1 - 0.3
	rect(s, -31.6, -10, -19.6, 19.6, fy, Y1, ST.floorOak, "Floor")
	rect(s, -10, 4, -19.6, 19.6, fy, Y1, ST.floorStone, "Floor")
	rect(s, 4, 12, -10, 19.6, fy, Y1, ST.floorStone, "Floor")
	rect(s, 12, 31.6, -19.6, 19.6, fy, Y1, ST.floorStone, "Floor")
	rect(s, 4, 12, -19.6, -10, fy, Y1, ST.floorTile, "Floor")

	-- Ground floor exterior walls
	local frontHoles = {
		{ -28.5, -26.5, Y1 + 1, Y1 + 11 },
		{ -16.5, -14.5, Y1 + 1, Y1 + 11 },
		{ -6, 3, Y1, Y1 + 10 },
		{ 6, 10, Y1 + 7, Y1 + 10 },
		{ 15, 27, Y1 + 4, Y1 + 9 },
	}
	wall(s, "x", -19.8, -32, -10, GROUND, C1, 0.4, ST.stoneDark, frontHoles, "Facade")
	wall(s, "x", -19.8, -10, 32, GROUND, C1, 0.4, ST.extWhite, frontHoles, "Facade")
	wall(s, "x", -19.3, -31.6, 31.6, Y1, C1, 0.6, ST.intWall, frontHoles, "Wall")
	local backHoles = { { -30, -12, Y1, Y1 + 11 }, { -9, 3, Y1, Y1 + 11 }, { 6, 30, Y1, Y1 + 11 } }
	wall(s, "x", 19.8, -32, 32, GROUND, C1, 0.4, ST.extWhite, backHoles, "Facade")
	wall(s, "x", 19.3, -31.6, 31.6, Y1, C1, 0.6, ST.intWall, backHoles, "Wall")
	local westHoles = { { -17, -10, Y1 + 1, Y1 + 11 }, { 10, 17, Y1 + 1, Y1 + 11 } }
	wall(s, "z", -31.8, -19.6, 19.6, GROUND, C1, 0.4, ST.stoneDark, westHoles, "Facade")
	wall(s, "z", -31.3, -19, 19, Y1, C1, 0.6, ST.intWall, westHoles, "Wall")
	local eastHoles = { { 6, 18, Y1 + 4, Y1 + 10 } }
	wall(s, "z", 31.8, -19.6, 19.6, GROUND, C1, 0.4, ST.extWhite, eastHoles, "Facade")
	wall(s, "z", 31.3, -19, 19, Y1, C1, 0.6, ST.intWall, eastHoles, "Wall")

	glazing(win, "x", -19.5, -28.5, -26.5, Y1 + 1, Y1 + 11, { panes = 1, sill = -1 })
	glazing(win, "x", -19.5, -16.5, -14.5, Y1 + 1, Y1 + 11, { panes = 1, sill = -1 })
	glazing(win, "x", -19.5, 6, 10, Y1 + 7, Y1 + 10, { panes = 1, glass = ST.frosted, sill = -1 })
	glazing(win, "x", -19.5, 15, 27, Y1 + 4, Y1 + 9, { panes = 2, sill = -1 })
	glazing(win, "x", 19.5, -9, 3, Y1, Y1 + 11, { panes = 2 })
	glazing(win, "z", -31.5, -17, -10, Y1 + 1, Y1 + 11, { panes = 1, sill = -1 })
	glazing(win, "z", -31.5, 10, 17, Y1 + 1, Y1 + 11, { panes = 1, sill = -1 })
	glazing(win, "z", 31.5, 6, 18, Y1 + 4, Y1 + 10, { panes = 2, sill = 1 })
	slidingDoors(doors, "x", 19.5, -30, -12, Y1, Y1 + 11, "F<", "Living Room Terrace")
	slidingDoors(doors, "x", 19.5, 6, 30, Y1, Y1 + 11, "F<>F", "Dining Terrace")

	-- Entrance: tall pivot door + glass sidelight
	ap(win, "x", -19.5, -6, 3, Y1 + 9.7, Y1 + 10, 0, 0.9, ST.frame, "Frame")
	ap(win, "x", -19.5, -6, -5.7, Y1, Y1 + 9.7, 0, 0.9, ST.frame, "Frame")
	ap(win, "x", -19.5, 2.7, 3, Y1, Y1 + 9.7, 0, 0.9, ST.frame, "Frame")
	ap(win, "x", -19.5, -1.0, -0.7, Y1, Y1 + 9.7, 0, 0.9, ST.frame, "Frame")
	ap(win, "x", -19.5, -0.7, 2.7, Y1, Y1 + 9.7, 0, 0.12, ST.glass, "Glass")
	do
		local g = item(doors, "Front Door")
		local leaf = ap(g, "x", -19.5, -5.65, -1.05, Y1 + 0.03, Y1 + 9.65, 0, 0.4, S(RGB(86, 58, 38), MAT.wood), "Leaf")
		for i = 1, 5 do -- vertical grooves
			ap(g, "x", -19.5, -5.65 + i * 0.77 - 0.03, -5.65 + i * 0.77 + 0.03, Y1 + 0.5, Y1 + 9.2, 0, 0.44, ST.black, "Groove")
		end
		for _, side in ipairs({ -1, 1 }) do -- long pull handles
			ap(g, "x", -19.5, -1.75, -1.6, Y1 + 2.5, Y1 + 7.5, side * 0.42, 0.15, ST.brass, "Handle")
			ap(g, "x", -19.5, -1.72, -1.63, Y1 + 2.9, Y1 + 3.1, side * 0.3, 0.12, ST.brass, "Standoff")
			ap(g, "x", -19.5, -1.72, -1.63, Y1 + 6.9, Y1 + 7.1, side * 0.3, 0.12, ST.brass, "Standoff")
		end
		if CONFIG.InteractiveDoors then
			makeDoor(g, leaf, "Front Door", { HingeOffset = V3(-1.15, 0, 0), OpenAngle = -90 })
		end
	end

	-- Slab between the floors (its underside is the ground-floor ceiling) + stair void
	rectHole(s, -35.6, 23.6, -25.6, 19.6, C1, Y2 - 0.4, ST.ceiling, -9.5, -3.5, -9.5, 6.5, "Slab")
	rect(s, 23.6, 32, -20, 20, C1, Y2 - 0.4, ST.ceiling, "Slab")
	local u1 = Y2 - 0.4
	rect(s, -35.6, -10, -25.6, -10, u1, Y2, ST.floorOak, "Floor")
	rect(s, -35.6, -22, -10, 2, u1, Y2, ST.floorTile, "Floor")
	rect(s, -22, -10, -10, 2, u1, Y2, ST.floorOak, "Floor")
	rect(s, -35.6, -10, 2, 19.6, u1, Y2, ST.floorOak, "Floor")
	rectHole(s, -10, 4, -25.6, 19.6, u1, Y2, ST.floorOak, -9.5, -3.5, -9.5, 6.5, "Floor")
	rect(s, 4, 23.6, -10, 19.6, u1, Y2, ST.floorOak, "Floor")
	rect(s, 4, 23.6, -25.6, -10, u1, Y2, ST.floorTile, "Floor")
	rect(s, 23.6, 32, -20, 20, u1, Y2, ST.deck, "Terrace")
	rect(s, 32, 32.3, -20.3, 20.3, C1 - 0.3, Y2 + 0.5, ST.extWhite, "Fascia")
	rect(s, 23.6, 32, -20.3, -20, C1 - 0.3, Y2 + 0.5, ST.extWhite, "Fascia")
	rect(s, 23.6, 32, 20, 20.3, C1 - 0.3, Y2 + 0.5, ST.extWhite, "Fascia")

	-- Upper floor exterior walls (cedar outside, plaster inside)
	local top = RT + 0.4
	local ufFront = { { -33, -14, Y2 + 2, Y2 + 9 }, { -9, 3, Y2, Y2 + 10 }, { 7, 21, Y2 + 6, Y2 + 9 } }
	wall(s, "x", -25.8, -36, 24, C1, top, 0.4, ST.cedar, ufFront, "Cladding")
	wall(s, "x", -25.3, -35.6, 23.6, Y2, C2, 0.6, ST.intWall, ufFront, "Wall")
	local ufBack = { { -33, -14, Y2, Y2 + 10 }, { -9, -5, Y2, Y2 + 10 }, { 6, 21, Y2, Y2 + 10 } }
	wall(s, "x", 19.8, -36, 24, C1, top, 0.4, ST.cedar, ufBack, "Cladding")
	wall(s, "x", 19.3, -35.6, 23.6, Y2, C2, 0.6, ST.intWall, ufBack, "Wall")
	local ufWest = { { -22, -13, Y2 + 2, Y2 + 9 }, { -7, -1, Y2 + 6, Y2 + 9 }, { 6, 15, Y2 + 2, Y2 + 9 } }
	wall(s, "z", -35.8, -25.6, 19.6, C1, top, 0.4, ST.cedar, ufWest, "Cladding")
	wall(s, "z", -35.3, -25, 19, Y2, C2, 0.6, ST.intWall, ufWest, "Wall")
	local ufEast = { { -22, -13, Y2 + 6, Y2 + 9 }, { 2, 14, Y2, Y2 + 9.5 } }
	wall(s, "z", 23.8, -25.6, -20, C1, top, 0.4, ST.cedar, ufEast, "Cladding")
	wall(s, "z", 23.8, -20, 19.6, Y2, top, 0.4, ST.cedar, ufEast, "Cladding")
	wall(s, "z", 23.3, -25, 19, Y2, C2, 0.6, ST.intWall, ufEast, "Wall")

	glazing(win, "x", -25.5, -33, -14, Y2 + 2, Y2 + 9, { panes = 3, sill = -1 })
	glazing(win, "x", -25.5, -9, 3, Y2, Y2 + 10, { panes = 3 })
	glazing(win, "x", -25.5, 7, 21, Y2 + 6, Y2 + 9, { panes = 2, glass = ST.frosted, sill = -1 })
	glazing(win, "x", 19.5, -33, -14, Y2, Y2 + 10, { panes = 3 })
	glazing(win, "x", 19.5, -9, -5, Y2, Y2 + 10, { panes = 1 })
	glazing(win, "x", 19.5, 6, 21, Y2, Y2 + 10, { panes = 3 })
	glazing(win, "z", -35.5, -22, -13, Y2 + 2, Y2 + 9, { panes = 2, sill = -1 })
	glazing(win, "z", -35.5, -7, -1, Y2 + 6, Y2 + 9, { panes = 1, glass = ST.frosted, sill = -1 })
	glazing(win, "z", -35.5, 6, 15, Y2 + 2, Y2 + 9, { panes = 2, sill = -1 })
	glazing(win, "z", 23.5, -22, -13, Y2 + 6, Y2 + 9, { panes = 2, glass = ST.frosted, sill = 1 })
	slidingDoors(doors, "z", 23.5, 2, 14, Y2, Y2 + 9.5, "F<", "Roof Terrace")

	-- Vertical cedar fins in front of the landing window
	for i = 0, 8 do
		box(s, V3(0.35, 10.6, 1.2), CF(-8.5 + i * 1.375, Y2 + 5, -26.6), ST.cedar, "Fin")
	end

	-- Interior partitions
	local iw = item(house, "Interior Walls")
	wall(iw, "z", 4, -19, -10.3, Y1, C1, 0.6, ST.intWall, { { -16, -12.5, Y1, Y1 + 8.5 } }, "Wall")
	wall(iw, "x", -10, 3.7, 12.3, Y1, C1, 0.6, ST.intWall, nil, "Wall")
	wall(iw, "z", 12, -19, -10.3, Y1, C1, 0.6, ST.intWall, nil, "Wall")
	door(doors, "z", 4, -16, -12.5, Y1, 8.5, 0.6, "a", 1, "Bathroom")
	wall(iw, "z", -10, -25, 19, Y2, C2, 0.6, ST.intWall, { { -19, -15.5, Y2, Y2 + 8.5 }, { 11, 14.5, Y2, Y2 + 8.5 } }, "Wall")
	door(doors, "z", -10, -19, -15.5, Y2, 8.5, 0.6, "a", -1, "Office")
	door(doors, "z", -10, 11, 14.5, Y2, 8.5, 0.6, "b", -1, "Bedroom")
	wall(iw, "x", -10, -35, -10.3, Y2, C2, 0.6, ST.intWall, nil, "Wall")
	wall(iw, "z", -22, -9.7, 1.7, Y2, C2, 0.6, ST.intWall, { { -3, 0.5, Y2, Y2 + 8.5 } }, "Wall")
	door(doors, "z", -22, -3, 0.5, Y2, 8.5, 0.6, "b", -1, "Bathroom")
	wall(iw, "x", 2, -35, -21.7, Y2, C2, 0.6, ST.intWall, nil, "Wall")
	wall(iw, "z", 4, -25, 19, Y2, C2, 0.6, ST.intWall, { { 2, 5.5, Y2, Y2 + 8.5 } }, "Wall")
	door(doors, "z", 4, 2, 5.5, Y2, 8.5, 0.6, "a", 1, "Main Bedroom")
	wall(iw, "x", -2, 4.3, 23, Y2, C2, 0.6, ST.intWall, { { 19.2, 22.5, Y2, Y2 + 8.5 } }, "Wall")
	casedOpening(iw, "x", -2, 19.2, 22.5, Y2, 8.5, 0.6)
	wall(iw, "x", -10, 4.3, 23, Y2, C2, 0.6, ST.intWall, { { 19.2, 22.5, Y2, Y2 + 8.5 } }, "Wall")
	door(doors, "x", -10, 19.2, 22.5, Y2, 8.5, 0.6, "b", -1, "Ensuite")

	-- Roof, gravel, coping and skylight over the stairs
	rectHole(s, -35.6, 23.6, -25.6, 19.6, C2, RT, ST.ceiling, -9, -2, -5, 5, "Roof")
	rectHole(s, -35.6, 23.6, -25.6, 19.6, RT, RT + 0.12, ST.gravel, -9.4, -1.6, -5.4, 5.4, "Gravel")
	local cy1, cy2 = top, top + 0.2
	rect(s, -36.1, 24.1, -26.1, -25.5, cy1, cy2, ST.frame, "Coping")
	rect(s, -36.1, 24.1, 19.5, 20.1, cy1, cy2, ST.frame, "Coping")
	rect(s, -36.1, -35.5, -25.5, 19.5, cy1, cy2, ST.frame, "Coping")
	rect(s, 23.5, 24.1, -25.5, 19.5, cy1, cy2, ST.frame, "Coping")
	rectHole(s, -9.4, -1.6, -5.4, 5.4, RT, RT + 0.8, ST.extWhite, -9, -2, -5, 5, "SkylightCurb")
	rect(s, -9.3, -1.7, -5.3, 5.3, RT + 0.8, RT + 0.95, ST.glass, "Skylight")
	-- solar panels
	for row = 0, 1 do
		for col = 0, 4 do
			local cf = CF(7 + col * 3.6, RT + 1.0, -20 + row * 7) * ANG(rad(-12), 0, 0)
			box(s, V3(3.4, 0.15, 5.6), cf, S(RGB(30, 40, 70), MAT.glass, 0, 0.3), "SolarPanel")
			box(s, V3(3.5, 0.1, 5.7), cf * CF(0, -0.11, 0), ST.steel, "PanelFrame")
			box(s, V3(0.3, 0.8, 0.3), CF(7 + col * 3.6, RT + 0.5, -20 + row * 7), ST.steel, "Support")
		end
	end

	-- Steel columns under the cantilever corners
	for _, p in ipairs({ { -35.5, -25.5 }, { 23.5, -25.5 }, { -35.5, 19.5 } }) do
		box(s, V3(0.6, C1 - GROUND, 0.6), CF(p[1], (C1 + GROUND) / 2, p[2]), ST.frame, "Column")
	end
	-- Soffit lights under the overhangs
	for x = -33, 21, 9 do
		downlight(s, x, -23, C1, 18, 1.2)
	end
	for z = -14, 14, 9.33 do
		downlight(s, -34, z, C1, 16, 1)
	end
end

------------------------------------------------------------------------------------------
-- Floating oak staircase on a steel spine, glass balustrades and a void railing above
------------------------------------------------------------------------------------------
local function buildStair(house)
	local st = item(house, "Staircase")
	local x1, x2 = -9, -4
	local xc = (x1 + x2) / 2
	local rise, run, zStart = (Y2 - Y1) / 16, 1.5, 13
	for i = 1, 15 do
		local topY = Y1 + rise * i
		box(st, V3(x2 - x1, 0.35, run + 0.15), CF(xc, topY - 0.175, zStart - run * (i - 0.5)), ST.oak, "Tread")
	end
	local function lineY(z) -- height of the tread tops along the stair
		return Y1 + rise * ((zStart - z) / run + 0.5)
	end
	local p1, p2 = V3(xc, lineY(14) - 0.85, 14), V3(xc, lineY(-9.5) - 0.85, -9.5)
	box(st, V3(0.9, 1.0, (p2 - p1).Magnitude), CFrame.lookAt((p1 + p2) / 2, p2), ST.blackMetal, "Spine")
	for _, x in ipairs({ x1 + 0.1, x2 - 0.1 }) do
		local a, b = V3(x, lineY(14) + 1.75, 14), V3(x, lineY(-9.5) + 1.75, -9.5)
		box(st, V3(0.1, 3.3, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), ST.glass, "Balustrade")
		local ha, hb = a + V3(0, 1.75, 0), b + V3(0, 1.75, 0)
		box(st, V3(0.2, 0.2, (hb - ha).Magnitude), CFrame.lookAt((ha + hb) / 2, hb), ST.blackMetal, "Handrail")
	end
	box(st, V3(0.1, 3.2, 16), CF(-3.45, Y2 + 1.6, -1.5), ST.glass, "Railing")
	box(st, V3(0.25, 0.2, 16.2), CF(-3.45, Y2 + 3.3, -1.5), ST.blackMetal, "Handrail")
	box(st, V3(6, 3.2, 0.1), CF(-6.5, Y2 + 1.6, 6.55), ST.glass, "Railing")
	box(st, V3(6.2, 0.2, 0.25), CF(-6.5, Y2 + 3.3, 6.55), ST.blackMetal, "Handrail")
end

------------------------------------------------------------------------------------------
-- GROUND FLOOR: living room with fireplace and piano, entrance hall, kitchen, dining, WC
------------------------------------------------------------------------------------------
local function buildFireplace(parent)
	local fp = item(parent, "Fireplace", CF(-30.2, Y1, 0))
	local basalt = S(RGB(60, 58, 58), MAT.slate)
	wall(fp, "z", -30.2, -7.5, 7.5, Y1, C1, 1.6, basalt, { { -4.5, 4.5, Y1 + 1.4, Y1 + 3.2 } }, "Stone")
	box(fp, V3(0.3, 1.8, 9), CF(-30.85, Y1 + 2.3, 0), ST.black, "Firebox")
	box(fp, V3(1.3, 0.12, 9), CF(-30.2, Y1 + 1.46, 0), ST.black, "FireBed")
	box(fp, V3(0.8, 0.06, 8), CF(-30.1, Y1 + 1.55, 0), S(RGB(255, 110, 40), MAT.neon), "Embers")
	for _, z in ipairs({ -2.6, 0, 2.6 }) do
		cyl(fp, 2.4, 0.35, CF(-30.3, Y1 + 1.72, z) * ANG(0, PI / 2, 0.15), S(RGB(72, 52, 38), MAT.wood), "Log")
		local burner = box(fp, V3(0.4, 0.4, 0.4), CF(-30.3, Y1 + 1.8, z), ST.black, "FireSource")
		burner.Transparency = 1
		burner.CanCollide = false
		local fire = Instance.new("Fire")
		fire.Size = 2.4
		fire.Heat = 3
		fire.Color = RGB(255, 150, 50)
		fire.SecondaryColor = RGB(255, 70, 20)
		fire.Parent = burner
		if z == 0 then
			addLight("PointLight", burner, { color = RGB(255, 150, 70), range = 18, brightness = 1.6 })
		end
	end
	box(fp, V3(1.4, 1.2, 15), CF(-28.7, Y1 + 0.6, 0), ST.stoneLight, "Hearth")
	for i, h in ipairs({ 0.9, 1.3, 0.7 }) do
		vcyl(fp, h, 0.4, CF(-28.6, Y1 + 1.2 + h / 2, 5.2 + i * 0.5), S(RGB(250, 246, 236)), "Candle")
	end
	for i = 0, 5 do -- firewood stack
		cyl(fp, 1.2, 0.45, CF(-28.6, Y1 + 1.45 + math.floor(i / 3) * 0.42, -6.6 + (i % 3) * 0.45 + math.floor(i / 3) * 0.22), S(RGB(120, 86, 60), MAT.wood), "Firewood")
	end
	F.tv(fp, CF(-29.25, Y1 + 7.4, 0) * ANG(0, TO_EAST, 0), 10)
end

local function buildGroundFloor(house)
	local gf = item(house, "Ground Floor")

	-- Living room ---------------------------------------------------------------------
	local living = item(gf, "Living Room")
	buildFireplace(living)
	F.rug(living, CF(-21.6, Y1, 0.5), 13, 17, COL.linen, COL.charcoal)
	F.sofa(living, CF(-16.8, Y1, 0) * ANG(0, TO_WEST, 0), 12.5, { chaise = 1, pillows = { COL.mustard, COL.teal }, throw = COL.sage })
	F.coffeeTable(living, CF(-22.6, Y1, 0.5) * ANG(0, TO_WEST, 0))
	F.armchair(living, CF(-23.2, Y1, 7.9) * ANG(0, TO_FRONT, 0), COL.terracotta, COL.cream)
	F.sideTable(living, CF(-16.8, Y1, 7.7), true)
	F.floorLamp(living, CF(-14.2, Y1, -5.6))
	F.plant(living, CF(-29.6, Y1, -9.2), "fig", 1.3)
	F.plant(living, CF(-29.6, Y1, 9.2), "monstera", 1.2)
	F.piano(living, CF(-20.5, Y1, -13) * ANG(0, TO_EAST, 0))
	F.bookshelf(living, CF(-21.5, Y1, -18.3) * ANG(0, TO_BACK, 0), 9, 10.5)
	F.armchair(living, CF(-27.2, Y1, 15.2) * ANG(0, TO_EAST, 0), COL.sage, COL.mustard)
	F.floorLamp(living, CF(-29.6, Y1, 17.8))
	F.plant(living, CF(-13.6, Y1, 17.6), "olive", 1.3)
	for _, x in ipairs({ -25, -17 }) do
		for _, z in ipairs({ -14, -4, 5, 14 }) do
			downlight(living, x, z, C1)
		end
	end

	-- Entrance hall ---------------------------------------------------------------------
	local hall = item(gf, "Entrance Hall")
	F.rug(hall, CF(-3.4, Y1, -16.4), 5.5, 3.6, COL.charcoal, COL.linen)
	do
		local console = item(hall, "Console", CF(-8.2, Y1, -18.4))
		box(console, V3(3.4, 0.2, 1.2), CF(-8.2, Y1 + 2.9, -18.4), ST.walnut, "Top")
		for _, dx in ipairs({ -1.5, 1.5 }) do
			box(console, V3(0.15, 2.8, 1.0), CF(-8.2 + dx, Y1 + 1.4, -18.4), ST.brass, "Leg")
		end
		F.tableLamp(console, CF(-9.1, Y1 + 3.0, -18.5))
		vcyl(console, 0.3, 1.1, CF(-7.4, Y1 + 3.15, -18.3), ST.blackGloss, "KeyBowl")
		cyl(console, 0.06, 2.8, CF(-8.2, Y1 + 6.6, -18.94) * ANG(0, PI / 2, 0), ST.brass, "MirrorRing")
		cyl(console, 0.08, 2.5, CF(-8.2, Y1 + 6.6, -18.88) * ANG(0, PI / 2, 0), ST.mirror, "Mirror")
	end
	do
		local tbl = item(hall, "Round Table", CF(-3, Y1, -12.5))
		vcyl(tbl, 0.15, 2.2, CF(-3, Y1 + 0.075, -12.5), ST.blackGloss, "Base")
		vcyl(tbl, 2.5, 0.9, CF(-3, Y1 + 1.35, -12.5), ST.walnut, "Pedestal")
		vcyl(tbl, 0.2, 4.2, CF(-3, Y1 + 2.7, -12.5), ST.marbleTop, "Top")
		F.vase(tbl, CF(-3, Y1 + 2.8, -12.5), 1.6, RGB(30, 30, 32), { RGB(250, 250, 250), RGB(244, 206, 214), RGB(250, 232, 170) })
		F.books(tbl, CF(-1.8, Y1 + 2.8, -12.0), 3)
	end
	F.pendant(hall, -3, -12.5, C1, 4.2, "globe")
	F.plant(hall, CF(-6.5, Y1, -7.2), "fig", 1.4)
	F.plant(gf, CF(-0.6, Y1, 16.6), "olive", 1.6)
	for _, p in ipairs({ { -3, -17 }, { 0, -4 }, { 0, 6 }, { -6.5, 16 }, { 1, 16 } }) do
		downlight(hall, p[1], p[2], C1)
	end
	F.art(gf, CF(8, Y1 + 6.6, -9.62) * ANG(0, TO_BACK, 0), 6.5, 4.6, "abstract")
	do -- small lounge between the hall and the kitchen
		local lounge = item(gf, "Garden Lounge")
		F.rug(lounge, CF(5, Y1, -3), 10, 7.5, COL.sage, COL.cream)
		F.armchair(lounge, CF(1.9, Y1, -3) * ANG(0, TO_EAST, 0), COL.navy, COL.mustard)
		F.armchair(lounge, CF(8.1, Y1, -3) * ANG(0, TO_WEST, 0), COL.navy, COL.blush)
		F.sideTable(lounge, CF(5, Y1, -3), false)
		F.floorLamp(lounge, CF(5, Y1, -5.8))
	end

	-- Kitchen ------------------------------------------------------------------------------
	local kitchen = item(gf, "Kitchen")
	F.counter(kitchen, CF(20.7, Y1, -17.8) * ANG(0, TO_BACK, 0), 15.4, { sink = -1.3 })
	F.counter(kitchen, CF(29.8, Y1, -13) * ANG(0, TO_WEST, 0), 12, { cooktop = -1, oven = -1 })
	F.rangeHood(kitchen, CF(30.1, Y1, -12) * ANG(0, TO_WEST, 0), C1 - Y1)
	do -- coffee machine and kettle on the worktop
		local cm = item(kitchen, "Coffee Machine", CF(27, Y1 + 3, -18.4))
		box(cm, V3(1.2, 1.6, 1.3), CF(27, Y1 + 3.8, -18.4), ST.black, "Body")
		box(cm, V3(1.0, 0.9, 0.06), CF(27, Y1 + 4.05, -17.73), ST.steel, "Front")
		vcyl(cm, 0.45, 0.4, CF(27, Y1 + 3.25, -17.5), ST.ceramic, "Cup")
		local kt = item(kitchen, "Kettle", CF(14.6, Y1 + 3, -18.3))
		vcyl(kt, 1.0, 0.8, CF(14.6, Y1 + 3.5, -18.3), ST.steel, "Body")
		box(kt, V3(0.12, 0.6, 0.12), CF(14.6, Y1 + 3.75, -17.82), ST.black, "Handle")
		vcyl(kt, 0.1, 0.9, CF(14.6, Y1 + 3.05, -18.3), ST.black, "Base")
		F.plant(kitchen, CF(15.9, Y1 + 3, -18.5), "snake", 0.35)
	end
	for _, y in ipairs({ 5.4, 7.4 }) do
		F.floatingShelf(kitchen, CF(30.5, Y1 + y, -16.8) * ANG(0, TO_WEST, 0), 4)
		F.floatingShelf(kitchen, CF(30.5, Y1 + y, -8.9) * ANG(0, TO_WEST, 0), 3)
	end
	F.fridge(kitchen, CF(29.8, Y1, -5.3) * ANG(0, TO_WEST, 0))
	F.ovenTower(kitchen, CF(29.8, Y1, -2.2) * ANG(0, TO_WEST, 0))
	F.pantry(kitchen, CF(29.8, Y1, 0.6) * ANG(0, TO_WEST, 0))
	rect(kitchen, 28.6, 31, -7, 2, Y1 + 9, C1, ST.cabinet, "Filler")
	F.island(kitchen, CF(20, Y1, -9.5), 10, 4.2)
	for _, x in ipairs({ 17, 20, 23 }) do
		F.barStool(kitchen, CF(x, Y1, -6.7))
		F.pendant(kitchen, x, -9.5, C1, 4.6, "dome")
	end
	for _, p in ipairs({ { 16, -15 }, { 22, -15 }, { 27, -12 }, { 16, -3 }, { 24, -3 } }) do
		downlight(kitchen, p[1], p[2], C1)
	end
	do
		local clock = cyl(kitchen, 0.15, 2.4, CF(12.38, Y1 + 8, -14.5), ST.white, "Clock")
		drawTheme(clock, Enum.NormalId.Right, 1, "clock", false)
	end

	-- Dining -------------------------------------------------------------------------------
	local dining = item(gf, "Dining Room")
	F.rug(dining, CF(19, Y1, 11.5), 18, 10, COL.cream, COL.sage)
	F.diningTable(dining, CF(19, Y1, 11.5), 14, 5)
	for _, x in ipairs({ 14.5, 19, 23.5 }) do
		F.chair(dining, CF(x, Y1, 7.9) * ANG(0, TO_BACK, 0))
		F.chair(dining, CF(x, Y1, 15.1) * ANG(0, TO_FRONT, 0))
		F.placeSetting(dining, CF(x, Y1 + 2.7, 9.6) * ANG(0, TO_BACK, 0))
		F.placeSetting(dining, CF(x, Y1 + 2.7, 13.4) * ANG(0, TO_FRONT, 0))
	end
	F.chair(dining, CF(10.4, Y1, 11.5) * ANG(0, TO_EAST, 0))
	F.chair(dining, CF(27.6, Y1, 11.5) * ANG(0, TO_WEST, 0))
	F.linearPendant(dining, 19, 11.5, C1, 4.2, 10)
	do
		local sb = item(dining, "Sideboard", CF(30, Y1, 12))
		lbox(sb, CF(30, Y1, 12), -1, 1, 0.5, 2.8, -4.5, 4.5, ST.walnut, "Body")
		for i = 0, 3 do
			lbox(sb, CF(30, Y1, 12), -1.06, -1.0, 0.6, 2.7, -4.4 + i * 2.2 + 0.03, -4.4 + (i + 1) * 2.2 - 0.03, S(RGB(124, 86, 58), MAT.wood), "Door")
		end
		for _, dz in ipairs({ -3.5, 3.5 }) do
			box(sb, V3(0.3, 0.5, 0.3), CF(30, Y1 + 0.25, 12 + dz), ST.brass, "Leg")
		end
		F.tableLamp(sb, CF(30, Y1 + 2.8, 9))
		F.vase(sb, CF(30, Y1 + 2.8, 14.5), 1.2, COL.sage, { RGB(250, 250, 250), RGB(250, 220, 120) })
		F.books(sb, CF(30.1, Y1 + 2.8, 11.8), 3)
	end
	F.plant(dining, CF(30, Y1, 3.6), "monstera", 1.2)
	downlight(dining, 12, 5, C1)
	downlight(dining, 26, 5, C1)

	-- Guest WC -----------------------------------------------------------------------------
	local wc = item(gf, "Guest WC")
	F.toilet(wc, CF(9.5, Y1, -17.55) * ANG(0, TO_BACK, 0))
	F.vanity(wc, CF(10.7, Y1, -13.6) * ANG(0, TO_WEST, 0), 3.2, 1)
	F.towelRail(wc, CF(7, Y1, -10.5) * ANG(0, TO_FRONT, 0), COL.sage)
	F.plant(wc, CF(5.4, Y1, -11.4), "snake", 0.7)
	F.art(wc, CF(4.42, Y1 + 6.3, -17.6) * ANG(0, TO_EAST, 0), 2, 2.6, "botanical")
	downlight(wc, 8, -14.5, C1, 12, 0.9)
end

------------------------------------------------------------------------------------------
-- UPPER FLOOR: office, guest bedroom + bathroom, landing lounge, reading nook,
-- main suite with walk-in closet and ensuite, roof terrace
------------------------------------------------------------------------------------------
local function buildUpperFloor(house)
	local uf = item(house, "Upper Floor")

	-- Office ----------------------------------------------------------------------------
	local office = item(uf, "Office")
	F.rug(office, CF(-23.5, Y2, -19.5), 11, 8, COL.navy, COL.cream)
	F.desk(office, CF(-23.5, Y2, -23.3) * ANG(0, TO_BACK, 0), 8)
	F.officeChair(office, CF(-23.5, Y2, -20.2) * ANG(0, TO_FRONT, 0))
	F.bookshelf(office, CF(-31.5, Y2, -11.0) * ANG(0, TO_FRONT, 0), 6, 9.5)
	F.bookshelf(office, CF(-25.3, Y2, -11.0) * ANG(0, TO_FRONT, 0), 6, 9.5)
	F.armchair(office, CF(-14.4, Y2, -13.4) * ANG(0, TO_WEST, 0), COL.charcoal, COL.mustard)
	F.floorLamp(office, CF(-11.6, Y2, -11.4))
	F.plant(office, CF(-33.6, Y2, -23.6), "fig", 1.1)
	F.art(office, CF(-10.42, Y2 + 6.5, -22.3) * ANG(0, TO_WEST, 0), 3.4, 4.4, "ocean")
	for _, p in ipairs({ { -30, -18 }, { -22, -17 }, { -16, -21 }, { -29, -13 } }) do
		downlight(office, p[1], p[2], C2)
	end

	-- Guest bathroom ------------------------------------------------------------------------
	local bath2 = item(uf, "Guest Bathroom")
	F.bathtub(bath2, CF(-33.2, Y2, -4) * ANG(0, TO_EAST, 0), 6.5, 3.2)
	F.toilet(bath2, CF(-26, Y2, -8.25) * ANG(0, TO_BACK, 0))
	F.vanity(bath2, CF(-29.5, Y2, 0.7) * ANG(0, TO_FRONT, 0), 4.5, 1)
	F.towelRail(bath2, CF(-22.5, Y2, -7.2) * ANG(0, TO_WEST, 0), COL.blush)
	F.rug(bath2, CF(-29.5, Y2, -2.4), 3.6, 2.2, COL.cream, COL.cream)
	F.plant(bath2, CF(-23.6, Y2, -9), "snake", 0.8)
	downlight(bath2, -29, -6, C2, 12, 0.9)
	downlight(bath2, -26, -1, C2, 12, 0.9)

	-- Guest bedroom ---------------------------------------------------------------------------
	local bed2 = item(uf, "Guest Bedroom")
	F.rug(bed2, CF(-28.5, Y2, 9), 12, 12, COL.cream, COL.sage)
	F.bed(bed2, CF(-28.5, Y2, 7.3) * ANG(0, TO_BACK, 0), 7, 9, { throw = COL.navy, accent = COL.mustard, headboard = COL.sage })
	for _, x in ipairs({ -33.55, -23.45 }) do
		F.nightstand(bed2, CF(x, Y2, 3.7) * ANG(0, TO_BACK, 0))
	end
	F.bench(bed2, CF(-28.5, Y2, 13.1) * ANG(0, TO_BACK, 0), 6, COL.mustard)
	F.art(bed2, CF(-28.5, Y2 + 7.6, 2.42) * ANG(0, TO_BACK, 0), 6, 2.6, "abstract")
	F.closet(bed2, CF(-16.2, Y2, -8.6) * ANG(0, TO_BACK, 0), 11, 9.5)
	do -- dresser with a round mirror in the alcove
		local dr = item(bed2, "Dresser", CF(-11.3, Y2, -2.5))
		lbox(dr, CF(-11.3, Y2, -2.5), -1, 1, 0.4, 3.0, -2.6, 2.6, ST.walnut, "Body")
		for k = 0, 2 do
			lbox(dr, CF(-11.3, Y2, -2.5), -1.06, -1.0, 0.5 + k * 0.85, 1.28 + k * 0.85, -2.5, 2.5, S(RGB(124, 86, 58), MAT.wood), "Drawer")
			lbox(dr, CF(-11.3, Y2, -2.5), -1.14, -1.06, 0.95 + k * 0.85, 1.03 + k * 0.85, -0.6, 0.6, ST.brass, "Handle")
		end
		cyl(dr, 0.1, 3.4, CF(-10.25, Y2 + 5.4, -2.5), ST.brass, "MirrorRing")
		cyl(dr, 0.1, 3.1, CF(-10.33, Y2 + 5.4, -2.5), ST.mirror, "Mirror")
		F.tableLamp(dr, CF(-11.3, Y2 + 3.0, -4.4))
		F.vase(dr, CF(-11.3, Y2 + 3.0, -0.6), 1.0, COL.blush, { RGB(250, 250, 250), RGB(244, 206, 214) })
	end
	F.armchair(bed2, CF(-19, Y2, 16.2) * ANG(0, TO_EAST, 0), COL.blush, COL.sage)
	F.floorLamp(bed2, CF(-21.6, Y2, 18.1))
	F.plant(bed2, CF(-34, Y2, 18), "monstera", 1.1)
	for _, p in ipairs({ { -28.5, 15 }, { -16, -3 }, { -16, 8 } }) do
		downlight(bed2, p[1], p[2], C2)
	end

	-- Landing lounge, gallery and reading nook ------------------------------------------------
	local landing = item(uf, "Landing")
	F.rug(landing, CF(-2.5, Y2, -18.5), 11, 9, COL.cream, COL.charcoal)
	F.sofa(landing, CF(-2.5, Y2, -15.2) * ANG(0, TO_FRONT, 0), 8, { color = RGB(96, 102, 110), pillows = { COL.mustard, COL.blush } })
	F.coffeeTable(landing, CF(-2.5, Y2, -19.6))
	F.plant(landing, CF(-8.4, Y2, -23.8), "fig", 1.2)
	F.plant(landing, CF(2.6, Y2, -23.8), "monstera", 1)
	F.art(landing, CF(3.58, Y2 + 6.2, -17) * ANG(0, TO_WEST, 0), 5, 6, "botanical")
	F.art(landing, CF(3.58, Y2 + 6.2, 12) * ANG(0, TO_WEST, 0), 4, 5, "arches")
	F.armchair(landing, CF(-6.8, Y2, 14.6) * ANG(0, TO_BACK, 0), COL.mustard, COL.navy)
	F.floorLamp(landing, CF(-4.6, Y2, 17.6))
	F.bookshelf(landing, CF(-9.0, Y2, 8.8) * ANG(0, TO_EAST, 0), 3.6, 9)
	F.plant(landing, CF(2.4, Y2, 17.8), "olive", 1.1)
	for _, p in ipairs({ { -5, -21 }, { 1, -21 }, { -6, -13 }, { 0, -4 }, { 0, 4 }, { 0, 12 }, { -7, 12 } }) do
		downlight(landing, p[1], p[2], C2)
	end

	-- Main bedroom ------------------------------------------------------------------------------
	local master = item(uf, "Main Bedroom")
	F.rug(master, CF(11.5, Y2, 5), 14, 13, COL.cream, RGB(196, 178, 156))
	F.bed(master, CF(11.5, Y2, 3.55) * ANG(0, TO_BACK, 0), 8.5, 9.5, { headboard = RGB(196, 178, 156), throw = COL.terracotta, accent = COL.teal })
	for _, x in ipairs({ 5.9, 17.1 }) do
		F.nightstand(master, CF(x, Y2, -0.3) * ANG(0, TO_BACK, 0))
		F.pendant(master, x, -0.3, C2, 5.2, "globe")
	end
	F.art(master, CF(11.5, Y2 + 7.8, -1.58) * ANG(0, TO_BACK, 0), 7, 3.2, "sunset")
	F.bench(master, CF(11.5, Y2, 9.9) * ANG(0, TO_BACK, 0), 7, COL.blush)
	F.sideTable(master, CF(17.5, Y2, 16.2), false)
	F.armchair(master, CF(14.4, Y2, 16.2) * ANG(0, TO_EAST, 0), COL.cream, COL.terracotta)
	F.armchair(master, CF(20.6, Y2, 16.2) * ANG(0, TO_WEST, 0), COL.cream, COL.teal)
	F.plant(master, CF(5.6, Y2, 17.6), "fig", 1.3)
	for _, p in ipairs({ { 8, 12 }, { 16, 10 }, { 20, 4 } }) do
		downlight(master, p[1], p[2], C2)
	end

	-- Linen curtains beside the floor-to-ceiling bedroom windows
	for _, x in ipairs({ -34.0, -13.0, 5.2, 21.8 }) do
		local curtain = item(x < 0 and bed2 or master, "Curtain", CF(x, Y2, 18.6))
		box(curtain, V3(1.8, Y2 + 10.4 - Y2 - 0.1, 0.25), CF(x, Y2 + 5.15, 18.55), S(RGB(236, 230, 218), MAT.fabric), "Curtain")
		for k = -1, 1 do
			box(curtain, V3(0.12, 10.2, 0.32), CF(x + k * 0.55, Y2 + 5.15, 18.55), S(RGB(226, 220, 206), MAT.fabric), "Fold")
		end
	end
	cyl(bed2, 21.4, 0.12, CF(-23.5, Y2 + 10.45, 18.5), ST.blackMetal, "CurtainRod")
	cyl(master, 17.6, 0.12, CF(13.5, Y2 + 10.45, 18.5), ST.blackMetal, "CurtainRod")

	-- Walk-in closet --------------------------------------------------------------------------
	local closet = item(uf, "Walk-in Closet")
	F.closet(closet, CF(12.4, Y2, -8.6) * ANG(0, TO_BACK, 0), 12.4, 10)
	F.closet(closet, CF(12.4, Y2, -3.4) * ANG(0, TO_FRONT, 0), 12.4, 10)
	F.rug(closet, CF(12.4, Y2, -6), 11, 2.4, COL.blush, COL.cream)
	box(closet, V3(0.1, 7.2, 2.6), CF(4.38, Y2 + 4, -6), ST.brass, "MirrorFrame")
	box(closet, V3(0.1, 7, 2.4), CF(4.45, Y2 + 4, -6), ST.mirror, "Mirror")
	for _, x in ipairs({ 8, 16, 21 }) do
		downlight(closet, x, -6, C2, 12, 0.9)
	end

	-- Ensuite -----------------------------------------------------------------------------------
	local ens = item(uf, "Ensuite")
	F.vanity(ens, CF(5.3, Y2, -17.5) * ANG(0, TO_EAST, 0), 9, 2)
	F.bathtub(ens, CF(12.5, Y2, -21.9), 7, 3.4)
	F.toilet(ens, CF(9, Y2, -11.75) * ANG(0, TO_FRONT, 0))
	F.towelRail(ens, CF(14, Y2, -10.5) * ANG(0, TO_FRONT, 0), COL.cream)
	F.rug(ens, CF(12.5, Y2, -18.8), 4, 2.2, COL.cream, COL.cream)
	F.plant(ens, CF(6.8, Y2, -24), "monstera", 0.9)
	do -- walk-in shower
		local sh = item(ens, "Shower", CF(20.2, Y2, -22))
		local zellige = S(RGB(84, 130, 114), MAT.tiles)
		rect(sh, 17.3, 23, -25, -19, Y2, Y2 + 0.08, S(RGB(70, 72, 74), MAT.slate), "ShowerTray")
		rect(sh, 22.9, 23, -25, -22, Y2, C2 - 0.5, zellige, "Tiles")
		rect(sh, 22.9, 23, -22, -19, Y2, Y2 + 5.8, zellige, "Tiles")
		rect(sh, 17.3, 22.9, -25, -24.9, Y2, C2 - 0.5, zellige, "Tiles")
		rect(sh, 17.25, 17.35, -25, -21.2, Y2, Y2 + 8.5, ST.glass, "Screen")
		rect(sh, 17.3, 23, -19.05, -18.95, Y2, Y2 + 8.5, ST.glass, "Screen")
		rect(sh, 17.2, 23, -19.1, -18.9, Y2 + 8.5, Y2 + 8.65, ST.blackMetal, "ScreenFrame")
		rect(sh, 17.2, 17.4, -25, -18.9, Y2 + 8.5, Y2 + 8.65, ST.blackMetal, "ScreenFrame")
		rect(sh, 20.1, 20.3, -24.9, -22.8, C2 - 1.4, C2 - 1.2, ST.blackMetal, "ShowerArm")
		rect(sh, 19.4, 21, -23.6, -22, C2 - 1.5, C2 - 1.4, ST.blackMetal, "RainHead")
		rect(sh, 17.6, 22.6, -24.9, -24.6, Y2 + 4, Y2 + 4.12, ST.blackMetal, "Niche")
		for i, c in ipairs({ RGB(250, 250, 250), RGB(214, 196, 170), RGB(40, 40, 44) }) do
			vcyl(sh, 0.7, 0.35, CF(18.3 + i * 0.5, Y2 + 4.47, -24.75), S(c), "Bottle")
		end
	end
	for _, p in ipairs({ { 8, -14 }, { 12.5, -21.5 }, { 20.2, -22 }, { 15, -14 } }) do
		downlight(ens, p[1], p[2], C2, 12, 0.9)
	end

	-- Roof terrace ------------------------------------------------------------------------------
	local ter = item(uf, "Roof Terrace")
	box(ter, V3(0.1, 3.2, 39.8), CF(31.85, Y2 + 1.6, 0), ST.glass, "Railing")
	box(ter, V3(0.25, 0.2, 40), CF(31.85, Y2 + 3.3, 0), ST.blackMetal, "Handrail")
	for _, z in ipairs({ -19.85, 19.85 }) do
		box(ter, V3(7.8, 3.2, 0.1), CF(28, Y2 + 1.6, z), ST.glass, "Railing")
		box(ter, V3(8, 0.2, 0.25), CF(28, Y2 + 3.3, z), ST.blackMetal, "Handrail")
	end
	for _, z in ipairs({ -12, -7 }) do
		F.lounger(ter, CF(27.9, Y2, z) * ANG(0, TO_EAST, 0), z == -12 and COL.teal or COL.mustard)
	end
	F.sideTable(ter, CF(28, Y2, -9.5), false)
	for _, z in ipairs({ -18.2, 18.2 }) do
		rect(ter, 24.2, 26.6, z - 1.2, z + 1.2, Y2, Y2 + 2.2, S(RGB(120, 118, 114), MAT.concrete), "Planter")
		F.grass(ter, CF(25.4, Y2 + 2.2, z), 1.1)
	end
	do -- bistro set
		local bistro = item(ter, "Bistro Set", CF(29, Y2, 16))
		vcyl(bistro, 0.15, 3, CF(29, Y2 + 2.5, 16), ST.teak, "Top")
		vcyl(bistro, 2.4, 0.2, CF(29, Y2 + 1.2, 16), ST.blackMetal, "Stem")
		vcyl(bistro, 0.1, 1.4, CF(29, Y2 + 0.05, 16), ST.blackMetal, "Base")
		F.chair(bistro, CF(26.9, Y2, 16) * ANG(0, TO_EAST, 0), { frame = ST.teak, color = COL.cream })
		F.chair(bistro, CF(29, Y2, 13.9) * ANG(0, TO_BACK, 0), { frame = ST.teak, color = COL.cream })
	end
	for _, z in ipairs({ -3, 16 }) do
		box(ter, V3(0.5, 1.2, 0.6), CF(24.25, Y2 + 6.5, z), ST.blackMetal, "WallLight")
		local glow = box(ter, V3(0.06, 0.9, 0.4), CF(24.52, Y2 + 6.5, z), ST.lamp, "Glow")
		addLight("PointLight", glow, { range = 12, brightness = 0.8 })
	end
end

------------------------------------------------------------------------------------------
-- FRONT GARDEN: lawn, entrance steps, path, boundary wall, hedges, driveway, carport, car
------------------------------------------------------------------------------------------
local LOT = { x1 = -66, x2 = 66, z1 = -66, z2 = 70 }

local function flowerBed(parent, x1, x2, z1, z2, colors)
	local bed = item(parent, "Flower Bed")
	rect(bed, x1, x2, z1, z2, GROUND - 0.2, GROUND + 0.15, ST.soil, "Soil")
	local x = x1 + 1.2
	while x < x2 - 0.8 do
		local z = z1 + (z2 - z1) * rng:NextNumber(0.3, 0.7)
		local r = rng:NextNumber()
		if r < 0.45 then
			F.bush(bed, CF(x, GROUND, z), rng:NextNumber(0.7, 1.0), colors[rng:NextInteger(1, #colors)])
		elseif r < 0.7 then
			F.grass(bed, CF(x, GROUND, z), rng:NextNumber(0.8, 1.1))
		else
			F.bush(bed, CF(x, GROUND, z), rng:NextNumber(0.8, 1.1))
		end
		x += rng:NextNumber(1.8, 2.8)
	end
	return bed
end

local function buildFrontGarden(house)
	local g = item(house, "Front Garden")
	rect(g, LOT.x1, LOT.x2, LOT.z1, LOT.z2, GROUND - 1, GROUND, ST.lawn, "Lawn")

	-- Entrance platform and steps
	rect(g, -14, 8, -28, -20, 0, Y1, ST.stoneLight, "Porch")
	for k = 1, 4 do
		local topY = Y1 - k * 0.78
		rect(g, -10, 4, -28 - 1.5 * k, -28 - 1.5 * (k - 1), 0, topY, ST.stoneLight, "Step")
	end
	for _, x in ipairs({ -12.5, 6.5 }) do -- planters flanking the steps
		rect(g, x - 1.5, x + 1.5, -34, -29, 0, 2.6, S(RGB(120, 118, 114), MAT.concrete), "Planter")
		F.plant(g, CF(x, 2.6 - 1.6, -31.5), "olive", 1.3)
	end

	-- Stepping-stone path to the gate, lined with garden lights
	local pz = -35.8
	local i = 0
	while pz > -63 do
		rect(g, -6, 0, pz - 1.25, pz + 1.25, GROUND - 0.3, GROUND + 0.12, ST.stoneLight, "Paver")
		if i % 2 == 0 then
			F.bollard(g, CF(i % 4 == 0 and -7.6 or 1.6, GROUND, pz))
		end
		pz -= 3.6
		i += 1
	end

	-- Front boundary wall with gate pillars, lanterns, mailbox and house number
	local wallSt, copeSt = ST.stoneLight, S(RGB(70, 70, 72))
	for _, seg in ipairs({ { -66, -7.5 }, { 1.5, 33 }, { 58, 66 } }) do
		rect(g, seg[1], seg[2], -65.6, -64.4, GROUND, GROUND + 2.8, wallSt, "BoundaryWall")
		rect(g, seg[1], seg[2], -65.75, -64.25, GROUND + 2.8, GROUND + 3.05, copeSt, "Coping")
	end
	for _, x in ipairs({ -8.25, 2.25, 32.25, 58.75 }) do
		rect(g, x - 0.85, x + 0.85, -65.85, -64.15, GROUND, GROUND + 4.4, wallSt, "Pillar")
		rect(g, x - 1, x + 1, -66, -64, GROUND + 4.4, GROUND + 4.65, copeSt, "Cap")
		local lantern = box(g, V3(0.8, 1.1, 0.8), CF(x, GROUND + 5.2, -65), S(RGB(255, 236, 200), MAT.neon), "Lantern")
		box(g, V3(1.0, 0.15, 1.0), CF(x, GROUND + 5.82, -65), ST.blackMetal, "LanternCap")
		addLight("PointLight", lantern, { range = 12, brightness = 0.9 })
	end
	do
		local sign = box(g, V3(1.2, 1.0, 0.1), CF(-8.25, GROUND + 3.2, -65.9), ST.blackMetal, "HouseNumber")
		label(surfaceGui(sign, Enum.NormalId.Front, false), CONFIG.HouseNumber, RGB(214, 176, 100), "GothamBold")
		local mail = item(g, "Mailbox", CF(2.25, GROUND, -66.5))
		box(mail, V3(1.2, 1.3, 0.9), CF(2.25, GROUND + 2.8, -66.3), ST.blackMetal, "Box")
		box(mail, V3(0.8, 0.08, 0.05), CF(2.25, GROUND + 3.15, -66.77), ST.brass, "Slot")
	end

	-- Hedges along the sides and the back
	rect(g, LOT.x1, LOT.x1 + 2.2, -64, LOT.z2, GROUND, GROUND + 7, ST.hedge, "Hedge")
	rect(g, LOT.x2 - 2.2, LOT.x2, -64, LOT.z2, GROUND, GROUND + 7, ST.hedge, "Hedge")
	rect(g, LOT.x1 + 2.2, LOT.x2 - 2.2, LOT.z2 - 2.2, LOT.z2, GROUND, GROUND + 7, ST.hedge, "Hedge")
	rect(g, -64, -9, -63.8, -62, GROUND, GROUND + 2.2, ST.hedge, "LowHedge")
	rect(g, 3.5, 31, -63.8, -62, GROUND, GROUND + 2.2, ST.hedge, "LowHedge")

	-- Planting along the facade and the front lawn
	flowerBed(g, -34, -15, -27, -21.5, { RGB(250, 250, 250), RGB(180, 140, 220) })
	flowerBed(g, 9.5, 31, -27, -21.5, { RGB(250, 250, 250), RGB(240, 180, 200) })
	flowerBed(g, -60, -40, -61, -57, { RGB(250, 220, 100), RGB(250, 250, 250) })
	flowerBed(g, 8, 28, -61, -57, { RGB(200, 120, 200), RGB(250, 250, 250) })
	F.tree(g, CF(-24, GROUND, -44), "maple", 1.05)
	F.tree(g, CF(-50, GROUND, -36), nil, 1.2)
	F.tree(g, CF(19, GROUND, -46), "blossom", 1.0)
	F.cypress(g, CF(-60, GROUND, -12), 1.2)
	F.cypress(g, CF(-60, GROUND, 2), 1.1)
	for _, p in ipairs({ { -24, -40 }, { 19, -42 }, { -50, -32 } }) do
		F.uplight(g, CF(p[1], GROUND, p[2]))
	end
	for _, p in ipairs({ { -40, -50, 2.2 }, { -37.5, -48.6, 1.4 }, { 26, -36, 1.8 } }) do
		ball(g, p[3], CF(p[1], GROUND + p[3] * 0.25, p[2]), S(RGB(130, 128, 124), MAT.slate), "Boulder")
	end

	-- Driveway and carport
	rect(g, 35, 55, -64.4, 8, GROUND - 0.3, GROUND + 0.12, ST.pavement, "Driveway")
	local cp = item(g, "Carport")
	for _, p in ipairs({ { 35.2, -19.5 }, { 54.8, -19.5 }, { 35.2, 7.5 }, { 54.8, 7.5 } }) do
		box(cp, V3(0.6, 13 - GROUND, 0.6), CF(p[1], (13 + GROUND) / 2, p[2]), ST.frame, "Column")
	end
	rect(cp, 34, 56, -20.8, 8.8, 13, 14, ST.extWhite, "Roof")
	rect(cp, 34.4, 55.6, -20.4, 8.4, 12.75, 13, ST.cedar, "Ceiling")
	for _, z in ipairs({ -13, -1 }) do
		downlight(cp, 45, z, 12.75, 16, 1)
	end
	F.car(g, CF(45, GROUND + 0.12, -4) * ANG(0, TO_FRONT, 0), RGB(24, 44, 78))
	F.bollard(g, CF(33.5, GROUND, -30))
	F.bollard(g, CF(56.5, GROUND, -30))
end

------------------------------------------------------------------------------------------
-- BACK GARDEN: timber deck, outdoor lounge and dining, pool terrace, fire pit, planting
------------------------------------------------------------------------------------------
local function stringLights(parent, a, b, sag, bulbs)
	local prev = a
	for i = 1, bulbs + 1 do
		local t = i / (bulbs + 1)
		local p = a:Lerp(b, t) - V3(0, sag * 4 * t * (1 - t), 0)
		box(parent, V3(0.05, 0.05, (p - prev).Magnitude), CFrame.lookAt((p + prev) / 2, p), ST.black, "Wire")
		if i <= bulbs then
			local bulb = ball(parent, 0.35, CF(p.X, p.Y - 0.25, p.Z), ST.lamp, "Bulb")
			if i % 3 == 2 then
				addLight("PointLight", bulb, { range = 9, brightness = 0.6 })
			end
		end
		prev = p
	end
end

local function buildBackGarden(house)
	local g = item(house, "Back Garden")

	-- Timber deck along the back of the house + steps to the lawn
	rect(g, -36, 32, 20, 34, Y1 - 0.4, Y1, ST.deck, "Deck")
	rect(g, -35.6, 31.6, 20, 33.6, 0, Y1 - 0.4, S(RGB(64, 62, 60), MAT.concrete), "DeckBase")
	for k = 1, 4 do
		rect(g, -34, -20, 34 + 1.5 * (k - 1), 34 + 1.5 * k, 0, Y1 - 0.78 * k, ST.deck, "Step")
	end
	for _, x in ipairs({ -31.2, -10.4, 4.6, 31.2 }) do -- wall lights on the piers
		box(g, V3(0.6, 1.4, 0.4), CF(x, Y1 + 8, 20.2), ST.blackMetal, "WallLight")
		local glow = box(g, V3(0.5, 0.06, 0.3), CF(x, Y1 + 7.27, 20.2), ST.lamp, "Glow")
		addLight("SpotLight", glow, { face = Enum.NormalId.Bottom, angle = 70, range = 12, brightness = 1 })
	end

	-- Outdoor lounge in front of the living room
	local lounge = item(g, "Outdoor Lounge")
	F.rug(lounge, CF(-24, Y1, 27.5), 14, 9, RGB(214, 206, 190), RGB(70, 72, 76))
	F.sofa(lounge, CF(-24, Y1, 23.6) * ANG(0, TO_BACK, 0), 10, { color = RGB(236, 230, 218), pillows = { COL.teal, COL.mustard } })
	F.coffeeTable(lounge, CF(-24, Y1, 28.4))
	F.armchair(lounge, CF(-31.2, Y1, 29) * ANG(0, TO_EAST, 0), RGB(236, 230, 218), COL.terracotta)
	F.armchair(lounge, CF(-16.8, Y1, 29) * ANG(0, TO_WEST, 0), RGB(236, 230, 218), COL.teal)
	for _, x in ipairs({ -35, -13.5 }) do
		rect(lounge, x - 1, x + 1, 31.6, 33.6, Y1, Y1 + 1.8, S(RGB(120, 118, 114), MAT.concrete), "Planter")
		F.grass(lounge, CF(x, Y1 + 1.8, 32.6), 1)
	end

	-- Outdoor dining under a pergola, plus a barbecue
	local din = item(g, "Outdoor Dining")
	F.outdoorTable(din, CF(17, Y1, 27.5), 10, 4, 3)
	for _, p in ipairs({ { 10.5, 22.2 }, { 23.5, 22.2 }, { 10.5, 32.8 }, { 23.5, 32.8 } }) do
		box(din, V3(0.5, 10.6, 0.5), CF(p[1], Y1 + 5.3, p[2]), ST.blackMetal, "Post")
	end
	for _, z in ipairs({ 22.2, 32.8 }) do
		box(din, V3(14, 0.6, 0.4), CF(17, Y1 + 10.6, z), ST.blackMetal, "Beam")
	end
	for i = 0, 11 do
		box(din, V3(0.3, 0.5, 11.6), CF(10.9 + i * 1.2, Y1 + 11.15, 27.5), ST.teak, "Slat")
	end
	stringLights(din, V3(10.5, Y1 + 10.2, 27.5), V3(23.5, Y1 + 10.2, 27.5), 1.0, 7)
	do
		local bbq = item(din, "Barbecue", CF(30, Y1, 27))
		rect(bbq, 28.6, 31.4, 24, 30, Y1, Y1 + 3, S(RGB(88, 86, 84), MAT.slate), "Counter")
		rect(bbq, 28.5, 31.5, 23.9, 30.1, Y1 + 3, Y1 + 3.2, ST.marbleTop, "Top")
		rect(bbq, 28.9, 31.1, 25, 28.5, Y1 + 3.2, Y1 + 3.6, ST.steel, "Grill")
		box(bbq, V3(2.2, 0.9, 3.5), CF(31.1, Y1 + 3.6, 26.75) * ANG(0, 0, rad(-55)) * CF(-1.1, 0.45, 0), ST.steel, "Lid")
		rect(bbq, 28.4, 28.5, 24.5, 29.5, Y1 + 1.2, Y1 + 2.6, ST.steel, "Door")
	end

	-- Pool terrace (stone), pool and loungers
	local pool = item(g, "Pool")
	rectHole(pool, -16, 32, 34, 62, 0, Y1, ST.stoneLight, -8.3, 24.3, 39.7, 52.3, "PoolTerrace")
	rect(pool, -8.3, 24.3, 39.7, 52.3, GROUND, GROUND + 0.4, ST.poolTile, "PoolFloor")
	local wy1, wy2 = GROUND + 0.4, Y1 - 0.1
	rect(pool, -8.3, 24.3, 39.7, 40, wy1, wy2, ST.poolTile, "PoolWall")
	rect(pool, -8.3, 24.3, 52, 52.3, wy1, wy2, ST.poolTile, "PoolWall")
	rect(pool, -8.3, -8, 40, 52, wy1, wy2, ST.poolTile, "PoolWall")
	rect(pool, 24, 24.3, 40, 52, wy1, wy2, ST.poolTile, "PoolWall")
	rectHole(pool, -9.3, 25.3, 38.7, 53.3, Y1 - 0.2, Y1 + 0.1, ST.coping, -8.1, 24.1, 39.9, 52.1, "Coping")
	for k = 1, 3 do
		rect(pool, -8, -8 + 1.3 * k, 42, 50, wy1, Y1 - 0.4 - 0.8 * k, ST.coping, "PoolStep")
	end
	local water = rect(pool, -8, 24, 40, 52, wy1, Y1 - 0.5, ST.water, "Water")
	water.CanCollide = false
	for _, x in ipairs({ 0, 8, 16 }) do
		for _, z in ipairs({ 40.03, 51.97 }) do
			local l = box(pool, V3(0.9, 0.9, 0.06), CF(x, GROUND + 2, z), S(RGB(210, 245, 255), MAT.neon), "PoolLight")
			addLight("PointLight", l, { color = RGB(150, 225, 255), range = 12, brightness = 1.3 })
		end
	end
	for _, x in ipairs({ 0, 16 }) do
		for _, dx in ipairs({ -1.6, 1.6 }) do
			F.lounger(pool, CF(x + dx, Y1, 57.0) * ANG(0, TO_FRONT, 0), dx < 0 and COL.teal or RGB(244, 240, 230))
		end
		F.parasol(pool, CF(x, Y1, 61.1), RGB(244, 240, 230))
	end
	for _, p in ipairs({ { 28.2, 41 }, { 28.2, 56 } }) do
		vcyl(pool, 1.2, 3.4, CF(p[1], Y1 + 0.6, p[2]), S(RGB(120, 118, 114), MAT.concrete), "Planter")
		F.palm(pool, CF(p[1], Y1 + 1.2, p[2]), 1.1)
		F.uplight(pool, CF(p[1] + 1.4, Y1, p[2] - 1.4))
	end
	for _, p in ipairs({ { -14, 36 }, { -14, 60 } }) do
		F.plant(pool, CF(p[1], Y1, p[2]), "olive", 1.4)
	end
	for k = 1, 4 do -- steps down to the fire-pit lawn
		rect(pool, -16 - 1.5 * k, -16 - 1.5 * (k - 1), 43, 49, 0, Y1 - 0.78 * k, ST.stoneLight, "Step")
	end

	-- Fire pit with lounge chairs and festoon lights
	local pit = item(g, "Fire Pit", CF(-40, GROUND, 52))
	local c = V3(-40, GROUND, 52)
	vcyl(pit, 0.12, 24, CF(c.X, GROUND + 0.06, c.Z), ST.gravel, "Gravel")
	vcyl(pit, 1.4, 5, CF(c.X, GROUND + 0.7, c.Z), S(RGB(110, 108, 104), MAT.slate), "Bowl")
	vcyl(pit, 0.1, 3.9, CF(c.X, GROUND + 1.42, c.Z), ST.black, "Ash")
	for i = 1, 3 do
		cyl(pit, 2.6, 0.35, CF(c.X, GROUND + 1.6, c.Z) * ANG(0, i * PI / 3, 0.2), S(RGB(72, 52, 38), MAT.wood), "Log")
	end
	local flame = box(pit, V3(0.5, 0.5, 0.5), CF(c.X, GROUND + 1.8, c.Z), ST.black, "FireSource")
	flame.Transparency = 1
	flame.CanCollide = false
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 6
	fire.Color = RGB(255, 150, 50)
	fire.SecondaryColor = RGB(255, 70, 20)
	fire.Parent = flame
	addLight("PointLight", flame, { color = RGB(255, 150, 70), range = 20, brightness = 1.8 })
	for i = 0, 3 do
		F.armchair(pit, CF(c.X, GROUND + 0.12, c.Z) * ANG(0, PI / 4 + i * PI / 2, 0) * CF(0, 0, 6.6), RGB(236, 230, 218), ({ COL.teal, COL.mustard, COL.terracotta, COL.sage })[i + 1])
	end
	local posts = {}
	for i = 0, 3 do
		local a = i * PI / 2
		local p = c + V3(math.cos(a) * 10.5, 0, math.sin(a) * 10.5)
		box(pit, V3(0.35, 9.5, 0.35), CF(p.X, GROUND + 4.75, p.Z), ST.blackMetal, "Post")
		posts[i + 1] = V3(p.X, GROUND + 9.3, p.Z)
	end
	for i = 1, 4 do
		stringLights(pit, posts[i], posts[i % 4 + 1], 1.6, 8)
	end

	-- Trees, planting and lights around the back lawn
	F.tree(g, CF(-56, GROUND, 28), nil, 1.25)
	F.tree(g, CF(-28, GROUND, 63), "blossom", 1.05)
	F.tree(g, CF(-57, GROUND, 63), "maple", 0.9)
	F.tree(g, CF(46, GROUND, 30), nil, 1.15)
	F.tree(g, CF(52, GROUND, 58), "blossom", 1.1)
	F.cypress(g, CF(38, GROUND, 64), 1.3)
	F.cypress(g, CF(60, GROUND, 14), 1.2)
	for _, p in ipairs({ { -56, 24 }, { 46, 26 }, { -28, 59 } }) do
		F.uplight(g, CF(p[1], GROUND, p[2]))
	end
	flowerBed(g, -60, -30, 64.4, 67.6, { RGB(250, 250, 250), RGB(180, 140, 220) })
	flowerBed(g, 36, 62, 64.4, 67.6, { RGB(250, 220, 100), RGB(240, 180, 200) })
	F.bench(g, CF(52, GROUND, 44) * ANG(0, TO_WEST, 0), 6, RGB(236, 230, 218))
	for k, p in ipairs({ { -28, 42 }, { -30.4, 44.6 }, { -32.2, 47.4 } }) do -- stepping stones to the fire pit
		rect(g, p[1] - 1.1, p[1] + 1.1, p[2] - 0.9, p[2] + 0.9, GROUND - 0.3, GROUND + 0.1 + k * 0.001, ST.stoneLight, "SteppingStone")
	end
	F.bollard(g, CF(-20, GROUND, 40.5))
	F.bollard(g, CF(-34.5, GROUND, 40.5))
end

------------------------------------------------------------------------------------------
-- Interactive doors: a Script inside the villa that adds an "Open" prompt to every door
------------------------------------------------------------------------------------------
local DOOR_SCRIPT = [==[
-- Created by the Luxury Villa builder. Adds an Open/Close prompt (key E) to every door.
local TweenService = game:GetService("TweenService")
local INFO = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local function setup(door)
	local root = door.PrimaryPart
	if not root then
		return
	end
	local closed = door:GetPivot()
	local open
	local slide = door:GetAttribute("SlideOffset")
	if slide then
		open = closed * CFrame.new(slide)
	else
		local hinge = closed * CFrame.new(door:GetAttribute("HingeOffset") or Vector3.zero)
		local angle = math.rad(door:GetAttribute("OpenAngle") or 90)
		open = hinge * CFrame.Angles(0, angle, 0) * hinge:ToObjectSpace(closed)
	end
	local value = Instance.new("CFrameValue")
	value.Value = closed
	value.Changed:Connect(function(cf)
		door:PivotTo(cf)
	end)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = door:GetAttribute("Label") or "Door"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	local isOpen = false
	prompt.Triggered:Connect(function()
		isOpen = not isOpen
		prompt.ActionText = isOpen and "Close" or "Open"
		TweenService:Create(value, INFO, { Value = isOpen and open or closed }):Play()
	end)
end

for _, d in ipairs(script.Parent:GetDescendants()) do
	if d:IsA("Model") and d:GetAttribute("Door") then
		setup(d)
	end
end
]==]

------------------------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------------------------
local function groundHeight(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local hit = Workspace:Raycast(V3(x, 1000, z), V3(0, -2000, 0), params)
	return hit and hit.Position.Y or 0
end

local function chooseOrigin(previous)
	if previous then
		return previous:GetPivot()
	end
	local camera = Workspace.CurrentCamera
	if CONFIG.BuildInFrontOfCamera and camera then
		local camCF = camera.CFrame
		local look = camCF.LookVector
		local yaw = 0
		if math.abs(look.X) + math.abs(look.Z) > 1e-3 then
			yaw = math.atan2(-look.X, -look.Z)
		end
		yaw = math.floor(yaw / (PI / 2) + 0.5) * (PI / 2) -- snap to the grid
		local forward = ANG(0, yaw, 0).LookVector
		local centre = camCF.Position + forward * (-LOT.z1 + 40)
		local x, z = math.floor(centre.X + 0.5), math.floor(centre.Z + 0.5)
		return CF(x, groundHeight(x, z), z) * ANG(0, yaw + PI, 0) -- front faces the camera
	end
	local p = CONFIG.Position
	return CF(p.X, p.Y, p.Z) * ANG(0, rad(CONFIG.RotationY), 0)
end

------------------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------------------
local started = os.clock()
local previous = Workspace:FindFirstChild(CONFIG.Name)
if not (CONFIG.ReplacePrevious and previous and previous:IsA("Model")) then
	previous = nil
end

local recording
pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("BuildLuxuryVilla", "Build Luxury Villa")
end)

local house = Instance.new("Model")
house.Name = CONFIG.Name

local ok, err = pcall(function()
	ORIGIN = chooseOrigin(previous)
	local doors = item(house, "Doors")
	buildStructure(house, doors)
	buildStair(house)
	buildGroundFloor(house)
	buildUpperFloor(house)
	buildFrontGarden(house)
	buildBackGarden(house)
	for _, p in ipairs(pivots) do
		p[1].WorldPivot = ORIGIN * p[2]
	end
	house.WorldPivot = ORIGIN
	if CONFIG.InteractiveDoors then
		local okScript = pcall(function()
			local s = Instance.new("Script")
			s.Name = "VillaDoors"
			s.Source = DOOR_SCRIPT
			s.Parent = house
		end)
		if not okScript then
			warn("[Villa] Could not add the door script; doors will stay closed in Play mode.")
		end
	end
	if previous then
		previous.Parent = nil
	end
	house.Parent = Workspace
end)

if not ok then
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
	end
	house:Destroy()
	error("[Villa] Build failed: " .. tostring(err), 0)
end

if CONFIG.ClockTime then
	Lighting.ClockTime = CONFIG.ClockTime
end
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
else
	pcall(function()
		ChangeHistoryService:SetWaypoint("Build Luxury Villa")
	end)
end
pcall(function()
	Selection:Set({ house })
end)
print(string.format("[Villa] Built %s with %d parts in %.2f s. Press F to focus the camera on it.", CONFIG.Name, partCount, os.clock() - started))
return house -- lets the script also run as a ModuleScript via require()
