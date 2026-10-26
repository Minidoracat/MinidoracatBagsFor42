-- 背包升級：容量與負重減輕存在每個背包自己身上（InventoryContainer 存檔會帶 capacity／weightReduction，
-- InventoryContainer.java:70-73）。下表的背包第一次升級時先換成強化版再套階級；公式見 AGENTS.md「設計定案」。
MDB = MDB or {}

-- 有強化版的背包＝升級配方清單裡的全部背包（使用者 2026-10-26 第二批決定）。
-- 強化版 MinidoracatBags.<物品名>_Reinforced：自重 0.1、不減速、側背包改穿第二個側背包位置，其餘欄位照來源。
-- scripts/gen_reinforced.py 讀這張表產生物品腳本、外觀、16 語名稱與配方清單；要加款式只加這裡再跑產生器。
-- 來源的 ClothingItemExtra（換穿法）目標也要在表裡，強化版才能互換。
MDB.REINFORCED_SOURCES = {
    -- 原版：升級配方清單裡全部的原版容器（可穿戴、沒有 AcceptItemFunction）
    "Base.Bag_ALICE_BeltSus", "Base.Bag_ALICE_BeltSus_Camo", "Base.Bag_ALICE_BeltSus_Green", "Base.Bag_ALICEpack",
    "Base.Bag_ALICEpack_Army", "Base.Bag_ALICEpack_DesertCamo", "Base.Bag_BaseballBag", "Base.Bag_BigHikingBag",
    "Base.Bag_BigHikingBag_Travel", "Base.Bag_BreakdownBag", "Base.Bag_BurglarBag", "Base.Bag_ChestRig",
    "Base.Bag_ChestRig_Tarp", "Base.Bag_ClothSatchel_Burlap", "Base.Bag_ClothSatchel_Cotton",
    "Base.Bag_ClothSatchel_Denim", "Base.Bag_ClothSatchel_DenimBlack", "Base.Bag_ClothSatchel_DenimLight",
    "Base.Bag_CraftedFramepack_Large", "Base.Bag_CraftedFramepack_Large2", "Base.Bag_CraftedFramepack_Large3",
    "Base.Bag_CraftedFramepack_Small", "Base.Bag_CrudeLeatherBag", "Base.Bag_CrudeTarpBag", "Base.Bag_DuffelBag",
    "Base.Bag_DuffelBagTINT", "Base.Bag_FannyPackBack", "Base.Bag_FannyPackBack_Hide", "Base.Bag_FannyPackBack_Tarp",
    "Base.Bag_FannyPackFront", "Base.Bag_FannyPackFront_Hide", "Base.Bag_FannyPackFront_Tarp",
    "Base.Bag_FishingBasket", "Base.Bag_FoodCanned", "Base.Bag_FoodSnacks", "Base.Bag_GolfBag",
    "Base.Bag_GolfBag_Melee", "Base.Bag_HideSatchel", "Base.Bag_HideSlingBag", "Base.Bag_HikingBag_Travel",
    "Base.Bag_HydrationBackpack", "Base.Bag_HydrationBackpack_Camo", "Base.Bag_InmateEscapedBag",
    "Base.Bag_MedicalBag", "Base.Bag_Military", "Base.Bag_MoneyBag", "Base.Bag_NormalHikingBag", "Base.Bag_Police",
    "Base.Bag_RifleCaseCloth", "Base.Bag_RifleCaseCloth2", "Base.Bag_RifleCaseClothCamo", "Base.Bag_SWAT",
    "Base.Bag_Satchel", "Base.Bag_SatchelPhoto", "Base.Bag_Satchel_Fishing", "Base.Bag_Satchel_Leather",
    "Base.Bag_Satchel_Mail", "Base.Bag_Satchel_Medical", "Base.Bag_Satchel_Military", "Base.Bag_Schoolbag",
    "Base.Bag_Schoolbag_Kids", "Base.Bag_Schoolbag_Medical", "Base.Bag_Schoolbag_Patches",
    "Base.Bag_Schoolbag_Travel", "Base.Bag_SheetSlingBag", "Base.Bag_Sheriff", "Base.Bag_ShotgunBag",
    "Base.Bag_ShotgunCaseCloth", "Base.Bag_ShotgunCaseCloth2", "Base.Bag_ShotgunDblBag",
    "Base.Bag_ShotgunDblSawnoffBag", "Base.Bag_ShotgunSawnoffBag", "Base.Bag_SurvivorBag",
    "Base.Bag_TarpFramepack_Large", "Base.Bag_TarpFramepack_Small", "Base.Bag_TarpSlingBag", "Base.Bag_TennisBag",
    "Base.Bag_ToolBag", "Base.Bag_WeaponBag", "Base.Bag_WorkerBag",
    -- 本 MOD（腰包的換穿變體和原款互指 ClothingItemExtra，要一起在表裡）
    "MinidoracatBags.ToolBeltPouch_Navy", "MinidoracatBags.ToolBeltPouch_Olive", "MinidoracatBags.MedicHipPouch_Navy",
    "MinidoracatBags.MedicHipPouch_Olive", "MinidoracatBags.ToolBeltPouchBack_Navy", "MinidoracatBags.ToolBeltPouchBack_Olive",
    "MinidoracatBags.MedicHipPouchFront_Navy", "MinidoracatBags.MedicHipPouchFront_Olive", "MinidoracatBags.AmmoBandolier_Navy",
    "MinidoracatBags.AmmoBandolier_Olive", "MinidoracatBags.CourierSatchel_Navy",
    "MinidoracatBags.CourierSatchel_Olive", "MinidoracatBags.DayPack_Navy", "MinidoracatBags.DayPack_Olive",
    "MinidoracatBags.ExpeditionPack_Navy", "MinidoracatBags.ExpeditionPack_Olive",
    "MinidoracatBags.ScoutChestRig_Navy", "MinidoracatBags.ScoutChestRig_Olive",
}
MDB.REINFORCED, MDB.ORIGINAL = {}, {}   -- 來源全名 → 強化版全名；反查
for _, ft in ipairs(MDB.REINFORCED_SOURCES) do
    local r = "MinidoracatBags." .. ft:match("[^.]+$") .. "_Reinforced"
    MDB.REINFORCED[ft] = r
    MDB.ORIGINAL[r] = ft
end

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

-- 換型途中為 true：applyTier 不重送，最後由 swapBag 送一次
local swapping = false

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
    if isServer() and container and not swapping then
        sendReplaceItemInContainer(container, bag, bag)
    end
end

-- 換成另一種背包（升級換成強化版、還原、舊 Plus 改裝），再套 tier。
-- copyClothingItem 搬內容物（同一批物件，ID 不變）、外觀、改名、顏色、耐久、最愛、液體與 modData（ISClothingExtraAction.lua:62-112）。
-- 新背包先放進同一個容器再搬：中途出錯時內容物分在兩個背包裡，不會落在沒有容器的物品上。
-- 伺服器最後只送一次 replace：客戶端依舊 ID 移除、加入整件新背包，並換掉動作佇列裡的舊參照
-- （ReplaceInventoryItemInContainerPacket.java:57-82）；單機改呼叫 replaceItemInContainer 換動作佇列（LuaManager.java:12442-12449）。
function MDB.swapBag(old, newType, tier, character)
    local cont = old:getContainer()
    local new = instanceItem(newType)
    cont:AddItem(new)
    swapping = true
    local ok, err = pcall(function()
        copyClothingItem(old, new)
        -- copyClothingItem 拿 getName() 比對腳本名稱，染血、磨損的前綴或水袋的液體名稱也會被當成改名寫進新背包
        -- （InventoryItem.java:2435-2480），名稱不同就跟著存檔（:1711）。只有玩家改過名才沿用原名（ISInventoryPaneContextMenu.lua:2741-2750）
        if old:isCustomName() then
            new:setName(old:getDisplayName())
            new:setCustomName(true)
        else
            new:setName(new:getScriptItem():getDisplayName())
        end
        MDB.applyTier(new, tier)
        -- copyClothingItem 搬液體時新背包還是腳本容量，多的被截掉（FluidContainer.java:179-194、:929-932）；容量設好後再搬一次
        local ofc, nfc = old:getFluidContainer(), new:getFluidContainer()
        if ofc and nfc then nfc:copyFluidsFrom(ofc) end
    end)
    swapping = false
    if not ok then error(err) end
    cont:Remove(old)   -- 也會把它從手上拿掉（ItemContainer.java:2036-2039）
    if isServer() then
        sendReplaceItemInContainer(cont, old, new)
    elseif character and cont == character:getInventory() then
        replaceItemInContainer(cont, old, new)   -- 會把容器的 parent 轉成 IsoPlayer，只能用在主物品欄
    end
    return new
end

local function tierOf(bag)
    return bag:getModData().MDB_tier or 0
end

-- 配方的 keep 輸入裡第一個背包（不是 CanBeDoneFromFloor 的配方，輸入開工前都搬進主物品欄，ISWidgetHandCraftControl.lua:342-351）
function MDB.keepBag(data)
    local items = data:getAllKeepInputItems()
    for i = 0, items:size() - 1 do
        if instanceof(items:get(i), "InventoryContainer") then return items:get(i) end
    end
end

-- 還原（強化版→原版）與 0.1.0 升過級的原版背包改成強化版：只換型，階級照舊
function MDB.onSwapKeepTier(data, character)
    local bag = MDB.keepBag(data)
    if not bag then return end
    local ft = bag:getFullType()
    MDB.swapBag(bag, MDB.ORIGINAL[ft] or MDB.REINFORCED[ft], tierOf(bag), character)
end

-- 已升級原版背包改成強化版：只放行第 1 階以上的背包，第 0 階要走升級（不然免費拿到自重 0.1）
function MDB.onTestUpgraded(item, character)
    return not instanceof(item, "InventoryContainer") or tierOf(item) >= 1
end

-- OnTest（item, character）：每個候選輸入都會呼叫（CraftRecipe.java:1010-1030），工具與材料一律放行
local function gate(item, tier)
    if not instanceof(item, "InventoryContainer") then return true end
    return tier <= MDB.opt("MaxTier") and tierOf(item) == tier - 1
end

function MDB.onTestTier1(item, character) return gate(item, 1) end
function MDB.onTestTier2(item, character) return gate(item, 2) end
function MDB.onTestTier3(item, character) return gate(item, 3) end

-- OnCreate（data, character）：只在單機或伺服器執行（ISHandcraftAction.lua:221-234）。
-- 有強化版的原版背包先換成強化版再套新階級
function MDB.onUpgrade(data, character)
    local bag = MDB.keepBag(data)
    if not bag then return end
    local tier = tierOf(bag) + 1
    if tier > MDB.opt("MaxTier") then return end
    local target = MDB.REINFORCED[bag:getFullType()]
    if target then
        MDB.swapBag(bag, target, tier, character)
    else
        MDB.applyTier(bag, tier)
    end
end

-- 換穿法（腰包前背↔後背）換成另一個物品：原版 createItemNew 搬了 modData，沒搬容量與負重減輕
-- （ISClothingExtraAction.lua:66-112），換完回到腳本預設、MDB_tier 卻還在，就升不回來了。這裡依 MDB_tier 重算。
-- 同一個函式也是 copyClothingItem（:62-64，InventoryItem.java:5029-5036）與背負噴霧器換物（ISEquipWeaponAction.lua:152）的路徑。
-- MP 的 complete() 在伺服器跑（NetTimedAction.java:132-139；客戶端不跑，LuaTimedActionNew.java:164-170）。
-- 新物品這時還沒放進容器，applyTier 不重送；接著 sendAddItemToContainer 整件送出，負重減輕與容量都在裡面
-- （AddInventoryItemToContainerPacket.java:54-58、InventoryContainer.java:57-58、ItemContainer.java:2439）。
-- MDB.swapBag 呼叫 copyClothingItem 時新背包已在容器裡，由 swapping 擋下這次重送。
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
