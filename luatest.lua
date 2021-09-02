#!/usr/bin/env lua

local io = io

running_in_testmode = true
disable_debug = true

local some_tests_failed = false
local format = string.format
local count_assertions = 0
local count_tests = 0
local count_errors = 0

local current_file = nil
local current_function = nil
local function passed()
    count_assertions = count_assertions + 1
    io.write(".")
end
local function failed()
    count_assertions = count_assertions + 1
    count_errors = count_errors + 1
    io.write("F")
    some_tests_failed = true
end


local function flattensequence(arg)
    local ret = {}
    if type(arg) ~= "table" then return arg end
    for i = 1, #arg do
        if type(arg[i]) == "table" then
            local argi = arg[i]
            if argi[".__type"] == "element" then
                ret[#ret + 1] = argi
            elseif argi[".__type"] == "attribute" then
                ret[#ret + 1] = tostring(argi)
            else
                local tmp = flattensequence(arg[i])
                if type(tmp) == "table" then
                    for j = 1, #tmp do
                        ret[#ret+1] = tmp[j]
                    end
                else
                    ret[#ret+1] = tmp
                end
            end
        else
            ret[#ret+1] = arg[i]
        end
    end
    if #ret == 1 then return ret[1] end
    return ret
end

local function compare_tables(a, b) -- http://lua-users.org/lists/lua-l/2008-12/msg00442.html
    local bi = nil

    for k, v in pairs(a) do
        bi = next(b, bi)
        if type(v) == "table" and type(b[k]) == "table" then
            setmetatable(v, {__tostring = array_to_string, __eq = compare_tables})
            setmetatable(b[k], {__tostring = array_to_string, __eq = compare_tables})
        end
        if v ~= b[k] then
            return false
        end
        if bi == nil then
            return false
        end
    end

    if next(b, bi) ~= nil then
        return false
    end
    return true
end

--
function array_to_string(a)
    local ret = {}
    for _, v in ipairs(a) do
        ret[#ret + 1] = string.format("'%s'", tostring(v))
    end
    return "{ " .. table.concat(ret, ", ") .. " }"
end

local function row()
    local dt = debug.traceback()
    lines = {}
    for s in dt:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines[4]:gsub("^.*:(%d+):.*$", "%1")
end

local function isNaN( v ) return type( v ) == "number" and v ~= v end

-- assert that the result of a is NaN (not a number)
function assert_nan(a, msg)
    a = flattensequence(a)
    if isNaN(a) then passed() return end

    if msg then
        print(msg)
    else
        print(
            string.format(
                "'%s' expected to be NaN.\nFile: %s, function: %s:%d",
                tostring(a),
                current_file,
                current_function,
                row()
            )
        )
    end
    failed()
end

function assert_equal(a, b, msg)
    a = flattensequence(a)
    b = flattensequence(b)

    if type(a) == "table" and type(b) == "table" then
        setmetatable(a, {__tostring = array_to_string, __eq = compare_tables})
        setmetatable(b, {__tostring = array_to_string, __eq = compare_tables})
    end
    if a == b then
        passed()
    else
        if msg then
            print(msg)
        else
            print(
                string.format(
                    "'%s' expected to be equal '%s'.\nFile: %s:%d (%s)",
                    tostring(a),
                    tostring(b),
                    current_file,
                    row(),
                    current_function
                )
            )
        end
        failed()
    end
end

function assert_not_nil(a, msg)
    a = flattensequence(a)

    if a == nil then
        if msg then
            print(msg)
        else
            print(format("'%s' expected to be non nil.\nFile: %s:%d", tostring(a), current_file, row()))
        end
        failed()
    else
        passed()
    end
end

function assert_nil(a, msg)
    a = flattensequence(a)
    if a ~= nil then
        if msg then
            print(msg)
        else
            print(format("'%s' expected to be nil.\nFile: %s:%d", tostring(a), current_file, row()))
        end
        failed()
    else
        passed()
    end
end

function assert_true(a, msg)
    a = flattensequence(a)
    if a ~= true then
        if msg then
            print(format("In %s: %s", current_function, msg))
        else
            print(format("'%s' expected to be true.\nFile: %s:%d", tostring(a), current_file, row()))
        end
        failed()
    else
        passed()
    end
end

function assert_false(a, msg)
    a = flattensequence(a)
    if a ~= false then
        if msg then
            print(msg)
        else
            print(format("'%s' expected to be false.\nFile: %s:%d", tostring(a), current_file, row()))
        end
        failed()
    else
        passed()
    end
end

function assert_fail(...)
    local ok, msg = pcall(...)
    if ok == false then
        passed()
        if msg:match("assertion failed!") then
            return true
        end
    end
    print(string.format("assertion did not fail.\nFile: %s, function: %s:%d", current_file, current_function, row()))
    failed()
end

function assert_not_fail(...)
    local ok, msg = pcall(...)
    if ok == true then
        passed()
        return true
    end
    print(string.format("assertion failed.\nFile: %s, function: %s:%d", current_file, current_function, row()))
    failed()
end

local mod
for _, modname in ipairs(arg) do
    if string.sub(modname, -4, -1) == ".lua" then
        modname = string.sub(modname, 1, -5)
    end
    current_file = modname
    mod = require(modname)

    local setup
    local teardown

    if mod.setup and type(mod.setup) == "function" then
        setup = mod.setup
    else
        setup = function()
        end
    end

    if mod.teardown and type(mod.teardown) == "function" then
        teardown = mod.teardown
    else
        teardown = function()
        end
    end

    local keys = {}
    for k,_ in pairs(mod) do
      keys[#keys + 1] = k
    end
    table.sort(keys)

    for i, k in ipairs(keys) do
        local j = mod[k]
        if string.sub(k, 1, 5) == "test_" and type(j) == "function" then
            count_tests = count_tests + 1
            current_function = k
            setup()
            j()
            teardown()
        end
    end
end

print(string.format("\n%d tests, %d assertions - with errors: %d", count_tests, count_assertions, count_errors))
print("Finished")

if some_tests_failed == true then
    print("tests failed.")
    os.exit(1)
end

print("All tests passed. Great!")

os.exit(0)
