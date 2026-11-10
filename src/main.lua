
-- =============================================================================
-- File:        main.lua
-- Project:     RS3 AFK Vitals Tint
-- Author:      John Crawley
-- Description:
--   Monitors player health and prayer points and displays transparent,
--   click-through warning overlays when resources become low.
--   Supports persistent settings, prayer stabilisation and one-shot preview.
-- =============================================================================
local settings = require("settings")
local logic = require("logic")
local SettingsUI = require("settings_ui")
SettingsUI.load(settings)

local EVENT_NAME = "afkVitalsTint"
local HEALTH_COLOUR = { 1.0, 0.04, 0.04 }
local PRAYER_COLOUR = { 0.05, 0.25, 1.0 }

-- Plugin state.
local redRectangle = nil
local blueRectangle = nil
local splitMode = false
local prayerSource = nil
local prayerState = logic.newReadingState()
local missingHPLogged = false
local missingPrayerLogged = false
local lastLoggedPrayer = nil
local hasLoggedPrayer = false
local simulationElapsedSeconds = 0

local prayerFilterOptions = {
    maxMissingSamples = settings.prayerMaxMissingSamples,
    riseConfirmationSamples = settings.prayerRiseConfirmationSamples,
    confirmRiseAboveFraction = settings.prayerConfirmRiseAboveFraction,
}

-- Safely retrieves numeric game variables.
local function readVariable(domainName, variableName)
    local success, result = pcall(function()
        local domain = var[domainName]
        local entry = domain and domain[variableName]
        return entry and entry.value or nil
    end)
    if success and type(result) == "number" then
        return result
    end
    return nil
end

-- Locks the Prayer scale to prevent inconsistent readings.
local function resolvePrayerScale(rawValue, maximumPrayer)
    if settings.prayerValueScale == 1 or settings.prayerValueScale == 10 then
        return settings.prayerValueScale
    end
    return rawValue > maximumPrayer * 1.5 and 10 or 1
end

-- Selects and remembers the first valid Prayer source.
local function selectPrayerSource(maximumPrayer)
    for _, candidate in ipairs(settings.prayerVariableCandidates) do
        local rawValue = readVariable(candidate.domain, candidate.name)
        if rawValue ~= nil then
            local scale = resolvePrayerScale(rawValue, maximumPrayer)
            local points = rawValue / scale
            if logic.isValidReading(points, maximumPrayer) then
                prayerSource = {
                    domain = candidate.domain,
                    name = candidate.name,
                    scale = scale,
                }
                log(
                    "AFK Vitals Tint: Prayer source="
                    .. candidate.domain .. "." .. candidate.name
                    .. ", scale=" .. tostring(scale)
                    .. ", raw=" .. tostring(rawValue)
                )
                return points, rawValue
            end
        end
    end
    return nil, nil
end

-- Reads Prayer without switching source during gameplay.
local function readPrayerPoints(maximumPrayer)
    if prayerSource == nil then
        return selectPrayerSource(maximumPrayer)
    end
    local rawValue = readVariable(prayerSource.domain, prayerSource.name)
    if rawValue == nil then
        return nil, nil
    end
    local points = rawValue / prayerSource.scale
    if not logic.isValidReading(points, maximumPrayer) then
        return nil, rawValue
    end
    return points, rawValue
end

-- Hides both overlays.
local function hideTints()
    if redRectangle ~= nil then redRectangle.hidden = true end
    if blueRectangle ~= nil then blueRectangle.hidden = true end
end

-- Destroys overlay components safely.
local function destroyTints()
    if redRectangle ~= nil then
        pcall(function() redRectangle:Destroy() end)
    end
    if blueRectangle ~= nil then
        pcall(function() blueRectangle:Destroy() end)
    end
    redRectangle = nil
    blueRectangle = nil
    splitMode = false
end

-- Resets cached resource readings and simulation progress.
local function resetReadings()
    prayerSource = nil
    prayerState = logic.newReadingState()
    missingHPLogged = false
    missingPrayerLogged = false
    lastLoggedPrayer = nil
    hasLoggedPrayer = false
    simulationElapsedSeconds = 0
end

-- Creates a transparent, click-through warning rectangle.
local function createTint(parent, colour)
    local rectangle = ui.Rectangle.new(parent)
    rectangle:SetPos(0, 0)
    rectangle:SetSize(0, 0, 1.0, 1.0)
    rectangle.colour = Vector4.new(colour[1], colour[2], colour[3], 0)
    rectangle.fill = true
    rectangle.clickthrough = true
    rectangle.hidden = true
    return rectangle
end

-- Initialises warning overlays on the plugin UI layer.
local function ensureTints()
    if redRectangle ~= nil and blueRectangle ~= nil then
        return true
    end
    local parent = ui.Interfaces:GetComponent(
        id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP
    )
    if parent == nil then return false end
    destroyTints()
    redRectangle = createTint(parent, HEALTH_COLOUR)
    blueRectangle = createTint(parent, PRAYER_COLOUR)
    return true
end

-- Splits the screen when both resource warnings are active.
local function setSplitMode(shouldSplit)
    if splitMode == shouldSplit then return end
    splitMode = shouldSplit
    if shouldSplit then
        redRectangle:SetPos(0, 0)
        redRectangle:SetSize(0, 0, 0.5, 1.0)
        blueRectangle:SetPos(0, 0, 0.5, 0)
        blueRectangle:SetSize(0, 0, 0.5, 1.0)
    else
        redRectangle:SetPos(0, 0)
        redRectangle:SetSize(0, 0, 1.0, 1.0)
        blueRectangle:SetPos(0, 0)
        blueRectangle:SetSize(0, 0, 1.0, 1.0)
    end
end

-- Updates overlay visibility and opacity.
local function updateTint(rectangle, colour, opacity)
    rectangle.hidden = opacity <= 0
    if opacity > 0 then
        rectangle.colour = Vector4.new(
            colour[1], colour[2], colour[3], opacity
        )
    end
end

-- Calculates Prayer warning opacity with full strength at 20%.
local function calculatePrayerOpacity(current, maximum)
    if not logic.isValidReading(current, maximum) then return 0 end
    local startFraction = settings.prayerWarningStart
    local fullStrength = settings.prayerFullStrengthAt
    if type(startFraction) ~= "number"
        or type(fullStrength) ~= "number"
        or startFraction <= fullStrength
        or startFraction > 1
        or fullStrength < 0 then
        return 0
    end
    local remaining = math.max(0, math.min(1, current / maximum))
    local urgency = math.max(0, math.min(
        1, (startFraction - remaining) / (startFraction - fullStrength)
    ))
    return math.max(0, math.min(1, settings.maxOpacity * urgency))
end

-- Runs one resource-depletion preview without changing game stats.
-- Disables simulation automatically after the full duration.
local function simulateResources(maximumHP, maximumPrayer)
    local configuration = settings.simulation
    local duration = math.max(tonumber(configuration.cycleSeconds) or 30, 1)
    local interval = (tonumber(settings.updateEveryLogicTicks) or 1) / 50
    simulationElapsedSeconds = math.min(
        duration, simulationElapsedSeconds + interval
    )
    local remaining = 1 - simulationElapsedSeconds / duration
    local hp, prayer = maximumHP, maximumPrayer

    if configuration.resource == "hp" or configuration.resource == "both" then
        hp = maximumHP * remaining
    end
    if configuration.resource == "prayer" or configuration.resource == "both" then
        prayer = maximumPrayer * remaining
    end

    if simulationElapsedSeconds >= duration then
        configuration.enabled = false
        simulationElapsedSeconds = 0
        SettingsUI.syncPreview(false)
        log("AFK Vitals Tint: preview complete; real monitoring resumed.")
    end
    return hp, prayer
end

-- Reads live or simulated resources and updates the overlays.
local function refresh()
    if not Player.IsAvailable() then
        hideTints()
        resetReadings()
        if settings.simulation.enabled then
            settings.simulation.enabled = false
            SettingsUI.syncPreview(false)
        end
        return
    end
    if not ensureTints() then return end

    local maximumHP = Player.GetLevelCapped(SkillType.HITPOINTS) * 100
    local maximumPrayer = Player.GetLevelCapped(SkillType.PRAYER) * 10
    local hp, prayer

    if settings.simulation and settings.simulation.enabled then
        hp, prayer = simulateResources(maximumHP, maximumPrayer)
    else
        hp = logic.normalisePoints(
            readVariable("VarPlayer", "LIFEPOINTS"),
            maximumHP
        )
        local prayerSample, prayerRaw = readPrayerPoints(maximumPrayer)
        prayer = logic.stabiliseReading(
            prayerState,
            prayerSample,
            maximumPrayer,
            prayerFilterOptions
        )

        if hp == nil and not missingHPLogged then
            log("AFK Vitals Tint: HP reading unavailable; red warning disabled.")
            missingHPLogged = true
        end
        if prayer == nil and not missingPrayerLogged then
            log("AFK Vitals Tint: Prayer reading unavailable; blue warning disabled.")
            missingPrayerLogged = true
        end
        if settings.debugPrayerReadings
            and (not hasLoggedPrayer or prayerRaw ~= lastLoggedPrayer) then
            local sourceName = prayerSource
                and (prayerSource.domain .. "." .. prayerSource.name)
                or "unavailable"
            log(
                "AFK Vitals Tint: Prayer source=" .. sourceName
                .. ", raw=" .. tostring(prayerRaw)
                .. ", scale=" .. tostring(prayerSource and prayerSource.scale)
                .. ", displayed=" .. tostring(prayer)
            )
            lastLoggedPrayer = prayerRaw
            hasLoggedPrayer = true
        end
    end

    local hpOpacity = 0
    if settings.enableHPWarning then
        hpOpacity = logic.warningOpacity(
            hp, maximumHP, settings.hpWarningStart, settings.maxOpacity
        )
    end

    local prayerOpacity = 0
    if settings.enablePrayerWarning then
        prayerOpacity = calculatePrayerOpacity(prayer, maximumPrayer)
    end

    setSplitMode(
        settings.splitWhenBothLow and hpOpacity > 0 and prayerOpacity > 0
    )
    updateTint(redRectangle, HEALTH_COLOUR, hpOpacity)
    updateTint(blueRectangle, PRAYER_COLOUR, prayerOpacity)
end

-- Applies settings changes immediately.
local function onSettingsChanged()
    simulationElapsedSeconds = 0
    prayerState = logic.newReadingState()
    refresh()
end

-- Builds the settings interface when its layer becomes available.
local function onSettingsLayerReady(event)
    if event == nil or event.component == nil then
        log("AFK Vitals Tint: settings layer unavailable.")
        return
    end
    SettingsUI.render(event.component, settings, onSettingsChanged)
end

-- Refreshes warning overlays at the configured interval.
local function onLogicTick(event)
    if event.logicTick % settings.updateEveryLogicTicks == 0 then
        refresh()
    end
end

-- Clears cached resources after a game-state change.
local function onGameStateChanged()
    destroyTints()
    resetReadings()
    settings.simulation.enabled = false
    SettingsUI.syncPreview(false)
end

-- Releases resources and removes event subscriptions.
function PluginShutdown()
    Event.Logic.Unsubscribe(EVENT_NAME)
    Event.GameStateChanged.Unsubscribe(EVENT_NAME)
    Event.SettingsLayerReady.Unsubscribe(EVENT_NAME)
    destroyTints()
    resetReadings()
end

-- Plugin initialisation.
Event.Logic.Subscribe(EVENT_NAME, onLogicTick)
Event.GameStateChanged.Subscribe(EVENT_NAME, onGameStateChanged)
Event.SettingsLayerReady.Subscribe(EVENT_NAME, onSettingsLayerReady)

if settings.simulation and settings.simulation.enabled then
    log("AFK Vitals Tint: simulation mode enabled; game stats unchanged.")
else
    log("AFK Vitals Tint loaded; HP and Prayer monitoring active.")
end
