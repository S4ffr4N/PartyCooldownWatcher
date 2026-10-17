local addonName, ns = ...
local Core = ns.Core

local AI = {}
ns.AuraInference = AI

-- Midnight/12.1 party-aura tracking cannot safely identify most teammate auras by spellID.
-- The useful information Blizzard still exposes is the set of auraInstanceIDs returned by
-- server-side filters such as BIG_DEFENSIVE / EXTERNAL_DEFENSIVE / IMPORTANT.  We watch
-- those anonymous instances, then infer the spell from class/spec, filter signature and
-- observed buff duration.  This deliberately mirrors the *idea* used by current public
-- cooldown trackers without depending on secret spell identity.

local FILTERS = {
    BIG_DEFENSIVE = "HELPFUL|BIG_DEFENSIVE",
    EXTERNAL_DEFENSIVE = "HELPFUL|EXTERNAL_DEFENSIVE",
    IMPORTANT = "HELPFUL|IMPORTANT",
}

local TOLERANCE = 0.80
local CAST_WINDOW = 0.30
local DEDUPE_WINDOW = 1.0

-- Detection rules.  These are not spellID lookups.  "types" describes which of Blizzard's
-- public filtered buckets the anonymous aura is expected to appear in.  A missing key means
-- "don't care"; false means the aura must not be in that bucket.
--
-- Durations are deliberately permissive where current talents can alter them.  A rule with
-- no usable party aura is omitted here and remains UNKNOWN in the main spell database.
local RULES = {
    -- Death Knight
    dk_ibf           = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}},
    dk_ams           = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={5,7}, allowEarly=true},
    blood_drw        = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=6, maxDuration=14},
    blood_vb         = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={10,12,14}},
    frost_pillar     = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={12}, minDurationRule=true},
    frost_breath     = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=3, maxDuration=40, allowEarly=true},

    -- Demon Hunter
    dh_blur          = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={10}},
    vengeance_meta   = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=12, maxDuration=25, minDurationRule=true},

    -- Druid
    druid_bark       = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8,12}},
    guardian_si      = {types={BIG_DEFENSIVE=true, IMPORTANT=false, EXTERNAL_DEFENSIVE=false}, minDuration=4, maxDuration=8, allowEarly=true},
    guardian_incarn  = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={30}, minDurationRule=true},
    balance_incarn   = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={20}, minDurationRule=true},
    balance_ca       = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={15}, minDurationRule=true},
    feral_incarn     = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={20}, minDurationRule=true},
    feral_berserk    = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={15}, minDurationRule=true},
    druid_convoke_dps   = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=2, maxDuration=6, allowEarly=true},
    druid_convoke_resto = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=2, maxDuration=6, allowEarly=true},
    resto_ironbark   = {types={EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=false, IMPORTANT=false}, durations={12}, allowEarly=true, external=true},

    -- Evoker
    evoker_scales    = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, minDuration=10, maxDuration=15, minDurationRule=true},
    evoker_zephyr    = {types={EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=false, IMPORTANT=false}, minDuration=6, maxDuration=10, allowEarly=true, external=true},
    dev_dragonrage   = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={18}, minDurationRule=true},
    aug_boe          = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=8, maxDuration=15, minDurationRule=true},
    pres_time_dilation = {types={EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=false, IMPORTANT=false}, durations={8}, allowEarly=true, external=true},

    -- Hunter
    hunter_turtle    = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}, allowEarly=true},
    hunter_sotf      = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={6,8}, minDurationRule=true},
    mm_trueshot      = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={15,17}, minDurationRule=true},
    sv_coord         = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={20}, minDurationRule=true},

    -- Mage
    mage_iceblock    = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={6,10}, allowEarly=true},
    mage_alter       = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={10}, allowEarly=true},
    arcane_surge     = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={15}, minDurationRule=true},
    fire_combust     = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={10}, minDurationRule=true},

    -- Monk
    monk_fort        = {types={BIG_DEFENSIVE=true, IMPORTANT=false, EXTERNAL_DEFENSIVE=false}, durations={15}, minDurationRule=true},
    ww_karma         = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={10}, allowEarly=true},
    mw_cocoon        = {types={EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=false, IMPORTANT=false}, durations={12}, allowEarly=true, external=true},

    -- Paladin
    pal_divine_shield = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}, allowEarly=true},
    pal_bop          = {types={EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=false, IMPORTANT=false}, durations={10}, allowEarly=true, external=true},
    pal_sac          = {types={EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=false, IMPORTANT=false}, durations={12}, allowEarly=true, external=true},
    ret_aw           = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=15, maxDuration=30, minDurationRule=true},
    holy_aw          = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=10, maxDuration=30, minDurationRule=true},
    holy_dp          = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}},
    ret_dp           = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}},
    holy_aura_mastery = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=6, maxDuration=10, minDurationRule=true},
    prot_gak         = {types={BIG_DEFENSIVE=true, IMPORTANT=false, EXTERNAL_DEFENSIVE=false}, durations={8}},
    prot_ardent      = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}},
    ret_sov          = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={8}, allowEarly=true},

    -- Priest
    priest_desperate = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={10}},
    shadow_dispersion = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={6}, allowEarly=true},
    disc_ps          = {types={EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=false, IMPORTANT=false}, durations={8}, allowEarly=true, external=true},
    holy_gs          = {types={EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=false, IMPORTANT=false}, durations={10}, allowEarly=true, external=true},
    holy_hymn        = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={5}, allowEarly=true},
    holy_apoth       = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={20}, minDurationRule=true},

    -- Rogue
    rogue_cloak      = {types={BIG_DEFENSIVE=true, IMPORTANT=false, EXTERNAL_DEFENSIVE=false}, durations={5}, allowEarly=true},
    rogue_evasion    = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={10}, allowEarly=true},
    sub_blades       = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={16,18,20}, minDurationRule=true},

    -- Shaman
    sham_astral      = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={12}},
    ele_asc          = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={15}, minDurationRule=true},
    enh_asc          = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={15}, minDurationRule=true},
    resto_asc        = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={15}, minDurationRule=true},

    -- Warlock
    lock_darkpact    = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=15, maxDuration=22, allowEarly=true},
    lock_ur          = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}},

    -- Warrior
    war_reflect      = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, durations={5}, allowEarly=true},
    arms_dbts        = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}},
    fury_er          = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}},
    prot_sw          = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, durations={8}},
    war_rally        = {types={IMPORTANT=true, BIG_DEFENSIVE=false, EXTERNAL_DEFENSIVE=false}, minDuration=8, maxDuration=12, allowEarly=true, external=true},
    prot_laststand   = {types={BIG_DEFENSIVE=true, IMPORTANT=true, EXTERNAL_DEFENSIVE=false}, minDuration=12, maxDuration=20, minDurationRule=true},
}

local observed = {}       -- unit -> auraInstanceID -> observation
local lastCast = {}       -- unit -> time, spell identity intentionally ignored
local lastAbsorb = {}     -- unit -> time
local lastFlags = {}      -- unit -> time
local recentCommit = {}   -- unit -> key -> time
local probeInitialized = false

-- Legacy Havoc Metamorphosis fallback. v0.5 normally uses the exact AuraContainer
-- sensor in SecureSensors (162264 minus the <=10s Demonic form). This model heuristic
-- is retained only for clients where that protected-widget path is unavailable.
local modelEpisodes = {} -- unit -> {startTime, lastEvent, generation, inferred}
local MODEL_DUPLICATE_WINDOW = 1.0
local HAVOC_DEMONIC_WINDOW = 5.0
local HAVOC_INFER_AFTER = 6.15
local HAVOC_META_DURATION = 20.0

local function plain(v)
    if issecretvalue and issecretvalue(v) then return false end
    return true
end

local function safeNumber(v)
    if not plain(v) or type(v) ~= "number" then return nil end
    return v
end

local function safeBool(v)
    if not plain(v) or type(v) ~= "boolean" then return nil end
    return v
end

local function unitFriendly(unit)
    return unit and UnitExists(unit) and not UnitCanAttack("player", unit)
end

local function sig(types)
    local s = ""
    if types.BIG_DEFENSIVE then s = s .. "B" end
    if types.EXTERNAL_DEFENSIVE then s = s .. "E" end
    if types.IMPORTANT then s = s .. "I" end
    if s == "" then s = "-" end
    return s
end

local function getDuration(aura)
    if not aura then return nil end
    local ok, v = pcall(function() return aura.duration end)
    if ok then return safeNumber(v) end
    return nil
end

local function getSpellID(aura)
    if not aura then return nil end
    local ok, v = pcall(function() return aura.spellId or aura.spellID end)
    if ok then
        v = safeNumber(v)
        if v and v > 0 then return v end
    end
    return nil
end

local function addFiltered(current, unit, filterName, filter)
    if not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, filter)
    if not ok or type(auras) ~= "table" then return end
    for _, aura in ipairs(auras) do
        local id
        local okID, value = pcall(function() return aura and aura.auraInstanceID end)
        if okID and plain(value) and type(value) == "number" then id = value end
        if id then
            local info = current[id]
            if not info then
                info = {types={}}
                current[id] = info
            end
            info.types[filterName] = true
            info.duration = info.duration or getDuration(aura)
            info.spellId = info.spellId or getSpellID(aura)
        end
    end
end

function AI:BuildCurrent(unit)
    local current = {}
    addFiltered(current, unit, "BIG_DEFENSIVE", FILTERS.BIG_DEFENSIVE)
    addFiltered(current, unit, "EXTERNAL_DEFENSIVE", FILTERS.EXTERNAL_DEFENSIVE)
    addFiltered(current, unit, "IMPORTANT", FILTERS.IMPORTANT)
    return current
end

local function typesMatch(rule, types)
    if not rule or not rule.types then return false end
    for k, expected in pairs(rule.types) do
        if expected == true and not types[k] then return false end
        if expected == false and types[k] then return false end
    end
    return true
end

local function durationMatches(rule, duration)
    if not duration or duration <= 0 then return true end -- signature-only fallback
    if rule.durations then
        for _, expected in ipairs(rule.durations) do
            if rule.allowEarly then
                if duration <= expected + TOLERANCE and duration >= 0.5 then return true end
            elseif rule.minDurationRule then
                if duration >= expected - TOLERANCE then return true end
            elseif math.abs(duration - expected) <= TOLERANCE then
                return true
            end
        end
        return false
    end
    if rule.minDuration and duration < rule.minDuration - TOLERANCE then return false end
    if rule.maxDuration and duration > rule.maxDuration + TOLERANCE then return false end
    return true
end

local function evidenceScore(unit, startTime)
    local score = 0
    if lastCast[unit] and math.abs(lastCast[unit] - startTime) <= CAST_WINDOW then score = score + 4 end
    if lastAbsorb[unit] and math.abs(lastAbsorb[unit] - startTime) <= CAST_WINDOW then score = score + 1 end
    if lastFlags[unit] and math.abs(lastFlags[unit] - startTime) <= CAST_WINDOW then score = score + 1 end
    return score
end

local function candidateUnitsForObservation(observedUnit, entry, rule)
    if not rule.external and entry.target ~= "party" then
        return {observedUnit}
    end
    local result = {}
    for _, unit in ipairs(Core:GetTrackedUnits()) do
        if Core:ShouldShow(entry, unit, true) then result[#result+1] = unit end
    end
    return result
end

local function entryHasSpellID(entry, spellId)
    if not spellId then return false end
    for _, id in ipairs(entry.spellIDs or {}) do if id == spellId then return true end end
    for _, id in ipairs(entry.auraIDs or {}) do if id == spellId then return true end end
    return false
end

local function buildCandidates(observedUnit, obs, duration)
    local candidates = {}
    local directID = obs.spellId

    -- Fast path: some filtered AuraData exposes a normal (non-secret) spellId even though
    -- generic party aura identity is restricted. When Blizzard gives us that ID, trust it
    -- over our hand-written category fingerprint. This especially helps specs whose flags
    -- changed between patches.
    if directID then
        for key, rule in pairs(RULES) do
            local entry = ns.SpellByKey[key]
            if entry and not (ns.SecureSensors and ns.SecureSensors:Supports(entry)) and entryHasSpellID(entry, directID) then
                for _, caster in ipairs(candidateUnitsForObservation(observedUnit, entry, rule)) do
                    if Core:ShouldShow(entry, caster, true) then
                        candidates[#candidates+1] = {
                            entry = entry,
                            caster = caster,
                            rule = rule,
                            score = 100 + evidenceScore(caster, obs.startTime),
                            direct = true,
                        }
                    end
                end
            end
        end
        if #candidates > 0 then return candidates end
    end

    for key, rule in pairs(RULES) do
        local entry = ns.SpellByKey[key]
        if entry and not (ns.SecureSensors and ns.SecureSensors:Supports(entry)) and typesMatch(rule, obs.types) and durationMatches(rule, duration) then
            for _, caster in ipairs(candidateUnitsForObservation(observedUnit, entry, rule)) do
                if Core:ShouldShow(entry, caster, true) then
                    candidates[#candidates+1] = {
                        entry = entry,
                        caster = caster,
                        rule = rule,
                        score = evidenceScore(caster, obs.startTime),
                    }
                end
            end
        end
    end
    return candidates
end

local function chooseCandidate(observedUnit, obs, duration)
    local candidates = buildCandidates(observedUnit, obs, duration)
    if #candidates == 0 then return nil end

    -- Prefer a cast-evidence owner.  This is especially useful for externals when two members
    -- could own the same spell.  We never read the secret spellID argument from the cast event.
    table.sort(candidates, function(a,b) return a.score > b.score end)
    if #candidates == 1 then return candidates[1] end
    if candidates[1].score > candidates[2].score then return candidates[1] end

    -- If all remaining candidates point to the same exact spell/caster, the ambiguity is fake.
    local first = candidates[1]
    local same = true
    for i=2,#candidates do
        if candidates[i].entry.key ~= first.entry.key or candidates[i].caster ~= first.caster then
            same = false
            break
        end
    end
    if same then return first end

    return nil
end

local function visualDuration(rule, measured)
    if type(measured) == "number" and measured > 0 then return measured end
    if rule and rule.durations and #rule.durations == 1 then return rule.durations[1] end
    if rule and rule.minDuration and rule.maxDuration and math.abs(rule.maxDuration - rule.minDuration) < 0.1 then
        return rule.minDuration
    end
    return nil
end

local function markActive(unit, entry, active)
    local st = Core.StateFor(unit, entry.key)
    st.active = active == true
    if not st.active then
        st.activeStart = 0
        st.activeUntil = 0
    end
    if ns.UI then ns.UI:RefreshUnit(unit) end
end

local function commit(observedUnit, auraID, obs, duration, phase)
    if obs.resolved then return true end
    local candidate = chooseCandidate(observedUnit, obs, duration)
    if not candidate then return false end

    recentCommit[candidate.caster] = recentCommit[candidate.caster] or {}
    local previous = recentCommit[candidate.caster][candidate.entry.key]
    local now = GetTime()
    if not previous or now - previous > DEDUPE_WINDOW then
        local st = Core.StateFor(candidate.caster, candidate.entry.key)
        if st.exactCastAt and now - st.exactCastAt < 2 then
            obs.resolved = true
            obs.caster = candidate.caster
            recentCommit[candidate.caster][candidate.entry.key] = now
            return true
        end
        Core:StartCooldown(candidate.caster, candidate.entry, "filtered-"..(phase or "aura"), visualDuration(candidate.rule, duration), phase)
        recentCommit[candidate.caster][candidate.entry.key] = now
    else
        markActive(candidate.caster, candidate.entry, true)
    end

    obs.resolved = true
    obs.caster = candidate.caster
    obs.entryKey = candidate.entry.key
    obs.entry = candidate.entry

    if PartyCDLensDB and PartyCDLensDB.debug then
        Core.Debug("infer", observedUnit, "aura#"..tostring(auraID), sig(obs.types), string.format("dur=%.2f", duration or -1), obs.spellId and ("spell="..tostring(obs.spellId)) or "spell=?", "=>", candidate.entry.name, "owner", candidate.caster)
    end
    return true
end

local function probeLine(prefix, unit, id, info, measured)
    if not PartyCDLensDB or not PartyCDLensDB.debug then return end
    local d = measured or info.duration
    local ds = d and string.format("%.2f", d) or "?"
    Core.Debug("probe", prefix, unit, "aura#"..tostring(id), "sig="..sig(info.types), "dur="..ds, info.spellId and ("spell="..tostring(info.spellId)) or "spell=?")
end

function AI:ScanUnit(unit)
    if not unitFriendly(unit) then return end
    observed[unit] = observed[unit] or {}
    local tracked = observed[unit]
    local current = self:BuildCurrent(unit)
    local now = GetTime()

    -- New anonymous aura instances.
    for id, info in pairs(current) do
        if not tracked[id] then
            local obs = {
                startTime = now,
                types = info.types,
                apiDuration = info.duration,
                spellId = info.spellId,
            }
            tracked[id] = obs
            probeLine("+", unit, id, info)
            -- Try immediately. If duration is hidden, class/spec + bucket signature (or a
            -- non-secret spellId fast path) can still safely resolve unique cases such as Blur.
            commit(unit, id, obs, info.duration, "start")
        else
            -- Merge filter membership; an instance can appear in more than one bucket.
            for k,v in pairs(info.types) do if v then tracked[id].types[k] = true end end
            tracked[id].apiDuration = tracked[id].apiDuration or info.duration
            tracked[id].spellId = tracked[id].spellId or info.spellId
        end
    end

    -- Removed instances: measured lifetime is non-secret because *we* measured it locally.
    for id, obs in pairs(tracked) do
        if not current[id] then
            local measured = math.max(0, now - obs.startTime)
            probeLine("-", unit, id, {types=obs.types, duration=obs.apiDuration, spellId=obs.spellId}, measured)
            if not obs.resolved then commit(unit, id, obs, measured, "end") end
            if obs.resolved and obs.entry and obs.caster then
                markActive(obs.caster, obs.entry, false)
            end
            tracked[id] = nil
        end
    end
end

function AI:ScanAll()
    -- Scan the player too, because a party member can cast an external on the healer/player.
    if UnitExists("player") then self:ScanUnit("player") end
    for _, unit in ipairs(Core:GetTrackedUnits()) do self:ScanUnit(unit) end
end

local function unitInCombatSafe(unit)
    local ok, v = Core.SafeCall(UnitAffectingCombat, unit)
    if not ok or Core.IsSecret(v) or type(v) ~= "boolean" then return false end
    return v
end

local function modelInferenceAllowed(unit)
    -- In a real key this is always allowed. Outside a key, limit it to combat unless
    -- debug is enabled so mounts/toys do not look like a 20-second Metamorphosis.
    if Core:IsChallengeActive() then return true end
    if unitInCombatSafe(unit) then return true end
    return PartyCDLensDB and PartyCDLensDB.debug == true
end

local function isHavocMetaCandidate(unit)
    if not unitFriendly(unit) then return false end
    local meta = Core:GetMeta(unit)
    local entry = ns.SpellByKey and ns.SpellByKey.havoc_meta
    if not meta or not entry then return false end
    if meta.class ~= "DEMONHUNTER" or meta.specID ~= 577 then return false end
    return Core:ShouldShow(entry, unit, true)
end

local function endModelActive(unit)
    local entry = ns.SpellByKey and ns.SpellByKey.havoc_meta
    if not entry then return end
    local st = Core.StateFor(unit, entry.key)
    if st.active then
        st.active = false
        st.activeStart = 0
        st.activeUntil = 0
        if ns.UI then ns.UI:RefreshUnit(unit) end
    end
end

function AI:OnModelChanged(unit)
    local entry = ns.SpellByKey and ns.SpellByKey.havoc_meta
    if entry and ns.SecureSensors and ns.SecureSensors:Supports(entry) then return end
    if not isHavocMetaCandidate(unit) or not modelInferenceAllowed(unit) then return end

    local now = GetTime()
    local ep = modelEpisodes[unit]
    if not ep then
        local gen = now
        ep = {startTime=now, lastEvent=now, generation=gen, inferred=false}
        modelEpisodes[unit] = ep
        Core.Debug("model", unit, "Havoc form candidate started")

        C_Timer.After(HAVOC_INFER_AFTER, function()
            local cur = modelEpisodes[unit]
            if not cur or cur.generation ~= gen or cur.inferred then return end
            -- A short Demonic episode should have produced a reversion model event by now.
            -- No reversion => best evidence available that the long 20s Meta form is active.
            if GetTime() - cur.startTime >= HAVOC_INFER_AFTER - 0.05 then
                local entry = ns.SpellByKey and ns.SpellByKey.havoc_meta
                if entry and isHavocMetaCandidate(unit) then
                    cur.inferred = true
                    Core:StartCooldown(unit, entry, "model-persist", HAVOC_META_DURATION, "start", cur.startTime)
                    Core.Debug("model", unit, "=> inferred Havoc Metamorphosis after", string.format("%.1fs", GetTime()-cur.startTime))
                end
            end
        end)
        return
    end

    local elapsed = now - ep.startTime
    ep.lastEvent = now

    -- Model transitions can occasionally emit more than one event during the same visual
    -- swap. Ignore very fast duplicates rather than treating them as the form ending.
    if elapsed <= MODEL_DUPLICATE_WINDOW then
        Core.Debug("model", unit, "duplicate transition ignored", string.format("%.2fs", elapsed))
        return
    end

    if not ep.inferred then
        -- A return to the normal model around the 5s mark is the expected Eye Beam/Demonic
        -- pattern, not the 2-minute Metamorphosis cooldown.
        if elapsed <= HAVOC_INFER_AFTER + 0.35 then
            Core.Debug("model", unit, "short form ended", string.format("%.1fs", elapsed), "(Demonic; ignored)")
            modelEpisodes[unit] = nil
            return
        end

        -- Edge case: scheduler delay meant we saw the reversion before the delayed inference
        -- callback. If it lasted well beyond Demonic, still count it as full Meta.
        local entry = ns.SpellByKey and ns.SpellByKey.havoc_meta
        if entry then
            ep.inferred = true
            Core:StartCooldown(unit, entry, "model-long-end", math.min(elapsed, HAVOC_META_DURATION), "end", ep.startTime)
            Core.Debug("model", unit, "=> inferred Havoc Metamorphosis from long form", string.format("%.1fs", elapsed))
        end
        modelEpisodes[unit] = nil
        return
    end

    -- Full Meta was already inferred and the model changed again: stop the active glow.
    Core.Debug("model", unit, "Havoc form ended", string.format("%.1fs", elapsed))
    endModelActive(unit)
    modelEpisodes[unit] = nil
end

function AI:OnUnitSpellcast(unit)
    if unitFriendly(unit) then lastCast[unit] = GetTime() end
end

function AI:OnAbsorbChanged(unit)
    if unitFriendly(unit) then lastAbsorb[unit] = GetTime() end
end

function AI:OnFlagsChanged(unit)
    if unitFriendly(unit) then lastFlags[unit] = GetTime() end
end

function AI:OnAuraEvent(unit)
    if unitFriendly(unit) then self:ScanUnit(unit) end
end

function AI:Reset()
    wipe(observed)
    wipe(recentCommit)
    wipe(modelEpisodes)
    probeInitialized = true
    local now = GetTime()
    local units = {"player"}
    for _, unit in ipairs(Core:GetTrackedUnits()) do units[#units+1] = unit end
    for _, unit in ipairs(units) do
        if unitFriendly(unit) then
            local current = self:BuildCurrent(unit)
            observed[unit] = {}
            for id, info in pairs(current) do
                -- Baseline only: do not pretend an aura that was already present when we
                -- initialized was freshly cast.  Once it disappears, it is simply forgotten.
                observed[unit][id] = {
                    startTime = now,
                    types = info.types,
                    apiDuration = info.duration,
                    spellId = info.spellId,
                    resolved = true,
                    baseline = true,
                }
            end
        end
    end
end

function AI:PrintCoverage()
    local counts = {sensor=0, inference=0, cast=0, unsupported=0}
    for _, entry in ipairs(ns.Spells) do
        local path
        if ns.SecureSensors and ns.SecureSensors:Supports(entry) then path="sensor"
        elseif RULES[entry.key] or entry.modelInference then path="inference"
        elseif not entry.passive and not entry.stateOnly and #entry.spellIDs > 0 then path="cast"
        else path="unsupported" end
        counts[path] = counts[path] + 1
        if path == "unsupported" then print("No detection:", entry.name) end
    end
    print(string.format("PartyCDLens paths: %d sensors, %d inference, %d readable-cast only, %d unsupported. Paths are not proof of in-game reliability; hidden cast IDs cannot be tracked.", counts.sensor, counts.inference, counts.cast, counts.unsupported))
end

AI.RULES = RULES
