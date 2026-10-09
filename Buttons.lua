local addonName, ns = ...

local C_Item, C_Spell = C_Item, C_Spell
local InCombatLockdown, GameTooltip = InCombatLockdown, GameTooltip

local NOOP = "grimoire_noop" -- secure action type with no handler: the click does nothing secure
local MENU_TEMPLATE = "SecureActionButtonTemplate, SecureHandlerBaseTemplate"
local BOOK_ICON = 133737 -- inv_misc_book_05
local BOOK_SCALE = 1.4

-- Toggles this button's menu and closes the other menus.
local TOGGLE_MENU = [[
	local menu = self:GetFrameRef("menu")
	local show = not menu:IsShown()
	for i = 1, 8 do
		local other = self:GetFrameRef("menu" .. i)
		if not other then break end
		other:Hide()
	end
	if show then menu:Show() else menu:Hide() end
]]
local MENU_AUTOCLOSE = 1.5 -- seconds after the mouse leaves an open menu (out of combat only)
local MENU_PRE = [[ return nil, true ]] -- keep the click, then run the post body
local MENU_CLOSE = [[ owner:GetFrameRef("menu"):Hide() ]]

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

local function OnLeave()
	GameTooltip:Hide()
end

local function TooltipAnchor(btn)
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
end

local function AddHint(text)
	GameTooltip:AddLine(text, 0.6, 0.8, 1)
end

-- Button factory -------------------------------------------------------------

local function CreateButton(key, template, parent)
	local name = "Grimoire" .. key .. "Button"
	local btn = CreateFrame("Button", name, parent or bar, template)
	btn.key = key
	btn.binding = "CLICK " .. name .. ":LeftButton"

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

-- Stone tooltips -----------------------------------------------------------------

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
	if mode == "toggle" then
		main:SetAttribute("type", "grimoiremenu")
	else
		main:SetAttribute("type2", "grimoiremenu")
	end

	local flyout = CreateFrame("Frame", "Grimoire" .. key .. "Menu", main, "SecureHandlerShowHideTemplate")
	flyout:Hide()
	main:SetFrameRef("menu", flyout)
	main.flyout = flyout
	main.items = {}

	-- Close once the mouse has been away from the button and the menu for a moment.
	-- Hiding a secure frame is blocked in combat, where a second click closes it instead.
	local away = 0
	flyout:HookScript("OnShow", function() away = 0 end)
	flyout:SetScript("OnUpdate", function(self, elapsed)
		if InCombatLockdown() then return end
		local over = main:IsMouseOver()
		for _, b in ipairs(main.items) do
			if b:IsShown() and b:IsMouseOver() then over = true break end
		end
		away = over and 0 or away + elapsed
		if away > MENU_AUTOCLOSE then self:Hide() end
	end)

	for i, entry in ipairs(entries) do
		local b = CreateButton(key .. i, "SecureActionButtonTemplate", flyout)
		b.entry = entry
		b.index = i
		if opts.demon then
			b:SetAttribute("type", "macro")
		else
			b:SetAttribute("type", "spell")
		end
		b:SetScript("OnEnter", function(btn)
			TooltipAnchor(btn)
			local spell = btn.spellID
			if spell then GameTooltip:SetSpellByID(spell) end
			if mode == "default" then
				GameTooltip:AddLine(" ")
				AddHint("Click: cast and make it the default")
			end
			if opts.demon and ns.hasFelDomination then
				GameTooltip:AddLine(" ")
				AddHint("Shift-click: Fel Domination first")
			end
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
		if opts.onClick then
			b:HookScript("PostClick", function(btn, mouse, down)
				if not down then opts.onClick(btn, mouse) end
			end)
		end
		SecureHandlerWrapScript(b, "OnClick", main, MENU_PRE, MENU_CLOSE)
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
	if spell then return spell end
	for _, e in ipairs(main.entries) do
		spell = ns.BestSpell(e)
		if spell then return spell end
	end
end

local function KnownCount(main)
	local n = 0
	for _, b in ipairs(main.items) do
		if b.spellID then n = n + 1 end
	end
	return n
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

	-- The grimoire: shard count, filling with fel light as shards accumulate.
	local book = CreateButton("Book")
	book.title = ns.buttonTitles.Book
	book.binding = nil
	book.icon:SetTexture(BOOK_ICON)
	book.fill = book:CreateTexture(nil, "ARTWORK")
	book.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
	book.fill:SetBlendMode("ADD")
	book.fill:SetGradient("VERTICAL", CreateColor(0.55, 0.2, 0.9, 0.55), CreateColor(0.3, 1, 0.3, 0.15))
	book.fill:SetPoint("BOTTOMLEFT")
	book.fill:SetPoint("BOTTOMRIGHT")
	book.Count:SetFontObject("NumberFontNormalLarge")
	book.Count:ClearAllPoints()
	book.Count:SetPoint("CENTER", 0, -2)
	book:RegisterForClicks("AnyUp")
	book:RegisterForDrag("LeftButton")
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
	book:SetScript("OnDragStart", function()
		if IsShiftKeyDown() and not ns.db.locked and not InCombatLockdown() and not ns.useElvUI then
			bar:StartMoving()
		end
	end)
	book:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		local point, _, relPoint, x, y = bar:GetPoint()
		ns.db.point = { point, "UIParent", relPoint, x, y }
	end)
	book:SetScript("OnEnter", function(btn)
		TooltipAnchor(btn)
		GameTooltip:AddLine("Grimoire")
		GameTooltip:AddDoubleLine("Soul Shards", ns.shards, 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Gained this session", ns.sessionShards or 0, 1, 1, 1, 0.6, 1, 0.6)
		if ns.db.shardCap > 0 then
			GameTooltip:AddDoubleLine("Cap", ns.db.shardCap, 1, 1, 1, 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		if ns.db.shardCap > 0 and ns.shards > ns.db.shardCap then
			AddHint("Left-click: delete extra shards")
		elseif ns.db.summonQueue then
			AddHint("Left-click: show/hide the summon queue")
		end
		AddHint("Right-click: options")
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
		local last = ns.char.lastSoulstone
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
			GameTooltip:Show()
		end)
	end
	for _, main in ipairs({ buffs, control, demons }) do
		main:SetScript("OnEnter", function(btn)
			TooltipAnchor(btn)
			GameTooltip:AddLine(btn.title)
			if btn == control and ns.creatureAlert then
				GameTooltip:AddLine(ns.creatureAlert, 0.2, 1, 0.2)
			end
			if btn == buffs and btn.glow:IsShown() then
				GameTooltip:AddLine("You have no armor on.", 1, 0.3, 0.3)
			end
			GameTooltip:AddLine(" ")
			AddHint("Click: open the menu")
			if btn == demons and ns.hasFelDomination then AddHint("Shift-click a demon: Fel Domination + summon") end
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
		GameTooltip:AddLine(" ")
		AddHint("Left-click: Ritual of Summoning on your target")
		if ns.hasPortal then AddHint("Right-click: Portal of Summoning") end
		if ns.db.summonAnnounce then AddHint("Announces the summon to your group") end
		GameTooltip:Show()
	end)

	ns:UpdateSecure()
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

local function LayoutMenu(main, size, gap, vertical)
	local prev
	for _, b in ipairs(main.items) do
		b:SetSize(size, size)
		b.glow:SetSize(size * 1.9, size * 1.9)
		b:ClearAllPoints()
		if b.spellID then
			if vertical then
				b:SetPoint("LEFT", prev or main, "RIGHT", gap, 0)
			else
				b:SetPoint("BOTTOM", prev or main, "TOP", 0, gap)
			end
			b:Show()
			prev = b
		else
			b:Hide()
		end
	end
	main.flyout:SetAllPoints(main)
end

function ns:Layout()
	local size, gap, vertical = ns.db.buttonSize, ns.db.spacing, ns.db.vertical
	local offset, thickness = gap, size
	for _, key in ipairs(ORDER) do
		local btn = buttons[key]
		local s = key == "Book" and math.floor(size * BOOK_SCALE) or size
		btn:SetSize(s, s)
		btn.glow:SetSize(s * 1.9, s * 1.9)
		btn:ClearAllPoints()
		if IsVisible(key) then
			if vertical then
				btn:SetPoint("TOP", bar, "TOP", 0, -offset)
			else
				btn:SetPoint("LEFT", bar, "LEFT", offset, 0)
			end
			btn:Show()
			offset = offset + s + gap
			thickness = math.max(thickness, s)
		else
			btn:Hide()
		end
	end
	if vertical then
		bar:SetSize(thickness + gap * 2, offset)
	else
		bar:SetSize(offset, thickness + gap * 2)
	end
	for _, main in pairs(ns.menus) do
		LayoutMenu(main, size, gap, vertical)
	end
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
	btn.icon:SetDesaturated(not item and ns.shards == 0)
	SetItemCooldown(btn, item or KnownItem(family))
	SetGlow(btn, ns:IsOutdated(family))
end

local function UpdateHotkey(btn)
	local key = btn.binding and GetBindingKey(btn.binding)
	local text = key and GetBindingText(key, true) or ""
	btn.HotKey:SetText(text)
	if ns.FormatHotkey then ns.FormatHotkey(btn) end
end

function ns:UpdateVisuals()
	if not bar then return end

	local book = buttons.Book
	book.Count:SetText(ns.shards)
	if ns.shards == 0 then
		book.Count:SetTextColor(1, 0.2, 0.2)
	elseif ns.shards <= ns.db.shardLow then
		book.Count:SetTextColor(1, 0.82, 0)
	else
		book.Count:SetTextColor(1, 1, 1)
	end
	local full = ns.db.shardCap > 0 and ns.db.shardCap or 20
	local ratio = math.min(ns.shards / full, 1)
	book.fill:SetHeight(math.max(book:GetHeight() * ratio, 0.01))
	book.fill:SetShown(ratio > 0)
	SetGlow(book, ns.db.shardCap > 0 and ns.shards > ns.db.shardCap)

	UpdateStoneButton(buttons.Healthstone, "healthstone")
	UpdateStoneButton(buttons.Soulstone, "soulstone")

	local ws = buttons.WeaponStone
	local fam = ns.known.firestone and "firestone" or "spellstone"
	local item = StoneItem(fam)
	ws.icon:SetTexture(item and C_Item.GetItemIconByID(item) or SpellIcon(ns.known[fam] and ns.known[fam].spellID) or 134400)
	ns:UpdateWeaponGlow()

	for key, main in pairs(ns.menus) do
		for _, b in ipairs(main.items) do
			b.icon:SetTexture(SpellIcon(b.spellID or ns.BestSpell(b.entry) or b.entry.ranks and b.entry.ranks[1] or b.entry.spell))
			UpdateHotkey(b)
		end
		if main.mode == "default" then
			main.icon:SetTexture(SpellIcon(main.spellID) or 136122)
			SetSpellCooldown(main, main.spellID)
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

	local rs = buttons.Ritual
	rs.icon:SetTexture(SpellIcon(ns.Data.ritualOfSummoning) or 136223)
	SetSpellCooldown(rs, ns.hasPortal and ns.Data.portalOfSummoning or nil)

	for _, key in ipairs({ "Healthstone", "Soulstone", "WeaponStone", "Mount", "Ritual" }) do
		UpdateHotkey(buttons[key])
	end
end
