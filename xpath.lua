dofile("debug.lua")


module(...,package.seeall)

stringreader = require("stringreader")


local round = function(a, prec)
    return math.floor(a + 0.5*prec) -- where prec is 10^n, starting at 0
end

local xpathfunctions = {}

local function register(ns,name,fun)
    xpathfunctions[ns] = xpathfunctions[ns] or {}
    xpathfunctions[ns][name] = fun
end

local match = unicode.utf8.match

local function doCompare(cmpfunc, a,b)
    if type(a) == "number" then a = {a} end
    if type(b) == "number" then b = {b} end
    local ret = false
    for ca = 1, #a do
        for cb = 1, #b do
            if cmpfunc(a[ca],b[cb]) then
                return true
            end
        end
    end
    return false
end

local function isEqual(a,b) return a == b end
local function isNotEqual(a,b) return a ~= b end
local function isLess(a,b) return a < b end
local function isLessEqual(a,b) return a <= b end
local function isGreater(a,b) return a > b end
local function isGreaterEqual(a,b) return a >= b end

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

local function get_comment()
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
    enterStep(infotbl,"2 parseExpr")
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
    leaveStep(infotbl,"2 parseExpr")
    if #ret == 1 then return ret[1] end
    return function(ctx)
        assert(ctx)
        local new = {}
        for i = 1, #ret do
            table.insert(new,ret[i](ctx))
        end
        return new
    end
end

-- [3] ExprSingle ::= ForExpr | QuantifiedExpr | IfExpr | OrExpr
function parseExprSingle(infotbl)
    enterStep(infotbl,"3 parseExprSinge")
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
    leaveStep(infotbl,"3 parseExprSinge")
    return ret
end

-- [4] ForExpr ::= SimpleForClause "return" ExprSingle
function parseForExpr(infotbl)
    enterStep(infotbl,"4 parseForExpr")
    local sfc = parseSimpleForClause(infotbl)
    infotbl.skip("return")
    local ret = parseExprSingle(infotbl)
    leaveStep(infotbl,"4 parseForExpr")
    return function(ctx)
        assert(ctx)
        local varname, tbl = sfc(ctx)
        local newret = {}
        for i = 1, #tbl do
            ctx.var[varname] = tbl[i]
            table.insert(newret, ret(ctx) )
        end
        return newret
    end
end

-- [5] SimpleForClause ::= "for" "$" VarName "in" ExprSingle ("," "$" VarName "in" ExprSingle)*
function parseSimpleForClause(infotbl)
    enterStep(infotbl,"5 parseSimpleForClause")
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
    leaveStep(infotbl,"5 parseSimpleForClause")
    return function(ctx) assert(ctx) return varname, ret(ctx) end
end

-- [6] QuantifiedExpr ::= ("some" | "every") "$" VarName "in" ExprSingle ("," "$" VarName "in" ExprSingle)* "satisfies" ExprSingle

-- [7] IfExpr ::= "if" "(" Expr ")" "then" ExprSingle "else" ExprSingle
function parseIfExpr(infotbl)
    enterStep(infotbl,"7 parseIfExpr")
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
    leaveStep(infotbl,"7 parseIfExpr")
    return function(ctx) assert(ctx) if test(ctx) then return thenpart(ctx) else return elsepart(ctx) end
        end
end

-- [8] OrExpr ::= AndExpr ( "or" AndExpr )*
function parseOrExpr(infotbl)
    enterStep(infotbl,"8 parseOrExpr")
    local ret = parseAndExpr(infotbl)
    local nexttok = infotbl.peek()
    if nexttok then
        local nexttokvalue = nexttok[2]
    end
    leaveStep(infotbl,"8 parseOrExpr")
    return ret
end

-- [9] AndExpr ::= ComparisonExpr ( "and" ComparisonExpr )*
function parseAndExpr(infotbl)
    enterStep(infotbl,"9 parseAndExpr")
    local ret = parseComparisonExpr(infotbl)
    -- while ...
    leaveStep(infotbl,"9 parseAndExpr")
    return ret
end

-- [10] ComparisonExpr ::= RangeExpr ( (ValueComp | GeneralComp| NodeComp) RangeExpr )?
function parseComparisonExpr(infotbl)
    enterStep(infotbl,"10 parseComparisonExpr")
    local lhs = parseRangeExpr(infotbl)
    local nexttok = infotbl.peek()
    -- [23] ValueComp	   ::= "eq" | "ne" | "lt" | "le" | "gt" | "ge"
    -- [22] GeneralComp	   ::= "=" | "!=" | "<" | "<=" | ">" | ">="
    -- [24] NodeComp	   ::= "is" | "<<" | ">>"
    local ret = lhs
    if nexttok and ( nexttok[2] == "eq" or nexttok[2] == "ne" or nexttok[2] == "lt" or nexttok[2] == "le" or nexttok[2] == "gt" or nexttok[2] == "ge" or nexttok[2] == "=" or nexttok[2] == "!=" or nexttok[2] == "<" or nexttok[2] == "<=" or nexttok[2] == ">" or nexttok[2] == ">=" or nexttok[2] == "is" or nexttok[2] == "<<" or nexttok[2] == ">>") then
        local op = (infotbl.nexttok)[2]
        rhs = parseRangeExpr(infotbl)
        if op == "=" then
            ret = function(ctx) assert(ctx) return doCompare(isEqual,lhs(ctx),rhs(ctx)) end
        elseif op == "!=" then
            ret = function(ctx) assert(ctx) return doCompare(isNotEqual,lhs(ctx),rhs(ctx)) end
        elseif op == "<" then
            ret = function(ctx) assert(ctx) return doCompare(isLess,lhs(ctx),rhs(ctx)) end
        elseif op == "<=" then
            ret = function(ctx) assert(ctx) return doCompare(isLessEqual,lhs(ctx),rhs(ctx)) end
        elseif op == ">" then
            ret = function(ctx) assert(ctx) return doCompare(isGreater,lhs(ctx),rhs(ctx)) end
        elseif op == ">=" then
            ret = function(ctx) assert(ctx) return doCompare(isGreaterEqual,lhs(ctx),rhs(ctx)) end
        elseif op == "eq" then
            ret = function(ctx) assert(ctx) return doCompare(isEqual,lhs(ctx),rhs(ctx)) end
        elseif op == "ne" then
            ret = function(ctx) assert(ctx) return doCompare(isNotEqual,lhs(ctx),rhs(ctx)) end
        elseif op == "lt" then
            ret = function(ctx) assert(ctx) return doCompare(isLess,lhs(ctx),rhs(ctx)) end
        elseif op == "le" then
            ret = function(ctx) assert(ctx) return doCompare(isLessEqual,lhs(ctx),rhs(ctx)) end
        elseif op == "gt" then
            ret = function(ctx) assert(ctx) return doCompare(isGreater,lhs(ctx),rhs(ctx)) end
        elseif op == "ge" then
            ret = function(ctx) assert(ctx) return doCompare(isGreaterEqual,lhs(ctx),rhs(ctx)) end
        end
    end
    leaveStep(infotbl,"10 parseComparisonExpr")
    return ret
end

-- [11]   	RangeExpr  ::=  AdditiveExpr ( "to" AdditiveExpr )?
function parseRangeExpr(infotbl)
    enterStep(infotbl,"11 parseRangeExpr")
    local ret = parseAdditiveExpr(infotbl)
    local nt = infotbl.peek()
    if nt and nt[2] == "to" then
        _ = infotbl.nexttok
        local to = parseAdditiveExpr(infotbl)
        return function(ctx)
            assert(ctx)
            local newret = {}
            for i = ret(ctx),to(ctx) do
                table.insert(newret,i)
            end
            return newret
        end
    else
        return ret
    end
    leaveStep(infotbl,"11 parseRangeExpr")
    return ret
end

-- [12]	AdditiveExpr ::= MultiplicativeExpr ( ("+" | "-") MultiplicativeExpr )*
function parseAdditiveExpr(infotbl)
    enterStep(infotbl,"12 parseAdditiveExpr")
    local tbl = {}
    tbl[#tbl + 1] = parseMultiplicativeExpr(infotbl)
    while true do
        local operator = infotbl.peek()
        if not operator then break end
        if operator[2] == "+" or operator[2] == "-" then
            tbl[#tbl + 1] = operator[2]
            local op = infotbl.nexttok
            tbl[#tbl + 1] = parseMultiplicativeExpr(infotbl)
        else
            break
        end
    end
    leaveStep(infotbl,"12 parseAdditiveExpr")
    return function(ctx)
        assert(ctx)
        local cur
        cur = tbl[1](ctx)
        local i = 1
        while i < #tbl do
            if tbl[i+1] == "+" then
                cur = cur + tbl[i+2](ctx)
            else
                cur = cur - tbl[i+2](ctx)
            end
            i = i + 2
        end
        return cur
    end
end

-- [13]	MultiplicativeExpr ::= 	UnionExpr ( ("*" | "div" | "idiv" | "mod") UnionExpr )*
function parseMultiplicativeExpr(infotbl)
    enterStep(infotbl,"13 parseMultiplicativeExpr")

    local tbl = {}
    tbl[#tbl + 1] = parseUnionExpr(infotbl)
    while true do
        local operator = infotbl.peek()
        if operator == nil then break end
        if operator[2] == "*" or operator[2] == "div" or operator[2] == "idiv" or operator[2] == "mod" then
                tbl[#tbl + 1] = operator[2]
                local op = infotbl.nexttok
                tbl[#tbl + 1] = parseUnionExpr(infotbl)
        else
            break
        end
    end
    leaveStep(infotbl,"13 parseMultiplicativeExpr")
    return function(ctx)
        local cur
        cur = tbl[1](ctx)
        local i = 1
        while i < #tbl do
            if tbl[i+1] == "*" then
                cur = cur * tbl[i+2](ctx)
            elseif tbl[i+1] == "div" then
                cur = cur / tbl[i+2](ctx)
            elseif tbl[i+1] == "idiv" then
                cur = round(cur / tbl[i+2](ctx),0)
            elseif tbl[i+1] == "mod" then
                cur = cur % tbl[i+2](ctx)
            end
            i = i + 2
        end
        return cur
    end
end

-- [14] UnionExpr ::= IntersectExceptExpr ( ("union" | "|") IntersectExceptExpr )*
function parseUnionExpr(infotbl)
    enterStep(infotbl,"14 parseUnionExpr")
    local ret
    ret = parseIntersectExceptExpr(infotbl)
    -- while...
    -- check for "union" or "|" then parse another IntersectExceptExpr
    leaveStep(infotbl,"14 parseUnionExpr")
    return ret
end

-- [15]	IntersectExceptExpr	 ::= InstanceofExpr ( ("intersect" | "except") InstanceofExpr )*
function parseIntersectExceptExpr(infotbl)
    enterStep(infotbl,"15 parseIntersectExceptExpr")
    local ret
    ret = parseInstanceofExpr(infotbl)
    -- while...
    -- check for "intersect" or "except" then parse another InstanceofExpr
    leaveStep(infotbl,"15 parseIntersectExceptExpr")
    return ret
end

-- [16] InstanceofExpr ::= TreatExpr ( "instance" "of" SequenceType )?
function parseInstanceofExpr(infotbl)
    enterStep(infotbl,"16 parseInstanceofExpr")
    local ret = parseTreatExpr(infotbl)
    leaveStep(infotbl,"16 parseInstanceofExpr")
    return ret
end

-- [17] TreatExpr ::= CastableExpr ( "treat" "as" SequenceType )?
function parseTreatExpr(infotbl)
    enterStep(infotbl,"17 parseTreatExpr")
    local ret = parseCastableExpr(infotbl)
    leaveStep(infotbl,"17 parseTreatExpr")
    return ret
end

-- [18] CastableExpr ::= CastExpr ( "castable" "as" SingleType )?
function parseCastableExpr(infotbl)
    enterStep(infotbl,"18 parseCastableExpr")
    local ret = parseCastExpr(infotbl)
    leaveStep(infotbl,"18 parseCastableExpr")
    return ret
end

-- [19] CastExpr ::= UnaryExpr ( "cast" "as" SingleType )?
function parseCastExpr(infotbl)
    enterStep(infotbl,"19 parseCastExpr")
    local ret = parseUnaryExpr(infotbl)
    leaveStep(infotbl,"19 parseCastExpr")
    return ret
end

-- [20] UnaryExpr ::= ("-" | "+")* ValueExpr
function parseUnaryExpr(infotbl)
    enterStep(infotbl,"20 parseUnaryExpr")
    local ret = parseValueExpr(infotbl)
    leaveStep(infotbl,"20 parseUnaryExpr")
    return ret
end

-- [21]	ValueExpr ::= PathExpr
function parseValueExpr(infotbl)
    enterStep(infotbl,"21 parseValueExpr")
    local ret = parsePathExpr(infotbl)
    leaveStep(infotbl,"21 parseValueExpr")
    return ret
end

-- [25] PathExpr ::= ("/" RelativePathExpr?) | ("//" RelativePathExpr) | RelativePathExpr
function parsePathExpr(infotbl)
    enterStep(infotbl,"25 parsePathExpr")
    local ret = parseRelativePathExpr(infotbl)
    leaveStep(infotbl,"25 parsePathExpr")
    return ret
end

-- [26] RelativePathExpr ::= StepExpr (("/" | "//") StepExpr)*
function parseRelativePathExpr(infotbl)
    enterStep(infotbl,"26 parseRelativePathExpr")
    local ret
    ret = parseStepExpr(infotbl)
    while true do
        local nt = infotbl.peek()
        if not nt then
            break
        end
        if nt[2] == "/" or nt[2] == "//"  then
            infotbl.skip(nt[2])
            parseStepExpr(infotbl)
        else
            break
        end
    end
    leaveStep(infotbl,"26 parseRelativePathExpr")
    return ret
end

-- 27 StepExpr := FilterExpr | AxisStep
function parseStepExpr(infotbl)
    enterStep(infotbl,"27 parseStepExpr")
    local ret = parseFilterExpr(infotbl)
    if not ret then
        ret = parseAxisStep(infotbl)
    end
    leaveStep(infotbl,"27 parseStepExpr")
    return ret
end


-- [28] AxisStep ::= (ReverseStep | ForwardStep) PredicateList
function parseAxisStep(infotbl)
    enterStep(infotbl,"28 parseAxisStep")
    ret = parseReverseStep(infotbl)
    if not ret then
        ret = parseForwardStep(infotbl)
    end
    parsePredicateList(infotbl)
    leaveStep(infotbl,"28 parseAxisStep")
    return ret
end

-- [29] ForwardStep ::= (ForwardAxis NodeTest) | AbbrevForwardStep
function parseForwardStep(infotbl)
    enterStep(infotbl,"29 parseForwardStep")
    local ret = parseForwardAxis(infotbl)
    if ret then
        ret = parseNodeTest(infotbl)
    else
        local nt = infotbl.peek()
        -- AbbrevForwardStep == "@"? NodeTest
        if nt and nt[2] == "@" then
            _ = infotbl.nexttok
        end
        ret = parseNodeTest(infotbl)
    end
    leaveStep(infotbl,"29 parseForwardStep")
    return ret
end

-- [30] ForwardAxis ::= ("child" "::") | ("descendant" "::")| ("attribute" "::")| ("self" "::")| ("descendant-or-self" "::")| ("following-sibling" "::")| ("following" "::")| ("namespace" "::")
function parseForwardAxis(infotbl)
    enterStep(infotbl,"30 parseForwardAxis")
    local nt = infotbl.peek()
    local nt = infotbl.peek()
    local nt2 = infotbl.peek(2)
    local ret
    if nt and nt2 then
        local opname = nt[2]
        local doublecolon = nt2[2]
        if doublecolon == "::" and ( opname == "child" or opname == "descendant" or opname == "attribute" or opname == "self" or opname == "descendant-or-self" or opname ==  "following-sibling" or opname == "following" or opname == "namespace" ) then
            w("forward step")
            _ = infotbl.nexttok
            _ = infotbl.nexttok
            ret = {}
        end
    end
    leaveStep(infotbl,"30 parseForwardAxis")
end

-- [32] ReverseStep ::= (ReverseAxis NodeTest) | AbbrevReverseStep
-- [34] AbbrevReverseStep ::= ".."
function parseReverseStep(infotbl)
    enterStep(infotbl,"32 parseReverseStep")
    local ret = parseReverseAxis(infotbl)
    if ret then
        ret = parseNodeTest(infotbl)
    else
        local nt = infotbl.peek()
        if nt and nt[2] == ".." then
            ret = {}
        end
    end
    leaveStep(infotbl,"32 parseReverseStep")
    return ret
end

-- [33] ReverseAxis ::= ("parent" "::") | ("ancestor" "::") | ("preceding-sibling" "::") | ("preceding" "::") | ("ancestor-or-self" "::")
function parseReverseAxis(infotbl)
    enterStep(infotbl,"33 parseReverseAxis")
    local nt = infotbl.peek()
    local nt2 = infotbl.peek(2)
    local ret
    if nt and nt2 then
        local opname = nt[2]
        local doublecolon = nt2[2]
        if doublecolon == "::" and ( opname == "parent" or opname == "ancestor" or opname == "preceding-sibling" or opname == "preceding" or opname == "ancestor-or-self" ) then
            w("reversestep")
            _ = infotbl.nexttok
            _ = infotbl.nexttok
            ret = {}
        end
    end
    leaveStep(infotbl,"33 parseReverseAxis")
    return ret
end

-- [35] NodeTest ::= KindTest | NameTest
function parseNodeTest(infotbl)
    enterStep(infotbl,"35 parseNodeTest")
    local ret
    ret = parseKindTest(infotbl)
    if not ret then
        ret = parseNameTest(infotbl)
    end
    leaveStep(infotbl,"35 parseNodeTest")
    return ret
end

-- [36] NameTest ::= QName | Wildcard
function parseNameTest(infotbl)
    enterStep(infotbl,"36 parseNameTest")
    local nt = infotbl.peek()
    if nt and ( nt[1] == TOK_QNAME or nt[1] == TOK_NCNAME ) then
        _ = infotbl.nexttok
        return true
    end
    leaveStep(infotbl,"36 parseNameTest")
end
-- [37]	Wildcard ::= "*" | (NCName ":" "*") | ("*" ":" NCName)

-- [38]	FilterExpr ::= PrimaryExpr PredicateList
function parseFilterExpr(infotbl)
    enterStep(infotbl,"38 parseFilterExpr")
    local ret
    ret = parsePrimaryExpr(infotbl)
    if ret and not infotbl.eof then
        parsePredicateList(infotbl)
    end
    leaveStep(infotbl,"38 parseFilterExpr")
    return ret
end

-- [39]   	PredicateList ::= Predicate*
function parsePredicateList(infotbl)
    enterStep(infotbl,"39 parsePredicateList")
    while true do
        local nexttok = infotbl.peek()
        if nexttok == nil then
            break
        elseif nexttok[1] == TOK_OPENBRACKET then
            parsePredicate(infotbl)
        else
            break
        end
    end
    leaveStep(infotbl,"39 parsePredicateList")
end


-- [40] Predicate ::= "[" Expr "]"
function parsePredicate(infotbl)
    enterStep(infotbl,"40 parsePredicate")
    infotbl.skiptoken(TOK_OPENBRACKET)
    parseExpr(infotbl)
    infotbl.skiptoken(TOK_CLOSEBRACKET)
    leaveStep(infotbl,"40 parsePredicate")
end

-- [41]	PrimaryExpr ::=	Literal | VarRef | ParenthesizedExpr | ContextItemExpr | FunctionCall
function parsePrimaryExpr(infotbl)
    enterStep(infotbl,"41 parsePrimaryExpr")
    local nexttok = infotbl.peek()
    local nexttoktype = nexttok[1]
    local nexttokvalue = nexttok[2]
    local ret
    if nexttoktype == TOK_STRING then
        local nexttok = infotbl.nexttok[2]
        ret = function() return nexttok end
    elseif nexttoktype == TOK_NUMBER then
        local nexttok = infotbl.nexttok[2]
        ret = function() return tonumber(nexttok) end
    elseif nexttoktype == TOK_VAR then
        local varname = infotbl.nexttok[2]
        return function(ctx) return ctx.var[varname] end
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
        w("unknown token")
    end
    leaveStep(infotbl,"41 parsePrimaryExpr")
    return ret
end


-- [46] ParenthesizedExpr ::= "(" Expr? ")"
function parseParenthesizedExpr(infotbl)
    enterStep(infotbl,"46 parseParenthesizedExpr")
    infotbl.skiptoken(TOK_OPENPAREN)
    local ret = parseExpr(infotbl)
    infotbl.skiptoken(TOK_CLOSEPAREN)
    leaveStep(infotbl,"46 parseParenthesizedExpr")

    return ret
end

-- [48] FunctionCall ::= QName "(" (ExprSingle ("," ExprSingle)*)? ")"
function parseFunctionCall(infotbl)
    enterStep(infotbl,"48 parseFunctionCall")
    local fname = infotbl.nexttok[2]
    w("fname %s",tostring(fname))
    infotbl.skiptoken(TOK_OPENPAREN)
    local args = {}
    args[#args + 1] = parseExprSingle(infotbl)
    while true do
        local nt = infotbl.peek()
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
    infotbl.skip(")")
    local prefix = ""
    if match(fname, ":") then
        local c = string.find(fname,":")
        prefix = string.sub(fname,1,c-1)
        fname = string.sub(fname,c+1,-1)
    end
    leaveStep(infotbl,"48 parseFunctionCall")
    return function(ctx)
        -- first, resolve the prefix
        local ns = ctx.ns[prefix] or ""
        local f = xpathfunctions[ns][fname]
        return f(ctx, args)
    end
end


-- [53] AtomicType ::= QName

-- [54] KindTest ::= DocumentTest| ElementTest| AttributeTest| SchemaElementTest| SchemaAttributeTest| PITest| CommentTest| TextTest| AnyKindTest
function parseKindTest(infotbl)
    enterStep(infotbl,"54 parseKindTest")
    leaveStep(infotbl,"54 parseKindTest")
end

-- [56] DocumentTest ::= "document-node" "(" (ElementTest | SchemaElementTest)? ")"
function parseDocumentTest(infotbl)
    enterStep(infotbl,"56 parseDocumentTest")
    leaveStep(infotbl,"56 parseDocumentTest")
end

-- [59] PITest ::= "processing-instruction" "(" (NCName | StringLiteral)? ")"
function parsePITest(infotbl)
    enterStep(infotbl,"59 parsePITest")
    leaveStep(infotbl,"59 parsePITest")
end

-- [60] AttributeTest ::= "attribute" "(" (AttribNameOrWildcard ("," QName)?)? ")"
function parseAttributeTest(infotbl)
    enterStep(infotbl,"54 parseAttributeTest")
    leaveStep(infotbl,"54 parseAttributeTest")
end

-- [62] SchemaAttributeTest ::= "schema-attribute" "(" AttributeDeclaration ")"
function parseSchemaAttributeTest(infotbl)
    enterStep(infotbl,"54 parseSchemaAttributeTest")
    leaveStep(infotbl,"54 parseSchemaAttributeTest")
end

-- [63] AttributeDeclaration ::= AttributeName
function parseKindTest(infotbl)
    enterStep(infotbl,"54 parseKindTest")
    leaveStep(infotbl,"54 parseKindTest")
end

-- [64] ElementTest ::= "element" "(" (ElementNameOrWildcard ("," QName "?"?)?)? ")"
function parseElementTest(infotbl)
    enterStep(infotbl,"64 parseElementTest")
    leaveStep(infotbl,"64 parseElementTest")
end

-- [65] ElementNameOrWildcard ::= ElementName | "*"
function parseKindTest(infotbl)
    enterStep(infotbl,"54 parseKindTest")
    leaveStep(infotbl,"54 parseKindTest")
end

-- [66] SchemaElementTest ::= "schema-element" "(" QName ")"
function parseSchemaElementTest(infotbl)
    enterStep(infotbl,"66 parseSchemaElementTest")
    leaveStep(infotbl,"66 parseSchemaElementTest")
end


-- [69] ElementName ::= QName

-- [61] AttribNameOrWildcard ::= AttributeName | "*"
-- [68] AttributeName ::= QName
-- [70] TypeName ::= QName


-- [58] CommentTest ::= "comment" "(" ")"
-- [57] TextTest ::= "text" "(" ")"
-- [55] AnyKindTest ::= "node" "(" ")"


infomt = {
    __index = function(tbl, key)
        if key == "nexttok" then
            tbl.pos = tbl.pos + 1
            return tbl.tokenlist[tbl.pos - 1]
        elseif key == "peek" then
            return function(n)
                if tbl.pos > #tbl.tokenlist then return nil end
                n = n or 1
                return tbl.tokenlist[tbl.pos + n - 1]
            end
        elseif key == "skip" then
            return function(n)
                local tok = tbl.nexttok
                if tok[2] ~= n then
                    w("parse error, expect %q, got %q",n, tok[2])
                end
            end
        elseif key == "skiptoken" then
            return function(n)
                local tok = tbl.nexttok
                if tok[1] ~= n then
                    w("parse error, expect %s, got %s",toktostring(n), toktostring(tok[1]))
                end
            end
        elseif key == "eof" then
            return tbl.pos >= #tbl.tokenlist
        else
            return rawget(tbl, key)
        end
    end
}

function parse(str)
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
            if string.match(tok,":") then
                table.insert(tokenlist, {TOK_QNAME, tok})
            else
                table.insert(tokenlist, {TOK_NCNAME, tok})
            end
        elseif match(c, "%(") then
            sr:getc()
            c = sr:peek()
            if c == ":" then
                tok = get_comment()
                table.insert(tokenlist, {TOK_COMMENT, tok})
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
        elseif match(c, "-") and match(c2,"%d") then
            sr:getc()
            tok = get_num(sr)
            table.insert(tokenlist, {TOK_NUMBER, tok * -1})
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


return {
    parse = parse,
    register = register,
}