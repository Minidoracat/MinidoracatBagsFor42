-- 背包升級：容量與負重減輕存在每個背包自己身上（InventoryContainer 存檔會帶 capacity／weightReduction，
-- InventoryContainer.java:70-73）。下表的背包第一次升級時先換成強化版再套階級；公式見 AGENTS.md「設計定案」。
MDB = MDB or {}

-- 有強化版的背包＝升級配方清單裡的全部背包（使用者 2026-10-26 第二批決定）。強化版自重 0.1、不減速、側背包改穿第二個側背包位置。
-- scripts/gen_reinforced.py 讀 MDB.REINFORCED_SOURCES 與 scripts/theme_shapes.json，產生物品腳本、外觀、16 語名稱與配方清單，並寫入 MDB.THEME_SOURCES。
-- 本 MOD 的背包一款一件 MinidoracatBags.<物品名>_Reinforced，欄位照來源；要加款式只加這張表再跑產生器。
-- 來源的 ClothingItemExtra（換穿法）目標也要在表裡，強化版才能互換。
MDB.REINFORCED_SOURCES = {
    -- 腰包的換穿變體和原款互指 ClothingItemExtra，要一起在表裡
    "MinidoracatBags.ToolBeltPouch_Navy", "MinidoracatBags.ToolBeltPouch_Olive", "MinidoracatBags.MedicHipPouch_Navy",
    "MinidoracatBags.MedicHipPouch_Olive", "MinidoracatBags.ToolBeltPouchBack_Navy", "MinidoracatBags.ToolBeltPouchBack_Olive",
    "MinidoracatBags.MedicHipPouchFront_Navy", "MinidoracatBags.MedicHipPouchFront_Olive", "MinidoracatBags.AmmoBandolier_Navy",
    "MinidoracatBags.AmmoBandolier_Olive", "MinidoracatBags.CourierSatchel_Navy",
    "MinidoracatBags.CourierSatchel_Olive", "MinidoracatBags.DayPack_Navy", "MinidoracatBags.DayPack_Olive",
    "MinidoracatBags.ExpeditionPack_Navy", "MinidoracatBags.ExpeditionPack_Olive",
    "MinidoracatBags.ScoutChestRig_Navy", "MinidoracatBags.ScoutChestRig_Olive",
}

-- 原版 80 種依穿戴網格併成 22 種形狀，每種做 S.T.A.R.S.（Navy）與保護傘（Olive）兩件
-- MinidoracatBags.<代表款>_<主題>_Reinforced（使用者 2026-10-27）。shape＝代表款去掉 Base.；themes[i]＝第 i－1 個
-- textureChoice（玩家那個包的顏色）升級後的主題，沒有 textureChoices 的只有一個；pair＝原版換穿法（ClothingItemExtra）的另一面
-- （前後兩面顏色清單相同，產生器核對），換穿過前後的腰包還原時用。
-- BEGIN gen_reinforced.py：由 scripts/theme_shapes.json 產生（--check 比對），不要手改
MDB.THEME_SOURCES = {
    ["Base.Bag_ALICE_BeltSus"] = { shape = "Bag_ALICE_BeltSus", themes = { "Olive", "Olive" } },
    ["Base.Bag_ALICE_BeltSus_Camo"] = { shape = "Bag_ALICE_BeltSus", themes = { "Olive" } },
    ["Base.Bag_ALICE_BeltSus_Green"] = { shape = "Bag_ALICE_BeltSus", themes = { "Olive" } },
    ["Base.Bag_ALICEpack"] = { shape = "Bag_ALICEpack", themes = { "Olive" } },
    ["Base.Bag_ALICEpack_Army"] = { shape = "Bag_ALICEpack", themes = { "Olive" } },
    ["Base.Bag_ALICEpack_DesertCamo"] = { shape = "Bag_ALICEpack", themes = { "Olive" } },
    ["Base.Bag_BaseballBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Navy" } },
    ["Base.Bag_BigHikingBag"] = { shape = "Bag_BigHikingBag", themes = { "Navy", "Olive", "Navy" } },
    ["Base.Bag_BigHikingBag_Travel"] = { shape = "Bag_BigHikingBag", themes = { "Navy", "Olive", "Navy" } },
    ["Base.Bag_BreakdownBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Olive", "Navy", "Navy", "Navy", "Navy", "Navy" } },
    ["Base.Bag_BurglarBag"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_ChestRig"] = { shape = "Bag_ChestRig", themes = { "Olive" } },
    ["Base.Bag_ChestRig_Tarp"] = { shape = "Bag_ChestRig", themes = { "Olive" } },
    ["Base.Bag_ClothSatchel_Burlap"] = { shape = "Bag_ClothSatchel_Cotton", themes = { "Olive" } },
    ["Base.Bag_ClothSatchel_Cotton"] = { shape = "Bag_ClothSatchel_Cotton", themes = { "Olive" } },
    ["Base.Bag_ClothSatchel_Denim"] = { shape = "Bag_ClothSatchel_Cotton", themes = { "Olive" } },
    ["Base.Bag_ClothSatchel_DenimBlack"] = { shape = "Bag_ClothSatchel_Cotton", themes = { "Olive" } },
    ["Base.Bag_ClothSatchel_DenimLight"] = { shape = "Bag_ClothSatchel_Cotton", themes = { "Olive" } },
    ["Base.Bag_CraftedFramepack_Large"] = { shape = "Bag_CraftedFramepack_Large", themes = { "Olive" } },
    ["Base.Bag_CraftedFramepack_Large2"] = { shape = "Bag_CraftedFramepack_Large2", themes = { "Olive" } },
    ["Base.Bag_CraftedFramepack_Large3"] = { shape = "Bag_CraftedFramepack_Large3", themes = { "Olive" } },
    ["Base.Bag_CraftedFramepack_Small"] = { shape = "Bag_CraftedFramepack_Small", themes = { "Olive" } },
    ["Base.Bag_CrudeLeatherBag"] = { shape = "Bag_CrudeLeatherBag", themes = { "Olive" } },
    ["Base.Bag_CrudeTarpBag"] = { shape = "Bag_CrudeLeatherBag", themes = { "Olive" } },
    ["Base.Bag_DuffelBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Olive", "Navy", "Navy", "Navy", "Navy", "Navy" } },
    ["Base.Bag_DuffelBagTINT"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_FannyPackBack"] = { shape = "Bag_FannyPackBack", themes = { "Navy", "Navy", "Navy" }, pair = "Base.Bag_FannyPackFront" },
    ["Base.Bag_FannyPackBack_Hide"] = { shape = "Bag_FannyPackBack", themes = { "Olive" }, pair = "Base.Bag_FannyPackFront_Hide" },
    ["Base.Bag_FannyPackBack_Tarp"] = { shape = "Bag_FannyPackBack", themes = { "Olive" }, pair = "Base.Bag_FannyPackFront_Tarp" },
    ["Base.Bag_FannyPackFront"] = { shape = "Bag_FannyPackFront", themes = { "Navy", "Navy", "Navy" }, pair = "Base.Bag_FannyPackBack" },
    ["Base.Bag_FannyPackFront_Hide"] = { shape = "Bag_FannyPackFront", themes = { "Olive" }, pair = "Base.Bag_FannyPackBack_Hide" },
    ["Base.Bag_FannyPackFront_Tarp"] = { shape = "Bag_FannyPackFront", themes = { "Olive" }, pair = "Base.Bag_FannyPackBack_Tarp" },
    ["Base.Bag_FishingBasket"] = { shape = "Bag_FishingBasket", themes = { "Olive" } },
    ["Base.Bag_FoodCanned"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_FoodSnacks"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_GolfBag"] = { shape = "Bag_GolfBag", themes = { "Navy", "Olive", "Navy", "Navy" } },
    ["Base.Bag_GolfBag_Melee"] = { shape = "Bag_GolfBag", themes = { "Navy", "Olive", "Navy", "Navy" } },
    ["Base.Bag_HideSatchel"] = { shape = "Bag_ClothSatchel_Cotton", themes = { "Olive" } },
    ["Base.Bag_HideSlingBag"] = { shape = "Bag_SheetSlingBag", themes = { "Olive" } },
    ["Base.Bag_HikingBag_Travel"] = { shape = "Bag_NormalHikingBag", themes = { "Navy", "Olive", "Navy" } },
    ["Base.Bag_HydrationBackpack"] = { shape = "Bag_HydrationBackpack", themes = { "Navy", "Navy", "Navy" } },
    ["Base.Bag_HydrationBackpack_Camo"] = { shape = "Bag_HydrationBackpack", themes = { "Olive" } },
    ["Base.Bag_InmateEscapedBag"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_MedicalBag"] = { shape = "Bag_DuffelBag", themes = { "Olive" } },
    ["Base.Bag_Military"] = { shape = "Bag_DuffelBag", themes = { "Olive" } },
    ["Base.Bag_MoneyBag"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_NormalHikingBag"] = { shape = "Bag_NormalHikingBag", themes = { "Navy", "Olive", "Navy", "Olive" } },
    ["Base.Bag_Police"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_RifleCaseCloth"] = { shape = "Bag_RifleCaseCloth", themes = { "Olive", "Olive" } },
    ["Base.Bag_RifleCaseCloth2"] = { shape = "Bag_RifleCaseCloth", themes = { "Olive", "Olive" } },
    ["Base.Bag_RifleCaseClothCamo"] = { shape = "Bag_RifleCaseCloth", themes = { "Olive" } },
    ["Base.Bag_SWAT"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_Satchel"] = { shape = "Bag_Satchel", themes = { "Olive", "Olive", "Olive" } },
    ["Base.Bag_SatchelPhoto"] = { shape = "Bag_Satchel", themes = { "Olive", "Olive", "Olive" } },
    ["Base.Bag_Satchel_Fishing"] = { shape = "Bag_Satchel_Leather", themes = { "Olive" } },
    ["Base.Bag_Satchel_Leather"] = { shape = "Bag_Satchel_Leather", themes = { "Olive" } },
    ["Base.Bag_Satchel_Mail"] = { shape = "Bag_Satchel_Leather", themes = { "Navy" } },
    ["Base.Bag_Satchel_Medical"] = { shape = "Bag_Satchel_Leather", themes = { "Olive" } },
    ["Base.Bag_Satchel_Military"] = { shape = "Bag_Satchel_Leather", themes = { "Olive" } },
    ["Base.Bag_Schoolbag"] = { shape = "Bag_Schoolbag", themes = { "Navy", "Navy", "Navy", "Navy" } },
    ["Base.Bag_Schoolbag_Kids"] = { shape = "Bag_Schoolbag", themes = { "Navy", "Navy", "Olive", "Navy", "Navy", "Navy" } },
    ["Base.Bag_Schoolbag_Medical"] = { shape = "Bag_Schoolbag", themes = { "Olive", "Olive" } },
    ["Base.Bag_Schoolbag_Patches"] = { shape = "Bag_Schoolbag", themes = { "Navy", "Olive" } },
    ["Base.Bag_Schoolbag_Travel"] = { shape = "Bag_Schoolbag", themes = { "Navy" } },
    ["Base.Bag_SheetSlingBag"] = { shape = "Bag_SheetSlingBag", themes = { "Olive" } },
    ["Base.Bag_Sheriff"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_ShotgunBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Olive", "Navy", "Navy", "Navy", "Navy", "Navy" } },
    ["Base.Bag_ShotgunCaseCloth"] = { shape = "Bag_RifleCaseCloth", themes = { "Olive", "Olive" } },
    ["Base.Bag_ShotgunCaseCloth2"] = { shape = "Bag_RifleCaseCloth", themes = { "Olive", "Olive" } },
    ["Base.Bag_ShotgunDblBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Olive", "Navy", "Navy", "Navy", "Navy", "Navy" } },
    ["Base.Bag_ShotgunDblSawnoffBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Olive", "Navy", "Navy", "Navy", "Navy", "Navy" } },
    ["Base.Bag_ShotgunSawnoffBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Olive", "Navy", "Navy", "Navy", "Navy", "Navy" } },
    ["Base.Bag_SurvivorBag"] = { shape = "Bag_ALICEpack", themes = { "Olive", "Olive", "Olive" } },
    ["Base.Bag_TarpFramepack_Large"] = { shape = "Bag_CraftedFramepack_Large", themes = { "Olive" } },
    ["Base.Bag_TarpFramepack_Small"] = { shape = "Bag_CraftedFramepack_Small", themes = { "Olive" } },
    ["Base.Bag_TarpSlingBag"] = { shape = "Bag_SheetSlingBag", themes = { "Olive" } },
    ["Base.Bag_TennisBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Navy" } },
    ["Base.Bag_ToolBag"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_WeaponBag"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
    ["Base.Bag_WorkerBag"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },
}
-- END gen_reinforced.py

MDB.THEMES = { "Navy", "Olive" }
MDB.REINFORCED, MDB.ORIGINAL = {}, {}   -- 本 MOD 來源全名 → 強化版全名；強化版全名 → 還原的預設款（主題強化版是代表款）
MDB.THEMED = {}                          -- 主題強化版全名 → { shape, theme }
for _, ft in ipairs(MDB.REINFORCED_SOURCES) do
    local r = "MinidoracatBags." .. ft:match("[^.]+$") .. "_Reinforced"
    MDB.REINFORCED[ft] = r
    MDB.ORIGINAL[r] = ft
end
function MDB.themedId(shape, theme) return "MinidoracatBags." .. shape .. "_" .. theme .. "_Reinforced" end
for _, s in pairs(MDB.THEME_SOURCES) do
    for _, theme in ipairs(MDB.THEMES) do
        local r = MDB.themedId(s.shape, theme)
        MDB.ORIGINAL[r] = "Base." .. s.shape
        MDB.THEMED[r] = { shape = s.shape, theme = theme }
    end
end

-- 來源的強化版：原版照 textureChoice（-1＝沒有顏色選擇）查主題；本 MOD 的一款一件
function MDB.reinforcedOf(ft, choice)
    local s = MDB.THEME_SOURCES[ft]
    if not s then return MDB.REINFORCED[ft] end
    return MDB.themedId(s.shape, s.themes[(choice or 0) + 1] or s.themes[1])
end

local DEFAULTS = {
    LockLegacyBags = true,
    MaxTier = 3,
    FullCapacityPercent = 100,
    FullWeightReduction = 100,
    LootMultiplier = 1,
}

-- 沙盒值；SandboxVars 還沒有本 MOD 的表時（例如單機 OnPreDistributionMerge 早於 SandboxOptions.load，
-- IsoWorld.java:1886、:1896）退回 sandbox-options.txt 的預設值。
function MDB.opt(name)
    local o = SandboxVars and SandboxVars.MinidoracatBags
    local v = o and o[name]
    if v == nil then return DEFAULTS[name] end
    return v
end

-- Bag Upgrade Plus 水袋的液體容量（使用者 2026-10-26：升滿要和 BUP 一樣）
local FULL_FLUID = 5.0

-- 換型途中為 true：applyTier 不重送，最後由 swapBag 送一次
local swapping = false

-- 最高階（MaxTier）升滿，中間各階平均分配；MaxTier 0 維持原值
function MDB.applyTier(bag, tier)
    local md = bag:getModData()
    if md.MDB_cap == nil then
        md.MDB_cap = bag:getCapacity()
        md.MDB_wr = bag:getWeightReduction()
    end
    local maxTier = MDB.opt("MaxTier")
    local t = maxTier > 0 and math.min(tier, maxTier) or 0
    local m = math.max(maxTier, 1)
    local pct = MDB.opt("FullCapacityPercent")
    -- base + round((full - base) * t / m)，round(x) = floor(x + 0.5)；全用整數算，免浮點誤差
    local function step(base, full) return base + math.floor(((full - base) * t * 2 + m) / (2 * m)) end
    -- 上限＝50 減背包自重：腳本載入與 tooltip 都壓在這裡（Item.java:2493-2499、InventoryContainer.java:125-131），
    -- 原本的 Plus 背包就是 49。自重取腳本值（Item.java:533）：伺服器上 getActualWeight() 會回 0（顯示名稱等於全名時，InventoryItem.java:2740-2742）
    local top = math.floor(50 - bag:getScriptItem():getActualWeight())
    local fullCap = md.MDB_cap + math.floor((math.max(top - md.MDB_cap, 0) * pct + 50) / 100)
    local cap, wr = step(md.MDB_cap, fullCap), step(md.MDB_wr, math.max(md.MDB_wr, MDB.opt("FullWeightReduction")))
    bag:setCapacity(cap)
    bag:setWeightReduction(wr)
    -- 液體容量存在 FluidContainer 元件（GameEntity.java:183、FluidContainer.java:683、存檔 :1202-1205）；
    -- 放在地上時元件搬到世界物品上（IsoWorldInventoryObject.java:103-105，撿起時搬回 :650-653）
    local fc, fluid = bag:getFluidContainerFromSelfOrWorldItem(), nil
    if fc then
        if md.MDB_fluid == nil then md.MDB_fluid = fc:getCapacity() end
        local base = md.MDB_fluid
        local full = base + math.max(FULL_FLUID - base, 0) * pct / 100
        fluid = base + (full - base) * t / m
        fc:setCapacity(fluid)
    end
    md.MDB_tier = tier
    -- 客戶端的容量與負重減輕要整件重送才會更新；單機無作用（LuaManager.java:12404-12412、RecipeCodeOnCreate.java:892-894）。
    -- 地上（含桌面）的背包在伺服器上沒有 container（ContainerID.java:392-396），改用伺服器指令把新數值送給客戶端，
    -- 由 MDB.onServerCommand 套在客戶端原本那件上。不用世界物品的 SWAP_ITEM：它在客戶端換成新物件（IsoWorldInventoryObject.java:115-153），
    -- 不像容器的 replace 會換動作佇列裡的參照（ReplaceInventoryItemInContainerPacket.java:76-81），排好的搬移會被當成東西不在而跳過
    -- （ItemContainer.java:634-635、ISInventoryTransferAction.lua:36-40）；原版也沒有帶容量與負重減輕的物品同步封包。
    if isServer() and not swapping then
        local wi, container = bag:getWorldItem(), bag:getContainer()
        if wi then
            local sq = wi:getSquare()
            sendServerCommand("MinidoracatBags", "floorTier", { x = sq:getX(), y = sq:getY(), z = sq:getZ(), id = bag:getID(), tier = tier,
                cap = cap, wr = wr, fluid = fluid, baseCap = md.MDB_cap, baseWr = md.MDB_wr, baseFluid = md.MDB_fluid })
        elseif container then
            sendReplaceItemInContainer(container, bag, bag)
        end
    end
end

-- 客戶端（OnServerCommand，GameClient.java:1071）：伺服器在地上原地升階後送來的數值，照 ID 找到那一格的世界物品，
-- 寫在同一個物件上，排好的動作與開著的背包面板照舊指著它。階級與基準也寫進 modData：OnTest 在客戶端用 MDB_tier 判斷下一階。
-- 找不到（那一格沒載入）就不管，區塊載入時拿到的是伺服器存的那份。伺服器指令走 RELIABLE、不保證順序
-- （GameServer.java:3497-3522 的 ClientCommand 封包，PacketTypes.java:510），原地升階只會往上，比現在低的是晚到的舊指令，不套
function MDB.onServerCommand(module, command, args)
    if module ~= "MinidoracatBags" or command ~= "floorTier" then return end
    local sq = getCell():getGridSquare(args.x, args.y, args.z)
    local wos = sq and sq:getWorldObjects()
    for i = 0, (wos and wos:size() or 0) - 1 do
        local bag = wos:get(i):getItem()
        if bag and bag:getID() == args.id then
            local md = bag:getModData()
            if (md.MDB_tier or 0) > args.tier then return end
            md.MDB_tier, md.MDB_cap, md.MDB_wr, md.MDB_fluid = args.tier, args.baseCap, args.baseWr, args.baseFluid
            bag:setCapacity(args.cap)
            bag:setWeightReduction(args.wr)
            local fc = args.fluid and bag:getFluidContainerFromSelfOrWorldItem()
            if fc then fc:setCapacity(args.fluid) end
            return
        end
    end
end
Events.OnServerCommand.Add(MDB.onServerCommand)

-- 換成另一種背包（升級換成強化版、還原、舊 Plus 改裝、換主題），再套 tier。
-- copyClothingItem 搬內容物（同一批物件，ID 不變）、外觀、改名、顏色、耐久、最愛、液體與 modData（ISClothingExtraAction.lua:62-112）。
-- 新背包先放進同一個容器再搬：中途出錯時內容物分在兩個背包裡，不會落在沒有容器的物品上。
-- 伺服器最後只送一次 replace：客戶端依舊 ID 移除、加入整件新背包，並換掉動作佇列裡的舊參照
-- （ReplaceInventoryItemInContainerPacket.java:57-82）；單機改呼叫 replaceItemInContainer 換動作佇列（LuaManager.java:12442-12449）。
-- 地上（含桌面）的背包：Neat Crafting 的「製作」不先搬進物品欄（NC_CraftActionPanel.lua:269-296），背包直接當輸入。
-- 伺服器重建的地面容器不設物品的 container（ContainerID.java:392-396、:566-575），單機則是背包面板的地面容器，
-- 兩種都改成在同一格同一位置放新的世界物品（先不送），做完再照原版撿起的寫法移除舊的（ISTransferAction.lua:131-159）、送出新的
-- （IsoGridSquare.java:6141-6143）。
function MDB.swapBag(old, newType, tier, character)
    local wi = old:getWorldItem()
    local cont = old:getContainer()
    if not wi and not cont then error("MDB.swapBag: " .. old:getFullType() .. " is neither in a container nor on the ground") end
    local new = instanceItem(newType)
    -- 階級的基準取新背包自己的腳本值：同形狀合併後強化版的起始值是同組最高的，還原成原款要回到原款的值。
    -- 要在 copyClothingItem 之前記：它搬來舊的 modData，檔尾的換穿包裝會先照舊基準套一次階級
    local cap, wr, nfc = new:getCapacity(), new:getWeightReduction(), new:getFluidContainer()
    local fluid = nfc and nfc:getCapacity()
    if wi then
        wi:getSquare():AddWorldInventoryItem(new, wi:getOffX(), wi:getOffY(), wi:getOffZ(), false)
        -- 「放置」擺的方向與不被地上物品清除的旗標存在舊的那份上（ISDropWorldItemAction.lua:81-87、IsoGridSquare.java:3223-3240），照搬
        new:setWorldXRotation(old:getWorldXRotation())
        new:setWorldYRotation(old:getWorldYRotation())
        new:setWorldZRotation(old:getWorldZRotation())
        new:getWorldItem():setIgnoreRemoveSandbox(wi:isIgnoreRemoveSandbox())
        new:getWorldItem():setExtendedPlacement(wi:isExtendedPlacement())
    else
        cont:AddItem(new)
    end
    swapping = true
    local ok, err = pcall(function()
        copyClothingItem(old, new)
        local md = new:getModData()
        md.MDB_cap, md.MDB_wr, md.MDB_fluid = cap, wr, fluid
        -- 換回記下的原款（MDB.toReinforced 記的）：顏色也換回去。主題強化版只有一張貼圖、不能隨機染色，搬過來的 textureChoice
        -- 一畫就被改成 0、染色變白（ItemVisual.java:153-166、:185-196），不能靠 copyClothingItem 帶回來
        local v = newType == md.MDB_origin and new:getVisual()
        if v then
            v:setTextureChoice(md.MDB_originTex or -1)
            if md.MDB_originTint then v:setTint(ImmutableColor.decode(md.MDB_originTint)) end
            new:synchWithVisual()
        end
        -- copyClothingItem 拿 getName() 比對腳本名稱，染血、磨損的前綴或水袋的液體名稱也會被當成改名寫進新背包
        -- （InventoryItem.java:2435-2480），名稱不同就跟著存檔（:1711）。玩家改過名的（ISInventoryPaneContextMenu.lua:2741-2750）
        -- 由檔尾的換穿包裝帶著旗標沿用原名，其餘換回新背包的腳本名稱。
        if not old:isCustomName() then
            new:setName(new:getScriptItem():getDisplayName())
        end
        MDB.applyTier(new, tier)
        -- copyClothingItem 搬液體時新背包還是腳本容量，多的被截掉（FluidContainer.java:179-194、:929-932）；容量設好後再搬一次。
        -- 地上的背包液體在世界物品上，原版 copyClothingItem 搬不到，只靠這一次（nfc 是同一個元件，放上地面只是換了主人）。
        -- 照公式裝不下時（主題水袋從組內最高的 3 升起算，還原成 2 升的一般水袋；或沙盒調低後換型），容量留在換型前的值，水不倒掉
        local ofc = old:getFluidContainerFromSelfOrWorldItem()
        if ofc and nfc then
            if ofc:getAmount() > nfc:getCapacity() then nfc:setCapacity(ofc:getCapacity()) end
            nfc:copyFluidsFrom(ofc)
        end
    end)
    swapping = false
    if not ok then
        -- 地上：新背包還沒送過，內容物搬回舊背包（copyClothingItem 用 takeItemsFrom 搬，ISClothingExtraAction.lua:74-75），
        -- 再從那一格撤掉，兩邊的物件清單照舊一致（移除封包按索引，RemoveItemFromSquarePacket.java:55-60、:83-87）
        if wi then
            local nwi = new:getWorldItem()
            old:getItemContainer():takeItemsFrom(new:getItemContainer())
            DesignationZoneAnimal.removeItemFromGround(nwi)
            wi:getSquare():removeWorldObject(nwi)
            new:setWorldItem(nil)
        end
        error(err)
    end
    if wi then
        if cont then cont:DoRemoveItem(old) end   -- 單機的背包面板地面容器（伺服器上地上物品沒有 container）
        local sq = wi:getSquare()
        DesignationZoneAnimal.removeItemFromGround(wi)
        sq:transmitRemoveItemFromSquare(wi)
        sq:removeWorldObject(wi)
        old:setWorldItem(nil)
        if isServer() then new:getWorldItem():transmitCompleteItemToClients() end
        return new
    end
    cont:Remove(old)   -- 也會把它從手上拿掉（ItemContainer.java:2036-2039）
    if isServer() then
        sendReplaceItemInContainer(cont, old, new)
    elseif character and cont == character:getInventory() then
        replaceItemInContainer(cont, old, new)   -- 會把容器的 parent 轉成 IsoPlayer，只能用在主物品欄
    end
    return new
end

local function tierOf(bag)
    return bag:getModData().MDB_tier or 0
end

-- 配方的 keep 輸入裡第一個背包。原版介面開工前把輸入搬進主物品欄（ISWidgetHandCraftControl.lua:342-351），Neat Crafting 不搬，
-- 所以也可能在地上：換型由 swapBag 處理，只升階的由 applyTier 送 floorTier 指令、客戶端原地套用
function MDB.keepBag(data)
    local items = data:getAllKeepInputItems()
    for i = 0, items:size() - 1 do
        if instanceof(items:get(i), "InventoryContainer") then return items:get(i) end
    end
end

-- 換成強化版。原版來源 sourceType（舊外殼則是它對應的原版）照這個包的顏色選主題，並把原款、顏色與染色記在 modData
-- （記在舊背包上，copyClothingItem 跟著搬，伺服器送出的新背包就帶著），還原時用。
-- textureChoice：getVisual() 第一次建立時就選好（InventoryItem.java:2323-2330、ItemVisual.java:214-222）。
-- 染色存成 ImmutableColor.decode 讀得懂的整數字串（ImmutableColor.java:102-119、:129-131；整數值的 tostring 不帶小數點，
-- KahluaUtil.java:180-188）
function MDB.toReinforced(bag, sourceType, tier, character)
    local choice = -1
    if MDB.THEME_SOURCES[sourceType] then
        local v, md = bag:getVisual(), bag:getModData()
        choice = v and v:getTextureChoice() or -1
        local t = v and v:getTint()
        md.MDB_origin, md.MDB_originTex = sourceType, choice
        md.MDB_originTint = t and tostring(math.floor(t:getRedFloat() * 255 + 0.5)
            + 256 * math.floor(t:getGreenFloat() * 255 + 0.5) + 65536 * math.floor(t:getBlueFloat() * 255 + 0.5)) or nil
    end
    return MDB.swapBag(bag, MDB.reinforcedOf(sourceType, choice), tier, character)
end

-- 還原（強化版→原版）與 0.1.0 升過級的原版背包改成強化版：只換型，階級照舊。
-- 主題強化版還原成記下的原款；換穿過前後的腰包是原款在這一面的版本（pair）；沒有紀錄或形狀對不上就是代表款
function MDB.onSwapKeepTier(data, character)
    local bag = MDB.keepBag(data)
    if not bag then return end
    local ft = bag:getFullType()
    local back = MDB.ORIGINAL[ft]
    if not back then
        MDB.toReinforced(bag, ft, tierOf(bag), character)
        return
    end
    local t, md = MDB.THEMED[ft], bag:getModData()
    local s = md.MDB_origin and MDB.THEME_SOURCES[md.MDB_origin]
    if t and s and s.shape ~= t.shape and s.pair and MDB.THEME_SOURCES[s.pair].shape == t.shape then
        md.MDB_origin, s = s.pair, MDB.THEME_SOURCES[s.pair]   -- swapBag 看到 newType 是記下的原款才換回顏色
    end
    if t and s and s.shape == t.shape then back = md.MDB_origin end
    MDB.swapBag(bag, back, tierOf(bag), character)
end

-- 換主題（S.T.A.R.S.↔保護傘）：只給主題強化版。階級、內容物、液體、改過的名字與記下的原款都照舊（swapBag）
function MDB.onSwapTheme(data, character)
    local bag = MDB.keepBag(data)
    local t = bag and MDB.THEMED[bag:getFullType()]
    if not t then return end
    MDB.swapBag(bag, MDB.themedId(t.shape, t.theme == "Navy" and "Olive" or "Navy"), tierOf(bag), character)
end

-- 已升級原版背包改成強化版：只放行第 1 階以上的背包，第 0 階要走升級（不然免費拿到自重 0.1）
function MDB.onTestUpgraded(item, character)
    return not instanceof(item, "InventoryContainer") or tierOf(item) >= 1
end

-- OnTest（item, character）：每個候選輸入都會呼叫（CraftRecipe.java:1010-1030），工具與材料一律放行
local function gate(item, tier)
    if not instanceof(item, "InventoryContainer") then return true end
    return tier <= MDB.opt("MaxTier") and tierOf(item) == tier - 1
end

function MDB.onTestTier1(item, character) return gate(item, 1) end
function MDB.onTestTier2(item, character) return gate(item, 2) end
function MDB.onTestTier3(item, character) return gate(item, 3) end

-- OnCreate（data, character）：只在單機或伺服器執行（ISHandcraftAction.lua:221-234）。
-- 有強化版的背包先換成強化版再套新階級
function MDB.onUpgrade(data, character)
    local bag = MDB.keepBag(data)
    if not bag then return end
    local tier = tierOf(bag) + 1
    if tier > MDB.opt("MaxTier") then return end
    local ft = bag:getFullType()
    if MDB.reinforcedOf(ft) then
        MDB.toReinforced(bag, ft, tier, character)
    else
        MDB.applyTier(bag, tier)
    end
end

-- 換穿法（腰包前背↔後背）換成另一個物品：原版 createItemNew 搬了 modData，沒搬容量與負重減輕
-- （ISClothingExtraAction.lua:66-112），換完回到腳本預設、MDB_tier 卻還在，就升不回來了。這裡依 MDB_tier 重算。
-- 同一個函式也是 copyClothingItem（:62-64，InventoryItem.java:5029-5036）與背負噴霧器換物（ISEquipWeaponAction.lua:152）的路徑。
-- MP 的 complete() 在伺服器跑（NetTimedAction.java:132-139；客戶端不跑，LuaTimedActionNew.java:164-170）。
-- 新物品這時還沒放進容器也沒放上地面，applyTier 不重送；接著 sendAddItemToContainer 整件送出，負重減輕與容量都在裡面
-- （AddInventoryItemToContainerPacket.java:54-58、InventoryContainer.java:57-58、ItemContainer.java:2439）。
-- MDB.swapBag 呼叫 copyClothingItem 時新背包已在容器裡或地上，由 swapping 擋下這次重送。
-- 原版只搬改過的名字（:76-79），沒搬改名旗標；swapBag 看旗標決定沿不沿用舊名，換穿過的改名腰包一升級就變回預設名。
-- 原版拿 getName() 比對、寫入，染血、磨損前綴也會寫進名字（InventoryItem.java:2435-2480），改過名的這裡換回原始名稱。
require "TimedActions/ISClothingExtraAction"
local createItemNew = ISClothingExtraAction.createItemNew
function ISClothingExtraAction:createItemNew(item, newItem)
    local result = createItemNew(self, item, newItem)
    if item:isCustomName() and instanceof(newItem, "InventoryContainer") then
        newItem:setName(item:getDisplayName())
        newItem:setCustomName(true)
    end
    local tier = newItem:hasModData() and newItem:getModData().MDB_tier
    if tier and instanceof(newItem, "InventoryContainer") then
        MDB.applyTier(newItem, tier)
    end
    return result
end
