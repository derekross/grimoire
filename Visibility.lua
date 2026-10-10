local addonName, ns = ...

-- When the bar shows, and how strongly. Showing and hiding go through a secure state
-- driver so "show in combat" works even though the bar holds secure buttons; the
-- driver can only be changed out of combat, so resting changes wait until then.
-- Fading only changes alpha, which is always allowed.

local FADE_SPEED = 4 -- alpha per second

local function Driver()
	local db = ns.db
	if not db.showBar then return "hide" end
	if db.visibility == "combat" then return "[combat] show; hide" end
	if db.hideResting and IsResting() then return "[combat] show; hide" end
	return "show"
end

function ns:UpdateVisibility()
	if not ns.bar then return end
	if InCombatLockdown() then
		ns.visibilityDirty = true
		return
	end
	ns.visibilityDirty = nil
	local driver = Driver()
	if driver ~= ns.visibilityDriver then
		ns.visibilityDriver = driver
		RegisterStateDriver(ns.bar, "visibility", driver)
	end
end

-- True while the player is pointing at the bar or one of its open menus.
local function Hovered()
	if ns.bar:IsMouseOver() then return true end
	for _, main in pairs(ns.menus) do
		if main.flyout:IsShown() then
			for _, b in ipairs(main.items) do
				if b:IsShown() and b:IsMouseOver() then return true end
			end
		end
	end
end

ns:Module(function()
	local fader = CreateFrame("Frame")
	local elapsedSince = 0
	fader:SetScript("OnUpdate", function(_, elapsed)
		elapsedSince = elapsedSince + elapsed
		if elapsedSince < 0.05 then return end
		local step = elapsedSince * FADE_SPEED
		elapsedSince = 0
		local bar = ns.bar
		local target = 1
		if ns.db.fadeOut and not Hovered() then target = ns.db.fadeAlpha end
		local alpha = bar:GetAlpha()
		if math.abs(alpha - target) < 0.01 then return end
		bar:SetAlpha(alpha < target and math.min(target, alpha + step) or math.max(target, alpha - step))
	end)
	ns:UpdateVisibility()
end)

ns:On("PLAYER_UPDATE_RESTING", function() ns:UpdateVisibility() end)
ns:On("PLAYER_ENTERING_WORLD", function() ns:UpdateVisibility() end)
ns:On("PLAYER_REGEN_ENABLED", function()
	if ns.visibilityDirty then ns:UpdateVisibility() end
end)
