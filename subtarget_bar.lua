local ui=require('ui_compat')
local M={width=190,height=36}
function M.initialPlacement(cfg)
    return math.max(0,cfg.targetX+(cfg.targetWidth-8-M.width)*cfg.targetScale),
        math.max(0,cfg.targetY+16*cfg.targetScale),cfg.targetScale
end
-- Independent overlay: just a name and HP track, with no descriptive title.
function M.draw(gui,dl,x,y,sub,font,scale)
    local function p(a,b)return {x+a*scale,y+b*scale}end
    local function width(value,size)
        return ui.measure(gui,font,value,size,scale)
    end
    local name=sub.name or ''
    local offset=math.max(1,scale*.75)
    local limit=M.width-3-offset/scale
    if width(name,16)>limit then
        while #name>0 and width(name..'...',16)>limit do name=name:sub(1,-2)end
        name=name..'...'
    end
    local function text(a,b,value,size,color)
        local pos=p(a,b)
        dl:AddText(font,size*scale,{pos[1]+offset,pos[2]+offset},0xCC000000,value)
        dl:AddText(font,size*scale,pos,color or 0xFFFFFFFF,value)
    end
    text(0,0,name,16,sub.nameColor or 0xFFFFDFC0)
    dl:AddRectFilled(p(0,20),p(M.width,36),0xFF2C253B)
    local ratio=math.max(0,math.min(100,sub.hpp or 0))/100
    if ratio>0 then dl:AddRectFilledMultiColor(p(0,20),p(M.width*ratio,36),0xFF44349C,0xFF736AE3,0xFF736AE3,0xFF44349C)end
    dl:AddRect(p(0,20),p(M.width,36),0xFFB4A091,0,0,math.max(.5,scale*.75))
    local percent=string.format('%d%%',sub.hpp or 0)
    text(M.width-3-width(percent,12),22,percent,12)
end
return M
