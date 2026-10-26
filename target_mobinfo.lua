-- Phoenix snapshot lookup. No network calls or retail fallback.
local M={zone=nil,data=nil}
local function normalize(name) return (name or ''):gsub('_',' ') end
function M.reset() M.zone=nil;M.data=nil end
function M.get(zone,id,name)
    if not zone or zone<=0 then return nil end
    if M.zone~=zone then
        M.zone=zone;M.data=nil
        local chunk=loadfile((addon.path or '')..'data/mobs/'..tostring(zone)..'.lua')
        if chunk then
            local ok,data=pcall(chunk)
            if ok and type(data)=='table' and data.rows and data.ids and data.names then M.data=data end
        end
    end
    local data=M.data
    if not data then return nil end
    name=normalize(name)
    local index=data.ids[id]
    if index then
        local row=data.rows[index]
        return row and row.name==name and row or nil
    end
    index=data.names[name]
    return index and data.rows[index] or nil
end
function M.label(info)
    if not info then return nil end
    local level=info.min==info.max and tostring(info.min) or tostring(info.min)..'-'..tostring(info.max)
    local parts={'Lv '..level,info.aggro and 'Aggro' or 'Passive'}
    if info.link then parts[#parts+1]='Link' end
    for _,method in ipairs(info.methods or {}) do parts[#parts+1]=method end
    return table.concat(parts,'  |  ')
end
return M
