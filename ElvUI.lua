local addonName, ns = ...

-- Everything here is skipped when ElvUI isn't loaded.
if not _G.ElvUI then return end

local E = unpack(_G.ElvUI)

-- ElvUI option table built from the shared option list in Options.lua.
local function InsertOptions()
	local ACH = E.Libs.ACH
	local group = ACH:Group("|cff9482c9Grimoire|r", nil, 50)
	group.args.header = ACH:Header("Grimoire", 1)
	for i, opt in ipairs(ns.optionList) do
		local order = i + 1
		local arg
		if opt.type == "header" then
			arg = ACH:Header(opt.name, order)
		elseif opt.type == "toggle" then
			arg = ACH:Toggle(opt.name, opt.desc, order)
		elseif opt.type == "range" then
			arg = ACH:Range(opt.name, opt.desc, order, { min = opt.min, max = opt.max, step = opt.step })
		elseif opt.type == "select" then
			arg = ACH:Select(opt.name, opt.desc, order, opt.values)
		else
			arg = ACH:Input(opt.name, opt.desc, order, nil, "full")
		end
		if opt.type ~= "header" then
			arg.get = function() return ns:GetOption(opt) end
			arg.set = function(_, value) ns:SetOptionValue(opt, value) end
		end
		group.args["opt" .. i] = arg
	end
	E.Options.args.Grimoire = group
end

function ns:OpenElvUIOptions()
	E:ToggleOptions("Grimoire")
	return true
end

-- Soul Shards datatext -----------------------------------------------------------

local DT = E:GetModule("DataTexts")
local panels = {}

local function ShardColor()
	if ns.shards == 0 then return "|cffff3333" end
	if ns.shards <= ns.db.shardLow then return "|cffffd100" end
	return "|cffffffff"
end

local function DTOnEvent(panel)
	panels[panel] = true
	if not ns.db then
		panel.text:SetText("Shards: -")
		return
	end
	panel.text:SetFormattedText("Shards: %s%d|r", ShardColor(), ns.shards)
end

local function DTOnEnter()
	DT.tooltip:ClearLines()
	if ns.db then
		ns:AddStatusLines(DT.tooltip)
		DT.tooltip:AddLine(" ")
		DT.tooltip:AddLine("Click: show/hide the Grimoire bar", 0.5, 0.5, 0.5)
	else
		DT.tooltip:AddLine("Grimoire")
	end
	DT.tooltip:Show()
end

local function DTOnClick()
	if ns.db then ns:SetOption("showBar", not ns.db.showBar) end
end

DT:RegisterDatatext("Soul Shards", "Grimoire", { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
	DTOnEvent, nil, DTOnClick, DTOnEnter, nil, "Soul Shards")

function ns:UpdateDataText()
	for panel in pairs(panels) do DTOnEvent(panel) end
end

-- Bar styling, mover, options ---------------------------------------------------

-- Hooks used by the other modules once ElvUI has initialized.

local timerFrames

function ns:SetupTimerMovers(timers, trance)
	timerFrames = { timers = timers, trance = trance }
end

function ns.SkinTimerBar(bar)
	bar:SetStatusBarTexture(E.media.normTex)
	bar:CreateBackdrop("Transparent")
	bar.label:FontTemplate(nil, 11)
	bar.time:FontTemplate(nil, 11)
end

function ns.SkinSummonQueue(frame)
	frame:SetBackdrop(nil)
	frame:SetTemplate("Transparent")
end

local AB

local function Color(c, fallback)
	if not c then return fallback end
	return { c.r or c[1], c.g or c[2], c.b or c[3] }
end

-- Grimoire's theme from ElvUI's settings: fonts, value color, borders, action bar colors.
local function ApplyTheme()
	local t = ns.Style.theme
	t.accent = Color(E.media.rgbvaluecolor, t.accent)
	t.border = Color(E.media.bordercolor, t.border)
	t.font = E.media.normFont or t.font
	t.outline = E.db.general.fontStyle ~= "NONE" and E.db.general.fontStyle or ""
	t.noPower = Color(AB.db and AB.db.noPowerColor, t.noPower)
	t.notUsable = Color(AB.db and AB.db.notUsableColor, t.notUsable)
	t.outOfRange = Color(AB.db and AB.db.noRangeColor, t.outOfRange)
	local power = E.db.unitframe and E.db.unitframe.colors and E.db.unitframe.colors.power
	t.mana = Color(power and power.MANA, t.mana)

	-- Square buttons use ElvUI's own action button style and the user's glow style.
	ns.Style.SquareElvUI = function(btn) AB:StyleButton(btn, nil, nil, true) end
	ns.Style.ElvUIGlow = function(btn, on)
		local LCG = E.Libs.CustomGlow
		if on then LCG.ShowOverlayGlow(btn) else LCG.HideOverlayGlow(btn) end
	end
	ns.Style.Font = function(fs, size, outline)
		fs:FontTemplate(nil, size, outline or E.db.general.fontStyle)
	end
end

local function StyleBar()
	AB = E:GetModule("ActionBars")
	ApplyTheme()
	ns.UpdateBarBackdrop = function()
		ns.bar:SetTemplate(ns.db.ring and "NoBackdrop" or "Transparent")
	end
	ns.FormatHotkey = function(btn) AB:FixKeybindText(btn) end
	ns:ApplyStyle()

	-- ElvUI's hover binding (/kb): hovering a Grimoire button binds a key to it,
	-- including individual spells inside the menus.
	local function HoverBind(btn) AB:BindUpdate(btn) end
	for _, btn in pairs(ns.buttons) do
		if btn.binding then
			btn.keyBoundTarget = btn.binding
			btn:HookScript("OnEnter", HoverBind)
		end
	end
	E:CreateMover(ns.bar, "GrimoireMover", "Grimoire", nil, nil, nil, "ALL,ACTIONBARS", nil, "Grimoire")
	-- Shift-drag moves the bar itself; on release, ElvUI's (hidden) mover is placed where
	-- the bar ended up and saved, then the bar is re-anchored to it the way ElvUI does.
	-- Showing the mover outside /moveui isn't safe: its handlers expect config mode.
	ns.StartDrag = function() ns.bar:StartMoving() end
	ns.StopDrag = function()
		local bar = ns.bar
		bar:StopMovingOrSizing()
		local holder = E.CreatedMovers.GrimoireMover
		if not holder then return end
		local point = holder.originPoint[1] or "CENTER"
		local x = point:find("LEFT") and bar:GetLeft() or point:find("RIGHT") and bar:GetRight() or (bar:GetLeft() + bar:GetRight()) / 2
		local y = point:find("TOP") and bar:GetTop() or point:find("BOTTOM") and bar:GetBottom() or (bar:GetTop() + bar:GetBottom()) / 2
		local scale = bar:GetEffectiveScale() / holder.mover:GetEffectiveScale()
		holder.mover:ClearAllPoints()
		holder.mover:SetPoint(point, UIParent, "BOTTOMLEFT", x * scale, y * scale)
		E:SaveMoverPosition("GrimoireMover")
		E:SetMoverPoints("GrimoireMover", bar)
	end
	if timerFrames then
		E:CreateMover(timerFrames.timers, "GrimoireTimersMover", "Grimoire Timers", nil, nil, nil, "ALL,ACTIONBARS", nil, "Grimoire")
		E:CreateMover(timerFrames.trance, "GrimoireTranceMover", "Grimoire Shadow Trance", nil, nil, nil, "ALL,ACTIONBARS", nil, "Grimoire")
	end
	E.Libs.EP:RegisterPlugin(addonName, InsertOptions)
end

function ns:SetupElvUI()
	-- ElvUI initializes from its own PLAYER_LOGIN handler; wait for it if we got there first.
	if E.db and E.private then
		StyleBar()
	else
		hooksecurefunc(E, "Initialize", StyleBar)
	end
end
