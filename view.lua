local M={}
local model=require('model')
local ui=require('ui_compat')
local metadata=require('effects')
local jobAssets=require('jobs')
local hatLayout=require('hat_layout')
local geometry=require('arc_geometry')
local paths=geometry.paths()
local jobs={'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN'}
local colors={bg=0xF0332010,border=0xFFB4A091,name=0xFFEDC5E2,text=0xFFFFFFFF,muted=0xFFFFFFFF,leaderName=0xFF78D8F0,memberName=0xFFFFDFC0,cyan=0xFFD5B658}
-- Six base units of transparent bounds for outer glows. No content/hitbox offsets.
M.glowMargin=12
local function alpha(rgb,a)return math.floor(model.clamp(a,0,1)*255+.5)*0x1000000+rgb end
function M.height(roster,showHeader,cfg)
    local h=showHeader and 34 or 0
    for _,m in ipairs(roster) do h=h+model.memberLayout(m,cfg).rowHeight end
    return h
end
-- All coordinates, fonts, images, borders and hitboxes share the same scale.
function M.party(imgui,dl,x,y,s,roster,font,texture,hit,preview,showTP,showHeader,pulseStrength,cfg,boldFont)
    local function p(a,b) return {x+a*s,y+b*s} end
    local function rect(a,b,c,d,col) dl:AddRectFilled(p(a,b),p(c,d),col) end
    local function glowRect(left,upper,right,lower,rgb,intensity,radius)
        if intensity<=0 then return end
        -- A single non-overlapping gradient band on each side, with transparent
        -- outer edges. Core resources are drawn later and retain their colors.
        local clear=alpha(rgb,0);local lit=alpha(rgb,intensity)
        dl:AddRectFilledMultiColor(p(left-radius,upper),p(left,lower),clear,lit,lit,clear)
        dl:AddRectFilledMultiColor(p(right,upper),p(right+radius,lower),lit,clear,clear,lit)
        dl:AddRectFilledMultiColor(p(left,upper-radius),p(right,upper),clear,clear,lit,lit)
        dl:AddRectFilledMultiColor(p(left,lower),p(right,lower+radius),lit,lit,clear,clear)
        -- Rounded AA outline softens the band corners without tinting the fill.
        dl:AddRect(p(left,upper),p(right,lower),lit,3*s,0,s)
    end
    local function text(a,b,value,size,col,alreadyOutlined,drawFont)
        local pos=p(a,b)
        local color=col or colors.text
        local label=tostring(value)
        if not alreadyOutlined then
            -- A single offset shadow gives contrast without swelling glyphs or
            -- filling the gaps in small digits, slashes and punctuation.
            local offset=math.max(1,s*.75)
            local black=math.floor((math.floor(color/0x1000000)%256)*.8+.5)*0x1000000
            dl:AddText(drawFont or font,size*s,{pos[1]+offset,pos[2]+offset},black,label)
        end
        dl:AddText(drawFont or font,size*s,pos,color,label)
    end
    local function measure(value,size,drawFont)
        return ui.measure(imgui,drawFont or font,value,size,s)
    end
    local function right(a,b,value,size,col,drawFont)
        text(a-measure(value,size,drawFont),b,value,size,col,false,drawFont)
    end
    local function clipped(left,rightEdge,upper,lower,value,size,col,drawFont)
        dl:PushClipRect(p(left,upper),p(rightEdge,lower),true)
        text(left,upper,value,size,col,false,drawFont)
        dl:PopClipRect()
    end
    if showHeader then
        rect(2,0,394,29,0xF0402B18)
        text(10,6,(preview and 'PREVIEW  ' or 'MOVE FRAMES  ')..#roster..' / 6',12)
        right(384,7,'Drag to move',10,colors.muted)
    end
    local top=showHeader and 34 or 0
    for _,m in ipairs(roster) do
        local layout=model.memberLayout(m,cfg)
        local nameTop=top
        top=top+layout.nameExtra
        local protection=m.protection
        local tint=protection and protection.amount or 0
        local rgb=protection and protection.kind=='red'and 0x00504CFF or 0x00FF9D42
        if tint>0 then
            -- Convex capsule, clockwise in screen space. A triangle fan and
            -- ordinary lines avoid host-specific path/polyline signatures.
            local upper=top+20
            local lower=math.max(top+94,top+layout.panelBottom+3)
            local centerY=(upper+lower)/2
            local function shell(pad,fill,opacity,thickness)
                local radius=(lower-upper)/2+pad
                -- Three base pixels of clearance around the portrait and panel.
                -- Keep the left curve anchored to the portrait as bars get taller.
                local points={{395+pad,upper-pad},{395+pad,lower+pad}}
                local centerX=36.5
                for i=0,12 do
                    local angle=math.pi/2+i*math.pi/12
                    points[#points+1]={centerX+math.cos(angle)*(36.5+pad),centerY+math.sin(angle)*radius}
                end
                local color=alpha(rgb,tint*opacity)
                for i,a in ipairs(points)do
                    local b=points[i%#points+1]
                    if fill then dl:AddTriangleFilled(p(197.5,centerY),p(a[1],a[2]),p(b[1],b[2]),color)
                    else dl:AddLine(p(a[1],a[2]),p(b[1],b[2]),color,thickness*s)end
                end
            end
            local opacity=(cfg and cfg.protectionShellOpacity or 14)/100
            local glow=(cfg and cfg.protectionShellGlow or 100)/100
            local weight=math.max(1,math.sqrt(glow))
            shell(5,false,.07*glow,2*weight)
            shell(3,false,.13*glow,2*weight)
            shell(1,false,.25*glow,1.5*weight)
            shell(0,true,opacity,0)
            shell(0,false,.95*glow,1.5*weight)
        end
        local job=jobs[m.job] or '?'
        rect(49,top+23,392,top+layout.panelBottom,colors.bg)
        dl:AddRect(p(49,top+23),p(392,top+layout.panelBottom),m.slot==0 and colors.name or colors.border,3*s,0,s)
        -- Limit long names to their assigned space; preserve full name in tooltip.
        local distance=m.distance and string.format('%.1fy',m.distance) or '--'
        local jobLabel=job..'/'..(jobs[m.subjob] or '?')
        local distanceRight=387
        local distanceBudget=math.min(140,(distanceRight-77)*.45)
        distance=ui.fit(imgui,font,distance,layout.distanceText,distanceBudget-2,s)
        local distanceLeft=distanceRight-measure(distance,layout.distanceText)-2
        local jobRight=distanceLeft-8
        jobLabel=ui.fit(imgui,font,jobLabel,layout.jobText,math.max(0,jobRight-77-56),s)
        local jobLeft=jobRight-measure(jobLabel,layout.jobText)-2
        local nameRight=math.max(77,jobLeft-8)
        local name=ui.fit(imgui,boldFont or font,m.name,layout.nameText,nameRight-77-2,s)
        clipped(77,nameRight,nameTop,nameTop+layout.nameText+3,name,layout.nameText,m.isLeader and colors.leaderName or colors.memberName,boldFont)
        if hit('name'..m.id,77,nameTop,math.max(1,nameRight-77),layout.nameText+2,m) then imgui.SetTooltip(m.name..'\nClick to target') end
        clipped(jobLeft,jobRight,nameTop+3,nameTop+layout.jobText+6,jobLabel,layout.jobText,colors.muted)
        clipped(distanceLeft,distanceRight,nameTop+3,nameTop+layout.distanceText+6,distance,layout.distanceText,m.distance and m.distance>20 and 0xFF6666FF or colors.muted)
        local function bar(label,current,maximum,percent,by,bg,left,rightColor,height,textSize,textOffset)
            height=height or 15;textSize=textSize or 10;textOffset=textOffset or 1
            local edge=showTP~=false and 343 or 383
            rect(77,by,edge,by+height,bg)
            local ratio=(m.resourcesAvailable or m.available) and model.clamp(percent,0,100)/100 or 0
            if ratio>0 then dl:AddRectFilledMultiColor(p(77,by),p(77+(edge-77)*ratio,by+height),left,rightColor,rightColor,left) end
            local value=type(current)=='number' and tostring(math.floor(current)) or '--'
            local valueWidth=measure(value,textSize,boldFont)
            local size=math.min(textSize,(edge-77)*.9*textSize/math.max(1,valueWidth))
            dl:PushClipRect(p(77,by),p(edge,by+height),true)
            text((77+edge-measure(value,size,boldFont))/2,by+(height-size)/2,value,size,nil,false,boldFont)
            dl:PopClipRect()
        end
        bar('HP',m.hp,m.maxhp,m.hpp,top+31,0xFF2C253B,0xFF44349C,0xFF736AE3,layout.hpHeight,layout.hpText,layout.hpTextOffset)
        bar('MP',m.mp,m.maxmp,m.mpp,top+layout.mpY,0xFF223B42,0xFF3589A3,0xFF6CC7E1,layout.mpHeight,layout.mpText,layout.mpTextOffset)
        if hit('resources'..m.id,49,top+23,showTP~=false and 299 or 343,layout.panelBottom-23,m) then imgui.SetTooltip(m.name..'\nClick to target') end
        if showTP~=false then
            local stages=geometry.tp(m.available and m.tp or 0)
            local pulse=model.pulseStyle(m.tpPulse or 0,pulseStrength or 1)
            if pulse.power>0 then
                for stage=1,3 do
                    local left=350+(stage-1)*11
                    glowRect(left-1,top+layout.tpTop-1,left+8,top+layout.tpBottom+1,0x006FD6FF,math.min(.9,pulse.power*.24),2+pulse.spread*.25)
                end
            end
            for stage=1,3 do
                local left=350+(stage-1)*11
                rect(left,top+layout.tpTop,left+7,top+layout.tpBottom,0xFF3B3025)
                if stages[stage]>0 then
                    rect(left,top+layout.tpBottom-(layout.tpBottom-layout.tpTop)*stages[stage],left+7,top+layout.tpBottom,0xFFF0CF78)
                end
                dl:AddRect(p(left,top+layout.tpTop),p(left+7,top+layout.tpBottom),0xFF887359,0,0,s)
            end
            if hit('tp'..m.id,348,top+layout.tpTop-3,35,57) then
                imgui.SetTooltip(m.available and m.tp and (m.tp..' TP\nLeft: 0-1000 | Middle: 1000-2000 | Right: 2000-3000') or 'TP unavailable')
            end
        end
        dl:AddCircleFilled(p(36.5,top+57.5),33.5*s,0xFF332010,48)
        local hat=jobAssets[job] and texture('jobs/'..jobAssets[job])
        if hat then
            local placement=hatLayout[job]
            if placement then
                dl:AddImage(hat,p(placement.x,top+placement.y),p(placement.x+placement.w,top+placement.y+placement.h),
                    {placement.u0,placement.v0},{placement.u1,placement.v1})
            else dl:AddImage(hat,p(12,top+33),p(61,top+82)) end
        else
            -- Unknown/anonymous jobs, cross-zone data and failed textures always
            -- retain a visible neutral portrait instead of a missing image.
            local size=30
            local width=measure('?',size)
            text(36.5-width/2,top+57.5-size/2,'?',size,0xFFE0D5CA)
        end
        if cfg and cfg.showSAHats and m.saRemaining and m.saRemaining>0 then
            local value=tostring(math.ceil(m.saRemaining))
            local width,height=ui.measure(imgui,font,value,24,s)
            -- Large, solid red digits centered in the portrait; fit long values
            -- to its interior rather than allowing them to spill over the rim.
            local size=math.min(48,54*24/math.max(1,width),48*24/math.max(1,height))
            text(36.5-width*size/24/2,top+57.5-height*size/24/2,value,size,0xFF3333FF)
        end
        dl:AddCircle(p(36.5,top+57.5),33.5*s,colors.border,64,1.5*s)
        if hit('job'..m.id,2,top+24,69,67) then imgui.SetTooltip(hat and job..' hat artwork' or job..': hat artwork missing (placeholder)') end
        local function effect(id,ex,ey,slot)
            local tex=texture('status/'..id..'.png',id)
            if tex then dl:AddImage(tex,p(ex,ey),p(ex+24,ey+24))
            else dl:AddRect(p(ex,ey),p(ex+24,ey+24),colors.border,0,0,s) end
            if hit('fx'..m.id..':'..slot,ex,ey,24,24) then
                local info=metadata[id]
                imgui.SetTooltip((info and info.name or ('Status effect '..id))..' (ID '..id..')\nDuration unavailable'..(tex and '' or '\nNative icon missing'))
            end
        end
        for k,id in ipairs(m.good) do
            if k>model.maxPartyBuffs then break end
            effect(id,77+(k-1)*27,top+layout.buffsY,'g'..k)
        end
        for k,id in ipairs(m.bad) do effect(id,407,top+24+(k-1)*27,'b'..k) end
        if not m.available then text(77,top+layout.warningY,m.state,10,colors.muted) end
        top=nameTop+layout.rowHeight
    end
end
-- Independent borderless notification; position is owned by the host settings.
function M.shadowAlerts(dl,labels,x,y,font,size)
    size=size or 30.647
    for i,label in ipairs(labels) do
        local ty=y+(i-1)*(size+6)
        dl:AddText(font,size,{x+1,ty+1},0xCC000000,label)
        dl:AddText(font,size,{x,ty},0xFF3333FF,label)
    end
end
-- Original ArcUI 2.0.18 three-stage tapered arc, retaining its geometry and fill.
local gaugePaths,gaugeScale
-- Compatibility renderer: only standard public line drawing calls.
local function emitArc(dl,path,x,y,s,fill,trail,pulse)
    local cuts={0,1,fill,math.max(fill,trail)}
    for i=1,#path-2 do cuts[#cuts+1]=i/(#path-1) end
    table.sort(cuts)
    for i=1,#cuts-1 do
        local lo,hi=cuts[i],cuts[i+1]
        if hi-lo>1e-12 then
            local a,b=geometry.sample(path,lo),geometry.sample(path,hi)
            local mid=(lo+hi)*.5
            local col=mid<fill and 0xFFF0CF78 or mid<trail and 0xFF999999 or 0xB04B443B
            local width=geometry.sample(path,mid).w*s
            local pa={x+(a.x-204)*s,y+(a.y+170)*s}
            local pb={x+(b.x-204)*s,y+(b.y+170)*s}
            if mid<fill and (pulse.haloAlpha or 0)>0 then
                dl:AddLine(pa,pb,pulse.haloAlpha*0x1000000+0x00FFF5D8,width+(pulse.spread or 0)*s)
            end
            dl:AddLine(pa,pb,col,math.max(.1,width))
            if mid<fill and (pulse.alpha or 0)>0 then
                dl:AddLine(pa,pb,pulse.alpha*0x1000000+0x00FFF5D8,math.max(.1,width))
            end
        end
    end
end
function M.gauge(dl,x,y,s,tp,trail,progress,travel,font,textSize,pulseAmount,pulseStrength)
    if progress<=0 then return end
    local eased=progress*progress*(3-2*progress)
    local function p(a,b) return {x+(a-204)*s,y+(b+170+(1-eased)*travel)*s} end
    local bottom=math.max(370,346+textSize+8)
    dl:PushClipRect({x-12*s,y+340*s*(1-eased)},{x+130*s,y+bottom*s},true)
    local actual,old=geometry.tp(tp),geometry.tp(trail)
    local pulse=model.pulseStyle(pulseAmount or 0,pulseStrength or 1)
    if gaugeScale~=s then gaugePaths=geometry.paths(s);gaugeScale=s end
    for j,path in ipairs{gaugePaths.tp,gaugePaths.second,gaugePaths.third} do
        emitArc(dl,path,x,y+(1-eased)*travel*s,s,actual[j],old[j],pulse)
    end
    dl:AddText(font,textSize*s,p(207,176),0xFFF0F0E8,tostring(tp))
    dl:PopClipRect()
end
return M
