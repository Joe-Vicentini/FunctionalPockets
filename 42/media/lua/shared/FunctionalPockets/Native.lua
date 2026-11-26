require "FunctionalPockets/Rules"
local FP = FunctionalPockets

-- Enabled for experimental testing, NOT production gameplay.
-- Use only in a disposable NEW single-player world.
local experimental = true
local converted = {}

function FP.isPocketContainer(container)
    local owner = container and container:getContainingItem()
    return owner ~= nil and converted[owner:getFullType()] ~= nil
end

function FP.classifyScript(script)
    if not script:isItemType(ItemType.CLOTHING) then return nil end
    local location = script:getBodyLocation()
    if not location then return nil end
    local tags = {}
    local iterator = script:getTags():iterator()
    while iterator:hasNext() do tags[#tags + 1] = tostring(iterator:next()) end
    return FP.classify(script:getFullName(), script:getName(), tostring(location), tags, true, false)
end

-- Called by the native container's admission check, not a UI-only restriction.
function FP.acceptItem(container, item)
    local owner = container:getContainingItem()
    local profile = owner and converted[owner:getFullType()]
    if not profile or not item or item == owner then return false end
    if instanceof(item, "InventoryContainer") or FP.isBulky(item:getType()) then return false end
    local weight = item:getActualWeight()
    return weight <= profile.maxItemSize
        and container:getCapacityWeight() + weight <= profile.capacity + 0.0001
end

local function install()
    if not experimental or isClient() or isServer() then return end
    local scripts = getScriptManager():getAllItems()
    for i = 0, scripts:size() - 1 do
        local script = scripts:get(i)
        local profile = FP.classifyScript(script)
        if profile then
            local location = tostring(script:getBodyLocation())
            -- Native container item type is necessary; the original Java Clothing
            -- class is NOT retained. Do not use this path in a production save.
            script:setItemType(ItemType.CONTAINER)
            script:DoParam("CanBeEquipped", location)
            script:DoParam("Capacity", tostring(math.max(1, math.ceil(profile.capacity))))
            script:DoParam("WeightReduction", tostring(profile.reduction))
            script:DoParam("MaxItemSize", tostring(profile.maxItemSize))
            script:DoParam("AcceptItemFunction", "FunctionalPockets.acceptItem")
            converted[script:getFullName()] = profile
        end
    end
end

Events.OnGameBoot.Add(install)

-- Vanilla corpse loot is generated lazily; OnZombieDead is too early.
local function distributeZombieLoot(roomType, containerType, inventory)
    if isClient() or isServer() or next(converted) == nil then return end
    local options = SandboxVars and SandboxVars.FunctionalPockets
    local mode = options and options.ZombiePocketLoot
    if mode ~= 2 and mode ~= 3 and mode ~= 4 then return end
    if not instanceof(inventory, "ItemContainer") then return end
    local body = inventory:getParent()
    if not instanceof(body, "IsoDeadBody") or not body:isZombie()
        or body:isPlayer() or body:getContainer() ~= inventory then return end

    local pockets, loose = {}, {}
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if body:isEquippedClothing(item) and instanceof(item, "InventoryContainer")
            and FP.isPocketContainer(item:getInventory()) then
            pockets[#pockets + 1] = item:getInventory()
        elseif not body:isEquipped(item) and not body:isEquippedClothing(item)
            and not body:isAttachedItem(item) and not body:isHandItem(item) then
            loose[#loose + 1] = item
        end
    end

    -- Snapshot before moving items; try every pocket before overflow.
    for _, item in ipairs(loose) do
        local moved = false
        for _, pocket in ipairs(pockets) do
            if FP.acceptItem(pocket, item) and pocket:isItemAllowed(item) then
                inventory:Remove(item)
                pocket:AddItem(item)
                if pocket:getItems():contains(item) then
                    moved = true
                    break
                end
                inventory:AddItem(item)
            end
        end
        if not moved then
            if mode == 3 then
                local square = body:getSquare()
                if square then
                    inventory:Remove(item)
                    if not square:AddWorldInventoryItem(item, 0.5, 0.5, 0) then
                        inventory:AddItem(item)
                    end
                end
            elseif mode == 4 then
                inventory:Remove(item)
            end
        end
    end
end

Events.OnFillContainer.Add(distributeZombieLoot)
