-- ArcXI: passive action observation; never sends, injects or modifies packets.
local M = {statuses={}, targets={}, expires={}}
local lands = {[127]=true,[160]=true,[164]=true,[166]=true,[186]=true,[194]=true,[203]=true,[205]=true,[230]=true,[236]=true,[237]=true,[266]=true,[267]=true,[268]=true,[269]=true,[271]=true,[272]=true,[277]=true,[278]=true,[279]=true,[280]=true,[319]=true,[320]=true,[375]=true,[412]=true}
local off = {[64]=true,[159]=true,[168]=true,[204]=true,[206]=true,[321]=true,[322]=true,[341]=true,[342]=true,[343]=true,[344]=true,[350]=true,[378]=true,[531]=true}
local death = {[6]=true,[20]=true,[97]=true,[113]=true,[406]=true,[605]=true}
local damage = {[1]=true,[2]=true,[67]=true,[110]=true,[163]=true,[185]=true,[187]=true,[229]=true,[252]=true,[264]=true,[265]=true,[317]=true,[352]=true,[353]=true,[379]=true}
-- Base durations are estimates, not server-authoritative remaining time.
-- Keep unknown durations unknown instead of displaying a fabricated countdown.
local spellSeconds = {
    [23]=60,[33]=60,[24]=120,[230]=60,[231]=120,
    [58]=120,[80]=120,[56]=180,[79]=180,[216]=120,[254]=180,[276]=180,
    [112]=12,[59]=120,[253]=60,[273]=60,[259]=90,[274]=90,[258]=60,[252]=5,
    [220]=90,[221]=120,[225]=90,[226]=120,[341]=180,[344]=180,[347]=180,[350]=60,
    [235]=90,[236]=90,[237]=90,[238]=90,[239]=90,[240]=90,
    -- Common ally buffs; equipment, merits and server rules can modify these.
    [40]=1800,[41]=1800,[42]=1800,[43]=1800,[44]=1800,
    [45]=1800,[46]=1800,[47]=1800,[48]=1800,[49]=1800,
    [53]=300,[54]=300,[55]=600,[57]=180,[106]=180,[108]=75,[109]=150,
    [110]=60,[111]=60,

}
local dotBuff = {[23]=134,[24]=134,[33]=134,[230]=135,[231]=135}
local spellDamage = {[2]=true,[252]=true,[264]=true,[265]=true}
function M.reset() M.statuses={}; M.targets={};M.expires={} end
local function put(id,status,now,duration)
    M.statuses[id]=M.statuses[id] or {}
    M.expires[id]=M.expires[id] or {}
    M.statuses[id][status]=now
    M.expires[id][status]=duration and now+duration or nil
end
function M.remaining(id,status,now)
    local expires=M.expires[id] and M.expires[id][status]
    if expires and M.statuses[id] and M.statuses[id][status] then return math.max(0,expires-now),true end
end
function M.parse(e, unpackBits)
    local offset, limit = 40, e.size*8
    local function read(n)
        if offset+n > limit then error('truncated action packet') end
        local v=unpackBits(e.data_raw,0,offset,n); offset=offset+n; return v
    end
    local a={actor=read(32), targets={}}
    local count=read(6); read(4); a.kind=read(4); a.param=read(32)%65536; read(32)
    for _=1,count do
        local t={id=read(32), actions={}}
        local ac=read(4)
        for _=1,ac do
            read(5);read(12);read(7);read(3)
            local v={param=read(17),message=read(10)}; read(31)
            if read(1)==1 then read(10);v.extra={param=read(17),message=read(10)} end
            if read(1)==1 then read(10);read(14);read(10) end
            t.actions[#t.actions+1]=v
        end
        a.targets[#a.targets+1]=t
    end
    return a
end
function M.observe(a, now)
    if (a.kind==1 or a.kind==4 or a.kind==6 or a.kind==7 or a.kind==11) and a.targets[1] then
        M.targets[a.actor]={id=a.targets[1].id,time=now}
    end
    for _,t in ipairs(a.targets) do
        local statuses=M.statuses[t.id] or {}; M.statuses[t.id]=statuses
        for _,v in ipairs(t.actions) do
            if damage[v.message] then statuses[2]=nil; statuses[19]=nil; statuses[193]=nil end
            local function apply(message,param)
                if lands[message] and param>0 and param<1024 and param~=255 then
                    put(t.id,param,now,a.kind==4 and spellSeconds[a.param] or nil)
                elseif off[message] then statuses[param]=nil
                elseif death[message] then M.statuses[t.id]=nil; M.targets[t.id]=nil;M.expires[t.id]=nil end
            end
            if a.kind==4 and dotBuff[a.param] and spellDamage[v.message] then
                -- Dia/Bio deliver a damage result, not a status-on message.
                local buff=dotBuff[a.param]
                put(t.id,buff,now,spellSeconds[a.param])
            end
            apply(v.message,v.param)
            if v.extra then apply(v.extra.message,v.extra.param) end
        end
    end
end
function M.message(id,status,message)
    if death[message] then M.statuses[id]=nil; M.targets[id]=nil;M.expires[id]=nil
    elseif off[message] and M.statuses[id] then
        M.statuses[id][status]=nil
        if status==2 then M.statuses[id][19]=nil; M.statuses[id][193]=nil end
    end
end
function M.list(id,now)
    local out={}
    for status,time in pairs(M.statuses[id] or {}) do
        -- Observation timeout, NOT a claimed duration. Prevent stale indefinite icons.
        local expiry=M.expires[id] and M.expires[id][status]
        if (expiry and now<expiry) or (not expiry and now-time<300) then out[#out+1]=status
        else M.statuses[id][status]=nil;if M.expires[id] then M.expires[id][status]=nil end end
    end
    table.sort(out); return out
end
function M.prune(now)
    for id,entries in pairs(M.statuses) do
        for status,time in pairs(entries) do
            local expiry=M.expires[id] and M.expires[id][status]
            if (expiry and now>=expiry) or (not expiry and now-time>=300) then
                entries[status]=nil;if M.expires[id] then M.expires[id][status]=nil end
            end
        end
        if next(entries)==nil then M.statuses[id]=nil;M.expires[id]=nil end
    end
    for id,v in pairs(M.targets) do if now-v.time>30 then M.targets[id]=nil end end
end
return M
