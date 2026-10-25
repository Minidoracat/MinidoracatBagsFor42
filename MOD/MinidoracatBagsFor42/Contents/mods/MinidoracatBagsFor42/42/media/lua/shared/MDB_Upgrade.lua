-- 背包升級：容量與負重減輕存在每個背包自己身上（InventoryContainer 存檔會帶 capacity／weightReduction，
-- InventoryContainer.java:70-73），不改物品類型。公式見 AGENTS.md「設計定案」。
MDB = MDB or {}

local DEFAULTS = {
    LockLegacyBags = true,
    MaxTier = 3,
    CapacityStepPercent = 15,
    WeightReductionStep = 5,
    MaxWeightReduction = 95,
    LootMultiplier = 1,
}

-- 沙盒值；SandboxVars 還沒有本 MOD 的表時（例如單機 OnPreDistributionMerge 早於 SandboxOptions.load，
-- IsoWorld.java:1886、:1896）退回 sandbox-options.txt 的預設值。
function MDB.opt(name)
    local o = SandboxVars and SandboxVars.MinidoracatBags
    local v = o and o[name]
    if v == nil then return DEFAULTS[name] end
    return v
end

function MDB.applyTier(bag, tier)
    local md = bag:getModData()
    if md.MDB_cap == nil then
        md.MDB_cap = bag:getCapacity()
        md.MDB_wr = bag:getWeightReduction()
    end
    -- cap(t)=floor(base×(1+step%×t)+0.5)，用整數算避免 1.45 這類小數誤差
    local cap = math.floor((md.MDB_cap * (100 + MDB.opt("CapacityStepPercent") * tier) + 50) / 100)
    -- 物品內容器的實際上限是 50 減背包重量（InventoryContainer.java:79-86），超過只會印警告
    cap = math.min(cap, math.floor(50 - bag:getActualWeight()))
    local wr = math.min(md.MDB_wr + MDB.opt("WeightReductionStep") * tier, MDB.opt("MaxWeightReduction"))
    bag:setCapacity(cap)
    bag:setWeightReduction(wr)
    md.MDB_tier = tier
    -- 客戶端的容量與負重減輕要整件重送才會更新；單機無作用（LuaManager.java:12404-12412、RecipeCodeOnCreate.java:892-894）
    local container = bag:getContainer()
    if isServer() and container then
        sendReplaceItemInContainer(container, bag, bag)
    end
end

local function tierOf(bag)
    return bag:getModData().MDB_tier or 0
end

-- OnTest（item, character）：每個候選輸入都會呼叫（CraftRecipe.java:1010-1030），工具與材料一律放行
local function gate(item, tier)
    if not instanceof(item, "InventoryContainer") then return true end
    return tier <= MDB.opt("MaxTier") and tierOf(item) == tier - 1
end

function MDB.onTestTier1(item, character) return gate(item, 1) end
function MDB.onTestTier2(item, character) return gate(item, 2) end
function MDB.onTestTier3(item, character) return gate(item, 3) end

-- OnCreate（data, character）：只在單機或伺服器執行（ISHandcraftAction.lua:221-234）
function MDB.onUpgrade(data, character)
    local items = data:getAllKeepInputItems()
    for i = 0, items:size() - 1 do
        local bag = items:get(i)
        if instanceof(bag, "InventoryContainer") then
            local tier = tierOf(bag) + 1
            if tier <= MDB.opt("MaxTier") then
                MDB.applyTier(bag, tier)
            end
            return
        end
    end
end
