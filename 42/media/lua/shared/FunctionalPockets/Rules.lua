FunctionalPockets = FunctionalPockets or {}
local FP = FunctionalPockets

-- Body regions are BloodBodyPartType names, not individual physical pockets.
local waist = {"Torso_Lower", "Groin", "UpperLeg_L", "UpperLeg_R"}
local cargo = {"Torso_Lower", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R"}
local torso = {"Torso_Upper", "Torso_Lower"}
local coat = {"Torso_Upper", "Torso_Lower"}
-- All capacities are combined garment capacities, not individual pockets.
-- Profile fields: capacity, reduction, maxItemSize, pocketCount, pocketRegions.
FP.Rules = {
    profiles = {
        trousers = {2, 30, 0.7, 4, waist}, jeans = {2, 30, 0.7, 4, waist},
        shorts = {1, 25, 0.5, 4, waist}, shirt = {0.5, 20, 0.25, 1, {"Torso_Upper"}},
        hoodie = {2, 30, 0.7, 2, {"Torso_Lower"}}, jacket = {3, 40, 1.0, 4, torso},
        coat = {4, 40, 1.2, 4, coat},
        overalls = {3, 35, 0.9, 5, {"Torso_Upper", "Torso_Lower", "Groin", "UpperLeg_L", "UpperLeg_R"}},
        vest = {1, 25, 0.5, 2, torso}, apron = {0.5, 20, 0.3, 1, {"Torso_Lower"}},
    },
    -- Six and eight pocket trousers share the engine's coarse leg regions.
    cargoPockets = {6, cargo},
    heavyCargoPockets = {8, cargo},
    overrides = {}, -- full item ID -> false or {capacity, reduction, maxItemSize, pocketCount?, pocketRegions?}
    tags = {nopockets = false, pocketless = false, pockets = true, haspockets = true},
    exclusions = {
        "pocketless", "nopockets", "pajama", "pyjama", "leggings", "tights",
        "yoga", "longjohns", "boxing", "swim", "tshirt", "tanktop", "jumper",
        "sweater", "ghillie", "poncho", "jersey", "vestdefault", "underpants",
        "bulletproof", "catcher", "hazmat", "costume", "cropTop", "sportsbra",
        "highvisibility", "reflectivevest", "shellsuit", "cheerleader",
    },
    -- First match wins. More specific garment names precede general ones.
    inclusions = {
        {"dungarees", "overalls"}, {"overalls", "overalls"},
        {"boilersuit", "overalls"}, {"coveralls", "overalls"},
        {"hoodie", "hoodie"}, {"shortsleeve", "shirt"}, {"shorts", "shorts"}, {"jean", "jeans"},
        {"trousersmeshdenim", "jeans"}, {"trousersdenim", "jeans"},
        {"trousers", "trousers"}, {"pants", "trousers"},
        {"waistcoat", "vest"}, {"jacketlong", "coat"}, {"longjacket", "coat"}, {"coat", "coat"},
        {"jacket", "jacket"}, {"vest", "vest"},
        {"apron", "apron"}, {"shirt", "shirt"},
    },
    -- One modifier only. Order resolves overlapping keywords deterministically.
    modifiers = {
        {"swat", 2, 10}, {"tactical", 2, 10}, {"cargo", 2, 10},
        {"hunting", 2, 0}, {"skinny", 0.5, 0}, {"prisonguard", 1.5, 5},
        {"fireman", 1.5, 5}, {"workman", 1.5, 5}, {"military", 1.5, 5},
        {"army", 1.5, 5}, {"police", 1.5, 5}, {"ranger", 1.5, 5},
        {"camo", 1.5, 5}, {"baggy", 1.25, 0}, {"sport", 0.5, 0},
    },
    locations = {
        pants = "trousers", pantsskinny = "jeans", shortpants = "shorts",
        shortsshort = "shorts", jacket = "jacket", jacketbulky = "jacket",
        jacketsuit = "jacket", shirt = "shirt", shortsleeveshirt = "shirt",
        boilersuit = "overalls",
    },
    bulky = {"sledgehammer", "baseballbat", "crowbar", "plank", "log", "mattress",
        "pillow", "umbrella", "rifle", "shotgun", "guitar", "broom", "fishingrod",
        "shovel", "poolcue", "spear", "fryingpan", "saucepan", "bucket"},
}

local R = FP.Rules
local function normalize(value)
    return (string.lower(tostring(value or "")):gsub("[^%w]", ""))
end
local function localName(value)
    return normalize(tostring(value or ""):match("[^:]+$") or "")
end
local function contains(name, word)
    return string.find(name, normalize(word), 1, true) ~= nil
end
local function result(profile, multiplier, bonus, pocketCount, pocketRegions)
    return {capacity = profile[1] * (multiplier or 1),
        reduction = math.min(100, profile[2] + (bonus or 0)), maxItemSize = profile[3],
        pocketCount = pocketCount or profile[4], pocketRegions = pocketRegions or profile[5]}
end

-- Use original capacity every time; repairing a hole restores its share.
-- A body region can cost at most one pocket, even if listed twice.
function FP.capacityAfterHoles(profile, hasHole)
    local count = profile.pocketCount
    if not count or count <= 0 then return math.ceil(profile.capacity), 0 end
    local damaged, seen = 0, {}
    for _, region in ipairs(profile.pocketRegions or {}) do
        if not seen[region] then
            seen[region] = true
            if hasHole(region) then damaged = damaged + 1 end
        end
    end
    damaged = math.min(count, damaged)
    return math.ceil(profile.capacity * (count - damaged) / count), damaged
end

-- Instance profiles preserve the original per-pocket capacity and never mutate
-- the shared classification tables.
function FP.profileWithExtraPockets(profile, extra)
    local regions = {}
    local seen = {}
    for _, region in ipairs(profile.pocketRegions or {}) do
        regions[#regions + 1] = region
        seen[region] = true
    end
    local count = profile.pocketCount
    for _, region in ipairs(extra or {}) do
        if not seen[region] then
            regions[#regions + 1] = region
            seen[region] = true
            count = count + 1
        end
    end
    return {capacity = profile.capacity * count / profile.pocketCount,
        reduction = profile.reduction, maxItemSize = profile.maxItemSize,
        pocketCount = count, pocketRegions = regions}
end

-- Pure classifier; adapters supply actual game metadata. Native storage is a hard guard.
function FP.classify(id, name, location, tags, isClothing, hasStorage)
    if not isClothing or hasStorage or not location or location == "" then return nil end
    local override = R.overrides[id]
    if override ~= nil then
        if override == false then return nil end
        local fallback = R.profiles[R.locations[localName(location)] or "vest"]
        return result(override, nil, nil, override[4] or fallback[4], override[5] or fallback[5])
    end
    name = normalize(name)
    location = localName(location)
    local tagged = false
    for _, tag in ipairs(tags or {}) do
        local rule = R.tags[localName(tag)]
        if rule == false then return nil end
        if rule == true then tagged = true end
    end
    if not tagged then
        for _, word in ipairs(R.exclusions) do
            if contains(name, word) then return nil end
        end
        if location == "tshirt" or location == "tanktop" or location == "sweater"
            or location == "torsoextravestbullet" then return nil end
    end
    local category
    for _, rule in ipairs(R.inclusions) do
        if contains(name, rule[1]) then category = rule[2]; break end
    end
    -- Generic vests and aprons get no fallback on ambiguous torso-extra slots.
    category = category or R.locations[location] or (tagged and "vest" or nil)
    if not category then return nil end
    if category == "vest" then
        if contains(name, "swat") or contains(name, "tactical") then return result({5, 50, 1.2, 8, torso}) end
        if contains(name, "hunting") then return result({4, 40, 1.0, 6, torso}) end
    end
    local multiplier, bonus = 1, 0
    for _, rule in ipairs(R.modifiers) do
        if contains(name, rule[1]) then multiplier, bonus = rule[2], rule[3]; break end
    end
    if location == "pantsskinny" and multiplier == 1 then multiplier = 0.5 end
    local pockets
    if category == "trousers" or category == "jeans" then
        if contains(name, "heavycargo") or contains(name, "cargoheavy") or contains(name, "8pocket") or contains(name, "eightpocket") then
            pockets = R.heavyCargoPockets
        elseif contains(name, "cargo") or contains(name, "tactical") or contains(name, "swat") then
            pockets = R.cargoPockets
        end
    end
    if pockets then return result(R.profiles[category], multiplier, bonus, pockets[1], pockets[2]) end
    return result(R.profiles[category], multiplier, bonus)
end

function FP.isBulky(name)
    name = normalize(name)
    for _, word in ipairs(R.bulky) do
        if contains(name, word) then return true end
    end
    return false
end

-- Public startup registration API. Existing Rules tables remain compatible.
FP.API = FP.API or {}
local API = FP.API
API.version = 1
local stats = {}

local function nonempty(value)
    assert(type(value) == "string" and normalize(value) ~= "", "Expected a nonempty name")
    return value
end

local function itemID(id)
    assert(type(id) == "string" and id:match("^[^%.]+%.[^%.]+$"), "Expected Module.Item full ID")
    return id
end

local function numberIn(value, minimum, maximum)
    assert(type(value) == "number" and value >= minimum and value <= maximum
        and value < math.huge, "Invalid pocket number")
    return value
end

local function profileData(profile)
    assert(type(profile) == "table", "Expected a pocket profile")
    local capacity = numberIn(profile.capacity, 0.000001, math.huge)
    local reduction = numberIn(profile.reduction, 0, 100)
    local size = numberIn(profile.maxItemSize, 0.000001, math.huge)
    local count = numberIn(profile.pocketCount, 1, math.huge)
    assert(count == math.floor(count), "Expected an integer pocket count")
    assert(type(profile.pocketRegions) == "table", "Expected pocket regions")
    local regions = {}
    for i, region in ipairs(profile.pocketRegions) do
        regions[i] = nonempty(region)
    end
    return {capacity, reduction, size, count, regions}
end

local function namedProfile(name)
    assert(type(name) == "string" and R.profiles[name], "Unknown pocket profile")
    return R.profiles[name]
end

function API.registerProfile(name, profile)
    nonempty(name)
    R.profiles[name] = profileData(profile)
end

function API.registerItem(id, profile)
    itemID(id)
    local data = type(profile) == "string" and namedProfile(profile) or profileData(profile)
    local regions = {}
    for i, region in ipairs(data[5]) do regions[i] = region end
    R.overrides[id] = {data[1], data[2], data[3], data[4], regions}
    stats[id] = nil
end

function API.excludeItem(id)
    R.overrides[itemID(id)] = false
    stats[id] = nil
end

-- Override stats of an otherwise eligible item without forcing eligibility.
function API.overrideStats(id, capacity, reduction)
    itemID(id)
    assert(capacity ~= nil or reduction ~= nil, "Expected at least one override")
    if capacity ~= nil then numberIn(capacity, 0.000001, math.huge) end
    if reduction ~= nil then numberIn(reduction, 0, 100) end
    stats[id] = {capacity = capacity, reduction = reduction}
end

function API.registerInclusionKeyword(keyword, profile)
    nonempty(keyword)
    namedProfile(profile)
    table.insert(R.inclusions, 1, {normalize(keyword), profile})
end

function API.registerExclusionKeyword(keyword)
    R.exclusions[#R.exclusions + 1] = normalize(nonempty(keyword))
end

-- Maps an existing game/mod body location; does not create an engine slot.
function API.registerBodyLocation(location, profile)
    nonempty(location)
    namedProfile(profile)
    R.locations[localName(location)] = profile
end

function API.registerBulkyKeyword(keyword)
    R.bulky[#R.bulky + 1] = normalize(nonempty(keyword))
end

local classify = FP.classify
function FP.classify(id, name, location, tags, isClothing, hasStorage)
    local profile = classify(id, name, location, tags, isClothing, hasStorage)
    local override = stats[id]
    if profile and override then
        profile.capacity = override.capacity or profile.capacity
        profile.reduction = override.reduction or profile.reduction
    end
    return profile
end
