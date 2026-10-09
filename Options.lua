local addonName, ns = ...

-- Settings shared by the Blizzard panel and the ElvUI options page.
ns.optionList = {
	{ key = "showBar", name = "Show bar", type = "toggle" },
	{ key = "locked", name = "Lock bar", type = "toggle", desc = "Stops shift-drag moving the bar (ElvUI users move it with /moveui)." },
	{ key = "vertical", name = "Vertical bar", type = "toggle" },
	{ key = "scale", name = "Scale", type = "range", min = 0.5, max = 2, step = 0.05 },
	{ key = "buttonSize", name = "Button size", type = "range", min = 24, max = 64, step = 1 },
	{ key = "spacing", name = "Button spacing", type = "range", min = 0, max = 16, step = 1 },
	{ key = "shardLow", name = "Low shard warning", type = "range", min = 0, max = 10, step = 1, desc = "Shard count turns yellow at or below this." },
	{ key = "shardCap", name = "Shard cap (0 = off)", type = "range", min = 0, max = 32, step = 1, desc = "Offer to delete shards above this count. Never deletes without asking." },
	{ key = "weaponWarnMinutes", name = "Weapon stone warning (min)", type = "range", min = 0, max = 30, step = 1, desc = "Glow when the main-hand stone has less than this left." },
	{ key = "tradeOnRightClick", name = "Right-click healthstone trades it", type = "toggle" },
	{ key = "summonAnnounce", name = "Announce Ritual of Summoning", type = "toggle" },
	{ key = "summonMessage", name = "Summon message (%t = target)", type = "input" },
}

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
	ns.db[key] = value
	ns:ApplySettings()
end

function ns:SetupOptions()
	local category = Settings.RegisterVerticalLayoutCategory("Grimoire")
	for _, opt in ipairs(ns.optionList) do
		if opt.type ~= "input" then
			local varType = opt.type == "toggle" and Settings.VarType.Boolean or Settings.VarType.Number
			local setting = Settings.RegisterAddOnSetting(category, "GRIMOIRE_" .. opt.key, opt.key, ns.db,
				varType, opt.name, ns.defaults[opt.key])
			setting:SetValueChangedCallback(function() ns:ApplySettings() end)
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
	elseif cmd == "lock" or cmd == "unlock" then
		ns:SetOption("locked", cmd == "lock")
	elseif cmd == "cap" and tonumber(arg) then
		ns:SetOption("shardCap", math.max(0, math.floor(tonumber(arg))))
		ns.Print(("Shard cap set to %d%s."):format(ns.db.shardCap, ns.db.shardCap == 0 and " (off)" or ""))
	elseif cmd == "msg" then
		ns.db.summonMessage = msg:match("^%S+%s+(.+)$") or ns.defaults.summonMessage
		ns.Print("Summon message: " .. ns.db.summonMessage)
	elseif cmd == "reset" then
		if InCombatLockdown() then return ns.Print("Not in combat.") end
		ns.db.point = CopyTable(ns.defaults.point)
		ns.bar:ClearAllPoints()
		ns.bar:SetPoint(ns.db.point[1], UIParent, ns.db.point[3], ns.db.point[4], ns.db.point[5])
		ns.Print("Bar position reset.")
	else
		ns.Print("/grim [config | show | hide | lock | unlock | cap <n> | msg <text> | reset]")
	end
end
