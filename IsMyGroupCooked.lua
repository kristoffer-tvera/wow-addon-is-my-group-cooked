-------------------------------
-- Config
-------------------------------
local LEAVE_MESSAGES = {"Goodbye", "Have a nice evening", "I have to go, sorry!"}

local inspectQueue = {}
local ilvlCache = {} -- [guid] = ilvl number
local queuedGUIDs = {}
local inspectingGUID
local checkActive = false
local manualCheck = false
local settings = {
    filterEnabled = false,
    thresholdPercent = 90
}
local RefreshFrame
local ProcessInspectQueue

local function IsOtherPlayer(unit)
    return UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player")
end

local function HasOtherPlayers()
    local isRaid = IsInRaid()
    local prefix = isRaid and "raid" or "party"
    local count = isRaid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for index = 1, count do
        if IsOtherPlayer(prefix .. index) then
            return true
        end
    end
    return false
end

local function GetClassColor(unit)
    local _, classFile = UnitClass(unit)
    if classFile and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

-------------------------------
-- Main Frame
-------------------------------
local frame = CreateFrame("Frame", "IsMyGroupCookedFrame", UIParent, "BackdropTemplate")
frame:SetSize(400, 280)
frame:SetPoint("CENTER")
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = {
        left = 8,
        right = 8,
        top = 8,
        bottom = 8
    }
})
frame:SetBackdropColor(0, 0, 0, 0.9)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetFrameStrata("DIALOG")
frame:Hide()

-- Title
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -15)
title:SetText("Is My Group Cooked?")

-- Close button (top-right X)
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)
closeBtn:SetScript("OnClick", function()
    checkActive = false
    frame:Hide()
end)

-- Column headers
local headerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerName:SetPoint("TOPLEFT", 20, -42)
headerName:SetText("Name - Realm")
headerName:SetTextColor(1, 0.82, 0)

local headerIlvl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerIlvl:SetPoint("TOPRIGHT", -20, -42)
headerIlvl:SetText("iLvl")
headerIlvl:SetTextColor(1, 0.82, 0)

-- Member rows (max 5 for a party)
local memberRows = {}
for i = 1, 5 do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(360, 20)
    row:SetPoint("TOPLEFT", 20, -58 - (i - 1) * 24)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT")
    row.name:SetWidth(260)
    row.name:SetJustifyH("LEFT")

    row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.ilvl:SetPoint("RIGHT")
    row.ilvl:SetJustifyH("RIGHT")

    row:Hide()
    memberRows[i] = row
end

-- Bottom buttons
local okButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
okButton:SetSize(170, 30)
okButton:SetPoint("BOTTOMLEFT", 15, 15)
okButton:SetText("I guess this'll do")
okButton:SetScript("OnClick", function()
    checkActive = false
    frame:Hide()
end)

local leaveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
leaveButton:SetSize(200, 30)
leaveButton:SetPoint("BOTTOMRIGHT", -15, 15)
leaveButton:SetText("Get me out of here")
leaveButton:SetScript("OnClick", function()
    checkActive = false
    frame:Hide()
    local msg = LEAVE_MESSAGES[math.random(#LEAVE_MESSAGES)]
    local chatType = IsInRaid() and "RAID" or "PARTY"
    SendChatMessage(msg, chatType)
    C_Timer.After(0.5, function()
        C_PartyInfo.LeaveParty()
    end)
end)

local optionsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
optionsButton:SetSize(100, 22)
optionsButton:SetPoint("BOTTOM", 0, 52)
optionsButton:SetText("Options +")

local optionsFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
optionsFrame:SetSize(400, 155)
optionsFrame:SetPoint("TOP", frame, "BOTTOM", 0, 0)
optionsFrame:SetBackdrop(frame:GetBackdrop())
optionsFrame:SetBackdropColor(0, 0, 0, 0.9)
optionsFrame:SetFrameStrata("DIALOG")
optionsFrame:EnableMouse(true)
optionsFrame:Hide()

local optionsClose = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
optionsClose:SetPoint("TOPRIGHT", -5, -5)
optionsClose:SetScript("OnClick", function()
    optionsFrame:Hide()
    optionsButton:SetText("Options +")
end)
optionsButton:SetScript("OnClick", function()
    local expanded = not optionsFrame:IsShown()
    optionsFrame:SetShown(expanded)
    optionsButton:SetText(expanded and "Options -" or "Options +")
end)
frame:SetScript("OnHide", function()
    if not checkActive then
        optionsFrame:Hide()
        optionsButton:SetText("Options +")
    end
end)

local filterCheckbox = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
filterCheckbox:SetPoint("TOPLEFT", 12, -18)
local filterLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
filterLabel:SetPoint("LEFT", filterCheckbox, "RIGHT", 2, 0)
filterLabel:SetWidth(305)
filterLabel:SetJustifyH("LEFT")
filterLabel:SetText("Only show if a group member is below the cutoff")

local thresholdLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
thresholdLabel:SetPoint("TOPLEFT", 22, -57)
local cutoffLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cutoffLabel:SetPoint("TOPLEFT", 22, -120)

local thresholdSlider = CreateFrame("Slider", "IsMyGroupCookedThresholdSlider", optionsFrame, "OptionsSliderTemplate")
thresholdSlider:SetPoint("TOPLEFT", 26, -87)
thresholdSlider:SetSize(348, 17)
thresholdSlider:SetMinMaxValues(1, 100)
thresholdSlider:SetValueStep(1)
thresholdSlider:SetObeyStepOnDrag(true)
IsMyGroupCookedThresholdSliderLow:SetText("1%")
IsMyGroupCookedThresholdSliderHigh:SetText("100%")
IsMyGroupCookedThresholdSliderText:SetText("")

local function UpdateOptions()
    local _, equipped = GetAverageItemLevel()
    filterCheckbox:SetChecked(settings.filterEnabled)
    thresholdLabel:SetText(string.format("Below %d%% of your equipped item level", settings.thresholdPercent))
    cutoffLabel:SetText(string.format("Cutoff: %.1f ilvl (yours: %.1f)", equipped * settings.thresholdPercent / 100,
        equipped))
end

filterCheckbox:SetScript("OnClick", function(self)
    settings.filterEnabled = self:GetChecked() and true or false
    if checkActive then
        RefreshFrame()
    end
end)
thresholdSlider:SetScript("OnValueChanged", function(self, value)
    settings.thresholdPercent = math.floor(value + 0.5)
    UpdateOptions()
    if checkActive then
        RefreshFrame()
    end
end)
thresholdSlider:SetValue(settings.thresholdPercent)
optionsFrame:SetScript("OnShow", UpdateOptions)

-------------------------------
-- Item Level Helper
-------------------------------
local function GetUnitItemLevel(unit)
    if UnitIsUnit(unit, "player") then
        local _, equipped = GetAverageItemLevel()
        return math.floor(equipped)
    end

    local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
    if ilvl and ilvl > 0 then
        return ilvl
    end
    return nil
end

-------------------------------
-- Populate / Refresh
-------------------------------
RefreshFrame = function()
    UpdateOptions()
    if not IsInGroup() or not HasOtherPlayers() then
        checkActive = false
        frame:Hide()
        return
    end

    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local prefix = isRaid and "raid" or "party"

    for i = 1, 5 do
        memberRows[i]:Hide()
    end

    local rowIndex = 0
    local belowCutoff = false

    -- Player row
    rowIndex = rowIndex + 1
    local playerName, playerRealm = UnitFullName("player")
    playerRealm = playerRealm or GetNormalizedRealmName() or ""
    local _, playerEquipped = GetAverageItemLevel()
    memberRows[rowIndex].name:SetText((playerName or "You") .. " - " .. playerRealm)
    memberRows[rowIndex].ilvl:SetText(math.floor(playerEquipped))
    memberRows[rowIndex].name:SetTextColor(GetClassColor("player"))
    memberRows[rowIndex]:Show()

    -- Group member rows
    local maxCheck = isRaid and numMembers or GetNumSubgroupMembers()
    for i = 1, maxCheck do
        local unit = prefix .. i
        if IsOtherPlayer(unit) then
            local guid = UnitGUID(unit)
            local ilvl = guid and ilvlCache[guid]
            if ilvl and ilvl < playerEquipped * settings.thresholdPercent / 100 then
                belowCutoff = true
            end

            if not ilvl and guid and not queuedGUIDs[guid] and CanInspect(unit) then
                queuedGUIDs[guid] = true
                table.insert(inspectQueue, unit)
            end

            if rowIndex < 5 then
                rowIndex = rowIndex + 1
                local name, realm = UnitFullName(unit)
                realm = realm or ""
                if realm == "" then
                    realm = GetNormalizedRealmName() or ""
                end

                memberRows[rowIndex].name:SetText((name or "Unknown") .. " - " .. realm)
                memberRows[rowIndex].name:SetTextColor(GetClassColor(unit))
                memberRows[rowIndex].ilvl:SetText(ilvl and tostring(math.floor(ilvl)) or "...")
                memberRows[rowIndex]:Show()
            end
        end
    end

    -- Resize frame height to fit content
    local contentHeight = 60 + (rowIndex * 24) + 85
    frame:SetHeight(math.max(180, contentHeight))
    frame:SetShown(manualCheck or not settings.filterEnabled or belowCutoff)
end

-------------------------------
-- Inspect Queue
-------------------------------
ProcessInspectQueue = function()
    if inspectingGUID or not checkActive then
        return
    end
    while #inspectQueue > 0 do
        local unit = table.remove(inspectQueue, 1)
        if IsOtherPlayer(unit) and CanInspect(unit) then
            local guid = UnitGUID(unit)
            inspectingGUID = guid
            NotifyInspect(unit)
            C_Timer.After(3, function()
                if inspectingGUID == guid then
                    inspectingGUID = nil
                    ProcessInspectQueue()
                end
            end)
            return
        end
    end
end

local inspectHandler = CreateFrame("Frame")
inspectHandler:RegisterEvent("INSPECT_READY")
inspectHandler:SetScript("OnEvent", function(self, event, guid)
    if not guid or guid ~= inspectingGUID then
        return
    end

    -- Find which group unit this GUID belongs to and cache its ilvl now,
    -- because inspect data is only valid for the most-recently-inspected unit.
    local unitToCheck
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitExists(u) and UnitGUID(u) == guid then
                unitToCheck = u
                break
            end
        end
    else
        for i = 1, GetNumGroupMembers() - 1 do
            local u = "party" .. i
            if UnitExists(u) and UnitGUID(u) == guid then
                unitToCheck = u
                break
            end
        end
    end

    if unitToCheck then
        local ilvl = GetUnitItemLevel(unitToCheck)
        if ilvl then
            ilvlCache[guid] = ilvl
        end
    end

    inspectingGUID = nil
    if checkActive then
        RefreshFrame()
    end
    C_Timer.After(1.5, ProcessInspectQueue)
end)

-------------------------------
-- Show Group Check
-------------------------------
local function ShowGroupCheck(manual)
    if not IsInGroup() or not HasOtherPlayers() then
        checkActive = false
        frame:Hide()
        if manual then
            print("|cff00ccffIsMyGroupCooked:|r No other players in your group. Type /cooked options for settings.")
        end
        return
    end

    inspectQueue = {}
    queuedGUIDs = {}
    checkActive = true
    manualCheck = manual and true or false
    RefreshFrame()
    C_Timer.After(0.5, ProcessInspectQueue)
end

-------------------------------
-- Auto-show on Group Join
-------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GROUP_JOINED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:SetScript("OnEvent", function(self, event, category, partyGUID)
    if event == "ADDON_LOADED" then
        if category == "IsMyGroupCooked" then
            if type(IsMyGroupCookedDB) ~= "table" then
                IsMyGroupCookedDB = {}
            end
            settings = IsMyGroupCookedDB
            settings.filterEnabled = settings.filterEnabled == true
            settings.thresholdPercent = math.max(1, math.min(100, tonumber(settings.thresholdPercent) or 90))
            settings.thresholdPercent = math.floor(settings.thresholdPercent + 0.5)
            thresholdSlider:SetValue(settings.thresholdPercent)
            UpdateOptions()
        end
        return
    end
    if event ~= "GROUP_JOINED" then
        if checkActive then
            RefreshFrame()
            ProcessInspectQueue()
        end
        return
    end
    -- Short delay so group info is available
    C_Timer.After(2, function()
        if IsInGroup() then
            ShowGroupCheck()
        end
    end)
end)

-------------------------------
-- Slash Commands
-------------------------------
SLASH_ISMYGROUPCOOKED1 = "/ismygroupcooked"
SLASH_ISMYGROUPCOOKED2 = "/cooked"
SlashCmdList["ISMYGROUPCOOKED"] = function(msg)
    if msg and msg:lower():match("^%s*options%s*$") then
        optionsFrame:Show()
        optionsButton:SetText("Options -")
    else
        ShowGroupCheck(true)
    end
end

print("|cff00ccffIsMyGroupCooked|r loaded. Type /cooked to check your group.")
