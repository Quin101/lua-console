-- A small, safe arithmetic evaluator (recursive-descent, no loadstring).
-- Supports:  + - * /  // (integer div)  %  ^ (power)  unary -  n! (factorial)
--   numbers: 12  1.5  .5  1e3  2.5e-3  0xFF  0b1011
--   grouping: ( )          lists for min/max/etc: f(a, b, c)
--   constants: pi tau e phi  and  ans (previous answer)
--   functions: sqrt cbrt abs sign exp ln log log2 log10
--              sin cos tan asin acos atan  sinh cosh tanh  deg rad
--              floor ceil round trunc fract  min max  gcd lcm  hypot  fact
local calc = {}

local FUNCS = {
    sqrt = math.sqrt,
    cbrt = function(x) return (x < 0 and -1 or 1) * math.abs(x) ^ (1 / 3) end,
    abs = math.abs,
    sign = function(x) return x > 0 and 1 or (x < 0 and -1 or 0) end,
    exp = math.exp,
    ln = math.log,
    log = function(x, b) return b and math.log(x) / math.log(b) or math.log(x) / math.log(10) end,
    log2 = function(x) return math.log(x) / math.log(2) end,
    log10 = function(x) return math.log(x) / math.log(10) end,
    sin = math.sin, cos = math.cos, tan = math.tan,
    asin = math.asin, acos = math.acos, atan = function(y, x) return x and math.atan2(y, x) or math.atan(y) end,
    sinh = math.sinh, cosh = math.cosh, tanh = math.tanh,
    deg = math.deg, rad = math.rad,
    floor = math.floor, ceil = math.ceil,
    round = function(x) return math.floor(x + 0.5) end,
    trunc = function(x) return x >= 0 and math.floor(x) or math.ceil(x) end,
    fract = function(x) return x - math.floor(x) end,
    min = math.min, max = math.max,
    hypot = function(a, b) return math.sqrt(a * a + b * b) end,
    gcd = function(a, b) a, b = math.abs(a), math.abs(b); while b > 0 do a, b = b, a % b end return a end,
    lcm = function(a, b) if a == 0 or b == 0 then return 0 end return math.abs(a * b) / FUNCS.gcd(a, b) end,
    fact = function(n)
        if n < 0 or n ~= math.floor(n) then error("fact needs a non-negative integer") end
        local r = 1
        for i = 2, n do r = r * i end
        return r
    end,
}

local CONSTS = { pi = math.pi, tau = math.pi * 2, e = math.exp(1), phi = (1 + math.sqrt(5)) / 2 }

-- tokenizer ------------------------------------------------------------------

local function tokenize(s)
    local toks, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c:match("[%d.]") then
            local num
            if s:sub(i, i + 1):lower() == "0x" then
                num = s:match("^0[xX][%x]+", i)
            elseif s:sub(i, i + 1):lower() == "0b" then
                local bits = s:match("^0[bB]([01]+)", i)
                if bits then
                    toks[#toks + 1] = { t = "num", v = tonumber(bits, 2) }
                    i = i + 2 + #bits
                    goto continue
                end
            end
            num = num or s:match("^%d*%.?%d+[eE][%+%-]?%d+", i) or s:match("^%d*%.?%d+", i) or s:match("^%d+%.?", i)
            if not num then return nil, "bad number at position " .. i end
            toks[#toks + 1] = { t = "num", v = tonumber(num) }
            i = i + #num
        elseif c:match("[%a_]") then
            local word = s:match("^[%a_][%w_]*", i)
            toks[#toks + 1] = { t = "name", v = word:lower() }
            i = i + #word
        else
            local two = s:sub(i, i + 1)
            if two == "//" then toks[#toks + 1] = { t = "op", v = "//" }; i = i + 2
            elseif two == "**" then toks[#toks + 1] = { t = "op", v = "^" }; i = i + 2
            elseif c:match("[%+%-%*/%%%^%(%),!]") then
                toks[#toks + 1] = { t = "op", v = c }; i = i + 1
            else
                return nil, "unexpected '" .. c .. "'"
            end
        end
        ::continue::
    end
    return toks
end

-- parser / evaluator ---------------------------------------------------------

function calc.eval(expr, vars)
    if type(expr) ~= "string" or expr:match("^%s*$") then return nil, "empty expression" end
    local toks, err = tokenize(expr)
    if not toks then return nil, err end
    local pos = 1
    local function peek() return toks[pos] end
    local function next_() local t = toks[pos]; pos = pos + 1; return t end
    local function expect(v)
        local t = next_()
        if not t or t.v ~= v then error("expected '" .. v .. "'") end
    end

    local parse_expr

    local function parse_primary()
        local t = next_()
        if not t then error("unexpected end of expression") end
        if t.t == "num" then return t.v end
        if t.v == "(" then
            local v = parse_expr()
            expect(")")
            return v
        end
        if t.t == "name" then
            local nx = peek()
            if nx and nx.v == "(" then
                next_()
                local args = {}
                if not (peek() and peek().v == ")") then
                    args[1] = parse_expr()
                    while peek() and peek().v == "," do next_(); args[#args + 1] = parse_expr() end
                end
                expect(")")
                local fn = FUNCS[t.v]
                if not fn then error("unknown function '" .. t.v .. "'") end
                return fn(unpack(args))
            end
            if CONSTS[t.v] ~= nil then return CONSTS[t.v] end
            if vars and vars[t.v] ~= nil then return vars[t.v] end
            error("unknown name '" .. t.v .. "'")
        end
        error("unexpected '" .. tostring(t.v) .. "'")
    end

    -- factorial postfix
    local function parse_postfix()
        local v = parse_primary()
        while peek() and peek().v == "!" do next_(); v = FUNCS.fact(v) end
        return v
    end

    local function parse_unary()
        local t = peek()
        if t and (t.v == "-" or t.v == "+") then
            next_()
            local v = parse_unary()
            return t.v == "-" and -v or v
        end
        return parse_postfix()
    end

    -- power is right-associative and binds tighter than unary on its right
    local function parse_power()
        local base = parse_unary()
        if peek() and peek().v == "^" then
            next_()
            return base ^ parse_power()
        end
        return base
    end

    local function parse_term()
        local v = parse_power()
        while peek() and (peek().v == "*" or peek().v == "/" or peek().v == "//" or peek().v == "%") do
            local op = next_().v
            local rhs = parse_power()
            if op == "*" then v = v * rhs
            elseif op == "/" then if rhs == 0 then error("division by zero") end; v = v / rhs
            elseif op == "//" then if rhs == 0 then error("division by zero") end; v = math.floor(v / rhs)
            else if rhs == 0 then error("division by zero") end; v = v % rhs end
        end
        return v
    end

    parse_expr = function()
        local v = parse_term()
        while peek() and (peek().v == "+" or peek().v == "-") do
            local op = next_().v
            local rhs = parse_term()
            v = op == "+" and v + rhs or v - rhs
        end
        return v
    end

    local ok, result = pcall(function()
        local v = parse_expr()
        if pos <= #toks then error("unexpected '" .. tostring(toks[pos].v) .. "'") end
        return v
    end)
    if not ok then
        return nil, tostring(result):gsub("^.-:%d+: ", "")
    end
    if result ~= result then return nil, "not a number (nan)" end
    if result == math.huge or result == -math.huge then return nil, "overflow (infinite)" end
    return result
end

-- format a number cleanly (integers without a decimal, otherwise trimmed)
function calc.format(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return ("%d"):format(v)
    end
    local s = ("%.10g"):format(v)
    return s
end

return calc
