-- =============================================================================
-- File:        test_logic.lua
-- Project:     RS3 AFK Vitals Tint
-- Author:      John Crawley
-- Description: Unit tests for resource opacity, scaling, and prayer stability.
-- =============================================================================

local logic = require("logic")

-- Asserts approximate numeric equality to avoid floating-point rounding issues.
local function assertNear(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.0000001,
        "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

assertNear(logic.warningOpacity(100, 100, 0.70, 0.52), 0)
assertNear(logic.warningOpacity(70, 100, 0.70, 0.52), 0)
assertNear(logic.warningOpacity(35, 100, 0.70, 0.52), 0.13)
assertNear(logic.warningOpacity(0, 100, 0.70, 0.52), 0.52)
assertNear(logic.warningOpacity(nil, 100, 0.70, 0.52), 0)
assertNear(logic.warningOpacity(0, 0, 0.70, 0.52), 0)
assertNear(logic.normalisePoints(4000, 990), 400)
assertNear(logic.normalisePoints(400, 990), 400)
assert(logic.isValidReading(0, 10))
assert(not logic.isValidReading(nil, 10))
assert(not logic.isValidReading(-1, 10))
assert(not logic.isValidReading(99, 10))

local options = {
    maxMissingSamples = 5,
    riseConfirmationSamples = 3,
    confirmRiseAboveFraction = 0.35,
}

local state = logic.newReadingState()
assertNear(logic.stabiliseReading(state, 5, 10, options), 5)
assertNear(logic.stabiliseReading(state, 2, 10, options), 2)
assertNear(logic.stabiliseReading(state, nil, 10, options), 2)
assertNear(logic.stabiliseReading(state, 10, 10, options), 2)
assertNear(logic.stabiliseReading(state, 2, 10, options), 2)
assertNear(logic.stabiliseReading(state, 1, 10, options), 1)
assertNear(logic.stabiliseReading(state, 0, 10, options), 0)
assertNear(logic.stabiliseReading(state, 10, 10, options), 0)
assertNear(logic.stabiliseReading(state, 10, 10, options), 0)
assertNear(logic.stabiliseReading(state, 10, 10, options), 10)

for _ = 1, options.maxMissingSamples do
    assertNear(logic.stabiliseReading(state, nil, 10, options), 10)
end
assert(logic.stabiliseReading(state, nil, 10, options) == nil)

print("All AFK Vitals Tint calculation and prayer stability tests passed")
