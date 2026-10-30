local ui=require('ui_compat')
local times=require('data.cast_times')
local M={states={}}
function M.reset()M.states={}end
function M.clear(id)M.states[id]=nil end
local function name(resources,kind,id)
    local ok,value=pcall(function()
        if kind==8 then return resources:GetSpellById(id).Name[1]end
        if kind==7 and id>=256 then return resources:GetString('monsters.abilities',id-256)end
        return resources:GetAbilityById(id).Name[1]
    end)
    return ok and type(value)=='string' and value~='' and value or ((kind==8 and 'Spell ' or 'Ability ')..id)
end
function M.observe(action,now,resources)
    M.get(nil,now)
    local kind=action.kind
    if kind==7 or kind==8 then
        local first=action.targets and action.targets[1]
        local detail=first and first.actions and first.actions[1]
        if action.param==28787 or (detail and detail.message==0)then M.clear(action.actor);return end
        if not detail or type(detail.param)~='number' or detail.param<=0 then return end
        -- Category 7 also carries weapon-skill preparation; monster moves use the 256 offset.
        if kind==7 and detail.param<256 then return end
        if kind==8 and action.param~=24931 then return end
        local duration=(kind==8 and times.spells or times.abilities)[detail.param]
        if not duration and kind==8 then
            local ok,value=pcall(function()return resources:GetSpellById(detail.param).CastTime/4 end)
            if ok and type(value)=='number' and value>0 and value<180 then duration=value end
        end
        M.states[action.actor]={name=name(resources,kind,detail.param),started=now,expires=now+math.max(60,(duration or 0)+15),kind=kind,duration=duration}
    elseif kind==3 or kind==4 or kind==11 or kind==13 then M.clear(action.actor)
    end
end
function M.get(id,now)
    for actor,state in pairs(M.states)do if now>=state.expires then M.states[actor]=nil end end
    return M.states[id]
end
function M.geometry(cfg,x,y)
    local s=cfg.targetScale
    local trackLeft,trackRight=86,cfg.targetWidth-8
    local width=(trackRight-trackLeft)*(cfg.castWidthPercent or 50)/100
    local hpY=62+math.max(cfg.targetNameSize,cfg.targetInfoSize)+5
    local hpH=math.max(18,cfg.targetHPSize+2)
    if cfg.castDetached then return cfg.castX,cfg.castY,cfg.castWidth,cfg.castHeight,cfg.castScale end
    return x+(trackRight-width)*s,y+(hpY+hpH+2)*s,width,cfg.castHeight,s
end
-- Native cast progress is local-player data only. Keep packet completion authoritative.
function M.withNative(state,memory)
    if not state or state.kind~=8 then return state end
    local result={}
    for k,v in pairs(state)do result[k]=v end
    result.native=true
    local ok,value=pcall(function()return memory:GetCastBar():GetPercent()end)
    if ok and type(value)=='number' and value==value and value>=0 and value<=1 then
        result.nativePercent=value
    end
    return result
end
function M.progress(state,now)
    if state.native then return state.nativePercent,nil end
    if not state.duration or state.duration<=0 then return nil,nil end
    local elapsed=math.max(0,now-state.started)
    return math.min(.98,elapsed/state.duration),math.max(0,state.duration-elapsed)
end
function M.draw(gui,dl,x,y,w,h,s,state,font,cfg,now)
    dl:AddRectFilled({x,y},{x+w*s,y+h*s},0xE020302E)
    local progress,remaining=M.progress(state,now)
    local fill=progress or (state.native and 0 or .15)
    if fill>0 then dl:AddRectFilled({x+s,y+s},{x+(1+(w-2)*fill)*s,y+(h-1)*s},0xD050B8DE)end
    dl:AddRect({x,y},{x+w*s,y+h*s},0xFF75D8F0,0,0,math.max(1,s))
    local size=math.min(cfg.castTextSize,h-4)
    local timer=state.native and (state.nativePercent and string.format('%d%%',math.floor(state.nativePercent*100)) or 'Progress unavailable') or remaining and (remaining>0 and string.format('~%.1fs',remaining) or 'Resolving') or 'Timing unknown'
    local timerSize=math.min(size,(w*.42)*size/math.max(1,ui.measure(gui,font,timer,size,s)))
    local timerWidth=ui.measure(gui,font,timer,timerSize,s)
    local nameWidth=math.max(0,w-timerWidth-16)
    local label=ui.fit(gui,font,state.name,size,nameWidth,s)
    local tw=ui.measure(gui,font,label,size,s)
    local tx,ty=x+(5+(nameWidth-tw)/2)*s,y+(h-size)*s/2
    dl:AddText(font,size*s,{tx+s,ty+s},0xCC000000,label)
    dl:AddText(font,size*s,{tx,ty},0xFFFFFFFF,label)
    local timerX,timerY=x+(w-5-timerWidth)*s,y+(h-timerSize)*s/2
    dl:AddText(font,timerSize*s,{timerX+s,timerY+s},0xCC000000,timer)
    dl:AddText(font,timerSize*s,{timerX,timerY},0xFFFFFFFF,timer)
end
return M
