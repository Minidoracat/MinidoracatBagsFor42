-- 舊 Bag Upgrade Plus 背包外殼的放入鎖與改裝配方（MDB_Legacy.txt、MDB_Convert.txt）。
-- MDB.opt、MDB.applyTier、MDB.toReinforced、MDB.reinforcedOf 在 MDB_Upgrade.lua；這裡只在呼叫時用到，不受載入順序影響。
MDB = MDB or {}

-- AcceptItemFunction（ItemContainer.isItemAllowed，ItemContainer.java:296-304）：
-- LockLegacyBags 明確為 false 才放行；讀不到沙盒時 MDB.opt 退回預設 true，也就是鎖住。
function MDB.acceptLegacy(container, item)
    return MDB.opt("LockLegacyBags") == false
end

-- 舊背包外殼 → 對應的原版背包（BUP 升級配方的對照表；ALICEpackPlus 對 Bag_ALICEpack）。改裝成它的強化版，主題照外殼的顏色
-- 查原版那張表（外殼 XML 的 textureChoices 和原版同款相同，test_legacy.lua 核對）
MDB.LEGACY_TARGET = {
    ["BagUpgradePlus.ALICEpackPlus"] = "Base.Bag_ALICEpack",
    ["BagUpgradePlus.ALICEpack_CamoPlus"] = "Base.Bag_ALICEpack_Army",
    ["BagUpgradePlus.ALICEpack_DesertCamoPlus"] = "Base.Bag_ALICEpack_DesertCamo",
    ["BagUpgradePlus.DuffelPlus"] = "Base.Bag_DuffelBag",
    ["BagUpgradePlus.MedicalPlus"] = "Base.Bag_MedicalBag",
    ["BagUpgradePlus.MilitaryPlus"] = "Base.Bag_Military",
    ["BagUpgradePlus.PolicePlus"] = "Base.Bag_Police",
    ["BagUpgradePlus.SheriffPlus"] = "Base.Bag_Sheriff",
    ["BagUpgradePlus.SWATPlus"] = "Base.Bag_SWAT",
    ["BagUpgradePlus.BreakdownBagPlus"] = "Base.Bag_BreakdownBag",
    ["BagUpgradePlus.BurglarBagPlus"] = "Base.Bag_BurglarBag",
    ["BagUpgradePlus.BaseballBagPlus"] = "Base.Bag_BaseballBag",
    ["BagUpgradePlus.TennisBagPlus"] = "Base.Bag_TennisBag",
    ["BagUpgradePlus.WeaponBagPlus"] = "Base.Bag_WeaponBag",
    ["BagUpgradePlus.InmateEscapedBagPlus"] = "Base.Bag_InmateEscapedBag",
    ["BagUpgradePlus.MoneyBagPlus"] = "Base.Bag_MoneyBag",
    ["BagUpgradePlus.WorkerBagPlus"] = "Base.Bag_WorkerBag",
    ["BagUpgradePlus.ShotgunBagPlus"] = "Base.Bag_ShotgunBag",
    ["BagUpgradePlus.ShotgunSawnoffBagPlus"] = "Base.Bag_ShotgunSawnoffBag",
    ["BagUpgradePlus.ShotgunDblBagPlus"] = "Base.Bag_ShotgunDblBag",
    ["BagUpgradePlus.ShotgunDblSawnoffBagPlus"] = "Base.Bag_ShotgunDblSawnoffBag",
    ["BagUpgradePlus.FoodCannedPlus"] = "Base.Bag_FoodCanned",
    ["BagUpgradePlus.FoodSnacksPlus"] = "Base.Bag_FoodSnacks",
    ["BagUpgradePlus.ToolBagPlus"] = "Base.Bag_ToolBag",
    ["BagUpgradePlus.FannyPackFrontPlus"] = "Base.Bag_FannyPackFront",
    ["BagUpgradePlus.FannyPackBackPlus"] = "Base.Bag_FannyPackBack",
    ["BagUpgradePlus.HydrationBackpackPlus"] = "Base.Bag_HydrationBackpack",
    ["BagUpgradePlus.HydrationBackpackPlus_Camo"] = "Base.Bag_HydrationBackpack_Camo",
    ["BagUpgradePlus.HikingBagPlus"] = "Base.Bag_NormalHikingBag",
    ["BagUpgradePlus.BigHikingBagplus"] = "Base.Bag_BigHikingBag",
    ["BagUpgradePlus.BigHikingBagPlus_Travel"] = "Base.Bag_HikingBag_Travel",
    ["BagUpgradePlus.SchoolbagPlus"] = "Base.Bag_Schoolbag",
    ["BagUpgradePlus.SatchelPlus"] = "Base.Bag_Satchel",
    ["BagUpgradePlus.Satchel_FishingPlus"] = "Base.Bag_Satchel_Fishing",
    ["BagUpgradePlus.Satchel_MedicalPlus"] = "Base.Bag_Satchel_Medical",
    ["BagUpgradePlus.Satchel_MilitaryPlus"] = "Base.Bag_Satchel_Military",
    ["Base.SheetSlingBagPlus"] = "Base.Bag_SheetSlingBag",
    ["ExtraCraft.SheetSlingBagPlus"] = "Base.Bag_SheetSlingBag",
}

-- 改裝配方 OnCreate（只在單機或伺服器執行，ISHandcraftAction.lua:221-234）：舊背包換成對應原版的強化版、直接給最高階；
-- 內容物、modData、液體（舊水袋 5 升）照 MDB.swapBag 搬過去，原款記成對應的原版（還原時換回它）
function MDB.onConvertLegacy(data, character)
    local bag = MDB.keepBag(data)
    if not bag then return end
    MDB.toReinforced(bag, MDB.LEGACY_TARGET[bag:getFullType()], MDB.opt("MaxTier"), character)
end

-- 強化版布吊帶包直接製作（BUP 的 MakeSheetSlingBagPlus 同材料）：配方 RemoveResultItems 不產出，這裡自己建。
-- 還沒放進容器時套最高階（applyTier 不重送），再放進主物品欄（自重 0.1，超重也不丟地上），伺服器整件送一次
-- （AddInventoryItemToContainerPacket.java:54-58；sendAddItemToContainer 只在伺服器有作用，LuaManager.java:12370-12374）
function MDB.onMakeReinforcedSling(data, character)
    local bag = instanceItem(MDB.reinforcedOf("Base.Bag_SheetSlingBag"))
    MDB.applyTier(bag, MDB.opt("MaxTier"))
    local inv = character:getInventory()
    inv:AddItem(bag)
    sendAddItemToContainer(inv, bag)
end
