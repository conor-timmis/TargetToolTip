-- UIEssentials
local addonName, addon = ...

-- ========================================
-- CONSTANTS
-- ========================================
local CONSTANTS = {
    CACHE_TIMEOUT = 0.75,
    CACHE_CLEANUP_INTERVAL = 5,
    MAX_PARTY_MEMBERS = 4,
    MAX_RAID_MEMBERS = 40,
    MAX_NAMEPLATES = 40,
    
    COLORS = {
        LABEL = "|cffff6600",
        ME = "|cff00ff00",
        FRIENDLY = "|cff00ff00",
        NEUTRAL = "|cffffff00",
        HOSTILE = "|cffff0000",
        DEFAULT = "|cffffffff"
    },
    
    REALM_FRAME_PATTERNS = {
        "^PartyMemberFrame%d",
        "^CompactRaidFrame%d",
        "^CompactRaidGroup%dMember%d",
        "^CompactPartyFrameMember%d"
    }
}

local DEFAULTS = {
    enableTooltips = true,
    hideRealmRaid = true,
    hideRealmParty = true,
    showItemLevelDecimals = true,
    showCursorHighlight = false,
}

-- ========================================
-- SETTINGS MODULE
-- ========================================
local SettingsManager = {}

function SettingsManager:Initialize()
    UIEssentials = UIEssentials or {}
    
    -- Merge defaults with saved settings
    for key, value in pairs(DEFAULTS) do
        if UIEssentials[key] == nil then
            UIEssentials[key] = value
        end
    end
    
    return UIEssentials
end

function SettingsManager:Get(key)
    return UIEssentials and UIEssentials[key]
end

function SettingsManager:Set(key, value)
    if UIEssentials then
        UIEssentials[key] = value
    end
end

-- ========================================
-- CACHE MODULE
-- ========================================
local Cache = {}
Cache.data = {}

function Cache:Get(guid)
    local cached = self.data[guid]
    if not cached then return nil end
    
    if GetTime() - cached.timestamp > CONSTANTS.CACHE_TIMEOUT then
        self.data[guid] = nil
        return nil
    end
    
    return cached.data
end

function Cache:Set(guid, data)
    self.data[guid] = {
        data = data,
        timestamp = GetTime()
    }
end

function Cache:Clean()
    local currentTime = GetTime()
    for guid, cached in pairs(self.data) do
        if currentTime - cached.timestamp > CONSTANTS.CACHE_TIMEOUT then
            self.data[guid] = nil
        end
    end
end

function Cache:StartCleanupTimer()
    local frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceLastCleanup = (self.timeSinceLastCleanup or 0) + elapsed
        
        if self.timeSinceLastCleanup >= CONSTANTS.CACHE_CLEANUP_INTERVAL then
            Cache:Clean()
            self.timeSinceLastCleanup = 0
        end
    end)
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================
local Utils = {}

function Utils.StripRealm(name)
    if not name then return "" end
    return name:match("^([^-]+)") or name
end

function Utils.GetUnitColor(unit)
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                return string.format("|cff%02x%02x%02x", 
                    classColor.r * 255, 
                    classColor.g * 255, 
                    classColor.b * 255)
            end
        end
    else
        local reaction = UnitReaction(unit, "player")
        if reaction then
            if reaction >= 5 then return CONSTANTS.COLORS.FRIENDLY
            elseif reaction == 4 then return CONSTANTS.COLORS.NEUTRAL
            else return CONSTANTS.COLORS.HOSTILE
            end
        end
    end
    
    return CONSTANTS.COLORS.DEFAULT
end

function Utils.FindUnitByGUID(guid)
    -- Check common units first (most likely)
    local commonUnits = {"mouseover", "target", "focus"}
    for _, unitToken in ipairs(commonUnits) do
        if UnitGUID(unitToken) == guid then
            return unitToken
        end
    end
    
    -- Check party members
    if IsInGroup() then
        for i = 1, CONSTANTS.MAX_PARTY_MEMBERS do
            local partyUnit = "party" .. i
            if UnitGUID(partyUnit) == guid then
                return partyUnit
            end
        end
    end
    
    -- Check raid members
    if IsInRaid() then
        for i = 1, CONSTANTS.MAX_RAID_MEMBERS do
            local raidUnit = "raid" .. i
            if UnitGUID(raidUnit) == guid then
                return raidUnit
            end
        end
    end
    
    -- Check nameplates
    for i = 1, CONSTANTS.MAX_NAMEPLATES do
        local nameplateUnit = "nameplate" .. i
        if UnitGUID(nameplateUnit) == guid then
            return nameplateUnit
        end
    end
    
    return nil
end

function Utils.MatchesFramePattern(frameName)
    if not frameName then return false end
    
    for _, pattern in ipairs(CONSTANTS.REALM_FRAME_PATTERNS) do
        if frameName:match(pattern) then
            return true
        end
    end
    
    return false
end

-- ========================================
-- TARGETING SCANNER MODULE
-- ========================================
local TargetingScanner = {}

function TargetingScanner.IsUnitTargeting(scanUnit, targetUnit)
    if not UnitExists(scanUnit) then return false end
    
    local scanTarget = scanUnit .. "target"
    return UnitExists(scanTarget) and UnitIsUnit(scanTarget, targetUnit)
end

function TargetingScanner.AddTargeter(scanUnit, targeters, checkDuplicates)
    local name = UnitName(scanUnit)
    if not name then return end
    
    name = Utils.StripRealm(name)
    
    -- Check for duplicates if requested
    if checkDuplicates then
        for _, targeter in ipairs(targeters) do
            if targeter.name == name then return end
        end
    end
    
    table.insert(targeters, {unit = scanUnit, name = name})
end

function TargetingScanner.ScanUnits(prefix, count, targetUnit, targeters, checkDuplicates)
    for i = 1, count do
        local scanUnit = prefix .. i
        if TargetingScanner.IsUnitTargeting(scanUnit, targetUnit) then
            TargetingScanner.AddTargeter(scanUnit, targeters, checkDuplicates)
        end
    end
end

function TargetingScanner.GetUnitsTargeting(targetUnit)
    local targeters = {}
    
    -- Check party (only if not in raid to avoid duplicates)
    if IsInGroup() and not IsInRaid() then
        TargetingScanner.ScanUnits("party", CONSTANTS.MAX_PARTY_MEMBERS, targetUnit, targeters, false)
    end
    
    -- Check raid
    if IsInRaid() then
        TargetingScanner.ScanUnits("raid", CONSTANTS.MAX_RAID_MEMBERS, targetUnit, targeters, false)
    end
    
    -- Check nameplates (skip in raids for performance)
    if not IsInRaid() then
        TargetingScanner.ScanUnits("nameplate", CONSTANTS.MAX_NAMEPLATES, targetUnit, targeters, true)
    end
    
    return targeters
end

-- ========================================
-- TOOLTIP RENDERER MODULE
-- ========================================
local TooltipRenderer = {}

function TooltipRenderer.RenderTargetLine(targetUnit)
    if UnitIsUnit(targetUnit, "player") then
        return CONSTANTS.COLORS.LABEL .. "Target: |r" .. CONSTANTS.COLORS.ME .. "Me|r"
    end
    
    local targetName = UnitName(targetUnit)
    if not targetName then return "" end
    
    targetName = Utils.StripRealm(targetName)
    local color = Utils.GetUnitColor(targetUnit)
    
    return CONSTANTS.COLORS.LABEL .. "Target: |r" .. color .. targetName .. "|r"
end

function TooltipRenderer.RenderTargetersList(targeters)
    local lines = {}
    
    -- Header
    if #targeters == 1 then
        table.insert(lines, CONSTANTS.COLORS.LABEL .. "Targeted by:|r")
    else
        table.insert(lines, CONSTANTS.COLORS.LABEL .. "Targeted by " .. #targeters .. " units:|r")
    end
    
    -- Targeters
    for _, targeter in ipairs(targeters) do
        local color = Utils.GetUnitColor(targeter.unit)
        table.insert(lines, "  " .. color .. targeter.name .. "|r")
    end
    
    return lines
end

function TooltipRenderer.ApplyTooltip(tooltip, targetText, targeterLines)
    if targetText and targetText ~= "" then
        tooltip:AddLine(targetText)
    end
    
    if targeterLines and #targeterLines > 0 then
        tooltip:AddLine(" ")
        for _, line in ipairs(targeterLines) do
            tooltip:AddLine(line)
        end
    end
    
    tooltip:Show()
end

-- ========================================
-- TOOLTIP HANDLER MODULE
-- ========================================
local TooltipHandler = {}

function TooltipHandler.AddTargetInfo(tooltip, data)
    if not data or not data.guid then return end
    if not SettingsManager:Get("enableTooltips") then return end
    
    -- Try cache first
    local cached = Cache:Get(data.guid)
    if cached then
        TooltipRenderer.ApplyTooltip(tooltip, cached.targetText, cached.targeterLines)
        return
    end
    
    -- Find unit
    local unit = Utils.FindUnitByGUID(data.guid)
    if not unit or not UnitExists(unit) then return end
    
    -- Build tooltip data
    local targetText = ""
    local targeterLines = {}
    
    -- Who is this unit targeting?
    local targetUnit = unit .. "target"
    if UnitExists(targetUnit) then
        targetText = TooltipRenderer.RenderTargetLine(targetUnit)
    end
    
    -- Who is targeting this unit?
    local targeters = TargetingScanner.GetUnitsTargeting(unit)
    if #targeters > 0 then
        targeterLines = TooltipRenderer.RenderTargetersList(targeters)
    end
    
    -- Cache for future
    Cache:Set(data.guid, {
        targetText = targetText,
        targeterLines = targeterLines
    })
    
    TooltipRenderer.ApplyTooltip(tooltip, targetText, targeterLines)
end

function TooltipHandler.Initialize()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if tooltip == GameTooltip then
            TooltipHandler.AddTargetInfo(tooltip, data)
        end
    end)
end

-- ========================================
-- REALM NAME REMOVAL MODULE
-- ========================================
local RealmNameRemoval = {}

function RealmNameRemoval.StripRealmFromFrame(frame)
    if not frame or frame:IsForbidden() then return end
    if not frame.unit or not frame.name then return end
    if not UnitIsPlayer(frame.unit) then return end
    
    local unitName = GetUnitName(frame.unit, true)
    if unitName then
        frame.name:SetText(unitName:match("[^-]+"))
    end
end

function RealmNameRemoval.InitializeRaidFrames()
    if not SettingsManager:Get("hideRealmRaid") then return end
    
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if Utils.MatchesFramePattern(frame:GetName()) then
            RealmNameRemoval.StripRealmFromFrame(frame)
        end
    end)
end

function RealmNameRemoval.InitializePartyFrames()
    if not SettingsManager:Get("hideRealmParty") then return end
    
    if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        hooksecurefunc("UnitFrame_Update", function()
            for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                local unitName = GetUnitName(frame.unit, true)
                if unitName then
                    frame.name:SetText(unitName:match("[^-]+"))
                end
            end
        end)
    elseif WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
        hooksecurefunc("UnitFrame_Update", function(frame)
            if frame and not frame:IsForbidden() and frame:GetName() then
                if frame:GetName():match("^PartyMemberFrame%d") and frame.unit and frame.name then
                    local unitName = GetUnitName(frame.unit, true)
                    if unitName then
                        frame.name:SetText(unitName:match("[^-]+"))
                    end
                end
            end
        end)
    end
end

function RealmNameRemoval.Initialize()
    RealmNameRemoval.InitializeRaidFrames()
    RealmNameRemoval.InitializePartyFrames()
end

-- ========================================
-- ITEM LEVEL DECIMAL MODULE
-- ========================================
local ItemLevelDecimal = {}
ItemLevelDecimal.isHooked = false
ItemLevelDecimal.isUpdating = false

function ItemLevelDecimal.UpdateDisplay()
    -- Force update the item level display
    if CharacterStatsPane and CharacterStatsPane.ItemLevelFrame and CharacterStatsPane.ItemLevelFrame.Value then
        local itemLevelText = CharacterStatsPane.ItemLevelFrame.Value
        local _, avgItemLevelEquipped = GetAverageItemLevel()
        
        if avgItemLevelEquipped and avgItemLevelEquipped > 0 then
            ItemLevelDecimal.isUpdating = true
            if SettingsManager:Get("showItemLevelDecimals") then
                itemLevelText:SetText(string.format("%.2f", avgItemLevelEquipped))
            else
                itemLevelText:SetText(math.floor(avgItemLevelEquipped))
            end
            ItemLevelDecimal.isUpdating = false
        end
    end
end

function ItemLevelDecimal.SetupHook()
    -- Only hook once
    if ItemLevelDecimal.isHooked then return true end
    
    -- Wait for CharacterStatsPane to exist
    if not CharacterStatsPane or not CharacterStatsPane.ItemLevelFrame or not CharacterStatsPane.ItemLevelFrame.Value then
        return false
    end
    
    local itemLevelText = CharacterStatsPane.ItemLevelFrame.Value
    
    -- Hook SetText to automatically add decimals to item level display
    hooksecurefunc(itemLevelText, "SetText", function(self, text)
        -- Check if feature is enabled
        if not SettingsManager:Get("showItemLevelDecimals") then return end
        
        -- Prevent infinite recursion
        if ItemLevelDecimal.isUpdating then return end
        
        -- Only modify if it's a whole number without decimals
        if text and tonumber(text) and not string.find(text, "%.") then
            local _, avgItemLevelEquipped = GetAverageItemLevel()
            
            if avgItemLevelEquipped and avgItemLevelEquipped > 0 then
                local roundedValue = math.floor(avgItemLevelEquipped)
                
                -- Only replace if text matches the rounded item level
                if tonumber(text) == roundedValue then
                    ItemLevelDecimal.isUpdating = true
                    self:SetText(string.format("%.2f", avgItemLevelEquipped))
                    ItemLevelDecimal.isUpdating = false
                end
            end
        end
    end)
    
    ItemLevelDecimal.isHooked = true
    return true
end

function ItemLevelDecimal.TrySetupHook()
    if not ItemLevelDecimal.SetupHook() then
        -- Retry if frame not ready yet
        C_Timer.After(0.5, ItemLevelDecimal.TrySetupHook)
    else
        -- Hook is ready, update display immediately if character frame is shown
        if CharacterFrame and CharacterFrame:IsShown() then
            ItemLevelDecimal.UpdateDisplay()
        end
    end
end

function ItemLevelDecimal.Initialize()
    -- Only initialize if feature is enabled
    if not SettingsManager:Get("showItemLevelDecimals") then return end
    
    -- Setup hook when character frame is shown
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", function()
            ItemLevelDecimal.TrySetupHook()
            -- Update display when character frame is shown
            C_Timer.After(0.1, ItemLevelDecimal.UpdateDisplay)
        end)
        
        -- Setup immediately if character frame is already open
        if CharacterFrame:IsShown() then
            ItemLevelDecimal.TrySetupHook()
        end
    end
end

-- ========================================
-- CURSOR HIGHLIGHT MODULE
-- ========================================
local CursorHighlight = {}
CursorHighlight.frame = nil
CursorHighlight.scaleTicker = nil

-- Constants
local CURSOR_SIZE = 13.25
local CURSOR_COLOR = {0, 1, 0, 1.0} -- Solid green
local SCALE_UPDATE_INTERVAL = 1.0 -- Update scale cache every second

function CursorHighlight.CreateHighlightFrame()
    if CursorHighlight.frame then return end
    
    -- Use TOOLTIP
    local frame = CreateFrame("Frame", "UIEssentialsCursorHighlight", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100) -- Much lower level, still visible but safer
    frame:SetWidth(CURSOR_SIZE)
    frame:SetHeight(CURSOR_SIZE)
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:Hide()
    
    -- Create solid filled square
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(unpack(CURSOR_COLOR))
    fill:SetAllPoints(frame)
    
    -- Cache scale and track last position to avoid unnecessary updates
    frame.cachedScale = UIParent:GetEffectiveScale()
    frame.lastX = 0
    frame.lastY = 0
    
    CursorHighlight.frame = frame
end

function CursorHighlight.StopTracking()
    local frame = CursorHighlight.frame
    if not frame then return end
    
    frame:Hide()
    frame:SetScript("OnUpdate", nil)
    
    -- Clean up scale ticker
    if CursorHighlight.scaleTicker then
        CursorHighlight.scaleTicker:Cancel()
        CursorHighlight.scaleTicker = nil
    end
end

function CursorHighlight.StartTracking()
    if not SettingsManager:Get("showCursorHighlight") then
        CursorHighlight.StopTracking()
        return
    end
    
    CursorHighlight.CreateHighlightFrame()
    local frame = CursorHighlight.frame
    
    -- Cache references for performance
    local uiParent = UIParent
    local cachedScale = frame.cachedScale
    
    frame:Show()
    
    -- Update position only when cursor moves (performance optimization)
    frame:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        
        -- Convert to UI coordinates
        x = x / cachedScale
        y = y / cachedScale
        
        -- Only update if position changed (avoids unnecessary frame operations)
        if x ~= self.lastX or y ~= self.lastY then
            self.lastX = x
            self.lastY = y
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", uiParent, "BOTTOMLEFT", x, y)
        end
    end)
    
    -- Periodically refresh scale cache (only if ticker doesn't exist)
    if not CursorHighlight.scaleTicker then
        CursorHighlight.scaleTicker = C_Timer.NewTicker(SCALE_UPDATE_INTERVAL, function()
            if frame and frame:IsShown() then
                local newScale = UIParent:GetEffectiveScale()
                if newScale ~= cachedScale then
                    cachedScale = newScale
                    frame.cachedScale = cachedScale
                    -- Force position update by resetting last position
                    frame.lastX = 0
                    frame.lastY = 0
                end
            else
                -- Clean up ticker if frame is hidden
                if CursorHighlight.scaleTicker then
                    CursorHighlight.scaleTicker:Cancel()
                    CursorHighlight.scaleTicker = nil
                end
            end
        end)
    end
end

function CursorHighlight.Initialize()
    if SettingsManager:Get("showCursorHighlight") then
        CursorHighlight.StartTracking()
    end
end

-- ========================================
-- OPTIONS PANEL MODULE
-- ========================================
local OptionsPanel = {}
OptionsPanel.frame = nil

-- UI Constants
local PANEL_WIDTH = 420
local PANEL_HEIGHT = 300
local BEIGE_BG = {0.85, 0.82, 0.75, 0.95}
local BEIGE_BORDER = {0.65, 0.60, 0.50, 1.0}

-- Text Colors
local COLOR_TITLE = {0.15, 0.10, 0.05, 1.0}
local COLOR_VERSION = {0.35, 0.28, 0.20, 1.0}
local COLOR_HEADER = {0.25, 0.18, 0.12, 1.0}
local COLOR_LABEL = {1.0, 0.85, 0.0, 1.0}
local COLOR_HINT = {0.45, 0.35, 0.25, 1.0}

-- Helper function to create a checkbox
local function CreateCheckbox(parent, label, tooltip, x, y, getFunc, setFunc)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", x, y)
    check:SetSize(22, 22)
    
    local labelText = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT", check, "RIGHT", 3, 0)
    labelText:SetText(label)
    labelText:SetTextColor(unpack(COLOR_LABEL))
    
    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if setFunc then setFunc(checked) end
    end)
    
    check:SetScript("OnEnter", function(self)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    
    check:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Update checkbox state
    check.UpdateState = function()
        local checked = getFunc and getFunc() or false
        check:SetChecked(checked)
    end
    
    check.UpdateState()
    return check
end

-- Helper function to create a section header
local function CreateSectionHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, y)
    header:SetTextColor(unpack(COLOR_HEADER))
    header:SetText(text)
    return header
end

function OptionsPanel.CreatePanel()
    if OptionsPanel.frame then return end
    
    -- Create main frame with backdrop template
    local frame = CreateFrame("Frame", "UIEssentialsOptionsPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(500, -500, -300, 300)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    
    -- Make it a system frame (ESC closes it)
    table.insert(UISpecialFrames, "UIEssentialsOptionsPanel")
    
    -- Border with backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(unpack(BEIGE_BG))
    frame:SetBackdropBorderColor(unpack(BEIGE_BORDER))
    
    -- Drag handling
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("UIEssentials")
    title:SetTextColor(unpack(COLOR_TITLE))
    
    -- Version
    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    version:SetText("Version 1.3.1")
    version:SetTextColor(unpack(COLOR_VERSION))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 12, -45)
    content:SetPoint("BOTTOMRIGHT", -12, 40)
    
    -- Tooltip Features Section
    local yOffset = -5
    CreateSectionHeader(content, "Tooltip Features", 8, yOffset)
    yOffset = yOffset - 18
    
    local enableTooltips = CreateCheckbox(content, "Show targeting info in tooltips", 
        "Display who is targeting what in unit tooltips", 16, yOffset,
        function() return SettingsManager:Get("enableTooltips") end,
        function(val) SettingsManager:Set("enableTooltips", val) end
    )
    yOffset = yOffset - 22
    
    -- Character Features Section
    yOffset = yOffset - 8
    CreateSectionHeader(content, "Character Features", 8, yOffset)
    yOffset = yOffset - 18
    
    local itemLevelDecimals = CreateCheckbox(content, "Show item level decimals", 
        "Display item level with decimal precision in character frame", 16, yOffset,
        function() return SettingsManager:Get("showItemLevelDecimals") end,
        function(val) SettingsManager:Set("showItemLevelDecimals", val) end
    )
    yOffset = yOffset - 22
    
    -- UI Features Section
    yOffset = yOffset - 8
    CreateSectionHeader(content, "UI Features", 8, yOffset)
    yOffset = yOffset - 18
    
    local cursorHighlight = CreateCheckbox(content, "Show green cursor highlight", 
        "Display a green square at your cursor position", 16, yOffset,
        function() return SettingsManager:Get("showCursorHighlight") end,
        function(val) 
            SettingsManager:Set("showCursorHighlight", val)
            if val then
                CursorHighlight.StartTracking()
            else
                CursorHighlight.StopTracking()
            end
        end
    )
    yOffset = yOffset - 22
    
    -- Realm Name Removal Section
    yOffset = yOffset - 8
    CreateSectionHeader(content, "Realm Name Removal", 8, yOffset)
    yOffset = yOffset - 18
    
    local hideRealmRaid = CreateCheckbox(content, "Hide realm names in raid frames", 
        "Remove realm names from raid unit frames", 16, yOffset,
        function() return SettingsManager:Get("hideRealmRaid") end,
        function(val) SettingsManager:Set("hideRealmRaid", val) end
    )
    yOffset = yOffset - 22
    
    local hideRealmParty = CreateCheckbox(content, "Hide realm names in party frames", 
        "Remove realm names from party unit frames", 16, yOffset,
        function() return SettingsManager:Get("hideRealmParty") end,
        function(val) SettingsManager:Set("hideRealmParty", val) end
    )
    yOffset = yOffset - 22
    
    -- Reload button
    local reloadBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reloadBtn:SetSize(90, 26)
    reloadBtn:SetPoint("BOTTOMRIGHT", -12, 8)
    reloadBtn:SetText("Reload UI")
    reloadBtn:SetScript("OnClick", ReloadUI)
    
    local reloadText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reloadText:SetPoint("RIGHT", reloadBtn, "LEFT", -8, 0)
    reloadText:SetText("Please /reload to apply ANY changes")
    reloadText:SetTextColor(unpack(COLOR_HINT))
    
    -- Store checkboxes for updates
    frame.checkboxes = {
        enableTooltips = enableTooltips,
        itemLevelDecimals = itemLevelDecimals,
        cursorHighlight = cursorHighlight,
        hideRealmRaid = hideRealmRaid,
        hideRealmParty = hideRealmParty
    }
    
    -- Update function
    frame.UpdateCheckboxes = function()
        for _, checkbox in pairs(frame.checkboxes) do
            if checkbox.UpdateState then
                checkbox:UpdateState()
            end
        end
    end
    
    -- Center on screen when shown
    frame:SetScript("OnShow", function(self)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        self:UpdateCheckboxes()
    end)
    
    OptionsPanel.frame = frame
end

function OptionsPanel.Show()
    OptionsPanel.CreatePanel()
    if OptionsPanel.frame then
        OptionsPanel.frame:Show()
    end
end

function OptionsPanel.Initialize()
    -- Create panel but don't show it yet
    OptionsPanel.CreatePanel()
    return true
end

-- ========================================
-- SLASH COMMANDS
-- ========================================
local function OpenOptionsPanel()
    OptionsPanel.Show()
end

SlashCmdList.UIESSENTIALS = OpenOptionsPanel
SLASH_UIESSENTIALS1 = "/ue"
SLASH_UIESSENTIALS2 = "/uiessentials"

-- ========================================
-- ADDON INITIALIZATION
-- ========================================
local function Initialize()
    SettingsManager:Initialize()
    TooltipHandler.Initialize()
    RealmNameRemoval.Initialize()
    ItemLevelDecimal.Initialize()
    CursorHighlight.Initialize()
    Cache:StartCleanupTimer()
    OptionsPanel.Initialize()
end

-- Register addon loaded event
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName == addonName then
        Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

