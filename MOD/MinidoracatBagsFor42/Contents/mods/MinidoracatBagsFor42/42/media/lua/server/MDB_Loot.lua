-- 戰利品：在 OnPreDistributionMerge 直接追加到原版清單（IsoWorld.java:1886 觸發，之後才 ItemPickerJava.Parse，:1901）。
-- 權重是每輪擲骰的百分比（ItemPickerJava.java:2091-2109），乘上沙盒 LootMultiplier；倍率 ≤ 0 不加。
-- 警局放 S.T.A.R.S.（_Navy），軍事與醫療放保護傘（_Olive）；露營用品店不放。
-- 注意：專用伺服器開機時已讀入沙盒（GameServer.java:1481-1488）；單機與主機模式的 SandboxOptions.load()
-- 在這個事件之後（IsoWorld.java:1896），這時讀到的 LootMultiplier 可能是預設值而不是存檔值。[INFERENCE，未實測]
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

function MDB.addLoot()
    local mult = MDB.opt("LootMultiplier")
    if mult <= 0 then return end
    for i = 1, #LOOT do
        local entry = LOOT[i]
        local list = ProceduralDistributions.list[entry[1]]
        if list and list.items then
            local pairsList = entry[3]
            for j = 1, #pairsList, 2 do
                table.insert(list.items, "MinidoracatBags." .. pairsList[j] .. entry[2])
                table.insert(list.items, pairsList[j + 1] * mult)
            end
        else
            print("[MinidoracatBagsFor42] loot list not found: " .. entry[1])
        end
    end
end

Events.OnPreDistributionMerge.Add(MDB.addLoot)
