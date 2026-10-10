local addonName, ns = ...

-- Requests: people waiting on you. Watches group chat and whispers for summon
-- ("123", "summon") and healthstone ("hs") requests and lists them. Clicking a summon
-- row targets the player and casts Ritual of Summoning (shift-click: Portal of
-- Summoning); clicking a healthstone row targets them and opens a trade with a stone.
-- Rows are secure buttons, so the list can only change out of combat; requests that
-- arrive in combat are added afterwards. With sync on, warlocks running Grimoire share
-- who has been summoned or given a stone.

local PREFIX = "GRIMOIRE"
local MAX_ROWS = 10
local ROW_HEIGHT = 18
local EXPIRE = 10 * 60 -- forget requests after 10 minutes

local queue = {} -- ordered { name = "Name", kind = "summon" | "hs", time = GetTime() }
local frame, rows = nil, {}
local dirty = false

local function ShortName(name)
	return name and Ambiguate(name, "none")
end

local function Find(name, kind)
	for i, entry in ipairs(queue) do
		if entry.name == name and entry.kind == kind then return i end
	end
end

-- A unit's name the way chat and addon messages report it after Ambiguate:
-- "Name" for your realm, "Name-Realm" for players from other realms.
local function FullName(unit)
	if not UnitExists(unit) then return end
	local name = ns.Safe(GetUnitName(unit, true))
	return name and Ambiguate(name, "none")
end

-- Group unit token for a player name, for status checks.
local function UnitFor(name)
	if name == FullName("player") then return "player" end
	local prefix, count = "party", GetNumSubgroupMembers()
	if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
	for i = 1, count do
		local unit = prefix .. i
		if FullName(unit) == name then return unit end
	end
end
ns.UnitForName = UnitFor

local function Status(entry)
	local unit = UnitFor(entry.name)
	if not unit then return "not in group", 0.6, 0.6, 0.6 end
	if not UnitIsConnected(unit) then return "offline", 0.6, 0.6, 0.6 end
	if UnitIsDeadOrGhost(unit) then return "dead", 1, 0.3, 0.3 end
	if entry.kind == "summon" and C_IncomingSummon and C_IncomingSummon.HasIncomingSummon(unit) then
		return "summon pending", 0.2, 1, 0.2
	end
	return nil, 1, 1, 1
end

local function KindAvailable(kind)
	if kind == "summon" then return ns.db.summonQueue and ns.hasRitual end
	return ns.db.hsRequests and (ns.known.healthstone ~= nil or ns.stones.healthstone ~= nil)
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
		local entry = queue[i]
		if now - entry.time > EXPIRE or not UnitFor(entry.name) or not KindAvailable(entry.kind) then
			table.remove(queue, i)
		end
	end
	local ritual = C_Spell.GetSpellName(ns.Data.ritualOfSummoning)
	local portal = ns.hasPortal and C_Spell.GetSpellName(ns.Data.portalOfSummoning)
	for i, row in ipairs(rows) do
		local entry = queue[i]
		if entry then
			row.name, row.kind = entry.name, entry.kind
			if entry.kind == "summon" then
				row:SetAttribute("macrotext1", ("/target %s\n/cast %s"):format(entry.name, ritual))
				row:SetAttribute("shift-macrotext1", portal and ("/cast %s"):format(portal) or nil)
				row.icon:SetTexture(C_Spell.GetSpellTexture(ns.Data.ritualOfSummoning))
			else
				row:SetAttribute("macrotext1", "/target " .. entry.name)
				row:SetAttribute("shift-macrotext1", nil)
				local stone = ns.stones.healthstone
				row.icon:SetTexture(C_Item.GetItemIconByID(stone and stone.itemID or ns.Data.stones.healthstone[1].item))
			end
			local status, r, g, b = Status(entry)
			row.text:SetText(status and ("%s |cff999999(%s)|r"):format(entry.name, status) or entry.name)
			row.text:SetTextColor(r, g, b)
			row:Show()
		else
			row.name, row.kind = nil, nil
			row:Hide()
		end
	end
	local shown = math.min(#queue, MAX_ROWS)
	frame:SetHeight(24 + math.max(shown, 1) * ROW_HEIGHT)
	frame.empty:SetShown(shown == 0)
	frame:SetShown((shown > 0 or frame.pinned) and true or false)
end

local function Add(name, kind)
	name = ShortName(name)
	if not name or Find(name, kind) or UnitFor(name) == "player" then return end
	if not UnitFor(name) then return end -- only group members can be summoned or traded
	table.insert(queue, { name = name, kind = kind, time = GetTime() })
	PlaySound(SOUNDKIT.TELL_MESSAGE)
	if kind == "hs" and ns.db.hsAutoReply then
		local msg = ns.stones.healthstone and "Grimoire: you're on my healthstone list, I'll trade you one shortly."
			or "Grimoire: you're on my healthstone list; I'm making more and will trade you one."
		C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, name)
	end
	ns:UpdateSummonQueue()
end

local DONE = { summon = "DONE", hs = "HSDONE" }

local function Remove(name, kind, fromSync)
	local i = Find(name, kind)
	if not i then return end
	table.remove(queue, i)
	if not fromSync and ns.db.summonSync and ns.GroupChannel() then
		C_ChatInfo.SendAddonMessage(PREFIX, DONE[kind] .. ":" .. name, ns.GroupChannel())
	end
	ns:UpdateSummonQueue()
end

-- Called by Speech.lua when a Ritual of Summoning starts on a target.
function ns:OnSummonCast(name)
	Remove(ShortName(name), "summon")
end

function ns:ToggleSummonQueue()
	if not frame or InCombatLockdown() then return end
	frame.pinned = not frame:IsShown()
	ns:UpdateSummonQueue()
end

-- Chat parsing -------------------------------------------------------------------

local keywords = { summon = {}, hs = {} }
local function ParseList(list, text)
	wipe(list)
	for word in (text or ""):gmatch("[^,]+") do
		word = strtrim(word):lower()
		if word ~= "" then table.insert(list, word) end
	end
end
local function ParseKeywords()
	ParseList(keywords.summon, ns.db.summonKeywords)
	ParseList(keywords.hs, ns.db.hsKeywords)
end
ns.ParseSummonKeywords = ParseKeywords

local function Matches(msg, list)
	for _, word in ipairs(list) do
		if msg == word or msg:sub(1, #word + 1) == word .. " " then return true end
	end
end

local function OnChat(_, msg, sender)
	msg, sender = ns.Safe(msg), ns.Safe(sender)
	if not (msg and sender) then return end
	msg = strtrim(msg:lower())
	if KindAvailable("summon") and Matches(msg, keywords.summon) then
		Add(sender, "summon")
	elseif KindAvailable("hs") and Matches(msg, keywords.hs) then
		Add(sender, "hs")
	end
end

local function OnAddonMessage(_, prefix, msg, _, sender)
	if prefix ~= PREFIX or not ns.db.summonSync then return end
	msg, sender = ns.Safe(msg), ns.Safe(sender)
	if not msg or ShortName(sender) == ns.SafeUnitName("player") then return end
	local name = msg:match("^DONE:(.+)$")
	if name then return Remove(name, "summon", true) end
	name = msg:match("^HSDONE:(.+)$")
	if name then Remove(name, "hs", true) end
end

-- Frame -------------------------------------------------------------------------

ns:Module(function()
	ParseKeywords()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

	frame = CreateFrame("Frame", "GrimoireSummonQueue", UIParent, "BackdropTemplate")
	frame:SetSize(190, 24 + ROW_HEIGHT)
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
	title:SetText("Requests")
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
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
		row.icon:SetPoint("LEFT", 2, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.text = row:CreateFontString(nil, "OVERLAY")
		ns.Style.Font(row.text, 11)
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
		row:SetScript("PreClick", function(self, mouse, down)
			if not down and mouse == "LeftButton" and self.kind == "summon" and ns.NoteRitualClick then
				ns:NoteRitualClick(self.name, IsShiftKeyDown())
			end
		end)
		row:SetScript("PostClick", function(self, mouse, down)
			if down or not self.name then return end
			if mouse == "RightButton" then
				Remove(self.name, self.kind)
			elseif self.kind == "hs" and ns.stones.healthstone and not InCombatLockdown() then
				-- The secure click just targeted them; now open the trade with a stone.
				local name = self.name
				if ns:TradeHealthstone() then Remove(name, "hs") end
			end
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.name)
			if self.kind == "summon" then
				GameTooltip:AddLine("Click: target and Ritual of Summoning", 0.5, 0.5, 0.5)
				if ns.hasPortal then GameTooltip:AddLine("Shift-click: Portal of Summoning", 0.5, 0.5, 0.5) end
			else
				GameTooltip:AddLine(ns.stones.healthstone and "Click: target and trade a healthstone"
					or "Make a healthstone first", 0.5, 0.5, 0.5)
			end
			GameTooltip:AddLine("Right-click: remove", 0.5, 0.5, 0.5)
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
