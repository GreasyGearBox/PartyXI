local M={}
function M.value(state,current,now,duration,enabled,highDuration)
    if not enabled or duration<=0 then return current,nil end
    if not state then return current,{previous=current,from=current,to=current,start=now,duration=duration} end
    local function displayed()
        local u=math.max(0,math.min(1,(now-state.start)/(state.duration or duration)))
        return state.to+(state.from-state.to)*(1-u)^2
    end
    local old=displayed()
    if current<state.previous then
        state.from=math.max(old,state.previous)
        state.duration=(state.previous>2000 and highDuration) or duration
        state.to=current;state.start=now
    elseif current~=state.previous then
        state.to=current
        if current>=old then state.from=current;state.start=now end
    end
    state.previous=current
    return math.max(current,displayed()),state
end
return M
