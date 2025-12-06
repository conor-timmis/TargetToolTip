-- TargetToolTip
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
    TargetToolTip = TargetToolTip or {}
    
    -- Merge defaults with saved settings
    for key, value in pairs(DEFAULTS) do
        if TargetToolTip[key] == nil then
            TargetToolTip[key] = value
        end
    end
    
    return TargetToolTip
end

function SettingsManager:Get(key)
    return TargetToolTip and TargetToolTip[key]
end

function SettingsManager:Set(key, value)
    if TargetToolTip then
        TargetToolTip[key] = value
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
    local frame = CreateFrame("Frame", "TargetToolTipCursorHighlight", UIParent)
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

function OptionsPanel.Initialize()
    local category, layout
    local categoryName = "TargetToolTip"
    
    -- Create the layout using the War Within Settings API
    if Settings and Settings.RegisterVerticalLayoutCategory then
        local success, err = pcall(function()
            category, layout = Settings.RegisterVerticalLayoutCategory(categoryName)
            
            -- Tooltip Features Section
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Tooltip Features"))
            do
                local variable = Settings.RegisterAddOnSetting(category, "TargetToolTip_EnableTooltips", "enableTooltips", TargetToolTip, Settings.VarType.Boolean, "Show targeting info in tooltips", true)
                Settings.CreateCheckbox(category, variable, "Show targeting info in tooltips")
            end
            
            -- Character Features Section  
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Character Features"))
            do
                local variable = Settings.RegisterAddOnSetting(category, "TargetToolTip_ItemLevelDecimals", "showItemLevelDecimals", TargetToolTip, Settings.VarType.Boolean, "Show item level decimals", true)
                Settings.CreateCheckbox(category, variable, "Show item level decimals")
            end
            
            -- UI Features Section
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("UI Features"))
            do
                local variable = Settings.RegisterAddOnSetting(category, "TargetToolTip_ShowCursorHighlight", "showCursorHighlight", TargetToolTip, Settings.VarType.Boolean, "Show green cursor highlight", false)
                Settings.CreateCheckbox(category, variable, "Show green cursor highlight")
            end
            
            -- Realm Name Removal Section
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Realm Name Removal"))
            do
                local variable1 = Settings.RegisterAddOnSetting(category, "TargetToolTip_HideRealmRaid", "hideRealmRaid", TargetToolTip, Settings.VarType.Boolean, "Hide realm names in raid frames", true)
                Settings.CreateCheckbox(category, variable1, "Hide realm names in raid frames")
                
                local variable2 = Settings.RegisterAddOnSetting(category, "TargetToolTip_HideRealmParty", "hideRealmParty", TargetToolTip, Settings.VarType.Boolean, "Hide realm names in party frames", true)
                Settings.CreateCheckbox(category, variable2, "Hide realm names in party frames")
            end
            
            -- Apply Changes Section
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Apply Changes - Type /reload to apply settings"))
            
            Settings.RegisterAddOnCategory(category)
        end)
        
        if success then
            return category
        else
            print("TargetToolTip: Failed to register settings panel -", tostring(err))
            return nil
        end
    else
        print("TargetToolTip: Modern Settings API not available. Using saved variables only.")
        return nil
    end
end

-- ========================================
-- SLASH COMMANDS
-- ========================================
local optionsCategory

local function OpenOptionsPanel()
    if optionsCategory then
        if Settings and Settings.OpenToCategory then
            if optionsCategory.GetID then
                local categoryID = optionsCategory:GetID()
                Settings.OpenToCategory(categoryID)
            else
                Settings.OpenToCategory(optionsCategory)
            end
        elseif SettingsPanel and SettingsPanel.OpenToCategory then
            SettingsPanel:OpenToCategory(optionsCategory)
        elseif SettingsPanel then
            SettingsPanel:Open()
        else
            print("TargetToolTip: Press ESC > Interface Options > AddOns > TargetToolTip")
        end
    else
        if SettingsPanel then
            SettingsPanel:Open()
        else
            print("TargetToolTip: Options panel unavailable")
        end
    end
end

SlashCmdList.TARGETTOOLTIP = OpenOptionsPanel
SLASH_TARGETTOOLTIP1 = "/tt"
SLASH_TARGETTOOLTIP2 = "/targettooltip"

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
    optionsCategory = OptionsPanel.Initialize()
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

