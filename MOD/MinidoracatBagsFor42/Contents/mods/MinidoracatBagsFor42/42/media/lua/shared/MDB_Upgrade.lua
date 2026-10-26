-- 背包升級：容量與負重減輕存在每個背包自己身上（InventoryContainer 存檔會帶 capacity／weightReduction，
-- InventoryContainer.java:70-73），不改物品類型。公式見 AGENTS.md「設計定案」。
MDB = MDB or {}

local DEFAULTS = {
    LockLegacyBags = true,
    MaxTier = 3,
    FullCapacityPercent = 100,
    FullWeightReduction = 100,
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

-- Bag Upgrade Plus 水袋的液體容量（使用者 2026-10-26：升滿要和 BUP 一樣）
local FULL_FLUID = 5.0

-- 最高階（MaxTier）升滿，中間各階平均分配；MaxTier 0 維持原值
function MDB.applyTier(bag, tier)
    local md = bag:getModData()
    if md.MDB_cap == nil then
        md.MDB_cap = bag:getCapacity()
        md.MDB_wr = bag:getWeightReduction()
    end
    local maxTier = MDB.opt("MaxTier")
    local t = maxTier > 0 and math.min(tier, maxTier) or 0
    local m = math.max(maxTier, 1)
    local pct = MDB.opt("FullCapacityPercent")
    -- base + round((full - base) * t / m)，round(x) = floor(x + 0.5)；全用整數算，免浮點誤差
    local function step(base, full) return base + math.floor(((full - base) * t * 2 + m) / (2 * m)) end
    -- 上限＝50 減背包自重：腳本載入與 tooltip 都壓在這裡（Item.java:2493-2499、InventoryContainer.java:125-131），
    -- 原本的 Plus 背包就是 49。自重取腳本值（Item.java:533）：伺服器上 getActualWeight() 會回 0（顯示名稱等於全名時，InventoryItem.java:2740-2742）
    local top = math.floor(50 - bag:getScriptItem():getActualWeight())
    local fullCap = md.MDB_cap + math.floor((math.max(top - md.MDB_cap, 0) * pct + 50) / 100)
    bag:setCapacity(step(md.MDB_cap, fullCap))
    bag:setWeightReduction(step(md.MDB_wr, math.max(md.MDB_wr, MDB.opt("FullWeightReduction"))))
    -- 液體容量存在 FluidContainer 元件（GameEntity.java:183、FluidContainer.java:683、存檔 :1202-1205）
    local fc = bag:getFluidContainer()
    if fc then
        if md.MDB_fluid == nil then md.MDB_fluid = fc:getCapacity() end
        local base = md.MDB_fluid
        local full = base + math.max(FULL_FLUID - base, 0) * pct / 100
        fc:setCapacity(base + (full - base) * t / m)
    end
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

-- 換穿法（腰包前背↔後背）換成另一個物品：原版 createItemNew 搬了 modData，沒搬容量與負重減輕
-- （ISClothingExtraAction.lua:66-112），換完回到腳本預設、MDB_tier 卻還在，就升不回來了。這裡依 MDB_tier 重算。
-- 同一個函式也是 copyClothingItem（:62-64，InventoryItem.java:5029-5036）與背負噴霧器換物（ISEquipWeaponAction.lua:152）的路徑。
-- MP 的 complete() 在伺服器跑（NetTimedAction.java:132-139；客戶端不跑，LuaTimedActionNew.java:164-170）。
-- 新物品這時還沒放進容器，applyTier 不重送；接著 sendAddItemToContainer 整件送出，負重減輕與容量都在裡面
-- （AddInventoryItemToContainerPacket.java:54-58、InventoryContainer.java:57-58、ItemContainer.java:2439）。
require "TimedActions/ISClothingExtraAction"
local createItemNew = ISClothingExtraAction.createItemNew
function ISClothingExtraAction:createItemNew(item, newItem)
    local result = createItemNew(self, item, newItem)
    local tier = newItem:hasModData() and newItem:getModData().MDB_tier
    if tier and instanceof(newItem, "InventoryContainer") then
        MDB.applyTier(newItem, tier)
    end
    return result
end
