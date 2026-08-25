-- Replays the Hyprland Lua bind files under a recording `hl` and prints what each
-- hl.bind call asked for, as JSON on stdout.
--
-- `hyprctl binds` reports every Lua bind as dispatcher `__lua` with an opaque
-- index, and `hyprctl dispatch` under a Lua config evaluates a Lua expression, so
-- the only way to run a bind from the cheatsheet is to know the expression it was
-- declared with. This is Omarchy's answer too (bin/omarchy-menu-keybindings).
--
-- Usage: lua recorder.lua <configDir> <module>...
-- The modules are the ones hyprland.lua requires for binds, in its order; a
-- module whose file does not exist is skipped, the same as hyprland.lua does.
--
-- Every hl.* call other than bind/define_submap is a no-op here; nothing is
-- executed. `expr` is null for a bind that cannot be replayed: a Lua function,
-- a `mouse = true` bind (drag needs a held button), or an argument that is not
-- a literal.

local configDir = arg[1]
if not configDir then
    io.stderr:write("usage: recorder.lua <configDir> <module>...\n")
    os.exit(2)
end
package.path = configDir .. "/?.lua;" .. configDir .. "/?/init.lua;" .. package.path

local MODIFIERS = {
    SHIFT = 1, CAPS = 2, CTRL = 4, CONTROL = 4, ALT = 8, MOD2 = 16, MOD3 = 32,
    SUPER = 64, WIN = 64, LOGO = 64, MOD4 = 64, MOD5 = 128,
}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "SUPER + SHIFT + code:82" -> 65, "code:82". The last non-modifier token is
-- the key, which is how `hyprctl binds` reports it.
local function parseKeys(keys)
    local modmask, key = 0, ""
    for part in tostring(keys or ""):gmatch("[^+]+") do
        local value = trim(part)
        local mod = MODIFIERS[value:upper()]
        if mod then
            if modmask & mod == 0 then modmask = modmask + mod end
        elseif value ~= "" then
            key = value
        end
    end
    return modmask, key
end

-- A value as Lua source, or nil when it has no literal form.
local literal
local function tableLiteral(t)
    local parts = {}
    local n = #t
    for i = 1, n do
        local v = literal(t[i])
        if v == nil then return nil end
        parts[#parts + 1] = v
    end
    local keys = {}
    for k in pairs(t) do
        if not (math.type(k) == "integer" and k >= 1 and k <= n) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local v = literal(t[k])
        if v == nil then return nil end
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
            parts[#parts + 1] = k .. " = " .. v
        else
            local kl = literal(k)
            if kl == nil then return nil end
            parts[#parts + 1] = "[" .. kl .. "] = " .. v
        end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

literal = function(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then
        if v.__dispatcher then return v.expr end
        return tableLiteral(v)
    end
    return nil
end

-- hl.dsp.window.move({ workspace = "r+1" }) records the call as its own source.
local function dispatcherProxy(path)
    return setmetatable({}, {
        __index = function(_, k) return dispatcherProxy(path .. "." .. tostring(k)) end,
        __call = function(_, ...)
            local args = table.pack(...)
            local parts = {}
            for i = 1, args.n do
                local lit = literal(args[i])
                if lit == nil then return { __dispatcher = true, expr = nil } end
                parts[#parts + 1] = lit
            end
            return { __dispatcher = true, expr = path .. "(" .. table.concat(parts, ", ") .. ")" }
        end,
    })
end

-- What every other hl.* call returns: callable, indexable, and empty to ipairs.
local anything = {}
setmetatable(anything, {
    __index = function(_, k) if type(k) == "number" then return nil end return anything end,
    __call = function() return anything end,
})

local records = {}
local currentSubmap = ""

hl = setmetatable({}, { __index = function() return anything end })
hl.dsp = dispatcherProxy("hl.dsp")

function hl.bind(keys, dispatcher, opts)
    opts = type(opts) == "table" and opts or {}
    local modmask, key = parseKeys(keys)
    local expr = nil
    if type(dispatcher) == "table" and dispatcher.__dispatcher and not opts.mouse then
        expr = dispatcher.expr
    end
    records[#records + 1] = {
        modmask = modmask,
        key = key,
        submap = currentSubmap,
        description = tostring(opts.description or ""),
        expr = expr,
    }
    return anything
end

function hl.define_submap(name, resetOrFn, fn)
    local body = type(resetOrFn) == "function" and resetOrFn or fn
    if type(body) ~= "function" then return end
    local previous = currentSubmap
    currentSubmap = tostring(name)
    body()
    currentSubmap = previous
end

-- A config's print would land in the JSON.
print = function(...)
    local parts = table.pack(...)
    for i = 1, parts.n do parts[i] = tostring(parts[i]) end
    io.stderr:write(table.concat(parts, "\t"), "\n")
end

local failed = false
local found = 0
for i = 2, #arg do
    local module = arg[i]
    if package.searchpath(module, package.path) then
        found = found + 1
        local ok, err = pcall(require, module)
        if not ok then
            io.stderr:write(module .. ": " .. tostring(err) .. "\n")
            failed = true
        end
    end
end
if found == 0 then
    io.stderr:write("none of the bind modules exist under " .. configDir .. "\n")
    failed = true
end

local function jsonString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        if c == "\n" then return "\\n" end
        if c == "\t" then return "\\t" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

local lines = {}
for _, r in ipairs(records) do
    lines[#lines + 1] = string.format(
        '{"modmask":%d,"key":%s,"submap":%s,"description":%s,"expr":%s}',
        r.modmask, jsonString(r.key), jsonString(r.submap), jsonString(r.description),
        r.expr and jsonString(r.expr) or "null")
end
io.write("[", table.concat(lines, ",\n"), "]\n")
os.exit(failed and 1 or 0)
