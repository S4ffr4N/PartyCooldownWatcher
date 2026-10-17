local addonName, ns = ...
local Core = ns.Core

local Options = {}
ns.Options = Options

local frame
local rows = {}

local function createButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 80, height or 22)
    b:SetText(text)
    return b
end

local function createCheck(parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(label)
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() == true)
        Core:RebuildAll()
    end)
    cb.Refresh = function(self) self:SetChecked(getter() == true) end
    return cb
end

local function modeColor(mode)
    if mode == "ON" then return "|cff55ff55ON|r" end
    if mode == "OFF" then return "|cffff5555OFF|r" end
    return "|cffddddddAUTO|r"
end

local function nextMode(mode)
    if mode == "AUTO" then return "ON" end
    if mode == "ON" then return "OFF" end
    return "AUTO"
end

local function displayName(entry)
    local suffix = ""
    if entry.reliability == "experimental" then suffix = suffix.." |cffffaa33[experimental]|r" end
    if entry.recommended then suffix = suffix.." |cff66ff99[recommended]|r" end
    if entry.category == "offensive" then suffix = suffix.." |cffb8a8ff[offensive]|r" end
    return entry.name..suffix
end

function Options:BuildSpellRows(scrollChild)
    for _, r in ipairs(rows) do r:Hide() end
    wipe(rows)

    local y = -4
    local classBuckets = {}
    for _, class in ipairs(ns.ClassOrder) do table.insert(classBuckets, class) end
    table.insert(classBuckets, "ITEM")

    for _, class in ipairs(classBuckets) do
        local spells = ns.SpellsByClass[class]
        if spells and #spells > 0 then
            local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            header:SetPoint("TOPLEFT", 8, y)
            header:SetText(class == "ITEM" and "Items" or (ns.ClassNames[class] or class))
            table.insert(rows, header)
            y = y - 24

            table.sort(spells, function(a,b) return a.name < b.name end)
            for _, entry in ipairs(spells) do
                local row = CreateFrame("Frame", nil, scrollChild)
                row:SetSize(660, 24)
                row:SetPoint("TOPLEFT", 4, y)
                row.entry = entry

                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20,20)
                row.icon:SetPoint("LEFT", 4, 0)
                local texture
                for _, id in ipairs(entry.spellIDs or {}) do
                    if C_Spell and C_Spell.GetSpellTexture then
                        local ok, t = pcall(C_Spell.GetSpellTexture, id)
                        if ok and t then texture=t break end
                    end
                end
                if not texture and entry.itemID and C_Item and C_Item.GetItemIconByID then
                    local ok,t=pcall(C_Item.GetItemIconByID,entry.itemID); if ok then texture=t end
                end
                row.icon:SetTexture(texture or 134400)

                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.label:SetWidth(500)
                row.label:SetJustifyH("LEFT")
                row.label:SetText(displayName(entry))

                row.mode = createButton(row, "AUTO", 70, 20)
                row.mode:SetPoint("RIGHT", -4, 0)
                row.mode:SetScript("OnClick", function(self)
                    local current = Core:GetSpellMode(entry.key)
                    Core:SetSpellMode(entry.key, nextMode(current))
                end)
                row.mode.Refresh = function(self)
                    local mode = Core:GetSpellMode(entry.key)
                    self:SetText(modeColor(mode))
                end

                table.insert(rows, row)
                y = y - 24
            end
            y = y - 8
        end
    end
    scrollChild:SetHeight(math.max(1, -y + 12))
end

function Options:Refresh()
    if not frame then return end
    frame.cbOff:Refresh()
    frame.cbExp:Refresh()
    frame.cbRec:Refresh()
    frame.sizeValue:SetText(tostring(PartyCDLensDB.iconSize or 24))
    for _, r in ipairs(rows) do
        if r.mode and r.mode.Refresh then r.mode:Refresh() end
    end
end

function Options:Initialize()
    if frame then return end
    frame = CreateFrame("Frame", "PartyCDLensOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(720, 650)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", 16, -10)
    frame.title:SetText("PartyCDLens 0.9.0-alpha")

    local info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 18, -38)
    info:SetWidth(680)
    info:SetJustifyH("LEFT")
    info:SetText("AUTO = use class/spec/talent/item detection. ON = force the icon. OFF = never show it. '?' means UNKNOWN, never 'ready'. v0.6 adds separate opt-in-able Elemental, Enhancement, and Restoration Ascendance rows; the exact sensor path is used where available. Open Blizzard Edit Mode to drag the PartyCDLens offset handle on its grid.")

    frame.cbOff = createCheck(frame, "Show offensive cooldowns", function() return PartyCDLensDB.showOffensives end, function(v) PartyCDLensDB.showOffensives=v end)
    frame.cbOff:SetPoint("TOPLEFT", 18, -86)
    frame.cbExp = createCheck(frame, "Show experimental/unproven trackers", function() return PartyCDLensDB.showExperimental end, function(v) PartyCDLensDB.showExperimental=v end)
    frame.cbExp:SetPoint("TOPLEFT", 220, -86)
    frame.cbRec = createCheck(frame, "Show healer-useful extras I added", function() return PartyCDLensDB.showRecommendedExtras end, function(v) PartyCDLensDB.showRecommendedExtras=v end)
    frame.cbRec:SetPoint("TOPLEFT", 490, -86)

    local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", 18, -119)
    sizeLabel:SetText("Icon size:")
    local minus = createButton(frame, "-", 28, 22)
    minus:SetPoint("LEFT", sizeLabel, "RIGHT", 8, 0)
    frame.sizeValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.sizeValue:SetPoint("LEFT", minus, "RIGHT", 9, 0)
    local plus = createButton(frame, "+", 28, 22)
    plus:SetPoint("LEFT", frame.sizeValue, "RIGHT", 9, 0)
    minus:SetScript("OnClick", function()
        PartyCDLensDB.iconSize = math.max(14, (PartyCDLensDB.iconSize or 24)-1)
        Core:RebuildAll()
    end)
    plus:SetScript("OnClick", function()
        PartyCDLensDB.iconSize = math.min(48, (PartyCDLensDB.iconSize or 24)+1)
        Core:RebuildAll()
    end)

    local rescan = createButton(frame, "Rescan specs/talents", 145, 22)
    rescan:SetPoint("TOPRIGHT", -18, -116)
    rescan:SetScript("OnClick", function() Core:RefreshRoster() end)

    local resetPos = createButton(frame, "Reset icon offset", 125, 22)
    resetPos:SetPoint("RIGHT", rescan, "LEFT", -8, 0)
    resetPos:SetScript("OnClick", function()
        if ns.EditMode then ns.EditMode:ResetOffset() else
            PartyCDLensDB.offsetX = -4; PartyCDLensDB.offsetY = 0; Core:RebuildAll()
        end
    end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -153)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(660)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    frame.scrollChild = child

    self:BuildSpellRows(child)
    frame:SetScript("OnShow", function() Options:Refresh() end)
    table.insert(UISpecialFrames, "PartyCDLensOptionsFrame")
    self:Refresh()
end

function Options:Toggle()
    if not frame then self:Initialize() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
