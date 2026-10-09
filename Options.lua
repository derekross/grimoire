local addonName, ns = ...

-- Key binding labels (Bindings.xml)
BINDING_HEADER_GRIMOIRE = "Grimoire"
for binding, label in pairs({
	["GrimoireHealthstoneButton:LeftButton"] = "Healthstone (create/use)",
	["GrimoireSoulstoneButton:LeftButton"] = "Soulstone (create/use)",
	["GrimoireWeaponStoneButton:LeftButton"] = "Firestone (create/apply)",
	["GrimoireWeaponStoneButton:RightButton"] = "Spellstone (create/apply)",
	["GrimoireCursesButton:LeftButton"] = "Cast default curse",
	["GrimoireCursesButton:RightButton"] = "Curse menu",
	["GrimoireBanesButton:LeftButton"] = "Cast default bane",
	["GrimoireBanesButton:RightButton"] = "Bane menu",
	["GrimoireBuffsButton:LeftButton"] = "Buff menu",
	["GrimoireControlButton:LeftButton"] = "Crowd control menu",
	["GrimoireDemonsButton:LeftButton"] = "Demon menu",
	["GrimoireMountButton:LeftButton"] = "Mount",
	["GrimoireRitualButton:LeftButton"] = "Ritual of Summoning",
	["GrimoireRitualButton:RightButton"] = "Portal of Summoning",
	["GrimoireSummonRow1:LeftButton"] = "Summon next in queue",
}) do
	_G["BINDING_NAME_CLICK " .. binding] = label
end

-- Settings shared by the Blizzard panel and the ElvUI options page.
-- path = nested key inside ns.db (e.g. { "speech", "demon" }); defaults to { key }.
ns.optionList = {
	{ type = "header", name = "Bar" },
	{ key = "showBar", name = "Show bar", type = "toggle" },
	{ key = "locked", name = "Lock bar", type = "toggle", desc = "Stops shift-drag on the book from moving the bar." },
	{ key = "ring", name = "Ring layout", type = "toggle", desc = "Book in the center with the buttons in a circle around it, like Necrosis." },
	{ key = "roundButtons", name = "Round buttons in the ring", type = "toggle", desc = "Changing this reloads the UI." },
	{ key = "ringAngle", name = "Ring start angle", type = "range", min = 0, max = 345, step = 15, desc = "Where the first button sits. 90 is the top." },
	{ key = "ringRadius", name = "Ring size", type = "range", min = 0.8, max = 1.6, step = 0.05 },
	{ key = "ringClockwise", name = "Ring runs clockwise", type = "toggle" },
	{ key = "vertical", name = "Vertical bar", type = "toggle", desc = "Ignored in the ring layout." },
	{ key = "scale", name = "Scale", type = "range", min = 0.5, max = 2, step = 0.05 },
	{ key = "buttonSize", name = "Button size", type = "range", min = 24, max = 64, step = 1 },
	{ key = "spacing", name = "Button spacing", type = "range", min = 0, max = 16, step = 1 },
	{ key = "menuAutoHide", name = "Menus close after (seconds)", type = "range", min = 1, max = 6, step = 0.5, desc = "How long an open menu stays after the mouse leaves it. Right-click keeps a menu open." },
	{ key = "bookMode", name = "Book shows", type = "select", values = { shards = "Soul Shards", soulstone = "Soulstone timer", mana = "Mana" }, order = { "shards", "soulstone", "mana" }, desc = "You can also scroll the mouse wheel over the book." },

	{ type = "header", name = "Shards and stones" },
	{ key = "shardLow", name = "Low shard warning", type = "range", min = 0, max = 10, step = 1, desc = "Shard count turns yellow at or below this." },
	{ key = "shardCap", name = "Shard cap (0 = off)", type = "range", min = 0, max = 32, step = 1, desc = "Offer to delete shards above this count. Never deletes without asking." },
	{ key = "sortShards", name = "Move shards into soul bags", type = "toggle" },
	{ key = "weaponWarnMinutes", name = "Weapon stone warning (min)", type = "range", min = 0, max = 30, step = 1, desc = "Glow when the main-hand stone has less than this left." },
	{ key = "tradeOnRightClick", name = "Right-click healthstone trades it", type = "toggle" },
	{ key = "armorReminder", name = "Glow Buffs when you have no armor", type = "toggle" },

	{ type = "header", name = "Timers and alerts" },
	{ key = "timers", name = "Crowd control timers", type = "toggle", desc = "Estimated from your own casts; can't see early breaks." },
	{ key = "soulstoneTimer", name = "Soulstone timer", type = "toggle" },
	{ key = "creatureAlert", name = "Banish/Subjugate target alert", type = "toggle" },
	{ key = "shadowTranceAlert", name = "Shadow Trance alert", type = "toggle" },
	{ key = "shadowTranceSound", name = "Shadow Trance sound", type = "toggle" },

	{ type = "header", name = "Summoning" },
	{ key = "summonAnnounce", name = "Announce summons", type = "toggle" },
	{ key = "summonMessage", name = "Summon message (%t = target)", type = "input" },
	{ key = "summonQueue", name = "Summon queue", type = "toggle", desc = "Collect summon requests from group chat and whispers." },
	{ key = "summonKeywords", name = "Summon keywords (comma separated)", type = "input" },
	{ key = "summonSync", name = "Share summons with other Grimoire warlocks", type = "toggle" },

	{ type = "header", name = "Chat messages (group only)" },
	{ key = "speechSoulstone", path = { "speech", "soulstone" }, name = "Announce soulstones", type = "toggle" },
	{ key = "speechSoulstoneWhisper", path = { "speech", "soulstoneWhisper" }, name = "Whisper the soulstoned player", type = "toggle" },
	{ key = "speechDemon", path = { "speech", "demon" }, name = "Demon summon lines", type = "toggle" },
	{ key = "speechMount", path = { "speech", "mount" }, name = "Mount lines", type = "toggle" },

	{ type = "header", name = "Buttons" },
}
for _, key in ipairs(ns.buttonOrder or {}) do
	if key ~= "Book" then
		table.insert(ns.optionList, { key = "show" .. key, path = { "hidden", key }, invert = true,
			name = "Show " .. ns.buttonTitles[key], type = "toggle" })
	end
end

local function Path(opt)
	return opt.path or { opt.key }
end

function ns:GetOption(opt)
	local t = ns.db
	local path = Path(opt)
	for i = 1, #path - 1 do t = t[path[i]] end
	local value = t[path[#path]]
	if opt.invert then return not value end
	return value
end

function ns:SetOptionValue(opt, value)
	local t = ns.db
	local path = Path(opt)
	for i = 1, #path - 1 do t = t[path[i]] end
	if opt.invert then value = not value end
	t[path[#path]] = value
	if opt.key == "summonKeywords" and ns.ParseSummonKeywords then ns.ParseSummonKeywords() end
	ns:ApplySettings()
	if opt.key == "ring" or opt.key == "roundButtons" then ns.Style.CheckShapeChange() end
end

-- Applies a changed setting; layout changes wait until combat ends.
function ns:ApplySettings()
	if not ns.bar then return end
	if InCombatLockdown() then
		ns.secureDirty = true
		ns.Print("Changes will apply when you leave combat.")
	else
		ns.bar:SetScale(ns.db.scale)
		ns:UpdateSecure()
	end
	ns:UpdateVisuals()
	ns:CheckShardCap()
end

function ns:SetOption(key, value)
	for _, opt in ipairs(ns.optionList) do
		if opt.key == key then return ns:SetOptionValue(opt, value) end
	end
end

function ns:SetupOptions()
	local category, layout = Settings.RegisterVerticalLayoutCategory("Grimoire")
	for _, opt in ipairs(ns.optionList) do
		if opt.type == "header" then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(opt.name))
		elseif opt.type == "select" then
			local setting = Settings.RegisterProxySetting(category, "GRIMOIRE_" .. opt.key, Settings.VarType.String, opt.name,
				ns:GetOption(opt), function() return ns:GetOption(opt) end, function(value) ns:SetOptionValue(opt, value) end)
			Settings.CreateDropdown(category, setting, function()
				local container = Settings.CreateControlTextContainer()
				for _, value in ipairs(opt.order) do container:Add(value, opt.values[value]) end
				return container:GetData()
			end, opt.desc)
		elseif opt.type ~= "input" then
			local varType = opt.type == "toggle" and Settings.VarType.Boolean or Settings.VarType.Number
			local default = ns:GetOption(opt)
			local setting = Settings.RegisterProxySetting(category, "GRIMOIRE_" .. opt.key, varType, opt.name, default,
				function() return ns:GetOption(opt) end,
				function(value) ns:SetOptionValue(opt, value) end)
			if opt.type == "toggle" then
				Settings.CreateCheckbox(category, setting, opt.desc)
			else
				local options = Settings.CreateSliderOptions(opt.min, opt.max, opt.step)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
				Settings.CreateSlider(category, setting, options, opt.desc)
			end
		end
	end
	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

local function OpenOptions()
	if ns.OpenElvUIOptions and ns:OpenElvUIOptions() then return end
	Settings.OpenToCategory(ns.settingsCategory:GetID())
end

SLASH_GRIMOIRE1 = "/grim"
SLASH_GRIMOIRE2 = "/grimoire"
SlashCmdList.GRIMOIRE = function(msg)
	if not ns.db then
		ns.Print("Grimoire only runs on warlocks.")
		return
	end
	local cmd, arg = msg:lower():match("^(%S*)%s*(.-)$")
	if cmd == "" or cmd == "config" or cmd == "options" then
		OpenOptions()
	elseif cmd == "show" or cmd == "hide" then
		ns:SetOption("showBar", cmd == "show")
	elseif cmd == "book" and ns.bookModeNames[arg] then
		ns:SetOption("bookMode", arg)
	elseif cmd == "ring" or cmd == "bar" then
		ns:SetOption("ring", cmd == "ring")
	elseif cmd == "lock" or cmd == "unlock" then
		ns:SetOption("locked", cmd == "lock")
	elseif cmd == "cap" and tonumber(arg) then
		ns:SetOption("shardCap", math.max(0, math.floor(tonumber(arg))))
		ns.Print(("Shard cap set to %d%s."):format(ns.db.shardCap, ns.db.shardCap == 0 and " (off)" or ""))
	elseif cmd == "msg" then
		ns:SetOption("summonMessage", msg:match("^%S+%s+(.+)$") or ns.defaults.summonMessage)
		ns.Print("Summon message: " .. ns.db.summonMessage)
	elseif cmd == "keywords" then
		ns:SetOption("summonKeywords", msg:match("^%S+%s+(.+)$") or ns.defaults.summonKeywords)
		ns.Print("Summon keywords: " .. ns.db.summonKeywords)
	elseif cmd == "queue" then
		if ns.ToggleSummonQueue then ns:ToggleSummonQueue() end
	elseif cmd == "reset" then
		if InCombatLockdown() then return ns.Print("Not in combat.") end
		ns.db.point = CopyTable(ns.defaults.point)
		ns.bar:ClearAllPoints()
		ns.bar:SetPoint(ns.db.point[1], UIParent, ns.db.point[3], ns.db.point[4], ns.db.point[5])
		ns.Print("Bar position reset.")
	else
		ns.Print("/grim [config | ring | bar | book shards|soulstone|mana | show | hide | lock | unlock | cap <n> | msg <text> | keywords <a, b> | queue | reset]")
	end
end
