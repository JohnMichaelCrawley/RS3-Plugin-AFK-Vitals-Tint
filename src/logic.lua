
-- =============================================================================
-- File:        logic.lua
-- Project:     RS3 AFK Vitals Tint
-- Author:      John Crawley
--
-- Description:
--   Provides resource calculations, prayer-reading stabilisation,
--   and simulated resource depletion for overlay testing.
--
--   All functions are independent of the RuneScape API.
-- =============================================================================
local Logic = {}
-- =============================================================================
-- Numeric Helpers
-- =============================================================================
-- Verifies that a value is a finite number to prevent invalid
-- resource readings from affecting warning calculations.
local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end
-- Restricts a numeric value to the specified minimum and maximum.
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end
-- =============================================================================
-- Resource Calculations
-- =============================================================================
-- Calculates warning opacity based on the remaining resource percentage.
-- The overlay gradually intensifies as the resource approaches zero.

-- Calculates warning opacity from the remaining resource percentage.
-- Supports an early full-strength threshold and configurable intensity curve.
function Logic.warningOpacity(
    current,
    maximum,
    startFraction,
    maxOpacity,
    fullStrengthFraction,
    curveExponent
)
    local fullStrength = fullStrengthFraction or 0
    local exponent = curveExponent or 2

    if not isFiniteNumber(current)
        or not isFiniteNumber(maximum)
        or not isFiniteNumber(startFraction)
        or not isFiniteNumber(maxOpacity)
        or not isFiniteNumber(fullStrength)
        or not isFiniteNumber(exponent)
        or maximum <= 0
        or startFraction <= 0
        or startFraction > 1
        or fullStrength < 0
        or fullStrength >= startFraction
        or maxOpacity < 0
        or exponent <= 0 then
        return 0
    end

    local remaining = clamp(current / maximum, 0, 1)

    local urgency = clamp(
        (startFraction - remaining)
            / (startFraction - fullStrength),
        0,
        1
    )

    return clamp(
        maxOpacity * urgency ^ exponent,
        0,
        1
    )
end

-- Converts unusually large resource readings from tenths to points.
-- Values already within the expected range retain their original scale.
function Logic.normalisePoints(value, maximum)
    if not isFiniteNumber(value)
        or not isFiniteNumber(maximum) then
        return value
    end
    if maximum > 0 and value > maximum * 2.5 then
        return value / 10
    end
    return value
end
-- Validates resource readings against a reasonable maximum.
-- Zero is considered valid because resources may be fully depleted.
function Logic.isValidReading(value, maximum)
    return isFiniteNumber(value)
        and isFiniteNumber(maximum)
        and maximum > 0
        and value >= 0
        and value <= maximum * 1.5
end
-- =============================================================================
-- Prayer Reading Stabilisation
-- =============================================================================
-- Creates independent state for tracking prayer readings and
-- identifying temporary missing or inconsistent values.
function Logic.newReadingState()
    return {
        lastValue = nil,
        missingSamples = 0,
        pendingRise = nil,
        riseSamples = 0,
    }
end

-- Stabilises prayer readings by retaining brief missing values and
-- confirming large increases before updating the warning overlay.
-- Resource decreases, including zero, are accepted immediately.
function Logic.stabiliseReading(state, observed, maximum, options)
    if not Logic.isValidReading(observed, maximum) then
        state.missingSamples = state.missingSamples + 1
        state.pendingRise = nil
        state.riseSamples = 0
        if state.missingSamples > options.maxMissingSamples then
            state.lastValue = nil
        end
        return state.lastValue
    end
    state.missingSamples = 0
    if state.lastValue == nil then
        state.lastValue = observed
        state.pendingRise = nil
        state.riseSamples = 0
        return observed
    end
    local rise = observed - state.lastValue
    if rise > maximum * options.confirmRiseAboveFraction then
        local sameRise = state.pendingRise ~= nil
            and math.abs(
                observed - state.pendingRise
            ) <= maximum * 0.05
        state.riseSamples = sameRise
            and (state.riseSamples + 1)
            or 1
        state.pendingRise = observed
        if state.riseSamples < options.riseConfirmationSamples then
            return state.lastValue
        end
    end
    state.lastValue = observed
    state.pendingRise = nil
    state.riseSamples = 0
    return observed
end
-- =============================================================================
-- Developer Simulation
-- =============================================================================
-- Simulates a full-to-empty-to-full resource cycle for testing overlays.
-- Only the calculated warning values change; actual game stats are unaffected.
function Logic.simulatedRemainingFraction(elapsedSeconds, cycleSeconds)
    if not isFiniteNumber(elapsedSeconds)
        or not isFiniteNumber(cycleSeconds)
        or cycleSeconds <= 0 then
        return 1
    end
    local progress = (
        math.max(0, elapsedSeconds) % cycleSeconds
    ) / cycleSeconds
    return math.abs(1 - 2 * progress)
end
-- =============================================================================
-- Module Export
-- =============================================================================

return Logic
