local addonName, ns = ...

-- Timer bars and alerts. Forever hides auras and the combat log from addons in
-- combat, so CC timers are estimates started from your own successful casts: they
-- can't see early breaks or resists. Recasting the same spell replaces its bar.

local GetTime = GetTime
local SOULSTONE_DURATION = 30 * 60
local SOULSTONE_WARN = 5 * 60
local SUBJUGATE_WARN = 30
local BAR_HEIGHT = 16

local anchor
local bars, pool = {}, {}

local function FormatTime(sec)
	if sec >= 60 then return ("%d:%02d"):format(sec / 60, sec % 60) end
	return ("%.0f"):format(sec)
end

local function AcquireBar()
	local bar = table.remove(pool)
	if bar then return bar end
	bar = CreateFrame("StatusBar", nil, anchor)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetHeight(BAR_HEIGHT)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
	bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
	bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.label:SetPoint("LEFT", 4, 0)
	bar.label:SetJustifyH("LEFT")
	bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.time:SetPoint("RIGHT", -4, 0)
	if ns.SkinTimerBar then ns.SkinTimerBar(bar) end
	return bar
end

local function Layout()
	table.sort(bars, function(a, b) return a.expires < b.expires end)
	local prev
	for _, bar in ipairs(bars) do
		bar:ClearAllPoints()
		bar:SetPoint("LEFT", anchor, "LEFT", BAR_HEIGHT + 2, 0)
		bar:SetPoint("RIGHT", anchor, "RIGHT")
		if prev then
			bar:SetPoint("BOTTOM", prev, "TOP", 0, 2)
		else
			bar:SetPoint("BOTTOM", anchor, "BOTTOM")
		end
		prev = bar
	end
end

local function RemoveBar(bar)
	for i, b in ipairs(bars) do
		if b == bar then table.remove(bars, i) break end
	end
	bar:Hide()
	table.insert(pool, bar)
	Layout()
end

-- id identifies what the bar tracks, so a recast replaces the old bar.
function ns:StartTimer(id, label, icon, duration, color, opts)
	if not anchor then return end
	for _, b in ipairs(bars) do
		if b.id == id then RemoveBar(b) break end
	end
	local bar = AcquireBar()
	bar.id = id
	bar.duration = duration
	bar.expires = GetTime() + duration
	bar.opts = opts or {}
	bar.warned = nil
	bar:SetMinMaxValues(0, duration)
	bar:SetStatusBarColor(unpack(color or { 0.58, 0.51, 0.79 }))
	bar.icon:SetTexture(icon)
	bar.label:SetText(label)
	bar:Show()
	table.insert(bars, bar)
	Layout()
	return bar
end

function ns:StopTimer(id)
	for _, b in ipairs(bars) do
		if b.id == id then RemoveBar(b) return end
	end
end

local elapsedSince = 0
local function OnUpdate(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.1 then return end
	elapsedSince = 0
	local now = GetTime()
	for i = #bars, 1, -1 do
		local bar = bars[i]
		local left = bar.expires - now
		if left <= 0 then
			if bar.opts.onExpire then bar.opts.onExpire() end
			RemoveBar(bar)
		else
			bar:SetValue(left)
			bar.time:SetText(FormatTime(left))
			if bar.opts.warnAt and not bar.warned and left <= bar.opts.warnAt then
				bar.warned = true
				bar.opts.onWarn()
			end
		end
	end
end

local function Alert(msg)
	RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING)
	PlaySound(SOUNDKIT.RAID_WARNING)
end

-- Crowd control -----------------------------------------------------------------

local sent = {} -- castGUID -> target name from UNIT_SPELLCAST_SENT

local function ControlEntry(spellID)
	for _, entry in ipairs(ns.Data.control) do
		local rank = ns.RankOf(entry, spellID)
		if rank then return entry, rank end
	end
end

local function OnSent(_, _, target, castGUID, spellID)
	castGUID, spellID = ns.Safe(castGUID), ns.Safe(spellID)
	if castGUID and spellID and ControlEntry(spellID) then
		sent[castGUID] = ns.Safe(target)
	end
end

local function OnSucceeded(_, _, castGUID, spellID)
	castGUID, spellID = ns.Safe(castGUID), ns.Safe(spellID)
	if not (castGUID and spellID and ns.db.timers) then return end
	local entry, rank = ControlEntry(spellID)
	if not entry then return end
	local target = sent[castGUID]
	sent[castGUID] = nil
	local name = C_Spell.GetSpellName(spellID)
	local duration = entry.durations[rank]
	local label = target and target ~= "" and ("%s: %s"):format(name, target) or name
	local opts
	if entry.subjugate then
		opts = { warnAt = SUBJUGATE_WARN, onWarn = function() Alert("Subjugate Demon ends in 30 seconds!") end,
			onExpire = function() Alert("Subjugate Demon has ended!") end }
	elseif entry.banish then
		opts = { warnAt = 5, onWarn = function() Alert("Banish ends in 5 seconds!") end }
	end
	-- Fear and Howl share one bar per target name; Death Coil is short enough to just show.
	ns:StartTimer("cc:" .. name .. ":" .. (target or ""), label, C_Spell.GetSpellTexture(spellID), duration,
		entry.subjugate and { 0.2, 0.8, 0.2 } or { 0.58, 0.51, 0.79 }, opts)
end

-- Soulstone ---------------------------------------------------------------------

function ns:StartSoulstoneTimer()
	local last = ns.char.lastSoulstone
	if not (last and last.time and ns.db.soulstoneTimer) then return end
	local left = SOULSTONE_DURATION - (time() - last.time)
	if left <= 0 then return end
	local icon = C_Item.GetItemIconByID(ns.Data.stones.soulstone[1].item)
	ns:StartTimer("soulstone", "Soulstone: " .. (last.name or "?"), icon, left, { 0.9, 0.3, 0.9 }, {
		warnAt = SOULSTONE_WARN,
		onWarn = function()
			if not last.warned then
				last.warned = true
				Alert(("Soulstone on %s expires in 5 minutes."):format(last.name or "?"))
			end
		end,
		onExpire = function() ns.Print(("Soulstone on %s has expired."):format(last.name or "?")) end,
	})
end

-- Creature alert ------------------------------------------------------------------

local function UpdateCreatureAlert()
	local alert
	if ns.db.creatureAlert and UnitExists("target") and UnitCanAttack("player", "target") then
		local kind = ns.Safe(UnitCreatureType("target"))
		local banish = ns.BestSpell(ns.Data.control[1])
		local subjugate = ns.BestSpell(ns.Data.control[4])
		if kind == "Demon" and (banish or subjugate) then
			alert = "Demon: can be Banished or Subjugated."
		elseif kind == "Elemental" and banish then
			alert = "Elemental: can be Banished."
		end
	end
	if alert ~= ns.creatureAlert then
		ns.creatureAlert = alert
		ns:UpdateVisuals()
	end
end

-- Shadow Trance ---------------------------------------------------------------------

local trance

local function SetTrance(on)
	if not ns.db.shadowTranceAlert then on = false end
	if on == trance.active then return end
	trance.active = on
	if on then
		trance:Show()
		trance.anim:Play()
		if ns.db.shadowTranceSound then PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3) end
	else
		trance.anim:Stop()
		trance:Hide()
	end
end

-- Out of combat the aura can be read directly.
local function CheckTranceAura()
	if InCombatLockdown() then return end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(ns.Data.shadowTrance)
	if issecretvalue and issecretvalue(aura) then return end
	SetTrance(aura ~= nil)
end

-- In combat, use the aura update payload when its fields aren't secret.
local function OnAura(_, _, info)
	if not trance then return end
	if not InCombatLockdown() or not info or info.isFullUpdate then
		return CheckTranceAura()
	end
	for _, aura in ipairs(info.addedAuras or {}) do
		if ns.Safe(aura.spellId) == ns.Data.shadowTrance then
			trance.instanceID = ns.Safe(aura.auraInstanceID)
			SetTrance(true)
		end
	end
	if trance.instanceID then
		for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
			if ns.Safe(id) == trance.instanceID then
				trance.instanceID = nil
				SetTrance(false)
			end
		end
	end
end

local function CreateTrance()
	trance = CreateFrame("Frame", "GrimoireShadowTrance", UIParent)
	trance:SetSize(48, 48)
	trance:SetPoint("BOTTOM", ns.bar, "TOP", 0, 60)
	trance:Hide()
	local icon = trance:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(C_Spell.GetSpellTexture(ns.Data.shadowTrance) or 136223)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local text = trance:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	text:SetPoint("TOP", trance, "BOTTOM", 0, -2)
	text:SetText("Shadow Trance!")
	local anim = trance:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local pulse = anim:CreateAnimation("Alpha")
	pulse:SetFromAlpha(1)
	pulse:SetToAlpha(0.4)
	pulse:SetDuration(0.4)
	trance.anim = anim
end

-- Setup ---------------------------------------------------------------------------

ns:Module(function()
	anchor = CreateFrame("Frame", "GrimoireTimers", UIParent)
	anchor:SetSize(200, BAR_HEIGHT)
	anchor:SetPoint("BOTTOMLEFT", ns.bar, "TOPLEFT", 0, 6)
	anchor:SetScript("OnUpdate", OnUpdate)
	CreateTrance()
	ns:StartSoulstoneTimer()
	if ns.SetupTimerMovers then ns:SetupTimerMovers(anchor, trance) end
end)

ns:On("UNIT_SPELLCAST_SENT", OnSent)
ns:On("UNIT_SPELLCAST_SUCCEEDED", OnSucceeded)
ns:On("PLAYER_TARGET_CHANGED", UpdateCreatureAlert)
ns:On("PLAYER_ENTERING_WORLD", UpdateCreatureAlert)
ns:On("SPELL_ACTIVATION_OVERLAY_SHOW", function(_, spellID)
	if ns.Safe(spellID) == ns.Data.shadowTrance then SetTrance(true) end
end)
ns:On("SPELL_ACTIVATION_OVERLAY_HIDE", function(_, spellID)
	if ns.Safe(spellID) == ns.Data.shadowTrance then SetTrance(false) end
end)
ns:On("UNIT_AURA", OnAura)
-- Shadow Bolt consumes the proc; if the aura can't be read in combat, clear on the next bolt.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, _, spellID)
	local name = ns.Safe(spellID) and C_Spell.GetSpellName(spellID)
	if name == "Shadow Bolt" and trance and trance.active then SetTrance(false) end
end)
ns:On("PLAYER_REGEN_ENABLED", function() if trance then CheckTranceAura() end end)
