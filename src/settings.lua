
-- =============================================================================
-- File:        settings.lua
-- Project:     RS3 AFK Vitals Tint
-- Author:      John Crawley
--
-- Description:
--   Defines configurable resource warnings, overlay appearance,
--   Prayer-reading stabilisation, and simulation options.
--
--   These values control plugin behaviour and can be modified
--   before reloading the plugin in RuneScape Developer Beta.
-- =============================================================================

return {

    -- =========================================================================
    -- Resource Warnings
    -- =========================================================================

    -- Enable or disable individual resource warning overlays.
    enableHPWarning = true,
    enablePrayerWarning = true,

    -- Begin displaying warnings below 70% remaining resources.
    hpWarningStart = 0.70,
    prayerWarningStart = 0.70,

    -- Reach maximum Prayer warning intensity at 20% remaining.
    -- The red HP warning retains its existing intensity calculation.
    prayerFullStrengthAt = 0.20,

    -- Maximum overlay opacity, keeping gameplay visible.
    maxOpacity = 0.52,

    -- =========================================================================
    -- Overlay Behaviour
    -- =========================================================================

    -- RuneScape operates at 50 logic ticks per second.
    -- A value of 10 updates warning overlays five times per second.
    updateEveryLogicTicks = 10,

    -- Separate HP and Prayer into left/right halves when both are low.
    -- Disable to allow full-screen overlapping warning colours.
    splitWhenBothLow = true,

    -- =========================================================================
    -- Prayer Reading Configuration
    -- =========================================================================

    -- Prayer readings may use points or tenths of points.
    -- "auto" detects the scale once, while 1 or 10 forces a fixed scale.
    -- Automatic detection is most reliable when reloaded at full Prayer.
    prayerValueScale = "auto",

    -- Preserve temporary missing Prayer readings for up to five samples.
    -- Prevents short data interruptions from immediately hiding blue.
    prayerMaxMissingSamples = 5,

    -- Require three matching samples before accepting large increases.
    -- Prevents isolated incorrect readings from resetting the warning.
    prayerRiseConfirmationSamples = 3,

    -- Treat increases above 35% of maximum Prayer as large jumps.
    prayerConfirmRiseAboveFraction = 0.35,

    -- Log Prayer readings and the selected variable for debugging.
    -- Enable temporarily when diagnosing unexpected blue-screen behaviour.
    debugPrayerReadings = false,

    -- =========================================================================
    -- Developer Simulation
    -- =========================================================================

    -- Simulates resource depletion without modifying actual game values.
    -- Keep disabled during normal gameplay and release testing.
    simulation = {
        enabled = false,

        -- Available modes: "hp", "prayer", or "both".
        resource = "both",

        -- Total cycle duration in seconds.
        -- A 30-second cycle drains for 15 seconds and restores for 15.
        cycleSeconds = 30,
    },

    -- =========================================================================
    -- Prayer Variable Candidates
    -- =========================================================================

    -- Candidate client variables used to locate Prayer points.
    -- These names remain unverified; confirm the actual source in-game.
    prayerVariableCandidates = {
        { domain = "VarPlayer", name = "PRAYERPOINTS" },
        { domain = "VarPlayer", name = "PRAYER_POINTS" },
        { domain = "VarPlayer", name = "PRAYER" },
        { domain = "VarClient", name = "PRAYERPOINTS" },
        { domain = "VarClient", name = "PRAYER_POINTS" },
        { domain = "VarClient", name = "PRAYER" },
    },
}
