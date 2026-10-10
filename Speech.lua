local addonName, ns = ...

-- Chat messages for warlock moments. Addons can only post to party/raid (and whispers)
-- from events: open-world /say and /yell need a hardware click, so everything here goes
-- to the group channel and is skipped when solo. %t = target, %d = demon.

ns.lines = {
	summon = nil, -- uses ns.db.summonMessage
	soulstone = {
		"%t's soul is now bound to my stone. Die freely.",
		"Soulstone on %t. Death is only a minor inconvenience now.",
		"%t, I have your soul. You'll get it back if you die.",
	},
	soulstoneWhisper = "I've soulstoned you. If you die, you can resurrect yourself.",
	demon = {
		"Come forth, %d!",
		"By the pact I command you: %d, rise!",
		"The Twisting Nether yields %d to my will.",
	},
	mount = {
		"My steed answers from the Nether.",
		"Hooves of flame, carry me.",
	},
}

local function Pick(list)
	return list[math.random(#list)]
end

local function Say(msg)
	local channel = ns.GroupChannel()
	if channel and msg then C_ChatInfo.SendChatMessage(msg, channel) end
end

-- Clicks record who the cast is aimed at; the cast events confirm it happened.

function ns:NoteSoulstoneClick()
	ns.pendingSoulstone = { name = ns:SoulstoneTargetName(), time = GetTime() }
end

function ns:NoteRitualClick(name, portal)
	ns.pendingRitual = { name = name, portal = portal, time = GetTime() }
end

local function IsSpell(spellID, entryList)
	for _, entry in ipairs(entryList) do
		if entry.spell == spellID then return entry end
		for _, id in ipairs(entry.ranks or {}) do
			if id == spellID then return entry end
		end
	end
end

local function OnCastStart(_, _, _, spellID)
	spellID = ns.Safe(spellID)
	local ritual = ns.pendingRitual
	if ritual and GetTime() - ritual.time < 2
		and (spellID == nil or spellID == ns.Data.ritualOfSummoning or spellID == ns.Data.portalOfSummoning) then
		ns.pendingRitual = nil
		if ns.db.summonAnnounce and (ritual.name or ritual.portal) then
			local msg = ritual.portal and "Opening a Portal of Summoning, please click it!"
				or ns.db.summonMessage:gsub("%%t", ritual.name)
			Say(msg)
		end
		if ritual.name and ns.OnSummonCast then ns:OnSummonCast(ritual.name) end
	end

	if spellID and ns.db.speech.demon then
		local demon = IsSpell(spellID, ns.Data.demons)
		if demon then
			local demonName = (C_Spell.GetSpellName(spellID) or "demon"):gsub("^Summon ", "")
			Say((Pick(ns.lines.demon):gsub("%%d", demonName)))
		end
	end
	if spellID and ns.db.speech.mount then
		for _, id in ipairs(ns.Data.mounts) do
			if id == spellID then Say(Pick(ns.lines.mount)) end
		end
	end
end

local function OnCastSucceeded(_, _, _, spellID)
	spellID = ns.Safe(spellID)
	local ss = ns.pendingSoulstone
	if not ss or GetTime() - ss.time > 3 then return end
	local name = spellID and C_Spell.GetSpellName(spellID)
	-- Item use spells are "Soulstone Resurrection"; a secret spell ID still counts.
	if spellID ~= nil and not (name and name:find(ns.Data.soulstoneKeyword)) then return end
	ns.pendingSoulstone = nil
	ns.char.lastSoulstone = { name = ss.name, time = time(), warned = nil }
	if ns.StartSoulstoneTimer then ns:StartSoulstoneTimer() end
	if ns.OnSoulstone then ns:OnSoulstone(ss.name) end
	ns:UpdateVisuals()

	if ss.name and ss.name ~= ns.SafeUnitName("player") then
		if ns.db.speech.soulstone then
			Say((Pick(ns.lines.soulstone):gsub("%%t", ss.name)))
		end
		if ns.db.speech.soulstoneWhisper then
			C_ChatInfo.SendChatMessage(ns.lines.soulstoneWhisper, "WHISPER", nil, ss.name)
		end
	end
end

ns:On("UNIT_SPELLCAST_START", OnCastStart)
ns:On("UNIT_SPELLCAST_SUCCEEDED", OnCastSucceeded)
