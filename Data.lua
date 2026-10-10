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

	portalOfSummoning = 437169,
	shadowTrance = 17941, -- Nightfall proc aura

	-- Menus: each entry lists every rank; the highest known one is cast.
	curses = {
		{ ranks = { 702, 1108, 6205, 7646, 11707, 11708 } },   -- Curse of Weakness
		{ ranks = { 704, 7658, 7659, 11717 } },                -- Curse of Recklessness
		{ ranks = { 1714, 11719 } },                           -- Curse of Tongues
		{ ranks = { 440892, 1311676, 1311677, 1311680 } },     -- Curse of the Elements (new IDs in Forever)
		{ ranks = { 18223 } },                                 -- Curse of Exhaustion (talent)
		{ ranks = { 18288 } },                                 -- Amplify Curse (talent)
	},
	banes = {
		{ ranks = { 980, 1014, 6217, 11711, 11712, 11713 } },  -- Bane of Agony
		{ ranks = { 603 } },                                   -- Bane of Doom
		{ ranks = { 1225228 } },                               -- Bane of Havoc (talent)
	},
	buffs = {
		{ ranks = { 706, 1086, 11733, 11734, 11735 }, fallback = { 687, 696 } }, -- Demon Armor, else Demon Skin
		{ ranks = { 19028 } },                                 -- Soul Link (talent)
		{ ranks = { 18788 } },                                 -- Demonic Sacrifice (talent)
		{ ranks = { 6229, 11739, 11740, 28610 } },             -- Shadow Ward
		{ ranks = { 5697 } },                                  -- Unending Breath
		{ ranks = { 132, 2970, 11743 } },                      -- Detect Invisibility
		{ ranks = { 126 } },                                   -- Eye of Kilrogg
		{ ranks = { 5500 } },                                  -- Sense Demons
	},
	-- Armor auras for the "no armor" reminder.
	armor = { 687, 696, 706, 1086, 11733, 11734, 11735 },
	-- durations are per rank, in seconds (PvE, before talents/diminishing returns)
	control = {
		{ ranks = { 710, 18647 }, durations = { 20, 30 }, banish = true },  -- Banish
		{ ranks = { 5782, 6213, 6215 }, durations = { 10, 15, 20 } },       -- Fear
		{ ranks = { 5484, 17928 }, durations = { 10, 15 } },                -- Howl of Terror
		{ ranks = { 1098, 11725, 11726 }, durations = { 300, 300, 300 }, subjugate = true, shard = true }, -- Subjugate Demon
		{ ranks = { 6789, 17925, 17926 }, durations = { 3, 3, 3 } },        -- Death Coil
	},
	mounts = { 23161, 5784 }, -- Dreadsteed first, then Felsteed
	lifeTap = { 1454, 1455, 1456, 11687, 11688, 11689 },

	-- family = UnitCreatureFamily("pet"), used to show the active demon's icon.
	demons = {
		{ spell = 688, family = "Imp" },
		{ spell = 697, family = "Voidwalker", shard = true },
		{ spell = 712, family = "Succubus", shard = true },
		{ spell = 713, family = "Incubus", shard = true },
		{ spell = 691, family = "Felhunter", shard = true },
	},
}
