require "FunctionalPockets/Native"
require "TimedActions/ISInventoryTransferAction"
local FP = FunctionalPockets

local originalNew = ISInventoryTransferAction.new
function ISInventoryTransferAction:new(character, item, srcContainer, destContainer, time)
    local action = originalNew(self, character, item, srcContainer, destContainer, time)
    if isClient() or isServer() or not item or not destContainer then return action end
    if not FP.isPocketContainer(srcContainer) or character:isTimedActionInstant() then return action end
    if not action.maxTime or action.maxTime <= 0 then return action end

    local options = SandboxVars and SandboxVars.FunctionalPockets
    local speed = options and options.RetrievalSpeed or 100
    if speed == 100 then return action end

    action.maxTime = action.maxTime * 100 / math.max(1, speed)
    -- Vanilla stores the initial duration separately for queued transfers.
    if action.queueList and action.queueList[1] then
        action.queueList[1].time = action.maxTime
    end
    return action
end
