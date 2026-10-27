-- A real calculator. Evaluates an arithmetic expression and shows the result.
--   calc 2 + 2        = 4
--   calc sqrt(144) * pi
--   = 100 * (1 + 0.05)   (the "=" alias)
-- Use `ans` for the previous result:  calc ans * 2
local calc = require("src.calc")

local last = 0

local function esc(s) return (tostring(s):gsub("{", "{{")) end

local EXAMPLES = {
    "2 + 2 * 10", "(5 + 3) / 2", "2^16", "sqrt(2)", "sin(pi/4)",
    "log2(1024)", "5!", "100 * 1.08", "max(3, 7, 2)", "0xFF + 0b1010",
}

return {
    name = "calc",
    aliases = { "=", "c" },
    help = "calculator — e.g. calc (5+3)*2 / sqrt(2)",
    usage = "calc <expression>",
    category = "tools",

    run = function(t, args, rest)
        rest = (rest or ""):gsub("^%s*=%s*", "")

        if rest == "" then
            t.print("{dim}calculator — type an expression after {accent}calc{dim} or {accent}={dim}")
            t.print("")
            t.print("{dim}operators{}  + - * / // % ^   n!   ( )")
            t.print("{dim}functions{}  sqrt cbrt abs sign exp ln log log2 log10")
            t.print("{dim}         {}  sin cos tan asin acos atan deg rad")
            t.print("{dim}         {}  floor ceil round min max gcd lcm hypot fact")
            t.print("{dim}constants{}  pi tau e phi   ·   {}ans{dim} = last result")
            t.print("")
            local ex = t.pick(EXAMPLES)
            t.print("{dim}try:  {accent}calc " .. ex)
            return
        end

        local value, err = calc.eval(rest, { ans = last })
        if not value then
            t.print("{err}✗{} " .. esc(err))
            t.sound("err", { volume = 0.5 })
            t.glitch(0.15, 0.3)
            return
        end
        last = value
        if t.terminal then t.terminal.calc_ans = value end

        local out = calc.format(value)
        -- a little extra context for integers: hex + binary when it's reasonable
        local extra = ""
        if value == math.floor(value) and math.abs(value) < 2 ^ 31 and math.abs(value) >= 1 then
            local n = math.floor(value)
            local hex = (n < 0 and "-0x" .. ("%X"):format(-n)) or ("0x" .. ("%X"):format(n))
            extra = "   {dim}" .. hex
        end
        t.type("{dim}= {}{white}" .. esc(out) .. "{}" .. extra, "text", 220)
        t.sound("beep", { pitch = 1.3, volume = 0.4 })
        t.sparks(6, "accent")
    end,
}
