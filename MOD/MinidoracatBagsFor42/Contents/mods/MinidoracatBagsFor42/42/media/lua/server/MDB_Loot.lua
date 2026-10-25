-- 戰利品：在 OnPreDistributionMerge 直接追加到原版清單（IsoWorld.java:1886 觸發，之後才 ItemPickerJava.Parse，:1901）。
-- 權重是每輪擲骰的百分比（ItemPickerJava.java:2091-2109），乘上沙盒 LootMultiplier；倍率 ≤ 0 不加。
-- 警局放 S.T.A.R.S.（_Navy），軍事與醫療放保護傘（_Olive）；露營用品店不放。
-- 專用伺服器開機時已讀入沙盒（GameServer.java:1481-1488），merge 時就是存檔值（bags-newbags-1025c 實測 ×2）。
-- 單機讀檔時 merge 早於 SandboxOptions.load()（IsoWorld.java:1896），讀到的是 continueLatestSave 先設的預設值：
-- bags-sandbox-sp-1025c 實測新遊戲 ×2、讀同一存檔變 ×1。所以單機在 OnInitGlobalModData 用存檔值重算一次
-- （IsoWorld.java:2009 GlobalModData.init → GlobalModData.java:54；在 load、toLua（SandboxOptions.java:966-981）之後，
-- 載入 chunk（IsoWorld.java:2188）之前），有改才重跑 ItemPickerJava.Parse()（先清空再重建，ItemPickerJava.java:137-143）。
MDB = MDB or {}

local LOOT = {
    { "PoliceStorageArmor", "_Navy", { "DayPack", 1, "CourierSatchel", 1, "ScoutChestRig", 1, "ToolBeltPouch", 1.5, "AmmoBandolier", 1, "MedicHipPouch", 0.5, "ExpeditionPack", 0.3 } },
    { "PoliceStorageGuns", "_Navy", { "AmmoBandolier", 3, "ScoutChestRig", 1.5, "ToolBeltPouch", 1.5, "DayPack", 1, "CourierSatchel", 1, "ExpeditionPack", 0.2 } },
    { "PoliceLockers", "_Navy", { "ToolBeltPouch", 1.5, "MedicHipPouch", 0.2, "CourierSatchel", 0.2, "DayPack", 0.2, "ScoutChestRig", 0.2, "AmmoBandolier", 0.2, "ExpeditionPack", 0.05 } },
    { "PoliceStorageOutfit", "_Navy", { "DayPack", 0.1, "CourierSatchel", 0.1, "ToolBeltPouch", 0.2 } },
    { "ArmySurplusBackpacks", "_Olive", { "DayPack", 10, "CourierSatchel", 10, "ScoutChestRig", 6, "ToolBeltPouch", 6, "MedicHipPouch", 6, "AmmoBandolier", 4, "ExpeditionPack", 4 } },
    { "ArmyStorageOutfit", "_Olive", { "DayPack", 0.3, "CourierSatchel", 0.3, "ToolBeltPouch", 0.3, "ScoutChestRig", 0.2, "AmmoBandolier", 0.2, "MedicHipPouch", 0.1, "ExpeditionPack", 0.05 } },
    { "LockerArmyBedroom", "_Olive", { "DayPack", 0.1, "ScoutChestRig", 0.1, "CourierSatchel", 0.1, "ExpeditionPack", 0.03 } },
    { "ArmyBunkerLockers", "_Olive", { "DayPack", 0.03, "ScoutChestRig", 0.02, "ExpeditionPack", 0.01 } },
    { "ArmyStorageMedical", "_Olive", { "MedicHipPouch", 0.3 } },
    { "HospitalLockers", "_Olive", { "MedicHipPouch", 1, "DayPack", 0.2, "CourierSatchel", 0.1 } },
    { "HospitalRoomShelves", "_Olive", { "MedicHipPouch", 0.5 } },
    { "NurseOutfit", "_Olive", { "MedicHipPouch", 1 } },
}

local PREFIX = "MinidoracatBags."

-- 把清單裡本 MOD 的條目設成「基礎權重 × mult」（mult ≤ 0 就拿掉）；已經一樣就不動。回傳有沒有改。
local function setLoot(mult)
    local changed = false
    for i = 1, #LOOT do
        local entry = LOOT[i]
        local list = ProceduralDistributions.list[entry[1]]
        if list and list.items then
            local items, pairsList = list.items, entry[3]
            local want, wantN = {}, 0
            if mult > 0 then
                for j = 1, #pairsList, 2 do
                    want[PREFIX .. pairsList[j] .. entry[2]] = pairsList[j + 1] * mult
                    wantN = wantN + 1
                end
            end
            local seen, n, same = {}, 0, true
            for k = 1, #items - 1, 2 do
                local name = items[k]
                if type(name) == "string" and name:sub(1, #PREFIX) == PREFIX then
                    if seen[name] or want[name] ~= items[k + 1] then same = false end
                    seen[name], n = true, n + 1
                end
            end
            if not same or n ~= wantN then
                for k = #items - 1, 1, -2 do
                    local name = items[k]
                    if type(name) == "string" and name:sub(1, #PREFIX) == PREFIX then
                        table.remove(items, k + 1)
                        table.remove(items, k)
                    end
                end
                if mult > 0 then
                    for j = 1, #pairsList, 2 do
                        table.insert(items, PREFIX .. pairsList[j] .. entry[2])
                        table.insert(items, pairsList[j + 1] * mult)
                    end
                end
                changed = true
            end
        else
            print("[MinidoracatBagsFor42] loot list not found: " .. entry[1])
        end
    end
    return changed
end

function MDB.addLoot()
    setLoot(MDB.opt("LootMultiplier"))
end

-- 只在單機：MP 的伺服器 merge 時已是存檔值，客戶端不擲戰利品
function MDB.reapplyLoot()
    if isClient() or isServer() then return end
    if setLoot(MDB.opt("LootMultiplier")) then
        print("[MinidoracatBagsFor42] loot reweighted for saved LootMultiplier " .. tostring(MDB.opt("LootMultiplier")))
        ItemPickerJava.Parse()
    end
end

Events.OnPreDistributionMerge.Add(MDB.addLoot)
Events.OnInitGlobalModData.Add(MDB.reapplyLoot)
