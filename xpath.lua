

dofile("debug.lua")

function enterStep() end
function leaveStep() end

local xstring
-- texlua has slnunicode, otherwise you should use lua-utf8 from luarocks
if unicode and unicode.utf8 then
    xstring = unicode.utf8
else
    local utf8 = require 'lua-utf8'
    if utf8 then
        xstring = utf8
        xstring.format = string.format
    end
end

local match = xstring.match

local stringreader = require("stringreader")
local xpathfunctions = {}

local function register(ns, name, fun)
    xpathfunctions[ns] = xpathfunctions[ns] or {}
    xpathfunctions[ns][name] = fun
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

local function isEmptySequence(arg)
    if arg == nil then return true end
    while true do
        if type(arg) == "table" and #arg == 1 and not arg[".__type"] then
            arg = arg[1]
        else
            break
        end
    end
    return type(arg) == "table" and next(arg) == nil
end

local function doCompare(cmpfunc, a, b)
    if type(a) == "table" and a[".__type"] == "attribute" then
        a = tostring(a)
    else
        a = flattensequence(a)
    end
    if type(b) == "table" and b[".__type"] == "attribute" then
        b = tostring(b)
    else
        b = flattensequence(b)
    end

    if type(a) == "number" or type(a) == "string" then
        a = {a}
    end
    if type(b) == "number" or type(b) == "string" then
        b = {b}
    end

    local taba = {}
    local tabb = {}
    if not a then return false end
    for i = 1, #a do
        taba[i] = tostring(a[i])
    end
    for i = 1, #b do
        tabb[i] = tostring(b[i])
    end
    a = taba
    b = tabb

    for ca = 1, #a do
        for cb = 1, #b do
            if cmpfunc(a[ca], b[cb]) then
                return true
            end
        end
    end
    return false
end

local function isEqual(a, b)
    return a == b
end
local function isNotEqual(a, b)
    return a ~= b
end
local function isLess(a, b)
    return a < b
end
local function isLessEqual(a, b)
    return a <= b
end
local function isGreater(a, b)
    return a > b
end
local function isGreaterEqual(a, b)
    return a >= b
end

-- Read all space until a non-space is found
local function space(sr)
    if sr:eof() then
        return
    end
    while match(sr:getc(), "%s") do
        if sr:eof() then
            return
        end
    end
    sr:back()
end

local function get_num(sr)
    local ret = {}
    while true do
        if sr:eof() then
            break
        end
        local c = sr:getc()
        if match(c, "[%d.]") then
            table.insert(ret, c)
        else
            sr:back()
            break
        end
    end

    if not sr:eof() and xstring.lower(sr:peek()) == "e" then
        table.insert(ret, "e")
        sr:getc()
        if not sr:eof() and xstring.lower(sr:peek()) == "-" then table.insert(ret, "-") sr:getc() end

        while true do
            if sr:eof() then
                break
            end
            local c = sr:getc()
            if match(c, "[%d.]") then
                table.insert(ret, c)
            else
                sr:back()
                break
            end

        end
    end

    return table.concat(ret, "")
end

local function get_word(sr)
    local ret = {}
    while true do
        if sr:eof() then
            break
        end
        local c = sr:getc()
        if match(c, "[-%a%d]") then
            table.insert(ret, c)
        elseif match(c, ":") and match(sr:peek(), "%a") then
            table.insert(ret, c)
        else
            sr:back()
            break
        end
    end
    return table.concat(ret, "")
end

local function get_comment(sr)
    local ret = {}
    local level = 1
    sr:getc()
    while true do
        if sr:eof() then
            break
        end
        local c = sr:getc()

        if c == ":" and sr:peek() == ")" then
            level = level - 1
            if level == 0 then
                sr:getc()
                break
            else
                table.insert(ret, ":")
            end
        elseif c == "(" and sr:peek() == ":" then
            level = level + 1
            sr:getc()
            table.insert(ret, "(:")
        else
            table.insert(ret, c)
        end
    end
    return table.concat(ret)
end

local function get_delimited_string(sr)
    local ret = {}
    local delim = sr:getc()
    while true do
        if sr:eof() then
            break
        end
        local c = sr:getc()
        if c ~= delim then
            table.insert(ret, c)
        else
            break
        end
    end
    return table.concat(ret, "")
end


local function xpath_test_eltname(eltname)
    return function(xmlelt)
        if type(xmlelt) == "table" and ( xmlelt[".__name"] == eltname or eltname == "*") then
            return true
        end
        return false
    end
end


local TOK_WORD = 1
local TOK_VAR = 2
local TOK_OPENPAREN = 3
local TOK_CLOSEPAREN = 4
local TOK_STRING = 7
local TOK_COMMENT = 8
local TOK_NUMBER = 9
local TOK_OPERATOR = 10
local TOK_OCCURRENCEINDICATOR = 11
local TOK_OPENBRACKET = 12
local TOK_CLOSEBRACKET = 13
local TOK_QNAME = 14
local TOK_NCNAME = 15


local opBooleanEqual

-- [2] Expr ::= ExprSingle ("," ExprSingle)*
function parseExpr(infotbl)
    enterStep(infotbl, "2 parseExpr")
    local ret = {}
    ret[#ret + 1] = parseExprSingle(infotbl)
    while true do
        local nt = infotbl.peek()
        if nt and nt[2] == "," then
            infotbl.skip(",")
            ret[#ret + 1] = parseExprSingle(infotbl)
        else
            break
        end
    end
    leaveStep(infotbl, "2 parseExpr")

    return function(ctx)
        assert(ctx)
        if #ret == 1 then
            return ret[1](ctx)
        else
            local new = {}
            for i = 1, #ret do
                table.insert(new, ret[i](ctx))
            end
            return new
        end
    end
end

-- [3] ExprSingle ::= ForExpr | QuantifiedExpr | IfExpr | OrExpr
function parseExprSingle(infotbl)
    enterStep(infotbl, "3 parseExprSingle")
    local nexttok = infotbl.peek()
    local ret
    if nexttok then
        local nexttoktype = nexttok[1]
        local nexttokvalue = nexttok[2]
        if nexttokvalue == "for" then
            ret = parseForExpr(infotbl)
        elseif nexttokvalue == "some" or nexttokvalue == "every" then
            parseQuantifiedExpr(infotbl)
        elseif nexttokvalue == "if" then
            ret = parseIfExpr(infotbl)
        else
            ret = parseOrExpr(infotbl)
        end
    end
    leaveStep(infotbl, "3 parseExprSingle")
    return ret
end

-- [4] ForExpr ::= SimpleForClause "return" ExprSingle

-- Parse `for $foo in ... return` expression
---@return function contextevaluator
function parseForExpr(infotbl)
    enterStep(infotbl, "4 parseForExpr")
    local sfc = parseSimpleForClause(infotbl)
    infotbl.skip("return")
    local ret = parseExprSingle(infotbl)
    leaveStep(infotbl, "4 parseForExpr")
    return function(ctx)
        assert(ctx)
        local varname, tbl = sfc(ctx)
        local newret = {}
        for i = 1, #tbl do
            ctx.var[varname] = tbl[i]
            table.insert(newret, ret(ctx))
        end
        return newret
    end
end

-- [5] SimpleForClause ::= "for" "$" VarName "in" ExprSingle ("," "$" VarName "in" ExprSingle)*
function parseSimpleForClause(infotbl)
    enterStep(infotbl, "5 parseSimpleForClause")
    infotbl.skip("for")
    local nexttok = infotbl.peek()
    local nexttoktype = nexttok[1]
    local varname = nexttok[2]
    if nexttoktype ~= TOK_VAR then
        w("parse error simpleForClause")
    end
    _ = infotbl.nexttok
    infotbl.skip("in")
    local ret = parseExprSingle(infotbl)
    leaveStep(infotbl, "5 parseSimpleForClause")
    return function(ctx)
        assert(ctx)
        return varname, ret(ctx)
    end
end

-- [6] QuantifiedExpr ::= ("some" | "every") "$" VarName "in" ExprSingle ("," "$" VarName "in" ExprSingle)* "satisfies" ExprSingle

-- [7] IfExpr ::= "if" "(" Expr ")" "then" ExprSingle "else" ExprSingle
function parseIfExpr(infotbl)
    enterStep(infotbl, "7 parseIfExpr")
    local nexttok = infotbl.nexttok
    if nexttok[2] ~= "if" then
        w("parse error, 'if' expected")
    end
    infotbl.skiptoken(TOK_OPENPAREN)
    local test = parseExpr(infotbl)
    infotbl.skiptoken(TOK_CLOSEPAREN)
    infotbl.skip("then")
    local thenpart = parseExprSingle(infotbl)
    infotbl.skip("else")
    local elsepart = parseExprSingle(infotbl)
    leaveStep(infotbl, "7 parseIfExpr")
    return function(ctx)
        assert(ctx)
        if opBooleanEqual(test(ctx),true) then
            return thenpart(ctx)
        else
            return elsepart(ctx)
        end
    end
end


local function booleanValue(arg)
    if arg == nil then return false end
    if tonumber(arg) then
        return tonumber(arg) ~= 0
    elseif type(arg) == "boolean" then
        return arg
    elseif type(arg) == "string" then
        return #arg > 0
    elseif type(arg) == "table" and #arg == 0 then
        return false
    elseif type(arg) == "table" and #arg == 1 then
        return booleanValue(arg[1])
    end
    return true
end

function opBooleanEqual(a,b)
    local a = booleanValue(a)
    local b = booleanValue(b)
    return a == b
end

-- [8] OrExpr ::= AndExpr ( "or" AndExpr )*
function parseOrExpr(infotbl)
    enterStep(infotbl, "8 parseOrExpr")
    local ret = parseAndExpr(infotbl)
    if ret == nil then
        return nil
    end
    local tmp = {ret}
    while true do
        local nexttok = infotbl.peek()
        if nexttok and nexttok[2] == "or" then
            _ = infotbl.nexttok
            tmp[#tmp + 1] = parseAndExpr(infotbl)
        else
            break
        end
    end
    if #tmp == 1 then
        -- ok, just use the value of AndExpr
    else
        ret = function(ctx)
            for i = 1, #tmp do
                if tmp[i](ctx) then
                    return true
                end
            end
            return false
        end
    end
    leaveStep(infotbl, "8 parseOrExpr")
    return ret
end

-- [9] AndExpr ::= ComparisonExpr ( "and" ComparisonExpr )*
function parseAndExpr(infotbl)
    enterStep(infotbl, "9 parseAndExpr")
    local ret = parseComparisonExpr(infotbl)
    if ret == nil then
        return nil
    end
    local tmp = {ret}
    while true do
        local nexttok = infotbl.peek()
        if nexttok and nexttok[2] == "and" then
            _ = infotbl.nexttok
            tmp[#tmp + 1] = parseAndExpr(infotbl)
        else
            break
        end
    end
    if #tmp == 1 then
        -- ok, just use the value of ComparisonExpr
    else
        ret = function(ctx)
            for i = 1, #tmp do
                if not tmp[i](ctx) then
                    return false
                end
            end
            return true
        end
    end
    leaveStep(infotbl, "9 parseAndExpr")
    return ret
end

-- [10] ComparisonExpr ::= RangeExpr ( (ValueComp | GeneralComp| NodeComp) RangeExpr )?
function parseComparisonExpr(infotbl)
    enterStep(infotbl, "10 parseComparisonExpr")
    local lhs = parseRangeExpr(infotbl)
    if lhs == nil then
        return nil
    end

    local nexttok = infotbl.peek()
    -- [23] ValueComp	   ::= "eq" | "ne" | "lt" | "le" | "gt" | "ge"
    -- [22] GeneralComp	   ::= "=" | "!=" | "<" | "<=" | ">" | ">="
    -- [24] NodeComp	   ::= "is" | "<<" | ">>"
    local ret = lhs
    if
        nexttok and
            (nexttok[2] == "eq" or nexttok[2] == "ne" or nexttok[2] == "lt" or nexttok[2] == "le" or nexttok[2] == "gt" or
                nexttok[2] == "ge" or
                nexttok[2] == "=" or
                nexttok[2] == "!=" or
                nexttok[2] == "<" or
                nexttok[2] == "<=" or
                nexttok[2] == ">" or
                nexttok[2] == ">=" or
                nexttok[2] == "is" or
                nexttok[2] == "<<" or
                nexttok[2] == ">>")
     then
        local op = (infotbl.nexttok)[2]
        local rhs = parseRangeExpr(infotbl)
        if op == "=" then
            ret = function(ctx)
                return doCompare(isEqual, lhs(ctx), rhs(ctx))
            end
        elseif op == "!=" then
            ret = function(ctx)
                return doCompare(isNotEqual, lhs(ctx), rhs(ctx))
            end
        elseif op == "<" then
            ret = function(ctx)
                return doCompare(isLess, lhs(ctx), rhs(ctx))
            end
        elseif op == "<=" then
            ret = function(ctx)
                return doCompare(isLessEqual, lhs(ctx), rhs(ctx))
            end
        elseif op == ">" then
            ret = function(ctx)
                return doCompare(isGreater, lhs(ctx), rhs(ctx))
            end
        elseif op == ">=" then
            ret = function(ctx)
                return doCompare(isGreaterEqual, lhs(ctx), rhs(ctx))
            end
        elseif op == "eq" then
            ret = function(ctx)
                return doCompare(isEqual, lhs(ctx), rhs(ctx))
            end
        elseif op == "ne" then
            ret = function(ctx)
                return doCompare(isNotEqual, lhs(ctx), rhs(ctx))
            end
        elseif op == "lt" then
            ret = function(ctx)
                return doCompare(isLess, lhs(ctx), rhs(ctx))
            end
        elseif op == "le" then
            ret = function(ctx)
                return doCompare(isLessEqual, lhs(ctx), rhs(ctx))
            end
        elseif op == "gt" then
            ret = function(ctx)
                return doCompare(isGreater, lhs(ctx), rhs(ctx))
            end
        elseif op == "ge" then
            ret = function(ctx)
                return doCompare(isGreaterEqual, lhs(ctx), rhs(ctx))
            end
        end
    end
    leaveStep(infotbl, "10 parseComparisonExpr")
    return ret
end

-- [11]   	RangeExpr  ::=  AdditiveExpr ( "to" AdditiveExpr )?
function parseRangeExpr(infotbl)
    enterStep(infotbl, "11 parseRangeExpr")
    local ae = parseAdditiveExpr(infotbl)
    local nt = infotbl.peek()
    local ret
    if nt and nt[2] == "to" then
        _ = infotbl.nexttok
        local to = parseAdditiveExpr(infotbl)
        ret = function(ctx)
            assert(ctx)
            local newret = {}
            for i = ae(ctx), to(ctx) do
                table.insert(newret, i)
            end
            return newret
        end
    else
        ret = ae
    end
    leaveStep(infotbl, "11 parseRangeExpr")
    return ret
end

-- [12]	AdditiveExpr ::= MultiplicativeExpr ( ("+" | "-") MultiplicativeExpr )*
function parseAdditiveExpr(infotbl)
    enterStep(infotbl, "12 parseAdditiveExpr")
    ret = parseMultiplicativeExpr(infotbl)
    local tbl = {}
    if ret == nil then
        return nil
    end
    tbl[#tbl + 1] = ret
    while true do
        local operator = infotbl.peek()
        if not operator then
            break
        end
        if operator[2] == "+" or operator[2] == "-" then
            tbl[#tbl + 1] = operator[2]
            local op = infotbl.nexttok
            tbl[#tbl + 1] = parseMultiplicativeExpr(infotbl)
        else
            break
        end
    end
    leaveStep(infotbl, "12 parseAdditiveExpr")
    return function(ctx)
        assert(ctx)
        local cur
        cur = tbl[1](ctx)
        local i = 1
        while i < #tbl do
            if tbl[i + 1] == "+" then
                cur = cur + tbl[i + 2](ctx)
            else
                cur = cur - tbl[i + 2](ctx)
            end
            i = i + 2
        end
        return cur
    end
end

-- [13]	MultiplicativeExpr ::= 	UnionExpr ( ("*" | "div" | "idiv" | "mod") UnionExpr )*
function parseMultiplicativeExpr(infotbl)
    enterStep(infotbl, "13 parseMultiplicativeExpr")

    local ret = parseUnionExpr(infotbl)
    if ret == nil then
        return nil
    end
    local tbl = {}
    tbl[#tbl + 1] = ret
    while true do
        local operator = infotbl.peek()
        if operator == nil then
            break
        end
        if operator[2] == "*" or operator[2] == "div" or operator[2] == "idiv" or operator[2] == "mod" then
            tbl[#tbl + 1] = operator[2]
            local op = infotbl.nexttok
            tbl[#tbl + 1] = parseUnionExpr(infotbl)
        else
            break
        end
    end
    leaveStep(infotbl, "13 parseMultiplicativeExpr")
    return function(ctx)
        if #tbl == 0 then
            return tbl
        elseif #tbl == 1 then
            return tbl[1](ctx)
        end
        local cur
        cur = tbl[1](ctx)
        cur = flattensequence(cur)
        local i = 1
        while i < #tbl do
            if tbl[i + 1] == "*" then
                cur = cur * tbl[i + 2](ctx)
            elseif tbl[i + 1] == "div" then
                cur = cur / tbl[i + 2](ctx)
            elseif tbl[i + 1] == "idiv" then
                local first = cur
                local second = tbl[i + 2](ctx)
                local a = first / second
                if a > 0 then
                    cur = math.floor(a)
                else
                    cur = math.ceil(a)
                end
            elseif tbl[i + 1] == "mod" then
                cur = cur % tbl[i + 2](ctx)
            end
            i = i + 2
        end
        return cur
    end
end

-- [14] UnionExpr ::= IntersectExceptExpr ( ("union" | "|") IntersectExceptExpr )*
function parseUnionExpr(infotbl)
    enterStep(infotbl, "14 parseUnionExpr")
    local ret
    ret = parseIntersectExceptExpr(infotbl)
    -- while...
    -- check for "union" or "|" then parse another IntersectExceptExpr
    leaveStep(infotbl, "14 parseUnionExpr")
    return ret
end

-- [15]	IntersectExceptExpr	 ::= InstanceofExpr ( ("intersect" | "except") InstanceofExpr )*
function parseIntersectExceptExpr(infotbl)
    enterStep(infotbl, "15 parseIntersectExceptExpr")
    local ret
    ret = parseInstanceofExpr(infotbl)
    -- while...
    -- check for "intersect" or "except" then parse another InstanceofExpr
    leaveStep(infotbl, "15 parseIntersectExceptExpr")
    return ret
end

-- [16] InstanceofExpr ::= TreatExpr ( "instance" "of" SequenceType )?
function parseInstanceofExpr(infotbl)
    enterStep(infotbl, "16 parseInstanceofExpr")
    local ret = parseTreatExpr(infotbl)
    leaveStep(infotbl, "16 parseInstanceofExpr")
    return ret
end

-- [17] TreatExpr ::= CastableExpr ( "treat" "as" SequenceType )?
function parseTreatExpr(infotbl)
    enterStep(infotbl, "17 parseTreatExpr")
    local ret = parseCastableExpr(infotbl)
    leaveStep(infotbl, "17 parseTreatExpr")
    return ret
end

-- [18] CastableExpr ::= CastExpr ( "castable" "as" SingleType )?
function parseCastableExpr(infotbl)
    enterStep(infotbl, "18 parseCastableExpr")
    local ret = parseCastExpr(infotbl)
    leaveStep(infotbl, "18 parseCastableExpr")
    return ret
end

-- [19] CastExpr ::= UnaryExpr ( "cast" "as" SingleType )?
function parseCastExpr(infotbl)
    enterStep(infotbl, "19 parseCastExpr")
    local ret = parseUnaryExpr(infotbl)
    leaveStep(infotbl, "19 parseCastExpr")
    return ret
end

-- [20] UnaryExpr ::= ("-" | "+")* ValueExpr
function parseUnaryExpr(infotbl)
    enterStep(infotbl, "20 parseUnaryExpr")
    local mult = 1
    while true do
        local nexttok = infotbl.peek()
        if nexttok and nexttok[2] == "-" or nexttok[2] == "+" then
            local op = infotbl.nexttok
            if op[2] == "-" then
                mult = mult * -1
            end
        else
            break
        end
    end
    local ret = parseValueExpr(infotbl)
    leaveStep(infotbl, "20 parseUnaryExpr")
    if mult == -1 then
        return function(ctx)
            return -1 * ret(ctx)
        end
    else
        return ret
    end
end

-- [21]	ValueExpr ::= PathExpr
function parseValueExpr(infotbl)
    enterStep(infotbl, "21 parseValueExpr")
    local ret = parsePathExpr(infotbl)
    leaveStep(infotbl, "21 parseValueExpr")
    return ret
end

-- [25] PathExpr ::= ("/" RelativePathExpr?) | ("//" RelativePathExpr) | RelativePathExpr
function parsePathExpr(infotbl)
    enterStep(infotbl, "25 parsePathExpr")
    local nexttok = infotbl.peek()
    if not nexttok then
        leaveStep(infotbl, "25 parsePathExpr")
        return
    end
    local rpe, ret
    if nexttok[2] == "/" then
        infotbl.skip("/")
        rpe = parseRelativePathExpr(infotbl)
        if rpe then
            ret = function(ctx)
                local nn = ctx.nn
                nn:root()
                return rpe(ctx)
            end
        else
            ret = function(ctx)
                local nn = ctx.nn
                return nn:root()
            end
        end
    else
        ret = parseRelativePathExpr(infotbl)
    end
    leaveStep(infotbl, "25 parsePathExpr")
    return ret
end

-- [26] RelativePathExpr ::= StepExpr (("/" | "//") StepExpr)*
function parseRelativePathExpr(infotbl)
    enterStep(infotbl, "26 parseRelativePathExpr")
    local ret = {}
    ret[#ret+1] = parseStepExpr(infotbl)
    while true do
        local nt = infotbl.peek()
        if not nt then
            break
        end
        if nt[2] == "/" or nt[2] == "//" then
            infotbl.skip(nt[2])
            nt = infotbl.peek()
            local f
            local tmp = parseStepExpr(infotbl)
            f = function(ctx)
                local save_current = ctx.nn.current
                local seret = {}
                for i = 1, #save_current do
                    ctx.nn.current = save_current[i]
                    local x = tmp(ctx)
                    table.insert(seret,x)
                end
                return seret
            end
            ret[#ret+1] = f
        else
            break
        end
    end
    leaveStep(infotbl, "26 parseRelativePathExpr")
    if #ret == 0 then return nil end
    if #ret == 1 then return ret[1] end
    return function (ctx)
        local newret
        for i = 1, #ret do
            newret = ret[i](ctx)
        end
        return newret
    end
end

-- 27 StepExpr := FilterExpr | AxisStep
function parseStepExpr(infotbl)
    enterStep(infotbl, "27 parseStepExpr")
    local ret = parseFilterExpr(infotbl)
    if not ret then
        ret = parseAxisStep(infotbl)
    end
    leaveStep(infotbl, "27 parseStepExpr")
    return ret
end

-- [28] AxisStep ::= (ReverseStep | ForwardStep) PredicateList
function parseAxisStep(infotbl)
    enterStep(infotbl, "28 parseAxisStep")
    local ret = parseReverseStep(infotbl)
    if not ret then
        ret = parseForwardStep(infotbl)
    end
    local pl = parsePredicateList(infotbl)
    local newret = ret
    if #pl > 0 then
        newret = function(ctx)
            ret(ctx)
            for i = 1, #pl do
                local predicate = pl[i]
                ctx.nn:filter(ctx,predicate)
            end
            return ctx.nn.current
        end
    end
    leaveStep(infotbl, "28 parseAxisStep")
    return newret
end

-- [29] ForwardStep ::= (ForwardAxis NodeTest) | AbbrevForwardStep
function parseForwardStep(infotbl)
    enterStep(infotbl, "29 parseForwardStep")
    -- ForwardAxis is something like child:: descendant::
    local pfa = parseForwardAxis(infotbl)
    local pnt,ret
    if pfa then
        pnt = parseNodeTest(infotbl)
        ret = function(ctx) return ctx.nn:child(xpath_test_eltname(pfa)) end
    else
        local attributes = false
        local nt = infotbl.peek()
        -- [31] AbbrevForwardStep == "@"? NodeTest
        if nt and nt[2] == "@" then
            _ = infotbl.nexttok
            attributes = true
        end
        pnt = parseNodeTest(infotbl)
        if pnt then
            if attributes then
                ret = function(ctx) return ctx.nn:attributes(pnt) end
            else
                ret = function(ctx) return ctx.nn:child(xpath_test_eltname(pnt)) end
            end
        end
    end
    leaveStep(infotbl, "29 parseForwardStep")
    return ret
end

-- [30] ForwardAxis ::= ("child" "::") | ("descendant" "::")| ("attribute" "::")| ("self" "::")| ("descendant-or-self" "::")| ("following-sibling" "::")| ("following" "::")| ("namespace" "::")
function parseForwardAxis(infotbl)
    enterStep(infotbl, "30 parseForwardAxis")
    local nt = infotbl.peek()
    local nt2 = infotbl.peek(2)
    local ret
    if nt and nt2 and nt2 == "::" then
        local opname = nt[2]
        if
                opname == "child" or opname == "descendant" or opname == "attribute" or opname == "self" or
                    opname == "descendant-or-self" or
                    opname == "following-sibling" or
                    opname == "following" or
                    opname == "namespace"
         then
            _ = infotbl.nexttok
            _ = infotbl.nexttok
            ret = {}
        end
    else
        -- w("else")
    end
    leaveStep(infotbl, "30 parseForwardAxis")
end

-- [32] ReverseStep ::= (ReverseAxis NodeTest) | AbbrevReverseStep
-- [34] AbbrevReverseStep ::= ".."
function parseReverseStep(infotbl)
    enterStep(infotbl, "32 parseReverseStep")
    local ret = parseReverseAxis(infotbl)
    if ret then
        ret = parseNodeTest(infotbl)
    else
        local nt = infotbl.peek()
        if nt and nt[2] == ".." then
            ret = {}
        end
    end
    leaveStep(infotbl, "32 parseReverseStep")
    return ret
end

-- [33] ReverseAxis ::= ("parent" "::") | ("ancestor" "::") | ("preceding-sibling" "::") | ("preceding" "::") | ("ancestor-or-self" "::")
function parseReverseAxis(infotbl)
    enterStep(infotbl, "33 parseReverseAxis")
    local nt = infotbl.peek()
    local nt2 = infotbl.peek(2)
    local ret
    if nt and nt2 then
        local opname = nt[2]
        local doublecolon = nt2[2]
        if
            doublecolon == "::" and
                (opname == "parent" or opname == "ancestor" or opname == "preceding-sibling" or opname == "preceding" or
                    opname == "ancestor-or-self")
         then
            _ = infotbl.nexttok
            _ = infotbl.nexttok
            ret = {}
        end
    end
    leaveStep(infotbl, "33 parseReverseAxis")
    return ret
end

-- [35] NodeTest ::= KindTest | NameTest
function parseNodeTest(infotbl)
    enterStep(infotbl, "35 parseNodeTest")
    local ret
    ret = parseKindTest(infotbl)
    if not ret then
        ret = parseNameTest(infotbl)
    end
    leaveStep(infotbl, "35 parseNodeTest")
    return ret
end

-- [36] NameTest ::= QName | Wildcard
function parseNameTest(infotbl)
    enterStep(infotbl, "36 parseNameTest")
    local nt = infotbl.peek()
    local nt2 = infotbl.peek(2)
    local nt3 = infotbl.peek(3)
    local ret
    if nt then
        if nt[1] == TOK_QNAME or nt[1] == TOK_NCNAME and not ( nt2 and nt2[2] == ":" ) then
            _ = infotbl.nexttok
            ret = nt[2]
        elseif nt[2] == "*" and not (nt2 and nt2[2] == ":" ) then
            _ = infotbl.nexttok
            ret = nt[2]
        else
            if nt2 and nt3 and nt2[2] == ":" then
                if nt3[2] == "*" or nt[2] == "*" then
                    _ = infotbl.nexttok
                    _ = infotbl.nexttok
                    _ = infotbl.nexttok
                    ret = table.concat({nt[2],nt2[2],nt3[2]},"")
                end
            end
        end
    end
    leaveStep(infotbl, "36 parseNameTest")
    return ret
end
-- [37]	Wildcard ::= "*" | (NCName ":" "*") | ("*" ":" NCName)

-- [38]	FilterExpr ::= PrimaryExpr PredicateList
function parseFilterExpr(infotbl)
    enterStep(infotbl, "38 parseFilterExpr")
    local newret
    local ret
    ret = parsePrimaryExpr(infotbl)
    if ret and not infotbl.eof then
        local pl = parsePredicateList(infotbl)
        if #pl > 0 then
            newret = function(ctx)
                ctx.nn.current = ret(ctx)
                for i = 1, #pl do
                    local predicate = pl[i]
                    ctx.nn:filter(ctx,predicate)
                end
                return ctx.nn.current
            end
        else
            newret = ret
        end
    else
        newret = ret
    end
    leaveStep(infotbl, "38 parseFilterExpr")
    return newret
end

-- [39]   	PredicateList ::= Predicate*
function parsePredicateList(infotbl)
    enterStep(infotbl, "39 parsePredicateList")
    local pl = {}
    while true do
        local nexttok = infotbl.peek()
        if nexttok == nil then
            break
        elseif nexttok[1] == TOK_OPENBRACKET then
            pl[#pl+1] = parsePredicate(infotbl)
        else
            break
        end
    end
    leaveStep(infotbl, "39 parsePredicateList")
    return pl
end


-- [40] Predicate ::= "[" Expr "]"
function parsePredicate(infotbl)
    enterStep(infotbl, "40 parsePredicate")
    local ret
    infotbl.skiptoken(TOK_OPENBRACKET)
    ret = parseExpr(infotbl)
    infotbl.skiptoken(TOK_CLOSEBRACKET)
    leaveStep(infotbl, "40 parsePredicate")
    return ret
end

-- [41]	PrimaryExpr ::=	Literal | VarRef | ParenthesizedExpr | ContextItemExpr | FunctionCall
function parsePrimaryExpr(infotbl)
    enterStep(infotbl, "41 parsePrimaryExpr")
    local nexttok = infotbl.peek()
    if not nexttok then
        leaveStep(infotbl, "41 parsePrimaryExpr")
        return ret
    end

    local nexttoktype = nexttok[1]
    local nexttokvalue = nexttok[2]
    local ret
    if nexttoktype == TOK_STRING then
        nexttok = infotbl.nexttok[2]
        ret = function()
            return nexttok
        end
    elseif nexttoktype == TOK_NUMBER then
        nexttok = infotbl.nexttok[2]
        ret = function() return tonumber(nexttok) end
    elseif nexttoktype == TOK_VAR then
        local varname = infotbl.nexttok[2]
        ret = function(ctx) return ctx.var[varname] end
    elseif nexttoktype == TOK_OPENPAREN then
        ret = parseParenthesizedExpr(infotbl)
    elseif nexttoktype == TOK_OPERATOR and nexttokvalue == "." then
        _ = infotbl.nexttok
        ret = function(ctx) return ctx.nn.current end
    elseif nexttoktype == TOK_QNAME or nexttoktype == TOK_NCNAME then
        local op = infotbl.peek(2)
        if op and op[1] == TOK_OPENPAREN then
            ret = parseFunctionCall(infotbl)
        end
    else
        -- w("unknown token")
    end
    leaveStep(infotbl, "41 parsePrimaryExpr")
    return ret
end

-- [46] ParenthesizedExpr ::= "(" Expr? ")"
function parseParenthesizedExpr(infotbl)
    enterStep(infotbl, "46 parseParenthesizedExpr")
    infotbl.skiptoken(TOK_OPENPAREN)
    local expr = parseExpr(infotbl)
    local ret = function (ctx)
        local seq = expr(ctx)
        if isEmptySequence(seq) then return nil end
        return seq
    end
    infotbl.skiptoken(TOK_CLOSEPAREN)
    leaveStep(infotbl, "46 parseParenthesizedExpr")
    return ret
end

-- [48] FunctionCall ::= QName "(" (ExprSingle ("," ExprSingle)*)? ")"
function parseFunctionCall(infotbl)
    enterStep(infotbl, "48 parseFunctionCall")
    local fname = infotbl.nexttok[2]
    infotbl.skiptoken(TOK_OPENPAREN)
    local args = {}
    local nt = infotbl.peek()
    if nt[1] == TOK_CLOSEPAREN then
        -- no exprSingle, shortcut
    else
        local tmp = parseExprSingle(infotbl)
        args[#args + 1] = tmp
        while true do
            nt = infotbl.peek()
            if nt then
                if nt[2] == "," then
                    infotbl.skip(",")
                    args[#args + 1] = parseExprSingle(infotbl)
                else
                    break
                end
            else
                w("close paren expected")
                break
            end
        end
    end
    infotbl.skip(")")
    local prefix = ""
    if match(fname, ":") then
        local c = xstring.find(fname, ":")
        prefix = xstring.sub(fname, 1, c - 1)
        fname = xstring.sub(fname, c + 1, -1)
    end
    leaveStep(infotbl, "48 parseFunctionCall")
    return function(ctx)
        -- first resolve the prefix
        local ns = ctx.ns[prefix] or ""
        local f = xpathfunctions[ns][fname]
        if not f then
            w("function %s not defined", fname)
        end
        return f(ctx, args)
    end
end

-- [53] AtomicType ::= QName

-- [54] KindTest ::= DocumentTest| ElementTest| AttributeTest| SchemaElementTest| SchemaAttributeTest| PITest| CommentTest| TextTest| AnyKindTest
function parseKindTest(infotbl)
    enterStep(infotbl, "54 parseKindTest")
    leaveStep(infotbl, "54 parseKindTest")
end

-- [56] DocumentTest ::= "document-node" "(" (ElementTest | SchemaElementTest)? ")"
function parseDocumentTest(infotbl)
    enterStep(infotbl, "56 parseDocumentTest")
    leaveStep(infotbl, "56 parseDocumentTest")
end

-- [59] PITest ::= "processing-instruction" "(" (NCName | StringLiteral)? ")"
function parsePITest(infotbl)
    enterStep(infotbl, "59 parsePITest")
    leaveStep(infotbl, "59 parsePITest")
end

-- [60] AttributeTest ::= "attribute" "(" (AttribNameOrWildcard ("," QName)?)? ")"
function parseAttributeTest(infotbl)
    enterStep(infotbl, "54 parseAttributeTest")
    leaveStep(infotbl, "54 parseAttributeTest")
end

-- [62] SchemaAttributeTest ::= "schema-attribute" "(" AttributeDeclaration ")"
function parseSchemaAttributeTest(infotbl)
    enterStep(infotbl, "54 parseSchemaAttributeTest")
    leaveStep(infotbl, "54 parseSchemaAttributeTest")
end

-- [63] AttributeDeclaration ::= AttributeName
function parseKindTest(infotbl)
    enterStep(infotbl, "54 parseKindTest")
    leaveStep(infotbl, "54 parseKindTest")
end

-- [64] ElementTest ::= "element" "(" (ElementNameOrWildcard ("," QName "?"?)?)? ")"
function parseElementTest(infotbl)
    enterStep(infotbl, "64 parseElementTest")
    leaveStep(infotbl, "64 parseElementTest")
end

-- [65] ElementNameOrWildcard ::= ElementName | "*"
function parseKindTest(infotbl)
    enterStep(infotbl, "54 parseKindTest")
    leaveStep(infotbl, "54 parseKindTest")
end

-- [66] SchemaElementTest ::= "schema-element" "(" QName ")"
function parseSchemaElementTest(infotbl)
    enterStep(infotbl, "66 parseSchemaElementTest")
    leaveStep(infotbl, "66 parseSchemaElementTest")
end

-- [69] ElementName ::= QName

-- [61] AttribNameOrWildcard ::= AttributeName | "*"
-- [68] AttributeName ::= QName
-- [70] TypeName ::= QName

-- [58] CommentTest ::= "comment" "(" ")"
-- [57] TextTest ::= "text" "(" ")"
-- [55] AnyKindTest ::= "node" "(" ")"

local infomt = {
    __index = function(tbl, key)
        if key == "nexttok" then
            tbl.pos = tbl.pos + 1
            return tbl.tokenlist[tbl.pos - 1]
        elseif key == "peek" then
            return function(n)
                if tbl.pos > #tbl.tokenlist then
                    return nil
                end
                n = n or 1
                return tbl.tokenlist[tbl.pos + n - 1]
            end
        elseif key == "skip" then
            return function(n)
                local tok = tbl.nexttok
                if tok[2] ~= n then
                    w("parse error, expect %q, got %q", n, tok[2])
                end
            end
        elseif key == "skiptoken" then
            return function(n)
                local tok = tbl.nexttok
                if tok[1] ~= n then
                    w("parse error, expect %s, got %s", toktostring(n), toktostring(tok[1]))
                end
            end
        elseif key == "eof" then
            return tbl.pos >= #tbl.tokenlist
        else
            return rawget(tbl, key)
        end
    end
}

local function parse(str)
    local sr = stringreader:new(str)
    local tokenlist = {}
    local infotbl = {
        tokenlist = tokenlist,
        pos = 1
    }
    setmetatable(infotbl, infomt)

    local toks = {}
    local tok
    while true do
        if sr:eof() then
            break
        end
        local c = sr:peek()
        local c2 = sr:peek(2)
        if match(c, "%a") then
            tok = get_word(sr)
            if xstring.match(tok, ":") then
                table.insert(tokenlist, {TOK_QNAME, tok})
            else
                table.insert(tokenlist, {TOK_NCNAME, tok})
            end
        elseif match(c, "%(") then
            sr:getc()
            c = sr:peek()
            if c == ":" then
                tok = get_comment(sr)
                -- table.insert(tokenlist, {TOK_COMMENT, tok})
            else
                table.insert(tokenlist, {TOK_OPENPAREN, "("})
            end
        elseif match(c, "%[") then
            sr:getc()
            table.insert(tokenlist, {TOK_OPENBRACKET, "["})
        elseif match(c, "%]") then
            sr:getc()
            table.insert(tokenlist, {TOK_CLOSEBRACKET, "]"})
        elseif match(c, "%)") then
            sr:getc()
            table.insert(tokenlist, {TOK_CLOSEPAREN, ")"})
        elseif match(c, "%d") then
            tok = get_num(sr)
            table.insert(tokenlist, {TOK_NUMBER, tok})
        elseif match(c, "%$") then
            sr:getc()
            tok = get_word(sr)
            table.insert(tokenlist, {TOK_VAR, tok})
        elseif match(c, "[,=/>[<%-*!+|?@%]:.]") then
            -- ',', =, >=, >>, >, [, <=, <<, <, -, *, !=, +, //, /, |
            local op = sr:getc()

            if op == "/" and sr:peek() == "/" then
                op = "//"
                sr:getc()
            elseif op == "<" and sr:peek() == "<" then
                op = "<<"
                sr:getc()
            elseif op == ">" and sr:peek() == ">" then
                op = ">>"
                sr:getc()
            elseif op == ">" and sr:peek() == "=" then
                op = ">="
                sr:getc()
            elseif op == "<" and sr:peek() == "=" then
                op = "<="
                sr:getc()
            elseif op == "!" and sr:peek() == "=" then
                op = "!="
                sr:getc()
            elseif op == "." and sr:peek() == "." then
                op = ".."
                sr:getc()
            elseif op == ":" and sr:peek() == ":" then
                op = "::"
                sr:getc()
            elseif op == "." then
                -- ok
            end
            table.insert(tokenlist, {TOK_OPERATOR, op})
        elseif match(c, "'") or match(c, '"') then
            tok = get_delimited_string(sr)
            table.insert(tokenlist, {TOK_STRING, tok})
        elseif match(c, "%s") then
            space(sr)
        else
            w("unhandled token %q", c)
            break
        end
    end
    return parseExpr(infotbl)
end

-- ---------------------------------------------------------------------
local function get_string_argument(ctx,args,fromwhere)
    if #args ~= 1 then
        w("error, one argument expected %s",fromwhere)
        return ""
    end
    return args[1](ctx)
end

local function fnAbs(ctx,args)
    local firstarg = args[1](ctx)
    return math.abs(firstarg)
end


local function fnBoolean(ctx,args)
    if #args ~= 1 then
        w("Error, boolean() must be called with one element")
        return false
    end
    local arg = args[1](ctx)
    return booleanValue(arg)
end

local function fnCeiling(ctx,args)
    local arg = args[1](ctx)
    if not tonumber(arg) then return 0/0 end
    return math.ceil(arg)
end

local function fnConcat(ctx,args)
    local ret = ""
    for i=1,#args do
        local arg = args[i](ctx)
        ret = ret .. tostring(arg)
    end
    return ret
end

local function fnCount(ctx, args)
    local arg = args[1](ctx) or {}
    while true do
        if type(arg) == "table" and #arg == 1 and not arg[".__type"] and not ( type(arg[1]) == "table" and arg[1][".__type"]  ) then
            arg = arg[1]
        else
            break
        end
    end

    if type(arg) ~= "table" then return 1 end
    local c = 0

    for i = 1, #arg do
        if not isEmptySequence(arg[i]) then
            c = c + 1
        end
    end
    return c
end

local function fnEmpty(ctx,args)
    local arg = args[1](ctx) or {}
    return isEmptySequence(arg)
end

local function fnFalse(ctx, args)
    return false
end

local function fnFloor(ctx,args)
    local arg = args[1](ctx)
    if not tonumber(arg) then return 0/0 end
    return math.floor(arg)
end

local function fnLast(ctx,args)
    local cur = ctx.nn.current
    if type(arg) == "table" and not(arg[".__type"] ) then
        return cur[".__last"]
    end
end

local function fnLocalname(ctx,args)
    local arg
    if #args == 0 then
        arg = ctx.nn.current
    else
        arg = args[1](ctx)
    end

    while true do
        if type(arg) == "table" and #arg == 1 and not arg[".__type"] then
            arg = arg[1]
        else
            break
        end
    end

    if type(arg) == "table" and arg[".__type"] == "element" then
        return arg[".__local_name"]
    elseif type(arg) == "table" and arg[".__type"] == "attribute" then
        for key, _ in pairs(arg) do
            if not( match(key,"^.__") )  then
                return key
            end
        end
    end

    return ""
end

local function fnMax(ctx,args)
    local tbl = args[1](ctx)
    if #tbl < 2 then return tbl[1] end
    local max = tbl[1]

    for i=2,#tbl do
        local argn = tbl[i]
        if tonumber(argn) and tonumber(argn) > max then
            max = tonumber(argn)
        end
    end
    return max
end

local function fnMin(ctx,args)
    local tbl = args[1](ctx)
    if #tbl < 2 then return tbl[1] end
    local min = tbl[1]

    for i=2,#tbl do
        local argn = tbl[i]
        if tonumber(argn) and tonumber(argn) < min then
            min = tonumber(argn)
        end
    end
    return min
end

local function fnNormalizeSpace(ctx, args)
    local str = get_string_argument(ctx,args,"normalize-space")
    str = str:gsub("^%s*(.-)%s*$","%1"):gsub("[%s\n]+"," ")
    return str
end

local function fnNamespaceURI(ctx,args)
    local arg

    if #args == 0 then
        arg = ctx.nn.current
    else
        arg = args[1](ctx)
    end
    if arg == nil then return "" end

    while true do
        if type(arg) == "table" and #arg == 1 and not arg[".__type"] then
            arg = arg[1]
        else
            break
        end
    end
    if type(arg) == "table" then
        if arg[".__type"] == "element" then
            return arg[".__namespace"]
        end
    end
end

local function fnNot(ctx,args)
    local arg1 = args[1](ctx)
    return not arg1
end

local function fnNumber(ctx,args)
    local arg1 = args[1](ctx)
    if arg1 == 'NaN' then return 0/0 end
    return tonumber(arg1)
end

local function fnPosition(ctx,args)
    local pos = ctx.nn.current[".__pos"]
    return pos
end

local function fnRound(ctx,args)
    local arg1 = args[1](ctx)
    return math.floor(tonumber(arg1) + 0.5)
end

local function stringvalue(arg)
    local ret = {}
    if type(arg) == "table" then
        if arg[".__type"] == "element" then
            for i = 1, #arg do
                ret[#ret+1] = stringvalue(arg[i])
            end
        else
            ret[#ret+1] = tostring(arg)
        end
    else
        ret[#ret+1] = tostring(arg)
    end
    return table.concat(ret,"")
end

local function fnString(ctx,args)
    local str = get_string_argument(ctx,args,"string")
    if type(str) == "string" then return str end

    while true do
        if type(str) == "table" and #str == 1 and not str[".__type"] then
            str = str[1]
        else
            break
        end
    end
    return stringvalue(str)
end

local function fnStringJoin(ctx,args)
    local seq = args[1](ctx) or {}
    local joiner = args[2](ctx)
    local ret = {}
    for i = 1, #seq do
        table.insert(ret,seq[i])
    end
    return table.concat(ret,joiner)
end

local function fnStringLength(ctx,args)
    if #args == 0 then return 0 end
    local str = args[1](ctx)
    return utf8.len(str)
end

local function fnTrue(ctx, args)
    return true
end

local function fnUpperCase(ctx,args)
    local str = get_string_argument(ctx,args,"upper-case")
    return xstring.upper(str)
end

register("", "abs", fnAbs)
register("", "boolean", fnBoolean)
register("", "ceiling", fnCeiling)
register("", "concat", fnConcat)
register("", "count", fnCount,1,1)
register("", "empty", fnEmpty,1,1)
register("", "false", fnFalse)
register("", "floor", fnFloor)
register("", "last", fnLast,0,0)
register("", "local-name", fnLocalname,0,1)
register("", "max",fnMax,1,1)
register("", "min",fnMin,1,1)
register("", "namespace-uri",fnNamespaceURI,0,1)
register("", "not",fnNot)
register("", "normalize-space", fnNormalizeSpace)
register("", "number",fnNumber)
register("", "position",fnPosition)
register("", "round", fnRound,1,1)
register("", "string",fnString)
register("", "string-join", fnStringJoin,2,2)
register("", "string-length", fnStringLength,0,1)
register("", "true", fnTrue)
register("", "upper-case", fnUpperCase)


local NodeNavigator = {}

local function setparents(xmlelt)
    for i = 1, #xmlelt do
        local cur = xmlelt[i]
        if type(cur) == "table" then
            if cur[".__type"] then
                cur[".__parent"] = xmlelt
            end
            setparents(cur)
        end
    end
end

function NodeNavigator:new(xmltree)
    local new_inst = {
        document = xmltree,
    }
    setparents(xmltree)
    setmetatable( new_inst, { __index = NodeNavigator } )
    return new_inst
end

function NodeNavigator:root()
    self.current = self.document
    return self.current
end

local attmt = {
    __tostring = function (tbl,idx)
        for k, v in pairs(tbl) do
            if not xstring.match(k,"^.__") then
                return v
            end
        end
    end
}

function NodeNavigator:attributes(name)
    name = name or "*"
    local attributes = {}
    local cur = self.current

    if type(cur) == "table" then
        if cur[".__attributes"] == nil then return end
        for attname, attvalue in pairs(cur[".__attributes"]) do
            if name ~= "*" and attname == name or name == "*" then
                table.insert(attributes,setmetatable({[attname] = attvalue, [".__type"] = "attribute" },attmt))
            end
        end
    end
    self.current = attributes
    return attributes
end

function NodeNavigator:child(testfunc)
    local selection = {}
    if self.current[".__type"] == "document" then
        for i = 1, #self.current do
            local cur = self.current[i]
            cur[".__pos"] = 1
            if testfunc(cur) then
                selection[#selection+1] = cur
            end
        end
    else
        local pos = 0
        for j = 1, #self.current do
            local cur = self.current[j]
            if testfunc(cur) then
                pos = pos + 1
                cur[".__pos"] = pos
                selection[#selection+1] = cur
            end
        end
    end
    for i = 1, #selection do
        selection[i][".__last"] = #selection
    end
    self.current = selection
    return selection
end

local function recurse(where,what)
    local ret = {}
    for i = 1, #where do
        local cur = where[i]
        if type(cur) == "table" and cur[".__type"] then
            if what(cur) then
                table.insert(ret,cur)
            end
            local r = recurse(cur,what)
            for _, value in pairs(r) do
                table.insert(ret,value)
            end
        else
            if what(cur) then
                table.insert(ret,cur)
            end

        end
    end
    return ret
end

function NodeNavigator:descendantorself(withself,what)
    local selection = {}
    local start = self.current
    if start[".__type"] == "document" then start = {start} end
    if withself then
        local cur = start
        local r = recurse(cur,what)
        for _, value in pairs(r) do
            table.insert(selection,value)
        end
    else
        for i = 1, #start do
            local cur = start[i]
            local r = recurse(cur,what)
            for _, value in pairs(r) do
                table.insert(selection,value)
            end
        end
    end

    self.current = selection
end


function NodeNavigator:filter(ctx,predicate)
    local sel = self.current
    local res = {}
    local c = 1
    if type(sel) ~= "table" then return sel end
    for i = 1, #sel do
        local cur = sel[i]
        if type(cur) ~= "table" then
            self.current = { cur , [".__pos"] = c }
            c = c + 1
        else
            self.current = cur
        end
        cur = self.current
        local pr = predicate(ctx)
        -- for example ...[1]
        if type(pr) == "number" then
            if pr == cur[".__pos"] then
                res[#res+1] = cur
                cur[".__pos"] = c
                c = c + 1
            end
        elseif booleanValue(pr) then
            res[#res+1] = cur
            cur[".__pos"] = c
            c = c + 1
        end
    end
    for i = 1, #res do
        res[i][".__last"] = #res
    end

    self.current = res
end




return {
    parse = parse,
    register = register,
    NodeNavigator = NodeNavigator
}
