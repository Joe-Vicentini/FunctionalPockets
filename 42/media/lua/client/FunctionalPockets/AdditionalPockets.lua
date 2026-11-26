require "FunctionalPockets/Native"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
local FP = FunctionalPockets
local Action = ISBaseTimedAction:derive("FPAdditionalPocketAction")

local fabricTypes = {
    ["Base.RippedSheets"] = true,
    ["Base.DenimStrips"] = true,
    ["Base.LeatherStrips"] = true,
}

-- Look in the carried inventory and ordinary bags, but not inside the garment
-- being altered. Recheck at completion so queued actions cannot reuse supplies.
local function supplies(player, garment)
    local found = {}
    local function scan(inventory)
        local items = inventory:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item ~= garment then
                local id = item:getFullType()
                if id == "Base.Scissors" and not found.scissors then found.scissors = item end
                if id == "Base.Needle" and not found.needle then found.needle = item end
                if id == "Base.Thread" and not found.thread and item:getCurrentUses() > 0 then
                    found.thread = item
                end
                if fabricTypes[id] and not found.fabric then found.fabric = item end
                if instanceof(item, "InventoryContainer") then scan(item:getInventory()) end
            end
        end
    end
    scan(player:getInventory())
    if found.scissors and found.needle and found.thread and found.fabric then return found end
end

local function carried(inventory, garment)
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item == garment then return true end
        if instanceof(item, "InventoryContainer") and carried(item:getInventory(), garment) then
            return true
        end
    end
    return false
end

local function hasRequiredTailoring(player)
    local options = SandboxVars and SandboxVars.FunctionalPockets
    local minimum = options and options.AdditionalPocketMinimumTailoring or 0
    return player:getPerkLevel(Perks.Tailoring) >= minimum
end

function Action:isValid()
    return hasRequiredTailoring(self.character)
        and carried(self.character:getInventory(), self.garment)
        and FP.additionalPocketOptions(self.garment) ~= nil
        and supplies(self.character, self.garment) ~= nil
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    local speed = SandboxVars.FunctionalPockets.AdditionalPocketSewingSpeed or 100
    return math.max(1, (150 - self.character:getPerkLevel(Perks.Tailoring) * 6) * 100 / speed)
end

function Action:start()
    self:setActionAnim("SewingCloth")
    self.sound = self.character:playSound("Sewing")
end

function Action:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function Action:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function Action:perform()
    self:stopSound()
    self.character:resetModel()
    ISBaseTimedAction.perform(self)
end

function Action:complete()
    if not self:isValid() then return false end
    local materials = supplies(self.character, self.garment)
    if not materials or not FP.addAdditionalPocket(self.garment) then return false end
    materials.fabric:getContainer():Remove(materials.fabric)
    materials.thread:UseAndSync()
    return true
end

function Action:new(character, garment)
    local o = ISBaseTimedAction.new(self, character)
    o.garment = garment
    o.maxTime = o:getDuration()
    return o
end

local function queue(player, garment)
    ISTimedActionQueue.add(Action:new(player, garment))
end

local function fillMenu(playerNum, context, items)
    if isClient() or isServer() then return end
    local player = getSpecificPlayer(playerNum)
    if not player or #items ~= 1 or not hasRequiredTailoring(player) then return end
    local entry = items[1]
    local garment = entry
    if type(entry) == "table" then
        if not entry.items or #entry.items ~= 2 then return end
        garment = entry.items[1]
    end
    if not garment or not carried(player:getInventory(), garment) then return end
    local available, count, maximum = FP.additionalPocketOptions(garment)
    if not available or not supplies(player, garment) then return end
    context:addOption(getText("ContextMenu_FunctionalPockets_SewAdditionalPocket", count, maximum),
        player, queue, garment)
end

Events.OnFillInventoryObjectContextMenu.Add(fillMenu)
