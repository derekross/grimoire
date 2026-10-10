local addonName, ns = ...

-- Group coordination between warlocks running Grimoire, over a hidden addon channel:
--   roster:      who runs Grimoire, which curse they're on, and their version
--   assignments: the group leader or an assistant (anyone in a 5-man) assigns curses;
--                the assigned warlock's curse button switches to it
--   soulstones:  everyone sees who holds whose soulstone, to avoid doubling up
-- The Warlocks panel (shift-click the book, or /grim raid) shows all of it.

local PREFIX = "GRIMOIRE"
local SOULSTONE_DURATION = 30 * 60
local ASSIGNABLE = 5 -- the first five curses (Amplify Curse isn't a curse to assign)
local ROW_HEIGHT = 22

local roster = {} -- name -> { version, curse = spellID, ss = { target, expires } }
ns.raidRoster = roster

local panel, rows = nil, {}

local function Me()
	return ns.SafeUnitName("player")
end

local function Send(msg)
	local channel = ns.GroupChannel()
	if channel then C_ChatInfo.SendAddonMessage(PREFIX, msg, channel) end
end

-- The curse this warlock casts by default, from the saved pick (the button's own
-- spell only refreshes out of combat).
local function MyCurse()
	local pick = ns.db.defaults.Curses
	local entry = pick and ns.Data.curses[pick]
	local spell = entry and ns.BestSpell(entry)
	if spell then return spell end
	local main = ns.menus.Curses
	return main and main.spellID or 0
end

local function MySoulstone()
	local last = ns.char.lastSoulstone
	if not (last and last.name and last.time) then return end
	local left = SOULSTONE_DURATION - (time() - last.time)
	if left > 0 then return last.name, left end
end

local function UpdateSelf()
	local me = Me()
	if not me then return end
	local entry = roster[me] or {}
	entry.version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	entry.curse = MyCurse()
	local target, left = MySoulstone()
	entry.ss = target and { target = target, expires = GetTime() + left } or nil
	roster[me] = entry
end

local function Hello(reply)
	Send(("%s:%s:%d"):format(reply and "HIBACK" or "HI", C_AddOns.GetAddOnMetadata(addonName, "Version") or "?", MyCurse()))
	local target, left = MySoulstone()
	if target and ns.db.shareSoulstones then Send(("SS:%s:%d"):format(target, left)) end
end

-- Can this group member hand out assignments?
local function CanAssign(name)
	if not IsInGroup() then return false end
	if not IsInRaid() then return true end
	local unit = ns.UnitForName and ns.UnitForName(name)
	return unit and (UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)) or false
end

local function CurseIndex(spellID)
	for i, entry in ipairs(ns.Data.curses) do
		for _, id in ipairs(entry.ranks) do
			if id == spellID then return i end
		end
	end
end

-- Panel -----------------------------------------------------------------------------

local function ClassColor()
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS.WARLOCK
	return c and c.r or 0.53, c and c.g or 0.53, c and c.b or 0.93
end

function ns:UpdateRaidPanel()
	if not (panel and panel:IsShown()) then return end
	UpdateSelf()
	local names = {}
	for name in pairs(roster) do
		if name == Me() or (ns.UnitForName and ns.UnitForName(name)) then table.insert(names, name) end
	end
	table.sort(names, function(a, b)
		if a == Me() then return true elseif b == Me() then return false end
		return a < b
	end)
	local canAssign = CanAssign(Me())
	local now = GetTime()
	for i, row in ipairs(rows) do
		local name = names[i]
		if name then
			local entry = roster[name]
			row.name = name
			row.label:SetText(name)
			row.label:SetTextColor(ClassColor())
			local current = CurseIndex(entry.curse)
			for c, icon in ipairs(row.curses) do
				local on = c == current
				icon.tex:SetDesaturated(not on)
				icon.tex:SetAlpha(on and 1 or (canAssign and 0.45 or 0.25))
				icon.border:SetShown(on)
				icon:EnableMouse(canAssign or on)
			end
			local ss = entry.ss
			if ss and ss.expires > now then
				row.ss:SetFormattedText("|cffd980d9%s|r %dm", ss.target, math.ceil((ss.expires - now) / 60))
			else
				row.ss:SetText("|cff666666no soulstone|r")
			end
			row:Show()
		else
			row.name = nil
			row:Hide()
		end
	end
	local shown = math.min(#names, #rows)
	-- title + rows (or the empty note) + the hint line
	panel:SetHeight(26 + math.max(shown, 1) * ROW_HEIGHT + 16)
	panel.empty:SetShown(shown == 0)
	panel.hint:SetText(canAssign and "Click a curse to assign it." or "Only the leader or an assistant can assign curses.")
end

function ns:ToggleRaidPanel()
	if not panel then return end
	panel:SetShown(not panel:IsShown())
	if panel:IsShown() then
		Hello()
		ns:UpdateRaidPanel()
	end
end

local function CreateRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 6, -22 - (i - 1) * ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", -6, -22 - (i - 1) * ROW_HEIGHT)
	row.label = row:CreateFontString(nil, "OVERLAY")
	ns.Style.Font(row.label, 11)
	row.label:SetPoint("LEFT")
	row.label:SetWidth(80)
	row.label:SetJustifyH("LEFT")
	row.curses = {}
	for c = 1, ASSIGNABLE do
		local entry = ns.Data.curses[c]
		local icon = CreateFrame("Button", nil, row)
		icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
		icon:SetPoint("LEFT", row, "LEFT", 84 + (c - 1) * (ROW_HEIGHT - 1), 0)
		icon.tex = icon:CreateTexture(nil, "ARTWORK")
		icon.tex:SetAllPoints()
		icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon.tex:SetTexture(C_Spell.GetSpellTexture(entry.ranks[1]))
		icon.border = icon:CreateTexture(nil, "OVERLAY")
		icon.border:SetPoint("TOPLEFT", -1, 1)
		icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
		icon.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		icon.border:SetBlendMode("ADD")
		local a = ns.Style.theme.accent
		icon.border:SetVertexColor(a[1], a[2], a[3])
		icon.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
		icon:SetScript("OnClick", function()
			if row.name and CanAssign(Me()) then
				Send(("ASSIGN:%s:%d"):format(row.name, c))
				if row.name == Me() then ns:ApplyCurseAssignment(c, Me()) end
			end
		end)
		icon:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetSpellByID(entry.ranks[1])
			if CanAssign(Me()) and row.name then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Click: assign to " .. row.name, 0.5, 0.5, 0.5)
			end
			GameTooltip:Show()
		end)
		icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.curses[c] = icon
	end
	row.ss = row:CreateFontString(nil, "OVERLAY")
	ns.Style.Font(row.ss, 10)
	row.ss:SetPoint("RIGHT")
	row.ss:SetJustifyH("RIGHT")
	row:Hide()
	return row
end

local function CreatePanel()
	panel = CreateFrame("Frame", "GrimoireRaidPanel", UIParent, "BackdropTemplate")
	panel:SetSize(300, 60)
	panel:SetPoint("CENTER", 0, 120)
	panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	panel:SetBackdropColor(0, 0, 0, 0.8)
	panel:SetBackdropBorderColor(0, 0, 0)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:Hide()
	tinsert(UISpecialFrames, "GrimoireRaidPanel") -- Escape closes it

	local title = panel:CreateFontString(nil, "OVERLAY")
	ns.Style.Font(title, 12)
	local a = ns.Style.theme.accent
	title:SetTextColor(a[1], a[2], a[3])
	title:SetPoint("TOPLEFT", 8, -6)
	title:SetText("Warlocks")

	local close = CreateFrame("Button", nil, panel)
	close:SetSize(16, 16)
	close:SetPoint("TOPRIGHT", -4, -4)
	close.text = close:CreateFontString(nil, "OVERLAY")
	ns.Style.Font(close.text, 14)
	close.text:SetPoint("CENTER")
	close.text:SetText("×")
	close.text:SetTextColor(0.6, 0.6, 0.6)
	close:SetScript("OnClick", function() panel:Hide() end)
	close:SetScript("OnEnter", function() close.text:SetTextColor(1, 1, 1) end)
	close:SetScript("OnLeave", function() close.text:SetTextColor(0.6, 0.6, 0.6) end)

	panel.empty = panel:CreateFontString(nil, "OVERLAY")
	ns.Style.Font(panel.empty, 10)
	panel.empty:SetTextColor(0.5, 0.5, 0.5)
	panel.empty:SetPoint("TOPLEFT", 8, -26)
	panel.empty:SetText("No other warlocks with Grimoire in your group.")

	panel.hint = panel:CreateFontString(nil, "OVERLAY")
	ns.Style.Font(panel.hint, 9)
	panel.hint:SetTextColor(0.5, 0.5, 0.5)
	panel.hint:SetPoint("BOTTOMLEFT", 8, 5)

	for i = 1, 10 do rows[i] = CreateRow(i) end
	if ns.SkinSummonQueue then ns.SkinSummonQueue(panel) end
end

-- Assignments ----------------------------------------------------------------------

function ns:ApplyCurseAssignment(index, from)
	local entry = ns.Data.curses[index]
	if not entry then return end
	local spell = ns.BestSpell(entry)
	local name = C_Spell.GetSpellName(entry.ranks[1])
	if not spell then
		ns.Print(("%s assigned you %s, but you don't know it yet."):format(from or "Your raid leader", name))
		return
	end
	ns.db.defaults.Curses = index
	ns:RequestSecureUpdate()
	ns:UpdateVisuals()
	ns.Print(("%s assigned you %s."):format(from or "Your raid leader", name))
	RaidNotice_AddMessage(RaidWarningFrame, "Your curse: " .. name, ChatTypeInfo.RAID_WARNING)
	ns:OnCurseChanged()
end

-- Called when this warlock's default curse changes.
function ns:OnCurseChanged()
	Send(("CURSE:%d"):format(MyCurse()))
	ns:UpdateRaidPanel()
end

-- Called by Speech.lua when this warlock places a soulstone.
function ns:OnSoulstone(target)
	if ns.db.shareSoulstones and target then
		Send(("SS:%s:%d"):format(target, SOULSTONE_DURATION))
	end
	ns:UpdateRaidPanel()
end

-- Messages --------------------------------------------------------------------------

local function OnAddonMessage(_, prefix, msg, _, sender)
	if prefix ~= PREFIX then return end
	msg, sender = ns.Safe(msg), ns.Safe(sender)
	if not (msg and sender) then return end
	sender = Ambiguate(sender, "none")
	if sender == Me() then return end
	local kind, rest = msg:match("^(%u+):(.*)$")
	if not kind then return end

	if kind == "HI" or kind == "HIBACK" then
		local version, curse = rest:match("^([^:]*):(%d+)$")
		roster[sender] = roster[sender] or {}
		roster[sender].version = version
		roster[sender].curse = tonumber(curse)
		-- Always answer a HI (they may have just reloaded); HIBACK never answers, so no loop.
		if kind == "HI" then Hello(true) end
	elseif kind == "CURSE" then
		roster[sender] = roster[sender] or {}
		roster[sender].curse = tonumber(rest)
	elseif kind == "SS" then
		local target, left = rest:match("^(.+):(%d+)$")
		if target then
			roster[sender] = roster[sender] or {}
			roster[sender].ss = { target = target, expires = GetTime() + tonumber(left) }
		end
	elseif kind == "ASSIGN" then
		local who, index = rest:match("^(.+):(%d+)$")
		index = tonumber(index)
		if who == Me() and index and index <= ASSIGNABLE and ns.db.acceptCurseAssignments and CanAssign(sender) then
			ns:ApplyCurseAssignment(index, sender)
		end
	end
	ns:UpdateRaidPanel()
end

-- Setup -------------------------------------------------------------------------------

ns:Module(function()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	CreatePanel()
	C_Timer.NewTicker(30, function() if panel:IsShown() then ns:UpdateRaidPanel() end end)
end)

local helloPending
local function ScheduleHello()
	if helloPending or not IsInGroup() then return end
	helloPending = true
	C_Timer.After(3, function()
		helloPending = nil
		-- Forget warlocks who left the group.
		for name in pairs(roster) do
			if name ~= Me() and not (ns.UnitForName and ns.UnitForName(name)) then roster[name] = nil end
		end
		Hello()
		ns:UpdateRaidPanel()
	end)
end

ns:On("CHAT_MSG_ADDON", OnAddonMessage)
ns:On("GROUP_ROSTER_UPDATE", ScheduleHello)
ns:On("PLAYER_ENTERING_WORLD", ScheduleHello)
