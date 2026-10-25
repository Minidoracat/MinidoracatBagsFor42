-- 開機檢查一次：舊 Plus 外殼是否被其他 BUP 版本蓋掉。
-- 同名物品會逐欄位合併（ScriptBucket.java:70-85），modID 記最後定義者（GameEntityScript.java:145-152），
-- 所以比對 modID，並找本 MOD 從不寫的欄位（BodyLocation、ClothingItemExtra）是否被別人帶進來。
MDB = MDB or {}

local MOD_ID = "MinidoracatBagsFor42"

-- 會定義 BagUpgradePlus.* 舊全名的 Workshop 版本（Updated、Realistic、原版與各分支、EFT 相容版、CloudBag）
local BUP_MOD_IDS = { "BagUpgradePlusUpdated", "BagUpgradePlusRealistic", "BagUpgradePlus",
    "BagUpgradePlusEFTCompat", "CloudBag" }

-- MDB_Legacy.txt 的 40 個外殼
local SHELLS = {
    "BagUpgradePlus.ALICEpackPlus", "BagUpgradePlus.ALICEpack_CamoPlus", "BagUpgradePlus.ALICEpack_DesertCamoPlus",
    "BagUpgradePlus.DuffelPlus", "BagUpgradePlus.MedicalPlus", "BagUpgradePlus.MilitaryPlus",
    "BagUpgradePlus.PolicePlus", "BagUpgradePlus.SheriffPlus", "BagUpgradePlus.SWATPlus",
    "BagUpgradePlus.BreakdownBagPlus", "BagUpgradePlus.BurglarBagPlus", "BagUpgradePlus.BaseballBagPlus",
    "BagUpgradePlus.TennisBagPlus", "BagUpgradePlus.WeaponBagPlus", "BagUpgradePlus.InmateEscapedBagPlus",
    "BagUpgradePlus.MoneyBagPlus", "BagUpgradePlus.WorkerBagPlus", "BagUpgradePlus.ShotgunBagPlus",
    "BagUpgradePlus.ShotgunSawnoffBagPlus", "BagUpgradePlus.ShotgunDblBagPlus",
    "BagUpgradePlus.ShotgunDblSawnoffBagPlus", "BagUpgradePlus.FoodCannedPlus", "BagUpgradePlus.FoodSnacksPlus",
    "BagUpgradePlus.ToolBagPlus", "BagUpgradePlus.FannyPackFrontPlus", "BagUpgradePlus.FannyPackBackPlus",
    "BagUpgradePlus.HydrationBackpackPlus", "BagUpgradePlus.HydrationBackpackPlus_Camo",
    "BagUpgradePlus.HikingBagPlus", "BagUpgradePlus.BigHikingBagplus", "BagUpgradePlus.BigHikingBagPlus_Travel",
    "BagUpgradePlus.SchoolbagPlus", "BagUpgradePlus.SatchelPlus", "BagUpgradePlus.Satchel_FishingPlus",
    "BagUpgradePlus.Satchel_MedicalPlus", "BagUpgradePlus.Satchel_MilitaryPlus",
    "Base.SheetSlingBagPlus", "Base.WaterBottleFull", "Base.WaterPopBottle", "ExtraCraft.SheetSlingBagPlus",
}
MDB.LEGACY_SHELLS = SHELLS

function MDB.warnDuplicates()
    local active = {}
    local mods = getActivatedMods()
    for _, id in ipairs(BUP_MOD_IDS) do
        if mods:contains(id) or mods:contains("\\" .. id) then active[#active + 1] = id end
    end
    local bad = {}
    local sm = getScriptManager()
    for _, fullType in ipairs(SHELLS) do
        local s = sm:getItem(fullType)
        if s == nil then
            bad[#bad + 1] = fullType .. "(missing)"
        else
            local extra = s:getClothingItemExtra()
            if s:getModID() ~= MOD_ID then
                bad[#bad + 1] = fullType .. "(modID=" .. tostring(s:getModID()) .. ")"
            elseif s:getBodyLocation() ~= nil or (extra ~= nil and extra:size() > 0) then
                bad[#bad + 1] = fullType .. "(merged)"
            end
        end
    end
    if #active == 0 and #bad == 0 then return end
    local shown = {}
    for i = 1, math.min(#bad, 5) do shown[i] = bad[i] end
    print("[MinidoracatBagsFor42] WARNING: another Bag Upgrade Plus is loaded; disable it. active="
        .. table.concat(active, ",") .. " overridden=" .. #bad .. " " .. table.concat(shown, ","))
end

Events.OnGameBoot.Add(MDB.warnDuplicates)
