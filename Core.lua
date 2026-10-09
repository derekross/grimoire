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
	ring = false, -- book in the center, buttons in a circle around it
	roundButtons = true, -- round buttons in the ring layout
	ringAngle = 90, -- degrees; 90 = first button at the top
	ringRadius = 1,
	ringClockwise = true,
	menuAutoHide = 2, -- seconds after the mouse leaves an open menu
	bookMode = "shards", -- shards | soulstone | mana
	hidden = {}, -- bar button key -> true to hide it
	shardLow = 3,
	shardCap = 0, -- 0 = off
	sortShards = true,
	tradeOnRightClick = true,
	weaponWarnMinutes = 5,
	defaults = {}, -- menu key -> spell entry index picked as that menu's default
	armorReminder = true,

	-- Timers and alerts
	timers = true,
	soulstoneTimer = true,
	creatureAlert = true,
	shadowTranceAlert = true,
	shadowTranceSound = true,

	-- Summoning
	summonAnnounce = true,
	summonMessage = "Summoning %t, please click the portal!",
	summonQueue = true,
	summonKeywords = "123, summon, summ, sum pls, port pls",
	summonSync = true,

	-- Chat messages ("speech"): sent to party/raid only; open-world /say is blocked for addons.
	speech = {
		soulstone = true,
		soulstoneWhisper = true,
		demon = false,
		mount = false,
	},
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

-- Event dispatch: modules call ns:On(event, handler) -------------------------------

local handlers = {}
local unitEvents = {
	UNIT_INVENTORY_CHANGED = true, UNIT_PET = true, UNIT_AURA = true,
	UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_SUCCEEDED = true,
	UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true,
}

function ns:On(event, handler)
	if not handlers[event] then
		handlers[event] = {}
		if ns.ready then
			if unitEvents[event] then
				Grimoire:RegisterUnitEvent(event, "player")
			else
				Grimoire:RegisterEvent(event)
			end
		end
	end
	table.insert(handlers[event], handler)
end

local function Dispatch(event, ...)
	for _, handler in ipairs(handlers[event] or {}) do
		handler(event, ...)
	end
end
ns.Dispatch = Dispatch

-- Spell knowledge -------------------------------------------------------------

local function IsKnown(spellID)
	return spellID and C_SpellBook.IsSpellKnown(spellID) or false
end
ns.IsKnown = IsKnown

-- Highest known rank of a spell entry ({ ranks = { id, ... } } or { spell = id }).
function ns.BestSpell(entry)
	if entry.spell then return IsKnown(entry.spell) and entry.spell or nil end
	local best
	for _, id in ipairs(entry.ranks) do
		if IsKnown(id) then best = id end
	end
	if not best and entry.fallback then
		return ns.BestSpell({ ranks = entry.fallback })
	end
	return best
end

-- Rank index (1-based) of a spell ID within an entry, for per-rank data like durations.
function ns.RankOf(entry, spellID)
	for i, id in ipairs(entry.ranks or {}) do
		if id == spellID then return i end
	end
end

ns.known = {}  -- stone family -> { rank = n, spellID = id }
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
	ns.hasPortal = ns.Data.portalOfSummoning and IsKnown(ns.Data.portalOfSummoning) or false
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

local SOUL_BAG = 0x0004 -- bag family flag for soul bags

local function IsSoulBag(bag)
	if bag == 0 then return false end
	local _, family = C_Container.GetContainerNumFreeSlots(bag)
	family = ns.Safe(family)
	return family and bit.band(family, SOUL_BAG) ~= 0 or false
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
	if ns.shards and shards > ns.shards and ns.sessionShards then
		ns.sessionShards = ns.sessionShards + (shards - ns.shards)
	end
	ns.shards, ns.stones = shards, stones
end

-- Every bag slot holding a soul shard, last bag/slot first so deletions take
-- shards from the end of the bags.
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

-- Moves one stray shard into a soul bag per bag update; the next BAG_UPDATE_DELAYED
-- moves the next one, which keeps us clear of item locks.
function ns:SortShards()
	if not ns.db.sortShards or InCombatLockdown() or CursorHasItem() then return end
	local target
	for bag = 1, NUM_BAG_SLOTS do
		if IsSoulBag(bag) then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				if not C_Container.GetContainerItemInfo(bag, slot) then
					target = { bag = bag, slot = slot }
					break
				end
			end
		end
		if target then break end
	end
	if not target then return end
	for _, pos in ipairs(ns:ShardSlots()) do
		if not IsSoulBag(pos.bag) then
			local info = C_Container.GetContainerItemInfo(pos.bag, pos.slot)
			if info and not ns.Safe(info.isLocked) then
				C_Container.PickupContainerItem(pos.bag, pos.slot)
				C_Container.PickupContainerItem(target.bag, target.slot)
				ClearCursor()
			end
			return
		end
	end
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

-- True when the player has none of the given spell IDs as an aura. Only meaningful
-- out of combat, where aura data isn't secret; returns nil when it can't tell.
function ns:MissingAura(spellIDs)
	if InCombatLockdown() then return nil end
	for _, id in ipairs(spellIDs) do
		local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
		if issecretvalue(aura) then return nil end
		if aura then return false end
	end
	return true
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
	ns:SortShards()
end

-- Marks secure state stale; it's rebuilt now, or when combat ends.
function ns:RequestSecureUpdate()
	if InCombatLockdown() then
		ns.secureDirty = true
	elseif ns.UpdateSecure then
		ns:UpdateSecure()
	end
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
	local cap = ns.db and ns.db.shardCap or 0
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

-- Stone upgrade (delete the outdated stone) ------------------------------------

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

-- Units ------------------------------------------------------------------------

function ns.SafeUnitName(unit)
	if not UnitExists(unit) then return end
	return ns.Safe(UnitName(unit))
end

function ns:SoulstoneTargetName()
	if UnitExists("mouseover") and UnitCanAssist("player", "mouseover") and not UnitIsDead("mouseover") then
		return ns.SafeUnitName("mouseover")
	elseif UnitExists("target") and UnitCanAssist("player", "target") and not UnitIsDead("target") then
		return ns.SafeUnitName("target")
	end
	return ns.SafeUnitName("player")
end

function ns.GroupChannel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
end

-- Events --------------------------------------------------------------------------

local function OnLogin()
	local _, class = UnitClass("player")
	if class ~= "WARLOCK" then
		Grimoire:UnregisterAllEvents()
		return
	end
	GrimoireDB = CopyDefaults(ns.defaults, GrimoireDB or {})
	GrimoireCharDB = GrimoireCharDB or {}
	ns.db = GrimoireDB
	ns.char = GrimoireCharDB
	ns.sessionShards = 0
	BuildIndex()
	ns:ScanSpells()
	ns:ScanBags()
	ns:CreateBar()
	if ns.SetupOptions then ns:SetupOptions() end
	-- ElvUI styles the bar once it has initialized; otherwise style it now.
	if ns.SetupElvUI then ns:SetupElvUI() else ns:ApplyStyle() end

	ns.ready = true
	for event in pairs(handlers) do
		if unitEvents[event] then
			Grimoire:RegisterUnitEvent(event, "player")
		else
			Grimoire:RegisterEvent(event)
		end
	end
	ns:Refresh()
end

-- Modules add an init function that runs once the bar exists and is styled
-- (so their frames pick up the theme, e.g. ElvUI's fonts).
function ns:Module(init)
	ns.modules = ns.modules or {}
	table.insert(ns.modules, init)
end

function ns:StartModules()
	if ns.modulesStarted then return end
	ns.modulesStarted = true
	for _, init in ipairs(ns.modules or {}) do init() end
end

ns:On("SPELLS_CHANGED", function()
	ns:ScanSpells()
	ns:Refresh()
end)
ns:On("PLAYER_ENTERING_WORLD", function() ns:Refresh() end)
ns:On("BAG_UPDATE_DELAYED", function() ns:Refresh() end)
ns:On("PLAYER_REGEN_ENABLED", function()
	if ns.secureDirty then
		ns.secureDirty = nil
		ns:UpdateSecure()
	end
	ns:Refresh()
end)
ns:On("PLAYER_REGEN_DISABLED", function()
	if ns.CloseMenus then ns:CloseMenus() end
end)
ns:On("TRADE_SHOW", function()
	if ns.pendingTrade and GetTime() - ns.pendingTrade < 10 then
		ns.pendingTrade = nil
		ns:PlaceHealthstoneInTrade()
	end
end)
local function Visuals() if ns.UpdateVisuals then ns:UpdateVisuals() end end
ns:On("BAG_UPDATE_COOLDOWN", Visuals)
ns:On("UNIT_INVENTORY_CHANGED", Visuals)
ns:On("UNIT_PET", Visuals)
ns:On("UPDATE_BINDINGS", Visuals)

Grimoire:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		OnLogin()
	else
		Dispatch(event, ...)
	end
end)
Grimoire:RegisterEvent("PLAYER_LOGIN")

-- Weapon enchants and the armor reminder have no reliable event, so poll cheaply.
C_Timer.NewTicker(5, function()
	if ns.UpdateWeaponGlow then ns:UpdateWeaponGlow() end
	if ns.UpdateArmorGlow then ns:UpdateArmorGlow() end
end)
