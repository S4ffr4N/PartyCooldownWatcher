-- Standalone regression suite: run from the addon directory with Lua 5.1+.
local ns = {}
local now = 100
function GetTime() return now end
function GetServerTime() return 100000 + now end
function GetUnitName(unit) return unit end
function UnitExists(unit) return unit == 'party1' end
function UnitGUID(unit) return unit end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function CreateFrame() return {SetScript=function() end, RegisterEvent=function() end} end
function GetSpellBaseCooldown() return 25000 end
C_Timer = {After=function() end}
PartyCDLensDB = {spellMode={},showExperimental=true,showOffensives=true,showRecommendedExtras=true,cache={}}
PartyCDLensState = {players={}}
assert(loadfile('Database.lua'))('test', ns)
assert(loadfile('Core.lua'))('test', ns)
local core = ns.Core
local function setup(class, spec)
    core.runtime.state = {}
    core.runtime.units.party1 = {name='party1',class=class,specID=spec,talentsKnown=true,talents={},talentRanks={}}
end
local function state(key) return core.StateFor('party1', key) end
setup('HUNTER',253)
core:OnTrackedSpellcast('party1',109304)
assert(state('hunter_exhil').status == 'cooldown')
assert(state('hunter_exhil').readyAt == 220)
assert(not state('hunter_exhil').active)
core:OnTrackedSpellcast('player',109304)
core:OnTrackedSpellcast('raid1',109304)
assert(core.runtime.state.player == nil and core.runtime.state.raid1 == nil)
setup('ROGUE',259)
core:OnTrackedSpellcast('party1',31230)
assert(state('rogue_cheat').status == 'unknown', 'passive talent is not a cast')
setup('MAGE',62)
core:OnTrackedSpellcast('party1',235450)
assert(state('mage_prismatic').readyAt == 125, 'base cooldown comes from client')
assert(state('mage_blazing').status == 'unknown', 'wrong spec excluded')
setup('DEMONHUNTER',581)
local meta=core.runtime.units.party1
meta.talents[389732]=true
core:OnTrackedSpellcast('party1',204021)
assert(#state('vengeance_brand').chargeReadyAts == 1)
core:OnTrackedSpellcast('party1',204021)
assert(#state('vengeance_brand').chargeReadyAts == 1, 'duplicate observation must not spend charge twice')
now=110
core:OnTrackedSpellcast('party1',204021)
assert(#state('vengeance_brand').chargeReadyAts == 2)
setup('MAGE',62)
issecretvalue=function(v) return v == 235450 end
core:OnTrackedSpellcast('party1',235450)
assert(state('mage_prismatic').status == 'unknown', 'secret IDs ignored')
issecretvalue=nil
GetSpellBaseCooldown=function() return 0 end
core:OnTrackedSpellcast('party1',235450)
assert(state('mage_prismatic').status == 'unknown', 'missing base data must not invent duration')
setup('WARRIOR',71)
core:OnTrackedSpellcast('party1',1234768)
assert(state('health_potion').readyAt == now+300 and not state('health_potion').active)
print('Cooldown regression checks passed')
-- Every specialization in the supported catalogue has at least one personal
-- defensive that can be dispatched through the readable-event fallback.
GetSpellBaseCooldown=function() return 25000 end
-- Explicit 12.1.5 roster: count-only checks can miss an omitted spec replaced
-- by an incorrect ID. Include Devourer (1480), the third Demon Hunter spec.
local expectedSpecs = {
    DEATHKNIGHT={250,251,252}, DEMONHUNTER={577,581,1480},
    DRUID={102,103,104,105}, EVOKER={1467,1468,1473},
    HUNTER={253,254,255}, MAGE={62,63,64}, MONK={268,269,270},
    PALADIN={65,66,70}, PRIEST={256,257,258}, ROGUE={259,260,261},
    SHAMAN={262,263,264}, WARLOCK={265,266,267}, WARRIOR={71,72,73},
}
local expectedClassForSpec = {}
local classCount = 0
for class, specs in pairs(expectedSpecs) do
    classCount = classCount + 1
    assert(ns.ClassNames[class], 'missing class '..class)
    for _, spec in ipairs(specs) do
        assert(ns.SpecNames[spec], 'missing 12.1.5 spec '..spec)
        expectedClassForSpec[spec] = class
    end
end
assert(classCount == 13 and #ns.ClassOrder == 13)
local seenClasses = {}
for _, class in ipairs(ns.ClassOrder) do
    assert(expectedSpecs[class] and not seenClasses[class], 'unexpected/duplicate class '..class)
    seenClasses[class] = true
end
for _, entry in ipairs(ns.Spells) do
    if entry.class ~= 'ITEM' then
        assert(expectedSpecs[entry.class], 'unknown class on '..entry.key)
        for _, spec in ipairs(entry.specs or {}) do
            assert(expectedClassForSpec[spec] == entry.class, 'wrong class/spec mapping on '..entry.key)
        end
    end
end
local specCount=0
for spec in pairs(ns.SpecNames) do
    assert(expectedClassForSpec[spec], "unexpected specialization "..spec)
    local found
    for _, entry in ipairs(ns.Spells) do
        if entry.class ~= 'ITEM' and entry.category == 'defensive' and not entry.passive then
            for _, supportedSpec in ipairs(entry.specs or {}) do
                if supportedSpec == spec then
                    setup(entry.class,spec)
                    for _, id in ipairs(entry.talentIDs or entry.spellIDs) do
                        core.runtime.units.party1.talents[id]=true
                    end
                    core:OnTrackedSpellcast('party1',entry.spellIDs[1])
                    assert(state(entry.key).proven, 'defensive cast not tracked for spec '..spec)
                    found=true
                    break
                end
            end
        end
        if found then break end
    end
    assert(found, 'no baseline defensive for spec '..spec)
    specCount=specCount+1
end
assert(specCount==40, 'specialization catalogue changed; review coverage')
print('All '..specCount..' specialization baseline checks passed')
