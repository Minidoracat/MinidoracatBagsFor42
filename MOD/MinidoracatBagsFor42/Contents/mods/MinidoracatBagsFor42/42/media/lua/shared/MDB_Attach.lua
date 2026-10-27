-- 強化版背包的額外快捷列掛點（Bag Upgrade Plus 的 AlicepackItemSlot1 這類掛點，改用本 MOD 自己的名稱）。
-- 一個掛點要四層定義才會出現、掛得上、看得到：
--   1. 快捷列定義 ISHotbarAttachDefinition：穿著的背包提供的每個掛點類型，沒有定義就不建欄位（ISHotbar.lua:472-477）。client/MDB_AttachClient.lua。
--   2. AttachedLocations 的 Human 群組：掛點名稱 → 模型掛點名稱。伺服器與其他客戶端收到掛上封包時照名稱找，
--      找不到就丟例外（GameCharacterAttachedItemPacket.java:102-123、AttachedLocationGroup.java:61-68），所以放 shared。
--   3. FemaleBody／MaleBody 的模型掛點（骨頭、位置、旋轉）：client/MDB_AttachClient.lua。
--   4. 強化版背包的 AttachmentsProvided：這裡在載入時用 DoParam 加。
-- 都在檔案載入時做：shared Lua 在腳本載入之後執行（Core.java:3928-3947、GameServer.java:1447、:1469）；
-- MP 客戶端進服會連腳本一起重載再跑一次 Lua，所以每次都從原始腳本開始。
MDB = MDB or {}

-- 物品槽接受的 AttachmentType → 擺法。同一個掛點裡擺法相同的類型共用一個 AttachedLocation 與模型掛點。
-- 類型清單照 Bag Upgrade Plus 原本的掛點；原版沒有物品用的類型（繩子、信號槍等）留給其他 MOD 的物品。
local TOOLS = {
    Hammer = "Hammer", Screwdriver = "Screwdriver", Knife = "Knife", Wrench = "Wrench", MeatCleaver = "Cleaver",
    Walkie = "Walkie", Gear = "Walkie", Saucepan = "Saucepan", Pan = "Pan", Rope = "Rope", SheetRope = "Rope",
    FlareGun = "Gear", Explosive = "Gear", AuthenticExplosive = "Gear", GasMask = "Gear",
}
local BOTTLES = { WaterBottle = "Bottle", Canteen = "Bottle", Sodacan = "Can", PillBottle = "Pills" }
local PLUSH = { SpiffoPlushie = "Plushie", Doll = "Plushie", TeddyBear = "Plushie", RubberDuck = "Plushie" }
local STRAP = { Umbrella = "Umbrella", Saw = "Saw", Tool = "Tool" }
local LIGHTS = {
    Flashlight = "Flashlight", MilitaryFlashlight = "Flashlight", OldFlashlight = "Flashlight", TorchSmall = "Flashlight",
    HandTorchSmall = "Flashlight", HandTorchBig = "Flashlight", Torch = "Torch", FlashlightBig = "Torch", Torchb = "Torch",
}
MDB.ATTACH_ACCEPTS = {
    Slot1 = TOOLS, Slot2 = TOOLS, Slot3 = TOOLS, BottleR = BOTTLES, BottleL = BOTTLES, Plushie = PLUSH,
    UmbrellaR = STRAP, UmbrellaL = STRAP, Flashlight = LIGHTS,
}

-- 家族照穿戴網格分（座標是照網格算的）：旅行登山包用一般登山包的網格（原版 Bag_HikingBag_Travel.xml），歸 Hiking；
-- Bag Upgrade Plus 把它歸大登山包，兩邊的掛點組合相同。名單是 Bag Upgrade Plus 有掛點的 28 款，加上同網格、BUP 沒給掛點的
-- Bag_DuffelBagTINT 與 Bag_BigHikingBag_Travel。base＝床捲掛點：DoParam 是整串取代（Item.java:2410-2411），原版有的要接回去；
-- 書包原版沒有，照 Bag Upgrade Plus 的書包加上（它只多這一個、沒有額外掛點），5 款書包同網格（m_schoolbag）一起加。
-- replacement＝穿著時背後欄位的長槍、大刀、鏟子等改用「with Bag」位置（ISHotbarAttachDefinition.lua:96-113）。原版行李袋沒有這欄，
-- 背後的長槍會埋進包裡；Bag Upgrade Plus 的行李袋 Plus 都加了，照做。代價和原版背包一樣：穿著時吉他不能背（對到 "null"）。
MDB.ATTACH_FAMILIES = {
    { name = "Alice", base = "BedrollBottomALICE",
      bags = { "Bag_ALICEpack", "Bag_ALICEpack_Army", "Bag_ALICEpack_DesertCamo", "Bag_SurvivorBag" },
      slots = { "Slot1", "Slot2", "Slot3", "BottleR", "BottleL", "Plushie", "UmbrellaR", "Flashlight" } },
    { name = "Duffel", replacement = "Bag",
      bags = { "Bag_DuffelBag", "Bag_MedicalBag", "Bag_Military", "Bag_Police", "Bag_Sheriff", "Bag_SWAT", "Bag_BreakdownBag",
               "Bag_BurglarBag", "Bag_BaseballBag", "Bag_TennisBag", "Bag_WeaponBag", "Bag_InmateEscapedBag", "Bag_MoneyBag",
               "Bag_WorkerBag", "Bag_ShotgunBag", "Bag_ShotgunSawnoffBag", "Bag_ShotgunDblBag", "Bag_ShotgunDblSawnoffBag",
               "Bag_FoodCanned", "Bag_FoodSnacks", "Bag_ToolBag", "Bag_DuffelBagTINT" },
      slots = { "Slot1", "Slot2", "Slot3", "BottleR", "Plushie", "UmbrellaR", "Flashlight" } },
    { name = "Hiking", base = "BedrollBottom",
      bags = { "Bag_NormalHikingBag", "Bag_HikingBag_Travel" },
      slots = { "Slot1", "Slot2", "Slot3", "BottleR", "BottleL", "Plushie", "UmbrellaL", "Flashlight" } },
    { name = "BigHiking", base = "BedrollBottomBig",
      bags = { "Bag_BigHikingBag", "Bag_BigHikingBag_Travel" },
      slots = { "Slot1", "Slot2", "Slot3", "BottleR", "BottleL", "Plushie", "UmbrellaL", "Flashlight" } },
    { name = "School", base = "BedrollBottom",
      bags = { "Bag_Schoolbag", "Bag_Schoolbag_Kids", "Bag_Schoolbag_Medical", "Bag_Schoolbag_Patches", "Bag_Schoolbag_Travel" },
      slots = {} },
}

-- 原版物品掛得上去要有 AttachmentType（實例建立時從腳本複製，存檔不記，讀檔重新取：Item.java:1892、InventoryItem.java:1663-1873），
-- 掛上去畫的是 StaticModel（ModelManager.java:601-607），沒有就看不到。腳本沒有讀 AttachmentType 的 getter，所以清單只收原版沒有
-- AttachmentType 的物品（test_attach.lua 對原版腳本核對）；類型名照 Bag Upgrade Plus 與常見掛點 MOD 的寫法，其他 MOD 的物品也掛得上。
-- 只加這兩個欄位：不照 Bag Upgrade Plus 拿掉液體、開瓶配方、cookable 等欄位。
MDB.ATTACH_ITEMS = {
    -- 瓶子
    ["Base.WaterBottle"] = "WaterBottle", ["Base.Sportsbottle"] = "WaterBottle", ["Base.PopBottle"] = "WaterBottle",
    ["Base.PopBottleRare"] = "WaterBottle", ["Base.BeerBottle"] = "WaterBottle", ["Base.BeerEmpty"] = "WaterBottle",
    ["Base.BeerImported"] = "WaterBottle", ["Base.Brandy"] = "WaterBottle", ["Base.Champagne"] = "WaterBottle",
    ["Base.Cider"] = "WaterBottle", ["Base.CoffeeLiquer"] = "WaterBottle", ["Base.Curacao"] = "WaterBottle",
    ["Base.Gin"] = "WaterBottle", ["Base.Grenadine"] = "WaterBottle", ["Base.Port"] = "WaterBottle", ["Base.Rum"] = "WaterBottle",
    ["Base.Scotch"] = "WaterBottle", ["Base.Sherry"] = "WaterBottle", ["Base.Tequila"] = "WaterBottle",
    ["Base.Vermouth"] = "WaterBottle", ["Base.Vodka"] = "WaterBottle", ["Base.Whiskey"] = "WaterBottle",
    ["Base.Wine"] = "WaterBottle", ["Base.Wine2"] = "WaterBottle", ["Base.WineOpen"] = "WaterBottle",
    ["Base.Wine2Open"] = "WaterBottle", ["Base.WineAged"] = "WaterBottle", ["Base.WineScrewtop"] = "WaterBottle",
    ["Base.JuiceCranberry"] = "WaterBottle", ["Base.JuiceFruitpunch"] = "WaterBottle", ["Base.JuiceGrape"] = "WaterBottle",
    ["Base.JuiceLemon"] = "WaterBottle", ["Base.JuiceOrange"] = "WaterBottle", ["Base.JuiceTomato"] = "WaterBottle",
    ["Base.MilkBottle"] = "WaterBottle", ["Base.Flask"] = "WaterBottle",
    -- 罐子
    ["Base.Pop"] = "Sodacan", ["Base.Pop2"] = "Sodacan", ["Base.Pop3"] = "Sodacan", ["Base.PopEmpty"] = "Sodacan",
    ["Base.Pop2Empty"] = "Sodacan", ["Base.Pop3Empty"] = "Sodacan", ["Base.SodaCan"] = "Sodacan",
    ["Base.BeerCan"] = "Sodacan", ["Base.BeerCanEmpty"] = "Sodacan",
    -- 藥瓶
    ["Base.Pills"] = "PillBottle", ["Base.PillsAntiDep"] = "PillBottle", ["Base.PillsBeta"] = "PillBottle",
    ["Base.PillsSleepingTablets"] = "PillBottle", ["Base.PillsVitamins"] = "PillBottle",
    -- 玩偶
    ["Base.Spiffo"] = "SpiffoPlushie", ["Base.BorisBadger"] = "SpiffoPlushie", ["Base.EyeOfCthulhu"] = "SpiffoPlushie",
    ["Base.FluffyfootBunny"] = "SpiffoPlushie", ["Base.FreddyFox"] = "SpiffoPlushie", ["Base.FurbertSquirrel"] = "SpiffoPlushie",
    ["Base.JacquesBeaver"] = "SpiffoPlushie", ["Base.MoleyMole"] = "SpiffoPlushie", ["Base.PancakeHedgehog"] = "SpiffoPlushie",
    ["Base.PanchoDog"] = "SpiffoPlushie", ["Base.Plushabug"] = "SpiffoPlushie", ["Base.Doll"] = "Doll",
    -- 側邊束帶：收合的傘、鋸子、噴燈
    ["Base.ClosedUmbrellaBlack"] = "Umbrella", ["Base.ClosedUmbrellaBlue"] = "Umbrella", ["Base.ClosedUmbrellaRed"] = "Umbrella",
    ["Base.ClosedUmbrellaTINTED"] = "Umbrella", ["Base.ClosedUmbrellaWhite"] = "Umbrella",
    ["Base.Saw"] = "Saw", ["Base.GardenSaw"] = "Saw", ["Base.SmallSaw"] = "Saw", ["Base.CrudeSaw"] = "Saw",
    ["Base.BlowTorch"] = "Tool",
    -- 手電筒
    ["Base.Torch"] = "Torch", ["Base.HandTorch"] = "Flashlight", ["Base.PenLight"] = "Flashlight",
    ["Base.Flashlight_Crafted"] = "Flashlight",
    -- 繩子
    ["Base.Rope"] = "Rope", ["Base.SheetRope"] = "SheetRope",
}
-- 沒有 StaticModel 的物品借它自己的地面模型（腳本已解析完，要寫全名：Item.java:3177-3180、ScriptManager.java:1926-1941）。
-- 寫了不存在的模型也算沒有：解析結果是「???.名稱」（ScriptManager.java:1946），一樣畫不出來；Bag Upgrade Plus 覆寫的獾、兔、狐就是這樣。
-- 快捷列掛上、拿下的動作會把 StaticModel 畫在手上：布繩、扭扭蟲改指向本 MOD 照抄的模型，多了手骨掛點（scripts/MDB_AttachModels.txt）
MDB.ATTACH_STATIC = {
    ["Base.Spiffo"] = "Base.SpiffoPlushie", ["Base.BorisBadger"] = "Base.PlushieBadger_Ground",
    ["Base.EyeOfCthulhu"] = "Base.PlushieEyeOfChulhu_Ground", ["Base.FluffyfootBunny"] = "Base.PlushieRabbit_Ground",
    ["Base.FreddyFox"] = "Base.PlushieFox_Ground", ["Base.FurbertSquirrel"] = "Base.PlushieSquirrel_Ground",
    ["Base.JacquesBeaver"] = "Base.PlushieBeaver_Ground", ["Base.MoleyMole"] = "Base.PlushieMole_Ground",
    ["Base.PancakeHedgehog"] = "Base.PlushieHedgehog_Ground", ["Base.PanchoDog"] = "Base.Pancho",
    ["Base.Plushabug"] = "MinidoracatBags.MDB_Plushabug", ["Base.Doll"] = "Base.Doll",
    ["Base.Rope"] = "Base.Rope_Looped", ["Base.SheetRope"] = "MinidoracatBags.MDB_SheetRope",
}
-- 本 MOD 照抄的模型的原版來源：物品的 StaticModel 正好是來源時也換成照抄的（只多手骨掛點，掛在包上一樣）。
-- 收錄 Bag Upgrade Plus 的 ServerPatch 把扭扭蟲的 StaticModel 寫成原版 Plushabug，不換的話拿在手上照舊包住手、背包上的校正也對不上
MDB.ATTACH_STATIC_SOURCE = { ["Base.SheetRope"] = "Base.SheetRope", ["Base.Plushabug"] = "Base.Plushabug" }

function MDB.attachSlotType(fam, slot) return "MDB_" .. fam .. slot end
function MDB.attachLocation(fam, slot, pose) return "MDB " .. fam .. " " .. slot .. " " .. pose end
function MDB.attachModelId(fam, slot, pose) return ("mdb_" .. fam .. "_" .. slot .. "_" .. pose):lower() end

-- fn(fam, slot, pose)：每個家族、每個掛點、每種擺法各一次
function MDB.eachAttachPose(fn)
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, slot in ipairs(f.slots) do
            local seen = {}
            for _, pose in pairs(MDB.ATTACH_ACCEPTS[slot]) do
                if not seen[pose] then
                    seen[pose] = true
                    fn(f.name, slot, pose)
                end
            end
        end
    end
end

function MDB.installAttach()
    local group = AttachedLocations.getGroup("Human")
    MDB.eachAttachPose(function(fam, slot, pose)
        group:getOrCreateLocation(MDB.attachLocation(fam, slot, pose)):setAttachmentName(MDB.attachModelId(fam, slot, pose))
    end)
    local sm = getScriptManager()
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        local list = { f.base }
        for _, slot in ipairs(f.slots) do list[#list + 1] = MDB.attachSlotType(f.name, slot) end
        local provided = "AttachmentsProvided = " .. table.concat(list, ";")
        for _, bag in ipairs(f.bags) do
            local s = sm:getItem("MinidoracatBags." .. bag .. "_Reinforced")
            if s then
                s:DoParam(provided)
                if f.replacement then s:DoParam("AttachmentReplacement = " .. f.replacement) end
            end
        end
    end
    for fullType, kind in pairs(MDB.ATTACH_ITEMS) do
        local s = sm:getItem(fullType)
        if s then
            s:DoParam("AttachmentType = " .. kind)
            local model = MDB.ATTACH_STATIC[fullType]
            local cur = s:getStaticModel()
            if model and (not cur or cur:sub(1, 4) == "???." or cur == MDB.ATTACH_STATIC_SOURCE[fullType]) then
                s:DoParam("StaticModel = " .. model)
            end
        end
    end
end

MDB.installAttach()
