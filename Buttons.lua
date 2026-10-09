local addonName, ns = ...

local C_Item, C_Spell = C_Item, C_Spell
local InCombatLockdown, GameTooltip = InCombatLockdown, GameTooltip

local NOOP = "grimoire_noop" -- secure action type with no handler: the click does nothing secure
local FLYOUT_PRE = [[ return nil, true ]] -- keep the click, ask for the post body
local FLYOUT_CLOSE = [[ owner:GetFrameRef("flyout"):Hide() ]]

local bar, flyout
local buttons = {}
ns.buttons = buttons

-- Helpers -----------------------------------------------------------------------

local function StoneItem(family)
	local stone = ns.stones[family]
	return stone and stone.itemID
end

-- The item a family's best known rank creates, for icons and cooldowns when none is in the bags.
local function KnownItem(family)
	local known = ns.known[family]
	return known and ns.Data.stones[family][known.rank].item
end

local function SpellIcon(spellID)
	return spellID and C_Spell.GetSpellTexture(spellID)
end

local function SetGlow(btn, on)
	if on then
		if not btn.glow.anim:IsPlaying() then
			btn.glow:Show()
			btn.glow.anim:Play()
		end
	elseif btn.glow:IsShown() then
		btn.glow.anim:Stop()
		btn.glow:Hide()
	end
end

local function SetItemCooldown(btn, itemID)
	if not itemID then
		btn.cooldown:Clear()
		return
	end
	local start, duration = C_Item.GetItemCooldown(itemID)
	-- In combat these can be secret; the cooldown widget accepts them as-is.
	local d = ns.Safe(duration)
	if d == nil or d > 0 then
		btn.cooldown:SetCooldown(start, duration)
	else
		btn.cooldown:Clear()
	end
end

local function OnLeave()
	GameTooltip:Hide()
end

-- Button factory -------------------------------------------------------------

local function CreateButton(key, template)
	local name = "Grimoire" .. key .. "Button"
	local btn = CreateFrame("Button", name, bar, template)
	btn.key = key
	btn:SetSize(ns.db.buttonSize, ns.db.buttonSize)

	btn.icon = btn:CreateTexture(name .. "Icon", "BACKGROUND")
	btn.icon:SetAllPoints()
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	btn.cooldown = CreateFrame("Cooldown", name .. "Cooldown", btn, "CooldownFrameTemplate")
	btn.cooldown:SetAllPoints()

	btn.Count = btn:CreateFontString(name .. "Count", "OVERLAY", "NumberFontNormal")
	btn.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.HotKey = btn:CreateFontString(name .. "HotKey", "OVERLAY", "NumberFontNormalSmallGray")
	btn.HotKey:SetPoint("TOPRIGHT", -2, -2)

	local glow = btn:CreateTexture(nil, "OVERLAY")
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(0.58, 0.51, 0.79) -- warlock purple
	glow:SetPoint("CENTER")
	glow:SetSize(ns.db.buttonSize * 1.9, ns.db.buttonSize * 1.9)
	glow:Hide()
	local anim = glow:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local alpha = anim:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0.3)
	alpha:SetDuration(0.6)
	glow.anim = anim
	btn.glow = glow

	if not ns.useElvUI then
		local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		border:SetPoint("TOPLEFT", -1, 1)
		border:SetPoint("BOTTOMRIGHT", 1, -1)
		border:SetFrameLevel(btn:GetFrameLevel())
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		border:SetBackdropBorderColor(0, 0, 0)
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	end

	if template and template:find("SecureActionButtonTemplate") then
		btn:RegisterForClicks("AnyUp", "AnyDown")
	end
	btn:SetScript("OnLeave", OnLeave)
	buttons[key] = btn
	return btn
end

-- Tooltips ----------------------------------------------------------------------

local function TooltipAnchor(btn)
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
end

local function AddHint(text)
	GameTooltip:AddLine(text, 0.6, 0.8, 1)
end

local function StoneTooltip(btn, family, hints)
	TooltipAnchor(btn)
	local item, known = StoneItem(family), ns.known[family]
	if item then
		GameTooltip:SetItemByID(item)
	elseif known then
		GameTooltip:SetSpellByID(known.spellID)
	else
		GameTooltip:AddLine(btn.title)
		GameTooltip:AddLine("Not learned yet.", 1, 0.3, 0.3)
	end
	if ns:IsOutdated(family) then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Upgrade available: you can make a better stone.", 0.2, 1, 0.2)
	end
	GameTooltip:AddLine(" ")
	for _, hint in ipairs(hints) do AddHint(hint) end
	GameTooltip:Show()
end

-- Bar --------------------------------------------------------------------------

function ns:CreateBar()
	ns.useElvUI = _G.ElvUI ~= nil

	bar = CreateFrame("Frame", "GrimoireBar", UIParent, "SecureHandlerStateTemplate")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	bar:SetScale(ns.db.scale)
	local p = ns.db.point
	bar:SetPoint(p[1], UIParent, p[3], p[4], p[5])
	ns.bar = bar

	-- Shards (display + shard cap + drag handle)
	local shard = CreateButton("Shards")
	shard.title = "Soul Shards"
	shard:RegisterForClicks("AnyUp")
	shard:RegisterForDrag("LeftButton")
	shard:SetScript("OnClick", function()
		local cap = ns.db.shardCap
		if cap > 0 and ns.shards > cap then
			ns.lastCapPrompt = nil
			ns:CheckShardCap()
		end
	end)
	shard:SetScript("OnDragStart", function()
		if IsShiftKeyDown() and not ns.db.locked and not InCombatLockdown() and not ns.useElvUI then
			bar:StartMoving()
		end
	end)
	shard:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		local point, _, relPoint, x, y = bar:GetPoint()
		ns.db.point = { point, "UIParent", relPoint, x, y }
	end)
	shard:SetScript("OnEnter", function(btn)
		TooltipAnchor(btn)
		GameTooltip:AddLine("Soul Shards")
		GameTooltip:AddDoubleLine("Carried", ns.shards, 1, 1, 1, 1, 1, 1)
		if ns.db.shardCap > 0 then
			GameTooltip:AddDoubleLine("Cap", ns.db.shardCap, 1, 1, 1, 1, 1, 1)
			if ns.shards > ns.db.shardCap then AddHint("Click: delete extra shards") end
		end
		if not ns.useElvUI then AddHint("Shift-drag: move the bar") end
		GameTooltip:Show()
	end)

	-- Healthstone
	local hs = CreateButton("Healthstone", "SecureActionButtonTemplate")
	hs.title = "Healthstone"
	hs:SetAttribute("type2", NOOP)
	hs:SetScript("PostClick", function(_, mouse, down)
		if down or mouse ~= "RightButton" then return end
		if IsShiftKeyDown() then
			ns:PromptUpgrade("healthstone")
		elseif ns.db.tradeOnRightClick then
			ns:TradeHealthstone()
		end
	end)
	hs:SetScript("OnEnter", function(btn)
		local hints = { StoneItem("healthstone") and "Left-click: use" or "Left-click: create" }
		if ns.db.tradeOnRightClick and StoneItem("healthstone") then
			table.insert(hints, "Right-click: trade to your target")
		end
		if ns:IsOutdated("healthstone") then
			table.insert(hints, "Shift-right-click: delete the old stone")
		end
		StoneTooltip(btn, "healthstone", hints)
	end)

	-- Soulstone
	local ss = CreateButton("Soulstone", "SecureActionButtonTemplate")
	ss.title = "Soulstone"
	ss:SetAttribute("type2", NOOP)
	ss:SetScript("PreClick", function(_, mouse, down)
		if not down and mouse == "LeftButton" and StoneItem("soulstone") then ns:NoteSoulstoneClick() end
	end)
	ss:SetScript("PostClick", function(_, mouse, down)
		if not down and mouse == "RightButton" and IsShiftKeyDown() then ns:PromptUpgrade("soulstone") end
	end)
	ss:SetScript("OnEnter", function(btn)
		local hints = { StoneItem("soulstone") and "Left-click: use on mouseover, target, or yourself" or "Left-click: create" }
		if ns:IsOutdated("soulstone") then table.insert(hints, "Shift-right-click: delete the old stone") end
		StoneTooltip(btn, "soulstone", hints)
		local last = GrimoireCharDB.lastSoulstone
		if last and last.name then
			local mins = math.floor((time() - last.time) / 60)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(("Last soulstone: %s (%d min ago)"):format(last.name, mins), 1, 0.82, 0)
			GameTooltip:Show()
		end
	end)

	-- Weapon stone: left = Firestone, right = Spellstone
	local ws = CreateButton("WeaponStone", "SecureActionButtonTemplate")
	ws.title = "Weapon Stone"
	ws:SetScript("OnEnter", function(btn)
		TooltipAnchor(btn)
		GameTooltip:AddLine("Weapon Stone")
		local left = ns:WeaponEnchantState()
		if left then
			GameTooltip:AddDoubleLine("Main hand", ("%d min left"):format(math.floor(left / 60)), 1, 1, 1, 0.2, 1, 0.2)
		else
			GameTooltip:AddDoubleLine("Main hand", "no stone", 1, 1, 1, 1, 0.3, 0.3)
		end
		GameTooltip:AddLine(" ")
		for _, fam in ipairs({ { "firestone", "Left", "Firestone" }, { "spellstone", "Right", "Spellstone" } }) do
			if ns.known[fam[1]] then
				AddHint(("%s-click: %s %s"):format(fam[2], StoneItem(fam[1]) and "apply" or "create", fam[3]))
			end
		end
		GameTooltip:Show()
	end)

	-- Demons: toggle button + flyout of known demons
	local demon = CreateButton("Demons", "SecureHandlerClickTemplate")
	demon.title = "Demons"
	demon:RegisterForClicks("AnyUp")
	flyout = CreateFrame("Frame", "GrimoireDemonFlyout", demon, "SecureHandlerShowHideTemplate")
	flyout:Hide()
	demon:SetFrameRef("flyout", flyout)
	demon:SetAttribute("_onclick", [[
		local f = self:GetFrameRef("flyout")
		if f:IsShown() then f:Hide() else f:Show() end
	]])
	demon:SetScript("OnEnter", function(btn)
		TooltipAnchor(btn)
		GameTooltip:AddLine("Demons")
		AddHint("Click: open the demon menu")
		if ns.hasFelDomination then AddHint("Shift-click a demon: Fel Domination + summon") end
		GameTooltip:Show()
	end)
	ns.flyoutButtons = {}
	for i, data in ipairs(ns.Data.demons) do
		local b = CreateButton("Demon" .. i, "SecureActionButtonTemplate")
		b:SetParent(flyout)
		b.data = data
		b:SetAttribute("type", "macro")
		b:SetScript("OnEnter", function(btn)
			TooltipAnchor(btn)
			GameTooltip:SetSpellByID(data.spell)
			if ns.hasFelDomination then
				GameTooltip:AddLine(" ")
				AddHint("Shift-click: Fel Domination first")
			end
			GameTooltip:Show()
		end)
		SecureHandlerWrapScript(b, "OnClick", demon, FLYOUT_PRE, FLYOUT_CLOSE)
		ns.flyoutButtons[i] = b
	end

	-- Ritual of Summoning
	local rs = CreateButton("Ritual", "SecureActionButtonTemplate")
	rs.title = "Ritual of Summoning"
	rs:SetAttribute("type", "spell")
	rs:SetAttribute("spell", ns.Data.ritualOfSummoning)
	rs:SetScript("PreClick", function(_, _, down)
		if not down then ns:NoteRitualClick() end
	end)
	rs:SetScript("OnEnter", function(btn)
		TooltipAnchor(btn)
		GameTooltip:SetSpellByID(ns.Data.ritualOfSummoning)
		if ns.db.summonAnnounce then
			GameTooltip:AddLine(" ")
			AddHint("Announces the summon to your group")
		end
		GameTooltip:Show()
	end)

	ns:UpdateSecure()
	ns:UpdateVisuals()
end

function ns:CloseFlyout()
	if flyout and not InCombatLockdown() then flyout:Hide() end
end

-- Secure state (out of combat only) ------------------------------------------

local ORDER = { "Shards", "Healthstone", "Soulstone", "WeaponStone", "Demons", "Ritual" }

local function SetStoneAction(btn, suffix, family)
	local item, known = StoneItem(family), ns.known[family]
	if item then
		btn:SetAttribute("type" .. suffix, "item")
		btn:SetAttribute("item" .. suffix, "item:" .. item)
	elseif known then
		btn:SetAttribute("type" .. suffix, "spell")
		btn:SetAttribute("spell" .. suffix, known.spellID)
	else
		btn:SetAttribute("type" .. suffix, NOOP)
	end
end

local function DemonMacro(data)
	local summon = C_Spell.GetSpellName(data.spell)
	if ns.hasFelDomination then
		return ("/cast [mod:shift] %s\n/cast %s"):format(C_Spell.GetSpellName(ns.Data.felDomination), summon)
	end
	return "/cast " .. summon
end

local function IsVisible(key)
	if key == "Shards" or key == "Healthstone" then return true end
	if key == "Soulstone" then return ns.known.soulstone ~= nil end
	if key == "WeaponStone" then return ns.known.firestone ~= nil or ns.known.spellstone ~= nil end
	if key == "Demons" then return #ns.demons > 0 end
	if key == "Ritual" then return ns.hasRitual end
end

function ns:Layout()
	local size, gap, vertical = ns.db.buttonSize, ns.db.spacing, ns.db.vertical
	local shown = 0
	for _, key in ipairs(ORDER) do
		local btn = buttons[key]
		btn:SetSize(size, size)
		btn.glow:SetSize(size * 1.9, size * 1.9)
		btn:ClearAllPoints()
		if IsVisible(key) then
			local offset = gap + shown * (size + gap)
			if vertical then
				btn:SetPoint("TOPLEFT", bar, "TOPLEFT", gap, -offset)
			else
				btn:SetPoint("TOPLEFT", bar, "TOPLEFT", offset, -gap)
			end
			btn:Show()
			shown = shown + 1
		else
			btn:Hide()
		end
	end
	local long = gap + shown * (size + gap)
	local short = size + gap * 2
	if vertical then bar:SetSize(short, long) else bar:SetSize(long, short) end

	-- Flyout opens away from the bar: up for a horizontal bar, right for a vertical one.
	local prev
	for _, b in ipairs(ns.flyoutButtons) do
		b:SetSize(size, size)
		b.glow:SetSize(size * 1.9, size * 1.9)
		b:ClearAllPoints()
		if ns.IsKnown(b.data.spell) then
			if vertical then
				b:SetPoint("LEFT", prev or buttons.Demons, "RIGHT", gap, 0)
			else
				b:SetPoint("BOTTOM", prev or buttons.Demons, "TOP", 0, gap)
			end
			b:Show()
			prev = b
		else
			b:Hide()
		end
	end
	flyout:SetAllPoints(buttons.Demons)

	bar:SetShown(ns.db.showBar)
end

function ns:UpdateSecure()
	if InCombatLockdown() or not bar then return end
	SetStoneAction(buttons.Healthstone, "1", "healthstone")
	SetStoneAction(buttons.Soulstone, "1", "soulstone")
	local soulstone = StoneItem("soulstone")
	if soulstone then
		buttons.Soulstone:SetAttribute("type1", "macro")
		buttons.Soulstone:SetAttribute("macrotext1",
			("/use [@mouseover,help,nodead][@target,help,nodead][@player] item:%d"):format(soulstone))
	end

	local ws = buttons.WeaponStone
	SetStoneAction(ws, "1", "firestone")
	SetStoneAction(ws, "2", "spellstone")
	ws:SetAttribute("target-slot", INVSLOT_MAINHAND) -- applies the stone to the main hand if it needs a target

	for _, b in ipairs(ns.flyoutButtons) do
		b:SetAttribute("macrotext", DemonMacro(b.data))
	end

	ns:Layout()
end

-- Visual state (safe any time) ----------------------------------------------

function ns:UpdateWeaponGlow()
	local ws = buttons.WeaponStone
	if not ws then return end
	local left = ns:WeaponEnchantState()
	local known = ns.known.firestone or ns.known.spellstone
	SetGlow(ws, known and (not left or left < ns.db.weaponWarnMinutes * 60))
end

local function UpdateStoneButton(btn, family)
	local item, known = StoneItem(family), ns.known[family]
	local icon = item and C_Item.GetItemIconByID(item) or (known and SpellIcon(known.spellID))
	btn.icon:SetTexture(icon or 134400)
	local stone = ns.stones[family]
	btn.Count:SetText(stone and stone.count > 1 and stone.count or "")
	btn.icon:SetDesaturated(not item and ns.shards == 0)
	SetItemCooldown(btn, item or KnownItem(family))
	SetGlow(btn, ns:IsOutdated(family))
end

function ns:UpdateVisuals()
	if not bar then return end

	local shard = buttons.Shards
	shard.icon:SetTexture(C_Item.GetItemIconByID(ns.Data.soulShard) or 134075)
	shard.Count:SetText(ns.shards)
	if ns.shards == 0 then
		shard.Count:SetTextColor(1, 0.2, 0.2)
	elseif ns.shards <= ns.db.shardLow then
		shard.Count:SetTextColor(1, 0.82, 0)
	else
		shard.Count:SetTextColor(1, 1, 1)
	end
	SetGlow(shard, ns.db.shardCap > 0 and ns.shards > ns.db.shardCap)

	UpdateStoneButton(buttons.Healthstone, "healthstone")
	UpdateStoneButton(buttons.Soulstone, "soulstone")

	local ws = buttons.WeaponStone
	local fam = ns.known.firestone and "firestone" or "spellstone"
	local item = StoneItem(fam)
	ws.icon:SetTexture(item and C_Item.GetItemIconByID(item) or SpellIcon(ns.known[fam] and ns.known[fam].spellID) or 134400)
	ns:UpdateWeaponGlow()

	local demon = buttons.Demons
	local pet = UnitExists("pet") and ns.Safe(UnitCreatureFamily("pet"))
	local icon
	for _, d in ipairs(ns.demons) do
		if pet and d.family == pet then icon = SpellIcon(d.spell) end
	end
	demon.icon:SetTexture(icon or (ns.demons[1] and SpellIcon(ns.demons[1].spell)) or 136082)
	for _, b in ipairs(ns.flyoutButtons) do
		b.icon:SetTexture(SpellIcon(b.data.spell))
	end

	buttons.Ritual.icon:SetTexture(SpellIcon(ns.Data.ritualOfSummoning) or 136223)
end
