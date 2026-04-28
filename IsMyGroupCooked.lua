-------------------------------
-- Config
-------------------------------
local LEAVE_MESSAGES = {"Goodbye", "Have a nice evening", "I have to go, sorry!"}

local inspectQueue = {}
local ilvlCache = {} -- [guid] = ilvl number

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
    frame:Hide()
end)

local leaveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
leaveButton:SetSize(200, 30)
leaveButton:SetPoint("BOTTOMRIGHT", -15, 15)
leaveButton:SetText("Get me out of here")
leaveButton:SetScript("OnClick", function()
    frame:Hide()
    local msg = LEAVE_MESSAGES[math.random(#LEAVE_MESSAGES)]
    local chatType = IsInRaid() and "RAID" or "PARTY"
    SendChatMessage(msg, chatType)
    C_Timer.After(0.5, function()
        C_PartyInfo.LeaveParty()
    end)
end)

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
        return math.floor(ilvl)
    end
    return nil
end

-------------------------------
-- Populate / Refresh
-------------------------------
local function RefreshFrame()
    if not IsInGroup() then
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
    local maxCheck = isRaid and numMembers or (numMembers - 1)
    for i = 1, maxCheck do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            rowIndex = rowIndex + 1
            if rowIndex > 5 then
                break
            end

            local name, realm = UnitFullName(unit)
            realm = realm or ""
            if realm == "" then
                realm = GetNormalizedRealmName() or ""
            end

            local ilvl = GetUnitItemLevel(unit)
            if not ilvl then
                local guid = UnitGUID(unit)
                if guid and ilvlCache[guid] then
                    ilvl = ilvlCache[guid]
                end
            end
            memberRows[rowIndex].name:SetText((name or "Unknown") .. " - " .. realm)
            memberRows[rowIndex].name:SetTextColor(GetClassColor(unit))
            memberRows[rowIndex].ilvl:SetText(ilvl and tostring(ilvl) or "...")
            memberRows[rowIndex]:Show()

            if not ilvl and CanInspect(unit) then
                table.insert(inspectQueue, unit)
            end
        end
    end

    -- Resize frame height to fit content
    local contentHeight = 60 + (rowIndex * 24) + 55
    frame:SetHeight(math.max(180, contentHeight))
end

-------------------------------
-- Inspect Queue
-------------------------------
local function ProcessInspectQueue()
    if #inspectQueue > 0 then
        local unit = table.remove(inspectQueue, 1)
        if UnitExists(unit) and CanInspect(unit) then
            NotifyInspect(unit)
        end
        if #inspectQueue > 0 then
            C_Timer.After(1.5, ProcessInspectQueue)
        end
    end
end

local inspectHandler = CreateFrame("Frame")
inspectHandler:RegisterEvent("INSPECT_READY")
inspectHandler:SetScript("OnEvent", function(self, event, guid)
    if not guid then
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

    if frame:IsShown() then
        RefreshFrame()
    end
end)

-------------------------------
-- Show Group Check
-------------------------------
local function ShowGroupCheck()
    if not IsInGroup() then
        print("|cff00ccffIsMyGroupCooked:|r You're not in a group.")
        return
    end

    inspectQueue = {}
    RefreshFrame()
    frame:Show()
    C_Timer.After(0.5, ProcessInspectQueue)
end

-------------------------------
-- Auto-show on Group Join
-------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GROUP_JOINED")
eventFrame:SetScript("OnEvent", function(self, event, category, partyGUID)
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
    ShowGroupCheck()
end

print("|cff00ccffIsMyGroupCooked|r loaded. Type /cooked to check your group.")
