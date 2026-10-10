local addonName, ns = ...

-- Ways to reach Grimoire from other UI: a LibDataBroker feed (Titan Panel, Bazooka,
-- ChocolateBar, ...) and Blizzard's AddOn compartment menu by the minimap.

local ICON = "Interface\\AddOns\\Grimoire\\Media\\Icon"

local function OnClick(_, mouse)
	if not ns.db then return end
	if mouse == "RightButton" then
		SlashCmdList.GRIMOIRE("")
	elseif IsShiftKeyDown() then
		if ns.ToggleRaidPanel then ns:ToggleRaidPanel() end
	else
		ns:SetOption("showBar", not ns.db.showBar)
	end
end

local function Hints(tt)
	tt:AddLine(" ")
	tt:AddLine("Left-click: show/hide the bar", 0.5, 0.5, 0.5)
	tt:AddLine("Shift-left-click: warlocks in your group", 0.5, 0.5, 0.5)
	tt:AddLine("Right-click: options", 0.5, 0.5, 0.5)
end

local function Tooltip(tt)
	if not ns.db then
		tt:AddLine("Grimoire")
		tt:AddLine("Only runs on warlocks.", 0.7, 0.7, 0.7)
		return
	end
	ns:AddStatusLines(tt)
	Hints(tt)
end

-- Data broker -----------------------------------------------------------------------

local feed
ns:Module(function()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	if not (LDB and ns.db.broker) then return end
	feed = LDB:NewDataObject("Grimoire", {
		type = "data source",
		label = "Soul Shards",
		text = "0",
		icon = ICON,
		OnClick = OnClick,
		OnTooltipShow = Tooltip,
	})
end)

function ns:UpdateBroker()
	if feed then feed.text = tostring(ns.shards) end
end

-- AddOn compartment (TOC: AddonCompartmentFunc*) -----------------------------------

function Grimoire_OnCompartmentClick(_, mouse)
	OnClick(nil, mouse)
end

function Grimoire_OnCompartmentEnter(_, frame)
	GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
	Tooltip(GameTooltip)
	GameTooltip:Show()
end

function Grimoire_OnCompartmentLeave()
	GameTooltip:Hide()
end
