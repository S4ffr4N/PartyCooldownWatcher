local addonName, ns = ...

-- PartyCDLens spell database.
-- Detection is layered. v0.5 prefers exact Blizzard AuraContainer spell-ID sensors for
-- abilities covered by KiraUI's PartyCD map, then falls back to anonymous filtered-aura
-- inference for entries without an exact sensor. Experimental entries are never promoted
-- to a trustworthy READY state without observed evidence.
--
-- category order in the UI:
-- defensive -> external -> group -> state -> offensive

local ALL_DK       = {250, 251, 252}
local ALL_DH_DPS   = {577, 1480} -- Havoc, Devourer
local ALL_DRUID_DPS= {102, 103}  -- Balance, Feral
local ALL_EVOKER_DPS={1467,1473} -- Devastation, Augmentation
local ALL_HUNTER   = {253,254,255}
local ALL_MAGE     = {62,63,64}
local ALL_MONK_DPS = {269}
local ALL_PRIEST   = {256,257,258}
local ALL_ROGUE    = {259,260,261}
local ALL_SHAMAN_DPS={262,263}
local ALL_WARLOCK  = {265,266,267}
local ALL_WARRIOR_DPS={71,72}

local function S(t)
    t.enabledByDefault = t.enabledByDefault ~= false
    t.category = t.category or "defensive"
    t.target = t.target or "self"
    t.reliability = t.reliability or "experimental"
    t.auraIDs = t.auraIDs or (t.spellID and {t.spellID} or {})
    t.spellIDs = t.spellIDs or (t.spellID and {t.spellID} or {})
    if (t.baseCharges and t.baseCharges > 1) or t.chargeTalentIDs then
        t.chargesPossible = true
    end
    return t
end

ns.ClassOrder = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE",
    "MONK", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

ns.ClassNames = {
    DEATHKNIGHT="Death Knight", DEMONHUNTER="Demon Hunter", DRUID="Druid",
    EVOKER="Evoker", HUNTER="Hunter", MAGE="Mage", MONK="Monk",
    PALADIN="Paladin", PRIEST="Priest", ROGUE="Rogue", SHAMAN="Shaman",
    WARLOCK="Warlock", WARRIOR="Warrior",
}

ns.SpecNames = {
    [250]="Blood", [251]="Frost", [252]="Unholy",
    [577]="Havoc", [581]="Vengeance", [1480]="Devourer",
    [102]="Balance", [103]="Feral", [104]="Guardian", [105]="Restoration",
    [1467]="Devastation", [1468]="Preservation", [1473]="Augmentation",
    [253]="Beast Mastery", [254]="Marksmanship", [255]="Survival",
    [62]="Arcane", [63]="Fire", [64]="Frost",
    [268]="Brewmaster", [269]="Windwalker", [270]="Mistweaver",
    [65]="Holy", [66]="Protection", [70]="Retribution",
    [256]="Discipline", [257]="Holy", [258]="Shadow",
    [259]="Assassination", [260]="Outlaw", [261]="Subtlety",
    [262]="Elemental", [263]="Enhancement", [264]="Restoration",
    [265]="Affliction", [266]="Demonology", [267]="Destruction",
    [71]="Arms", [72]="Fury", [73]="Protection",
}

ns.Spells = {
    -- Healing potions share one timer; inventory is never assumed inspectable.
    -- Instant healing has no aura suitable for the protected AuraContainer path.
    S{ key="health_potion", name="Health Potion", class="ITEM", consumable=true,
        castOnly=true, spellIDs={1234768,1295247,431416}, auraIDs={}, itemID=241304,
        cooldown=300, category="defensive", reliability="experimental",
        warning="Tracks observed Silvermoon (including Fleeting), Concentrated Silvermoon, and Algari healing potion use. Hidden cast IDs cannot be detected. Remaining inventory and potion cooldown modifiers are unknown; estimated ready does not mean a potion is available." },
    -- Additional defensive entries use the installed client's base cooldown data.
    -- Inspection gates optional talents; unavailable client data leaves the timer UNKNOWN.
    S{ key="dk_amz", name="Anti-Magic Zone", class="DEATHKNIGHT", specs=ALL_DK, spellID=51052, cooldown=0, category="group", optional=true, reliability="experimental", talentCD=true },
    S{ key="mage_prismatic", name="Prismatic Barrier", class="MAGE", specs={62}, spellID=235450, cooldown=0, reliability="experimental", dynamicCDR=true },
    S{ key="mage_blazing", name="Blazing Barrier", class="MAGE", specs={63}, spellID=235313, cooldown=0, reliability="experimental", dynamicCDR=true },
    S{ key="mage_ice_barrier", name="Ice Barrier", class="MAGE", specs={64}, spellID=11426, cooldown=0, reliability="experimental", dynamicCDR=true },
    S{ key="monk_diffuse", name="Diffuse Magic", class="MONK", specs={269,270}, spellID=122783, cooldown=0, optional=true, reliability="experimental", talentCD=true },
    -- DEATH KNIGHT
    S{ key="dk_ibf", name="Icebound Fortitude", class="DEATHKNIGHT", specs=ALL_DK, spellID=48792, cooldown=120, reliability="reliable" },
    S{ key="dk_ams", name="Anti-Magic Shell", class="DEATHKNIGHT", specs=ALL_DK, spellID=48707, cooldown=60, reliability="reliable", talentCD=true },
    S{ key="blood_drw", name="Dancing Rune Weapon", class="DEATHKNIGHT", specs={250}, spellID=49028, cooldown=120, reliability="experimental" },
    S{ key="blood_vb", name="Vampiric Blood", class="DEATHKNIGHT", specs={250}, spellID=55233, cooldown=90, reliability="experimental", recommended=true },
    S{ key="frost_pillar", name="Pillar of Frost", class="DEATHKNIGHT", specs={251}, spellID=51271, cooldown=45, category="offensive", reliability="reliable" },
    S{ key="frost_breath", name="Breath of Sindragosa", class="DEATHKNIGHT", specs={251}, spellIDs={1249658,152279}, auraIDs={1249658,152279}, cooldown=90, category="offensive", optional=true, reliability="experimental" },
    S{ key="unholy_army", name="Army of the Dead", class="DEATHKNIGHT", specs={252}, spellID=42650, cooldown=180, category="offensive", reliability="experimental", noAuraLikely=true },

    -- DEMON HUNTER
    S{ key="dh_blur", name="Blur", class="DEMONHUNTER", specs=ALL_DH_DPS, spellID=198589, cooldown=60, reliability="reliable", baseCharges=1, chargeTalentIDs={1266307}, chargeTalentAdd=1 },
    S{ key="havoc_meta", name="Metamorphosis", class="DEMONHUNTER", specs={577}, spellIDs={191427}, auraIDs={162264}, cooldown=120, category="offensive", reliability="reliable", modelInference=true, warning="Preferred path: exact Blizzard AuraContainer sensor for aura 162264, with a second <=10s sensor rejecting short Demonic. If that widget path is unavailable, the old model-duration heuristic remains only as a fallback." },
    S{ key="devourer_meta", name="Metamorphosis", class="DEMONHUNTER", specs={1480}, spellID=1217605, cooldown=120, category="offensive", reliability="experimental" },
    S{ key="vengeance_brand", name="Fiery Brand", class="DEMONHUNTER", specs={581}, spellID=204021, cooldown=60, reliability="reliable", baseCharges=1, chargeTalentIDs={389732}, chargeTalentAdd=1, chargeTalentCooldownReduction=12 },
    S{ key="vengeance_meta", name="Metamorphosis", class="DEMONHUNTER", specs={581}, spellID=187827, cooldown=120, reliability="experimental", dynamicCDR=true, warning="Last Resort/procs can make inferred Vengeance Meta timers wrong." },

    -- DRUID
    S{ key="druid_bark", name="Barkskin", class="DRUID", specs={102,103,104,105}, spellID=22812, cooldown=60, reliability="reliable" },
    S{ key="guardian_si", name="Survival Instincts", class="DRUID", specs={104}, spellID=61336, auraIDs={61336,50322}, cooldown=180, reliability="experimental", warning="Current 12.1.5 spell data shows one charge; Blizzard aura flag/ID handling has also been inconsistent for Survival Instincts." },
    S{ key="guardian_incarn", name="Incarnation: Guardian of Ursoc", class="DRUID", specs={104}, spellID=102558, auraIDs={102558,50334}, cooldown=180, reliability="reliable", optional=true },
    S{ key="balance_incarn", name="Incarnation: Chosen of Elune", class="DRUID", specs={102}, spellID=102560, auraIDs={102560,390414}, cooldown=180, category="offensive", reliability="reliable", optional=true },
    S{ key="balance_ca", name="Celestial Alignment", class="DRUID", specs={102}, spellID=194223, cooldown=180, category="offensive", reliability="reliable" },
    S{ key="feral_incarn", name="Incarnation: Avatar of Ashamane", class="DRUID", specs={103}, spellID=102543, cooldown=180, category="offensive", reliability="reliable", optional=true },
    S{ key="feral_berserk", name="Berserk", class="DRUID", specs={103}, spellID=106951, cooldown=180, category="offensive", reliability="reliable" },
    S{ key="druid_convoke_dps", name="Convoke the Spirits", class="DRUID", specs={102,103}, spellIDs={391528,323764}, auraIDs={391528,323764}, cooldown=120, category="offensive", optional=true, reliability="experimental" },
    S{ key="druid_convoke_resto", name="Convoke the Spirits", class="DRUID", specs={105}, spellIDs={391528,323764}, auraIDs={391528,323764}, cooldown=120, category="group", optional=true, reliability="experimental" },
    S{ key="balance_solar", name="Solar Beam", class="DRUID", specs={102}, spellID=78675, cooldown=60, category="group", optional=true, reliability="experimental", noAuraLikely=true },
    S{ key="resto_ironbark", name="Ironbark", class="DRUID", specs={105}, spellID=102342, cooldown=90, category="external", target="party", reliability="reliable", talentCD=true },

    -- EVOKER
    S{ key="evoker_scales", name="Obsidian Scales", class="EVOKER", specs={1467,1468,1473}, spellID=363916, cooldown=90, reliability="reliable", baseCharges=1, chargeTalentIDs={375406}, chargeTalentAdd=1 },
    S{ key="evoker_zephyr", name="Zephyr", class="EVOKER", specs={1467,1468,1473}, spellID=374227, cooldown=120, category="group", target="party", optional=true, reliability="experimental" },
    S{ key="dev_dragonrage", name="Dragonrage", class="EVOKER", specs={1467}, spellID=375087, cooldown=120, category="offensive", reliability="reliable" },
    S{ key="aug_boe", name="Breath of Eons", class="EVOKER", specs={1473}, spellIDs={403631,442204}, auraIDs={403631,442204}, cooldown=120, category="offensive", reliability="experimental" },
    S{ key="pres_time_dilation", name="Time Dilation", class="EVOKER", specs={1468}, spellID=357170, cooldown=60, category="external", target="party", reliability="reliable", baseCharges=1, chargeTalentIDs={376204}, chargeTalentAdd=1, chargeTalentCooldownReduction=10, dynamicCDR=true, warning="Just in Time grants a second charge and -10s recharge; Essence healing casts can further reduce the real cooldown, so the local timer can be conservative." },
    S{ key="pres_rewind", name="Rewind", class="EVOKER", specs={1468}, spellIDs={363534,384089}, auraIDs={363534,384089}, cooldown=180, category="group", reliability="experimental" },

    -- HUNTER
    S{ key="hunter_turtle", name="Aspect of the Turtle", class="HUNTER", specs=ALL_HUNTER, spellID=186265, cooldown=180, reliability="reliable", talentCD=true },
    S{ key="hunter_sotf", name="Survival of the Fittest", class="HUNTER", specs=ALL_HUNTER, spellID=264735, cooldown=90, optional=true, reliability="reliable", baseCharges=1, chargeTalentIDs={459450}, chargeTalentAdd=1 },
    S{ key="hunter_exhil", name="Exhilaration", class="HUNTER", specs=ALL_HUNTER, spellID=109304, cooldown=120, reliability="experimental", noAuraLikely=true },
    S{ key="mm_trueshot", name="Trueshot", class="HUNTER", specs={254}, spellID=288613, cooldown=120, category="offensive", reliability="reliable", talentCD=true },
    S{ key="sv_coord", name="Coordinated Assault", class="HUNTER", specs={255}, spellID=360952, cooldown=120, category="offensive", reliability="experimental" },

    -- MAGE
    S{ key="mage_iceblock", name="Ice Block / Ice Cold", class="MAGE", specs=ALL_MAGE, spellIDs={45438,414659}, auraIDs={45438,414659}, cooldown=240, reliability="reliable", talentCD=true, cooldownTalentEffects={ { ids={382424}, perRank=30, maxRank=2, name="Winter's Protection" }, { ids={1265517}, perRank=30, maxRank=1, name="Permafrost Bauble" } }, warning="Cooldown is talent-aware: Winter's Protection reduces it by 30s per rank (up to 2 ranks), and Permafrost Bauble reduces it by another 30s." },
    S{ key="mage_alter", name="Alter Time", class="MAGE", specs=ALL_MAGE, spellID=342245, cooldown=50, reliability="reliable", optional=true },
    S{ key="arcane_surge", name="Arcane Surge", class="MAGE", specs={62}, spellID=365350, cooldown=90, category="offensive", reliability="reliable" },
    S{ key="frost_ray", name="Ray of Frost", class="MAGE", specs={64}, spellID=205021, cooldown=60, category="offensive", optional=true, reliability="experimental" },
    S{ key="fire_combust", name="Combustion", class="MAGE", specs={63}, spellID=190319, cooldown=120, category="offensive", reliability="reliable", talentCD=true },

    -- MONK
    S{ key="monk_fort", name="Fortifying Brew", class="MONK", specs={268,269,270}, spellID=115203, cooldown=120, reliability="reliable", talentCD=true },
    S{ key="ww_karma", name="Touch of Karma", class="MONK", specs=ALL_MONK_DPS, spellID=122470, cooldown=90, reliability="reliable", talentCD=true },
    S{ key="ww_xuen", name="Invoke Xuen, the White Tiger", class="MONK", specs=ALL_MONK_DPS, spellID=123904, cooldown=120, category="offensive", optional=true, reliability="experimental", noAuraLikely=true },
    S{ key="brew_celestial", name="Celestial Brew", class="MONK", specs={268}, spellID=322507, cooldown=60, reliability="experimental", recommended=true },
    S{ key="mw_cocoon", name="Life Cocoon", class="MONK", specs={270}, spellID=116849, cooldown=120, category="external", target="party", reliability="reliable" },
    S{ key="mw_revival", name="Revival", class="MONK", specs={270}, spellID=115310, cooldown=180, category="group", reliability="experimental" },
    S{ key="mw_restoral", name="Restoral", class="MONK", specs={270}, spellID=388615, cooldown=180, category="group", optional=true, reliability="experimental" },
    S{ key="mw_chiji", name="Invoke Chi-Ji, the Red Crane", class="MONK", specs={270}, spellID=325197, cooldown=180, category="group", optional=true, reliability="experimental", noAuraLikely=true },
    S{ key="mw_yulon", name="Invoke Yu'lon, the Jade Serpent", class="MONK", specs={270}, spellID=322118, cooldown=180, category="group", optional=true, reliability="experimental", noAuraLikely=true },

    -- PALADIN (12.1.5 talent-aware)
    S{ key="pal_divine_shield", name="Divine Shield", class="PALADIN", specs={65,66,70}, spellID=642, cooldown=300, activeDuration=8, reliability="reliable",
        cooldownTalentEffects={
            { ids={114154}, reducePercent=30, name="Unbreakable Spirit" },
            { ids={378425}, reducePercent=15, specs={66}, name="Uther's Counsel" },
        } },
    S{ key="pal_bop", name="Blessing of Protection / Spellwarding", class="PALADIN", specs={65,66,70}, spellIDs={1022,204018}, auraIDs={1022,204018}, talentIDs={1022,204018,384909}, cooldown=300, activeDuration=10, category="external", target="party", optional=true, reliability="reliable", talentCD=true,
        cooldownTalentEffects={
            { ids={384909}, flat=60, name="Improved Blessing of Protection" },
            { ids={378425}, reducePercent=15, specs={66}, name="Uther's Counsel" },
        }, warning="Improved Blessing of Protection removes 60s. Protection's Uther's Counsel also reduces Blessing of Protection/Spellwarding by 15%." },
    S{ key="pal_sac", name="Blessing of Sacrifice", class="PALADIN", specs={65,66,70}, spellID=6940, cooldown=120, category="external", target="party", optional=true, reliability="reliable", talentCD=true },
    S{ key="pal_freedom", name="Blessing of Freedom", class="PALADIN", specs={65,66,70}, spellIDs={1044,305395,262618,299256}, auraIDs={1044,305395,262618,299256}, talentIDs={1044}, cooldown=25, activeDuration=8, category="external", target="party", optional=true, reliability="reliable", warning="Tracks current Freedom aura variants. Most last 8s; variant 262618 lasts 3s." },

    S{ key="ret_aw", name="Avenging Wrath (Retribution)", class="PALADIN", specs={70}, spellID=31884, talentIDs={31884}, cooldown=60, activeDuration=20, category="offensive", optional=true, reliability="reliable", warning="Retribution's spec passive reduces Avenging Wrath from 120s to 60s." },
    S{ key="ret_crusade", name="Crusade (Retribution)", class="PALADIN", specs={70}, spellID=231895, talentIDs={231895}, cooldown=60, activeDuration=20, category="offensive", optional=true, reliability="reliable" },
    S{ key="holy_aw", name="Avenging Wrath (Holy)", class="PALADIN", specs={65}, spellID=31884, talentIDs={31884}, cooldown=120, activeDuration=20, category="group", optional=true, reliability="reliable",
        cooldownTalentEffects={ { ids={1241511}, perRank=15, maxRank=2, name="Call of the Righteous" } },
        activeDurationTalentEffects={ { ids={1241511}, changePerRank=-3, maxRank=2, name="Call of the Righteous" }, { ids={53376}, increasePercent=50, name="Sanctified Wrath" } } },
    S{ key="holy_avenging_crusader", name="Avenging Crusader (Holy)", class="PALADIN", specs={65}, spellID=216331, talentIDs={216331}, cooldown=60, activeDuration=15, category="group", optional=true, reliability="reliable",
        cooldownTalentEffects={ { ids={1241511}, perRank=7.5, maxRank=2, name="Call of the Righteous" } },
        activeDurationTalentEffects={ { ids={1241511}, changePerRank=-2, maxRank=2, name="Call of the Righteous" }, { ids={53376}, increasePercent=50, name="Sanctified Wrath" } } },
    S{ key="prot_aw", name="Avenging Wrath (Protection)", class="PALADIN", specs={66}, spellID=31884, talentIDs={31884}, cooldown=120, activeDuration=20, category="group", optional=true, reliability="reliable",
        cooldownTalentEffects={ { ids={204074}, reducePercent=50, name="Righteous Protector" } },
        activeDurationTalentEffects={ { ids={204074}, reducePercent=40, name="Righteous Protector" } } },
    S{ key="prot_sentinel", name="Sentinel (Protection)", class="PALADIN", specs={66}, spellID=389539, talentIDs={389539}, cooldown=120, activeDuration=20, category="group", optional=true, reliability="reliable",
        cooldownTalentEffects={ { ids={204074}, reducePercent=50, name="Righteous Protector" } },
        activeDurationTalentEffects={ { ids={204074}, reducePercent=40, name="Righteous Protector" } } },

    S{ key="holy_dp", name="Divine Protection", class="PALADIN", specs={65}, spellID=498, cooldown=60, reliability="reliable", optional=true,
        cooldownTalentEffects={ { ids={114154}, reducePercent=30, name="Unbreakable Spirit" } } },
    S{ key="ret_dp", name="Divine Protection", class="PALADIN", specs={70}, spellIDs={403876,498}, auraIDs={403876,498}, cooldown=60, reliability="reliable", optional=true,
        cooldownTalentEffects={ { ids={114154}, reducePercent=30, name="Unbreakable Spirit" } } },
    S{ key="pal_loh", name="Lay on Hands", class="PALADIN", specs={65,66,70}, spellID=633, talentIDs={633,387791}, cooldown=600, category="external", target="party", reliability="reliable",
        cooldownTalentEffects={
            { ids={114154}, reducePercent=30, name="Unbreakable Spirit" },
            { ids={378425}, reducePercent=15, specs={66}, name="Uther's Counsel" },
            { ids={414720}, reducePercent=40, specs={65}, name="Tirion's Devotion (Holy)" },
        }, warning="Empyreal Ward gives Lay on Hands a trackable target aura. Static talent reductions are applied. Action-dependent reductions such as Protection Tirion's Devotion / Retribution Healing Hands remain conservative." },
    S{ key="holy_aura_mastery", name="Aura Mastery", class="PALADIN", specs={65}, spellID=31821, talentIDs={31821,392911}, cooldown=180, activeDuration=8, category="group", optional=true, reliability="reliable",
        cooldownTalentEffects={ { ids={392911}, flat=30, name="Unwavering Spirit" } } },
    S{ key="prot_gak", name="Guardian of Ancient Kings", class="PALADIN", specs={66}, spellID=86659, cooldown=180, reliability="reliable", baseCharges=1, chargeTalentIDs={1246481}, chargeTalentAdd=1 },
    S{ key="prot_ardent", name="Ardent Defender", class="PALADIN", specs={66}, spellID=31850, cooldown=90, reliability="reliable", talentCD=true,
        cooldownTalentEffects={ { ids={114154}, reducePercent=30, name="Unbreakable Spirit" } } },
    S{ key="ret_sov", name="Shield of Vengeance", class="PALADIN", specs={70}, spellID=184662, cooldown=90, reliability="experimental", recommended=true,
        cooldownTalentEffects={ { ids={114154}, reducePercent=30, name="Unbreakable Spirit" } } },

    -- PRIEST (12.1.5 talent-aware)
    S{ key="priest_fade", name="Fade", class="PRIEST", specs=ALL_PRIEST, spellID=586, auraIDs={586,1250385,335986,114239,373447}, talentIDs={586,390670,1250378,335984,373446}, cooldown=30, activeDuration=10, optional=true, reliability="reliable",
        cooldownTalentEffects={ { ids={390670}, perRank=5, maxRank=2, name="Improved Fade" } }, warning="Tracks Fade plus Spectral Illusion/Phantasm/Translucent Image aura aliases. Improved Fade reduces cooldown by 5s per rank." },
    S{ key="priest_desperate", name="Desperate Prayer", class="PRIEST", specs=ALL_PRIEST, spellID=19236, talentIDs={19236,238100,373450}, cooldown=90, activeDuration=10, optional=true, reliability="reliable",
        cooldownTalentEffects={ { ids={238100}, flat=20, name="Angel's Mercy" } }, warning="Angel's Mercy removes 20s. Light's Inspiration changes the max-health gain, not the cooldown." },
    S{ key="shadow_dispersion", name="Dispersion", class="PRIEST", specs={258}, spellID=47585, talentIDs={47585,288733}, cooldown=120, activeDuration=6, reliability="reliable", talentCD=true,
        cooldownTalentEffects={ { ids={288733}, flat=30, name="Intangibility" } }, warning="Intangibility keeps the same Dispersion spell ID (47585) and reduces cooldown by 30s." },
    S{ key="disc_ps", name="Pain Suppression", class="PRIEST", specs={256}, spellID=33206, talentIDs={33206,373035}, cooldown=180, activeDuration=8, category="external", target="party", reliability="reliable", baseCharges=1, chargeTalentIDs={373035}, chargeTalentAdd=1, dynamicCDR=true, warning="Protector of the Frail grants a second charge. The ×2 badge is charge capacity; Power Word: Shield also reduces recharge by 3s per cast, so the timer is intentionally conservative." },
    S{ key="disc_barrier", name="Power Word: Barrier", class="PRIEST", specs={256}, spellID=62618, cooldown=180, category="group", reliability="experimental", noAuraLikely=true },
    S{ key="disc_ultimate_penitence", name="Ultimate Penitence", class="PRIEST", specs={256}, spellID=421453, talentIDs={421453}, cooldown=240, activeDuration=6.5, category="group", optional=true, reliability="reliable" },
    S{ key="holy_gs", name="Guardian Spirit", class="PRIEST", specs={257}, spellID=47788, talentIDs={47788,200209}, cooldown=180, activeDuration=10, category="external", target="party", optional=true, reliability="reliable", warning="Guardian Angel is outcome-dependent: if Guardian Spirit expires without saving the target, the remaining cooldown becomes 60s. The tracker starts conservatively at 180s." },
    S{ key="holy_hymn", name="Divine Hymn", class="PRIEST", specs={257}, spellID=64843, talentIDs={64843,419110}, cooldown=180, activeDuration=5, category="group", optional=true, reliability="reliable", talentCD=true,
        cooldownTalentEffects={ { ids={419110}, flat=60, name="Seraphic Crescendo" } } },
    S{ key="holy_apoth", name="Apotheosis", class="PRIEST", specs={257}, spellID=200183, talentIDs={200183,1215245,1215241}, cooldown=120, activeDuration=20, category="group", optional=true, reliability="reliable",
        activeDurationTalentEffects={ { ids={1215245}, change=12, name="Eternal Sanctity" } }, warning="Eternal Sanctity adds 12s. Divinity improves Apotheosis output but does not change its cooldown." },

    -- ROGUE
    S{ key="rogue_feint", name="Feint", class="ROGUE", specs=ALL_ROGUE, spellID=1966, cooldown=15, reliability="experimental" },
    S{ key="rogue_cloak", name="Cloak of Shadows", class="ROGUE", specs=ALL_ROGUE, spellID=31224, auraIDs={31224,35729}, cooldown=120, reliability="reliable", warning="Exact sensor accepts both the 5s Cloak aura (31224) and its triggered immunity aura (35729)." },
    S{ key="rogue_evasion", name="Evasion", class="ROGUE", specs=ALL_ROGUE, spellID=5277, cooldown=120, reliability="reliable", recommended=true },
    S{ key="rogue_cheat", passive=true, name="Cheat Death", class="ROGUE", specs=ALL_ROGUE, spellIDs={31230}, auraIDs={45181}, cooldown=360, category="state", optional=true, reliability="experimental", warning="Passive proc. The tracker watches the Cheated Death lockout aura, not a cast." },
    S{ key="sub_blades", name="Shadow Blades", class="ROGUE", specs={261}, spellID=121471, cooldown=90, category="offensive", reliability="reliable" },
    S{ key="assa_deathmark", name="Deathmark", class="ROGUE", specs={259}, spellID=360194, auraIDs={1249810}, cooldown=120, category="offensive", reliability="reliable", warning="Exact sensor uses Finish the Job (1249810) when present and also watches the rogue's current target for the Deathmark debuff (360194), so Negotiable Contract builds are covered too." },
    S{ key="outlaw_prep", name="Preparation", class="ROGUE", specs={260}, spellID=1277933, cooldown=240, category="offensive", optional=true, reliability="experimental", noAuraLikely=true },

    -- SHAMAN
    S{ key="sham_astral", name="Astral Shift", class="SHAMAN", specs={262,263,264}, spellID=108271, cooldown=120, reliability="reliable" },
    S{ key="sham_windveil", name="Windveil", class="SHAMAN", specs={262,263,264}, spellIDs={355630}, auraIDs={355634}, cooldown=0, category="state", optional=true, reliability="experimental", stateOnly=true, warning="Passive 12s magic DR after a successful Wind Shear; no recharge timer." },
    S{ key="ele_asc", name="Ascendance (Elemental)", class="SHAMAN", specs={262}, spellID=114050, talentIDs={114050,1219480}, cooldown=120, category="offensive", optional=true, reliability="reliable", talentCD=true },
    S{ key="enh_asc", name="Ascendance (Enhancement)", class="SHAMAN", specs={263}, spellID=114051, talentIDs={114051}, cooldown=120, category="offensive", optional=true, reliability="reliable", talentCD=true },
    S{ key="resto_slt", name="Spirit Link Totem", class="SHAMAN", specs={264}, spellID=98008, cooldown=180, category="group", reliability="experimental", noAuraLikely=true },
    S{ key="resto_ht", name="Healing Tide Totem", class="SHAMAN", specs={264}, spellID=108280, cooldown=120, category="group", reliability="experimental", noAuraLikely=true, warning="Known to be difficult/impossible to observe reliably through current party aura/event restrictions." },
    S{ key="resto_asc", name="Ascendance (Restoration)", class="SHAMAN", specs={264}, spellID=114052, talentIDs={114052}, cooldown=180, category="group", optional=true, reliability="reliable", talentCD=true },

    -- WARLOCK
    S{ key="lock_darkpact", name="Dark Pact", class="WARLOCK", specs=ALL_WARLOCK, spellID=108416, cooldown=60, optional=true, reliability="experimental" },
    S{ key="lock_ur", name="Unending Resolve", class="WARLOCK", specs=ALL_WARLOCK, spellID=104773, cooldown=180, reliability="reliable", talentCD=true },
    S{ key="aff_darkglare", name="Summon Darkglare", class="WARLOCK", specs={265}, spellID=205180, talentIDs={205180}, cooldown=120, activeDuration=20, category="offensive", optional=true, reliability="reliable",
        cooldownTalentEffects={ { ids={387084}, flat=30, name="Grand Warlock's Design" } },
        activeDurationTalentEffects={ { ids={1279521}, change=5, name="Eye Contract" } } },
    S{ key="demo_imp_lord", name="Grimoire: Imp Lord", class="WARLOCK", specs={266}, spellID=1276452, talentIDs={1276452}, cooldown=120, activeDuration=20, category="offensive", optional=true, reliability="reliable",
        activeDurationTalentEffects={ { ids={1276661}, change=3, name="Stabilized Portals" } } },

    -- WARRIOR
    S{ key="war_reflect", name="Spell Reflection", class="WARRIOR", specs={71,72,73}, spellID=23920, cooldown=25, reliability="reliable", talentCD=true },
    S{ key="arms_dbts", name="Die by the Sword", class="WARRIOR", specs={71}, spellID=118038, cooldown=120, reliability="reliable" },
    S{ key="fury_er", name="Enraged Regeneration", class="WARRIOR", specs={72}, spellID=184364, cooldown=120, reliability="reliable" },
    S{ key="prot_sw", name="Shield Wall", class="WARRIOR", specs={73}, spellID=871, cooldown=180, reliability="reliable", talentCD=true, baseCharges=1, chargeTalentIDs={397103}, chargeTalentAdd=1, chargeTalentCooldownReduction=60, dynamicCDR=true, warning="Defender's Aegis grants a second charge and -60s recharge. Other Protection Warrior CDR can make the local timer conservative." },
    S{ key="war_rally", name="Rallying Cry", class="WARRIOR", specs={71,72,73}, spellID=97462, cooldown=180, category="group", target="party", optional=true, reliability="experimental" },
    S{ key="prot_laststand", name="Last Stand", class="WARRIOR", specs={73}, spellID=12975, cooldown=180, reliability="experimental", recommended=true },
    S{ key="prot_demo", name="Demoralizing Shout", class="WARRIOR", specs={73}, spellID=1160, cooldown=45, reliability="experimental", recommended=true },

    -- SOULCOILER RITUAL VESSEL (healer trinket)
    S{ key="soulcoiler", name="Soulcoiler Ritual Vessel", class="ITEM", specs={65,105,1468,256,257,264,270}, spellID=1291894, auraIDs={1291894}, itemID=270162, cooldown=120, category="group", reliability="experimental", dynamicCDR=true, item=true, warning="Allied deaths reduce this trinket cooldown by 30s. The local timer is therefore conservative and can be too long." },
}

ns.SpellByKey = {}
ns.SpellsByClass = {}
for _, entry in ipairs(ns.Spells) do
    ns.SpellByKey[entry.key] = entry
    local bucket = entry.class
    if entry.class == "ITEM" then bucket = "ITEM" end
    ns.SpellsByClass[bucket] = ns.SpellsByClass[bucket] or {}
    table.insert(ns.SpellsByClass[bucket], entry)
end

ns.CategoryPriority = {
    defensive = 1,
    external = 2,
    group = 3,
    state = 4,
    offensive = 5,
}
