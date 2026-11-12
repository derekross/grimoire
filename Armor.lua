local addonName, ns = ...

-- Armor alerts: a warning before Demon Armor/Skin runs out, and a sound when you have
-- no armor on. Forever hides auras from addons in combat, so the expiry is read out of
-- combat and counted down from there; a recast in combat restarts the count from the
-- spell's duration. "No armor" is only checked out of combat (and not while dead or on
-- a flight), so it waits until a fight ends. A dispel in combat goes unseen until then.

local GetTime = GetTime
local DEFAULT_DURATION = 30 * 60
local SETTLE = 5 -- seconds after a loading screen before nagging

local state = {
	expires = nil,       -- GetTime() when the armor runs out, if known
	duration = DEFAULT_DURATION,
	warned = false,      -- the running-out warning already fired for this cast
	missing = false,     -- out of combat, no armor was found
	nextNag = nil,       -- when the next "no armor" alert is due
	quietUntil = 0,
}

local isArmor = {}
for _, id in ipairs(ns.Data.armor) do isArmor[id] = true end

local function ArmorSpell()
	return ns.BestSpell(ns.Data.buffs[1])
end

local function ArmorName(spellID)
	local name = spellID and C_Spell.GetSpellName(spellID)
	return ns.Safe(name) or "Demon Armor"
end

local function FormatLeft(sec)
	if sec >= 60 then return ("%d:%02d"):format(sec / 60, sec % 60) end
	return ("%d sec"):format(sec)
end

local function Notice(msg)
	RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING)
end

-- Out of combat: true plus the expiry (nil if it has none) when armor is on, false when
-- there's none. nil when it can't tell (in combat, or the data is secret).
local function ReadArmor()
	if InCombatLockdown() then return nil end
	for _, id in ipairs(ns.Data.armor) do
		local aura, readable = ns.ReadAura("player", id)
		if not readable then return nil end
		if aura then
			local expires, duration = ns.Safe(aura.expirationTime), ns.Safe(aura.duration)
			if duration and duration > 0 then state.duration = duration end
			return true, (expires and expires > 0) and expires or nil, id
		end
	end
	return false
end

local function CanNag(now)
	return now >= state.quietUntil and not UnitIsDeadOrGhost("player") and not UnitOnTaxi("player")
end

local function SetLow(low)
	if low == ns.armorLow then return end
	ns.armorLow = low
	if ns.UpdateArmorGlow then ns:UpdateArmorGlow() end
end

local function Tick()
	local db = ns.db
	if not db then return end
	local now = GetTime()

	local on, expires, spellID = ReadArmor()
	if on then
		state.missing, state.nextNag = false, nil
		state.spellID = spellID
		if expires ~= state.expires then
			state.expires = expires
			state.warned = false
		end
	elseif on == false then
		state.expires = nil
		if not state.missing then
			state.missing = true
			state.nextNag = now
		end
	elseif state.expires and now >= state.expires then
		state.expires = nil -- ran out in combat; the next out-of-combat read confirms it
	end

	-- Running out
	local warnAt = db.armorWarnSeconds or 0
	local left = state.expires and state.expires - now
	SetLow(left ~= nil and warnAt > 0 and left <= warnAt and ArmorSpell() ~= nil)
	if left and warnAt > 0 and not state.warned and left > 0 and left <= warnAt then
		state.warned = true
		Notice(("%s: %s left"):format(ArmorName(state.spellID), FormatLeft(left)))
		if db.armorWarnSound then PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_2) end
	end

	-- None on
	if on == false and state.nextNag and now >= state.nextNag and CanNag(now) then
		local spell = ArmorSpell()
		if spell and db.armorMissingAlert then
			Notice(("No armor! Cast %s"):format(ArmorName(spell)))
			PlaySound(SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING)
		end
		local every = db.armorNagSeconds or 0
		state.nextNag = every > 0 and now + every or nil
	end
end

-- A recast in combat can't be read, so restart the count from the last known duration.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	spellID = ns.Safe(spellID)
	if unit ~= "player" or not spellID or not isArmor[spellID] then return end
	state.expires = GetTime() + state.duration
	state.spellID = spellID
	state.warned, state.missing, state.nextNag = false, false, nil
	SetLow(false)
end)

ns:On("PLAYER_ENTERING_WORLD", function()
	state.quietUntil = GetTime() + SETTLE
end)

ns:Module(function()
	C_Timer.NewTicker(1, Tick)
end)
