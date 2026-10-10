# Grimoire

A warlock helper for **World of Warcraft: Forever**, in the spirit of Necrosis.

## Features

- **The grimoire:** a tome on the bar showing your soul shard count. It fills with fel light as shards build up. It also tracks shards gained this session, can sort shards into a soul bag, and has an optional cap that offers to delete extra shards (always asking first).
- **Healthstone:** creates your highest learned rank, or uses the stone in your bags. Glows when your stone is outdated; shift-right-click deletes it (with a prompt) so you can make the new rank. Right-click trades it to your friendly target.
- **Soulstone:** creates the stone, or uses it on your mouseover, then your target, then yourself. A 30-minute timer warns you before it expires. Optionally announces the soulstone to your group and whispers the target.
- **Weapon stone:** left-click for Firestone, right-click for Spellstone. Creates the stone or applies it to your main hand, and glows when the enchant is missing or about to expire.
- **Curse and Bane menus:** left-click casts your default, right-click opens the menu, and the spell you pick becomes the new default. Banes are separate in Forever.
- **Buff menu:** Demon Armor/Skin, Soul Link, Demonic Sacrifice, Shadow Ward, Unending Breath, Detect Invisibility, Eye of Kilrogg, Sense Demons. Glows when you have no armor on.
- **Crowd control menu:** Banish, Fear, Howl of Terror, Subjugate Demon, Death Coil. Glows when your target can be banished or subjugated.
- **Demon menu:** the demons you know. Shift-click casts Fel Domination first.
- **Mount button:** your best warlock mount, Dreadsteed or Felsteed.
- **Summoning:** left-click Ritual of Summoning, right-click Portal of Summoning, with a group announcement.
- **Summon queue:** collects "123" / "summon" requests from group chat and whispers. Click a name to target and summon them. It shows offline, dead, and already-summoned players, and syncs with other Grimoire warlocks.
- **Timers:** estimated Banish, Fear, Howl, Subjugate and Death Coil bars, started from your own casts, with warnings before Banish and Subjugate end.
- **Shadow Trance alert** when Nightfall procs.
- **Chat lines** for soulstones, demon summons and mounts. These go to party/raid only; Blizzard blocks addons from using /say in the open world.
- **Keybindings** for every button: Key Bindings → AddOns → Grimoire.
- **Ring layout:** the book in the center with the buttons in a circle around it, like Necrosis. Start angle, size and direction are adjustable. Menus open outward. Three styles:
  - **Grimoire** (default): Grimoire's own art. A leather tome with a fel sigil sits in an iron bezel whose 20 sockets light up with your soul shards, surrounded by iron-rimmed round buttons.
  - **Flat round:** thin-rimmed round buttons in your ElvUI colors.
  - **Square:** ElvUI's action-button style.
- **Menus** close on their own shortly after the mouse leaves, even in combat. Right-click keeps a menu open (shift-right-click for Curses and Banes).
- **At a glance:** icons turn blue when you're out of mana and grey when you can't cast them. Menu icons show their mana cost. Tooltips show soul shard costs.
- **Book display:** soul shards, your soulstone countdown, or mana. Scroll the mouse wheel over the book to switch.

## ElvUI integration

When ElvUI is loaded:

- Buttons use ElvUI's action-button style.
- The bar has a `/moveui` mover.
- Settings appear under `/ec` → Grimoire.
- A **Soul Shards** datatext can be placed on any panel.

Without ElvUI, Grimoire uses a plain look, and its settings are in Blizzard's AddOns options.

## Commands

`/grim [config | show | hide | lock | unlock | cap <n> | msg <text> | keywords <a, b> | queue | reset]`

## Limitations

Forever applies retail's addon restrictions: auras, health and cooldowns are hidden from addons in combat. Crowd control timers are therefore estimates: they can't see early breaks or resists. DoT timers, threat and low-health alerts aren't possible; use the built-in Cooldown Manager for DoTs.

## Art

All textures in `Media/` are original and drawn in code by `tools/art/draw.py` (needs Python cairo and ImageMagick). Run `python3 tools/art/draw.py Media` to regenerate them.
