local addonName, ns = ...
local Core = ns.Core

local UI = {}
ns.UI = UI

local rows = {}
local testAnchor

local function getTextureForEntry(entry)
    for _, id in ipairs(entry.spellIDs or {}) do
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, texture = pcall(C_Spell.GetSpellTexture, id)
            if ok and texture then return texture end
        elseif GetSpellTexture then
            local ok, texture = pcall(GetSpellTexture, id)
            if ok and texture then return texture end
        end
    end
    if entry.itemID and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, entry.itemID)
        if ok and icon then return icon end
    end
    return 134400 -- question mark
end

local function unitFromFrame(frame)
    if not frame then return nil end
    local u = rawget(frame, "unit")
    if type(u) == "string" then return u end
    if frame.GetAttribute then
        local ok, v = pcall(frame.GetAttribute, frame, "unit")
        if ok and type(v) == "string" then return v end
    end
    return nil
end

local function frameMatchesUnit(frame, unit)
    local u = unitFromFrame(frame)
    if not u then return false end
    if u == unit then return true end
    if UnitIsUnit then
        local ok, same = pcall(UnitIsUnit, u, unit)
        if ok and not Core.IsSecret(same) and same == true then return true end
    end
    return false
end

local function scanChildrenForUnit(root, unit, depth)
    if not root or depth > 4 then return nil end
    if frameMatchesUnit(root, unit) then return root end
    if not root.GetChildren then return nil end
    local children = {root:GetChildren()}
    for _, child in ipairs(children) do
        local hit = scanChildrenForUnit(child, unit, depth + 1)
        if hit then return hit end
    end
    return nil
end

function UI:FindPartyFrame(unit)
    -- ElvUI common party button globals.
    for i = 1, 5 do
        local names = {
            "ElvUF_PartyGroup1UnitButton"..i,
            "ElvUF_PartyUnitButton"..i,
            "ElvUF_Party"..i,
        }
        for _, name in ipairs(names) do
            local f = _G[name]
            if f and frameMatchesUnit(f, unit) then return f end
        end
    end

    -- ElvUI headers vary between versions/profiles. Search a few known roots recursively.
    local rootNames = {"ElvUF_Party", "ElvUF_PartyGroup1", "ElvUF_PartyGroup1Header"}
    for _, rootName in ipairs(rootNames) do
        local root = _G[rootName]
        if root then
            local hit = scanChildrenForUnit(root, unit, 0)
            if hit then return hit end
        end
    end

    -- Blizzard compact party frames.
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember"..i]
        if f and frameMatchesUnit(f, unit) then return f end
    end

    if _G.CompactPartyFrame then
        local hit = scanChildrenForUnit(_G.CompactPartyFrame, unit, 0)
        if hit then return hit end
    end

    return nil
end

local function createBorder(frame)
    frame.border = {}
    local thickness = 1
    local function edge(point1, point2, w, h)
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0,0,0,1)
        t:SetPoint(point1)
        t:SetPoint(point2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        table.insert(frame.border, t)
    end
    edge("TOPLEFT", "TOPRIGHT", nil, thickness)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness)
    edge("TOPLEFT", "BOTTOMLEFT", thickness, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", thickness, nil)
end

local function setBorderActive(icon, active)
    for _, t in ipairs(icon.border or {}) do
        if active then t:SetColorTexture(1,0.82,0,1) else t:SetColorTexture(0,0,0,1) end
    end
end

local function createIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetClipsChildren(false)

    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints()
    f.texture:SetTexCoord(0.08,0.92,0.08,0.92)

    f.shade = f:CreateTexture(nil, "OVERLAY")
    f.shade:SetAllPoints()
    f.shade:SetColorTexture(0,0,0,0.48)
    f.shade:Hide()

    -- Separate radial swipe for the *active buff duration*. This is intentionally not the
    -- recharge animation: while a defensive is active, the healer should see how long its
    -- protection remains, then the normal cooldown state takes over.
    f.activeSweep = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.activeSweep:SetAllPoints()
    if f.activeSweep.SetDrawEdge then f.activeSweep:SetDrawEdge(false) end
    if f.activeSweep.SetDrawBling then f.activeSweep:SetDrawBling(false) end
    if f.activeSweep.SetDrawSwipe then f.activeSweep:SetDrawSwipe(true) end
    if f.activeSweep.SetSwipeColor then f.activeSweep:SetSwipeColor(0,0,0,0.55) end
    if f.activeSweep.SetReverse then f.activeSweep:SetReverse(true) end
    f.activeSweep:Hide()

    f.glow = f:CreateTexture(nil, "OVERLAY", nil, 7)
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    f.glow:SetSize(42,42)
    f.glow:Hide()
    f.glowAnim = f.glow:CreateAnimationGroup()
    f.glowAnim:SetLooping("REPEAT")
    local fadeOut = f.glowAnim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1.0)
    fadeOut:SetToAlpha(0.35)
    fadeOut:SetDuration(0.55)
    fadeOut:SetOrder(1)
    local fadeIn = f.glowAnim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.35)
    fadeIn:SetToAlpha(1.0)
    fadeIn:SetDuration(0.55)
    fadeIn:SetOrder(2)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("CENTER", 0, 0)
    f.text:SetJustifyH("CENTER")
    f.text:SetShadowOffset(1,-1)
    f.text:SetTextColor(1,1,1,1)

    f.activeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.activeText:SetPoint("CENTER", 0, 0)
    f.activeText:SetJustifyH("CENTER")
    f.activeText:SetShadowOffset(1,-1)
    f.activeText:SetTextColor(1,1,1,1)
    f.activeText:Hide()

    f.chargeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.chargeText:SetPoint("BOTTOMRIGHT", -1, 0)
    f.chargeText:SetJustifyH("RIGHT")
    f.chargeText:SetShadowOffset(1,-1)
    f.chargeText:SetTextColor(1,1,1,1)
    f.chargeText:SetText("")

    f.badge = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.badge:SetPoint("TOPRIGHT", 1, 2)
    f.badge:SetTextColor(1,0.75,0.15,1)
    f.badge:SetShadowOffset(1,-1)

    createBorder(f)

    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entry.name, 1,1,1)
        local meta = Core:GetMeta(self.unit)
        if meta then
            local spec = ns.SpecNames[meta.specID] or "spec unknown"
            GameTooltip:AddLine((meta.name or self.unit).." - "..spec, 0.8,0.8,0.8)
        end
        local secureOwned = ns.SecureSensors and ns.SecureSensors:Owns(self.unit, self.entry, self)
        local st = Core.StateFor(self.unit, self.entry.key)
        if secureOwned then
            GameTooltip:AddLine("State: rendered by exact protected aura sensor", 0.4,1,0.7, true)
            GameTooltip:AddLine("Blank means unobserved or estimated ready; it does not prove availability. Protected state cannot be read back by Lua.", 0.65,0.8,1, true)
            local maxCharges = Core:GetMaxCharges(self.entry, self.unit)
            if maxCharges > 1 then
                GameTooltip:AddLine("Max charges: "..tostring(maxCharges).." (live remaining-charge count is not decoded yet)", 0.5,0.9,1, true)
            end
            GameTooltip:AddLine("Detection: exact Blizzard AuraContainer spell-ID filter", 0.7,0.7,0.7, true)
        else
            if st.status == "unknown" then
                GameTooltip:AddLine("State: UNKNOWN - do not assume this cooldown is ready.", 1,0.5,0.2, true)
            elseif st.status == "ready" then
                GameTooltip:AddLine(self.entry.consumable and "State: estimated cooldown elapsed; inventory unknown" or "State: ready (inferred)", 0.4,1,0.4)
            elseif st.status == "cooldown" then
                local r = math.max(0, st.readyAt - GetTime())
                GameTooltip:AddLine("State: cooldown ~"..math.ceil(r).."s", 1,0.8,0.3)
            elseif st.status == "active" then
                GameTooltip:AddLine("State: active", 0.4,1,0.4)
            end
            if st.maxCharges and st.maxCharges > 1 then
                local chargeState = st.status == "unknown" and "?" or tostring(st.charges or 0)
                GameTooltip:AddLine("Charges: "..chargeState.."/"..tostring(st.maxCharges), 0.5,0.9,1)
                if st.chargeReadyAts and st.chargeReadyAts[1] and st.chargeReadyAts[1] > GetTime() then
                    GameTooltip:AddLine("Next charge: ~"..math.ceil(st.chargeReadyAts[1] - GetTime()).."s", 0.7,0.85,1)
                end
            end
            if st.active then
                if st.activeUntil and st.activeUntil > GetTime() then
                    GameTooltip:AddLine("Active for ~"..math.ceil(st.activeUntil - GetTime()).."s more", 0.4,1,0.4)
                else
                    GameTooltip:AddLine("Active now", 0.4,1,0.4)
                end
            end
            GameTooltip:AddLine(self.entry.castOnly and "Detection: readable party spell-use events only" or ("Detection: "..self.entry.reliability.."; readable cast fallback"), 0.7,0.7,0.7)
        end
        if not Core:HasDetectionPath(self.entry) then
            GameTooltip:AddLine("No proven filtered-aura detection path yet; this entry will remain UNKNOWN rather than fake READY.", 1,0.45,0.2, true)
        end
        if Core:CooldownIsEstimated(self.entry, self.unit) then
            GameTooltip:AddLine("~ Estimated timer: missing talent information, charges, or conditional reductions can change availability.", 1,0.75,0.2, true)
        end
        if self.entry.warning then
            GameTooltip:AddLine(self.entry.warning, 1,0.55,0.2, true)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f
end

local function createRow(unit)
    if rows[unit] then return rows[unit] end
    local row = CreateFrame("Frame", nil, UIParent)
    row.unit = unit
    row.icons = {}
    row:SetFrameStrata("MEDIUM")
    rows[unit] = row
    return row
end

local function sortedEntriesForUnit(unit)
    local list = {}
    for _, entry in ipairs(ns.Spells) do
        if Core:ShouldShow(entry, unit, false) then table.insert(list, entry) end
    end
    table.sort(list, function(a,b)
        local pa = ns.CategoryPriority[a.category] or 99
        local pb = ns.CategoryPriority[b.category] or 99
        if pa ~= pb then return pa < pb end
        return a.name < b.name
    end)
    return list
end

function UI:RefreshUnit(unit)
    local row = rows[unit] or createRow(unit)
    local entries = sortedEntriesForUnit(unit)
    local size = PartyCDLensDB.iconSize or 24
    local spacing = PartyCDLensDB.spacing or 2

    for i, entry in ipairs(entries) do
        local icon = row.icons[i] or createIcon(row)
        row.icons[i] = icon
        icon.entry = entry
        icon.unit = unit
        icon:SetSize(size, size)
        if icon.glow then icon.glow:SetSize(size * 1.75, size * 1.75) end
        icon.texture:SetTexture(getTextureForEntry(entry))
        if ns.SecureSensors then ns.SecureSensors:BindIcon(unit, entry, icon) end
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        else
            icon:SetPoint("RIGHT", row.icons[i-1], "LEFT", -spacing, 0)
        end
        icon:Show()
    end

    for i = #entries + 1, #row.icons do row.icons[i]:Hide() end
    local width = math.max(1, (#entries * size) + (math.max(0,#entries-1) * spacing))
    row:SetSize(width, size)
    self:UpdateUnitIcons(unit)
end

local function setActiveVisual(icon, active, st, now)
    if active then
        icon.glow:Show()
        if icon.glowAnim and not icon.glowAnim:IsPlaying() then icon.glowAnim:Play() end

        local hasTimer = st.activeStart and st.activeStart > 0 and st.activeUntil and st.activeUntil > st.activeStart
        if hasTimer then
            local duration = st.activeUntil - st.activeStart
            if icon._activeStart ~= st.activeStart or icon._activeDuration ~= duration then
                icon._activeStart = st.activeStart
                icon._activeDuration = duration
                icon.activeSweep:SetCooldown(st.activeStart, duration)
            end
            icon.activeSweep:Show()
            icon.activeText:SetText(tostring(math.max(0, math.ceil(st.activeUntil - now))))
            icon.activeText:Show()
        else
            icon.activeSweep:Hide()
            icon.activeText:SetText("")
            icon.activeText:Hide()
        end
    else
        if icon.glowAnim and icon.glowAnim:IsPlaying() then icon.glowAnim:Stop() end
        icon.glow:SetAlpha(1)
        icon.glow:Hide()
        icon.activeSweep:Hide()
        icon.activeText:SetText("")
        icon.activeText:Hide()
        icon._activeStart = nil
        icon._activeDuration = nil
    end
end

function UI:UpdateUnitIcons(unit)
    local row = rows[unit]
    if not row then return end
    local now = GetTime()
    for _, icon in ipairs(row.icons) do
        if icon:IsShown() and icon.entry then
            local entry = icon.entry
            if ns.SecureSensors and ns.SecureSensors:RefreshIcon(unit, entry, icon) then
                -- The secure sensor renderer owns this icon. Its alpha/status-bar values may
                -- be secret, so ordinary Lua state must not overwrite them.
            else
            local st = Core.StateFor(unit, entry.key)
            local maxCharges = Core:GetMaxCharges(entry, unit)
            st.maxCharges = maxCharges

            setBorderActive(icon, st.active)
            setActiveVisual(icon, st.active, st, now)
            icon.badge:SetText(Core:CooldownIsEstimated(entry, unit) and "~" or "")

            if maxCharges > 1 then
                if st.status == "unknown" then
                    icon.chargeText:SetText("?")
                else
                    icon.chargeText:SetText(tostring(st.charges == nil and maxCharges or st.charges))
                end
            else
                icon.chargeText:SetText("")
            end

            -- While the aura is active, the center number belongs to the active-duration\n            -- countdown. Never cover it with the recharge number.
            if st.active then
                icon.shade:Hide()
                icon.texture:SetDesaturated(false)
                icon.text:SetText("")
            elseif st.status == "unknown" then
                icon.shade:Show()
                icon.texture:SetDesaturated(true)
                icon.text:SetText("?")
            elseif st.status == "cooldown" then
                icon.shade:Show()
                icon.texture:SetDesaturated(true)
                local remaining = math.max(0, st.readyAt - now)
                icon.text:SetText(tostring(math.ceil(remaining)))
            else
                icon.shade:Hide()
                icon.texture:SetDesaturated(false)
                icon.text:SetText("")
            end
            end -- secure renderer / ordinary renderer
        end
    end
end

function UI:UpdateTimers()
    for unit, row in pairs(rows) do
        if row:IsShown() then self:UpdateUnitIcons(unit) end
    end
end

local function ensureTestAnchor()
    if testAnchor then return testAnchor end
    testAnchor = CreateFrame("Frame", "PartyCDLensTestAnchor", UIParent, "BackdropTemplate")
    testAnchor:SetSize(220, 32)
    testAnchor:SetPoint("CENTER", UIParent, "CENTER", 180, 0)
    testAnchor:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    testAnchor:SetBackdropColor(0.06,0.06,0.06,0.85)
    testAnchor:SetBackdropBorderColor(0,0,0,1)
    testAnchor.text = testAnchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    testAnchor.text:SetPoint("CENTER")
    testAnchor.text:SetText("PartyCDLens test anchor")
    testAnchor:Hide()
    return testAnchor
end

function UI:AnchorUnit(unit)
    local row = rows[unit] or createRow(unit)
    row:ClearAllPoints()

    local anchor = self:FindPartyFrame(unit)
    if anchor then
        row:SetPoint("RIGHT", anchor, "LEFT", PartyCDLensDB.offsetX or -4, PartyCDLensDB.offsetY or 0)
        row:Show()
    elseif Core.runtime.testMode then
        local ta = ensureTestAnchor()
        ta:Show()
        local index = tonumber(string.match(unit, "%d+")) or 1
        row:SetPoint("RIGHT", ta, "LEFT", -6, (2.5-index) * ((PartyCDLensDB.iconSize or 24)+4))
        row:Show()
    else
        row:Hide()
    end
end

function UI:ReanchorAll()
    local anyTest = false
    for i = 1,4 do
        local unit = "party"..i
        if UnitExists(unit) then
            self:RefreshUnit(unit)
            self:AnchorUnit(unit)
            if Core.runtime.testMode then anyTest = true end
        elseif rows[unit] then
            rows[unit]:Hide()
        end
    end
    if testAnchor and not anyTest then testAnchor:Hide() end
    if ns.EditMode and ns.EditMode.Refresh then ns.EditMode:Refresh() end
end

function UI:Initialize()
    for i=1,4 do createRow("party"..i) end
    C_Timer.After(0.5, function() UI:ReanchorAll() end)
    C_Timer.After(2.0, function() UI:ReanchorAll() end)
end
