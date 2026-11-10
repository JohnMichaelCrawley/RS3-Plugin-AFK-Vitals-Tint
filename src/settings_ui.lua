
-- =============================================================================
-- File:        settings_ui.lua
-- Project:     RS3 AFK Vitals Tint
-- Author:      John Crawley
-- Description:
--   Persistent settings, warning thresholds, one-time preview,
--   feedback information and manifest-generated version display.
-- =============================================================================
local SettingsUI = {}
local VERSION = "__PLUGIN_VERSION__"
local STORAGE_KEY = "afkVitalsPreferences"
local PERSISTED_KEYS = {
    "enableHPWarning",
    "enablePrayerWarning",
    "splitWhenBothLow",
    "hpWarningStart",
    "prayerWarningStart",
    "maxOpacity",
}
local defaults = {}
local activePreviewCheck = nil

local function percentage(value)
    return math.floor(value * 100 + 0.5)
end

-- Validates saved settings.
local function isValidPreference(key, value)
    if key == "enableHPWarning"
        or key == "enablePrayerWarning"
        or key == "splitWhenBothLow" then
        return type(value) == "boolean"
    end
    if type(value) ~= "number" or value ~= value then return false end
    if key == "hpWarningStart" then
        return value >= 0.20 and value <= 0.95
    end
    if key == "prayerWarningStart" then
        return value >= 0.30 and value <= 0.95
    end
    if key == "maxOpacity" then
        return value >= 0.10 and value <= 0.70
    end
    return false
end

-- Synchronises the preview checkbox when the simulation finishes.
function SettingsUI.syncPreview(enabled)
    if activePreviewCheck == nil then return end
    pcall(function()
        activePreviewCheck.value = enabled
    end)
end

-- Loads persisted settings. Preview always starts disabled.
function SettingsUI.load(config)
    for _, key in ipairs(PERSISTED_KEYS) do
        defaults[key] = config[key]
    end
    config.simulation.enabled = false
    config.simulation.resource = "both"
    local success, saved = pcall(function()
        return PersistentDB:GetStructuredData(STORAGE_KEY)
    end)
    if not success or type(saved) ~= "table" then return end
    for _, key in ipairs(PERSISTED_KEYS) do
        if isValidPreference(key, saved[key]) then
            config[key] = saved[key]
        end
    end
end

-- Saves preferences without persisting preview settings.
function SettingsUI.save(config)
    local preferences = {}
    for _, key in ipairs(PERSISTED_KEYS) do
        preferences[key] = config[key]
    end
    local success, result = pcall(function()
        return PersistentDB:SetStructuredData(STORAGE_KEY, preferences)
    end)
    if not success or result == false then
        log("AFK Vitals Tint: unable to save preferences.")
    end
end

-- Restores all default settings.
function SettingsUI.reset(config)
    for _, key in ipairs(PERSISTED_KEYS) do
        config[key] = defaults[key]
    end
    config.simulation.enabled = false
    config.simulation.resource = "both"
    SettingsUI.syncPreview(false)
    SettingsUI.save(config)
end

-- Creates a readable label.
local function addLabel(parent, content, height)
    local label = ui.Text.new(parent)
    label:SetSize(0, height or 22, 1.0, 0)
    label.content = content
    label.font = id.Font.MUSEO_SANS_15PT_REGULAR
    label.colour = Vector4.new(0.95, 0.90, 0.78, 1.0)
    label:AlignTo(ui.AlignMode.CENTRE)
    return label
end

-- Creates a clickable button.
local function addButton(parent, title, callback, width, height)
    local button = ui.Button.new(parent)
    button:SetSize(0, height or 30, width or 1.0, 0)
    button.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
    button.label = title
    button:Subscribe(ui.Hook.ONBUTTONPRESSED, callback)
    return button
end

-- Creates a checkbox with persistent configuration.
local function addCheckbox(parent, config, key, title, onChange)
    local checkbox = ui.Check.new(parent)
    checkbox:SetSize(0, 30, 1.0, 0)
    checkbox.stylesheetID = id.StyleSheet.CHECKBOX_DEFAULT
    checkbox.alignment = ui.CheckAlignMode.LEFT
    checkbox.buttonSize = 22
    checkbox.label = title
    checkbox.value = config[key]
    checkbox:Subscribe(ui.Hook.ONBUTTONPRESSED, function(component)
        config[key] = component.value
        SettingsUI.save(config)
        if onChange then onChange() end
    end)
    return checkbox
end

-- Creates a grouped slider with space for labels and numeric values.
local function addPercentageSlider(
    parent, config, key, title, minimum, maximum, step, onChange
)
    local group = ui.Panel.new(parent)
    group:SetSize(0, 82, 1.0, 0)
    group.isVertical = true
    group.spacing = 0

    local label = addLabel(group, "", 22)
    local slider = ui.Slider.new(group)
    slider:SetSize(0, 47, 1.0, 0)
    slider.stylesheetID = id.StyleSheet.SLIDER_DEFAULT
    slider:Setup(minimum, maximum, percentage(config[key]), 1, step)

    local function refreshLabel()
        label.content = title .. ": " .. percentage(config[key]) .. "%"
    end

    slider:Subscribe(
        ui.Hook.ONSELECTIONCHANGED,
        function(component, _, selectedStatus)
            if selectedStatus ~= 1 then return end
            config[key] = component.value / 100
            refreshLabel()
            SettingsUI.save(config)
            if onChange then onChange() end
        end
    )
    refreshLabel()
    return slider, refreshLabel
end

-- Creates a settings page. Warnings starts visible.
local function createPage(parent, spacing, initiallyVisible)
    local page = ui.Panel.new(parent)
    page:SetPos(16, 50)
    page:SetSize(-32, -56, 1.0, 1.0)
    page.isVertical = true
    page.spacing = spacing
    page.hidden = not initiallyVisible
    return page
end

-- Builds the complete tabbed settings interface.
function SettingsUI.render(parent, config, onChange)
    local pages = {
        createPage(parent, 12, true),
        createPage(parent, 4, false),
        createPage(parent, 3, false),
    }

    -- Tab navigation.
    local navigation = ui.Panel.new(parent)
    navigation:SetPos(12, 8)
    navigation:SetSize(-24, 34, 1.0, 0)
    navigation.isVertical = false
    navigation.spacing = 6

    local tabNames = { "Warnings", "Thresholds", "Preview" }
    local tabButtons = {}

    local function showPage(selected)
        for index, page in ipairs(pages) do
            page.hidden = index ~= selected
            tabButtons[index].label = index == selected
                and ("[" .. tabNames[index] .. "]")
                or tabNames[index]
        end
    end

    for index, title in ipairs(tabNames) do
        local tabIndex = index
        local initialLabel = index == 1
            and ("[" .. title .. "]") or title
        tabButtons[index] = addButton(
            navigation, initialLabel,
            function() showPage(tabIndex) end, 0.31
        )
    end

    -- =======================================================================
    -- TAB 1: WARNINGS
    -- =======================================================================
    local warnings = pages[1]
    addLabel(warnings, "Resource Warnings", 22)

    local hpCheck = addCheckbox(
        warnings, config, "enableHPWarning",
        "Enable HP warning (red)", onChange
    )
    local prayerCheck = addCheckbox(
        warnings, config, "enablePrayerWarning",
        "Enable Prayer warning (blue)", onChange
    )
    local splitCheck = addCheckbox(
        warnings, config, "splitWhenBothLow",
        "Split red and blue when both are low", onChange
    )

    -- =======================================================================
    -- TAB 2: THRESHOLDS
    -- =======================================================================
    local thresholds = pages[2]

    local hpSlider, refreshHPLabel = addPercentageSlider(
        thresholds, config, "hpWarningStart",
        "HP warning begins", 20, 95, 5, onChange
    )
    local prayerSlider, refreshPrayerLabel = addPercentageSlider(
        thresholds, config, "prayerWarningStart",
        "Prayer warning begins", 30, 95, 5, onChange
    )
    local opacitySlider, refreshOpacityLabel = addPercentageSlider(
        thresholds, config, "maxOpacity",
        "Maximum opacity", 10, 70, 1, onChange
    )

    -- =======================================================================
    -- TAB 3: PREVIEW, VERSION AND FEEDBACK
    -- =======================================================================
    local preview = pages[3]

    -- Version is embedded from plugin.json during packaging.
    addLabel(preview, "AFK Vitals Tint - v" .. VERSION, 20)

    -- One-time visual preview.
    local previewCheck = ui.Check.new(preview)
    activePreviewCheck = previewCheck
    previewCheck:SetSize(0, 28, 1.0, 0)
    previewCheck.stylesheetID = id.StyleSheet.CHECKBOX_DEFAULT
    previewCheck.alignment = ui.CheckAlignMode.LEFT
    previewCheck.buttonSize = 22
    previewCheck.label = "Run one-time preview (visual only)"
    previewCheck.value = config.simulation.enabled

    previewCheck:Subscribe(ui.Hook.ONBUTTONPRESSED, function(component)
        config.simulation.enabled = component.value
        if onChange then onChange() end
    end)

    addLabel(preview, "Select resources to preview", 18)

    -- Compact resource-selection buttons.
    local modeRow = ui.Panel.new(preview)
    modeRow:SetSize(0, 32, 1.0, 0)
    modeRow.isVertical = false
    modeRow.spacing = 6

    local modes = {
        { key = "hp", label = "HP only" },
        { key = "prayer", label = "Prayer only" },
        { key = "both", label = "Both" },
    }
    local modeButtons = {}

    local function refreshModeLabels()
        for _, mode in ipairs(modes) do
            local selected = config.simulation.resource == mode.key
            modeButtons[mode.key].label = selected
                and ("[" .. mode.label .. "]")
                or mode.label
        end
    end

    for _, mode in ipairs(modes) do
        local selectedMode = mode
        modeButtons[mode.key] = addButton(
            modeRow,
            mode.label,
            function()
                config.simulation.resource = selectedMode.key
                refreshModeLabels()
                if onChange then onChange() end
            end,
            0.31,
            30
        )
    end
    refreshModeLabels()

    addLabel(
        preview,
        "Preview runs once, then resumes normal monitoring.",
        18
    )

    -- Reset all preferences and update visible controls.
    addButton(preview, "Reset to Defaults", function()
        SettingsUI.reset(config)

        hpCheck.value = config.enableHPWarning
        prayerCheck.value = config.enablePrayerWarning
        splitCheck.value = config.splitWhenBothLow
        previewCheck.value = false

        hpSlider:SetValue(percentage(config.hpWarningStart), false)
        prayerSlider:SetValue(percentage(config.prayerWarningStart), false)
        opacitySlider:SetValue(percentage(config.maxOpacity), false)

        refreshHPLabel()
        refreshPrayerLabel()
        refreshOpacityLabel()
        refreshModeLabels()

        if onChange then onChange() end
        log("AFK Vitals Tint: default settings restored.")
    end, 1.0, 28)

    -- Feedback is informational only.
    addLabel(preview, "Feedback & Support", 18)
    addLabel(preview, "Leave feedback on my mod.io page.", 20)

    -- Warnings is already visible; no extra tab click is required.
end

return SettingsUI
