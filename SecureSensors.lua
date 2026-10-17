local addonName, ns = ...
local Core = ns.Core

local SS = {}
ns.SecureSensors = SS

local _G = _G
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local ipairs, pairs, pcall, type, tostring = ipairs, pairs, pcall, type, tostring
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local tconcat = table.concat

local issecretvalue = _G.issecretvalue
local issecrettable = _G.issecrettable
local function secret(v) return issecretvalue and issecretvalue(v) end

-- UNIT_AURA updateInfo itself can be protected in 12.1.  Treat unreadable payloads as
-- meaningful churn, matching KiraUI's conservative behavior.
local function auraPayloadChurns(info)
    local function read()
        if secret(info) or info == nil or (issecrettable and issecrettable(info)) then return true end
        local full, added, removed = info.isFullUpdate, info.addedAuras, info.removedAuraInstanceIDs
        if secret(full) or secret(added) or secret(removed) then return true end
        return (full or added or removed) and true or false
    end
    local ok, v = pcall(read)
    return not ok or v
end

local EvalBool = _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean
local READ_EVERY, READS_AFTER, HOLD = 0.20, 2, 0.50
local TICK = 0.25
local CODES, LINGER = 254, 4
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local T0 = GetTime() - 1024

local function Now() return floor(GetTime() - T0 + 0.5) end

local function hasTemplate(name)
    local X = _G.C_XMLUtil
    if not (X and X.GetTemplateInfo) then return false end
    local ok, info = pcall(X.GetTemplateInfo, name)
    return ok and info ~= nil
end

local function doorTest()
    local d = { state = 'error' }
    if not EvalBool then
        d.detail = 'C_CurveUtil.EvaluateColorValueFromBoolean is missing'
        return d
    end
    local bytes = { 0, 1, 48, 85, 127, 200, 254, 255 }
    local off = 0
    for _, k in ipairs(bytes) do
        local want, v = k / 255, k / 255
        for pass = 1, 16 do
            local ok, w
            if pass % 2 == 1 then ok, w = pcall(EvalBool, true, v, 0)
            else ok, w = pcall(EvalBool, false, 0, v) end
            if not ok then d.detail = tostring(w) return d end
            if secret(w) then d.state = 'hidden' return d end
            if type(w) ~= 'number' then d.detail = 'curve returned '..type(w) return d end
            v = w
            local gap = abs(v - want)
            if gap > off then off = gap end
        end
    end
    d.off = off
    d.state = off == 0 and 'exact' or (off <= 1e-6 and 'close' or 'coarse')
    return d
end

local door = doorTest()
local function doorOpen()
    return door.state == 'exact' or door.state == 'close' or door.state == 'hidden'
end

SS.available = hasTemplate('CustomAuraContainerTemplate') and doorOpen() and true or false
SS.failure = not hasTemplate('CustomAuraContainerTemplate') and 'CustomAuraContainerTemplate unavailable'
    or (not doorOpen() and (door.detail or door.state)) or nil

-- Key-specific definitions take precedence over generic spell-ID definitions.  This lets
-- replacement/choice abilities that share a cast spell (notably Paladin wings) keep separate
-- rows without one variant lighting every row.
local BY_KEY = {
    -- PALADIN
    pal_divine_shield = { buff={642}, active=8, poll=true },
    pal_bop = { buff={1022,204018}, zone=true, active=10, poll=true },
    pal_freedom = { buff={1044,305395,262618,299256}, zone=true, active=8, poll=true },
    ret_aw = { buff={31884}, poll=true },
    ret_crusade = { buff={231895}, poll=true },
    holy_aw = { buff={31884}, poll=true },
    holy_avenging_crusader = { buff={216331}, poll=true },
    prot_aw = { buff={31884}, poll=true },
    prot_sentinel = { buff={389539}, poll=true },
    pal_loh = { buff={387792}, zone=true, poll=true },
    holy_aura_mastery = { buff={412629,317929,31821}, active=8, poll=true },

    -- PRIEST
    priest_fade = { buff={586,1250385,335986,114239,373447}, poll=true },
    priest_desperate = { buff={19236}, poll=true },
    shadow_dispersion = { buff={47585}, poll=true },
    disc_ps = { buff={33206}, zone=true, poll=true },
    disc_ultimate_penitence = { buff={421453,421434,419305}, poll=true },
    -- Divine Hymn grants Guardian Spirit to its caster. Track real GS on self or allies, but
    -- reject the caster-side 47788 aura while the Divine Hymn channel aura is present.
    holy_gs = { buff={47788}, excludeBuff={64843}, zone=true, poll=true },
    holy_hymn = { buff={64843,64844}, zone=true, poll=true },
    holy_apoth = { buff={200183}, poll=true },

    -- WARLOCK
    aff_darkglare = { buff={1280663,205180}, poll=true },
    demo_imp_lord = { buff={1288945,1276452}, poll=true },
}

-- Exact aura identities taken from the PartyCD module supplied by the user.  These are
-- intentionally separate from AuraInference: the AuraContainer performs the spell-ID
-- candidate filtering inside Blizzard UI code, so Lua never has to read the protected aura ID.
-- Aliases are included where our database uses the talent/replacement cast spell as the key.
local BY_SPELL = {
    [49028]  = { buff={81256} },
    [48792]  = { buff={48792} },
    [48707]  = { buff={48707,444741} },
    [51271]  = { buff={51271} },
    [42650]  = { buff={42650} },
    [51052]  = { buff={51052,145629}, zone=true },

    [191427] = { buff={162264}, short=10, active=20 },
    [198589] = { buff={212800}, active=10 },

    [194223] = { buff={194223,102560,390414} },
    [102560] = { buff={194223,102560,390414} },
    [106951] = { buff={106951,102543} },
    [102543] = { buff={106951,102543} },
    [740]    = { buff={740,157982,1264623} },
    [22812]  = { buff={22812} },
    [61336]  = { buff={61336} },

    [375087] = { buff={375087} },
    [363534] = { buff={363534} },
    [384089] = { buff={363534} },
    [403631] = { buff={403631} },
    [442204] = { buff={403631} },
    [363916] = { buff={363916} },

    [19574]  = { buff={19574,186254,1235388,1285912} },
    [288613] = { buff={288613} },
    [1250646]= { buff={1250646,1251703} },
    [186265] = { buff={186265} },
    [264735] = { buff={264735} },

    [365350] = { buff={365350,365362} },
    [190319] = { buff={190319}, short=8 },
    [45438]  = { buff={45438,414658} },
    [414659] = { buff={45438,414658} },
    [342245] = { buff={342246} },

    [132578] = { buff={132578} },
    [123904] = { buff={123904,1248992} },
    [115203] = { buff={115203,120954} },
    [122783] = { buff={122783} },
    [122470] = { buff={125174} },

    [31884]  = { buff={31884,231895,454351,216331,389539} },
    [642]    = { buff={642} },
    [498]    = { buff={498,403876} },
    [403876] = { buff={498,403876} },
    [31850]  = { buff={31850} },

    [62618]  = { buff={81782} },
    [200183] = { buff={200183} },
    [228260] = { buff={194249} },
    [19236]  = { buff={19236} },
    [47585]  = { buff={47585} },

    -- Deathmark is awkward in Midnight: Kira's supplied PartyCD map watches the
    -- Finish the Job self-buff (1249810), but that aura is absent when the rogue
    -- chooses Negotiable Contract instead.  Keep Kira's exact self sensor and add
    -- a protected HARMFUL sensor on partyNtarget for the actual Deathmark debuff.
    [360194] = { buff={1249810}, targetDebuff={360194}, active=16, poll=true },
    [121471] = { buff={121471} },
    -- 31224 is the visible 5s Cloak aura. 35729 is its triggered 1s school-immunity
    -- aura; accepting both makes the sensor resilient to which layer Blizzard exposes.
    [31224]  = { buff={31224,35729}, active=5, poll=true },
    [5277]   = { buff={5277} },

    [114050] = { buff={114050,1219480}, short=10 },
    [114051] = { buff={114051}, short=10 },
    [114052] = { buff={114052}, short=10 },
    [98008]  = { buff={325174} },
    [108271] = { buff={108271} },
    [198103] = { buff={198103,381755} },

    [265187] = { buff={1276767} },
    [205180] = { buff={205180} },
    [1122]   = { buff={111685,266087,417282} },
    [104773] = { buff={104773} },
    [108416] = { buff={108416} },

    [1719]   = { buff={1719} },
    [118038] = { buff={118038} },
    [184364] = { buff={184364} },
    [97462]  = { buff={97463} },
    [23920]  = { buff={23920} },

    [33206]  = { buff={33206}, zone=true },
    [47788]  = { buff={47788}, zone=true, others=true },
    [102342] = { buff={102342}, zone=true },
    [116849] = { buff={116849}, zone=true },
    [6940]   = { buff={6940}, zone=true, others=true },
    [357170] = { buff={357170}, zone=true },
}

local function sensorDefFor(entry)
    if not entry then return nil end
    if entry.key and BY_KEY[entry.key] then
        return BY_KEY[entry.key], (entry.spellIDs and entry.spellIDs[1])
    end
    for _, id in ipairs(entry.spellIDs or {}) do
        if BY_SPELL[id] then return BY_SPELL[id], id end
    end
    return nil
end

function SS:Supports(entry)
    return self.available and sensorDefFor(entry) ~= nil
end

local function makeSet(list)
    local t = {}
    for _, id in ipairs(list or {}) do t[id] = true end
    return t
end

local function signature(def)
    local ids = {}
    for _, id in ipairs(def.buff or {}) do ids[#ids+1] = tostring(id) end
    table.sort(ids)
    local s = tconcat(ids, ',')
    if def.short then s = s .. '<' .. tostring(def.short) end
    if def.excludeBuff then
        local ex = {}
        for _, id in ipairs(def.excludeBuff) do ex[#ex+1] = tostring(id) end
        table.sort(ex)
        s = s .. '|X:' .. tconcat(ex, ',')
    end
    if def.targetDebuff then
        local harmful = {}
        for _, id in ipairs(def.targetDebuff) do harmful[#harmful+1] = tostring(id) end
        table.sort(harmful)
        s = s .. '|H:' .. tconcat(harmful, ',')
    end
    return s
end

local function addSensorGroup(c, key, filterString)
    local function initButton(b)
        pcall(b.SetSize, b, 1, 1)
        pcall(b.SetMouseClickEnabled, b, false)
        pcall(b.SetMouseMotionEnabled, b, false)
    end
    return pcall(c.AddAuraGroup, c, key, filterString or 'HELPFUL', {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = {} },
        initializeFrame = initButton,
        layout = { elementWidth = 50000, elementHeight = 1, elementSpacing = 0, lineSpacing = 0 },
    })
end

local sensorHost
local function ensureSensorHost()
    if sensorHost then return end
    sensorHost = CreateFrame('Frame', 'PartyCDLensSecureSensorHost', UIParent)
    sensorHost:SetSize(1,1)
    sensorHost:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', -50, 0)
    sensorHost:EnableMouse(false)
end

local function newSensor(unit, filters, filterString)
    if InCombatLockdown and InCombatLockdown() then return nil, 'combat' end
    ensureSensorHost()
    local ok, c = pcall(CreateFrame, 'AuraContainer', nil, sensorHost, 'CustomAuraContainerTemplate')
    if not ok or not c then return nil, 'AuraContainer refused' end
    c:SetSize(1,1)
    c:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', -11, 0)
    pcall(c.EnableMouse, c, false)
    local okG, err = addSensorGroup(c, 'cd', filterString)
    if not okG then return nil, tostring(err) end
    pcall(c.SetUnit, c, unit)
    local okF = pcall(c.SetAuraGroupCandidateFilters, c, 'cd', filters)
    if not okF then return nil, 'candidate filter refused' end
    pcall(c.SetEnabled, c, true)
    pcall(c.UpdateAllAuras, c)
    c.__pcdlOn = true
    return c
end

local function parkSensor(c)
    if c and c.__pcdlOn then
        c.__pcdlOn = false
        pcall(c.SetEnabled, c, false)
    end
end

local function sensorLit(c)
    if not c then return false end
    return c:IsMouseOver(1e5, -1e5, 0, 0)
end

local function pick(cur, dual, short, a, b)
    if not dual then return EvalBool(cur, a, b) end
    if dual == 'any' then
        local r = EvalBool(cur, a, b)
        for i = 1, short.n do r = EvalBool(short[i], a, r) end
        return r
    end
    if dual == 'anyExcept' then
        -- (cur AND NOT excluded) OR any(zone target). All branches remain protected-safe.
        local r = EvalBool(cur, EvalBool(short.exclude, b, a), b)
        for i = 1, short.n do r = EvalBool(short[i], a, r) end
        return r
    end
    return EvalBool(cur, EvalBool(short, b, a), b)
end

local function state(cur, dual, short)
    if secret(cur) then return false, false end
    if dual == 'any' or dual == 'anyExcept' then
        local up = cur and true or false
        if dual == 'anyExcept' then
            local ex = short.exclude
            if secret(ex) then return false, false end
            up = up and not ex
        end
        for i = 1, short.n do
            local v = short[i]
            if secret(v) then return false, false end
            if v then up = true end
        end
        return true, up
    end
    if secret(short) then return false, false end
    return true, (cur and not (dual and short)) and true or false
end

local function timerUnit(seconds) return max(1, ceil(seconds / CODES)) end

local function clearTimer(t, n)
    local a, b = t.slot[1], t.slot[2]
    a.c, a.v, a.epoch = 1, 0, n
    b.c, b.v, b.epoch = 1, 0, n
    t.cur = 1
end

local function newTimer(seconds)
    -- The protected renderer encodes whole-second positions. Round fractional talent-modified
    -- cooldowns upward (e.g. 52.5 -> 53) so the healer display stays conservative.
    seconds = max(1, ceil(tonumber(seconds) or 1))
    local t = { seconds=seconds, slot={{},{}} }
    t.u = timerUnit(seconds)
    t.P = CODES * t.u
    clearTimer(t, Now())
    return t
end

local function rollTimer(t, n)
    local k = t.cur
    if n - t.slot[k].epoch < t.P then return false end
    k = 3 - k
    local sl = t.slot[k]
    sl.c, sl.v, sl.epoch = 1, 0, n
    t.cur = k
    return true
end

local function stampTimer(t, n)
    local code = floor((n - t.slot[t.cur].epoch) / t.u)
    if code < 0 then code = 0 elseif code > CODES then code = CODES end
    return (255 - code) / 255
end

local function startPlain(t, n)
    rollTimer(t, n)
    local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
    sl.c, sl.v, other.v = stampTimer(t, n), 1, 0
end

local function startSecret(t, cur, dual, short, prev, prevDual, prevShort, n)
    rollTimer(t, n)
    local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
    sl.c = pick(cur, dual, short, pick(prev, prevDual, prevShort, sl.c, stampTimer(t, n)), sl.c)
    sl.v = pick(cur, dual, short, pick(prev, prevDual, prevShort, sl.v, 1), sl.v)
    other.v = pick(cur, dual, short, pick(prev, prevDual, prevShort, other.v, 0), other.v)
end

local meter
local metrics, strips = {}, {}
local function ensureMeter()
    if meter then return end
    meter = UIParent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    meter:SetPoint('BOTTOMLEFT', UIParent, 'TOPLEFT', -1000, 1000)
    meter:SetAlpha(0)
end

local function lineMetrics(font, size)
    ensureMeter()
    local key = tostring(font)..'|'..tostring(size)
    local m = metrics[key]
    if m then return m[1], m[2] end
    meter:SetFont(font, size, 'OUTLINE')
    meter:SetText('0')
    local one = meter:GetStringHeight()
    meter:SetText('0\n0\n0\n0\n0\n0\n0\n0\n0')
    local nine = meter:GetStringHeight()
    if secret(one) or secret(nine) or type(one)~='number' or type(nine)~='number' or nine <= one then
        return size, size
    end
    local step = (nine-one)/8
    metrics[key] = {step,one}
    return step,one
end

local function stripText(seconds)
    local s = strips[seconds]
    if s then return s end
    local out = {}
    for r=seconds,1,-1 do
        out[#out+1] = r >= 60 and string.format('%d:%02d', floor(r/60), r%60) or tostring(r)
    end
    s = tconcat(out, '\n')
    strips[seconds] = s
    return s
end

local renderLayer
local function ensureRenderLayer()
    if renderLayer then return end
    renderLayer = CreateFrame('Frame', 'PartyCDLensSecureRenderLayer', UIParent)
    renderLayer:SetAllPoints(UIParent)
    renderLayer:EnableMouse(false)
end

local function newRenderer(icon, timer, kind)
    ensureRenderLayer()
    local r = { icon=icon, timer=timer, kind=kind, pos={}, fill={}, host={}, strip={}, gate={}, cover={} }
    r.win = CreateFrame('Frame', nil, icon)
    r.win:SetClipsChildren(true)
    r.win:SetPoint('CENTER', icon, 'CENTER', 0, 0)
    r.clip = CreateFrame('Frame', nil, icon)
    r.clip:SetClipsChildren(true)
    r.clip:SetPoint('TOPLEFT', icon, 'TOPLEFT', 1, -1)
    r.clip:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT', -1, 1)

    for k=1,2 do
        local pos = CreateFrame('StatusBar', nil, renderLayer)
        pos:SetStatusBarTexture(WHITE)
        pos:SetStatusBarColor(0,0,0,0)
        pos:SetOrientation('VERTICAL')
        pos:SetMinMaxValues(0,1)
        pos:SetValue(1)
        r.pos[k] = pos
        r.fill[k] = pos:GetStatusBarTexture()

        local h = CreateFrame('Frame', nil, r.win)
        h:SetAllPoints(r.win)
        h:SetAlpha(0)
        local fs = h:CreateFontString(nil, 'OVERLAY')
        fs:SetJustifyH('CENTER')
        fs:SetTextColor(1,1,1,1)
        fs:SetPoint('BOTTOM', r.fill[k], 'TOP', 0, 0)
        r.host[k], r.strip[k] = h, fs

        if kind == 'cooldown' then
            local gate = CreateFrame('StatusBar', nil, renderLayer)
            gate:SetStatusBarTexture(WHITE)
            gate:SetStatusBarColor(0,0,0,0)
            gate:SetOrientation('VERTICAL')
            gate:SetMinMaxValues(0,1)
            gate:SetValue(1)
            r.gate[k] = gate
            local edge = gate:GetStatusBarTexture()
            local cover = CreateFrame('Frame', nil, r.clip)
            cover:SetClipsChildren(true)
            cover:SetAlpha(0)
            local shade = cover:CreateTexture(nil, 'OVERLAY')
            shade:SetColorTexture(0,0,0,0.52)
            shade:SetAllPoints(r.clip)
            cover.shade = shade
            cover.edge = edge
            r.cover[k] = cover
        end
    end
    return r
end

local function dressRenderer(r, iconSize, textSize)
    local font = _G.STANDARD_TEXT_FONT
    if _G.GameFontNormalSmall and _G.GameFontNormalSmall.GetFont then
        local ok, f = pcall(_G.GameFontNormalSmall.GetFont, _G.GameFontNormalSmall)
        if ok and f then font = f end
    end
    local step, one = lineMetrics(font, textSize)
    local line = min(one, step)
    local seconds, u = r.timer.seconds, r.timer.u
    local sig = table.concat({ tostring(font), tostring(textSize), tostring(iconSize), tostring(seconds), tostring(u), r.kind }, '|')
    if r.sig == sig then return false end
    r.sig = sig
    local jump = iconSize + 2
    r.win:SetSize(iconSize+6, line)
    r.line = line
    for k=1,2 do
        local pos = r.pos[k]
        pos:ClearAllPoints()
        pos:SetPoint('BOTTOM', r.win, 'BOTTOM', 0, -(seconds - 1 + u) * step)
        pos:SetSize(1, 255 * u * step)
        r.strip[k]:SetFont(font, textSize, 'OUTLINE')
        r.strip[k]:SetText(stripText(seconds))
        if r.kind == 'cooldown' then
            local gate = r.gate[k]
            gate:ClearAllPoints()
            gate:SetPoint('BOTTOM', r.clip, 'BOTTOM', 0, -(seconds - 1 + u) * jump)
            gate:SetSize(1, 255 * u * jump)
            local cover = r.cover[k]
            cover:ClearAllPoints()
            cover:SetPoint('BOTTOM', cover.edge, 'TOP', 0, -1)
            cover:SetPoint('TOP', cover.edge, 'TOP', 0, (seconds - 1) * jump + iconSize + 1)
            cover:SetWidth(iconSize)
        end
    end
    return true
end

local function rangeRenderer(r, k, sl, now)
    local u = r.timer.u
    local m = (254 - (now - sl.epoch) / u) / 255
    r.pos[k]:SetMinMaxValues(m, m+1)
    if r.gate[k] then r.gate[k]:SetMinMaxValues(m, m+1) end
end

local function leftTimer(t, sl, n)
    if secret(sl.c) then return nil end
    local code = 255 - floor(sl.c * 255 + 0.5)
    return t.seconds - ((n - sl.epoch) - t.u * code)
end

local function gatedAlpha(track, slv, wantActive)
    if not track.primed then return 0 end
    if wantActive then
        return pick(track.lastCur, track.lastDual, track.lastShort, slv, 0)
    end
    return pick(track.lastCur, track.lastDual, track.lastShort, 0, slv)
end

local function pushTimer(timer, renderer, track)
    if not renderer then return end
    local now = Now()
    for k=1,2 do
        local sl = timer.slot[k]
        renderer.pos[k]:SetMinMaxValues(0,1)
        renderer.pos[k]:SetValue(sl.c)
        if renderer.gate[k] then
            renderer.gate[k]:SetMinMaxValues(0,1)
            renderer.gate[k]:SetValue(sl.c)
        end
        local alpha = gatedAlpha(track, sl.v, renderer.kind == 'active')
        renderer.host[k]:SetAlpha(alpha)
        if renderer.cover[k] then renderer.cover[k]:SetAlpha(alpha) end
        rangeRenderer(renderer, k, sl, now)
    end
end

local function makeGlowGate(icon)
    if icon.secureGlowGate then return icon.secureGlowGate end
    local g = CreateFrame('Frame', nil, icon)
    g:SetAllPoints(icon)
    g:SetFrameLevel(icon:GetFrameLevel()+12)
    g:SetAlpha(0)
    g:EnableMouse(false)
    local glow = g:CreateTexture(nil, 'OVERLAY', nil, 7)
    glow:SetTexture('Interface\\Buttons\\UI-ActionButton-Border')
    glow:SetBlendMode('ADD')
    glow:SetPoint('CENTER')
    glow:SetSize((icon:GetWidth() or 24)*1.75, (icon:GetHeight() or 24)*1.75)
    glow:SetAlpha(1)
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping('BOUNCE')
    local a = ag:CreateAnimation('Alpha')
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.55)
    ag:Play()
    g.glow, g.anim = glow, ag
    icon.secureGlowGate = g
    return g
end

local units = {}
local zoneSensors = {}
local pendingRefresh = false
local driver
local ticker
local hideRenderer

local function unitState(unit)
    local u = units[unit]
    if not u then
        u = { unit=unit, tracks={}, reads=0, hold=0 }
        units[unit] = u
    end
    return u
end

local function filtersFor(def, short, ids)
    local f = { includeSpellIDs = makeSet(ids or def.buff) }
    if short and def.short then f.maxDuration = def.short end
    return f
end

local function ensureTrackSensor(track)
    if track.def.others then return true end
    if not track.sensor then
        local c, why = newSensor(track.unit, filtersFor(track.def, false))
        if not c then track.sensorError = why return false end
        track.sensor = c
    end
    if track.def.short and not track.shortSensor then
        local c, why = newSensor(track.unit, filtersFor(track.def, true))
        if not c then track.sensorError = why return false end
        track.shortSensor = c
    end
    if track.def.excludeBuff and not track.excludeSensor then
        local c, why = newSensor(track.unit, filtersFor(track.def, false, track.def.excludeBuff))
        if not c then track.sensorError = why return false end
        track.excludeSensor = c
    end
    if track.def.targetDebuff and not track.targetSensor then
        local c, why = newSensor(track.unit .. 'target', filtersFor(track.def, false, track.def.targetDebuff), 'HARMFUL')
        if not c then track.targetSensorError = why return false end
        track.targetSensor = c
    end
    return true
end

local function unitExistsSafe(unit)
    local ok, v = pcall(UnitExists, unit)
    if not ok or secret(v) then return false end
    return v and true or false
end

local function guidOf(unit)
    local ok, g = pcall(UnitGUID, unit)
    if ok and not secret(g) then return g end
    return nil
end

local function zoneKey(def) return signature(def) end

local function ensureZoneSensor(targetUnit, def)
    local sig = zoneKey(def)
    zoneSensors[targetUnit] = zoneSensors[targetUnit] or {}
    local c = zoneSensors[targetUnit][sig]
    if not c then
        local why
        c, why = newSensor(targetUnit, filtersFor(def, false))
        if not c then return nil, why end
        zoneSensors[targetUnit][sig] = c
    end
    return c
end

local ALL_UNITS = {'player','party1','party2','party3','party4'}
local function zoneRead(track)
    track.zoneLists = track.zoneLists or { {n=0}, {n=0} }
    local list = track.zoneLists[1] == track.prevShort and track.zoneLists[2] or track.zoneLists[1]
    local k = 0
    local sig = zoneKey(track.def)
    for _, target in ipairs(ALL_UNITS) do
        if target ~= track.unit and unitExistsSafe(target) then
            local c = zoneSensors[target] and zoneSensors[target][sig]
            if c then
                k = k + 1
                list[k] = sensorLit(c)
            end
        end
    end
    for i=k+1,(list.n or 0) do list[i]=nil end
    list.n = k
    return list
end

-- Keep two alternating tables so prevShort remains a snapshot rather than being
-- mutated in-place on the next poll.  The protected boolean itself may stay secret.
local function targetRead(track)
    track.targetLists = track.targetLists or { {n=0}, {n=0} }
    local list = track.targetLists[1] == track.prevShort and track.targetLists[2] or track.targetLists[1]
    if track.targetSensor then
        list[1] = sensorLit(track.targetSensor)
        list.n = 1
    else
        list[1] = nil
        list.n = 0
    end
    return list
end

local function feedTrack(track, cur, dual, short, n)
    if track.primed then
        rollTimer(track.cooldown, n)
        if track.activeTimer then rollTimer(track.activeTimer, n) end
        local prev, prevDual, prevShort = track.prev, track.prevDual, track.prevShort
        local curKnown, up = state(cur, dual, short)
        local prevKnown, was = state(prev, prevDual, prevShort)
        local idle = (curKnown and not up) or (prevKnown and was)
        local suppressed = track.suppressEdgeUntil and GetTime() < track.suppressEdgeUntil
        if not idle and not suppressed then
            if curKnown and prevKnown then
                startPlain(track.cooldown, n)
                if track.activeTimer then startPlain(track.activeTimer, n) end
            else
                startSecret(track.cooldown, cur, dual, short, prev, prevDual, prevShort, n)
                if track.activeTimer then startSecret(track.activeTimer, cur, dual, short, prev, prevDual, prevShort, n) end
            end
        end
    end
    track.prev, track.prevDual, track.prevShort = cur, dual, short
    track.lastCur, track.lastDual, track.lastShort = cur, dual, short
    track.primed = true
    if track.cooldownRenderer then pushTimer(track.cooldown, track.cooldownRenderer, track) end
    if track.activeRenderer then pushTimer(track.activeTimer, track.activeRenderer, track) end
    if track.icon and track.icon.secureGlowGate then
        track.icon.secureGlowGate:SetAlpha(pick(cur, dual, short, 1, 0))
    end
end

local function readTrack(track, n)
    local cur = false
    if not track.def.others then cur = sensorLit(track.sensor) end
    local dual, short = false, false
    if track.def.short then
        dual = true
        short = sensorLit(track.shortSensor)
    end
    if track.def.zone then
        short = zoneRead(track)
        if track.def.excludeBuff then
            dual = 'anyExcept'
            short.exclude = sensorLit(track.excludeSensor)
        else
            dual = 'any'
        end
    elseif track.def.excludeBuff then
        dual = true
        short = sensorLit(track.excludeSensor)
    elseif track.def.targetDebuff then
        dual = 'any'
        short = targetRead(track)
    end
    feedTrack(track, cur, dual, short, n)
end

local function readUnit(u)
    local n = Now()
    for _, track in pairs(u.tracks) do
        if track.live then
            local ok, err = pcall(readTrack, track, n)
            if not ok and PartyCDLensDB and PartyCDLensDB.debug then
                print('|cff69ccf0PartyCDLens secure:|r read error', tostring(err))
            end
        end
    end
end

local function wakeDriver()
    if not driver then return end
    if not driver:IsShown() then driver.acc=0 driver:Show() end
end

local function ensureDrivers()
    if not driver then
        driver = CreateFrame('Frame')
        driver:Hide()
        driver.acc = 0
        driver:SetScript('OnUpdate', function(self, elapsed)
            self.acc = self.acc + elapsed
            if self.acc < READ_EVERY then return end
            self.acc = 0
            local now, busy = GetTime(), false
            for _, u in pairs(units) do
                if u.reads > 0 then
                    if now >= u.hold then
                        u.reads = u.reads - 1
                        readUnit(u)
                    end
                    if u.reads > 0 then busy=true end
                end
            end
            if not busy then self:Hide() end
        end)
    end
    if not ticker then
        ticker = C_Timer.NewTicker(TICK, function()
            local n = Now()
            for _, u in pairs(units) do
                for _, track in pairs(u.tracks) do
                    if track.live then
                        -- Some rogue auras have proven inconsistent about which UNIT_AURA
                        -- payload fields churn. Polling the native sensors is cheap and avoids
                        -- missing Cloak/Deathmark edges while keeping all spell data protected.
                        if track.def.poll then
                            local ok, err = pcall(readTrack, track, n)
                            if not ok and PartyCDLensDB and PartyCDLensDB.debug then
                                print('|cff69ccf0PartyCDLens secure poll:|r', tostring(err))
                            end
                        end
                        rollTimer(track.cooldown, n)
                        if track.activeTimer then rollTimer(track.activeTimer, n) end

                        -- Readable/plain states can be retired once the encoded timer is well
                        -- past zero. Protected states cannot be inspected, so their geometry
                        -- simply scrolls out of the clipping window (the same trick Kira uses).
                        for _, timer in ipairs({ track.cooldown, track.activeTimer }) do
                            if timer then
                                for k=1,2 do
                                    local sl = timer.slot[k]
                                    if not secret(sl.v) and sl.v ~= 0 then
                                        local left = leftTimer(timer, sl, n)
                                        if left and left <= -LINGER then sl.v = 0 end
                                    end
                                end
                            end
                        end

                        if track.cooldownRenderer then pushTimer(track.cooldown, track.cooldownRenderer, track) end
                        if track.activeRenderer then pushTimer(track.activeTimer, track.activeRenderer, track) end
                    end
                end
            end
        end)
    end
end

local function ensureTrack(unit, entry)
    local u = unitState(unit)
    local track = u.tracks[entry.key]
    local def = sensorDefFor(entry)
    if not def then return nil end
    local cd = Core:GetCooldownSeconds(entry, unit)
    if cd <= 0 then return nil end
    local active = Core.GetActiveSeconds and Core:GetActiveSeconds(entry, unit, def.active) or (def.active or 0)
    local cdRounded = max(1, ceil(cd))
    local activeRounded = active > 0 and max(1, ceil(active)) or 0
    if not track then
        track = {
            unit=unit, entry=entry, def=def, sig=signature(def), live=true,
            cooldown=newTimer(cdRounded),
        }
        if activeRounded > 0 then track.activeTimer = newTimer(activeRounded) end
        u.tracks[entry.key] = track
    else
        track.entry, track.def, track.live = entry, def, true
        if track.cooldown.seconds ~= cdRounded then
            hideRenderer(track.cooldownRenderer)
            -- Keep the encoded cast timestamp, including protected values. Changing
            -- its encoding unit would reinterpret that timestamp, so retain u/P.
            track.cooldown.seconds = cdRounded
            track.cooldownRenderer = nil
        end
        local oldActive = track.activeTimer and track.activeTimer.seconds or 0
        if oldActive ~= activeRounded then
            hideRenderer(track.activeRenderer)
            track.activeRenderer = nil
            track.activeTimer = activeRounded > 0 and newTimer(activeRounded) or nil
            track.primed = false
        end
    end
    ensureTrackSensor(track)
    return track
end

function SS:Refresh()
    if not self.available then return end
    if InCombatLockdown and InCombatLockdown() then pendingRefresh=true return end
    pendingRefresh=false
    ensureDrivers()

    local wantedZone = {}
    for i=1,4 do
        local unit = 'party'..i
        local u = unitState(unit)
        local guid = unitExistsSafe(unit) and guidOf(unit) or nil
        if u.guid ~= guid then
            u.guid = guid
            for _, tr in pairs(u.tracks) do
                tr.primed = false
                tr.suppressEdgeUntil = nil
                clearTimer(tr.cooldown, Now())
                if tr.activeTimer then clearTimer(tr.activeTimer, Now()) end
            end
        end
        for _, tr in pairs(u.tracks) do tr.live=false end
        if guid then
            for _, entry in ipairs(ns.Spells or {}) do
                if Core:ShouldShow(entry, unit, false) and self:Supports(entry) then
                    local tr = ensureTrack(unit, entry)
                    if tr and tr.def.zone then wantedZone[zoneKey(tr.def)] = tr.def end
                end
            end
        end
        for _, tr in pairs(u.tracks) do
            if not tr.live then
                parkSensor(tr.sensor)
                parkSensor(tr.shortSensor)
                parkSensor(tr.excludeSensor)
                parkSensor(tr.targetSensor)
            end
        end
    end

    for sig, def in pairs(wantedZone) do
        for _, unit in ipairs(ALL_UNITS) do
            if unitExistsSafe(unit) then ensureZoneSensor(unit, def) end
        end
    end

    for i=1,4 do
        local u=units['party'..i]
        if u and u.guid then
            u.hold=GetTime()+0.10
            u.reads=READS_AFTER
        end
    end
    wakeDriver()
end

function SS:OnAuraEvent(unit, updateInfo)
    if not self.available or not unit then return end
    if not auraPayloadChurns(updateInfo) then return end
    local now = GetTime()
    local direct = units[unit]
    if direct then
        direct.hold = now + HOLD
        direct.reads = READS_AFTER
    end
    -- Externals can appear on any recipient, so an aura change on player/party can affect a
    -- different source row. Wake all rows that own a zone/external sensor.
    if type(unit) == 'string' and (unit == 'player' or unit:match('^party%d$')) then
        for _, u in pairs(units) do
            local hasZone=false
            for _, tr in pairs(u.tracks) do if tr.live and tr.def.zone then hasZone=true break end end
            if hasZone then u.hold=now+HOLD u.reads=READS_AFTER end
        end
    end
    wakeDriver()
end

function SS:OnUnitTarget(unit)
    if not self.available or type(unit) ~= 'string' then return end
    local u = units[unit]
    if not u then return end
    local now = GetTime()
    local touched = false
    for _, tr in pairs(u.tracks) do
        if tr.live and tr.targetSensor then
            pcall(tr.targetSensor.UpdateAllAuras, tr.targetSensor)
            touched = true
        end
    end
    if touched then
        u.hold = now
        u.reads = READS_AFTER
        wakeDriver()
    end
end

-- If Blizzard leaves a party spellID readable, use it as an exact zero-latency fallback.
-- In restricted combat it may be secret; in that case this function deliberately does nothing
-- and the AuraContainer path remains authoritative.
function SS:OnSpellcastSucceeded(unit, spellID)
    if not self.available or secret(spellID) or type(spellID) ~= 'number' then return end
    local u = units[unit]
    if not u then return end
    local n, now = Now(), GetTime()
    for _, tr in pairs(u.tracks) do
        if tr.live then
            local hit = false
            for _, id in ipairs(tr.entry.spellIDs or {}) do
                if id == spellID then hit = true break end
            end
            if hit then
                startPlain(tr.cooldown, n)
                if tr.activeTimer then startPlain(tr.activeTimer, n) end
                tr.suppressEdgeUntil = now + 1.25
                if tr.cooldownRenderer then pushTimer(tr.cooldown, tr.cooldownRenderer, tr) end
                if tr.activeRenderer then pushTimer(tr.activeTimer, tr.activeRenderer, tr) end
                if PartyCDLensDB and PartyCDLensDB.debug then
                    print('|cff69ccf0PartyCDLens secure cast:|r', unit, tr.entry.name, spellID)
                end
            end
        end
    end
end

hideRenderer = function(r)
    if not r then return end
    for k=1,2 do
        if r.host[k] then r.host[k]:SetAlpha(0) end
        if r.cover[k] then r.cover[k]:SetAlpha(0) end
    end
end

local function releaseIcon(icon)
    if not icon then return end
    local old = icon._secureTracker
    if old then
        if old.icon == icon then old.icon = nil end
        hideRenderer(old.cooldownRenderer)
        hideRenderer(old.activeRenderer)
        icon._secureTracker = nil
    end
    if icon.secureGlowGate then icon.secureGlowGate:SetAlpha(0) end
    if icon.text then icon.text:Show() end
    if icon.chargeText then icon.chargeText:SetText('') end
    for _, edge in ipairs(icon.border or {}) do edge:SetColorTexture(0,0,0,1) end
end

local function setChargeCapacity(icon, unit, entry)
    if not icon or not icon.chargeText then return end
    local n = Core:GetMaxCharges(entry, unit)
    -- This is CAPACITY from inspected talents, not a claim that all charges are currently ready.
    icon.chargeText:SetText(n > 1 and ('×' .. tostring(n)) or '')
end

function SS:BindIcon(unit, entry, icon)
    if not icon then return false end
    if icon._secureTracker and (icon._secureTracker.unit ~= unit or icon._secureTracker.entry.key ~= entry.key) then
        releaseIcon(icon)
    end
    if not self:Supports(entry) or type(unit) ~= 'string' or not unit:match('^party%d$') then
        releaseIcon(icon)
        return false
    end
    local track = ensureTrack(unit, entry)
    if not track then return false end
    icon._secureTracker = track
    track.icon = icon

    if icon.glow then icon.glow:Hide() end
    if icon.glowAnim and icon.glowAnim:IsPlaying() then icon.glowAnim:Stop() end
    if icon.activeSweep then icon.activeSweep:Hide() end
    if icon.activeText then icon.activeText:Hide() end
    if icon.text then icon.text:SetText('') icon.text:Hide() end
    if icon.shade then icon.shade:Hide() end
    setChargeCapacity(icon, unit, entry)
    if icon.badge then icon.badge:SetText('~') end
    for _, edge in ipairs(icon.border or {}) do edge:SetColorTexture(0,0,0,1) end

    local size = icon:GetWidth() or (PartyCDLensDB and PartyCDLensDB.iconSize) or 24
    local textSize = max(9, floor(size*0.46))
    if not track.cooldownRenderer or track.cooldownRenderer.icon ~= icon then
        track.cooldownRenderer = newRenderer(icon, track.cooldown, 'cooldown')
    end
    dressRenderer(track.cooldownRenderer, size, textSize)
    if track.activeTimer then
        if not track.activeRenderer or track.activeRenderer.icon ~= icon then
            track.activeRenderer = newRenderer(icon, track.activeTimer, 'active')
        end
        dressRenderer(track.activeRenderer, size, textSize)
    end
    local g = makeGlowGate(icon)
    g.glow:SetSize(size*1.75,size*1.75)
    if track.primed then
        g:SetAlpha(pick(track.lastCur, track.lastDual, track.lastShort, 1, 0))
    else
        g:SetAlpha(0)
    end
    pushTimer(track.cooldown, track.cooldownRenderer, track)
    if track.activeRenderer then pushTimer(track.activeTimer, track.activeRenderer, track) end
    return true
end

function SS:Owns(unit, entry, icon)
    return icon and icon._secureTracker and icon._secureTracker.unit == unit and icon._secureTracker.entry.key == entry.key
end

function SS:RefreshIcon(unit, entry, icon)
    if not self:Owns(unit, entry, icon) then return false end
    local tr = icon._secureTracker
    icon.texture:SetDesaturated(false)
    icon.texture:SetAlpha(1)
    if icon.text then icon.text:Hide() end
    if icon.shade then icon.shade:Hide() end
    if icon.activeSweep then icon.activeSweep:Hide() end
    if icon.activeText then icon.activeText:Hide() end
    setChargeCapacity(icon, unit, entry)
    if icon.badge then icon.badge:SetText('~') end
    local size = icon:GetWidth() or 24
    local textSize = max(9,floor(size*0.46))
    local changed = false
    if tr.cooldownRenderer then changed = dressRenderer(tr.cooldownRenderer, size, textSize) or changed end
    if tr.activeRenderer then changed = dressRenderer(tr.activeRenderer, size, textSize) or changed end
    if changed then
        pushTimer(tr.cooldown, tr.cooldownRenderer, tr)
        if tr.activeRenderer then pushTimer(tr.activeTimer, tr.activeRenderer, tr) end
    end
    return true
end

-- A challenge reset must clear the visual engine too; Core state is separate.
function SS:ResetTimers()
    local n = Now()
    for _, u in pairs(units) do
        for _, tr in pairs(u.tracks) do
            clearTimer(tr.cooldown, n)
            if tr.activeTimer then clearTimer(tr.activeTimer, n) end
            tr.primed = false
            tr.suppressEdgeUntil = nil
            if tr.cooldownRenderer then pushTimer(tr.cooldown, tr.cooldownRenderer, tr) end
            if tr.activeRenderer then pushTimer(tr.activeTimer, tr.activeRenderer, tr) end
        end
    end
end

function SS:OnRosterOrSpecChanged()
    C_Timer.After(0.05, function() SS:Refresh() end)
end

function SS:OnCombatEnded()
    if pendingRefresh then self:Refresh() end
end

function SS:Initialize()
    if not self.available then return end
    ensureDrivers()
    C_Timer.After(0.8, function() SS:Refresh() end)
end

function SS:PrintStatus()
    print('|cff69ccf0PartyCDLens secure sensor engine|r')
    print('available:', self.available and 'yes' or 'NO', '| door:', door.state, door.off and string.format('%.1e',door.off) or '', self.failure or '')
    local n=0
    for _, u in pairs(units) do for _, tr in pairs(u.tracks) do if tr.live then n=n+1 end end end
    print('live exact-aura trackers:', n)
    print('Key exact sensors include Meta/Blur, Paladin wings/BoP/Freedom/Aura Mastery, Priest Fade/GS/Hymn/Apotheosis/Ultimate Penitence, Darkglare and Imp Lord.')
    print('Party charge REMAINING counts are not decoded; inspected maximum capacity is shown as ×2 where applicable.')
end
