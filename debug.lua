
function w( ... )
  local ok,fmt = pcall(string.format,...)
  if ok == false then
    print("-(e)-> " .. fmt)
    print(debug.traceback())
  else
    print("-----> " .. fmt)
  end
  io.stdout:flush()
end

if not log then
  log = function (...)
    print(string.format(...))
  end
end


function toktostring(tok)
  if tok == 0 then
    return "TOK_VOID"
  elseif tok == 1 then
      return "TOK_WORD"
  elseif tok == 2 then
      return "TOK_VAR"
  elseif tok == 3 then
      return "TOK_OPENPAREN"
  elseif tok == 4 then
      return "TOK_CLOSEPAREN"
  elseif tok == 7 then
      return "TOK_STRING"
  elseif tok == 8 then
      return "TOK_COMMENT"
  elseif tok == 9 then
      return "TOK_NUMBER"
  elseif tok == 10 then
      return "TOK_OPERATOR"
  elseif tok == 11 then
      return "TOK_OCCURRENCEINDICATOR"
  elseif tok == 12 then
      return "TOK_OPENBRACKET"
    elseif tok == 13 then
      return "TOK_CLOSEBRACKET"
    elseif tok == 14 then
      return "TOK_QNAME"
    elseif tok == 15 then
      return "TOK_NCNAME"
  end
end

do
  local level = 0
  function enterStep(infotbl,where)
    local nexttok = infotbl.peek()
    nexttok = nexttok or {0,""}
    w("%s%s (next: %s|%q)",string.rep(" ",level), where,toktostring(nexttok[1]),nexttok[2])
    level = level + 1
  end

  function leaveStep(infotbl,where)
    local nexttok = infotbl.peek()
    level = level - 1
    nexttok = nexttok or {0,""}
    w("%s%s ... done (next: %s|%q)",string.rep(" ",level),where,toktostring(nexttok[1]),nexttok[2])
  end
end


local function cmpkeys( a,b )
  if type(a) == type(b) then
      if a == "elementname" then return true end
      if b == "elementname" then return false end
      if type(a) == "table" then return true end
      return a < b
  end
  if type(a) == "number" then return false end
  return true
end


do
  local function indent(level)
    return string.rep( "    ", level )
  end
  function printtable (ind,tbl_to_print,level,depth)
    if depth and depth <= level then return end
    if type(tbl_to_print) ~= "table" then
      log("printtable: %q is not a table, it is a %s (%q)",tostring(ind),type(tbl_to_print),tostring(tbl_to_print))
      return
    end
    level = level or 0
    local k,l
    local key
    if level > 0 then
      if type(ind) == "number" then
        key = string.format("[%d]",ind)
      elseif type(ind) == "table" then
        key = "table"
      else
        key = string.format("[%q]",ind)
      end
    else
      key = ind
    end
    log(indent(level) .. tostring(key) .. " = {")
    level=level+1
    local keys = {}
    for k,_ in pairs(tbl_to_print) do
      keys[#keys + 1] = k
    end
    table.sort(keys,cmpkeys)
    for i=1,#keys do
        local k = keys[i]
        local l = tbl_to_print[k]
        if type(l) == "userdata" and node.is_node(l) then
            l = "⬖".. nodelist_tostring(l) .. "⬗"
        end
      if type(l)=="table" then
        if k ~= ".__parent" and k ~= ".__context" then
          printtable(k,l,level,depth)
        else
          if k == ".__parent" then
            log("%s[\".__parent\"] = <%s>", indent(level),l[".__local_name"])
          end
        end
      else
        if type(k) == "number" then
          key = string.format("[%d]",k)
        else
          key = string.format("[%q]",tostring(k))
        end
        log("%s%s = %q", indent(level), key,tostring(l))
      end
    end
    log(indent(level-1) .. "},")
  end
end
