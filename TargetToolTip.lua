-- TargetToolTip: Show targeting information in unit tooltips

local addonName, addon = ...

-- ========================================
-- CONFIGURATION
-- ========================================
local CONFIG = {
    CACHE_TIMEOUT = 0.75,
    CACHE_CLEANUP_INTERVAL = 5,
    COLORS = {
        LABEL = "|cffff6600",
        ME = "|cff00ff00",
        FRIENDLY = "|cff00ff00",
        NEUTRAL = "|cffffff00",
        HOSTILE = "|cffff0000",
        DEFAULT = "|cffffffff"
    }
}

-- Default settings for realm name removal
local DEFAULTS = {
    hideRealmRaid = true,
    hideRealmParty = true,
}

-- ========================================
-- CACHE SYSTEM
-- ========================================
local Cache = {
    data = {},
    
    Get = function(self, guid)
        local cached = self.data[guid]
        if not cached then return nil end
        
        if GetTime() - cached.timestamp > CONFIG.CACHE_TIMEOUT then
            self.data[guid] = nil
            return nil
        end
        
        return cached.data
    end,
    
    Set = function(self, guid, data)
        self.data[guid] = {
            data = data,
            timestamp = GetTime()
        }
    end,
    
    Clean = function(self)
        local currentTime = GetTime()
        for guid, cached in pairs(self.data) do
            if currentTime - cached.timestamp > CONFIG.CACHE_TIMEOUT then
                self.data[guid] = nil
            end
        end
    end
}

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================
local function StripRealm(name)
    if not name then return "" end
    return name:match("^([^-]+)") or name
end

local function FindUnitByGUID(guid)
    -- Check common units first (most likely)
    local commonUnits = {"mouseover", "target", "focus"}
    for _, unitToken in ipairs(commonUnits) do
        if UnitGUID(unitToken) == guid then
            return unitToken
        end
    end
    
    -- Check party members
    if IsInGroup() then
        for i = 1, 4 do
            local partyUnit = "party" .. i
            if UnitGUID(partyUnit) == guid then
                return partyUnit
            end
        end
    end
    
    -- Check raid members
    if IsInRaid() then
        for i = 1, 40 do
            local raidUnit = "raid" .. i
            if UnitGUID(raidUnit) == guid then
                return raidUnit
            end
        end
    end
    
    -- Check nameplates
    for i = 1, 40 do
        local nameplateUnit = "nameplate" .. i
        if UnitGUID(nameplateUnit) == guid then
            return nameplateUnit
        end
    end
    
    return nil
end

local function GetUnitColor(unit)
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                return string.format("|cff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
            end
        end
    else
        local reaction = UnitReaction(unit, "player")
        if reaction then
            if reaction >= 5 then return CONFIG.COLORS.FRIENDLY
            elseif reaction == 4 then return CONFIG.COLORS.NEUTRAL
            else return CONFIG.COLORS.HOSTILE
            end
        end
    end
    
    return CONFIG.COLORS.DEFAULT
end

-- ========================================
-- TARGETING SCAN FUNCTIONS
-- ========================================
local function IsUnitTargeting(scanUnit, targetUnit)
    if not UnitExists(scanUnit) then return false end
    
    local scanTarget = scanUnit .. "target"
    return UnitExists(scanTarget) and UnitIsUnit(scanTarget, targetUnit)
end

local function AddTargeter(scanUnit, targeters, checkDuplicates)
    local name = UnitName(scanUnit)
    if not name then return end
    
    name = StripRealm(name)
    
    -- Check for duplicates if requested
    if checkDuplicates then
        for _, targeter in ipairs(targeters) do
            if targeter.name == name then return end
        end
    end
    
    table.insert(targeters, {unit = scanUnit, name = name})
end

local function ScanForTargeters(prefix, count, targetUnit, targeters, checkDuplicates)
    for i = 1, count do
        local scanUnit = prefix .. i
        if IsUnitTargeting(scanUnit, targetUnit) then
            AddTargeter(scanUnit, targeters, checkDuplicates)
        end
    end
end

local function GetUnitsTargetingUnit(targetUnit)
    local targeters = {}
    
    -- Check party (only if not in raid to avoid duplicates)
    if IsInGroup() and not IsInRaid() then
        ScanForTargeters("party", 4, targetUnit, targeters, false)
    end
    
    -- Check raid
    if IsInRaid() then
        ScanForTargeters("raid", 40, targetUnit, targeters, false)
    end
    
    -- Check nameplates (skip in raids for performance)
    if not IsInRaid() then
        ScanForTargeters("nameplate", 40, targetUnit, targeters, true)
    end
    
    return targeters
end

-- ========================================
-- TOOLTIP RENDERING
-- ========================================
local function RenderTargetLine(tooltip, targetUnit)
    if UnitIsUnit(targetUnit, "player") then
        return CONFIG.COLORS.LABEL .. "Target: |r" .. CONFIG.COLORS.ME .. "Me|r"
    end
    
    local targetName = UnitName(targetUnit)
    if not targetName then return "" end
    
    targetName = StripRealm(targetName)
    local color = GetUnitColor(targetUnit)
    
    return CONFIG.COLORS.LABEL .. "Target: |r" .. color .. targetName .. "|r"
end

local function RenderTargetersList(tooltip, targeters)
    local lines = {}
    
    -- Header
    if #targeters == 1 then
        table.insert(lines, CONFIG.COLORS.LABEL .. "Targeted by:|r")
    else
        table.insert(lines, CONFIG.COLORS.LABEL .. "Targeted by " .. #targeters .. " units:|r")
    end
    
    -- Targeters
    for _, targeter in ipairs(targeters) do
        local color = GetUnitColor(targeter.unit)
        table.insert(lines, {text = "  " .. color .. targeter.name .. "|r", coloredName = color .. targeter.name})
    end
    
    return lines
end

local function ApplyTooltipData(tooltip, targetText, targeterLines)
    if targetText and targetText ~= "" then
        tooltip:AddLine(targetText)
    end
    
    if targeterLines and #targeterLines > 0 then
        tooltip:AddLine(" ")
        for _, line in ipairs(targeterLines) do
            if type(line) == "string" then
                tooltip:AddLine(line)
            else
                tooltip:AddLine(line.text)
            end
        end
    end
    
    tooltip:Show()
end

-- ========================================
-- MAIN TOOLTIP HANDLER
-- ========================================
local function AddTargetInfoToTooltip(tooltip, data)
    if not data or not data.guid then return end
    
    -- Try cache first
    local cached = Cache:Get(data.guid)
    if cached then
        ApplyTooltipData(tooltip, cached.targetText, cached.targeterLines)
        return
    end
    
    -- Find unit
    local unit = FindUnitByGUID(data.guid)
    if not unit or not UnitExists(unit) then return end
    
    -- Build tooltip data
    local targetText = ""
    local targeterLines = {}
    
    -- Who is this unit targeting?
    local targetUnit = unit .. "target"
    if UnitExists(targetUnit) then
        targetText = RenderTargetLine(tooltip, targetUnit)
    end
    
    -- Who is targeting this unit?
    local targeters = GetUnitsTargetingUnit(unit)
    if #targeters > 0 then
        targeterLines = RenderTargetersList(tooltip, targeters)
    end
    
    -- Cache for future
    Cache:Set(data.guid, {
        targetText = targetText,
        targeterLines = targeterLines
    })
    
    ApplyTooltipData(tooltip, targetText, targeterLines)
end

-- ========================================
-- INITIALIZATION
-- ========================================
-- Register tooltip processor
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
    if tooltip == GameTooltip then
        AddTargetInfoToTooltip(tooltip, data)
    end
end)

-- Periodic cache cleanup
local cleanupFrame = CreateFrame("Frame")
cleanupFrame:SetScript("OnUpdate", function(self, elapsed)
    self.timeSinceLastCleanup = (self.timeSinceLastCleanup or 0) + elapsed
    
    if self.timeSinceLastCleanup >= CONFIG.CACHE_CLEANUP_INTERVAL then
        Cache:Clean()
        self.timeSinceLastCleanup = 0
    end
end)

-- ========================================
-- REALM NAME REMOVAL (Party & Raid Frames)
-- ========================================
local realmFrame = CreateFrame("Frame")

local function InitializeRealmNameRemoval()
    -- Load settings
    TargetToolTipDB = TargetToolTipDB or CopyTable(DEFAULTS)
    local db = TargetToolTipDB
    
    -- Hide realm names on raid frames (includes party member frames shown in raid-style)
    if db.hideRealmRaid then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            if frame and not frame:IsForbidden() then
                local frameName = frame:GetName()
                if frameName and (frameName:match("^PartyMemberFrame%d") or frameName:match("^CompactRaidFrame%d") or frameName:match("^CompactRaidGroup%dMember%d") or frameName:match("^CompactPartyFrameMember%d")) and frame.unit and frame.name then
                    if UnitIsPlayer(frame.unit) then
                        local unitName = GetUnitName(frame.unit, true)
                        if unitName then
                            frame.name:SetText(unitName:match("[^-]+"))
                        end
                    end
                end
            end
        end)
    end
    
    -- Hide realm names on party frames
    if db.hideRealmParty then
        if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
            hooksecurefunc("UnitFrame_Update", function(frame)
                for activeFrame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                    local unitName = GetUnitName(activeFrame.unit, true)
                    if unitName then
                        activeFrame.name:SetText(unitName:match("[^-]+"))
                    end
                end
            end)
        elseif WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
            hooksecurefunc("UnitFrame_Update", function(frame)
                if frame and not frame:IsForbidden() then
                    local frameName = frame:GetName()
                    if frameName and frameName:match("^PartyMemberFrame%d") and frame.unit and frame.name then
                        local unitName = GetUnitName(frame.unit, true)
                        if unitName then
                            frame.name:SetText(unitName:match("[^-]+"))
                        end
                    end
                end
            end)
        end
    end
end

realmFrame:RegisterEvent("ADDON_LOADED")
realmFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName == addonName then
        InitializeRealmNameRemoval()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
