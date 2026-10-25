-- 殭屍死亡掉落：每隻殭屍死亡時執行一次，不掛每次殭屍更新的事件。
-- OnZombieDead 在 DoZombieInventory() 之後觸發（IsoZombie.java:5405-5409），屍體接手這份 inventory（IsoDeadBody.java:324-339），
-- 所以直接加進 zombie:getInventory() 不會被清掉。只在單機或伺服器執行，客戶端直接 return。
-- 服裝名稱出自原版 media/clothing/clothing.xml 的 <m_Name>。
MDB = MDB or {}

local OUTFITS = {
    Police = "_Navy", PoliceRiot = "_Navy", PoliceState = "_Navy", Police_SWAT = "_Navy", Sheriff_Deputy = "_Navy",
    ArmyCamoDesert = "_Olive", ArmyCamoGreen = "_Olive", ArmyInstructor = "_Olive", ArmyServiceUniform = "_Olive",
    Doctor = "medic", Nurse = "medic", AmbulanceDriver = "medic",
}
local MODELS = { "ToolBeltPouch", "MedicHipPouch", "AmmoBandolier", "CourierSatchel", "DayPack", "ExpeditionPack", "ScoutChestRig" }
local CHANCE_BP = 300 -- 每萬分之 300＝3%，再乘 LootMultiplier

function MDB.onZombieDead(zombie)
    if isClient() then return end
    local kind = OUTFITS[zombie:getOutfitName()]
    if not kind then return end
    if ZombRand(10000) >= CHANCE_BP * MDB.opt("LootMultiplier") then return end
    local name
    if kind == "medic" then
        name = "MinidoracatBags.MedicHipPouch_Olive"
    else
        name = "MinidoracatBags." .. MODELS[ZombRand(#MODELS) + 1] .. kind
    end
    zombie:getInventory():AddItem(name)
end

Events.OnZombieDead.Add(MDB.onZombieDead)
