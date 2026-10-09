# Grimoire

A warlock helper for **World of Warcraft: Forever**, in the spirit of Necrosis.

## Features

- **Healthstone button**: creates your highest learned rank, or uses the stone in your bags. Glows when your stone is outdated; shift-right-click deletes it (with a prompt) so you can make the new rank. Right-click trades it to your friendly target.
- **Soulstone button**: creates the stone, or uses it on your mouseover, then your target, then yourself. Remembers who you last soulstoned.
- **Weapon stone button**: left-click for Firestone, right-click for Spellstone. Creates the stone or applies it to your main hand, and glows when the enchant is missing or about to expire.
- **Soul shard counter**: colored when low, with an optional cap that offers to delete extra shards. It always asks first.
- **Demon menu**: lists the demons you know. Shift-click casts Fel Domination first.
- **Ritual of Summoning**: casts on your target and announces the summon to your group.

## ElvUI integration

When ElvUI is loaded:

- Buttons use ElvUI's action-button style.
- The bar has a `/moveui` mover.
- Settings appear under `/ec` → Grimoire.
- A **Soul Shards** datatext can be placed on any panel.

Without ElvUI, Grimoire uses a plain look, and its settings are in Blizzard's AddOns options.

## Commands

`/grim [config | show | hide | lock | unlock | cap <n> | msg <text> | reset]`

## Limitations

Forever applies retail's addon restrictions: auras, health and cooldowns are hidden from addons in combat. That rules out DoT timers and low-health alerts. Use the built-in Cooldown Manager for those.
