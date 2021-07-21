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
str = "*:foo"
str = "foo:*"
str = [=[abc * def != fff = 5 < 3 << 5 | >>> ? @ val ]=]
str = [=[]=]
str = [=[(1,1) $varname  ]=]
str = [=[(1 to 100)[. mod 5 eq 0] ]=]
str = [=[ns:funcall(ab:funcall2(a,b),c)]=]

local sr = stringreader:new(str)


local match = unicode.utf8.match


-- Read all space until a non-space is found
local function space(sr)
    if sr:eof() then return end
    while match(sr:getc(),"%s") do
        if sr:eof() then return end
    end
    sr:back()
end

local function get_num(sr)
    local ret = {}
    while true do
        if sr:eof() then break end
        local c = sr:getc()
        if match(c,"[%d.]") then
            table.insert(ret,c)
        else
            sr:back()
            break
        end
    end
    return table.concat(ret,"")
end

local function get_word(sr)
    local ret = {}
    while true do
        if sr:eof() then break end
        local c = sr:getc()
        if match(c,"[-%a%d]") then
            table.insert(ret,c)
        elseif match(c,":") and match(sr:peek(),"%a") then
            table.insert(ret,c)
        else
            sr:back()
            break
        end
    end
    return table.concat(ret,"")
end

local function get_comment()
    local ret = {}
    local level = 1
    sr:getc()
    while true do
        if sr:eof() then break end
        local c = sr:getc()

        if c == ":" and sr:peek() == ")" then
            level = level - 1
            if level == 0 then
                sr:getc()
                break
            else
                table.insert(ret,":")
            end
        elseif c == "(" and sr:peek() == ":" then
            level = level + 1
            sr:getc()
            table.insert(ret,"(:")
        else
            table.insert(ret,c)
        end
    end
    return table.concat(ret)
end

local function get_delimited_string(sr)
    local ret = {}
    local delim = sr:getc()
    while true do
        if sr:eof() then break end
        local c = sr:getc()
        if c ~= delim then
            table.insert(ret,c)
        else
            break
        end
    end
    return table.concat(ret,"")
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


local tokenlist = {}

local toks = {}
local tok
while true do
    if sr:eof() then break end
    local c = sr:peek()
    if match(c,"%a") then
        tok = get_word(sr)
        table.insert(tokenlist,{TOK_WORD,tok})
    elseif match(c,"%(") then
        sr:getc()
        c = sr:peek()
        if c == ":" then
            tok = get_comment()
            table.insert(tokenlist,{TOK_COMMENT,tok})
        else
            table.insert(tokenlist,{TOK_OPENPAREN,"("})
        end
    elseif match(c,"%)") then
        sr:getc()
        table.insert(tokenlist,{TOK_CLOSEPAREN,")"})
    elseif match(c,"%d") then
        tok = get_num(sr)
        table.insert(tokenlist,{TOK_NUMBER,tok})
    elseif match(c,"%$") then
        sr:getc()
        tok = get_word(sr)
        table.insert(tokenlist,{TOK_VAR,tok})
        -- ',', =, >=, >>, >, [, <=, <<, <, -, *, !=, +, //, /, |
    elseif match(c,"[,=/>[<-*!+|?@%]]") then
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
        table.insert(tokenlist,{TOK_OPERATOR,op})
    elseif match(c,"'") or match(c,'"') then
        tok = get_delimited_string(sr)
        table.insert(tokenlist,{TOK_STRING,tok})
    elseif match(c,"%s") then
        space(sr)
    else
        w("unhandled token %q",c)
        break
    end
end

local function toktostring(tok)
    if tok ==  1 then return "TOK_WORD"
    elseif tok ==  2 then return "TOK_VAR"
    elseif tok ==  3 then return "TOK_OPENPAREN"
    elseif tok ==  4 then return "TOK_CLOSEPAREN"
    elseif tok ==  7 then return "TOK_STRING"
    elseif tok ==  8 then return "TOK_COMMENT"
    elseif tok ==  9 then return "TOK_NUMBER"
    elseif tok == 10 then return "TOK_OPERATOR"
    elseif tok == 11 then return "TOK_OCCURRENCEINDICATOR"
    end
end



local function fixup_tokenlist(list)
    local state = "DEFAULT"
    local c = 1
    local statestack = {}
    local checknexttoknth = function(idx,tok,val)
        if c + idx - 1 >= #list then
            return false
        end
        local nexttok = list[c+idx]
        val = val or nexttok[2]
        return nexttok[1] == tok and nexttok[2] == val
    end

    local checknexttok = function(tok,val)
        return checknexttoknth(1,tok,val)
    end
    local function pushstate(newstate)
        table.insert(statestack,newstate or state)
    end
    local function popstate()
        state = table.remove(statestack)
    end

    while true do
        if c > #list then break end
        local curtok = list[c]
        w("state: %s next token %s value %q",state,toktostring(curtok[1]),curtok[2] or "")
        if state == "DEFAULT" then
            if curtok[1] == TOK_WORD then
                local word = curtok[2]
                if false then
                elseif checknexttok(TOK_OPERATOR,":") and checknexttoknth(2,TOK_OPERATOR,"*") then
                    c = c + 2
                    state = "OPERATOR"
                    w("ncname followed by :*")
                elseif ( word == "for" or word == "some" or word == "every" ) and checknexttok(TOK_VAR) then
                    w("a variable preceded with %s",word)
                    state = "OPERATOR"
                elseif word == "if" then
                    if  checknexttok(TOK_OPENPAREN) then
                        c = c + 1
                        state = "DEFAULT"
                    else
                        w("if not followed by an opening paren")
                    end
                elseif  word == "element" or word == "attribute" or word == "schema-element" or word == "schema-attribute" or word == "comment" or word == "text" or word == "node" or word == "document-node" then
                    if checknexttok(TOK_OPENPAREN) then
                        c = c + 1
                        pushstate("OPERATOR")
                        state = "KINDTEST"
                    else
                        w("%s not followed by an opening paren",word)
                    end
                elseif word == "processing-instruction" then
                    if checknexttok(TOK_OPENPAREN) then
                        c = c + 1
                        pushstate("OPERATOR")
                        state = "KINDTESTPI"
                        -- TODO
                    else
                        w("%s not followed by an opening paren",word)
                    end
                end
            elseif curtok[1] == TOK_NUMBER then
                state = "OPERATOR"
            elseif curtok[1] == TOK_OPERATOR then
                local op = curtok[2]
                if op == "." or op == ".." then
                    state = "OPERATOR"
                elseif op == "*" and checknexttok(TOK_OPERATOR,":") and checknexttoknth(2,TOK_WORD) then
                    c = c + 2
                    state = "OPERATOR"
                elseif op == "*" then
                    state = "OPERATOR"
                elseif op == "," or op == "-" or op == "+" or op == "//" or op == "/" or op == "@" then
                    state = "DEFAULT"
                end
            elseif curtok[1] == TOK_OPENPAREN then
                state = "DEFAULT"
            elseif curtok[1] == TOK_CLOSEPAREN then
                state ="OPERATOR"
            elseif curtok[1] == TOK_VAR then
                state = "OPERATOR"
            elseif curtok[1] == TOK_STRING then
                state = "OPERATOR"
            end
        elseif state == "OPERATOR" then
            if curtok[1] == TOK_WORD then
                local word = curtok[2]
                w("word %s",tostring(word))
                if word == "then" or word == "else" or word == "and" or word == "div" or word == "except" or word == "eq" or word == "ge" or word == "gt" or word == "le" or word == "lt" or word == "ne" or word == "idiv" or word == "intersect" or word == "in" or word == "is" or word == "mod" or word == "return" or word == "satisfies" or word == "to" or word == "union" then
                    state = "DEFAULT"
                elseif (word == "castable" and checknexttok(TOK_WORD,"as")) or  (word == "cast" and checknexttok(TOK_WORD,"as")) then
                    if not checknexttoknth(2,TOK_WORD) then
                        w("%s as needs a qname",word)
                    else
                        list[c] = {TOK_OPERATOR, string.format("%s as",word)}
                        table.remove(list,c + 1)
                    end
                elseif ( word == "instance" and checknexttok(TOK_WORD,"of")) or (word == "treat" and checknexttok(TOK_WORD,"as")) then
                    local nextword
                    if word == "instance" then nextword = "of" else nextword = "as" end
                    list[c] = {TOK_OPERATOR, string.format("%s %s",word,nextword)}
                    table.remove(list,c + 1)

                    state = "ITEMTYPE"
                end
            elseif curtok[1] == TOK_VAR then
                w("var!!")
            elseif curtok[1] == TOK_OPERATOR then
                local op = curtok[2]
                if op == "?" or op == "]" then
                    -- keep state
                else
                    state = "DEFAULT"
                end
            elseif curtok[1] == TOK_OPENPAREN or curtok[1] == TOK_CLOSEPAREN then
                -- keep state
            else
                w("unknown token %s",toktostring(curtok[1]))
            end
        elseif state == "ITEMTYPE" then
            w("itemtype")
            if curtok[1] == TOK_WORD then
                local word = curtok[2]
                w("itemtype word %s",word)
                if word == "empty-sequence" and checknexttok(TOK_OPENPAREN) and checknexttoknth(2,TOK_CLOSEPAREN) then
                    state = "OPERATOR"
                elseif ( word == "element" or word == "attribute"  or word == "schema-element"  or word == "schema-attribute"  or word == "comment"  or word == "text"  or word == "node"  or word == "document-node" ) then
                    if checknexttok(TOK_OPENPAREN) then
                        pushstate("OCCURRENCEINDICATOR")
                        state = "KINDTEST"
                    end
                    -- qname
                end
            end
        elseif state == "KINDTEST" then
            if curtok[1] == TOK_CLOSEPAREN then
                popstate()
            elseif curtok[1] == TOK_OPERATOR and curtok[2] == "*" then
                w("KINDTEST *")
                state = "CLOSEKINDTEST"
            elseif curtok[1] == TOK_WORD then
                local word = curtok[2]
                if (word == "element" or word == "schema-element" ) and checknexttok(TOK_OPENPAREN) then
                    pushstate("KINDTEST")
                else
                    w("word %s",word)
                    state = "CLOSEKINDTEST"
                end
            end
        elseif state == "CLOSEKINDTEST" then
            if curtok[1] == TOK_CLOSEPAREN then
                popstate()
            elseif curtok[1] == TOK_OPERATOR and curtok[2] == "," then
                state = "KINDTEST"
            elseif curtok[1] == TOK_OPERATOR and curtok[2] == "?" then
                -- keep state
            end
        elseif state == "OCCURRENCEINDICATOR" then
            if curtok[1] == TOK_OPERATOR then
                local op = curtok[2]
                if op == "?" or op == "*" or op == "+" then
                    curtok[1] = TOK_OCCURRENCEINDICATOR
                    c = c + 1
                end
            end
            state = "OPERATOR"
        else
            w("unknown state %s!!!",state)
        end
        c = c + 1
    end
    w("final state %s",state)
    printtable("statestack",statestack)
end

fixup_tokenlist(tokenlist)

-- printtable("tokenlist",tokenlist)

function parse_expression(lhs,lhspos,min_precedence)
    local startpos = lhspos
    w("parse_expression")
    local tok = lhs[lhspos]
    while true do
        printtable("tok",tok)
        if tok[1] == TOK_OPENPAREN then
            local ret, newpos = parse_expression(lhs,lhspos + 1,10)
            lhspos = newpos
        elseif tok[1] == TOK_CLOSEPAREN then
            return {}, lhspos
        end
        tok = lhs[lhspos]
        lhspos = lhspos + 1
        if lhspos > #lhs then
            break
        end
    end
    return {}, lhspos
end

parse_expression(tokenlist,1)
