-- 背包升級：容量與負重減輕存在每個背包自己身上（InventoryContainer 存檔會帶 capacity／weightReduction，
-- InventoryContainer.java:70-73），不改物品類型。公式見 AGENTS.md「設計定案」。
MDB = MDB or {}

local DEFAULTS = {
    LockLegacyBags = true,
    MaxTier = 3,
    CapacityStepPercent = 34,
    WeightReductionStep = 10,
    MaxWeightReduction = 100,
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
    -- 上限＝50 減背包自重：腳本載入與 tooltip 都壓在這裡（Item.java:2493-2499、InventoryContainer.java:125-131），
    -- 原本的 Plus 背包就是 49。自重取腳本值（Item.java:533）：伺服器上 getActualWeight() 會回 0（顯示名稱等於全名時，InventoryItem.java:2740-2742）
    local top = math.floor(50 - bag:getScriptItem():getActualWeight())
    -- 每階補上「原本容量到上限」差距的 CapacityStepPercent%，預設 34 時第 3 階補滿（使用者 2026-10-26：升滿要和 Bag Upgrade Plus 一樣）
    local fill = math.min(100, MDB.opt("CapacityStepPercent") * tier)
    local cap = md.MDB_cap + math.floor((math.max(top - md.MDB_cap, 0) * fill + 50) / 100)
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
