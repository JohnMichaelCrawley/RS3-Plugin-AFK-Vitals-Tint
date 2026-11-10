
-- =============================================================================
-- File:        main.lua
-- Project:     RS3 AFK Vitals Tint
-- Author:      John Crawley
--
-- Description:
--   Monitors player health and prayer points and displays transparent,
--   click-through warning overlays when either resource becomes low.
--
--   Supports stable prayer readings, configurable warning intensity,
--   split-screen overlays, and visual resource simulation.
--
--   No gameplay actions or player resources are modified.
-- =============================================================================

local settings = require("settings")
local logic = require("logic")

-- =============================================================================
-- Constants
-- =============================================================================

local EVENT_NAME = "afkVitalsTint"

local HEALTH_COLOUR = { 1.0, 0.04, 0.04 }
local PRAYER_COLOUR = { 0.05, 0.25, 1.0 }

-- =============================================================================
-- Plugin State
-- =============================================================================

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

-- =============================================================================
-- Resource Reading
-- =============================================================================

-- Reads a numeric RuneScape variable safely.
-- Missing or inaccessible variables return nil instead of causing an error.
local function readVariable(domainName, variableName)
    local succeeded, result = pcall(function()
        local domain = var[domainName]
        local entry = domain and domain[variableName]

        return entry and entry.value or nil
    end)

    if succeeded and type(result) == "number" then
        return result
    end

    return nil
end

-- Determines the Prayer variable's scale once per session.
-- An explicit scale overrides automatic detection when necessary.
local function resolvePrayerScale(rawValue, maximumPrayer)
    if settings.prayerValueScale == 1
        or settings.prayerValueScale == 10 then
        return settings.prayerValueScale
    end

    if rawValue > maximumPrayer * 1.5 then
        return 10
    end

    return 1
end

-- Selects a valid Prayer variable and remembers its name and scale.
-- Prevents the plugin from switching interpretation during depletion.
local function selectPrayerSource(maximumPrayer)
    for _, candidate in ipairs(settings.prayerVariableCandidates) do
        local rawValue = readVariable(
            candidate.domain,
            candidate.name
        )

        if rawValue ~= nil then
            local scale = resolvePrayerScale(
                rawValue,
                maximumPrayer
            )

            local points = rawValue / scale

            if logic.isValidReading(points, maximumPrayer) then
                prayerSource = {
                    domain = candidate.domain,
                    name = candidate.name,
                    scale = scale,
                }

                log(
                    "AFK Vitals Tint: Prayer source="
                    .. candidate.domain
                    .. "."
                    .. candidate.name
                    .. ", scale="
                    .. tostring(scale)
                    .. ", raw="
                    .. tostring(rawValue)
                )

                return points, rawValue
            end
        end
    end

    return nil, nil
end

-- Reads Prayer using the previously selected variable and scale.
-- Invalid readings are passed as nil to the stability filter.
local function readPrayerPoints(maximumPrayer)
    if prayerSource == nil then
        return selectPrayerSource(maximumPrayer)
    end

    local rawValue = readVariable(
        prayerSource.domain,
        prayerSource.name
    )

    if rawValue == nil then
        return nil, nil
    end

    local points = rawValue / prayerSource.scale

    if not logic.isValidReading(points, maximumPrayer) then
        return nil, rawValue
    end

    return points, rawValue
end

-- =============================================================================
-- Overlay Management
-- =============================================================================

-- Hides both warning overlays without destroying their UI components.
-- Used whenever player information becomes unavailable.
local function hideTints()
    if redRectangle ~= nil then
        redRectangle.hidden = true
    end

    if blueRectangle ~= nil then
        blueRectangle.hidden = true
    end
end

-- Destroys existing overlays and clears their references.
-- Allows components to be recreated after game-state changes.
local function destroyTints()
    if redRectangle ~= nil then
        pcall(function()
            redRectangle:Destroy()
        end)
    end

    if blueRectangle ~= nil then
        pcall(function()
            blueRectangle:Destroy()
        end)
    end

    redRectangle = nil
    blueRectangle = nil
    splitMode = false
end

-- Resets cached Prayer data, logging flags, and simulation progress.
-- Prevents readings from one game session affecting another.
local function resetReadings()
    prayerSource = nil
    prayerState = logic.newReadingState()

    missingHPLogged = false
    missingPrayerLogged = false
    lastLoggedPrayer = nil
    hasLoggedPrayer = false

    simulationElapsedSeconds = 0
end

-- Creates a transparent, click-through UI rectangle.
-- The rectangle provides a visual warning without intercepting clicks.
local function createTint(parent, colour)
    local rectangle = ui.Rectangle.new(parent)

    rectangle:SetPos(0, 0)
    rectangle:SetSize(0, 0, 1.0, 1.0)

    rectangle.colour = Vector4.new(
        colour[1],
        colour[2],
        colour[3],
        0
    )

    rectangle.fill = true
    rectangle.clickthrough = true
    rectangle.hidden = true

    return rectangle
end

-- Creates warning overlays using RuneScape's dedicated plugin UI layer.
-- Existing components are reused whenever possible.
local function ensureTints()
    if redRectangle ~= nil and blueRectangle ~= nil then
        return true
    end

    local parent = ui.Interfaces:GetComponent(
        id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP
    )

    if parent == nil then
        return false
    end

    destroyTints()

    redRectangle = createTint(parent, HEALTH_COLOUR)
    blueRectangle = createTint(parent, PRAYER_COLOUR)

    return true
end

-- Displays red and blue on separate halves when both warnings are active.
-- Otherwise, each warning can occupy the entire game window.
local function setSplitMode(shouldSplit)
    if splitMode == shouldSplit then
        return
    end

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

-- Updates the visibility and transparency of a warning overlay.
-- An opacity of zero hides the overlay entirely.
local function updateTint(rectangle, colour, opacity)
    rectangle.hidden = opacity <= 0

    if opacity > 0 then
        rectangle.colour = Vector4.new(
            colour[1],
            colour[2],
            colour[3],
            opacity
        )
    end
end

-- =============================================================================
-- Warning Calculations
-- =============================================================================

-- Calculates Prayer opacity with a linear intensity curve.
-- Maximum blue intensity is reached before Prayer reaches zero.
local function calculatePrayerOpacity(current, maximum)
    if not logic.isValidReading(current, maximum) then
        return 0
    end

    local startFraction = settings.prayerWarningStart
    local fullStrength = settings.prayerFullStrengthAt

    if type(startFraction) ~= "number"
        or type(fullStrength) ~= "number"
        or startFraction <= fullStrength
        or startFraction > 1
        or fullStrength < 0 then
        return 0
    end

    local remaining = math.max(
        0,
        math.min(1, current / maximum)
    )

    local urgency = math.max(
        0,
        math.min(
            1,
            (startFraction - remaining)
                / (startFraction - fullStrength)
        )
    )

    return math.max(
        0,
        math.min(1, settings.maxOpacity * urgency)
    )
end

-- =============================================================================
-- Resource Simulation
-- =============================================================================

-- Generates simulated resource values for testing warning overlays.
-- Actual player health and Prayer points remain unchanged.
local function simulateResources(maximumHP, maximumPrayer)
    local configuration = settings.simulation

    simulationElapsedSeconds = simulationElapsedSeconds
        + settings.updateEveryLogicTicks / 50

    local remaining = logic.simulatedRemainingFraction(
        simulationElapsedSeconds,
        configuration.cycleSeconds
    )

    local hp = maximumHP
    local prayer = maximumPrayer

    if configuration.resource == "hp"
        or configuration.resource == "both" then
        hp = maximumHP * remaining
    end

    if configuration.resource == "prayer"
        or configuration.resource == "both" then
        prayer = maximumPrayer * remaining
    end

    return hp, prayer
end

-- =============================================================================
-- Warning Updates
-- =============================================================================

-- Retrieves current or simulated resources and updates both overlays.
-- Applies Prayer stabilisation before calculating warning intensity.
local function refresh()
    if not Player.IsAvailable() then
        hideTints()
        resetReadings()
        return
    end

    if not ensureTints() then
        return
    end

    local maximumHP =
        Player.GetLevelCapped(SkillType.HITPOINTS) * 100

    local maximumPrayer =
        Player.GetLevelCapped(SkillType.PRAYER) * 10

    local hp
    local prayer

    if settings.simulation and settings.simulation.enabled then
        hp, prayer = simulateResources(
            maximumHP,
            maximumPrayer
        )
    else
        hp = logic.normalisePoints(
            readVariable("VarPlayer", "LIFEPOINTS"),
            maximumHP
        )

        local prayerSample, prayerRaw = readPrayerPoints(
            maximumPrayer
        )

        prayer = logic.stabiliseReading(
            prayerState,
            prayerSample,
            maximumPrayer,
            prayerFilterOptions
        )

        if hp == nil and not missingHPLogged then
            log(
                "AFK Vitals Tint: HP reading unavailable; "
                .. "red warning disabled."
            )

            missingHPLogged = true
        end

        if prayer == nil and not missingPrayerLogged then
            log(
                "AFK Vitals Tint: Prayer reading unavailable; "
                .. "blue warning disabled."
            )

            missingPrayerLogged = true
        end

        if settings.debugPrayerReadings
            and (
                not hasLoggedPrayer
                or prayerRaw ~= lastLoggedPrayer
            ) then

            local sourceName = prayerSource
                and (
                    prayerSource.domain
                    .. "."
                    .. prayerSource.name
                )
                or "unavailable"

            log(
                "AFK Vitals Tint: Prayer source="
                .. sourceName
                .. ", raw="
                .. tostring(prayerRaw)
                .. ", scale="
                .. tostring(
                    prayerSource and prayerSource.scale
                )
                .. ", displayed="
                .. tostring(prayer)
            )

            lastLoggedPrayer = prayerRaw
            hasLoggedPrayer = true
        end
    end

    -- Preserve the existing quadratic HP warning behaviour.
    local hpOpacity = 0

    if settings.enableHPWarning then
        hpOpacity = logic.warningOpacity(
            hp,
            maximumHP,
            settings.hpWarningStart,
            settings.maxOpacity
        )
    end

    -- Use the earlier, linear full-strength threshold for Prayer.
    local prayerOpacity = 0

    if settings.enablePrayerWarning then
        prayerOpacity = calculatePrayerOpacity(
            prayer,
            maximumPrayer
        )
    end

    setSplitMode(
        settings.splitWhenBothLow
        and hpOpacity > 0
        and prayerOpacity > 0
    )

    updateTint(
        redRectangle,
        HEALTH_COLOUR,
        hpOpacity
    )

    updateTint(
        blueRectangle,
        PRAYER_COLOUR,
        prayerOpacity
    )
end

-- =============================================================================
-- Event Handlers
-- =============================================================================

-- Processes resource readings at the configured logic-tick interval.
-- Reduces unnecessary calculations during normal gameplay.
local function onLogicTick(event)
    if event.logicTick % settings.updateEveryLogicTicks == 0 then
        refresh()
    end
end

-- Resets overlays and cached readings after a game-state transition.
-- Ensures old UI references do not persist between game sessions.
local function onGameStateChanged()
    destroyTints()
    resetReadings()
end

-- Unsubscribes events and releases plugin resources during shutdown.
-- Prevents unused overlays and callbacks from remaining active.
function PluginShutdown()
    Event.Logic.Unsubscribe(EVENT_NAME)
    Event.GameStateChanged.Unsubscribe(EVENT_NAME)

    destroyTints()
    resetReadings()
end

-- =============================================================================
-- Plugin Initialisation
-- =============================================================================

Event.Logic.Subscribe(
    EVENT_NAME,
    onLogicTick
)

Event.GameStateChanged.Subscribe(
    EVENT_NAME,
    onGameStateChanged
)

if settings.simulation and settings.simulation.enabled then
    log(
        "AFK Vitals Tint: simulation mode enabled. "
        .. "Actual player resources are unchanged."
    )
else
    log(
        "AFK Vitals Tint loaded. "
        .. "Health and Prayer monitoring active."
    )
end
