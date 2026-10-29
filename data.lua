local M={}
local model=require('model')
local effects={}
local metadata=require('effects')
local sa=require('sa')
local partyEffects=require('party_effects')
local saState=sa.new()
local effectSerial,revision,ownEpoch=0,0,0
local function call(obj,method,...)
    local args={...}
    local ok,value=pcall(function() return obj[method](obj,unpack(args)) end)
    if ok then return value end
end
M.call=call
function M.clear() effects={};saState=sa.new();ownEpoch=ownEpoch+1 end
function M.clearEffects()effects={};ownEpoch=ownEpoch+1 end
function M.packet(s,now)
    local decoded=model.decodePartyEffects(s)
    if decoded then
        revision=revision+1
        local nextEffects={}
        for id,buffs in pairs(decoded)do
            local old=effects[id]
            if not old then effectSerial=effectSerial+1 end
            local valid=true;for _,buff in ipairs(buffs)do if buff==0 then valid=false end end
            nextEffects[id]={ids=buffs,time=now,revision=revision,valid=valid,key=old and old.key or ('party:'..effectSerial)}
        end
        effects=nextEffects -- Omission is unknown, never a synthetic empty-effect list.
    end
end
-- Prefer the host GetBuffs effect-ID source when available.
-- Do not assume a packed, one-based icon table or stop at a hole/sentinel.
local function effectList(raw)
    local kind=type(raw)
    if kind~='table' and kind~='userdata' and kind~='cdata' then return nil end
    local slots={}
    if kind~='table' then
        -- Native indexed containers are not necessarily Lua tables.
        local out,read={},false
        local first=kind=='cdata' and 0 or 1
        for i=first,first+31 do
            local ok,value=pcall(function()return raw[i]end)
            local id=ok and tonumber(value) or nil
            if id then
                read=true
                if id>0 and model.validEffect(id) then out[#out+1]=id end
            end
        end
        return read and out or nil
    end
    for slot,id in pairs(raw) do
        if type(slot)=='number' and type(id)=='number' then slots[#slots+1]=slot end
    end
    table.sort(slots)
    local out={}
    for _,slot in ipairs(slots) do
        local id=raw[slot]
        if id>0 and model.validEffect(id) then out[#out+1]=id end
    end
    return out
end
local lastStatusReport
local function ownEffects(player)
    local buffOK,buffRaw=pcall(function()return player:GetBuffs()end)
    local iconOK,iconRaw=pcall(function()return player:GetStatusIcons()end)
    local buffs=buffOK and effectList(buffRaw) or nil
    if buffs==nil and iconOK then buffs=effectList(iconRaw) end
    local report=string.format('GetBuffs: %s; GetStatusIcons: %s; parsed effects: %s',
        buffOK and type(buffRaw) or tostring(buffRaw),
        iconOK and type(iconRaw) or tostring(iconRaw),buffs and tostring(#buffs) or 'unavailable')
    if report~=lastStatusReport then
        lastStatusReport=report
        pcall(function()
            local file=io.open(addon.path..'status-runtime.txt','w')
            if file then file:write(report..'\n');file:close() end
        end)
    end
    return buffs
end
function M.sample(now,cfg)
    local mem=AshitaCore:GetMemoryManager()
    local party,player,entity=mem:GetParty(),mem:GetPlayer(),mem:GetEntity()
    local zoning=call(player,'GetIsZoning')
    if zoning and zoning~=0 then M.clear();return {} end
    local selfId=call(party,'GetMemberServerId',0)
    if not selfId or selfId==0 then M.clear();return {} end
    local zone=call(party,'GetMemberZone',0)
    local leaderId=call(party,'GetAlliancePartyLeaderServerId1')
    if type(leaderId)~='number' or leaderId<=0 then leaderId=nil end
    local out,present={},{}
    local clientEffects=partyEffects.read()
    for i=0,5 do
        local id=call(party,'GetMemberServerId',i)
        local name=call(party,'GetMemberName',i)
        local active=call(party,'GetMemberIsActive',i)
        -- Inactive slots may retain old IDs/names after a party departure.
        -- Membership is distinct from being nearby or having a loaded entity.
        if id and id~=0 and name and name~='' and active~=0 and active~=false then
            present[id]=true
            local idx=call(party,'GetMemberTargetIndex',i)
            local sameZone=call(party,'GetMemberZone',i)==zone
            local available=sameZone
                and idx and idx>0 and call(entity,'GetServerId',idx)==id
            local m={id=id,slot=i,name=name,isLeader=leaderId~=nil and id==leaderId,job=call(party,'GetMemberMainJob',i) or 0,
                subjob=call(party,'GetMemberSubJob',i) or 0,available=not not available,
                level=call(party,'GetMemberMainJobLevel',i) or 0,sublevel=call(party,'GetMemberSubJobLevel',i) or 0,
                zone=call(party,'GetMemberZone',i) or 0,localZone=sameZone,resourcesAvailable=sameZone,active=active~=0 and active~=false,
                state=sameZone and 'Out of range' or 'Other zone'}
            -- Party HP/MP do not require a nearby loaded world entity.
            if sameZone then
                m.hp=call(party,'GetMemberHP',i);m.mp=call(party,'GetMemberMP',i)
                m.hpp=call(party,'GetMemberHPPercent',i);m.mpp=call(party,'GetMemberMPPercent',i)
            end
            if available then
                m.tp=call(party,'GetMemberTP',i)
                local distance=call(entity,'GetDistance',idx)
                m.distance=distance and math.sqrt(math.max(0,distance))
                if i==0 then m.maxhp=call(player,'GetHPMax');m.maxmp=call(player,'GetMPMax') end
                local native=i~=0 and clientEffects[id] or nil
                if native then
                    local old=effects[id]
                    if not old then effectSerial=effectSerial+1 end
                    revision=revision+1
                    effects[id]={ids=native,time=now,revision=revision,valid=true,
                        key=old and old.key or ('party:'..effectSerial)}
                end
                local cached=effects[id]
                local buffs=i==0 and ownEffects(player) or nil
                if buffs then
                    revision=revision+1
                    m.effectObservation={ids=buffs,time=now,revision=revision,key='self:'..ownEpoch}
                end
                if not buffs and cached and now-cached.time<=cfg.effectStaleSeconds then buffs=cached.ids end
                if buffs and not m.effectObservation and cached and cached.valid~=false then m.effectObservation=cached end
                m.effectsKnown=buffs~=nil
                m.good,m.bad=model.split(buffs,metadata,cfg.effectOverrides)
            else effects[id]=nil;m.good={};m.bad={} end
            out[#out+1]=m
        end
    end
    for id in pairs(effects) do if not present[id] then effects[id]=nil end end
    if cfg.showSAHats then
        sa.sync(saState,out)
        for _,m in ipairs(out)do
            local seconds
            if m.slot==0 and saState.timers[m.id]then
                local recast=call(mem,'GetRecast')
                if recast then
                    for slot=0,31 do
                        if call(recast,'GetAbilityTimerId',slot)==64 then
                            local ticks=call(recast,'GetAbilityTimer',slot)
                            if type(ticks)=='number'then seconds=ticks/60 end
                            break
                        end
                    end
                end
            end
            if m.available then m.saRemaining,m.saSource=sa.remaining(saState,m.id,now,seconds)end
        end
    else saState=sa.new()end
    return out
end
function M.observeSA(event,now,cfg,unpackBits)
    if not cfg.showSAHats then return false end
    local action=sa.parse(event,unpackBits)
    if not action then return false end
    M.sample(now,cfg) -- Refresh identities/job levels before accepting the actor.
    return sa.observe(saState,action,now)
end
return M
