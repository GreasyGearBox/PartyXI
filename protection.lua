-- Confirmed status snapshots only. No cast guesses, durations or shadow counting.
local M={}
local utsusemi={[66]=true,[444]=true,[445]=true,[446]=true}
function M.families(ids)
    local shadows,eye=false,false
    for _,id in ipairs(ids or {})do
        if utsusemi[id]then shadows=true elseif id==67 then eye=true end
    end
    return shadows,eye
end
local function signature(m)
    return table.concat({m.name or '',m.job or 0,m.level or 0,m.subjob or 0,m.sublevel or 0,m.zone or 0},':')
end
function M.update(states,roster,now,cfg)
    local nextStates={}
    for _,m in ipairs(roster)do
        m.protection=nil
        local selected=cfg.protectionEnabled and cfg.protectionMembers and cfg.protectionMembers[tostring(m.id)]==m.name
        local obs=m.effectObservation
        if selected and m.available and m.effectsKnown and obs and now-obs.time<=cfg.effectStaleSeconds then
            local sig=signature(m)
            local old=states[m.id]
            local fresh=not old or old.key~=obs.key or old.revision~=obs.revision
            local continuous=old and old.signature==sig and old.key==obs.key and obs.time-old.observedAt<=cfg.effectStaleSeconds
            local s=continuous and old or {signature=sig,key=obs.key}
            if old and old.signature~=sig and old.key==obs.key then
                s.blockedRevision=old.revision
                s.revision=obs.revision;s.observedAt=obs.time
            end
            if s.blockedRevision and s.blockedRevision~=obs.revision then s.blockedRevision=nil end
            if not s.blockedRevision then
                if fresh or not continuous then
                    local shadows,eye=M.families(obs.ids)
                    local active=shadows or eye
                    if active then s.redStart=nil;s.pending=nil
                    elseif continuous and s.active then s.pending=now end
                    s.shadows=shadows;s.eye=eye;s.active=active
                    s.revision=obs.revision;s.observedAt=obs.time
                end
                -- Briefly coalesce replacement/reapplication packets. A fresh absent
                -- observation is required; cache loss never creates this pending state.
                if s.pending and now-s.pending>=.18 then s.redStart=now;s.pending=nil end
                -- The text and shield share the same confirmed red transition.
                -- Red stays latched, but this player's text only lasts 3 seconds.
                local visual={kind='neutral',amount=0,utsusemi=s.shadows,thirdEye=s.eye,
                    shadowLost=s.redStart~=nil and now-s.redStart<3}
                if s.active then visual.kind='blue';visual.amount=(cfg.protectionBlue or 80)/100
                elseif s.redStart then
                    -- Latch a confirmed protection loss until a positive
                    -- protection snapshot arrives. Text alert remains 3 seconds.
                    visual.kind='red';visual.amount=(cfg.protectionRed or 80)/100
                end
                m.protection=visual
            end
            nextStates[m.id]=s
        end
    end
    return nextStates
end
-- Persistent localized TP readiness, separate from the personal arc's old envelope.
function M.ready(roster,now,period,enabled)
    for _,m in ipairs(roster)do
        m.tpPulse=0
        if enabled and m.available and type(m.tp)=='number'and m.tp>=1000 then
            m.tpPulse=.35+.65*(.5-.5*math.cos(now*2*math.pi/math.max(.3,period)))
        end
    end
end
return M
