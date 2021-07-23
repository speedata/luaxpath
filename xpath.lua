dofile("debug.lua")

stringreader = require("stringreader")

local str = [[abc(: as(: bla :)dfsd ):  :) / de // f]]
local str = ""
local str = [=[abc [ def ]]=]
local str = [=[5.24]=]
local str = [=[4 +-+-+-+-+-+ 1]=]
local str = [[if-3d  ($a-3 = 123) then äbc else 'en "d' "e'nd"]]
local str = [=[abc * def != fff = 5 < 3 << 5 | >>> ? @ val ]=]
str = [=[if ( 1 = 1 ) then true() else false()]=]
str = "schema-element"
str = ".."
str = "for $i in "
str = "$a castable as"
str = "//sales[not(. castable as xs:decimal)]"
str = ". instance of element(*, gml:CoordinateSystemAxisType)"
str = [[if (doc("inv.xml") instance of document-node(schema-element(mf:invoice)))]]
str = "1 instance of element()?"
str = [=[  if ("a" = "b") then "x" else "y"]=]
str = "*:foo"
str = "foo:*"
str = [=[abc * def != fff = 5 < 3 << 5 | >>> ? @ val ]=]
str = [=[(1,1) $varname  ]=]
str = [=[(1 to 100)[. mod 5 eq 0] ]=]
str = [=[ns:funcall(ab:funcall2(a,b),c)]=]
str = [=[]=]
str = [=[foo:bar("a","b")]=]
str = [=[position() = 1]=]

local sr = stringreader:new(str)

local match = unicode.utf8.match

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

local tokenlist = {}

local toks = {}
local tok
while true do
    if sr:eof() then
        break
    end
    local c = sr:peek()
    if match(c, "%a") then
        tok = get_word(sr)
        table.insert(tokenlist, {TOK_WORD, tok})
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
    elseif match(c, "%$") then
        sr:getc()
        tok = get_word(sr)
        table.insert(tokenlist, {TOK_VAR, tok})
    elseif match(c, "[,=/>[<-*!+|?@%]]") then
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

printtable("tokenlist", tokenlist)

function plusfunc(a, b)
    return a + b
end

constantQueryMt = {
    __index = function(tbl, key)
        if key == "typ" then
            return "constantQuery"
        elseif key == "evaluate" then
            return function()
                w("evaluate constantQuery")
                return rawget(tbl, "val")
            end
        end
    end
}

numericQueryMt = {
    __index = function(tbl, key)
        if key == "typ" then
            return "numericQuery"
        elseif key == "evaluate" then
            return function()
                w("evaluate numericQuery")
                local f = rawget(tbl, "func")
                local left = rawget(tbl, "left").evaluate()
                local right = rawget(tbl, "right").evaluate()
                return f(left, right)
            end
        end
    end
}

exprQueryMt = {
    __index = function(tbl, key)
        if key == "typ" then
            return "exprQuery"
        elseif key == "evaluate" then
            return function(ctx)
                w("evaluate exprQuery")
                local exprSingle = rawget(tbl, "exprSingle")
                local ret = {}
                for i = 1, #exprSingle do
                    ret[#ret + 1] = exprSingle[i].evaluate()
                end
                return ret
            end
        end
    end
}


-- [2] Expr ::= ExprSingle ("," ExprSingle)*
function parseExpr(infotbl)
    enterStep(infotbl,"2 parseExpr")
    parseExprSingle(infotbl)
    while true do
        local nt = infotbl.peek()
        if nt and nt[2] == "," then
            infotbl.skip(",")
            parseExprSingle(infotbl)
        else
            break
        end
    end
    -- local ret = parseAdditiveExpr(infotbl)
    -- local q = setmetatable({exprSingle = {ret} }, exprQueryMt)
    -- return q
    leaveStep(infotbl,"2 parseExpr")
end

-- [3] ExprSingle ::= ForExpr | QuantifiedExpr | IfExpr | OrExpr
function parseExprSingle(infotbl)
    enterStep(infotbl,"3 parseExprSinge")
    local nexttok = infotbl.peek()
    if nexttok then
        local nexttoktype = nexttok[1]
        local nexttokvalue = nexttok[2]
        if nexttokvalue == "for" then
            parseForExpr(infotbl)
        elseif nexttokvalue == "some" or nexttokvalue == "every" then
            parseQuantifiedExpr(infotbl)
        elseif nexttokvalue == "if" then
            parseIfExpr(infotbl)
        else
            parseOrExpr(infotbl)
        end
    end
    leaveStep(infotbl,"3 parseExprSinge")
end

-- [7] IfExpr ::= "if" "(" Expr ")" "then" ExprSingle "else" ExprSingle
function parseIfExpr(infotbl)
    enterStep(infotbl,"7 parseIfExpr")
    local nexttok = infotbl.nexttok
    if nexttok[2] ~= "if" then
        w("parse error, 'if' expected")
    end

    infotbl.skiptoken(TOK_OPENPAREN)
    parseExpr(infotbl)
    infotbl.skiptoken(TOK_CLOSEPAREN)
    infotbl.skip("then")
    parseExprSingle(infotbl)
    infotbl.skip("else")
    parseExprSingle(infotbl)
    leaveStep(infotbl,"7 parseIfExpr")
end

-- [8] OrExpr ::= AndExpr ( "or" AndExpr )*
function parseOrExpr(infotbl)
    enterStep(infotbl,"8 parseOrExpr")
    parseAndExpr(infotbl)
    local nexttok = infotbl.peek()
    if nexttok then
        local nexttokvalue = nexttok[2]
    end
    leaveStep(infotbl,"8 parseOrExpr")
end

-- [9] AndExpr ::= ComparisonExpr ( "and" ComparisonExpr )*
function parseAndExpr(infotbl)
    enterStep(infotbl,"9 parseAndExpr")
    parseComparisonExpr(infotbl)
    -- while ...
    leaveStep(infotbl,"9 parseAndExpr")
end

-- [10] ComparisonExpr ::= RangeExpr ( (ValueComp | GeneralComp| NodeComp) RangeExpr )?
function parseComparisonExpr(infotbl)
    enterStep(infotbl,"10 parseComparisonExpr")
    parseRangeExpr(infotbl)
    local nexttok = infotbl.peek()
    if op then
        local op = nexttok[2]
        -- [23]   	ValueComp	   ::=   	"eq" | "ne" | "lt" | "le" | "gt" | "ge"
        -- [22]   	GeneralComp	   ::=   	"=" | "!=" | "<" | "<=" | ">" | ">="
        -- [24]   	NodeComp	   ::=   	"is" | "<<" | ">>"
        if op == "eq" or op == "ne" or op == "lt" or op == "le" or op == "gt" or op == "ge" or op == "=" or op == "!=" or op == "<" or op == "<=" or op == ">" or op == ">=" or op == "is" or op == "<<" or op == ">>" then
            w("comparison")
            _ = infotbl.nexttok
            parseRangeExpr(infotbl)
        end
    end
    leaveStep(infotbl,"10 parseComparisonExpr")
end

-- [11]   	RangeExpr  ::=  AdditiveExpr ( "to" AdditiveExpr )?
function parseRangeExpr(infotbl)
    enterStep(infotbl,"11 parseRangeExpr")
    parseAdditiveExpr(infotbl)
    leaveStep(infotbl,"11 parseRangeExpr")
    -- check for "to", if yes, parse another additiveExpr
end

-- [12]	AdditiveExpr ::= MultiplicativeExpr ( ("+" | "-") MultiplicativeExpr )*
function parseAdditiveExpr(infotbl)
    enterStep(infotbl,"12 parseAdditiveExpr")
    local left, right
    left = parseMultiplicativeExpr(infotbl)
    local operator = infotbl.peek()
    if operator then
        if operator[2] == "+" or operator[2] == "-" then
            w("+ or -")
            local op = infotbl.nexttok
            right = parseMultiplicativeExpr(infotbl)
        end
        local q = setmetatable({left = left, right = right, func = plusfunc}, numericQueryMt)
    end
    leaveStep(infotbl,"12 parseAdditiveExpr")
    return q
end

-- [13]	MultiplicativeExpr ::= 	UnionExpr ( ("*" | "div" | "idiv" | "mod") UnionExpr )*
function parseMultiplicativeExpr(infotbl)
    enterStep(infotbl,"13 parseMultiplicativeExpr")
    parseUnionExpr(infotbl)
    leaveStep(infotbl,"13 parseMultiplicativeExpr")
    return setmetatable({val = nil}, constantQueryMt)
end

-- [14]   	UnionExpr	   ::=  IntersectExceptExpr ( ("union" | "|") IntersectExceptExpr )*
function parseUnionExpr(infotbl)
    enterStep(infotbl,"14 parseUnionExpr")
    parseIntersectExceptExpr(infotbl)
    -- while...
    -- check for "union" or "|" then parse another IntersectExceptExpr
    leaveStep(infotbl,"14 parseUnionExpr")
end

-- [15]	IntersectExceptExpr	 ::= InstanceofExpr ( ("intersect" | "except") InstanceofExpr )*
function parseIntersectExceptExpr(infotbl)
    enterStep(infotbl,"15 parseIntersectExceptExpr")
    parseInstanceofExpr(infotbl)
    -- while...
    -- check for "intersect" or "except" then parse another InstanceofExpr
    leaveStep(infotbl,"15 parseIntersectExceptExpr")
end

-- [16]   	InstanceofExpr	   ::=   	TreatExpr ( "instance" "of" SequenceType )?
function parseInstanceofExpr(infotbl)
    enterStep(infotbl,"16 parseInstanceofExpr")
    parseTreatExpr(infotbl)
    leaveStep(infotbl,"16 parseInstanceofExpr")
end

-- [17]   	TreatExpr	   ::=   	CastableExpr ( "treat" "as" SequenceType )?
function parseTreatExpr(infotbl)
    enterStep(infotbl,"17 parseTreatExpr")
    parseCastableExpr(infotbl)
    leaveStep(infotbl,"17 parseTreatExpr")
end

-- [18]   	CastableExpr	   ::=   	CastExpr ( "castable" "as" SingleType )?
function parseCastableExpr(infotbl)
    enterStep(infotbl,"18 parseCastableExpr")
    parseCastExpr(infotbl)
    leaveStep(infotbl,"18 parseCastableExpr")
end

-- [19]   	CastExpr	   ::=   	UnaryExpr ( "cast" "as" SingleType )?
function parseCastExpr(infotbl)
    enterStep(infotbl,"19 parseCastExpr")
    parseUnaryExpr(infotbl)
    leaveStep(infotbl,"19 parseCastExpr")
end

-- [20] UnaryExpr  ::=	("-" | "+")* ValueExpr
function parseUnaryExpr(infotbl)
    enterStep(infotbl,"20 parseUnaryExpr")
    parseValueExpr(infotbl)
    leaveStep(infotbl,"20 parseUnaryExpr")
end

-- [21]	ValueExpr	   ::=   	PathExpr
function parseValueExpr(infotbl)
    enterStep(infotbl,"21 parseValueExpr")
    parsePathExpr(infotbl)
    leaveStep(infotbl,"21 parseValueExpr")
end

-- [25]   	PathExpr  ::= 	("/" RelativePathExpr?) | ("//" RelativePathExpr) | RelativePathExpr
function parsePathExpr(infotbl)
    enterStep(infotbl,"25 parsePathExpr")
    parseRelativePathExpr(infotbl)
    leaveStep(infotbl,"25 parsePathExpr")
end

-- [26]   	RelativePathExpr ::= StepExpr (("/" | "//") StepExpr)*
function parseRelativePathExpr(infotbl)
    enterStep(infotbl,"26 parseRelativePathExpr")
    parseStepExpr(infotbl)
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

-- 28 	AxisStep ::= (ReverseStep | ForwardStep) PredicateList
function parseAxisStep(infotbl)
    enterStep(infotbl,"28 parseAxisStep")
    parsePredicateList(infotbl)
    leaveStep(infotbl,"28 parseAxisStep")
    return nil
end


-- [38]	FilterExpr ::= PrimaryExpr PredicateList
function parseFilterExpr(infotbl)
    enterStep(infotbl,"38 parseFilterExpr")
    local ret = {}
    ret[#ret + 1] = parsePrimaryExpr(infotbl)
    parsePredicateList(infotbl)
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
    local ret = {}
    if nexttoktype == TOK_STRING or nexttoktype == TOK_NUMBER then
        ret[#ret + 1] = infotbl.nexttok
    elseif nexttoktype == TOK_VAR then
        w("var")
    elseif nexttoktype == TOK_OPENPAREN then
        parseParenthesizedExpr(infotbl)
    elseif nexttoktype == TOK_OPERATOR and nexttokvalue == "." then
        w("context item")
    elseif nexttoktype == TOK_WORD and infotbl.peek(2)[1] == TOK_OPENPAREN then
        w("funcall")
        parseFunctionCall(infotbl)
    else
        -- w("unknown token")
    end
    leaveStep(infotbl,"41 parsePrimaryExpr")
    return ret
end


-- [46] ParenthesizedExpr ::= "(" Expr? ")"
function parseParenthesizedExpr(infotbl)
    enterStep(infotbl,"46 parseParenthesizedExpr")
    infotbl.skiptoken(TOK_OPENPAREN)
    parseExpr(infotbl)
    infotbl.skiptoken(TOK_CLOSEPAREN)
    leaveStep(infotbl,"46 parseParenthesizedExpr")
end

-- [48] FunctionCall ::= QName "(" (ExprSingle ("," ExprSingle)*)? ")"
function parseFunctionCall(infotbl)
    enterStep(infotbl,"48 parseFunctionCall")
    local fname = infotbl.nexttok[2]
    w("fname %s",tostring(fname))
    infotbl.skiptoken(TOK_OPENPAREN)
    parseExprSingle(infotbl)
    while true do
        local nt = infotbl.peek()
        if nt then
            if nt[2] == "," then
                infotbl.skip(",")
                parseExprSingle(infotbl)
            else
                break
            end
        else
            w("close paren expected")
            break
        end
    end
    infotbl.skip(")")
    leaveStep(infotbl,"48 parseFunctionCall")
end

function parse(infotbl)
    w("parse")
    parseExpr(infotbl)
end

infotbl = {
    tokenlist = tokenlist,
    pos = 1
}

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
        else
            return rawget(tbl, key)
        end
    end
}
setmetatable(infotbl, infomt)

parse(infotbl)
