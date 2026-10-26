-- PartyXI: pure data transformations. No inferred durations or maximums.
local M = {}
function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, tonumber(v) or lo)) end
function M.validEffect(id) return id and id >= 0 and id < 1023 and id ~= 255 end
local function u32(s, p)
    local a,b,c,d = s:byte(p+1,p+4)
    return a and d and a+b*256+c*65536+d*16777216 or nil
end
-- Incoming 0x076, offsets include the four-byte packet header. Five 48-byte entries.
-- Two high bits per effect; decode bytewise to avoid uint64/double precision loss.
function M.decodePartyEffects(s)
    if type(s) ~= 'string' or #s < 244 then return nil end
    local out = {}
    for member=0,4 do
        local base=member*48
        local id=u32(s,base+4)
        if id and id ~= 0 then
            local effects={}
            for slot=0,31 do
                local packed=s:byte(base+12+math.floor(slot/4)+1)
                local high=math.floor(packed/2^(2*(slot%4)))%4
                local effect=s:byte(base+20+slot+1)+high*256
                if effect==255 or effect==1023 then break end -- remaining slots may contain zero padding
                if M.validEffect(effect) then effects[#effects+1]=effect end
            end
            out[id]=effects
        end
    end
    return out
end
function M.split(effects, metadata, overrides)
    local good,bad={},{}
    for _,id in ipairs(effects or {}) do
        local kind=overrides and overrides[tostring(id)]
        if kind == 'debuff' or (kind ~= 'buff' and metadata[id] and metadata[id].harmful) then
            bad[#bad+1]=id
        else good[#good+1]=id end
    end
    return good,bad
end
-- Retain mockup's base 117px row; expand only when actual icon count needs it.
function M.rowHeight(good,bad)
    return math.max(117,91+math.ceil(math.max(1,good)/11)*27,24+bad*27+4)
end
-- Shared measurements for drawing, icon hitboxes, row stacking and window height.
-- Only authoritative party slot 0 identifies the local player's row.
function M.memberLayout(member,cfg)
    local nameText=M.clamp(cfg and cfg.nameTextSize or 15,10,32)
    local jobText=M.clamp(cfg and cfg.jobTextSize or 10,10,32)
    local distanceText=M.clamp(cfg and cfg.distanceTextSize or 10,10,32)
    local nameExtra=math.max(0,math.max(nameText,jobText+3,distanceText+3)+4-23)
    local hpText=cfg and cfg.hpTextSize or 10
    local mpText=cfg and cfg.mpTextSize or 10
    hpText=M.clamp(hpText,10,24);mpText=M.clamp(mpText,10,24)
    local hpHeight=math.max(15,hpText+4)
    local mpHeight=math.max(15,mpText+4)
    local hpExtra,mpExtra=hpHeight-(15),mpHeight-15
    local extra=hpExtra+mpExtra
    local panelBottom=51+hpExtra+mpHeight+5
    local layout={nameText=nameText,jobText=jobText,distanceText=distanceText,nameExtra=nameExtra,hpHeight=hpHeight,hpText=hpText,
        hpTextOffset=(hpHeight-hpText)/2,mpHeight=mpHeight,mpText=mpText,mpTextOffset=(mpHeight-mpText)/2,
        panelBottom=panelBottom,mpY=51+hpExtra,
        tpTextY=74+extra,tpTop=31,tpBottom=panelBottom-6,
        buffsY=panelBottom+8,warningY=panelBottom+9,
        rowHeight=M.rowHeight(#member.good,#member.bad)+extra}
    layout.rowHeight=math.max(layout.buffsY+math.max(1,math.ceil(#member.good/11))*27+3,24+#member.bad*27+4)+nameExtra
    return layout
end
function M.resource(current,maximum)
    return tostring(current or '--')..' / '..(maximum ~= nil and tostring(maximum) or '--')
end
-- Key by server identity, never by party slot. A first observation is not a crossing.
function M.pulseStyle(amount,strength)
    local power=M.clamp(amount,0,1)*M.clamp(strength,0,5)
    return {power=power,alpha=math.floor(255*math.min(1,power)),haloAlpha=math.floor(110*math.min(1,power)),spread=power*4}
end
function M.partyTP(states,roster,now,duration,enabled)
    local nextStates={}
    for _,m in ipairs(roster) do
        m.tpPulse=0
        if m.available and m.tp~=nil then
            local old=states[m.id]
            local started=old and old.started
            if old and old.tp<1000 and m.tp>=1000 then started=now end
            if m.tp<1000 then started=nil end
            if started and now-started>=duration then started=nil end
            if enabled and started then
                local t=math.max(0,(now-started)/duration)
                m.tpPulse=(.5+.5*math.cos(t*6*math.pi))*(1-t)
            end
            nextStates[m.id]={tp=m.tp,started=started}
        end
    end
    return nextStates
end
return M
