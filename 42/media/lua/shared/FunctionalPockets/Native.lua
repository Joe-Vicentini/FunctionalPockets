require "FunctionalPockets/Rules"
local FP = FunctionalPockets

-- Enabled for experimental testing, NOT production gameplay.
-- Use only in a disposable NEW single-player world.
local experimental = true
local converted = {}

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
