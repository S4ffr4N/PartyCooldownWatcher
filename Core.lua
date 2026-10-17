local addonName, ns = ...

local Core = {}
ns.Core = Core

local defaults = {
    iconSize = 24,
    spacing = 2,
    offsetX = -4,
    offsetY = 0,
    showOffensives = true,
    showExperimental = true,
    showRecommendedExtras = false,
    debug = false,
    spellMode = {}, -- AUTO / ON / OFF
    cache = {},     -- name -> {class, specID, talents={}, items={}}
}

local runtime = {
    units = {},               -- party1..party4 metadata
    state = {},               -- unit -> key -> {status, readyAt, active, proven}
    dirty = true,
    lastScan = 0,
    inspectQueue = {},
    inspectUnit = nil,
    inspectPending = false,
    challengeStartedThisSession = false,
    activeChallengeAtLogin = false,
    testMode = false,
}
Core.runtime = runtime

local eventFrame = CreateFrame("Frame")
Core.eventFrame = eventFrame

local function deepcopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = deepcopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function isSecret(v)
    return issecretvalue and issecretvalue(v)
end
Core.IsSecret = isSecret

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return false, nil end
    return true, a, b, c, d
end
Core.SafeCall = safeCall

local function debugPrint(...)
    if PartyCDLensDB and PartyCDLensDB.debug then
        print("|cff69ccf0PartyCDLens:|r", ...)
    end
end
Core.Debug = debugPrint

local function challengeActive()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and not isSecret(active) then return active == true end
    end
    return false
end
Core.IsChallengeActive = challengeActive

local function unitNameSafe(unit)
    local ok, name = safeCall(GetUnitName, unit, true)
    if not ok or isSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

local function unitClassSafe(unit)
    local ok, _, class = safeCall(UnitClass, unit)
    if not ok or isSecret(class) or type(class) ~= "string" then return nil end
    return class
end

local function unitGUIDSafe(unit)
    local ok, guid = safeCall(UnitGUID, unit)
    if not ok or isSecret(guid) or type(guid) ~= "string" then return nil end
    return guid
end

local function specMatches(entry, specID)
    if not entry.specs then return true end
    if not specID then return false end
    for _, id in ipairs(entry.specs) do
        if id == specID then return true end
    end
    return false
end

local function classMatches(entry, class)
    if entry.class == "ITEM" then return true end
    return entry.class == class
end

local function arrayContains(t, value)
    if not t then return false end
    for _, v in ipairs(t) do
        if v == value then return true end
    end
    return false
end

local function hasSelectedTalent(meta, entry)
    if not entry.optional then return true end
    if not meta or type(meta.talents) ~= "table" then return false end
    local ids = entry.talentIDs or entry.spellIDs
    if not ids then return false end
    for _, id in ipairs(ids) do
        if meta.talents[id] then return true end
    end
    return false
end

local function hasSoulcoiler(meta)
    if not meta or type(meta.items) ~= "table" then return false end
    return meta.items[270162] == true
end

function Core:GetSpellMode(key)
    local mode = PartyCDLensDB and PartyCDLensDB.spellMode and PartyCDLensDB.spellMode[key]
    if mode ~= "ON" and mode ~= "OFF" then return "AUTO" end
    return mode
end

function Core:SetSpellMode(key, mode)
    if mode ~= "AUTO" and mode ~= "ON" and mode ~= "OFF" then return end
    PartyCDLensDB.spellMode[key] = mode == "AUTO" and nil or mode
    self:RebuildAll()
end

function Core:GetMeta(unit)
    return runtime.units[unit]
end

function Core:GetCachedMeta(name)
    if not name then return nil end
    return PartyCDLensDB.cache[name]
end

function Core:ShouldShow(entry, unit, forInference)
    local mode = self:GetSpellMode(entry.key)
    if mode == "OFF" then return false end

    local meta = runtime.units[unit]
    if not meta then return false end

    if entry.consumable then
        return mode == "ON" or PartyCDLensDB.showExperimental
    end

    if entry.item then
        if mode == "ON" then return true end
        return hasSoulcoiler(meta)
    end

    if not classMatches(entry, meta.class) then return false end
    if entry.specs then
        -- ON can force an icon when the spec is still unknown, but never onto a known
        -- mismatched spec. This keeps per-spec opt-ins (such as Shaman Ascendance) sane.
        if meta.specID and not specMatches(entry, meta.specID) then return false end
        if not meta.specID and mode ~= "ON" then return false end
    end

    if entry.category == "offensive" and not PartyCDLensDB.showOffensives and mode ~= "ON" then
        return false
    end

    if entry.recommended and not PartyCDLensDB.showRecommendedExtras and mode ~= "ON" then
        return false
    end

    if entry.reliability == "experimental" and not PartyCDLensDB.showExperimental and mode ~= "ON" then
        return false
    end

    if entry.optional and mode == "AUTO" then
        -- Fail closed when we know the inspected talent build. If inspect data is missing,
        -- the spell remains hidden rather than inventing a button the player may not have.
        if type(meta.talents) == "table" and meta.talentsKnown then
            if not hasSelectedTalent(meta, entry) then return false end
        elseif not forInference then
            return false
        end
    end

    return true
end

function Core:GetTrackedUnits()
    local t = {}
    for i = 1, 4 do
        local unit = "party"..i
        if UnitExists(unit) then table.insert(t, unit) end
    end
    return t
end

function Core:GetAuraTargets()
    local t = {"player"}
    for i = 1, 4 do
        local unit = "party"..i
        if UnitExists(unit) then table.insert(t, unit) end
    end
    return t
end

local function stateFor(unit, key)
    runtime.state[unit] = runtime.state[unit] or {}
    runtime.state[unit][key] = runtime.state[unit][key] or {
        status = "unknown",
        readyAt = 0,
        active = false,
        activeStart = 0,
        activeUntil = 0,
        proven = false,
        maxCharges = 1,
        charges = nil,
        chargeReadyAts = {},
    }
    local st = runtime.state[unit][key]
    st.chargeReadyAts = st.chargeReadyAts or {}
    st.activeStart = st.activeStart or 0
    st.activeUntil = st.activeUntil or 0
    st.maxCharges = st.maxCharges or 1
    return st
end
Core.StateFor = stateFor

local function selectedTalent(unit, ids)
    if not ids then return false, false end
    local meta = runtime.units[unit]
    if not meta or not meta.talentsKnown or type(meta.talents) ~= "table" then
        return false, false
    end
    for _, id in ipairs(ids) do
        if meta.talents[id] then return true, true end
    end
    return false, true
end

local function selectedTalentRank(unit, ids)
    if not ids then return 0, false end
    local meta = runtime.units[unit]
    if not meta or not meta.talentsKnown or type(meta.talents) ~= "table" then
        return 0, false
    end
    local best = 0
    local ranks = type(meta.talentRanks) == "table" and meta.talentRanks or nil
    for _, id in ipairs(ids) do
        if ranks and type(ranks[id]) == "number" then
            best = math.max(best, ranks[id])
        elseif meta.talents[id] then
            -- Backward-compatible cache fallback: if we know the talent is selected but
            -- do not yet have rank data, count it as one rank until the next inspect.
            best = math.max(best, 1)
        end
    end
    return best, true
end

function Core:HasDetectionPath(entry)
    if not entry then return false end
    if not entry.passive and not entry.stateOnly and #entry.spellIDs > 0 then return true end
    if ns.SecureSensors and ns.SecureSensors:Supports(entry) then return true end
    if ns.AuraInference and ns.AuraInference.RULES and ns.AuraInference.RULES[entry.key] then
        return true
    end
    if entry.modelInference then return true end
    return false
end

function Core:GetMaxCharges(entry, unit)
    local maxCharges = entry.baseCharges or 1
    if entry.chargeTalentIDs then
        local selected = selectedTalent(unit, entry.chargeTalentIDs)
        if selected then
            maxCharges = maxCharges + (entry.chargeTalentAdd or 1)
        end
    end
    return math.max(1, maxCharges)
end

local function talentEffectApplies(unit, effect)
    if not effect then return false end
    local meta = runtime.units[unit]
    local spec = meta and meta.specID
    if effect.spec and spec ~= effect.spec then return false end
    if type(effect.specs) == "table" then
        if not spec then return false end
        local found = false
        for _, id in ipairs(effect.specs) do
            if id == spec then found = true break end
        end
        if not found then return false end
    end
    return true
end

function Core:GetCooldownSeconds(entry, unit)
    if entry.stateOnly then return 0 end
    local cd = entry.cooldown or 0
    if cd <= 0 then
        local id = entry.spellIDs and entry.spellIDs[1]
        if id and GetSpellBaseCooldown then
            local ok, ms = safeCall(GetSpellBaseCooldown, id)
            if ok and not isSecret(ms) and type(ms) == "number" and ms > 0 then
                cd = ms / 1000
            end
        end
    end

    if cd > 0 and entry.chargeTalentIDs and entry.chargeTalentCooldownReduction then
        local selected = selectedTalent(unit, entry.chargeTalentIDs)
        if selected then cd = math.max(1, cd - entry.chargeTalentCooldownReduction) end
    end

    -- Static inspectable cooldown modifiers. Flat reductions are applied first and
    -- percentage reductions are accumulated against the resulting cooldown. This mirrors
    -- the common Blizzard spell-mod pattern and, importantly, never fabricates action-
    -- dependent CDR that cannot be reconstructed for another party member.
    if cd > 0 and type(entry.cooldownTalentEffects) == "table" then
        local flatTotal, pctTotal = 0, 0
        for _, effect in ipairs(entry.cooldownTalentEffects) do
            if talentEffectApplies(unit, effect) then
                local rank = selectedTalentRank(unit, effect.ids)
                if effect.maxRank and rank > effect.maxRank then rank = effect.maxRank end
                if rank > 0 then
                    flatTotal = flatTotal + (tonumber(effect.flat) or 0) + (tonumber(effect.perRank) or 0) * rank
                    pctTotal = pctTotal + (tonumber(effect.reducePercent) or 0)
                        + (tonumber(effect.reducePercentPerRank) or 0) * rank
                end
            end
        end
        cd = math.max(1, cd - flatTotal)
        if pctTotal ~= 0 then cd = math.max(1, cd * math.max(0, 1 - pctTotal / 100)) end
    end
    return cd
end

-- Even a known base duration is only an estimate when inspection or dynamic
-- effects cannot establish the player's effective recharge time.
function Core:CooldownIsEstimated(entry, unit)
    local meta = self:GetMeta(unit)
    return entry.consumable or not (meta and meta.talentsKnown) or entry.talentCD or entry.dynamicCDR
        or entry.setBonusCDR or self:GetMaxCharges(entry, unit) > 1
end

function Core:GetActiveSeconds(entry, unit, fallback)
    local seconds = tonumber(entry and entry.activeDuration)
    if seconds == nil then seconds = tonumber(fallback) or 0 end
    if seconds <= 0 then return 0 end

    if type(entry.activeDurationTalentEffects) == "table" then
        local change, reducePct, increasePct = 0, 0, 0
        for _, effect in ipairs(entry.activeDurationTalentEffects) do
            if talentEffectApplies(unit, effect) then
                local rank = selectedTalentRank(unit, effect.ids)
                if effect.maxRank and rank > effect.maxRank then rank = effect.maxRank end
                if rank > 0 then
                    change = change + (tonumber(effect.change) or 0) + (tonumber(effect.changePerRank) or 0) * rank
                    reducePct = reducePct + (tonumber(effect.reducePercent) or 0)
                        + (tonumber(effect.reducePercentPerRank) or 0) * rank
                    increasePct = increasePct + (tonumber(effect.increasePercent) or 0)
                        + (tonumber(effect.increasePercentPerRank) or 0) * rank
                end
            end
        end
        seconds = math.max(0, seconds + change)
        local scale = 1 - reducePct / 100 + increasePct / 100
        seconds = math.max(0, seconds * math.max(0, scale))
    end
    return seconds
end

local function playerKeyForUnit(unit)
    local meta = runtime.units[unit]
    if meta and meta.name then return meta.name end
    return unitNameSafe(unit)
end

local function trimMaturedCharges(st, now)
    local changed = false
    while #st.chargeReadyAts > 0 and st.chargeReadyAts[1] <= now do
        table.remove(st.chargeReadyAts, 1)
        changed = true
    end
    return changed
end

function Core:UpdateChargeState(unit, entry, st)
    st = st or stateFor(unit, entry.key)
    local now = GetTime()
    local changed = trimMaturedCharges(st, now)
    local maxCharges = self:GetMaxCharges(entry, unit)
    if st.maxCharges ~= maxCharges then changed = true end
    st.maxCharges = maxCharges

    while #st.chargeReadyAts > maxCharges do
        table.remove(st.chargeReadyAts)
        changed = true
    end

    st.charges = math.max(0, maxCharges - #st.chargeReadyAts)
    if st.status ~= "unknown" or st.proven then
        if st.charges > 0 then
            st.status = "ready"
            st.readyAt = 0
        else
            st.status = "cooldown"
            st.readyAt = st.chargeReadyAts[1] or 0
        end
    end
    return changed
end

function Core:PersistState(unit, entry, st)
    PartyCDLensState.players = PartyCDLensState.players or {}
    local playerKey = playerKeyForUnit(unit)
    if not playerKey then return end
    PartyCDLensState.players[playerKey] = PartyCDLensState.players[playerKey] or {}

    local maxCharges = self:GetMaxCharges(entry, unit)
    if maxCharges > 1 then
        local saved = { chargeReadyServers = {}, maxCharges = maxCharges }
        local now = GetTime()
        local server = GetServerTime()
        for _, readyAt in ipairs(st.chargeReadyAts or {}) do
            if readyAt > now then
                saved.chargeReadyServers[#saved.chargeReadyServers+1] = server + math.ceil(readyAt - now)
            end
        end
        if #saved.chargeReadyServers > 0 then
            PartyCDLensState.players[playerKey][entry.key] = saved
        else
            PartyCDLensState.players[playerKey][entry.key] = nil
        end
    else
        if st.readyAt and st.readyAt > GetTime() then
            PartyCDLensState.players[playerKey][entry.key] = GetServerTime() + math.ceil(st.readyAt - GetTime())
        else
            PartyCDLensState.players[playerKey][entry.key] = nil
        end
    end
end

-- Backwards-compatible wrapper retained for old internal callers/saved-state migrations.
function Core:PersistCooldown(unit, entry, remaining)
    local st = stateFor(unit, entry.key)
    if remaining and remaining > 0 then
        st.readyAt = GetTime() + remaining
    else
        st.readyAt = 0
        wipe(st.chargeReadyAts)
    end
    self:PersistState(unit, entry, st)
end

function Core:StartCooldown(unit, entry, reason, activeDuration, phase, usedAtOverride)
    if not unit or not entry then return end
    local st = stateFor(unit, entry.key)
    local now = GetTime()
    st.lastDetectionAt = now
    local duration = type(activeDuration) == "number" and activeDuration > 0 and activeDuration or nil
    local usedAt
    if type(usedAtOverride) == "number" and usedAtOverride >= 0 then
        usedAt = usedAtOverride
    else
        usedAt = (phase == "end" and duration) and math.max(0, now - duration) or now
    end

    st.proven = true
    if phase == "end" then
        st.active = false
        st.activeStart = 0
        st.activeUntil = 0
    else
        st.active = true
        st.activeStart = usedAt
        st.activeUntil = duration and (usedAt + duration) or 0
    end

    if entry.stateOnly then
        st.status = st.active and "active" or "ready"
        st.readyAt = 0
    else
        local cd = self:GetCooldownSeconds(entry, unit)
        if cd > 0 then
            local maxCharges = self:GetMaxCharges(entry, unit)
            st.maxCharges = maxCharges
            if maxCharges > 1 then
                trimMaturedCharges(st, now)

                -- If a cast is observed while our inferred queue says zero charges, the cast
                -- itself proves our local CDR model drifted. Drop the oldest predicted recharge
                -- rather than claiming an impossible negative charge.
                if #st.chargeReadyAts >= maxCharges then
                    table.remove(st.chargeReadyAts, 1)
                end

                local rechargeStart = usedAt
                local lastReady = st.chargeReadyAts[#st.chargeReadyAts]
                if lastReady and lastReady > rechargeStart then rechargeStart = lastReady end
                st.chargeReadyAts[#st.chargeReadyAts+1] = rechargeStart + cd
                table.sort(st.chargeReadyAts)
                self:UpdateChargeState(unit, entry, st)
            else
                wipe(st.chargeReadyAts)
                st.maxCharges = 1
                st.charges = 0
                st.status = "cooldown"
                st.readyAt = usedAt + cd
            end
            self:PersistState(unit, entry, st)
        else
            st.status = "unknown"
            st.readyAt = 0
        end
    end

    debugPrint("detected", entry.name, "on", playerKeyForUnit(unit) or unit, reason or "aura",
        st.maxCharges and st.maxCharges > 1 and ("charges "..tostring(st.charges).."/"..tostring(st.maxCharges)) or "")
    if ns.UI then ns.UI:RefreshUnit(unit) end
end

-- Diagnostics keep only plain text; secret values are classified, never decoded.
-- A bounded buffer and counters prevent combat chat spam and unbounded storage.
local diagnostic = {enabled=false, lines={}, total=0, hidden=0, potions=0}
local function diagnosticLine(message)
    local context = ""
    if InCombatLockdown then
        local ok, combat = safeCall(InCombatLockdown)
        if ok and not isSecret(combat) and combat then context = " combat" end
    end
    if challengeActive() then context = context.." mythic+" end
    local line = string.format("[%.1f%s] %s", GetTime(), context, message)
    table.insert(diagnostic.lines, line)
    if #diagnostic.lines > 200 then table.remove(diagnostic.lines, 1) end
end

function Core:DiagnosticCast(unit, spellID)
    if not diagnostic.enabled then return end
    local token = "hidden-unit"
    if not isSecret(unit) then
        if type(unit) ~= "string" then return end
        if unit ~= "player" and not unit:match("^party[1-4]$") then return end
        token = unit
    end
    diagnostic.total = diagnostic.total + 1
    if isSecret(spellID) then
        diagnostic.hidden = diagnostic.hidden + 1
        diagnosticLine(token.." SUCCEEDED spellID=HIDDEN (cannot identify potion)")
    elseif type(spellID) ~= "number" then
        diagnosticLine(token.." SUCCEEDED spellID=MISSING/INVALID")
    else
        local potion = ns.SpellByKey.health_potion
        local matched = false
        if potion then
            for _, id in ipairs(potion.spellIDs) do
                if id == spellID then matched = true break end
            end
        end
        local detail = ""
        if matched then
            diagnostic.potions = diagnostic.potions + 1
            if token == "player" then detail = " POTION (self; party timer intentionally excluded)"
            elseif token == "hidden-unit" then detail = " POTION (unit hidden; timer excluded)"
            elseif self:ShouldShow(potion, token, false) then detail = " POTION (eligible for timer)"
            else detail = " POTION (timer excluded: settings or missing roster metadata)" end
        end
        diagnosticLine(token.." SUCCEEDED spellID="..tostring(spellID)..detail)
    end
end

function Core:GetDiagnosticText()
    return string.format("PartyCDLens potion diagnostics: %s\nEvents=%d hiddenIDs=%d readablePotionMatches=%d\nLast %d lines; timestamps are seconds since client start.\n",
        diagnostic.enabled and "ON" or "OFF", diagnostic.total, diagnostic.hidden,
        diagnostic.potions, #diagnostic.lines)..table.concat(diagnostic.lines, "\n")
end

function Core:ShowDiagnostics()
    if not self.diagnosticWindow then
        local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(700, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
        f:SetBackdropColor(0.05,0.05,0.05,0.98)
        local title = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        title:SetPoint("TOPLEFT",12,-12)
        title:SetText("PartyCDLens diagnostics - Ctrl/Cmd+A, Ctrl/Cmd+C to copy")
        local close = CreateFrame("Button",nil,f,"UIPanelCloseButton")
        close:SetPoint("TOPRIGHT")
        local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",12,-40)
        scroll:SetPoint("BOTTOMRIGHT",-32,12)
        local edit = CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(645)
        edit:SetScript("OnEscapePressed",function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        self.diagnosticWindow = f
    end
    local f = self.diagnosticWindow
    f.edit:SetText(self:GetDiagnosticText())
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

function Core:DiagnosticCommand(action)
    if action == "on" then
        diagnostic.enabled = true
        diagnosticLine("CAPTURE START; player is a control, only party1-party4 feed timers")
        print("PartyCDLens diagnostics ON. Use /pcdl diag mark immediately before a potion, then /pcdl diag off and /pcdl diag show. Buffer is cleared by reload/logout.")
    elseif action == "off" then
        diagnosticLine("CAPTURE STOP")
        diagnostic.enabled = false
        print("PartyCDLens diagnostics OFF. /pcdl diag show opens the copyable report.")
    elseif action == "clear" then
        wipe(diagnostic.lines)
        diagnostic.total, diagnostic.hidden, diagnostic.potions = 0, 0, 0
        print("PartyCDLens diagnostic buffer cleared.")
    elseif action == "mark" then
        diagnosticLine("MARK: compare surrounding events with the observed potion use")
    elseif action == "show" then
        self:ShowDiagnostics()
    else
        print("PartyCDLens: /pcdl diag on | off | mark | show | clear")
    end
end

-- All manually cast entries have a readable-event fallback, including spells
-- without a lasting aura. Protected sensor entries keep their own authoritative
-- visual path. Never infer passive procs or compare secret spell identities.
function Core:OnTrackedSpellcast(unit, spellID)
    self:DiagnosticCast(unit, spellID)
    if isSecret(unit) or type(unit) ~= "string" or not unit:match("^party[1-4]$") then return end
    if isSecret(spellID) or type(spellID) ~= "number" then return end
    local now = GetTime()
    for _, entry in ipairs(ns.Spells) do
        if not entry.passive and not entry.stateOnly and self:ShouldShow(entry, unit, false)
            and not (ns.SecureSensors and ns.SecureSensors:Supports(entry)) then
            for _, id in ipairs(entry.spellIDs) do
                if spellID == id then
                    local st = stateFor(unit, entry.key)
                    -- An exact cast supersedes an earlier approximate aura observation.
                    -- Suppress the delayed aura edge so charges aren't spent twice.
                    st.exactCastAt = now
                    if st.lastDetectionAt and now - st.lastDetectionAt < 2 then return end
                    local duration = not entry.consumable and self:GetActiveSeconds(entry, unit) or 0
                    self:StartCooldown(unit, entry, "exact-cast", duration,
                        duration > 0 and "start" or "end")
                    break
                end
            end
        end
    end
end

function Core:RestoreUnitState(unit)
    local meta = runtime.units[unit]
    if not meta or not meta.name then return end
    local savedPlayer = PartyCDLensState.players and PartyCDLensState.players[meta.name]
    local nowServer = GetServerTime()
    local now = GetTime()

    for _, entry in ipairs(ns.Spells) do
        if self:ShouldShow(entry, unit, false) then
            local st = stateFor(unit, entry.key)
            st.active = false
            st.activeStart = 0
            st.activeUntil = 0
            st.maxCharges = self:GetMaxCharges(entry, unit)
            st.charges = nil
            wipe(st.chargeReadyAts)

            local saved = savedPlayer and savedPlayer[entry.key]
            local restored = false
            if type(saved) == "table" and type(saved.chargeReadyServers) == "table" then
                for _, serverReady in ipairs(saved.chargeReadyServers) do
                    if type(serverReady) == "number" and serverReady > nowServer then
                        st.chargeReadyAts[#st.chargeReadyAts+1] = now + (serverReady - nowServer)
                    end
                end
                table.sort(st.chargeReadyAts)
                if #st.chargeReadyAts > 0 then
                    st.proven = true
                    self:UpdateChargeState(unit, entry, st)
                    restored = true
                end
            elseif type(saved) == "number" and saved > nowServer then
                local remaining = saved - nowServer
                st.proven = true
                st.status = "cooldown"
                st.readyAt = now + remaining
                st.maxCharges = 1
                st.charges = 0
                restored = true
            end

            if not restored then
                st.status = "unknown"
                st.readyAt = 0
                st.proven = false
            end
        end
    end
end

function Core:ResetForChallengeStart()
    if ns.SecureSensors then ns.SecureSensors:ResetTimers() end
    runtime.challengeStartedThisSession = true
    PartyCDLensState.players = {}
    for _, unit in ipairs(self:GetTrackedUnits()) do
        runtime.state[unit] = runtime.state[unit] or {}
        for _, entry in ipairs(ns.Spells) do
            if self:ShouldShow(entry, unit, false) then
                local st = stateFor(unit, entry.key)
                st.active = false
                st.activeStart = 0
                st.activeUntil = 0
                st.readyAt = 0
                st.proven = false
                wipe(st.chargeReadyAts)
                st.maxCharges = self:GetMaxCharges(entry, unit)
                st.charges = st.maxCharges
                -- Reliable entries can be treated as ready after the M+ reset.
                -- Experimental entries stay ? until the observation path proves itself.
                st.status = (not entry.passive and not entry.consumable and entry.reliability == "reliable") and "ready" or "unknown"
            end
        end
        if ns.UI then ns.UI:RefreshUnit(unit) end
    end
end

-- Direct by-spell-ID aura lookup. Under 12.1 the returned AuraData may be secret,
-- but presence (table vs nil) is still usable. We intentionally never read duration,
-- expirationTime, stacks, or other secret fields here.
function Core:HasAura(unit, entry)
    if not C_UnitAuras or not C_UnitAuras.GetUnitAuraBySpellID then return false end
    for _, spellID in ipairs(entry.auraIDs or {}) do
        local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
        if ok and aura ~= nil then
            return true
        end
    end
    return false
end

function Core:FindUniqueCaster(entry)
    local found = nil
    for _, unit in ipairs(self:GetTrackedUnits()) do
        if self:ShouldShow(entry, unit, true) then
            if found then return nil end -- ambiguous: two eligible casters
            found = unit
        end
    end
    return found
end

function Core:ScanAll()
    -- 12.1.5: do NOT identify teammate auras by spellID. The inference module watches
    -- Blizzard's server-filtered anonymous auraInstanceIDs instead.
    if ns.AuraInference then ns.AuraInference:ScanAll() end

    local now = GetTime()
    for _, unit in ipairs(self:GetTrackedUnits()) do
        for _, entry in ipairs(ns.Spells) do
            if self:ShouldShow(entry, unit, false) then
                local st = stateFor(unit, entry.key)

                -- Active-aura animation can end independently from the recharge timer.
                if st.active and st.activeUntil and st.activeUntil > 0 and now >= st.activeUntil then
                    st.active = false
                    st.activeStart = 0
                    st.activeUntil = 0
                end

                local maxCharges = self:GetMaxCharges(entry, unit)
                if maxCharges > 1 then
                    local changed = self:UpdateChargeState(unit, entry, st)
                    if changed then self:PersistState(unit, entry, st) end
                elseif st.status == "cooldown" and st.readyAt > 0 and now >= st.readyAt then
                    st.status = "ready"
                    st.readyAt = 0
                    st.charges = 1
                    self:PersistState(unit, entry, st)
                end
            end
        end
    end
end

function Core:MarkDirty()
    runtime.dirty = true
end

local function cacheUnit(unit)
    local name = unitNameSafe(unit)
    local class = unitClassSafe(unit)
    if not name or not class then return nil end

    local cached = PartyCDLensDB.cache[name] or {}
    cached.name = name
    cached.class = class
    cached.guid = unitGUIDSafe(unit) or cached.guid
    cached.talents = cached.talents or {}
    cached.talentRanks = cached.talentRanks or {}
    cached.items = cached.items or {}
    PartyCDLensDB.cache[name] = cached

    runtime.units[unit] = {
        name = name,
        class = class,
        guid = cached.guid,
        specID = cached.specID,
        talents = cached.talents,
        talentRanks = cached.talentRanks,
        talentsKnown = cached.talentsKnown,
        items = cached.items,
        inspectTime = cached.inspectTime,
    }
    return runtime.units[unit]
end

function Core:RefreshRoster()
    local oldUnits = runtime.units
    runtime.units = {}

    for i = 1, 4 do
        local unit = "party"..i
        if UnitExists(unit) then
            local meta = cacheUnit(unit)
            if meta then
                self:RestoreUnitState(unit)
            end
        end
    end

    self:QueueInspects()
    self:MarkDirty()
    if ns.UI then ns.UI:ReanchorAll() end
end

function Core:ReadInspectTalents()
    if not C_Traits or not C_Traits.GetConfigInfo or not C_Traits.GetTreeNodes or
       not C_Traits.GetNodeInfo or not C_Traits.GetEntryInfo or not C_Traits.GetDefinitionInfo then
        return nil
    end

    local talents, talentRanks = {}, {}
    local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, -1)
    if not okInfo or not configInfo or isSecret(configInfo) then return nil end
    if not configInfo.treeIDs then return nil end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if okNodes and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local okNode, nodeInfo = pcall(C_Traits.GetNodeInfo, -1, nodeID)
                if okNode and nodeInfo and not isSecret(nodeInfo) then
                    local committed = nodeInfo.entryIDsWithCommittedRanks
                    if type(committed) == "table" then
                        for _, entryID in ipairs(committed) do
                            local okEntry, entryInfo = pcall(C_Traits.GetEntryInfo, -1, entryID)
                            if okEntry and entryInfo and not isSecret(entryInfo) and entryInfo.definitionID then
                                local okDef, def = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
                                if okDef and def and not isSecret(def) then
                                    local rank = tonumber(nodeInfo.activeRank) or 1
                                    if rank < 1 then rank = 1 end
                                    if type(def.spellID) == "number" then
                                        talents[def.spellID] = true
                                        talentRanks[def.spellID] = math.max(talentRanks[def.spellID] or 0, rank)
                                    end
                                    if type(def.overriddenSpellID) == "number" then
                                        talents[def.overriddenSpellID] = true
                                        talentRanks[def.overriddenSpellID] = math.max(talentRanks[def.overriddenSpellID] or 0, rank)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return talents, talentRanks
end

function Core:FinishInspect(unit)
    if not unit or not UnitExists(unit) then return end
    local meta = runtime.units[unit] or cacheUnit(unit)
    if not meta then return end

    local specID
    if C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
        local ok, v = pcall(C_SpecializationInfo.GetInspectSpecialization, unit)
        if ok and not isSecret(v) and type(v) == "number" and v > 0 then specID = v end
    elseif GetInspectSpecialization then
        local ok, v = pcall(GetInspectSpecialization, unit)
        if ok and not isSecret(v) and type(v) == "number" and v > 0 then specID = v end
    end

    local talents, talentRanks = self:ReadInspectTalents()
    local items = {} -- refresh from the current inspected gear, do not retain an unequipped trinket
    if GetInventoryItemID then
        for _, slot in ipairs({13,14}) do
            local ok, itemID = pcall(GetInventoryItemID, unit, slot)
            if ok and not isSecret(itemID) and type(itemID) == "number" then
                if itemID == 270162 then items[270162] = true end
            end
        end
    end

    if specID then meta.specID = specID end
    if talents then
        meta.talents = talents
        meta.talentRanks = talentRanks or {}
        meta.talentsKnown = true
    end
    meta.items = items
    meta.inspectTime = GetTime()

    local cached = PartyCDLensDB.cache[meta.name] or {}
    cached.name = meta.name
    cached.class = meta.class
    cached.guid = meta.guid
    cached.specID = meta.specID
    cached.talents = meta.talents
    cached.talentRanks = meta.talentRanks
    cached.talentsKnown = meta.talentsKnown
    cached.items = meta.items
    cached.inspectTime = time()
    PartyCDLensDB.cache[meta.name] = cached

    debugPrint("inspect", meta.name, "spec", meta.specID or "unknown", "talents", talents and "yes" or "no")
    self:RestoreUnitState(unit)
    if ns.UI then ns.UI:RefreshUnit(unit) end
    if ns.SecureSensors then ns.SecureSensors:OnRosterOrSpecChanged() end
end

function Core:CanInspectNow(unit)
    if InCombatLockdown and InCombatLockdown() then return false end
    if challengeActive() then return false end
    if not UnitExists(unit) then return false end
    if CanInspect then
        local ok, can = pcall(CanInspect, unit, false)
        if not ok or isSecret(can) or can ~= true then return false end
    end
    return true
end

function Core:QueueInspects()
    wipe(runtime.inspectQueue)
    if challengeActive() then return end
    for _, unit in ipairs(self:GetTrackedUnits()) do
        if self:CanInspectNow(unit) then table.insert(runtime.inspectQueue, unit) end
    end
    self:StartNextInspect()
end

function Core:StartNextInspect()
    if runtime.inspectPending or #runtime.inspectQueue == 0 then return end
    local unit = table.remove(runtime.inspectQueue, 1)
    if not self:CanInspectNow(unit) then
        C_Timer.After(0.4, function() Core:StartNextInspect() end)
        return
    end
    runtime.inspectPending = true
    runtime.inspectUnit = unit
    runtime.inspectGUID = unitGUIDSafe(unit)
    local requestedGUID = runtime.inspectGUID
    C_Timer.After(5, function()
        if runtime.inspectPending and runtime.inspectUnit == unit and runtime.inspectGUID == requestedGUID then
            runtime.inspectPending = false
            runtime.inspectUnit = nil
            runtime.inspectGUID = nil
            Core:StartNextInspect()
        end
    end)
    local ok = pcall(NotifyInspect, unit)
    if not ok then
        runtime.inspectPending = false
        runtime.inspectUnit = nil
        C_Timer.After(0.8, function() Core:StartNextInspect() end)
    end
end

function Core:OnInspectReady(guid)
    local unit = runtime.inspectUnit
    if not unit or isSecret(guid) or guid ~= runtime.inspectGUID then return end
    if unitGUIDSafe(unit) ~= runtime.inspectGUID then return end
    local requestedGUID = runtime.inspectGUID
    C_Timer.After(0, function()
        if not runtime.inspectPending or runtime.inspectGUID ~= requestedGUID then return end
        if unitGUIDSafe(unit) ~= requestedGUID then return end
        Core:FinishInspect(unit)
        if ClearInspectPlayer then pcall(ClearInspectPlayer) end
        runtime.inspectPending = false
        runtime.inspectUnit = nil
        C_Timer.After(0.8, function() Core:StartNextInspect() end)
    end)
end

function Core:RebuildAll()
    for _, unit in ipairs(self:GetTrackedUnits()) do
        self:RestoreUnitState(unit)
    end
    self:MarkDirty()
    if ns.UI then ns.UI:ReanchorAll() end
    if ns.SecureSensors then ns.SecureSensors:OnRosterOrSpecChanged() end
    if ns.Options then ns.Options:Refresh() end
end

function Core:ToggleDebug()
    PartyCDLensDB.debug = not PartyCDLensDB.debug
    print("PartyCDLens debug:", PartyCDLensDB.debug and "ON" or "OFF")
end

function Core:ToggleTest()
    runtime.testMode = not runtime.testMode
    print("PartyCDLens test mode:", runtime.testMode and "ON" or "OFF")
    if ns.UI then ns.UI:ReanchorAll() end
end

function Core:PrintCharges()
    print("|cff69ccf0PartyCDLens charge model|r")
    for _, unit in ipairs(self:GetTrackedUnits()) do
        local meta = runtime.units[unit]
        if meta then
            for _, entry in ipairs(ns.Spells) do
                if self:ShouldShow(entry, unit, false) then
                    local maxCharges = self:GetMaxCharges(entry, unit)
                    if maxCharges > 1 then
                        if ns.SecureSensors and ns.SecureSensors:Supports(entry) then
                            print((meta.name or unit)..":", entry.name, "?/"..maxCharges.." (max charges known; live remaining charges are protected/not decoded yet)")
                        else
                            local st = stateFor(unit, entry.key)
                            self:UpdateChargeState(unit, entry, st)
                            local available = st.status == "unknown" and "?" or tostring(st.charges or maxCharges)
                            local nextText = ""
                            if st.chargeReadyAts[1] and st.chargeReadyAts[1] > GetTime() then
                                nextText = " next~"..tostring(math.ceil(st.chargeReadyAts[1] - GetTime())).."s"
                            end
                            print((meta.name or unit)..":", entry.name, available.."/"..maxCharges..nextText)
                        end
                    end
                end
            end
        end
    end
end

function Core:PrintStatus()
    print("|cff69ccf0PartyCDLens 0.9.0-alpha|r")
    print("Challenge active:", challengeActive() and "yes" or "no")
    for _, unit in ipairs(self:GetTrackedUnits()) do
        local m = runtime.units[unit]
        if m then
            print(unit, m.name or "?", m.class or "?", ns.SpecNames[m.specID] or tostring(m.specID or "spec unknown"), m.talentsKnown and "talents cached" or "talents unknown")
        end
    end
end

function Core:Initialize()
    PartyCDLensDB = deepcopyDefaults(PartyCDLensDB, defaults)
    PartyCDLensState = PartyCDLensState or {players={}}
    PartyCDLensState.players = PartyCDLensState.players or {}
    runtime.activeChallengeAtLogin = challengeActive()

    SLASH_PARTYCDLENS1 = "/pcdl"
    SlashCmdList.PARTYCDLENS = function(msg)
        msg = strlower(strtrim(msg or ""))
        if msg == "diag" or msg:match("^diag ") then
            Core:DiagnosticCommand(msg:match("^diag%s+(%S+)") or "")
        elseif msg == "debug" then
            Core:ToggleDebug()
        elseif msg == "test" then
            Core:ToggleTest()
        elseif msg == "status" then
            Core:PrintStatus()
        elseif msg == "coverage" then
            if ns.AuraInference then ns.AuraInference:PrintCoverage() end
        elseif msg == "charges" then
            Core:PrintCharges()
        elseif msg == "secure" then
            if ns.SecureSensors then ns.SecureSensors:PrintStatus() end
        elseif msg == "rescan" then
            Core:RefreshRoster()
            print("PartyCDLens: roster/spec inspection queued where Blizzard permits it.")
        elseif msg == "reset" then
            PartyCDLensDB = deepcopyDefaults({}, defaults)
            PartyCDLensState = {players={}}
            Core:RefreshRoster()
            print("PartyCDLens: settings reset.")
        else
            if ns.Options then ns.Options:Toggle() end
        end
    end

    self:RefreshRoster()
    if ns.AuraInference then
        C_Timer.After(1.0, function() ns.AuraInference:Reset() end)
    end
end

local fallbackElapsed = 0
local uiElapsed = 0
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    fallbackElapsed = fallbackElapsed + elapsed
    uiElapsed = uiElapsed + elapsed

    if runtime.dirty or fallbackElapsed >= 0.50 then
        runtime.dirty = false
        fallbackElapsed = 0
        Core:ScanAll()
    end
    if uiElapsed >= 0.10 then
        uiElapsed = 0
        if ns.UI then ns.UI:UpdateTimers() end
    end
end)

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Core:Initialize()
        if ns.UI then ns.UI:Initialize() end
        if ns.SecureSensors then ns.SecureSensors:Initialize() end
        if ns.Options then ns.Options:Initialize() end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if PartyCDLensDB then C_Timer.After(0.2, function()
            Core:RefreshRoster()
            if ns.AuraInference then ns.AuraInference:Reset() end
            if ns.SecureSensors then ns.SecureSensors:OnRosterOrSpecChanged() end
        end) end
    elseif event == "UNIT_MODEL_CHANGED" then
        local unit = ...
        if ns.AuraInference then ns.AuraInference:OnModelChanged(unit) end
    elseif event == "UNIT_AURA" then
        local unit, updateInfo = ...
        if ns.AuraInference then ns.AuraInference:OnAuraEvent(unit) end
        if ns.SecureSensors then ns.SecureSensors:OnAuraEvent(unit, updateInfo) end
        runtime.dirty = true
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        Core:OnTrackedSpellcast(unit, spellID)
        if ns.AuraInference then ns.AuraInference:OnUnitSpellcast(unit) end
        if ns.SecureSensors then ns.SecureSensors:OnSpellcastSucceeded(unit, spellID) end
    elseif event == "UNIT_TARGET" then
        local unit = ...
        if ns.SecureSensors then ns.SecureSensors:OnUnitTarget(unit) end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        local unit = ...
        if ns.AuraInference then ns.AuraInference:OnAbsorbChanged(unit) end
    elseif event == "UNIT_FLAGS" then
        local unit = ...
        if ns.AuraInference then ns.AuraInference:OnFlagsChanged(unit) end
    elseif event == "INSPECT_READY" then
        Core:OnInspectReady(...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if PartyCDLensDB then Core:QueueInspects() end
        if ns.SecureSensors then ns.SecureSensors:OnCombatEnded() end
    elseif event == "CHALLENGE_MODE_START" then
        Core:ResetForChallengeStart()
        if ns.AuraInference then ns.AuraInference:Reset() end
        if ns.SecureSensors then ns.SecureSensors:OnRosterOrSpecChanged() end
        runtime.dirty = true
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        runtime.challengeStartedThisSession = false
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if ns.UI then C_Timer.After(0.1, function() ns.UI:ReanchorAll() end) end
    elseif event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == "ElvUI" and ns.UI then C_Timer.After(1, function() ns.UI:ReanchorAll() end) end
    end
end)

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_TARGET")
eventFrame:RegisterEvent("UNIT_MODEL_CHANGED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
eventFrame:RegisterEvent("ADDON_LOADED")
