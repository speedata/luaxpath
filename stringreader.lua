

local stringreader = {}

function stringreader.new(self,str)
    local s = {
        str = str,
        pos = 1
    }
    setmetatable(s, self)
    self.__index = self
    local tab = {}
    for i in string.utfcharacters(str) do
        table.insert(tab,i)
    end
    s.tab = tab
	return s
end

function stringreader.getc(self)
    local s = self.tab[self.pos]
    self.pos = self.pos + 1
    return s
end

function stringreader.peek(self,pos)
    pos = pos or 1
    return self.tab[self.pos + pos - 1]
end

function stringreader.back(self)
    self.pos = self.pos -1
    return self.tab[self.pos]
end


function stringreader.eof(self)
    return self.pos == #self.tab +1
end

return stringreader