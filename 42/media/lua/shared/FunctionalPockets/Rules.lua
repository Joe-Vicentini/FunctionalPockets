FunctionalPockets = FunctionalPockets or {}
local FP = FunctionalPockets

-- All capacities are combined garment capacities, not individual pockets.
FP.Rules = {
    profiles = {
        trousers = {2, 30, 0.7}, jeans = {2, 30, 0.7},
        shorts = {1, 25, 0.5}, shirt = {0.5, 20, 0.25},
        hoodie = {2, 30, 0.7}, jacket = {3, 40, 1.0},
        coat = {4, 40, 1.2}, overalls = {3, 35, 0.9},
        vest = {1, 25, 0.5}, apron = {0.5, 20, 0.3},
    },
    overrides = {}, -- full item ID -> false or {capacity, reduction, maxItemSize}
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
local function result(profile, multiplier, bonus)
    return {capacity = profile[1] * (multiplier or 1),
        reduction = math.min(100, profile[2] + (bonus or 0)), maxItemSize = profile[3]}
end

-- Pure classifier; adapters supply actual game metadata. Native storage is a hard guard.
function FP.classify(id, name, location, tags, isClothing, hasStorage)
    if not isClothing or hasStorage or not location or location == "" then return nil end
    local override = R.overrides[id]
    if override ~= nil then
        if override == false then return nil end
        return result(override)
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
        if contains(name, "swat") or contains(name, "tactical") then return result({5, 50, 1.2}) end
        if contains(name, "hunting") then return result({4, 40, 1.0}) end
    end
    local multiplier, bonus = 1, 0
    for _, rule in ipairs(R.modifiers) do
        if contains(name, rule[1]) then multiplier, bonus = rule[2], rule[3]; break end
    end
    if location == "pantsskinny" and multiplier == 1 then multiplier = 0.5 end
    return result(R.profiles[category], multiplier, bonus)
end

function FP.isBulky(name)
    name = normalize(name)
    for _, word in ipairs(R.bulky) do
        if contains(name, word) then return true end
    end
    return false
end
