-- SA observation only. No dependency on standalone SATA; no buff-based inference.
local M={}
function M.new()return {roster={},timers={}}end
function M.eligible(m)
    return (m.job==6 and (m.level or 0)>=15) or (m.subjob==6 and (m.sublevel or 0)>=15)
end
local function signature(m)
    return table.concat({m.name or '',m.job or 0,m.level or 0,m.subjob or 0,m.sublevel or 0,m.zone or 0},':')
end
function M.sync(state,rows)
    local keep={}
    for _,m in ipairs(rows)do
        if M.eligible(m) and m.localZone~=false and m.active~=false then
            local sig=signature(m)
            if state.roster[m.id]~=sig then state.timers[m.id]=nil end
            keep[m.id]=sig
        end
    end
    for id in pairs(state.timers)do if not keep[id]then state.timers[id]=nil end end
    state.roster=keep
end
function M.parse(event,unpackBits)
    if not event or event.injected or event.id~=0x028 or not event.size or event.size<19 or not event.data_raw then return nil end
    local ok,a=pcall(function()
        return {actor=unpackBits(event.data_raw,0,40,32),category=unpackBits(event.data_raw,0,82,4),
            ability=unpackBits(event.data_raw,0,86,32),packetRecast=unpackBits(event.data_raw,0,118,32)}
    end)
    if ok and a.category==6 and a.ability==44 then return a end
end
function M.observe(state,action,now)
    if not action or action.category~=6 or action.ability~=44 or not state.roster[action.actor]then return false end
    -- PHX action_t::normalize zeroes JA recast before serialization. Even nonzero
    -- packet data is not promoted to an exact cooldown; only local IRecast is trusted.
    state.timers[action.actor]={started=now,expires=now+60,source='60-second base estimate'}
    return true
end
function M.remaining(state,id,now,localSeconds)
    local t=state.timers[id]
    if not t then return nil end
    -- Let the client's recast table process the activation packet first.
    if now-t.started>=.15 and type(localSeconds)=='number' and localSeconds>=0 and localSeconds<=600 then
        if localSeconds>0 then t.expires=now+localSeconds;t.localObserved=true;t.source='local IRecast'
        elseif t.localObserved then state.timers[id]=nil;return nil end
    end
    local remaining=math.ceil(t.expires-now)
    if remaining<=0 then state.timers[id]=nil;return nil end
    return remaining,t.source
end
return M
