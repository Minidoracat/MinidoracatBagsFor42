-- 舊 Bag Upgrade Plus 背包外殼的放入鎖與改裝配方（MDB_Legacy.txt、MDB_Convert.txt）。
-- MDB.opt、MDB.applyTier 在 MDB_Upgrade.lua；這裡只在呼叫時用到，不受載入順序影響。
MDB = MDB or {}

-- AcceptItemFunction（ItemContainer.isItemAllowed，ItemContainer.java:296-304）：
-- LockLegacyBags 明確為 false 才放行；讀不到沙盒時 MDB.opt 退回預設 true，也就是鎖住。
function MDB.acceptLegacy(container, item)
    return MDB.opt("LockLegacyBags") == false
end

-- 改裝配方 OnCreate（只在單機或伺服器執行，ISHandcraftAction.lua:221-234）：產出直接給最高階。
function MDB.onConvert(data, character)
    local created = data:getAllCreatedItems()
    if created:size() == 0 then return end
    MDB.applyTier(created:get(0), MDB.opt("MaxTier"))
end
