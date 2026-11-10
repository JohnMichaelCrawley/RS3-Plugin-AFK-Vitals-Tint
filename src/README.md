# AFK Vitals Tint — RS3 developer prototype v0.1

An experimental, Lua-based health and prayer warning overlay for the **official RuneScape 3 client API**. No bots, automatic item usage, prayer switching, or simulated input. Red increases as health falls; blue increases as prayer falls. If both are low, red colours the left half and blue the right. Both overlays are click-through.

**Status: prototype.** Calculations have been tested separately, but this plugin has **not** been executed within the RuneScape beta client. The exact prayer-points variable has not been confirmed. See the diagnostic steps below. Not available for live worlds until Jagex approves it.

## Install (macOS)

1. Launch the **RuneScape plugin developer beta** at least once.
2. Unzip the download and copy the entire `afk-vitals-tint` folder to:
   `~/Jagex/RuneScape-BETA/dev_plugins/afk-vitals-tint/`
   Ensure this directory directly contains `main.lua` and `plugin.json`.
3. On a developer world, open the console with **Option/Alt + the key below Esc**.
4. Enter these console commands one by one:
   ```text
   prf
   plist
   pon afk-vitals-tint
   ```
5. To reload after editing `settings.lua`, run `prl afk-vitals-tint`. To stop, run `poff afk-vitals-tint`.

The official developer docs: https://developer.runescape.com/rs/tutorial/1helloworld.html

## Prayer variable diagnostic (important)

`LIFEPOINTS` has been publicly shown as a supported `var.VarPlayer` value. Prayer's exact current-points key was **not** reliably established from the official public reference. `settings.lua` checks several **unverified candidates**. If none exists, the blue overlay stays hidden, rather than making up a prayer value.

In the developer console:

1. Run `pan VarPlayer`, paste its clipboard output into a text editor, and search for `PRAYER` and `POINTS`.
2. If no clear current prayer-points variable appears, run `pan VarClient` and search the output.
3. Confirm candidate values change as you enable/disable prayers, for example by adding a one-off temporary `print(var.VarPlayer.YOUR_VARIABLE.value)` to the plugin and reloading it (replace `YOUR_VARIABLE`).
4. Add the confirmed `{ domain = "VarPlayer", name = "YOUR_VARIABLE" }` or equivalent VarClient entry at the start of `prayerVariableCandidates` in `settings.lua`.
5. If neither domain exposes current prayer points, a future version would need to read the existing prayer UI component instead; this draft does not pretend that unavailable data exists.

## Behaviour/settings

Edit `settings.lua`:

- `hpWarningStart = 0.70`: begin tint below 70% HP.
- `prayerWarningStart = 0.70`: begin tint below 70% prayer.
- `maxOpacity = 0.52`: maximum overlay alpha.
- `updateEveryLogicTicks = 10`: refresh about 5 times per second.
- `splitWhenBothLow = true`: red left / blue right if both low.

The opacity curve uses a quadratic ease-in, based on the fraction of remaining points. At 70%: invisible. At 35%: about 13% opacity. At 0%: 52% opacity.

The default maximum health/prayer values are derived from Constitution × 100 and Prayer × 10. Buffs and temporary raised maxima may lead to imperfect percentages; validate with actual in-game values before publishing.

## Testing and publishing

From this folder, `texlua tests/test_logic.lua` runs the isolated calculation tests, if `texlua` is installed.

Test on developer worlds, including normal depletion, restoration, world hops, and both warnings at once. Jagex says combat overlays are **subject to moderation review**, not automatically approved. The manifest email `contact@example.invalid` is **only a placeholder** — replace it with an email you control before submission. For other submission rules: https://developer.runescape.com/rs/submission/guidelines.html
