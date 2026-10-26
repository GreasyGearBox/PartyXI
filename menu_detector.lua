-- Active-menu pointer chain and event/interface signatures adapted from XIUI
-- core/gamestate.lua, MIT, Copyright (c) 2023 tirem [github.com/tirem].
-- Original signature credits: Velyn. Full license: licenses/XIUI-MIT.txt.
-- No XIUI dependency; no writes, packet injection or native UI changes.
local M={}
local function validator()
    local ok,ffi=pcall(require,'ffi')
    if not ok or ffi.os~='Windows' then return nil end
    pcall(ffi.cdef,[[
        typedef struct {
            void* BaseAddress; void* AllocationBase; unsigned long AllocationProtect;
            size_t RegionSize; unsigned long State; unsigned long Protect; unsigned long Type;
        } partyxi_mbi_v1;
    ]])
    pcall(ffi.cdef,'size_t __stdcall VirtualQuery(const void*, void*, size_t);')
    local loaded,kernel=pcall(ffi.load,'kernel32')
    if not loaded then return nil end
    local readable={[2]=true,[4]=true,[8]=true,[32]=true,[64]=true,[128]=true}
    local info=ffi.new('partyxi_mbi_v1[1]')
    return function(address,count)
        if kernel.VirtualQuery(ffi.cast('const void*',address),info,ffi.sizeof(info[0]))==0 then return false end
        local page=info[0]
        if page.State~=0x1000 or math.floor(tonumber(page.Protect)/256)%2==1 or
            not readable[tonumber(page.Protect)%256] then return false end
        return address+count<=tonumber(ffi.cast('uintptr_t',page.BaseAddress))+tonumber(page.RegionSize)
    end
end
function M.new(memory,canRead)
    local self={memory=memory,readable=canRead or validator(),scanned=false,pointers={}}
    function self:scan()
        if self.scanned then return end
        self.scanned=true
        if not self.memory or not self.memory.find then return end
        local function find(pattern,offset)
            local ok,result=pcall(self.memory.find,'FFXiMain.dll',0,pattern,offset,0)
            return ok and tonumber(result) or 0
        end
        self.pointers.menu=find('8B480C85C974??8B510885D274??3B05',16)
        self.pointers.event=find('A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3',0)
        self.pointers.interface=find('8B4424046A016A0050B9????????E8????????F6D81BC040C3',0)
    end
    function self:read(method,address,count)
        if type(address)~='number' or address~=math.floor(address) or address<0x10000 or
            address+count>0x100000000 or not self.readable then return nil end
        local valid,allowed=pcall(self.readable,address,count)
        if not valid or not allowed then return nil end
        local ok,result
        if method=='read_string' then ok,result=pcall(self.memory[method],address,count)
        else ok,result=pcall(self.memory[method],address) end
        if ok then return result end
    end
    function self:sample()
        self:scan()
        local result={menu='',menuAvailable=false,status='Menu detection unavailable',event=false,interface=false}
        if not self.memory then result.status='Ashita memory API unavailable';return result end
        if not self.readable then result.status='Readable-pointer validation unavailable';return result end
        local p=self.pointers
        if p.menu and p.menu>0 then
            local root=self:read('read_uint32',p.menu,4)
            if root==0 then result.menuAvailable=true
            elseif root then
                local menu=self:read('read_uint32',root,4)
                if menu==0 then result.menuAvailable=true
                elseif menu then
                    local header=self:read('read_uint32',menu+4,4)
                    if header and header~=0 then
                        local name=self:read('read_string',header+0x46,16)
                        if type(name)=='string' then
                            name=name:match('^[^%z]*') or ''
                            if not name:find('[\001-\008\011\012\014-\031\127-\255]') then
                                result.menu=name;result.menuAvailable=true
                            end
                        end
                    end
                end
            end
            result.status=result.menuAvailable and 'Menu detection ready' or 'Menu pointer/read unavailable'
        else result.status='Menu signature not found' end
        local event=p.event and p.event>0 and self:read('read_uint32',p.event+1,4)
        if event and event~=0 then result.event=self:read('read_uint8',event,1)==1 end
        local interface=p.interface and p.interface>0 and self:read('read_uint32',p.interface+10,4)
        if interface and interface~=0 then result.interface=self:read('read_uint8',interface+0xB4,1)==1 end
        return result
    end
    return self
end
return M
