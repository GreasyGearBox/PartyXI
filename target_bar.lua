local ui=require('ui_compat')
local M={}
local mobs=require('target_mobinfo')
local anonymous={}
local playerIndices={}
-- Player update flags: 0x00D byte 0x21 bit 0x10; self 0x037 byte 0x28 bit 0x20.
-- Source: Windower/Lua addons/libs/packets/fields.lua (PC and player updates).
function M.observePlayer(id,packet)
    if id==0x00A or id==0x00B then anonymous={};playerIndices={};return end
    if type(packet)~='string' then return end
    local function uint(at,n)local v=0;for i=0,n-1 do v=v+packet:byte(at+i)*256^i end;return v end
    if id==0x00D and #packet>=34 then
        local serverId=uint(5,4)
        local mask=packet:byte(11)
        if math.floor(mask/32)%2==1 then anonymous[serverId]=nil;playerIndices[serverId]=nil
        else
            playerIndices[serverId]=uint(9,2)
            if math.floor(mask/4)%2==1 then anonymous[serverId]=math.floor(packet:byte(34)/16)%2==1 end
        end
    elseif id==0x037 and #packet>=42 then
        anonymous[uint(37,4)]=math.floor(packet:byte(41)/32)%2==1
    end
end

-- ImGui colors are ABGR: native yellow, outside-claim pink, own-claim red.
function M.nameColor(mem,index,monster)
    if not monster then
        local ok,id=pcall(function()
            local ent=mem:GetEntity()
            if (ent:GetSpawnFlags(index) or 0)%2==1 then return ent:GetServerId(index) end
        end)
        return ok and anonymous[id] and 0xFFFF8855 or 0xFFFFDFC0
    end
    local ok,color=pcall(function()
        local claim=(mem:GetEntity():GetClaimStatus(index) or 0)%65536
        if claim==0 then return 0xFF66FFFF end
        local party=mem:GetParty()
        for slot=0,17 do
            if party:GetMemberIsActive(slot)==1 then
                local id=party:GetMemberServerId(slot)
                if id and id~=0 and id%65536==claim then return 0xFF6666FF end
            end
        end
        return 0xFFFF66FF
    end)
    return ok and color or 0xFF66FFFF
end
function M.sample(core)
    local ok,result=pcall(function()
        local mem=core:GetMemoryManager()
        local targets,entities=mem:GetTarget(),mem:GetEntity()
        local activeOK,active=pcall(function()return targets:GetIsSubTargetActive()end)
        local subActive=activeOK and (active==1 or active==true)
        local cursor=targets:GetTargetIndex(0)
        local original=subActive and targets:GetTargetIndex(1) or cursor
        local index=original and original>0 and original or cursor
        if not index or index<=0 then return nil end
        local id=entities:GetServerId(index)
        local name=entities:GetName(index)
        if not id or id==0 or not name or name=='' then return nil end
        local distance=entities:GetDistance(index)
        local monster=math.floor((entities:GetSpawnFlags(index) or 0)/16)%2==1
        local sub
        if subActive and cursor and cursor>0 and original and original>0 then
            local subId=entities:GetServerId(cursor)
            local subName=entities:GetName(cursor)
            if subId and subId~=0 and subName and subName~=''then
                sub={nameColor=M.nameColor(mem,cursor,math.floor((entities:GetSpawnFlags(cursor) or 0)/16)%2==1),id=subId,name=subName,hpp=entities:GetHPPercent(cursor)or 0}
            end
        end
        return {index=index,nameColor=M.nameColor(mem,index,monster),subtarget=sub,id=id,name=name,hpp=entities:GetHPPercent(index) or 0,
            distance=distance and math.sqrt(math.max(0,distance)),monster=monster,
            info=monster and mobs.get(mem:GetParty():GetMemberZone(0),id,name) or nil}
    end)
    return ok and result or nil
end
-- Resolve only referenced entities; never enumerate the entity table.
function M.actionTarget(core,t,tracker,now)
    if not t or not t.monster or (t.hpp or 0)<=0 then return nil end
    local ok,result=pcall(function()
        local mem=core:GetMemoryManager()
        local entities=mem:GetEntity()
        local function entity(index,expected,label)
            if type(index)~='number' or index%1~=0 or index<=0 or index>=2304 then return nil end
            local success,value=pcall(function()
                local id=entities:GetServerId(index)
                if not id or id==0 or (expected and id~=expected) then return nil end
                local name=entities:GetName(index)
                if not name or name=='' then return nil end
                local hp=entities:GetHPPercent(index)
                if type(hp)~='number' or hp<=0 then return nil end
                local monster=math.floor((entities:GetSpawnFlags(index) or 0)/16)%2==1
                return {id=id,name=name,hpp=hp,nameColor=M.nameColor(mem,index,monster),label=label}
            end)
            return success and value or nil
        end
        local record=tracker and tracker.targets and tracker.targets[t.id]
        if record and type(now)=='number' and now>=record.time and now-record.time<=30 then
            local id=record.id
            local value=entity(playerIndices[id],id,'Last action')
            if value then return value end
            local party=mem:GetParty()
            for slot=0,17 do
                local found,memberId=pcall(function()return party:GetMemberServerId(slot)end)
                if found and memberId==id then
                    local success,index=pcall(function()return party:GetMemberTargetIndex(slot)end)
                    if success then value=entity(index,id,'Last action');if value then return value end end
                end
            end
            -- Monster/pet IDs encode their local index; still validate the full ID.
            if type(id)=='number' then value=entity(id%4096,id,'Last action');if value then return value end end
        end
        -- A local index is valid only while it still identifies the sampled mob.
        if not t.index or entities:GetServerId(t.index)~=t.id then return nil end
        local success,index=pcall(function()return entities:GetTargetedIndex(t.index)end)
        if success then return entity(index,nil,'Target') end
    end)
    return ok and result or nil
end
function M.details(t,cfg)
    local parts={}
    local info=t.info
    if t.monster then
        if cfg.targetLevel then
            parts[#parts+1]=info and ('Lv '..(info.min==info.max and tostring(info.min) or info.min..'-'..info.max)) or 'Lv ?'
        end
        if cfg.targetAggro then parts[#parts+1]=info and (info.aggro and 'Aggro' or 'Passive') or 'Aggro ?' end
        if cfg.targetLink then parts[#parts+1]=info and (info.link and 'Links' or 'No link') or 'Link ?' end
        if cfg.targetDetection and info then
            for _,method in ipairs(info.methods or {})do parts[#parts+1]=method end
        end
    end
    return table.concat(parts,' | ')
end
function M.height(cfg)return 56+6+cfg.targetNameSize+8+cfg.targetInfoSize+8+math.max(24,cfg.targetHPSize+6)+2*(32+(cfg.targetTimers and (cfg.targetTimerSize or 12)+4 or 0))+8 end
function M.timer(seconds)
    if type(seconds)~='number'or seconds<=0 then return nil end
    seconds=math.ceil(seconds)
    if seconds>=60 then return string.format('%dm%02d',math.floor(seconds/60),seconds%60)end
    return seconds..'s'
end
function M.draw(gui,dl,x,y,t,font,cfg,texture,nameFont)
    local s,w=cfg.targetScale,cfg.targetWidth
    local function p(a,b)return {x+a*s,y+b*s}end
    local function width(value,size)
        return ui.measure(gui,font,value,size,s)
    end
    local function fit(value,size,limit)
        limit=math.max(0,limit-math.max(1/s,.75))
        if width(value,size)<=limit then return value end
        while #value>0 and width(value..'...',size)>limit do value=value:sub(1,-2)end
        return value..'...'
    end
    local function text(a,b,value,size,color,drawFont)
        local offset=math.max(1,s*.75)
        -- Include the shadow in the right bound, including fractional scales.
        a=math.min(a,w-8-width(value,size)-offset/s)
        local pos=p(a,b)
        dl:AddText(drawFont or font,size*s,{pos[1]+offset,pos[2]+offset},0xCC000000,value)
        dl:AddText(drawFont or font,size*s,pos,color or 0xFFFFFFFF,value)
    end
    -- Leave the entire left 72px area empty for the separate Gaze addon.
    local left=80
    local nameY=62 -- preserve the saved main-target drawing origin
    local details=M.details(t,cfg)
    local distance=cfg.targetDistance and t.distance and string.format('%.1fy',t.distance)or ''
    local trackLeft,trackRight=left+6,w-8
    local reserved=distance~='' and width(distance,cfg.targetNameSize)+12 or 0
    local hpY=nameY+math.max(cfg.targetNameSize,cfg.targetInfoSize)+5
    local hpH=math.max(18,cfg.targetHPSize+2)
    local infoY=hpY+hpH+7
    local panelBottom=infoY+(details~='' and cfg.targetInfoSize+3 or 0)
    -- Main target name always uses the bold face, including width measurement.
    if nameFont then ui.pushFont(gui,nameFont,24) end
    text(trackLeft,nameY,ui.fit(gui,nameFont or font,t.name,cfg.targetNameSize,trackRight-trackLeft-reserved-2,s),cfg.targetNameSize,t.nameColor or (t.monster and 0xFF66FFFF or 0xFFFFDFC0),nameFont)
    if nameFont then gui.PopFont() end
    if distance~=''then text(trackRight-width(distance,cfg.targetNameSize),nameY,distance,cfg.targetNameSize)end
    -- Only the HP track has a border; the surrounding canvas stays transparent.
    dl:AddRectFilled(p(trackLeft,hpY),p(trackRight,hpY+hpH),0xFF2C253B)
    local ratio=math.max(0,math.min(100,t.hpp))/100
    if ratio>0 then dl:AddRectFilledMultiColor(p(trackLeft,hpY),p(trackLeft+(trackRight-trackLeft)*ratio,hpY+hpH),0xFF44349C,0xFF736AE3,0xFF736AE3,0xFF44349C)end
    dl:AddRect(p(trackLeft,hpY),p(trackRight,hpY+hpH),0xFFB4A091,0,0,math.max(.5,s*.75))
    local hp=string.format('%d%%',t.hpp)
    text(trackRight-4-width(hp,cfg.targetHPSize),hpY+(hpH-cfg.targetHPSize)/2,hp,cfg.targetHPSize)
    if details~=''then text(trackLeft,infoY,fit(details,cfg.targetInfoSize,trackRight-trackLeft),cfg.targetInfoSize,0xFFFFFFFF)end
    if cfg.targetBuffs then
        local buffs=t.buffs or {}
        local iconSize=24
        local timerSize=cfg.targetTimerSize or 12
        local cellWidth=28
        if cfg.targetTimers then
            for _,id in ipairs(buffs)do
                local label=M.timer(t.remaining and t.remaining[id])
                if label then cellWidth=math.max(cellWidth,width(label,timerSize)+4)end
            end
        end
        local rowHeight=cfg.targetTimers and 32+timerSize+4 or 28
        cellWidth=math.min(cellWidth,trackRight-trackLeft-2)
        local cols=math.max(1,math.floor((trackRight-trackLeft-2)/cellWidth))
        for i,id in ipairs(buffs)do
            if i>cols*2 then break end
            local bx=trackLeft+1+(i-1)%cols*cellWidth+(cellWidth-iconSize)/2
            local by=panelBottom+6+math.floor((i-1)/cols)*rowHeight
            local tex=texture and texture('status/'..id..'.png',id)
            if tex then dl:AddImage(tex,p(bx,by),p(bx+iconSize,by+iconSize))end
            local label=cfg.targetTimers and M.timer(t.remaining and t.remaining[id])
            if label then
                -- Keep the complete duration; shrink only when the cell is narrow.
                local drawSize=math.min(timerSize,timerSize*(cellWidth-4)/math.max(1,width(label,timerSize)))
                text(bx+iconSize/2-width(label,drawSize)/2,by+iconSize+3,label,drawSize)
            end
        end
    end
end
return M
