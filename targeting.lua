local M={}
function M.select(member,core)
    if not member or not member.available then return false end
    local slot=member.slot
    if type(slot)~='number' or slot%1~=0 or slot<0 or slot>5 then return false end
    -- Recheck the slot so a roster change cannot target its new occupant.
    local party=core:GetMemoryManager():GetParty()
    if tonumber(party:GetMemberServerId(slot))~=member.id then return false end
    core:GetChatManager():QueueCommand(1,string.format('/target <p%d>',slot))
    return true
end
return M
