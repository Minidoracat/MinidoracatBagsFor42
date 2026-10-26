-- 地上背包的右鍵選單：原版「穿上」會因為物品欄放不下而失敗時，才加「穿上（連同內容物）」。
-- 動作與伺服器端驗證在 shared/MDB_FloorWear.lua。
MDB = MDB or {}

-- 和原版搬移一樣用 hasRoomFor 判斷（單機 ISInventoryTransferAction.lua:110；MP 客戶端 isItemTransactionConsistent，
-- LuaManager.java:12139-12143、TransactionManager.java:278-292），未穿時重量是自重加全部內容物（InventoryItem.java:3425-3427）
function MDB.needsFloorWear(chr, item)
    return instanceof(item, "InventoryContainer") and item:getWorldItem() ~= nil and item:canBeEquipped() ~= nil
        and not chr:getInventory():hasRoomFor(chr, item)
end

-- 先走到背包旁邊，照原版穿地上物品的做法（ISInventoryPaneContextMenu.lua:1915-1919）
local function onWear(chr, bag)
    if luautils.walkAdj(chr, bag:getWorldItem():getSquare()) then
        ISTimedActionQueue.add(MDB_WearFromFloor:new(chr, bag))
    end
end

function MDB.onFillFloorWearMenu(player, context, items)
    local chr = getSpecificPlayer(player)
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if MDB.needsFloorWear(chr, item) then
            context:addOption(getText("ContextMenu_MDB_WearWithContents"), chr, onWear, item)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(MDB.onFillFloorWearMenu)
