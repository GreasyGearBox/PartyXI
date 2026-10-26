-- Read the existing client party-status cache, as the installed PartyBuffs
-- addon does: party.statusicons -> five 0x30-byte entries. No memory writes.
-- Uses the shared VirtualQuery-backed address validation from menu_detector.
local M={}
local reader,pointerAddress,initialized
local function initialize()
    if initialized then return end
    initialized=true
    if not ashita or not ashita.memory then return end
    reader=require('menu_detector').new(ashita.memory)
    local ok,address=pcall(function()return AshitaCore:GetPointerManager():Get('party.statusicons')end)
    if ok then pointerAddress=tonumber(address) end
end
function M.read()
    initialize()
    if not reader or not pointerAddress then return {} end
    local base=reader:read('read_uint32',pointerAddress,4)
    if type(base)~='number' or base<0x10000 then return {} end
    local memory=ashita.memory
    local out={}
    for index=0,4 do
        local entry=base+index*0x30
        local valid,readable=pcall(reader.readable or function()return false end,entry,0x30)
        if valid and readable and entry+0x30<=0x100000000 then
            local ok,id,ids=pcall(function()
                local serverId=memory.read_uint32(entry)
                if not serverId or serverId==0 then return nil end
                local result={}
                for slot=0,31 do
                    local packed=memory.read_uint8(entry+8+math.floor(slot/4))
                    local low=memory.read_uint8(entry+16+slot)
                    if type(packed)~='number' or type(low)~='number' then return nil end
                    local high=math.floor(packed/2^(2*(slot%4)))%4
                    local effect=low+high*256
                    if effect==255 or effect==1023 then return serverId,result end
                    if effect==0 then return nil end -- zero-filled / unknown is not loss
                    if effect>0 and effect<1023 then result[#result+1]=effect end
                end
                return serverId,result
            end)
            if ok and id and ids then out[id]=ids end
        end
    end
    return out
end
return M
