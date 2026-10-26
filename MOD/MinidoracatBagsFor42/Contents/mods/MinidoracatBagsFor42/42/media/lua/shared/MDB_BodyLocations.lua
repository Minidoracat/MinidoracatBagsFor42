-- 第二個側背包位置（registries.lua 註冊）加進人物的穿戴位置群組。
-- 沒加進群組就穿，BodyLocationGroup.isMultiItem 會空指標錯誤（BodyLocationGroup.java:116-119）。
-- 群組在重載 Lua 前被清空（Core.java:3896），原版 NPCs/BodyLocations.lua 載入時重建，所以這裡每次載入都接在它後面加；
-- 不 reset、不重建整個群組，原版與其他 MOD 的位置與規則都不動。
-- 位置在群組裡的順序就是繪製順序（WornItems.java:68-81），排在原版側背包（base:satchel）後面，兩個側背包畫的層次相同。
-- 原版側背包沒有任何互斥或隱藏規則（BodyLocations.lua:104 只加進群組），這個位置也不設，和原版側背包一樣。
require "NPCs/BodyLocations"
require "TimedActions/ISWearClothing"
MDB = MDB or {}

MDB.SATCHEL2_ID = "minidoracatbags:satchel2"

function MDB.addSatchel2Location()
    local loc = ItemBodyLocation.get(ResourceLocation.of(MDB.SATCHEL2_ID))
    if not loc then
        -- registries.lua 沒跑到時不能傳 nil：getOrCreateLocation(nil) 會建出 id 為 null 的位置，之後比對時空指標錯誤
        print("[MinidoracatBagsFor42] ERROR body location " .. MDB.SATCHEL2_ID .. " is not registered")
        return
    end
    local group = BodyLocations.getGroup("Human")
    group:getOrCreateLocation(loc)   -- 先接在最後（BodyLocationGroup.java:39-45）
    local satchel = group:indexOf(ItemBodyLocation.SATCHEL)
    if satchel >= 0 then
        group:moveLocationToIndex(loc, satchel + 1)   -- 再移到原版側背包後面（:53-62）
    end
    -- 原版側背包可以邊走邊穿脫（ISWearClothing.lua:176-215），第二個位置照辦
    table.insert(ISWearClothing.WalkBodyLocations, loc)
end

MDB.addSatchel2Location()
