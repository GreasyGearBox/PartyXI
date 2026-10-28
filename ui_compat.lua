local M={}
function M.modern()
    return type(ImGuiChildFlags_Borders)=='number'
end
function M.beginChild(gui,id,size)
    if M.modern() then return gui.BeginChild(id,size,ImGuiChildFlags_Borders,0) end
    return gui.BeginChild(id,size,true,0)
end
function M.pushFont(gui,font,size)
    if M.modern() then gui.PushFont(font,size or 24) else gui.PushFont(font) end
end
local function dimensions(value,height)
    if type(value)=='number' then return value,type(height)=='number' and height or nil end
    if value then
        local ok,w,h=pcall(function()return value.x or value[1],value.y or value[2]end)
        if ok and type(w)=='number' then return w,type(h)=='number' and h or nil end
    end
end
function M.measure(gui,font,value,size,scale)
    value=tostring(value);scale=scale or 1
    -- Phoenix's direct ImFont:CalcTextSizeA binding raises a native access
    -- violation. Measure through the active ImGui font instead.
    local pushed=font and type(gui.PushFont)=='function'
    if pushed then M.pushFont(gui,font,M.modern() and size*scale or 24) end
    local native=type(gui.GetFontSize)=='function' and gui.GetFontSize() or 24
    if type(native)~='number' or native<=0 then native=24 end
    local w,h=dimensions(gui.CalcTextSize(value))
    if pushed then gui.PopFont() end
    return (w or 0)*size/native,(h or native)*size/native
end
function M.fit(gui,font,value,size,limit,scale)
    value=tostring(value)
    if limit<=0 then return '' end
    if M.measure(gui,font,value,size,scale)<=limit then return value end
    if M.measure(gui,font,'...',size,scale)>limit then return '' end
    while #value>0 and M.measure(gui,font,value..'...',size,scale)>limit do value=value:sub(1,-2) end
    return value..'...'
end
return M
