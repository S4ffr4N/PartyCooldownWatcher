local addonName, ns = ...
local UI = ns.UI

local EM = {}
ns.EditMode = EM

local handle
local dragging = false
local dragStartX, dragStartY, startOffsetX, startOffsetY
local hooked = false

local function firstPartyUnit()
    for i=1,4 do
        local unit = "party"..i
        if UnitExists(unit) then return unit end
    end
end

local function refreshHandlePosition()
    if not handle or not handle:IsShown() then return end
    handle:ClearAllPoints()
    local unit = firstPartyUnit()
    local anchor = unit and UI and UI:FindPartyFrame(unit)
    if anchor then
        handle:SetPoint("RIGHT", anchor, "LEFT", PartyCDLensDB.offsetX or -4, PartyCDLensDB.offsetY or 0)
    else
        handle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if handle.label then
        handle.label:SetText(string.format("PartyCDLens cooldowns\nX %d   Y %d", math.floor((PartyCDLensDB.offsetX or -4)+0.5), math.floor((PartyCDLensDB.offsetY or 0)+0.5)))
    end
end

local function updateDrag()
    if not dragging then return end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    local dx = (x - dragStartX) / scale
    local dy = (y - dragStartY) / scale
    PartyCDLensDB.offsetX = startOffsetX + dx
    PartyCDLensDB.offsetY = startOffsetY + dy
    if UI then UI:ReanchorAll() end
    refreshHandlePosition()
end

local function createHandle()
    if handle then return handle end
    handle = CreateFrame("Frame", "PartyCDLensEditModeHandle", UIParent, "BackdropTemplate")
    handle:SetSize(185, 38)
    handle:SetFrameStrata("DIALOG")
    handle:SetClampedToScreen(true)
    handle:SetMovable(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 2,
    })
    handle:SetBackdropColor(0.05, 0.35, 0.70, 0.70)
    handle:SetBackdropBorderColor(1, 0.82, 0.15, 1)

    handle.label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handle.label:SetPoint("CENTER")
    handle.label:SetJustifyH("CENTER")

    handle.help = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    handle.help:SetPoint("BOTTOM", handle, "TOP", 0, 4)
    handle.help:SetText("Drag to offset all PartyCDLens rows from party frames")

    handle:SetScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then return end
        dragging = true
        dragStartX, dragStartY = GetCursorPosition()
        startOffsetX = PartyCDLensDB.offsetX or -4
        startOffsetY = PartyCDLensDB.offsetY or 0
        handle:SetScript("OnUpdate", updateDrag)
    end)
    handle:SetScript("OnDragStop", function()
        dragging = false
        handle:SetScript("OnUpdate", nil)
        -- Keep saved values readable and stable across UI-scale changes.
        PartyCDLensDB.offsetX = math.floor((PartyCDLensDB.offsetX or -4) + 0.5)
        PartyCDLensDB.offsetY = math.floor((PartyCDLensDB.offsetY or 0) + 0.5)
        if UI then UI:ReanchorAll() end
        refreshHandlePosition()
    end)
    handle:Hide()
    return handle
end

function EM:Enter()
    if not PartyCDLensDB then return end
    local h = createHandle()
    h:Show()
    refreshHandlePosition()
end

function EM:Exit()
    dragging = false
    if handle then
        handle:SetScript("OnUpdate", nil)
        handle:Hide()
    end
end

function EM:Refresh()
    refreshHandlePosition()
end

function EM:ResetOffset()
    PartyCDLensDB.offsetX = -4
    PartyCDLensDB.offsetY = 0
    if UI then UI:ReanchorAll() end
    refreshHandlePosition()
end

function EM:Initialize()
    if hooked then return end
    if not EditModeManagerFrame then return end
    hooked = true
    EditModeManagerFrame:HookScript("OnShow", function() EM:Enter() end)
    EditModeManagerFrame:HookScript("OnHide", function() EM:Exit() end)
    if EditModeManagerFrame:IsShown() then EM:Enter() end
end

-- Blizzard does not expose a safe public RegisterSystemFrame API to addons.  Instead of
-- tainting Edit Mode, we place our own drag handle on top of Blizzard's Edit Mode/grid while
-- it is open.  This gives the requested in-grid positioning without touching protected
-- internal registration code.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function() EM:Initialize() end)
    elseif event == "ADDON_LOADED" and name == "Blizzard_EditMode" then
        C_Timer.After(0, function() EM:Initialize() end)
    end
end)
