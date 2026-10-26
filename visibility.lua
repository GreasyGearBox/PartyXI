-- Shared read-only client detector. XIUI-derived signatures are attributed in
-- menu_detector.lua and licenses/XIUI-MIT.txt. Menu policy lives separately.
local detector=require('menu_detector').new(ashita and ashita.memory)
local M={}
function M.sample()return detector:sample()end
-- Legacy event/interface hiding; maps are now governed by menu_policy settings.
function M.hidden()
    local state=M.sample()
    return state.event or state.interface
end
return M
