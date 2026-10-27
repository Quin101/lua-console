-- ─────────────────────────────────────────────────────────────
--  Qrawller Terminal — settings
--  Edit this file to change how the terminal looks and behaves.
-- ─────────────────────────────────────────────────────────────
return {
    -- Shown in the prompt:  qrawller ❯
    prompt = "qrawller",
    prompt_symbol = "❯",

    -- Colour theme: red, mint, cyan, violet, amber, ice, mono
    -- (can also be changed live with the `theme` command)
    theme = "red",

    font_size = 15,
    line_spacing = 1.35,

    -- Effects
    glow = 0.55,             -- soft bloom around text (0 = off)
    background_grid = true,  -- faint dot grid that ripples when you type
    particles = true,        -- little sparks while typing
    screen_shake = true,

    -- Sound (all sounds are generated in code, no audio files needed)
    sound = true,
    volume = 0.5,

    -- Play the boot animation on start (hold Shift or press any key to skip it)
    boot = true,

    -- Commands to run automatically after boot
    autorun = {},

    -- Shortcuts: typing the key runs the value
    aliases = {
        cls = "clear",
        ["?"] = "help",
        ls = "help",
        quit = "exit",
    },
}
