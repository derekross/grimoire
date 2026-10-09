local addonName, ns = ...

-- Spell and item IDs checked against Wowhead's Forever data (build 1.60.1).
-- Forever keeps the Classic IDs. Every learned rank is a separate spell, named plainly
-- ("Create Healthstone"), so ranks are tracked by ID. itemName is the fallback match
-- if Blizzard ever re-IDs a stone.
ns.Data = {
	soulShard = 6265,
	felDomination = 18708,
	ritualOfSummoning = 698,
	soulstoneKeyword = "Soulstone", -- item use spells are "Soulstone Resurrection"

	stones = {
		healthstone = {
			{ spell = 6201, item = 5512, itemName = "Minor Healthstone", alt = { 19004, 19005 } },
			{ spell = 6202, item = 5511, itemName = "Lesser Healthstone", alt = { 19006, 19007 } },
			{ spell = 5699, item = 5509, itemName = "Healthstone", alt = { 19008, 19009 } },
			{ spell = 11729, item = 5510, itemName = "Greater Healthstone", alt = { 19010, 19011 } },
			{ spell = 11730, item = 9421, itemName = "Major Healthstone", alt = { 19012, 19013 } },
		},
		soulstone = {
			{ spell = 693, item = 5232, itemName = "Minor Soulstone" },
			{ spell = 20752, item = 16892, itemName = "Lesser Soulstone" },
			{ spell = 20755, item = 16893, itemName = "Soulstone" },
			{ spell = 20756, item = 16895, itemName = "Greater Soulstone" },
			{ spell = 20757, item = 16896, itemName = "Major Soulstone" },
		},
		firestone = {
			{ spell = 6366, item = 1254, itemName = "Lesser Firestone" },
			{ spell = 17951, item = 13699, itemName = "Firestone" },
			{ spell = 17952, item = 13700, itemName = "Greater Firestone" },
			{ spell = 17953, item = 13701, itemName = "Major Firestone" },
		},
		spellstone = {
			{ spell = 2362, item = 5522, itemName = "Spellstone" },
			{ spell = 17727, item = 13602, itemName = "Greater Spellstone" },
			{ spell = 17728, item = 13603, itemName = "Major Spellstone" },
		},
	},

	-- family = UnitCreatureFamily("pet"), used to show the active demon's icon.
	demons = {
		{ spell = 688, family = "Imp" },
		{ spell = 697, family = "Voidwalker" },
		{ spell = 712, family = "Succubus" },
		{ spell = 713, family = "Incubus" },
		{ spell = 691, family = "Felhunter" },
	},
}
