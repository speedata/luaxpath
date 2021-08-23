

dofile("debug.lua")

if disable_debug then
    function enterStep() end
    function leaveStep() end
end

module(..., package.seeall)

local string = unicode.utf8

local stringreader = require("stringreader")

-- local round = function(a, prec)
--     return math.floor(a + 0.5 * prec) -- where prec is 10^n, starting at 0
-- end

local xpathfunctions = {}

local function register(ns, name, fun)
    xpathfunctions[ns] = xpathfunctions[ns] or {}
    xpathfunctions[ns][name] = fun
end

local match = string.match

local function doCompare(cmpfunc, a, b)
    if type(a) == "number" or type(a) == "string" then
        a = {a}
    end
    if type(b) == "number" or type(b) == "string" then
        b = {b}
    end

    local taba = {}
    local tabb = {}
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
        if test(ctx) then
            return thenpart(ctx)
        else
            return elsepart(ctx)
        end
    end
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
        end
        local cur
        cur = tbl[1](ctx)
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
            if nt[2] == "*" then
                infotbl.skip("*")
                f = function(ctx) return ctx.nn:child(xpath_test_eltname("*")) end
            else
                local tmp = parseStepExpr(infotbl)
                f = function(ctx)
                    return tmp(ctx)
                end
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
    local ret
    ret = parsePrimaryExpr(infotbl)
    if ret and not infotbl.eof then
        parsePredicateList(infotbl)
    end
    leaveStep(infotbl, "38 parseFilterExpr")
    return ret
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
        ret = function()
            return tonumber(nexttok)
        end
    elseif nexttoktype == TOK_VAR then
        local varname = infotbl.nexttok[2]
        return function(ctx)
            return ctx.var[varname]
        end
    elseif nexttoktype == TOK_OPENPAREN then
        return parseParenthesizedExpr(infotbl)
    elseif nexttoktype == TOK_OPERATOR and nexttokvalue == "." then
        w("context item")
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
    local ret = parseExpr(infotbl)
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
        local c = string.find(fname, ":")
        prefix = string.sub(fname, 1, c - 1)
        fname = string.sub(fname, c + 1, -1)
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
            if string.match(tok, ":") then
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
        elseif match(c, "[,=/>[<-*!+|?@%]:]") then
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


local function fnBoolean(ctx,args)
    if #args ~= 1 then
        w("Error, boolean() must be called with one element")
        return false
    end
    local arg = args[1](ctx)
    if tonumber(arg) then
        return tonumber(arg) ~= 0
    elseif type(arg) == "boolean" then
        return arg
    elseif type(arg) == "string" then
        return #arg > 0
    elseif type(arg) == "table" and #arg == 0 then
        return false
    end

end

local function fnCount(ctx, args)
    if #args ~= 1 then
        w("error, one argument expected")
        return
    end
    args = args[1](ctx)
    return #args
end

local function fnFalse(ctx, args)
    return false
end

local function fnMax(ctx,args)
    local max = tonumber(args[1](ctx))
    if not max then
        w("First argument in max() is not a number, returning 0")
        return 0
    end
    for i=2,#args do
        local argn = args[i](ctx)
        if tonumber(argn) and tonumber(argn) > max then
            max = tonumber(argn)
        end
    end
    return max
end

local function fnMin(ctx,args)
    local min = tonumber(args[1](ctx))
    if not min then
            w("First argument in min() is not a number, returning 0")
        return 0
    end
    for i=2,#args do
        local argn = args[i](ctx)
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

local function fnNot(ctx,args)
    local arg1 = args[1](ctx)
    return not arg1
end

local function fnPosition(ctx,args)
    local pos = ctx.nn.pos[ctx.nn.current[1]]
    return pos
end

local function fnString(ctx,args)
    local str = get_string_argument(ctx,args,"string")
    if type(str) == "string" then return str end
    local ret = {}
    for i = 1, #str do
        local cur = str[i]
        ret[#ret+1] = tostring(cur)
    end
    return table.concat(ret,"")
end

local function fnUpperCase(ctx,args)
    local str = get_string_argument(ctx,args,"upper-case")
    return string.upper(str)
end

local function fnTrue(ctx, args)
    return true
end

register("", "boolean", fnBoolean)
register("", "count", fnCount)
register("", "false", fnFalse)
register("", "max",fnMax)
register("", "min",fnMin)
register("", "not",fnNot)
register("", "position",fnPosition)
register("", "normalize-space", fnNormalizeSpace)
register("", "string",fnString)
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
        current  = xmltree,
        pos      = {},
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
            return v
        end
    end
}

function NodeNavigator:attributes(name)
    name = name or "*"
    local attributes = {}
    for i = 1, #self.current do
        local cur = self.current[i]
        if type(cur) == "table" then
            for attname, attvalue in pairs(cur.attributes) do
                if name ~= "*" and attname == name or name == "*" then
                    table.insert(attributes,setmetatable({[attname] = attvalue},attmt))
                end
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
            self.pos[cur] = 1
            if testfunc(cur) then
                selection[#selection+1] = cur
            end
        end
    else
        for i = 1, #self.current do
            local pos = 0
            for j = 1, #self.current[i] do
                local cur = self.current[i][j]
                if testfunc(cur) then
                    pos = pos + 1
                    self.pos[cur] = pos
                    selection[#selection+1] = cur
                end
            end
        end
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
    for i = 1, #sel do
        self.current = { sel[i] }
        local pr = predicate(ctx)
        if type(pr) == "number" then
            if pr == self.pos[sel[i]] then
                res[#res+1] = sel[i]
                self.pos[sel[i]] = c
                c = c + 1
            end
        elseif pr then
            res[#res+1] = sel[i]
            self.pos[sel[i]] = c
            c = c + 1
        end
    end
    self.current = res
end




return {
    parse = parse,
    register = register,
    NodeNavigator = NodeNavigator
}
