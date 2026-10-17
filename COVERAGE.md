# Defensive coverage audit — Retail 12.1.5

Roster target: **13 classes and 40 specializations**, including Demon Hunter Devourer (1480). The regression suite checks the exact class/spec IDs and rejects missing, unexpected, or mismatched mappings.

Implemented catalogue; not a certified exhaustive list of live-game spells. Optional talents require inspection. Protected sensors require available Blizzard APIs. Readable cast events cannot recover hidden spell IDs.

| Spec | Personal defensive entries |
|---|---|
| Arcane (62) | Prismatic Barrier, Ice Block / Ice Cold, Alter Time |
| Fire (63) | Blazing Barrier, Ice Block / Ice Cold, Alter Time |
| Frost (64) | Ice Barrier, Ice Block / Ice Cold, Alter Time |
| Holy (65) | Divine Shield, Divine Protection |
| Protection (66) | Divine Shield, Guardian of Ancient Kings, Ardent Defender |
| Retribution (70) | Divine Shield, Divine Protection, Shield of Vengeance |
| Arms (71) | Spell Reflection, Die by the Sword |
| Fury (72) | Spell Reflection, Enraged Regeneration |
| Protection (73) | Spell Reflection, Shield Wall, Last Stand, Demoralizing Shout |
| Balance (102) | Barkskin |
| Feral (103) | Barkskin |
| Guardian (104) | Barkskin, Survival Instincts, Incarnation: Guardian of Ursoc |
| Restoration (105) | Barkskin |
| Blood (250) | Icebound Fortitude, Anti-Magic Shell, Dancing Rune Weapon, Vampiric Blood |
| Frost (251) | Icebound Fortitude, Anti-Magic Shell |
| Unholy (252) | Icebound Fortitude, Anti-Magic Shell |
| Beast Mastery (253) | Aspect of the Turtle, Survival of the Fittest, Exhilaration |
| Marksmanship (254) | Aspect of the Turtle, Survival of the Fittest, Exhilaration |
| Survival (255) | Aspect of the Turtle, Survival of the Fittest, Exhilaration |
| Discipline (256) | Fade, Desperate Prayer |
| Holy (257) | Fade, Desperate Prayer |
| Shadow (258) | Fade, Desperate Prayer, Dispersion |
| Assassination (259) | Feint, Cloak of Shadows, Evasion |
| Outlaw (260) | Feint, Cloak of Shadows, Evasion |
| Subtlety (261) | Feint, Cloak of Shadows, Evasion |
| Elemental (262) | Astral Shift |
| Enhancement (263) | Astral Shift |
| Restoration (264) | Astral Shift |
| Affliction (265) | Dark Pact, Unending Resolve |
| Demonology (266) | Dark Pact, Unending Resolve |
| Destruction (267) | Dark Pact, Unending Resolve |
| Brewmaster (268) | Fortifying Brew, Celestial Brew |
| Windwalker (269) | Diffuse Magic, Fortifying Brew, Touch of Karma |
| Mistweaver (270) | Diffuse Magic, Fortifying Brew |
| Havoc (577) | Blur |
| Vengeance (581) | Fiery Brand, Metamorphosis |
| Devastation (1467) | Obsidian Scales |
| Preservation (1468) | Obsidian Scales |
| Augmentation (1473) | Obsidian Scales |
| Devourer (1480) | Blur |

## Spell detection paths

| Class | Spell | Preferred path |
|---|---|---|
| ITEM | Health Potion | Readable cast only |
| DEATHKNIGHT | Anti-Magic Zone | Protected sensor |
| MAGE | Prismatic Barrier | Readable cast only |
| MAGE | Blazing Barrier | Readable cast only |
| MAGE | Ice Barrier | Readable cast only |
| MONK | Diffuse Magic | Protected sensor |
| DEATHKNIGHT | Icebound Fortitude | Protected sensor |
| DEATHKNIGHT | Anti-Magic Shell | Protected sensor |
| DEATHKNIGHT | Dancing Rune Weapon | Protected sensor |
| DEATHKNIGHT | Vampiric Blood | Aura inference |
| DEMONHUNTER | Blur | Protected sensor |
| DEMONHUNTER | Fiery Brand | Readable cast only |
| DEMONHUNTER | Metamorphosis | Aura inference |
| DRUID | Barkskin | Protected sensor |
| DRUID | Survival Instincts | Protected sensor |
| DRUID | Incarnation: Guardian of Ursoc | Aura inference |
| DRUID | Convoke the Spirits | Aura inference |
| DRUID | Solar Beam | Readable cast only |
| DRUID | Ironbark | Protected sensor |
| EVOKER | Obsidian Scales | Protected sensor |
| EVOKER | Zephyr | Aura inference |
| EVOKER | Time Dilation | Protected sensor |
| EVOKER | Rewind | Protected sensor |
| HUNTER | Aspect of the Turtle | Protected sensor |
| HUNTER | Survival of the Fittest | Protected sensor |
| HUNTER | Exhilaration | Readable cast only |
| MAGE | Ice Block / Ice Cold | Protected sensor |
| MAGE | Alter Time | Protected sensor |
| MONK | Fortifying Brew | Protected sensor |
| MONK | Touch of Karma | Protected sensor |
| MONK | Celestial Brew | Readable cast only |
| MONK | Life Cocoon | Protected sensor |
| MONK | Revival | Readable cast only |
| MONK | Restoral | Readable cast only |
| MONK | Invoke Chi-Ji, the Red Crane | Readable cast only |
| MONK | Invoke Yu'lon, the Jade Serpent | Readable cast only |
| PALADIN | Divine Shield | Protected sensor |
| PALADIN | Blessing of Protection / Spellwarding | Protected sensor |
| PALADIN | Blessing of Sacrifice | Protected sensor |
| PALADIN | Blessing of Freedom | Protected sensor |
| PALADIN | Avenging Wrath (Holy) | Protected sensor |
| PALADIN | Avenging Crusader (Holy) | Protected sensor |
| PALADIN | Avenging Wrath (Protection) | Protected sensor |
| PALADIN | Sentinel (Protection) | Protected sensor |
| PALADIN | Divine Protection | Protected sensor |
| PALADIN | Divine Protection | Protected sensor |
| PALADIN | Lay on Hands | Protected sensor |
| PALADIN | Aura Mastery | Protected sensor |
| PALADIN | Guardian of Ancient Kings | Aura inference |
| PALADIN | Ardent Defender | Protected sensor |
| PALADIN | Shield of Vengeance | Aura inference |
| PRIEST | Fade | Protected sensor |
| PRIEST | Desperate Prayer | Protected sensor |
| PRIEST | Dispersion | Protected sensor |
| PRIEST | Pain Suppression | Protected sensor |
| PRIEST | Power Word: Barrier | Protected sensor |
| PRIEST | Ultimate Penitence | Protected sensor |
| PRIEST | Guardian Spirit | Protected sensor |
| PRIEST | Divine Hymn | Protected sensor |
| PRIEST | Apotheosis | Protected sensor |
| ROGUE | Feint | Readable cast only |
| ROGUE | Cloak of Shadows | Protected sensor |
| ROGUE | Evasion | Protected sensor |
| ROGUE | Cheat Death | Unsupported |
| SHAMAN | Astral Shift | Protected sensor |
| SHAMAN | Windveil | Unsupported |
| SHAMAN | Spirit Link Totem | Protected sensor |
| SHAMAN | Healing Tide Totem | Readable cast only |
| SHAMAN | Ascendance (Restoration) | Protected sensor |
| WARLOCK | Dark Pact | Protected sensor |
| WARLOCK | Unending Resolve | Protected sensor |
| WARRIOR | Spell Reflection | Protected sensor |
| WARRIOR | Die by the Sword | Protected sensor |
| WARRIOR | Enraged Regeneration | Protected sensor |
| WARRIOR | Shield Wall | Aura inference |
| WARRIOR | Rallying Cry | Protected sensor |
| WARRIOR | Last Stand | Aura inference |
| WARRIOR | Demoralizing Shout | Readable cast only |
| ITEM | Soulcoiler Ritual Vessel | Readable cast only |

Passive effects, unobservable resets, set bonuses, and remaining charges are not fully modelled. A detection path is not proof of in-game reliability.

New entries with cooldown=0 query installed-client base cooldown data. Missing data leaves the timer unknown.

References:
- https://github.com/Tercioo/Open-Raid-Library/blob/main/ThingsToMantain_Midnight.lua (IDs/spec mappings; older durations are not assumed current).
- https://worldofwarcraft.blizzard.com/en-us/news/24244455/midnight-pre-expansion-content-update-notes

Roster reference: https://news.blizzard.com/en-us/article/24235745/developer-insight-combat-for-everyone-in-midnight
Patch reference: https://worldofwarcraft.blizzard.com/en-us/news/24304162/
