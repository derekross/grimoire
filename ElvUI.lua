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

local function StoneLine(tooltip, label, family)
	local stone = ns.stones[family]
	if stone then
		local name = C_Item.GetItemNameByID(stone.itemID) or label
		local outdated = ns:IsOutdated(family) and " |cff33ff33(upgrade)|r" or ""
		tooltip:AddDoubleLine(label, name .. outdated, 1, 1, 1, 0.6, 1, 0.6)
	elseif ns.known[family] then
		tooltip:AddDoubleLine(label, "none", 1, 1, 1, 1, 0.3, 0.3)
	end
end

local function DTOnEnter(panel)
	DT.tooltip:ClearLines()
	DT.tooltip:AddLine("Grimoire")
	if ns.db then
		DT.tooltip:AddDoubleLine("Soul Shards", ns.shards, 1, 1, 1, 1, 1, 1)
		DT.tooltip:AddDoubleLine("Gained this session", ns.sessionShards or 0, 1, 1, 1, 0.6, 1, 0.6)
		StoneLine(DT.tooltip, "Healthstone", "healthstone")
		StoneLine(DT.tooltip, "Soulstone", "soulstone")
		StoneLine(DT.tooltip, "Firestone", "firestone")
		StoneLine(DT.tooltip, "Spellstone", "spellstone")
		local left = ns:WeaponEnchantState()
		DT.tooltip:AddDoubleLine("Weapon stone", left and ("%d min"):format(math.floor(left / 60)) or "none",
			1, 1, 1, left and 0.6 or 1, left and 1 or 0.3, left and 0.6 or 0.3)
		local last = ns.char.lastSoulstone
		if last and last.name then
			DT.tooltip:AddDoubleLine("Last soulstone", ("%s (%d min ago)"):format(last.name, math.floor((time() - last.time) / 60)),
				1, 1, 1, 1, 0.82, 0)
		end
		DT.tooltip:AddLine(" ")
		DT.tooltip:AddLine("Click: show/hide the Grimoire bar", 0.6, 0.8, 1)
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

local function StyleBar()
	AB = E:GetModule("ActionBars")
	ns.bar:SetTemplate("Transparent")
	for _, btn in pairs(ns.buttons) do
		AB:StyleButton(btn, nil, nil, true)
	end
	ns.FormatHotkey = function(btn) AB:FixKeybindText(btn) end
	E:CreateMover(ns.bar, "GrimoireMover", "Grimoire", nil, nil, nil, "ALL,ACTIONBARS", nil, "Grimoire")
	if timerFrames then
		E:CreateMover(timerFrames.timers, "GrimoireTimersMover", "Grimoire Timers", nil, nil, nil, "ALL,ACTIONBARS", nil, "Grimoire")
		E:CreateMover(timerFrames.trance, "GrimoireTranceMover", "Grimoire Shadow Trance", nil, nil, nil, "ALL,ACTIONBARS", nil, "Grimoire")
	end
	E.Libs.EP:RegisterPlugin(addonName, InsertOptions)
	ns:UpdateVisuals()
end

function ns:SetupElvUI()
	-- ElvUI initializes from its own PLAYER_LOGIN handler; wait for it if we got there first.
	if E.db and E.private then
		StyleBar()
	else
		hooksecurefunc(E, "Initialize", StyleBar)
	end
end
