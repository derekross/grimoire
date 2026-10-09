local addonName, ns = ...

local C_Container, C_Item, C_Spell, C_SpellBook = C_Container, C_Item, C_Spell, C_SpellBook
local InCombatLockdown, GetTime = InCombatLockdown, GetTime

local Grimoire = CreateFrame("Frame", "GrimoireCore")
ns.Grimoire = Grimoire
_G.Grimoire = ns

ns.defaults = {
	showBar = true,
	locked = false,
	point = { "CENTER", "UIParent", "CENTER", 0, -220 },
	scale = 1,
	buttonSize = 36,
	spacing = 4,
	vertical = false,
	shardLow = 3,
	shardCap = 0, -- 0 = off
	tradeOnRightClick = true,
	summonAnnounce = true,
	summonMessage = "Summoning %t, please click the portal!",
	weaponWarnMinutes = 5,
}

-- Secret values (Midnight/Forever addon restrictions) can't be compared or stored.
local issecretvalue = issecretvalue or function() return false end
function ns.Safe(value)
	if issecretvalue(value) then return nil end
	return value
end

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function ns.Print(...)
	print("|cff9482c9Grimoire:|r", ...)
end

-- Spell knowledge -------------------------------------------------------------

local function IsKnown(spellID)
	return spellID and C_SpellBook.IsSpellKnown(spellID) or false
end
ns.IsKnown = IsKnown

ns.known = {}  -- family -> { rank = n, spellID = id }
ns.demons = {} -- ordered list of known demon entries from ns.Data.demons

function ns:ScanSpells()
	for family, ranks in pairs(ns.Data.stones) do
		local best
		for i, rank in ipairs(ranks) do
			if IsKnown(rank.spell) then best = i end
		end
		ns.known[family] = best and { rank = best, spellID = ranks[best].spell } or nil
	end

	wipe(ns.demons)
	for _, demon in ipairs(ns.Data.demons) do
		if IsKnown(demon.spell) then
			table.insert(ns.demons, demon)
		end
	end

	ns.hasFelDomination = IsKnown(ns.Data.felDomination)
	ns.hasRitual = IsKnown(ns.Data.ritualOfSummoning)
end

-- Bag scan ----------------------------------------------------------------------

-- itemID -> family, rank. Unknown IDs fall back to an exact English name match so
-- a Forever re-ID doesn't silently break detection.
local itemIndex, nameIndex = {}, {}
local function BuildIndex()
	for family, ranks in pairs(ns.Data.stones) do
		for i, rank in ipairs(ranks) do
			if rank.item then itemIndex[rank.item] = { family = family, rank = i } end
			for _, alt in ipairs(rank.alt or {}) do itemIndex[alt] = { family = family, rank = i } end
			if rank.itemName then nameIndex[rank.itemName] = { family = family, rank = i } end
		end
	end
end

local function Classify(itemID)
	local entry = itemIndex[itemID]
	if entry ~= nil then
		if entry then return entry.family, entry.rank end
		return
	end
	local name = C_Item.GetItemNameByID(itemID)
	if not name then return end -- not cached yet; try again on the next scan
	entry = nameIndex[name] or false
	itemIndex[itemID] = entry
	if entry then return entry.family, entry.rank end
end

ns.shards = 0
ns.stones = {} -- family -> { itemID, rank, count, bag, slot }

function ns:ScanBags()
	local shards, stones = 0, {}
	local shardID = ns.Data.soulShard
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local itemID = info and ns.Safe(info.itemID)
			if itemID == shardID then
				shards = shards + (ns.Safe(info.stackCount) or 1)
			elseif itemID then
				local family, rank = Classify(itemID)
				if family then
					local current = stones[family]
					if not current or rank > current.rank then
						stones[family] = { itemID = itemID, rank = rank, bag = bag, slot = slot }
					end
				end
			end
		end
	end
	for _, stone in pairs(stones) do
		stone.count = C_Item.GetItemCount(stone.itemID)
	end
	ns.shards, ns.stones = shards, stones
end

-- Finds every bag slot holding a soul shard, highest bag/slot first so deletions
-- take shards from the end of the bags.
function ns:ShardSlots()
	local slots = {}
	for bag = NUM_BAG_SLOTS, 0, -1 do
		for slot = C_Container.GetContainerNumSlots(bag), 1, -1 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and ns.Safe(info.itemID) == ns.Data.soulShard then
				table.insert(slots, { bag = bag, slot = slot })
			end
		end
	end
	return slots
end

-- Main hand temporary enchant (Firestone/Spellstone in Forever).
function ns:WeaponEnchantState()
	local enchants = C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.MainHand)
	local best
	for _, enchant in pairs(enchants or {}) do
		local has, left = ns.Safe(enchant.hasEnchant), ns.Safe(enchant.timeLeft)
		if has and left and (not best or left > best) then best = left end
	end
	return best and best / 1000 or nil -- seconds left, or nil when none
end

-- Combat-safe update scheduling -----------------------------------------------

function ns:Refresh()
	ns:ScanBags()
	if InCombatLockdown() then
		ns.secureDirty = true
	elseif ns.UpdateSecure then
		ns:UpdateSecure()
	end
	if ns.UpdateVisuals then ns:UpdateVisuals() end
	if ns.UpdateDataText then ns:UpdateDataText() end
	ns:CheckShardCap()
end

-- Shard cap ---------------------------------------------------------------------

StaticPopupDialogs.GRIMOIRE_DELETE_SHARDS = {
	text = "Grimoire: you have %d Soul Shards. Delete %d to get back to %d?",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(_, data) ns:DeleteShards(data) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns:CheckShardCap()
	local cap = GrimoireDB and GrimoireDB.shardCap or 0
	if cap <= 0 or InCombatLockdown() then return end
	local extra = ns.shards - cap
	if extra <= 0 then
		ns.lastCapPrompt = nil
		return
	end
	-- Prompt once per new shard count so a dismissed prompt doesn't nag.
	if ns.lastCapPrompt == ns.shards then return end
	ns.lastCapPrompt = ns.shards
	StaticPopup_Show("GRIMOIRE_DELETE_SHARDS", ns.shards, extra, cap, extra)
end

function ns:DeleteShards(count)
	if InCombatLockdown() then return end
	ClearCursor()
	local deleted = 0
	for _, pos in ipairs(ns:ShardSlots()) do
		if deleted >= count then break end
		C_Container.PickupContainerItem(pos.bag, pos.slot)
		if CursorHasItem() then
			DeleteCursorItem()
			deleted = deleted + 1
		end
	end
	ClearCursor()
end

-- Healthstone upgrade (delete the outdated stone) ------------------------------

StaticPopupDialogs.GRIMOIRE_DELETE_STONE = {
	text = "Grimoire: delete your outdated %s so you can make a new one?",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(_, data)
		if InCombatLockdown() then return end
		local stone = ns.stones[data]
		if not stone then return end
		ClearCursor()
		C_Container.PickupContainerItem(stone.bag, stone.slot)
		if CursorHasItem() then DeleteCursorItem() end
		ClearCursor()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns:IsOutdated(family)
	local stone, known = ns.stones[family], ns.known[family]
	return stone and known and stone.rank < known.rank or false
end

function ns:PromptUpgrade(family)
	if InCombatLockdown() or not ns:IsOutdated(family) then return end
	local name = C_Item.GetItemNameByID(ns.stones[family].itemID) or family
	StaticPopup_Show("GRIMOIRE_DELETE_STONE", name, nil, family)
end

-- Healthstone trade --------------------------------------------------------------

function ns:TradeHealthstone()
	if InCombatLockdown() or not ns.stones.healthstone then return end
	if not (UnitIsPlayer("target") and UnitIsFriend("player", "target") and not UnitIsUnit("target", "player")) then
		ns.Print("Target a friendly player to trade them a healthstone.")
		return
	end
	if TradeFrame and TradeFrame:IsShown() then
		ns:PlaceHealthstoneInTrade()
	else
		ns.pendingTrade = GetTime()
		InitiateTrade("target")
	end
end

function ns:PlaceHealthstoneInTrade()
	local stone = ns.stones.healthstone
	if not stone then return end
	ClearCursor()
	C_Container.PickupContainerItem(stone.bag, stone.slot)
	if CursorHasItem() then
		ClickTradeButton(1)
	end
	ClearCursor()
end

-- Soulstone / ritual bookkeeping -------------------------------------------------

local function SafeUnitName(unit)
	if not UnitExists(unit) then return end
	return ns.Safe(UnitName(unit))
end

function ns:SoulstoneTargetName()
	if UnitExists("mouseover") and UnitCanAssist("player", "mouseover") and not UnitIsDead("mouseover") then
		return SafeUnitName("mouseover")
	elseif UnitExists("target") and UnitCanAssist("player", "target") and not UnitIsDead("target") then
		return SafeUnitName("target")
	end
	return SafeUnitName("player")
end

function ns:NoteSoulstoneClick()
	ns.pendingSoulstone = { name = ns:SoulstoneTargetName(), time = GetTime() }
end

function ns:NoteRitualClick()
	ns.pendingRitual = { name = SafeUnitName("target"), time = GetTime() }
end

local function ChatChannel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
end

local function OnPlayerCast(event, spellID)
	spellID = ns.Safe(spellID)
	local now = GetTime()

	local ritual = ns.pendingRitual
	if event == "UNIT_SPELLCAST_START" and ritual and now - ritual.time < 2
		and (spellID == nil or spellID == ns.Data.ritualOfSummoning) then
		ns.pendingRitual = nil
		local channel = ChatChannel()
		if GrimoireDB.summonAnnounce and channel and ritual.name then
			local msg = GrimoireDB.summonMessage:gsub("%%t", ritual.name)
			C_ChatInfo.SendChatMessage(msg, channel)
		end
	end

	local ss = ns.pendingSoulstone
	if event == "UNIT_SPELLCAST_SUCCEEDED" and ss and now - ss.time < 3 then
		local name = spellID and C_Spell.GetSpellName(spellID)
		if spellID == nil or (name and name:find(ns.Data.soulstoneKeyword)) then
			ns.pendingSoulstone = nil
			GrimoireCharDB.lastSoulstone = { name = ss.name, time = time() }
			if ns.UpdateVisuals then ns:UpdateVisuals() end
		end
	end
end

-- Events --------------------------------------------------------------------------

Grimoire:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		local _, class = UnitClass("player")
		if class ~= "WARLOCK" then
			self:UnregisterAllEvents()
			return
		end
		GrimoireDB = CopyDefaults(ns.defaults, GrimoireDB or {})
		GrimoireCharDB = GrimoireCharDB or {}
		ns.db = GrimoireDB
		BuildIndex()
		ns:ScanSpells()
		ns:ScanBags()
		ns:CreateBar()
		if ns.SetupOptions then ns:SetupOptions() end
		if ns.SetupElvUI then ns:SetupElvUI() end

		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("BAG_UPDATE_DELAYED")
		self:RegisterEvent("BAG_UPDATE_COOLDOWN")
		self:RegisterEvent("SPELLS_CHANGED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("TRADE_SHOW")
		self:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		self:RegisterUnitEvent("UNIT_PET", "player")
		ns:Refresh()
	elseif event == "SPELLS_CHANGED" then
		ns:ScanSpells()
		ns:Refresh()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE_DELAYED" then
		ns:Refresh()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.secureDirty then
			ns.secureDirty = nil
			ns:UpdateSecure()
		end
		ns:Refresh()
	elseif event == "PLAYER_REGEN_DISABLED" then
		if ns.CloseFlyout then ns:CloseFlyout() end
	elseif event == "TRADE_SHOW" then
		if ns.pendingTrade and GetTime() - ns.pendingTrade < 10 then
			ns.pendingTrade = nil
			ns:PlaceHealthstoneInTrade()
		end
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, _, spellID = ...
		OnPlayerCast(event, spellID)
	else -- BAG_UPDATE_COOLDOWN, UNIT_INVENTORY_CHANGED, UNIT_PET
		if ns.UpdateVisuals then ns:UpdateVisuals() end
	end
end)
Grimoire:RegisterEvent("PLAYER_LOGIN")

-- Weapon enchants have no event when they expire, so poll the glow cheaply.
C_Timer.NewTicker(5, function()
	if ns.UpdateWeaponGlow then ns:UpdateWeaponGlow() end
end)
