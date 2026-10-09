local addonName, ns = ...

-- Summon queue: watches group chat and whispers for "123"/"summon" style requests and
-- lists the players. Clicking a row targets them and casts Ritual of Summoning
-- (shift-click: Portal of Summoning). Rows are secure buttons, so the list can only
-- change out of combat; requests that arrive in combat are added afterwards.
-- With sync on, warlocks running Grimoire share who has been summoned.

local PREFIX = "GRIMOIRE"
local MAX_ROWS = 10
local ROW_HEIGHT = 18
local EXPIRE = 10 * 60 -- forget requests after 10 minutes

local queue = {} -- ordered { name = "Name", time = GetTime() }
local frame, rows = nil, {}
local dirty = false

local function ShortName(name)
	return name and Ambiguate(name, "none")
end

local function Find(name)
	for i, entry in ipairs(queue) do
		if entry.name == name then return i end
	end
end

-- Group unit token for a player name, for status checks.
local function UnitFor(name)
	if name == ns.SafeUnitName("player") then return "player" end
	local prefix, count = "party", GetNumSubgroupMembers()
	if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
	for i = 1, count do
		local unit = prefix .. i
		if ns.SafeUnitName(unit) == name then return unit end
	end
end

local function Status(name)
	local unit = UnitFor(name)
	if not unit then return "not in group", 0.6, 0.6, 0.6 end
	if not UnitIsConnected(unit) then return "offline", 0.6, 0.6, 0.6 end
	if UnitIsDeadOrGhost(unit) then return "dead", 1, 0.3, 0.3 end
	if C_IncomingSummon and C_IncomingSummon.HasIncomingSummon(unit) then return "summon pending", 0.2, 1, 0.2 end
	return nil, 1, 1, 1
end

function ns:UpdateSummonQueue()
	if not frame then return end
	if InCombatLockdown() then
		dirty = true
		return
	end
	dirty = false
	local now = GetTime()
	for i = #queue, 1, -1 do
		if now - queue[i].time > EXPIRE or not UnitFor(queue[i].name) then table.remove(queue, i) end
	end
	local ritual = C_Spell.GetSpellName(ns.Data.ritualOfSummoning)
	local portal = ns.hasPortal and C_Spell.GetSpellName(ns.Data.portalOfSummoning)
	for i, row in ipairs(rows) do
		local entry = queue[i]
		if entry then
			row.name = entry.name
			row:SetAttribute("macrotext1", ("/target %s\n/cast %s"):format(entry.name, ritual))
			row:SetAttribute("shift-macrotext1", portal and ("/cast %s"):format(portal) or nil)
			local status, r, g, b = Status(entry.name)
			row.text:SetText(status and ("%s |cff999999(%s)|r"):format(entry.name, status) or entry.name)
			row.text:SetTextColor(r, g, b)
			row:Show()
		else
			row.name = nil
			row:Hide()
		end
	end
	local shown = math.min(#queue, MAX_ROWS)
	frame:SetHeight(24 + math.max(shown, 1) * ROW_HEIGHT)
	frame.empty:SetShown(shown == 0)
	frame:SetShown(ns.db.summonQueue and (shown > 0 or frame.pinned) and ns.hasRitual or false)
end

local function Add(name)
	name = ShortName(name)
	if not name or Find(name) or name == ns.SafeUnitName("player") then return end
	table.insert(queue, { name = name, time = GetTime() })
	PlaySound(SOUNDKIT.TELL_MESSAGE)
	ns:UpdateSummonQueue()
end

local function Remove(name, fromSync)
	local i = Find(name)
	if not i then return end
	table.remove(queue, i)
	if not fromSync and ns.db.summonSync and ns.GroupChannel() then
		C_ChatInfo.SendAddonMessage(PREFIX, "DONE:" .. name, ns.GroupChannel())
	end
	ns:UpdateSummonQueue()
end

-- Called by Speech.lua when a Ritual of Summoning starts on a target.
function ns:OnSummonCast(name)
	Remove(ShortName(name))
end

function ns:ToggleSummonQueue()
	if not frame or InCombatLockdown() then return end
	frame.pinned = not frame:IsShown()
	ns:UpdateSummonQueue()
end

-- Chat parsing -------------------------------------------------------------------

local keywords = {}
local function ParseKeywords()
	wipe(keywords)
	for word in (ns.db.summonKeywords or ""):gmatch("[^,]+") do
		word = strtrim(word):lower()
		if word ~= "" then table.insert(keywords, word) end
	end
end
ns.ParseSummonKeywords = ParseKeywords

local function IsRequest(msg)
	msg = strtrim(msg:lower())
	for _, word in ipairs(keywords) do
		if msg == word or msg:sub(1, #word + 1) == word .. " " then return true end
	end
end

local function OnChat(_, msg, sender)
	msg, sender = ns.Safe(msg), ns.Safe(sender)
	if not (ns.db.summonQueue and ns.hasRitual and msg and sender) then return end
	if IsRequest(msg) then Add(sender) end
end

local function OnAddonMessage(_, prefix, msg, _, sender)
	if prefix ~= PREFIX or not ns.db.summonSync then return end
	msg, sender = ns.Safe(msg), ns.Safe(sender)
	if not msg or ShortName(sender) == ns.SafeUnitName("player") then return end
	local name = msg:match("^DONE:(.+)$")
	if name then Remove(name, true) end
end

-- Frame -------------------------------------------------------------------------

ns:Module(function()
	ParseKeywords()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

	frame = CreateFrame("Frame", "GrimoireSummonQueue", UIParent, "BackdropTemplate")
	frame:SetSize(180, 24 + ROW_HEIGHT)
	frame:SetPoint("BOTTOMRIGHT", ns.bar, "TOPRIGHT", 0, 6)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	frame:SetBackdropColor(0, 0, 0, 0.7)
	frame:SetBackdropBorderColor(0, 0, 0)
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY")
	ns.Style.Font(title, 11)
	local a = ns.Style.theme.accent
	title:SetTextColor(a[1], a[2], a[3])
	title:SetPoint("TOPLEFT", 6, -6)
	title:SetText("Summon queue")
	frame.empty = frame:CreateFontString(nil, "OVERLAY")
	ns.Style.Font(frame.empty, 10)
	frame.empty:SetTextColor(0.5, 0.5, 0.5)
	frame.empty:SetPoint("TOPLEFT", 8, -24)
	frame.empty:SetText("Nobody is waiting.")

	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", "GrimoireSummonRow" .. i, frame, "SecureActionButtonTemplate")
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 4, -20 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", -4, -20 - (i - 1) * ROW_HEIGHT)
		row:RegisterForClicks("AnyUp", "AnyDown")
		row:SetAttribute("type1", "macro")
		row:SetAttribute("type2", "grimoire_noop")
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.text = row:CreateFontString(nil, "OVERLAY")
		ns.Style.Font(row.text, 11)
		row.text:SetPoint("LEFT", 4, 0)
		row:SetScript("PreClick", function(self, mouse, down)
			if not down and mouse == "LeftButton" and self.name and ns.NoteRitualClick then
				ns:NoteRitualClick(self.name, IsShiftKeyDown())
			end
		end)
		row:SetScript("PostClick", function(self, mouse, down)
			if not down and mouse == "RightButton" and self.name then Remove(self.name) end
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.name)
			GameTooltip:AddLine("Click: target and Ritual of Summoning", 0.6, 0.8, 1)
			if ns.hasPortal then GameTooltip:AddLine("Shift-click: Portal of Summoning", 0.6, 0.8, 1) end
			GameTooltip:AddLine("Right-click: remove", 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:Hide()
		rows[i] = row
	end
	if ns.SkinSummonQueue then ns.SkinSummonQueue(frame) end
end)

for _, event in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
	ns:On(event, OnChat)
end
ns:On("CHAT_MSG_ADDON", OnAddonMessage)
ns:On("GROUP_ROSTER_UPDATE", function() ns:UpdateSummonQueue() end)
ns:On("PLAYER_REGEN_ENABLED", function() if dirty then ns:UpdateSummonQueue() end end)
