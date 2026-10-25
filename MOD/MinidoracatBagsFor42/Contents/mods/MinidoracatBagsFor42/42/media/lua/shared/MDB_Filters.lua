-- 放入限制（AcceptItemFunction，簽名 (container, item)）。函式名解析不到時容器會照收任何物品
-- （ItemContainer.java:296-304），名稱由 scripts/test_newbags.lua 檢查。
MDB = MDB or {}

-- 醫療腰包：只收急救類（繃帶、消毒水、藥品）
function MDB.acceptFirstAid(container, item)
    return item:getDisplayCategory() == "FirstAid"
end

-- 彈藥背帶：散裝子彈與霰彈都帶 base:ammo，彈藥盒、彈藥箱沒有（normal.txt）；寫法同原版 AcceptItemFunction.lua:19-21
function MDB.acceptAmmo(container, item)
    return item:hasTag(ItemTag.AMMO)
end
