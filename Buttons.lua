local addonName, ns = ...

local C_Item, C_Spell = C_Item, C_Spell
local InCombatLockdown, GameTooltip = InCombatLockdown, GameTooltip
local Style = ns.Style

local NOOP = "grimoire_noop" -- secure action type with no handler: the click does nothing secure
local MENU_TEMPLATE = "SecureActionButtonTemplate, SecureHandlerBaseTemplate"
local BOOK_ICON = 133737 -- inv_misc_book_05
local BOOK_SCALE = 1.4
local RING_BOOK_SCALE = 1.8
local MAX_ITEMS = 10

-- Menu open/close, run in the secure environment so it also works in combat.
--   open:  auto-hides a moment after the mouse leaves the button and the menu
--   pin:   stays open until the button is clicked again (right-click on toggle menus,
--          shift-right-click on Curse/Bane menus whose right-click picks a spell)
--   other menus close when one opens
local TOGGLE_MENU = [[
	local menu = self:GetFrameRef("menu")
	local pin = button == "RightButton" and (self:GetAttribute("pinmode") == "right" or IsShiftKeyDown())
	if menu:IsShown() then
		if pin and not menu:GetAttribute("pinned") then
			menu:SetAttribute("pinned", true)
			menu:UnregisterAutoHide()
		else
			menu:Hide()
		end
		return
	end
	for i = 1, 8 do
		local other = self:GetFrameRef("menu" .. i)
		if not other then break end
		other:Hide()
	end
	menu:SetAttribute("pinned", pin)
	menu:Show()
	if not pin then
		menu:RegisterAutoHide(self:GetAttribute("autohide"))
		menu:AddToAutoHide(self)
		for i = 1, 10 do
			local item = self:GetFrameRef("item" .. i)
			if not item then break end
			if item:IsShown() then menu:AddToAutoHide(item) end
		end
	end
]]
local MENU_PRE = [[ return nil, true ]] -- keep the click, then run the post body
local MENU_CLOSE = [[
	local menu = owner:GetFrameRef("menu")
	if not menu:GetAttribute("pinned") then menu:Hide() end
]]

local bar
local buttons = {}
ns.buttons = buttons
ns.menus = {}

-- Bar order. Keys double as button name parts and option keys.
local ORDER = { "Book", "Healthstone", "Soulstone", "WeaponStone", "Curses", "Banes", "Buffs", "Control", "Demons", "Mount", "Ritual" }
ns.buttonOrder = ORDER

ns.buttonTitles = {
	Book = "Grimoire (Soul Shards)", Healthstone = "Healthstone", Soulstone = "Soulstone",
	WeaponStone = "Weapon Stone", Curses = "Curses", Banes = "Banes", Buffs = "Buffs",
	Control = "Crowd Control", Demons = "Demons", Mount = "Mount", Ritual = "Summoning",
}

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
	Style.SetGlow(btn, on)
end
ns.SetGlow = SetGlow

local function SetCooldown(btn, start, duration)
	-- In combat these can be secret; the cooldown widget accepts them as-is.
	local d = ns.Safe(duration)
	if start and (d == nil or d > 0) then
		btn.cooldown:SetCooldown(start, duration)
	else
		btn.cooldown:Clear()
	end
end

local function SetItemCooldown(btn, itemID)
	if not itemID then return btn.cooldown:Clear() end
	SetCooldown(btn, C_Item.GetItemCooldown(itemID))
end

local function SetSpellCooldown(btn, spellID)
	local info = spellID and C_Spell.GetSpellCooldown(spellID)
	if not info then return btn.cooldown:Clear() end
	SetCooldown(btn, info.startTime, info.duration)
end

-- Tint only for reasons the player can act on: blue when out of mana, grey when the
-- spell needs a soul shard and there are none. The game's general "not usable" flag
-- also covers things like an armor that's already on, which would grey out spells
-- that can be cast. Keeps the last state when the answer is secret (in combat).
local function UpdateUsable(btn, spellID, needsShard)
	if not spellID then return Style.SetUsable(btn, nil) end
	if needsShard and ns.shards == 0 then return Style.SetUsable(btn, "unusable") end
	local _, noPower = C_Spell.IsSpellUsable(spellID)
	noPower = ns.Safe(noPower)
	if noPower == nil then return end
	Style.SetUsable(btn, noPower and "nopower" or nil)
end

-- Mana cost of a spell, or nil.
local function ManaCost(spellID)
	local costs = spellID and C_Spell.GetSpellPowerCost(spellID)
	for _, cost in ipairs(costs or {}) do
		if ns.Safe(cost.type) == Enum.PowerType.Mana then return ns.Safe(cost.cost) end
	end
end

local function FormatCost(cost)
	if not cost or cost <= 0 then return "" end
	if cost >= 1000 then return ("%.1fk"):format(cost / 1000) end
	return tostring(cost)
end

local function OnLeave()
	GameTooltip:Hide()
end

local function TooltipAnchor(btn)
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
end

local function AddHint(text)
	GameTooltip:AddLine(text, 0.5, 0.5, 0.5)
end

-- "Soul Shards: N" for spells that use one; red when you have none.
local function AddShardLine(needsShard)
	if not needsShard then return end
	local r, g, b = 1, 1, 1
	if ns.shards == 0 then r, g, b = 1, 0.27, 0.27 end
	GameTooltip:AddDoubleLine("Soul Shards", ns.shards, 0.7, 0.7, 0.7, r, g, b)
end

-- Button factory -------------------------------------------------------------

local function CreateButton(key, template, parent, withCost)
	local name = "Grimoire" .. key .. "Button"
	local btn = CreateFrame("Button", name, parent or bar, template)
	btn.key = key
	btn.binding = "CLICK " .. name .. ":LeftButton"

	btn.icon = btn:CreateTexture(name .. "Icon", "ARTWORK")
	btn.icon:SetAllPoints()
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	btn.cooldown = CreateFrame("Cooldown", name .. "Cooldown", btn, "CooldownFrameTemplate")
	btn.cooldown:SetAllPoints()

	btn.Count = btn:CreateFontString(name .. "Count", "OVERLAY", "NumberFontNormal")
	btn.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.HotKey = btn:CreateFontString(name .. "HotKey", "OVERLAY", "NumberFontNormalSmallGray")
	btn.HotKey:SetPoint("TOPRIGHT", -2, -2)
	if withCost then
		btn.cost = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		btn.cost:SetPoint("BOTTOM", 0, 2)
	end

	if template and template:find("SecureActionButtonTemplate") then
		btn:RegisterForClicks("AnyUp", "AnyDown")
	end
	btn:SetScript("OnLeave", OnLeave)
	buttons[key] = btn
	return btn
end

-- Stone tooltips -----------------------------------------------------------------

local function StoneTooltip(btn, family, hints)
	TooltipAnchor(btn)
	local item, known = StoneItem(family), ns.known[family]
	if item then
		GameTooltip:SetItemByID(item)
	elseif known then
		GameTooltip:SetSpellByID(known.spellID)
		AddShardLine(true)
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

-- Menus --------------------------------------------------------------------------

-- A menu is a main button plus a flyout of spell buttons. "toggle" menus open on any
-- click; "default" menus cast the last picked spell on left-click and open on right-click.
local function CreateMenu(key, entries, mode, opts)
	opts = opts or {}
	local main = CreateButton(key, MENU_TEMPLATE)
	main.title = ns.buttonTitles[key]
	main.mode = mode
	main.entries = entries
	main:SetAttribute("_grimoiremenu", TOGGLE_MENU)
	main:SetAttribute("autohide", ns.db.menuAutoHide)
	if mode == "toggle" then
		main:SetAttribute("type", "grimoiremenu")
		main:SetAttribute("pinmode", "right")
	else
		main:SetAttribute("type2", "grimoiremenu")
		main:SetAttribute("pinmode", "shiftright")
	end

	local flyout = CreateFrame("Frame", "Grimoire" .. key .. "Menu", main, "SecureHandlerShowHideTemplate")
	flyout:Hide()
	main:SetFrameRef("menu", flyout)
	main.flyout = flyout
	main.items = {}

	for i, entry in ipairs(entries) do
		if i > MAX_ITEMS then break end
		local b = CreateButton(key .. i, "SecureActionButtonTemplate", flyout, not opts.demon)
		b.entry = entry
		b.index = i
		b:SetAttribute("type", opts.demon and "macro" or "spell")
		b:SetScript("OnEnter", function(btn)
			TooltipAnchor(btn)
			if btn.spellID then GameTooltip:SetSpellByID(btn.spellID) end
			AddShardLine(entry.shard)
			GameTooltip:AddLine(" ")
			if mode == "default" then AddHint("Click: cast and make it the default") end
			if opts.demon and ns.hasFelDomination then AddHint("Shift-click: Fel Domination first") end
			GameTooltip:Show()
		end)
		if mode == "default" then
			b:SetScript("PostClick", function(btn, _, down)
				if down then return end
				ns.db.defaults[key] = btn.index
				ns:RequestSecureUpdate()
				ns:UpdateVisuals()
			end)
		end
		SecureHandlerWrapScript(b, "OnClick", main, MENU_PRE, MENU_CLOSE)
		main:SetFrameRef("item" .. i, b)
		main.items[i] = b
	end

	ns.menus[key] = main
	return main
end

-- The spell a "default" menu casts: the saved pick if still known, else the first known entry.
local function MenuDefault(main)
	local pick = ns.db.defaults[main.key]
	local entry = pick and main.entries[pick]
	local spell = entry and ns.BestSpell(entry)
	if spell then return spell, entry end
	for _, e in ipairs(main.entries) do
		spell = ns.BestSpell(e)
		if spell then return spell, e end
	end
end

local function KnownCount(main)
	local n = 0
	for _, b in ipairs(main.items) do
		if b.spellID then n = n + 1 end
	end
	return n
end

-- Book ---------------------------------------------------------------------------

local BOOK_MODES = { "shards", "soulstone", "mana" }
local BOOK_MODE_NAMES = { shards = "Soul Shards", soulstone = "Soulstone timer", mana = "Mana" }
ns.bookModes, ns.bookModeNames = BOOK_MODES, BOOK_MODE_NAMES

local function SoulstoneLeft()
	local last = ns.char.lastSoulstone
	if not (last and last.time) then return end
	local left = 30 * 60 - (time() - last.time)
	return left > 0 and left or nil
end

function ns:UpdateBook()
	local book = buttons.Book
	if not book or not book.fill then return end
	local mode = ns.db.bookMode
	local fill, text = book.fill, book.Count
	local a = Style.theme.accent
	if mode == "mana" then
		local m = Style.theme.mana
		Style.SetFillColor(fill, m[1], m[2], m[3])
		fill:SetMinMaxValues(0, UnitPowerMax("player", Enum.PowerType.Mana))
		fill:SetValue(UnitPower("player", Enum.PowerType.Mana))
		-- Secret in combat; the widgets accept secret values, so the display keeps working.
		text:SetFormattedText("%d%%", UnitPowerPercent("player", Enum.PowerType.Mana, true, CurveConstants.ScaleTo100))
		text:SetTextColor(1, 1, 1)
	elseif mode == "soulstone" then
		local left = SoulstoneLeft()
		Style.SetFillColor(fill, 0.85, 0.35, 0.85)
		fill:SetMinMaxValues(0, 30 * 60)
		fill:SetValue(left or 0)
		if not left then
			text:SetText("-")
			text:SetTextColor(0.6, 0.6, 0.6)
		elseif left >= 60 then
			text:SetFormattedText("%dm", math.ceil(left / 60))
			if left < 300 then text:SetTextColor(1, 0.82, 0) else text:SetTextColor(1, 1, 1) end
		else
			text:SetFormattedText("%ds", left)
			text:SetTextColor(1, 0.27, 0.27)
		end
	else
		local full = ns.db.shardCap > 0 and ns.db.shardCap or 20
		Style.SetFillColor(fill, a[1], a[2], a[3])
		fill:SetMinMaxValues(0, full)
		fill:SetValue(math.min(ns.shards, full))
		text:SetText(ns.shards)
		if ns.shards == 0 then
			text:SetTextColor(1, 0.27, 0.27)
		elseif ns.shards <= ns.db.shardLow then
			text:SetTextColor(1, 0.82, 0)
		else
			text:SetTextColor(1, 1, 1)
		end
	end
	SetGlow(book, ns.db.shardCap > 0 and ns.shards > ns.db.shardCap)
end

function ns:CycleBookMode(delta)
	local index = 1
	for i, m in ipairs(BOOK_MODES) do
		if m == ns.db.bookMode then index = i end
	end
	index = (index - 1 + delta) % #BOOK_MODES + 1
	ns.db.bookMode = BOOK_MODES[index]
	ns:UpdateBook()
end

local function StoneSummary(label, family)
	local stone, known = ns.stones[family], ns.known[family]
	if not known and not stone then return end
	if stone then
		local name = C_Item.GetItemNameByID(stone.itemID) or label
		local extra = ns:IsOutdated(family) and " |cff33ff33(upgrade)|r" or ""
		GameTooltip:AddDoubleLine(label, name .. (stone.count > 1 and (" x" .. stone.count) or "") .. extra,
			0.7, 0.7, 0.7, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine(label, "none", 0.7, 0.7, 0.7, 1, 0.27, 0.27)
	end
end

local function BookTooltip(btn)
	TooltipAnchor(btn)
	local a = Style.theme.accent
	GameTooltip:AddLine("Grimoire", a[1], a[2], a[3])
	AddShardLine(true)
	GameTooltip:AddDoubleLine("Gained this session", ns.sessionShards or 0, 0.7, 0.7, 0.7, 0.6, 1, 0.6)
	if ns.db.shardCap > 0 then GameTooltip:AddDoubleLine("Cap", ns.db.shardCap, 0.7, 0.7, 0.7, 1, 1, 1) end
	GameTooltip:AddLine(" ")
	StoneSummary("Healthstone", "healthstone")
	StoneSummary("Soulstone", "soulstone")
	StoneSummary("Firestone", "firestone")
	StoneSummary("Spellstone", "spellstone")
	local left = ns:WeaponEnchantState()
	if ns.known.firestone or ns.known.spellstone then
		if left then
			GameTooltip:AddDoubleLine("Weapon", ("%d min"):format(math.floor(left / 60)), 0.7, 0.7, 0.7, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine("Weapon", "no stone", 0.7, 0.7, 0.7, 1, 0.27, 0.27)
		end
	end
	local last, ssLeft = ns.char.lastSoulstone, SoulstoneLeft()
	if last and last.name and ssLeft then
		GameTooltip:AddDoubleLine("Soulstoned", ("%s (%dm left)"):format(last.name, math.ceil(ssLeft / 60)),
			0.7, 0.7, 0.7, 0.85, 0.5, 0.85)
	end
	local pet = UnitExists("pet") and ns.Safe(UnitCreatureFamily("pet"))
	if pet then GameTooltip:AddDoubleLine("Demon", pet, 0.7, 0.7, 0.7, 1, 1, 1) end
	GameTooltip:AddLine(" ")
	if ns.db.shardCap > 0 and ns.shards > ns.db.shardCap then
		AddHint("Left-click: delete extra shards")
	elseif ns.db.summonQueue then
		AddHint("Left-click: summon queue")
	end
	AddHint("Mouse wheel: shards / soulstone / mana")
	AddHint("Right-click: options")
	if not ns.db.locked then AddHint("Shift-drag: move") end
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

	-- The grimoire. Its fill and center text show shards, the soulstone timer or mana.
	local book = CreateButton("Book")
	book.title = ns.buttonTitles.Book
	book.binding = nil
	book.icon:SetTexture(BOOK_ICON)
	book.Count:ClearAllPoints()
	book.Count:SetPoint("CENTER", 0, -1)
	book:RegisterForClicks("AnyUp")
	book:RegisterForDrag("LeftButton")
	book:EnableMouseWheel(true)
	book:SetScript("OnMouseWheel", function(_, delta) ns:CycleBookMode(delta > 0 and 1 or -1) end)
	book:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			SlashCmdList.GRIMOIRE("")
		elseif ns.db.shardCap > 0 and ns.shards > ns.db.shardCap then
			ns.lastCapPrompt = nil
			ns:CheckShardCap()
		elseif ns.ToggleSummonQueue then
			ns:ToggleSummonQueue()
		end
	end)
	-- Shift-drag moves the bar (under ElvUI, its mover, so the spot is saved in the profile).
	book:SetScript("OnDragStart", function(btn)
		if not IsShiftKeyDown() or ns.db.locked or InCombatLockdown() then return end
		btn.dragging = true
		if ns.StartDrag then ns.StartDrag() else bar:StartMoving() end
	end)
	book:SetScript("OnDragStop", function(btn)
		if not btn.dragging then return end
		btn.dragging = nil
		if ns.StopDrag then
			ns.StopDrag()
		else
			bar:StopMovingOrSizing()
			local point, _, relPoint, x, y = bar:GetPoint()
			ns.db.point = { point, "UIParent", relPoint, x, y }
		end
	end)
	book:SetScript("OnEnter", BookTooltip)

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
		if not down and mouse == "LeftButton" and StoneItem("soulstone") and ns.NoteSoulstoneClick then
			ns:NoteSoulstoneClick()
		end
	end)
	ss:SetScript("PostClick", function(_, mouse, down)
		if not down and mouse == "RightButton" and IsShiftKeyDown() then ns:PromptUpgrade("soulstone") end
	end)
	ss:SetScript("OnEnter", function(btn)
		local hints = { StoneItem("soulstone") and "Left-click: use on mouseover, target, or yourself" or "Left-click: create" }
		if ns:IsOutdated("soulstone") then table.insert(hints, "Shift-right-click: delete the old stone") end
		StoneTooltip(btn, "soulstone", hints)
		local last, left = ns.char.lastSoulstone, SoulstoneLeft()
		if last and last.name and left then
			GameTooltip:AddLine(" ")
			GameTooltip:AddDoubleLine("Soulstoned", ("%s (%dm left)"):format(last.name, math.ceil(left / 60)),
				0.7, 0.7, 0.7, 0.85, 0.5, 0.85)
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
			GameTooltip:AddDoubleLine("Main hand", ("%d min left"):format(math.floor(left / 60)), 0.7, 0.7, 0.7, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine("Main hand", "no stone", 0.7, 0.7, 0.7, 1, 0.27, 0.27)
		end
		StoneSummary("Firestone", "firestone")
		StoneSummary("Spellstone", "spellstone")
		GameTooltip:AddLine(" ")
		for _, fam in ipairs({ { "firestone", "Left", "Firestone" }, { "spellstone", "Right", "Spellstone" } }) do
			if ns.known[fam[1]] then
				AddHint(("%s-click: %s %s"):format(fam[2], StoneItem(fam[1]) and "apply" or "create", fam[3]))
			end
		end
		GameTooltip:Show()
	end)

	-- Spell menus
	local curses = CreateMenu("Curses", ns.Data.curses, "default")
	local banes = CreateMenu("Banes", ns.Data.banes, "default")
	local buffs = CreateMenu("Buffs", ns.Data.buffs, "toggle")
	local control = CreateMenu("Control", ns.Data.control, "toggle")
	local demons = CreateMenu("Demons", ns.Data.demons, "toggle", { demon = true })
	for _, main in ipairs({ curses, banes }) do
		main:SetScript("OnEnter", function(btn)
			TooltipAnchor(btn)
			local spell = MenuDefault(btn)
			if spell then GameTooltip:SetSpellByID(spell) else GameTooltip:AddLine(btn.title) end
			GameTooltip:AddLine(" ")
			AddHint("Left-click: cast the default")
			AddHint("Right-click: choose another")
			AddHint("Shift-right-click: keep the menu open")
			GameTooltip:Show()
		end)
	end
	for _, main in ipairs({ buffs, control, demons }) do
		main:SetScript("OnEnter", function(btn)
			TooltipAnchor(btn)
			local a = Style.theme.accent
			GameTooltip:AddLine(btn.title, a[1], a[2], a[3])
			if btn == control and ns.creatureAlert then
				GameTooltip:AddLine(ns.creatureAlert, 0.2, 1, 0.2)
			end
			if btn == buffs and btn.glowing then
				GameTooltip:AddLine("You have no armor on.", 1, 0.27, 0.27)
			end
			if btn == demons then
				local pet = UnitExists("pet") and ns.Safe(UnitCreatureFamily("pet"))
				GameTooltip:AddDoubleLine("Current", pet or "none", 0.7, 0.7, 0.7, 1, 1, 1)
				AddShardLine(true)
			end
			GameTooltip:AddLine(" ")
			AddHint("Left-click: open the menu")
			AddHint("Right-click: keep it open")
			if btn == demons and ns.hasFelDomination then AddHint("Shift-click a demon: Fel Domination first") end
			GameTooltip:Show()
		end)
	end
	-- Each menu button closes the others when it opens.
	local all = { curses, banes, buffs, control, demons }
	for _, main in ipairs(all) do
		local n = 0
		for _, other in ipairs(all) do
			if other ~= main then
				n = n + 1
				main:SetFrameRef("menu" .. n, other.flyout)
			end
		end
	end

	-- Mount
	local mount = CreateButton("Mount", "SecureActionButtonTemplate")
	mount.title = "Mount"
	mount:SetAttribute("type", "spell")
	mount:SetScript("OnEnter", function(btn)
		TooltipAnchor(btn)
		if btn.spellID then GameTooltip:SetSpellByID(btn.spellID) else GameTooltip:AddLine("Mount") end
		GameTooltip:Show()
	end)

	-- Ritual of Summoning (left) / Portal of Summoning (right)
	local rs = CreateButton("Ritual", "SecureActionButtonTemplate")
	rs.title = "Summoning"
	rs:SetAttribute("type", "spell")
	rs:SetAttribute("spell1", ns.Data.ritualOfSummoning)
	rs:SetScript("PreClick", function(_, mouse, down)
		if not down and ns.NoteRitualClick then ns:NoteRitualClick(ns.SafeUnitName("target"), mouse == "RightButton") end
	end)
	rs:SetScript("OnEnter", function(btn)
		TooltipAnchor(btn)
		GameTooltip:SetSpellByID(ns.Data.ritualOfSummoning)
		AddShardLine(true)
		GameTooltip:AddLine(" ")
		AddHint("Left-click: Ritual of Summoning on your target")
		if ns.hasPortal then AddHint("Right-click: Portal of Summoning") end
		if ns.db.summonAnnounce then AddHint("Announces the summon to your group") end
		GameTooltip:Show()
	end)

	ns:UpdateSecure()
end

-- Runs once the theme is known (after ElvUI initializes, when it's loaded).
function ns:ApplyStyle()
	ns.loginRound = Style.IsRound() and true or false
	for _, btn in pairs(buttons) do
		Style.Button(btn)
		btn.glowing = nil
	end
	buttons.Book.fill = Style.BookFill(buttons.Book)
	Style.BookText(buttons.Book, buttons.Book.fill)
	if InCombatLockdown() then ns.secureDirty = true else ns:Layout() end
	ns:StartModules()
	ns:UpdateVisuals()
end

function ns:CloseMenus()
	if InCombatLockdown() then return end
	for _, main in pairs(ns.menus) do main.flyout:Hide() end
end

-- Secure state (out of combat only) ------------------------------------------

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

local function DemonMacro(spellID)
	local summon = C_Spell.GetSpellName(spellID)
	if ns.hasFelDomination then
		return ("/cast [mod:shift] %s\n/cast %s"):format(C_Spell.GetSpellName(ns.Data.felDomination), summon)
	end
	return "/cast " .. summon
end

local function IsVisible(key)
	if ns.db.hidden[key] then return false end
	if key == "Book" or key == "Healthstone" then return true end
	if key == "Soulstone" then return ns.known.soulstone ~= nil end
	if key == "WeaponStone" then return ns.known.firestone ~= nil or ns.known.spellstone ~= nil end
	if key == "Mount" then return buttons.Mount.spellID ~= nil end
	if key == "Ritual" then return ns.hasRitual end
	local main = ns.menus[key]
	return main and KnownCount(main) > 0
end

local function SizeButton(btn, size)
	btn:SetSize(size, size)
	Style.Resize(btn, size)
end

-- Menus open away from the bar: up for a horizontal bar, right for a vertical one,
-- and outward from the center along the button's angle in the ring.
local function LayoutMenu(main, size, gap, vertical)
	local n = 0
	for _, b in ipairs(main.items) do
		SizeButton(b, size)
		b:ClearAllPoints()
		if b.spellID then
			n = n + 1
			local step = n * (size + gap)
			if main.angle then
				b:SetPoint("CENTER", main, "CENTER", math.cos(main.angle) * step, math.sin(main.angle) * step)
			elseif vertical then
				b:SetPoint("CENTER", main, "CENTER", step, 0)
			else
				b:SetPoint("CENTER", main, "CENTER", 0, step)
			end
			b:Show()
		else
			b:Hide()
		end
	end
	main.flyout:SetAllPoints(main)
end

-- Ring: the book in the center, the other buttons evenly around it from the start
-- angle. The radius grows with the button count so they never overlap.
local function LayoutRing(visible, size, gap, showBook)
	local book = buttons.Book
	local bookSize = math.floor(size * RING_BOOK_SCALE)
	SizeButton(book, bookSize)
	book:ClearAllPoints()
	book:SetPoint("CENTER", bar, "CENTER")
	book:SetShown(showBook)

	local count = #visible
	local radius = bookSize / 2 + size / 2 + gap * 2
	radius = math.max(radius, count * (size + gap) / (2 * math.pi)) * ns.db.ringRadius
	local start = math.rad(ns.db.ringAngle)
	local dir = ns.db.ringClockwise and -1 or 1
	for i, btn in ipairs(visible) do
		local angle = start + dir * (i - 1) * 2 * math.pi / math.max(count, 1)
		btn.angle = angle
		btn:SetPoint("CENTER", bar, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
	end
	local diameter = 2 * (radius + size / 2) + gap * 2
	bar:SetSize(diameter, diameter)
end

function ns:Layout()
	local size, gap, vertical, ring = ns.db.buttonSize, ns.db.spacing, ns.db.vertical, ns.db.ring
	local offset, thickness = gap, size
	local ringButtons = {}
	for _, key in ipairs(ORDER) do
		local btn = buttons[key]
		local s = key == "Book" and math.floor(size * BOOK_SCALE) or size
		SizeButton(btn, s)
		btn:ClearAllPoints()
		btn.angle = nil
		if not IsVisible(key) then
			btn:Hide()
		elseif ring then
			if key ~= "Book" then table.insert(ringButtons, btn) end
			btn:Show()
		else
			if vertical then
				btn:SetPoint("TOP", bar, "TOP", 0, -offset)
			else
				btn:SetPoint("LEFT", bar, "LEFT", offset, 0)
			end
			btn:Show()
			offset = offset + s + gap
			thickness = math.max(thickness, s)
		end
	end
	if ring then
		LayoutRing(ringButtons, size, gap, IsVisible("Book"))
	elseif vertical then
		bar:SetSize(thickness + gap * 2, offset)
	else
		bar:SetSize(offset, thickness + gap * 2)
	end
	for _, main in pairs(ns.menus) do
		main:SetAttribute("autohide", ns.db.menuAutoHide)
		LayoutMenu(main, size, gap, vertical)
	end
	if ns.UpdateBarBackdrop then ns.UpdateBarBackdrop() end
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
	ws:SetAttribute("target-slot", INVSLOT_MAINHAND) -- the stone needs a weapon target, like poisons

	for key, main in pairs(ns.menus) do
		for _, b in ipairs(main.items) do
			local spell = ns.BestSpell(b.entry)
			b.spellID = spell
			if key == "Demons" then
				b:SetAttribute("macrotext", spell and DemonMacro(spell) or nil)
			else
				b:SetAttribute("spell", spell)
			end
		end
		if main.mode == "default" then
			local spell = MenuDefault(main)
			main.spellID = spell
			main:SetAttribute("type1", spell and "spell" or NOOP)
			main:SetAttribute("spell1", spell)
		end
	end

	local mount
	for _, id in ipairs(ns.Data.mounts) do
		if ns.IsKnown(id) then mount = id break end
	end
	buttons.Mount.spellID = mount
	buttons.Mount:SetAttribute("spell", mount)

	buttons.Ritual:SetAttribute("type2", ns.hasPortal and "spell" or NOOP)
	buttons.Ritual:SetAttribute("spell2", ns.Data.portalOfSummoning)

	ns:Layout()
	if ns.UpdateSummonQueue then ns:UpdateSummonQueue() end
end

-- Visual state (safe any time) ----------------------------------------------

function ns:UpdateWeaponGlow()
	local ws = buttons.WeaponStone
	if not ws then return end
	local left = ns:WeaponEnchantState()
	local known = ns.known.firestone or ns.known.spellstone
	SetGlow(ws, known and (not left or left < ns.db.weaponWarnMinutes * 60))
end

function ns:UpdateArmorGlow()
	local buffs = ns.menus.Buffs
	if not buffs or not ns.db.armorReminder then
		if buffs then SetGlow(buffs, false) end
		return
	end
	local missing = ns:MissingAura(ns.Data.armor)
	if missing ~= nil then SetGlow(buffs, missing and ns.BestSpell(ns.Data.buffs[1]) ~= nil) end
end

local function UpdateStoneButton(btn, family)
	local item, known = StoneItem(family), ns.known[family]
	local icon = item and C_Item.GetItemIconByID(item) or (known and SpellIcon(known.spellID))
	btn.icon:SetTexture(icon or 134400)
	local stone = ns.stones[family]
	btn.Count:SetText(stone and stone.count > 1 and stone.count or "")
	if item then
		Style.SetUsable(btn, nil)
	else
		Style.SetUsable(btn, ns.shards == 0 and "unusable" or nil)
	end
	SetItemCooldown(btn, item or KnownItem(family))
	SetGlow(btn, ns:IsOutdated(family))
end

local function UpdateHotkey(btn)
	local key = btn.binding and GetBindingKey(btn.binding)
	local text = key and GetBindingText(key, true) or ""
	btn.HotKey:SetText(text)
	if ns.FormatHotkey then ns.FormatHotkey(btn) end
end

-- Usability and cooldowns only (cheap; runs on SPELL_UPDATE_USABLE and power changes).
function ns:UpdateUsable()
	if not bar then return end
	for _, main in pairs(ns.menus) do
		for _, b in ipairs(main.items) do
			if b.spellID then
				UpdateUsable(b, b.spellID, b.entry.shard)
				SetSpellCooldown(b, b.spellID)
			end
		end
		if main.mode == "default" then
			local _, entry = MenuDefault(main)
			UpdateUsable(main, main.spellID, entry and entry.shard)
			SetSpellCooldown(main, main.spellID)
		end
	end
	UpdateUsable(buttons.Mount, buttons.Mount.spellID)
	if ns.hasRitual then UpdateUsable(buttons.Ritual, ns.Data.ritualOfSummoning, true) end
	SetSpellCooldown(buttons.Ritual, ns.hasPortal and ns.Data.portalOfSummoning or nil)
end

function ns:UpdateVisuals()
	if not bar then return end

	ns:UpdateBook()
	UpdateStoneButton(buttons.Healthstone, "healthstone")
	UpdateStoneButton(buttons.Soulstone, "soulstone")

	local ws = buttons.WeaponStone
	local fam = ns.known.firestone and "firestone" or "spellstone"
	local item = StoneItem(fam)
	ws.icon:SetTexture(item and C_Item.GetItemIconByID(item) or SpellIcon(ns.known[fam] and ns.known[fam].spellID) or 134400)
	ns:UpdateWeaponGlow()

	for _, main in pairs(ns.menus) do
		for _, b in ipairs(main.items) do
			local spell = b.spellID or ns.BestSpell(b.entry)
			b.icon:SetTexture(SpellIcon(spell or (b.entry.ranks and b.entry.ranks[1]) or b.entry.spell))
			if b.cost then b.cost:SetText(FormatCost(ManaCost(spell))) end
			UpdateHotkey(b)
		end
		if main.mode == "default" then
			main.icon:SetTexture(SpellIcon(main.spellID) or 136122)
		end
		UpdateHotkey(main)
	end

	local demon = ns.menus.Demons
	local pet = UnitExists("pet") and ns.Safe(UnitCreatureFamily("pet"))
	local icon
	for _, d in ipairs(ns.demons) do
		if pet and d.family == pet then icon = SpellIcon(d.spell) end
	end
	demon.icon:SetTexture(icon or (ns.demons[1] and SpellIcon(ns.demons[1].spell)) or 136082)

	ns.menus.Buffs.icon:SetTexture(SpellIcon(ns.BestSpell(ns.Data.buffs[1])) or 136185)
	ns:UpdateArmorGlow()

	local control = ns.menus.Control
	local banish = ns.BestSpell(ns.Data.control[1])
	control.icon:SetTexture(SpellIcon(ns.creatureAlert and banish or ns.BestSpell(ns.Data.control[2])) or 136183)
	SetGlow(control, ns.creatureAlert ~= nil)

	local mount = buttons.Mount
	mount.icon:SetTexture(SpellIcon(mount.spellID) or 136103)

	buttons.Ritual.icon:SetTexture(SpellIcon(ns.Data.ritualOfSummoning) or 136223)

	for _, key in ipairs({ "Healthstone", "Soulstone", "WeaponStone", "Mount", "Ritual" }) do
		UpdateHotkey(buttons[key])
	end
	ns:UpdateUsable()
end

-- Live updates for usability, mana and the soulstone countdown.
ns:On("SPELL_UPDATE_USABLE", function() ns:UpdateUsable() end)
ns:On("SPELL_UPDATE_COOLDOWN", function() ns:UpdateUsable() end)
ns:On("UNIT_POWER_FREQUENT", function(_, unit)
	if unit == "player" and ns.db and ns.db.bookMode == "mana" then ns:UpdateBook() end
end)
ns:On("UNIT_MAXPOWER", function(_, unit)
	if unit == "player" and ns.db and ns.db.bookMode == "mana" then ns:UpdateBook() end
end)
C_Timer.NewTicker(1, function()
	if ns.db and ns.db.bookMode == "soulstone" then ns:UpdateBook() end
end)
