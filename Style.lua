local addonName, ns = ...

-- Button visuals. Three looks:
--   grimoire: Grimoire's own art (Media/, drawn by tools/art/draw.py): iron-rimmed round
--             buttons and the tome in a bezel whose sockets light up with soul shards.
--   round:    flat round buttons with a thin rim and an accent halo.
--   square:   ElvUI's own action-button style when ElvUI is loaded, else a thin border.
-- The ring layout uses grimoire or round (the "Ring style" option); the bar is square.
-- Colors, fonts and the glow follow ElvUI's settings when it's loaded, so Grimoire
-- matches the rest of the UI. The look is fixed at login; changing it asks for a reload.

local Style = {}
ns.Style = Style

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SOFT_GLOW = "Interface\\Buttons\\UI-Common-MouseHilight"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local RIM = 2 -- rim thickness in pixels (round)
local MEDIA = "Interface\\AddOns\\Grimoire\\Media\\"
local ART_ICON_INSET = 0.115 -- icon inset inside Rim.tga, as a fraction of the button size
local PIPS = 20              -- shard sockets in Grimoire.tga
local PIP_RADIUS = 115 / 256 -- socket ring radius, as a fraction of the tome's size
local WELL_INSET = (128 - 92) / 256 -- inner well of the bezel, for the mana fill

-- Theme ------------------------------------------------------------------------

-- ElvUI.lua replaces these with ElvUI-aware versions.
Style.theme = {
	accent = { 0.58, 0.51, 0.79 },      -- warlock purple
	border = { 0, 0, 0 },
	font = STANDARD_TEXT_FONT,
	outline = "OUTLINE",
	noPower = { 0.5, 0.5, 1 },
	notUsable = { 0.4, 0.4, 0.4 },
	mana = { 0.31, 0.45, 0.63 },
}

function Style.Look()
	if not ns.db.ring then return "square" end
	return ns.db.ringStyle
end

function Style.IsRound()
	return Style.Look() ~= "square"
end

function Style.IsArt()
	return Style.Look() == "grimoire"
end

function Style.Font(fs, size, outline)
	local t = Style.theme
	fs:SetFont(t.font, size, outline or t.outline)
	fs:SetShadowOffset(0, 0)
end

local function Masked(parent, layer, sublevel, mask)
	local tex = parent:CreateTexture(nil, layer, nil, sublevel)
	tex:SetTexture(WHITE)
	tex:AddMaskTexture(mask)
	return tex
end

local function NewMask(btn, inset)
	local mask = btn:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetPoint("TOPLEFT", -inset, inset)
	mask:SetPoint("BOTTOMRIGHT", inset, -inset)
	return mask
end

-- Round ------------------------------------------------------------------------

local function StyleRound(btn)
	local t = Style.theme
	btn.round = true

	-- Halo (hover/glow), rim, then the icon inset by the rim.
	btn.haloMask = NewMask(btn, 3)
	btn.halo = Masked(btn, "BACKGROUND", -7, btn.haloMask)
	btn.halo:SetAllPoints(btn.haloMask)
	btn.halo:SetVertexColor(t.accent[1], t.accent[2], t.accent[3])
	btn.halo:Hide()

	btn.rimMask = NewMask(btn, 0)
	btn.rim = Masked(btn, "BACKGROUND", -6, btn.rimMask)
	btn.rim:SetAllPoints()
	btn.rim:SetVertexColor(t.border[1], t.border[2], t.border[3])

	btn.iconMask = NewMask(btn, -RIM)
	btn.icon:ClearAllPoints()
	btn.icon:SetPoint("TOPLEFT", RIM, -RIM)
	btn.icon:SetPoint("BOTTOMRIGHT", -RIM, RIM)
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon:AddMaskTexture(btn.iconMask)

	local pushed = Masked(btn, "ARTWORK", 7, btn.iconMask)
	pushed:SetAllPoints(btn.icon)
	pushed:SetVertexColor(0, 0, 0, 0.35)
	btn:SetPushedTexture(pushed)

	btn.cooldown:ClearAllPoints()
	btn.cooldown:SetAllPoints(btn.icon)
	btn.cooldown:SetSwipeTexture(CIRCLE)
	btn.cooldown:SetSwipeColor(0, 0, 0, 0.7)
	btn.cooldown:SetUseCircularEdge(true)
	btn.cooldown:SetDrawEdge(false)

	-- Soft accent glow for "needs attention"
	btn.softGlow = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
	btn.softGlow:SetTexture(SOFT_GLOW)
	btn.softGlow:SetBlendMode("ADD")
	btn.softGlow:SetVertexColor(t.accent[1], t.accent[2], t.accent[3])
	btn.softGlow:SetPoint("CENTER")
	btn.softGlow:Hide()
	local anim = btn.softGlow:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local alpha = anim:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0.35)
	alpha:SetDuration(0.8)
	alpha:SetSmoothing("IN_OUT")
	btn.softGlow.anim = anim

	btn:HookScript("OnEnter", function(self) self.halo:Show() end)
	btn:HookScript("OnLeave", function(self) if not self.glowing then self.halo:Hide() end end)

	btn.HotKey:ClearAllPoints()
	btn.HotKey:SetPoint("TOP", 0, -3)
	if btn.key ~= "Book" then -- the book's number stays centered
		btn.Count:ClearAllPoints()
		btn.Count:SetPoint("BOTTOM", 0, 3)
	end
end

-- Grimoire art ------------------------------------------------------------------

-- Hover halo and pulsing "needs attention" glow, both from the tinted glow ring.
local function ArtGlows(btn)
	local a = Style.theme.accent
	btn.halo = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
	btn.halo:SetTexture(MEDIA .. "RimGlow")
	btn.halo:SetBlendMode("ADD")
	btn.halo:SetVertexColor(a[1], a[2], a[3], 0.7)
	btn.halo:SetPoint("CENTER")
	btn.halo:Hide()

	btn.softGlow = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
	btn.softGlow:SetTexture(MEDIA .. "RimGlow")
	btn.softGlow:SetBlendMode("ADD")
	btn.softGlow:SetVertexColor(a[1], a[2], a[3])
	btn.softGlow:SetPoint("CENTER")
	btn.softGlow:Hide()
	local anim = btn.softGlow:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local alpha = anim:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0.3)
	alpha:SetDuration(0.8)
	alpha:SetSmoothing("IN_OUT")
	btn.softGlow.anim = anim

	btn:HookScript("OnEnter", function(self) self.halo:Show() end)
	btn:HookScript("OnLeave", function(self) if not self.glowing then self.halo:Hide() end end)
end

local function StyleArt(btn)
	btn.round, btn.art = true, true

	btn.iconMask = btn:CreateMaskTexture()
	btn.iconMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	btn.iconMask:SetAllPoints(btn.icon)
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon:AddMaskTexture(btn.iconMask)

	btn.rim = btn:CreateTexture(nil, "ARTWORK", nil, 7)
	btn.rim:SetTexture(MEDIA .. "Rim")
	btn.rim:SetAllPoints()

	local pushed = Masked(btn, "ARTWORK", 6, btn.iconMask)
	pushed:SetAllPoints(btn.icon)
	pushed:SetVertexColor(0, 0, 0, 0.35)
	btn:SetPushedTexture(pushed)

	btn.cooldown:ClearAllPoints()
	btn.cooldown:SetAllPoints(btn.icon)
	btn.cooldown:SetSwipeTexture(CIRCLE)
	btn.cooldown:SetSwipeColor(0, 0, 0, 0.7)
	btn.cooldown:SetUseCircularEdge(true)
	btn.cooldown:SetDrawEdge(false)

	ArtGlows(btn)
	if btn.cost then
		btn.cost:ClearAllPoints()
		btn.cost:SetPoint("BOTTOM", 0, 6) -- clear of the rim
	end
	btn.HotKey:ClearAllPoints()
	btn.HotKey:SetPoint("TOP", 0, -4)
	btn.Count:ClearAllPoints()
	btn.Count:SetPoint("BOTTOM", 0, 4)
end

-- The tome in its bezel. Its sockets light up one by one (shards, or soulstone time).
local function StyleArtBook(book)
	book.round, book.art = true, true
	book.icon:SetTexture(MEDIA .. "Grimoire")
	book.icon:SetTexCoord(0, 1, 0, 1)
	book.icon:ClearAllPoints()
	book.icon:SetAllPoints()
	book.pips = {}
	for i = 1, PIPS do
		local pip = book:CreateTexture(nil, "ARTWORK", nil, 5)
		pip:SetTexture(MEDIA .. "Pip")
		pip:Hide()
		local flash = pip:CreateAnimationGroup()
		local fade = flash:CreateAnimation("Alpha")
		fade:SetFromAlpha(0)
		fade:SetToAlpha(1)
		fade:SetDuration(0.4)
		fade:SetSmoothing("OUT")
		pip.flash = flash
		book.pips[i] = pip
	end
	ArtGlows(book)
end

-- Lights the first n sockets; newly lit ones fade in.
function Style.SetPips(book, n)
	if not book.pips then return end
	for i, pip in ipairs(book.pips) do
		local on = i <= n
		if on and not pip:IsShown() then
			pip:Show()
			pip.flash:Play()
		elseif not on then
			pip:Hide()
		end
	end
end

-- Square -----------------------------------------------------------------------

local function StyleSquarePlain(btn)
	local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetFrameLevel(btn:GetFrameLevel())
	border:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0)
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
end

-- Blizzard-style square glow, used without ElvUI.
local function SquareGlow(btn)
	local glow = btn:CreateTexture(nil, "OVERLAY")
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	local a = Style.theme.accent
	glow:SetVertexColor(a[1], a[2], a[3])
	glow:SetPoint("CENTER")
	glow:Hide()
	local anim = glow:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local alpha = anim:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0.3)
	alpha:SetDuration(0.6)
	glow.anim = anim
	btn.squareGlow = glow
end

-- Public -----------------------------------------------------------------------

-- Styles one button. Called for every Grimoire button once the theme is known.
function Style.Button(btn)
	if btn.styled then return end
	btn.styled = true
	local t = Style.theme
	Style.Font(btn.HotKey, 10)
	Style.Font(btn.Count, btn.key == "Book" and 16 or 12)
	if btn.cost then Style.Font(btn.cost, 9) end
	if Style.IsArt() then
		if btn.key == "Book" then StyleArtBook(btn) else StyleArt(btn) end
	elseif Style.IsRound() then
		StyleRound(btn)
	elseif Style.SquareElvUI then
		Style.SquareElvUI(btn)
	else
		StyleSquarePlain(btn)
		SquareGlow(btn)
	end
	if btn.cost then btn.cost:SetTextColor(t.mana[1] + 0.3, t.mana[2] + 0.3, t.mana[3] + 0.3) end
end

-- Keeps size-dependent pieces in step with the button size.
function Style.Resize(btn, size)
	if btn.art then
		local glow = btn.pips and 1.18 or 1.4
		btn.halo:SetSize(size * glow, size * glow)
		btn.softGlow:SetSize(size * glow, size * glow)
		if btn.pips then
			local r, pipSize = size * PIP_RADIUS, math.max(6, size * 0.095)
			for i, pip in ipairs(btn.pips) do
				local angle = math.pi / 2 - (i - 1) * 2 * math.pi / PIPS
				pip:SetSize(pipSize, pipSize)
				pip:SetPoint("CENTER", btn, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
			end
			btn.Count:ClearAllPoints()
			btn.Count:SetPoint("CENTER", btn, "CENTER", 0, -size * 0.33)
			if btn.fill then
				local inset = size * WELL_INSET
				btn.fill:ClearAllPoints()
				btn.fill:SetPoint("TOPLEFT", inset, -inset)
				btn.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
			end
		else
			local inset = math.floor(size * ART_ICON_INSET + 0.5)
			btn.icon:ClearAllPoints()
			btn.icon:SetPoint("TOPLEFT", inset, -inset)
			btn.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
		end
		return
	end
	if btn.softGlow then btn.softGlow:SetSize(size * 1.9, size * 1.9) end
	if btn.squareGlow then btn.squareGlow:SetSize(size * 1.9, size * 1.9) end
end

function Style.SetGlow(btn, on)
	on = on and true or false
	if btn.glowing == on then return end
	btn.glowing = on
	if btn.softGlow then
		btn.softGlow:SetShown(on)
		btn.halo:SetShown(on or btn:IsMouseOver())
		if on then btn.softGlow.anim:Play() else btn.softGlow.anim:Stop() end
	elseif btn.squareGlow then
		btn.squareGlow:SetShown(on)
		if on then btn.squareGlow.anim:Play() else btn.squareGlow.anim:Stop() end
	elseif Style.ElvUIGlow then
		Style.ElvUIGlow(btn, on)
	end
end

-- Usability tint: full color, out of mana (blue), or unusable (grey + desaturated).
function Style.SetUsable(btn, state)
	local t = Style.theme
	if state == "nopower" then
		btn.icon:SetDesaturated(false)
		btn.icon:SetVertexColor(t.noPower[1], t.noPower[2], t.noPower[3])
	elseif state == "unusable" then
		btn.icon:SetDesaturated(true)
		btn.icon:SetVertexColor(t.notUsable[1] + 0.3, t.notUsable[2] + 0.3, t.notUsable[3] + 0.3)
	else
		btn.icon:SetDesaturated(false)
		btn.icon:SetVertexColor(1, 1, 1)
	end
end

-- The book's fill: a status bar so it can show secret values (mana in combat),
-- clipped to a circle in the round style.
function Style.BookFill(book)
	local fill = CreateFrame("StatusBar", nil, book)
	fill:SetOrientation("VERTICAL")
	fill:SetStatusBarTexture(WHITE)
	fill:SetFrameLevel(book:GetFrameLevel())
	local tex = fill:GetStatusBarTexture()
	tex:SetBlendMode("ADD")
	if Style.IsRound() then
		fill:SetAllPoints(book.icon) -- the art look re-insets this to the bezel's well in Resize
		local mask = fill:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(fill)
		tex:AddMaskTexture(mask)
	else
		fill:SetAllPoints(book.icon)
	end
	-- Bright surface line on top of the liquid.
	fill.surface = fill:CreateTexture(nil, "OVERLAY")
	fill.surface:SetTexture(WHITE)
	fill.surface:SetBlendMode("ADD")
	fill.surface:SetHeight(1)
	fill.surface:SetPoint("BOTTOMLEFT", tex, "TOPLEFT")
	fill.surface:SetPoint("BOTTOMRIGHT", tex, "TOPRIGHT")
	if fill.surface.AddMaskTexture and Style.IsRound() then
		local mask = fill:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(fill)
		fill.surface:AddMaskTexture(mask)
	end
	return fill
end

-- Lifts the book's number above the fill so the liquid never washes over it.
function Style.BookText(book, fill)
	local overlay = CreateFrame("Frame", nil, book)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(fill:GetFrameLevel() + 2)
	book.Count:SetParent(overlay)
end

function Style.SetFillColor(fill, r, g, b)
	fill:SetStatusBarColor(r, g, b, 0.45)
	fill.surface:SetVertexColor(r, g, b, 0.9)
end

-- Reload prompt when the shape changes ------------------------------------------

StaticPopupDialogs.GRIMOIRE_RELOAD = {
	text = "Grimoire: reload the UI to apply the new button style?",
	button1 = RELOADUI,
	button2 = LATER,
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- A rim for small round extras (e.g. the Shadow Trance alert) in the art look.
function Style.ArtRim(frame)
	local rim = frame:CreateTexture(nil, "OVERLAY", nil, -1)
	rim:SetTexture(MEDIA .. "Rim")
	rim:SetAllPoints()
	return rim
end

function Style.CheckShapeChange()
	if ns.loginLook ~= nil and ns.loginLook ~= Style.Look() then
		StaticPopup_Show("GRIMOIRE_RELOAD")
	end
end
