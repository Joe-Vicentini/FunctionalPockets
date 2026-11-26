require "FunctionalPockets/Rules"
local FP = FunctionalPockets

-- Enabled for experimental testing, NOT production gameplay.
-- Use only in a disposable NEW single-player world.
local experimental = true
local converted = {}
local hasConverted = false

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

local function instanceProfile(owner, profile)
    return FP.profileWithExtraPockets(profile, owner:getModData().FunctionalPocketsExtraRegions)
end

function FP.additionalPocketOptions(owner)
    if isClient() or isServer() or not owner then return nil end
    local options = SandboxVars and SandboxVars.FunctionalPockets
    if not options or not options.AllowAdditionalPockets then return nil end
    local base = converted[owner:getFullType()]
    if not base or not instanceof(owner, "InventoryContainer") then return nil end
    local profile = instanceProfile(owner, base)
    local covered = base.coveredRegions or {}
    local maximum = #covered
    if profile.pocketCount >= maximum then return nil end
    local occupied = {}
    for _, region in ipairs(profile.pocketRegions) do occupied[region] = true end
    local available = {}
    local visual = owner:getVisual()
    if not visual then return nil end
    for _, region in ipairs(covered) do
        local part = BloodBodyPartType[region]
        if not occupied[region] and part and visual:getHole(part) == 0 then
            available[#available + 1] = region
        end
    end
    if #available == 0 then return nil end
    return available, profile.pocketCount, maximum
end

local function damageEnabled()
    local options = SandboxVars and SandboxVars.FunctionalPockets
    return options and options.PocketCapacityLossFromHoles == true
end

-- Read actual visual holes; general condition, dirt and blood are not holes.
local function currentCapacity(owner, profile)
    profile = instanceProfile(owner, profile)
    if not damageEnabled() then return profile.capacity, 0 end
    local visual = owner:getVisual()
    return FP.capacityAfterHoles(profile, function(region)
        local part = BloodBodyPartType[region]
        return visual ~= nil and part ~= nil and visual:getHole(part) > 0
    end)
end

local function setCapacity(owner, pocket, capacity)
    local rounded = math.ceil(capacity)
    if owner:getCapacity() ~= rounded then owner:setCapacity(rounded) end
    if pocket:getCapacity() ~= rounded then pocket:setCapacity(rounded) end
end

-- Initialize newly created pockets directly, before they enter an inventory.
-- Log the first instance of each type to diagnose native script initialization.
local checkedCreation = {}
function FP.initializePocket(owner)
    if isClient() or isServer() or not owner then return end
    local id = owner:getFullType()
    local profile = converted[id]
    if not profile or not instanceof(owner, "InventoryContainer") then return end
    local pocket = owner:getInventory()
    if not pocket then return end
    local expected = math.ceil(profile.capacity)
    local ownerBefore, pocketBefore = owner:getCapacity(), pocket:getCapacity()
    setCapacity(owner, pocket, expected)
    if not checkedCreation[id] then
        checkedCreation[id] = true
        print("[FunctionalPockets] create " .. id .. " expected=" .. tostring(expected)
            .. " owner=" .. tostring(ownerBefore) .. "->" .. tostring(owner:getCapacity())
            .. " container=" .. tostring(pocketBefore) .. "->" .. tostring(pocket:getCapacity()))
    end
end

-- Update this instance, never the shared item script. A failed world drop is
-- restored and retried later, rather than deliberately deleting an item.
local function updatePocket(owner, square)
    local profile = converted[owner:getFullType()]
    if not profile or not instanceof(owner, "InventoryContainer") then return end
    local pocket = owner:getInventory()
    local capacity, damaged = currentCapacity(owner, profile)
    setCapacity(owner, pocket, capacity)
    if damaged == 0 or not square then return end
    local items = pocket:getItems()
    while items:size() > 0 and (capacity == 0 or pocket:getCapacityWeight() > capacity + 0.0001) do
        local item = items:get(ZombRand(items:size()))
        pocket:Remove(item)
        if items:contains(item) then break end
        if not square:AddWorldInventoryItem(item, 0.5, 0.5, 0) then
            pocket:AddItem(item)
            break
        end
    end
end

-- Only called after the timed action has revalidated its tools and materials.
function FP.addAdditionalPocket(owner)
    local available = FP.additionalPocketOptions(owner)
    if not available then return false end
    local data = owner:getModData()
    local extra = data.FunctionalPocketsExtraRegions or {}
    extra[#extra + 1] = available[ZombRand(#available) + 1]
    data.FunctionalPocketsExtraRegions = extra
    updatePocket(owner, nil)
    return true
end

-- Damage is normally acquired while worn. Scan carried garments (also inside
-- bags) periodically so pre-existing holes and repaired garments are handled.
local function updateInventory(inventory, square)
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            if converted[item:getFullType()] then
                updatePocket(item, square)
            else
                updateInventory(item:getInventory(), square)
            end
        end
    end
end

local playerTicks = {}
local function updatePlayerPockets(player)
    if isClient() or isServer() or not hasConverted then return end
    local num = player:getPlayerNum()
    local ticks = (playerTicks[num] or 29) + 1
    playerTicks[num] = ticks % 30
    if ticks < 30 then return end
    updateInventory(player:getInventory(), player:getCurrentSquare())
end

Events.OnPlayerUpdate.Add(updatePlayerPockets)

-- Small vanilla containers that can realistically fit in garment pockets.
local smallContainers = {
    ["Base.Wallet"] = true,
    ["Base.Wallet_Male"] = true,
    ["Base.Wallet_Female"] = true,
    ["Base.Wallet_Hide"] = true,
    ["Base.DiceBag"] = true,
    ["Base.GemBag"] = true,
    ["Base.SeedBag"] = true,
    ["Base.SeedBag_Farming"] = true,
    ["Base.PencilCase"] = true,
    ["Base.PencilCase_Gaming"] = true,
    ["Base.FirstAidKit_Camping"] = true,
    ["Base.FirstAidKit_Camping_New"] = true,
    ["Base.FirstAidKit_Military"] = true,
}

-- Called by the native container's admission check, not a UI-only restriction.
function FP.acceptItem(container, item)
    local owner = container:getContainingItem()
    local profile = owner and converted[owner:getFullType()]
    if not profile or not item or item == owner then return false end
    if FP.isBulky(item:getType()) then return false end
    local weight = item:getActualWeight()
    if instanceof(item, "InventoryContainer") then
        local id = item:getFullType()
        local keyRing = id == "Base.KeyRing" or string.sub(id, 1, 13) == "Base.KeyRing_"
        if not keyRing and not smallContainers[id] then return false end
        local contents = item:getInventory()
        if not contents then return false end
        local items = contents:getItems()
        for i = 0, items:size() - 1 do
            local inside = items:get(i)
            if instanceof(inside, "InventoryContainer") or FP.isBulky(inside:getType()) then return false end
        end
        weight = weight + contents:getCapacityWeight()
    end
    local capacity = currentCapacity(owner, profile)
    setCapacity(owner, container, capacity)
    return capacity > 0 and weight <= profile.maxItemSize
        and container:getCapacityWeight() + weight <= capacity + 0.0001
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
            -- Capture actual coverage before changing the native item class.
            profile.coveredRegions = {}
            local bloodTypes = script:getBloodClothingType()
            if bloodTypes then
                local parts = BloodClothingType.getCoveredParts(bloodTypes)
                local seen = {}
                if parts then
                    for j = 0, parts:size() - 1 do
                        local region = tostring(parts:get(j))
                        if not seen[region] and BloodBodyPartType[region]
                            and BloodBodyPartType[region] ~= BloodBodyPartType.MAX then
                            seen[region] = true
                            profile.coveredRegions[#profile.coveredRegions + 1] = region
                        end
                    end
                end
            end
            script:setItemType(ItemType.CONTAINER)
            script:DoParam("CanBeEquipped", location)
            script:DoParam("Capacity", tostring(math.max(1, math.ceil(profile.capacity))))
            script:DoParam("WeightReduction", tostring(profile.reduction))
            script:DoParam("MaxItemSize", tostring(profile.maxItemSize))
            script:DoParam("AcceptItemFunction", "FunctionalPockets.acceptItem")
            converted[script:getFullName()] = profile
            -- Preserve existing item creation callbacks from vanilla or other mods.
            local onCreate = script:getLuaCreate()
            if not onCreate or onCreate == "" then
                script:setLuaCreate("FunctionalPockets.initializePocket")
            end
            hasConverted = true
        end
    end
end

Events.OnGameBoot.Add(install)

-- Vanilla corpse loot is generated lazily; OnZombieDead is too early.
local function distributeZombieLoot(roomType, containerType, inventory)
    if isClient() or isServer() or not hasConverted then return end
    local options = SandboxVars and SandboxVars.FunctionalPockets
    local mode = options and options.ZombiePocketLoot
    if not instanceof(inventory, "ItemContainer") then return end
    local body = inventory:getParent()
    if not instanceof(body, "IsoDeadBody") or not body:isZombie()
        or body:isPlayer() or body:getContainer() ~= inventory then return end

    -- Apply holes before redistributing loot, even when vanilla loot mode is selected.
    updateInventory(inventory, body:getSquare())
    if mode ~= 2 and mode ~= 3 and mode ~= 4 then return end
    local pockets, loose = {}, {}
    local items = inventory:getItems()
    local wornItems = body:getWornItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        -- Converted garments are native containers; also check actual worn-item membership.
        local worn = body:isEquippedClothing(item) or (wornItems and wornItems:contains(item))
        if worn and instanceof(item, "InventoryContainer")
            and FP.isPocketContainer(item:getInventory()) then
            pockets[#pockets + 1] = item:getInventory()
        elseif not body:isEquipped(item) and not worn
            and not body:isAttachedItem(item) and not body:isHandItem(item) then
            loose[#loose + 1] = item
        end
    end
    print("[FunctionalPockets] zombie loot: pockets=" .. tostring(#pockets)
        .. " loose=" .. tostring(#loose))

    -- Snapshot before moving items; try every pocket before overflow.
    for _, item in ipairs(loose) do
        local moved = false
        local acceptedByRules = false
        for _, pocket in ipairs(pockets) do
            if FP.acceptItem(pocket, item) then
                acceptedByRules = true
                if pocket:isItemAllowed(item) then
                    inventory:Remove(item)
                    pocket:AddItem(item)
                    if pocket:getItems():contains(item) then
                        moved = true
                        break
                    end
                    inventory:AddItem(item)
                end
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
                -- A missing pocket or a failed native transfer is not confirmed overflow.
                if #pockets > 0 and not acceptedByRules then
                    inventory:Remove(item)
                    print("[FunctionalPockets] zombie overflow deleted: " .. item:getFullType()
                        .. " weight=" .. tostring(item:getActualWeight()))
                else
                    print("[FunctionalPockets] zombie loot retained: " .. item:getFullType()
                        .. (#pockets == 0 and " (no detected pockets)" or " (native admission/transfer failed)"))
                end
            end
        elseif mode == 4 then
            print("[FunctionalPockets] zombie loot stored: " .. item:getFullType())
        end
    end
end

Events.OnFillContainer.Add(distributeZombieLoot)
