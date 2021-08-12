
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


do
  tables_printed = {}
  function printtable (ind,tbl_to_print,level)
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
      else
        key = string.format("[%q]",ind)
      end
    else
      key = ind
    end
    log(string.rep("  ",level) .. tostring(key) .. " = {")
    level=level+1

    for k,l in pairs(tbl_to_print) do
      if (type(l)=="table") then
        if k ~= ".__parent" then
          printtable(k,l,level)
        else
          log("%s[\".__parent\"] = <%s>", string.rep("  ",level),l[".__name"])
        end
      else
        if type(k) == "number" then
          key = string.format("[%d]",k)
        else
          key = string.format("[%q]",k)
        end
        log("%s%s = %q", string.rep("  ",level), key,tostring(l))
      end
    end
    log(string.rep("  ",level-1) .. "},")
  end
end

