-- 離線測試：強化版背包的額外快捷列掛點與說明（shared/MDB_Attach.lua、client/MDB_AttachClient.lua、IG_UI 與 Tooltip 翻譯）。
--   lua scripts/test_attach.lua             四層定義互相對得上、伺服器有 AttachedLocations、DoParam 清單、座標換算、穿戴網格、翻譯鍵
--   lua scripts/test_attach.lua --mutants   另對 MOD 檔案植入錯誤，確認測試抓得到
-- 有遊戲本體時（PZ_PATH，預設 D:/SteamLibrary/steamapps/common/ProjectZomboid）另對原版腳本核對：
-- 加 AttachmentType 的物品原本沒有這欄、借來的模型存在。沒有就略過那幾項。
-- 執行目錄：repo 根。

local MEDIA = "MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42/42/media/"
local TRANSLATE = MEDIA .. "lua/shared/Translate/"
local F = {
    SHARED = MEDIA .. "lua/shared/MDB_Attach.lua",
    CLIENT = MEDIA .. "lua/client/MDB_AttachClient.lua",
    REINF = MEDIA .. "scripts/MDB_Reinforced.txt",
    ITEMS = MEDIA .. "scripts/MDB_Items.txt",
    MODELS = MEDIA .. "scripts/MDB_AttachModels.txt",
    EN = TRANSLATE .. "EN/IG_UI.json",
    CH = TRANSLATE .. "CH/IG_UI.json",
    CHTIP = TRANSLATE .. "CH/Tooltip.json",
    UPG = MEDIA .. "lua/shared/MDB_Upgrade.lua",
}
local LANGS = { "AR", "CH", "CN", "DE", "EN", "ES", "ES_CL", "ES_MX", "FR", "JP", "KO", "PL", "PT", "PTBR", "RU", "TR" }
local PZ = (os.getenv("PZ_PATH") or "D:/SteamLibrary/steamapps/common/ProjectZomboid"):gsub("\\", "/")
local WORKSHOP = (os.getenv("PZ_WORKSHOP") or "D:/SteamLibrary/steamapps/workshop/content/108600"):gsub("\\", "/")   -- 其他 MOD 的玩偶核對用

local MUTATION
local function readRaw(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local text = fh:read("*a")
    fh:close()
    return text
end
local function readFile(path)
    local text = assert(readRaw(path), "找不到檔案：" .. path)
    if MUTATION and F[MUTATION.file] == path then
        local s, e = text:find(MUTATION.from, 1, true)
        if not s then error("突變片段不在原始碼中：" .. MUTATION.name) end
        text = text:sub(1, s - 1) .. MUTATION.to .. text:sub(e + 1)
    end
    return text
end

local pass, fail = 0, 0
local quiet = false
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1 end
    if not quiet then io.write((cond and "  PASS  " or "  FAIL  ") .. name .. "\n") end
end

-- ===== 腳本解析（MDB_Reinforced.txt 與原版腳本共用） =====
local function blocks(text, kind)
    local out = {}
    local pos = 1
    while true do
        local s, e, name = text:find("\n%s*" .. kind .. "%s+([%w_]+)%s*{", pos)
        if not s then break end
        local depth, j = 1, e + 1
        while depth > 0 and j <= #text do
            local c = text:sub(j, j)
            if c == "{" then depth = depth + 1 elseif c == "}" then depth = depth - 1 end
            j = j + 1
        end
        out[name] = text:sub(e + 1, j - 2)
        pos = j
    end
    return out
end
local function field(body, key)
    return body and body:match("\n%s*" .. key .. "%s*=%s*([^,\n]-)%s*,?%s*\n")
end

local WINDOWS = package.config:sub(1, 1) == "\\"
local function listDir(dir, pattern)
    local cmd = WINDOWS and ('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul') or ('ls "' .. dir .. '" 2>/dev/null')
    local out, p = {}, io.popen(cmd)
    for line in p:lines() do if line:match(pattern) then out[#out + 1] = line end end
    p:close()
    return out
end

-- 原版腳本：物品與 model（只讀一次）
local vanilla
local function loadVanilla()
    if vanilla ~= nil then return vanilla end
    local root = PZ .. "/media/scripts/generated/"
    if not readRaw(root .. "items/normal.txt") then vanilla = false return false end
    vanilla = { items = {}, models = {} }
    for _, n in ipairs(listDir(root .. "items", "%.txt$")) do
        for k, v in pairs(blocks(readRaw(root .. "items/" .. n), "item")) do vanilla.items[k] = v end
    end
    for _, n in ipairs(listDir(root, "^models_.*%.txt$")) do
        for k, b in pairs(blocks(readRaw(root .. n), "model")) do vanilla.models[k] = b end
    end
    return vanilla
end

-- ===== 假引擎 =====
local env
local function newVec()
    local v = { 0, 0, 0 }
    function v:set(x, y, z) self[1], self[2], self[3] = x, y, z end
    return v
end
local function newAttachment(id)
    local a = { id = id, offset = newVec(), rotate = newVec(), scale = 1 }
    function a:getId() return self.id end
    function a:setBone(b) self.bone = b end
    function a:getOffset() return self.offset end
    function a:getRotate() return self.rotate end
    function a:setScale(s) self.scale = s end
    return a
end
local function newModelScript(name)
    local ms = { name = name, list = {}, byId = {} }
    function ms:getAttachmentById(id) return self.byId[id] end
    function ms:addAttachment(a) self.list[#self.list + 1] = a; self.byId[a.id] = a; return a end
    return ms
end
local function newScriptItem(fullType, staticModel)
    local s = { fullType = fullType, params = {}, staticModel = staticModel }
    function s:DoParam(str)
        local k, v = str:match("^%s*(%w+)%s*=%s*(.-)%s*$")
        self.params[k] = v
        if k == "StaticModel" then self.staticModel = v end
    end
    function s:getStaticModel() return self.staticModel end
    return s
end

local function resetEnv()
    env = { locations = {}, items = {}, models = { MaleBody = newModelScript("MaleBody"), FemaleBody = newModelScript("FemaleBody") } }
    MDB = nil
    AttachedLocations = { getGroup = function(name)
        env.group = name
        return { getOrCreateLocation = function(_, loc)
            return { setAttachmentName = function(_, id) env.locations[loc] = id end }
        end }
    end }
    function getScriptManager()
        return {
            getItem = function(_, ft) return env.items[ft] end,
            -- 原版與本 MOD 的 model（FIX 校正的對象）用到才建；身體兩個先建好
            getModelScript = function(_, n)
                if not env.models[n] and (n:match("^Base%.") or n:match("^MinidoracatBags%.")) then env.models[n] = newModelScript(n) end
                return env.models[n]
            end,
        }
    end
    ModelAttachment = { new = newAttachment }
    ISHotbarAttachDefinition = {}
    ISHotbar = { doMenuFromInventory = function(_, _, context) env.menuCalls = (env.menuCalls or 0) + 1 end }
    package.loaded["Hotbar/ISHotbarAttachDefinition"] = true
    package.loaded["Hotbar/ISHotbar"] = true
end
function getText(key) return key end

-- 強化版物品：MDB_Reinforced.txt 裡的每一件；本 MOD 的原款（MDB_Items.txt，驗「掛點只給強化版」）；外加原版物品。
-- Base.Doll 假裝已有 StaticModel（驗「有就不蓋」）；
-- Base.BorisBadger 假裝寫了不存在的模型、解析成「???.」（Bag Upgrade Plus 並存時的樣子），驗「畫不出來就改借」；
-- Base.Plushabug 假裝寫了原版 Plushabug（同樣是 BUP 並存時的樣子），驗「是照抄來源就換成照抄的」
local SEED_STATIC = { ["Base.Doll"] = "SomeoneElsesDoll", ["Base.BorisBadger"] = "???.PlushieBadger_Static", ["Base.Plushabug"] = "Base.Plushabug" }
local function seedItems(reinforced, own, attachItems)
    for name in pairs(reinforced) do env.items["MinidoracatBags." .. name] = newScriptItem("MinidoracatBags." .. name) end
    for name in pairs(own) do env.items["MinidoracatBags." .. name] = newScriptItem("MinidoracatBags." .. name) end
    for ft in pairs(attachItems) do env.items[ft] = newScriptItem(ft, SEED_STATIC[ft]) end
end

local load = loadstring or load

-- Bag Upgrade Plus 有額外掛點的 28 款（BUPResearch 第 1.1 節）；它的書包只多一個床捲掛點 BedrollBottom（原版書包沒有），歸 School 家族
local BUP_SETS = {
    A = { "Slot1", "Slot2", "Slot3", "BottleR", "BottleL", "Plushie", "UmbrellaR", "Flashlight" },
    D = { "Slot1", "Slot2", "Slot3", "BottleR", "Plushie", "UmbrellaR", "Flashlight" },
    H = { "Slot1", "Slot2", "Slot3", "BottleR", "BottleL", "Plushie", "UmbrellaL", "Flashlight" },
}
local BUP_BAGS = {
    Bag_ALICEpack = "A", Bag_ALICEpack_Army = "A", Bag_ALICEpack_DesertCamo = "A", Bag_SurvivorBag = "A",
    Bag_NormalHikingBag = "H", Bag_BigHikingBag = "H", Bag_HikingBag_Travel = "H",
}
for _, b in ipairs({ "Bag_DuffelBag", "Bag_MedicalBag", "Bag_Military", "Bag_Police", "Bag_Sheriff", "Bag_SWAT", "Bag_BreakdownBag",
    "Bag_BurglarBag", "Bag_BaseballBag", "Bag_TennisBag", "Bag_WeaponBag", "Bag_InmateEscapedBag", "Bag_MoneyBag", "Bag_WorkerBag",
    "Bag_ShotgunBag", "Bag_ShotgunSawnoffBag", "Bag_ShotgunDblBag", "Bag_ShotgunDblSawnoffBag", "Bag_FoodCanned", "Bag_FoodSnacks",
    "Bag_ToolBag" }) do BUP_BAGS[b] = "D" end
-- 家族 → 穿戴網格（強化版 ClothingItem XML 的 m_MaleModel；主題款照代表款的原版網格產生，日行背包、遠征框架背包是本 MOD 自己的）
local MESH = { Alice = "m_alice_pack", Duffel = "m_duffelbag", Hiking = "m_hikingbag", BigHiking = "m_bighikingbag", School = "m_schoolbag",
    DayPack = "mdb_daypack_m", Expedition = "mdb_expeditionpack_m" }
-- 拿在手上要校正的物品 → 照抄的原版模型（MDB_AttachModels.txt 的 MDB_SheetRope、MDB_Plushabug）
local HELD_FIX = { ["Base.SheetRope"] = "SheetRope", ["Base.Plushabug"] = "Plushabug" }

local function suite()
    resetEnv()
    local reinforced, own = blocks(readFile(F.REINF), "item"), blocks(readFile(F.ITEMS), "item")
    -- 先單獨載入 shared，模擬伺服器（不跑 client Lua：GameServer.java:1469-1471）
    local shared = readFile(F.SHARED)
    MDB = nil
    -- 載入前先種物品（ATTACH_ITEMS 要先讀到才知道種哪些）：預跑一次拿清單
    do
        AttachedLocations = { getGroup = function() return { getOrCreateLocation = function() return { setAttachmentName = function() end } end } end }
        function getScriptManager() return { getItem = function() return nil end } end
        assert(load(shared, "@MDB_Attach.lua"))()
    end
    local attachItems = MDB.ATTACH_ITEMS
    resetEnv()
    seedItems(reinforced, own, attachItems)
    assert(load(shared, "@MDB_Attach.lua"))()

    check("AttachedLocations 用 Human 群組", env.group == "Human")
    local fams, poses = {}, 0
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do fams[f.name] = f end
    local ids, idOk = {}, true
    MDB.eachAttachPose(function(fam, slot, pose)
        poses = poses + 1
        local loc, id = MDB.attachLocation(fam, slot, pose), MDB.attachModelId(fam, slot, pose)
        if env.locations[loc] ~= id or ids[id] or not id:match("^mdb_[%l%d_]+$") then idOk = false end
        ids[id] = true
    end)
    local nLoc = 0
    for _ in pairs(env.locations) do nLoc = nLoc + 1 end
    check("伺服器載入 shared 就登記全部 " .. poses .. " 個 AttachedLocation，模型掛點名不重複、只有小寫英數與底線",
        idOk and nLoc == poses and poses > 0)
    check("掛點名稱帶本 MOD 前綴，不用 Bag Upgrade Plus 的名稱",
        MDB.attachSlotType("Alice", "Slot1") == "MDB_AliceSlot1" and MDB.attachLocation("Alice", "Slot1", "Hammer"):match("^MDB ") ~= nil)

    -- 掛點組合照 Bag Upgrade Plus：它的 28 款各歸一個家族，家族的掛點等於 BUP 的組合（同網格的其他背包由下面的原版核對要求加入）
    local bagFam, dup = {}, false
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, b in ipairs(f.bags) do
            if bagFam[b] then dup = true end
            bagFam[b] = f
        end
    end
    local setOk = not dup
    -- 原版來源 → 形狀（MDB_Upgrade.lua 由產生器寫的 MDB.THEME_SOURCES）：BUP 的每款都升級成它形狀的兩件主題強化版，兩件都在家族裡
    local shapeOf = {}
    for src, shape in readFile(F.UPG):gmatch('%["Base%.([%w_]+)"%] = { shape = "([%w_]+)"') do shapeOf[src] = shape end
    -- 第二個玩偶扣環是本 MOD 多加的（使用者 2026-11-01），比對時拿掉：其餘照 BUP 的組合與順序
    local function bupView(slots)
        local out = {}
        for _, s in ipairs(slots) do if s ~= "Plushie2" then out[#out + 1] = s end end
        return table.concat(out, ",")
    end
    for b, set in pairs(BUP_BAGS) do
        for _, th in ipairs({ "Navy", "Olive" }) do
            local f = shapeOf[b] and bagFam[shapeOf[b] .. "_" .. th]
            if not f or bupView(f.slots) ~= table.concat(BUP_SETS[set], ",") then setOk = false end
        end
    end
    check("Bag Upgrade Plus 的 28 款升級後的兩件主題強化版都歸一個家族，掛點組合照 BUP（ALICE、行李袋、登山包三種；另加包面下緣的第二個玩偶扣環）", setOk)
    local sf, sf2 = bagFam.Bag_Schoolbag_Navy, bagFam.Bag_Schoolbag_Olive
    check("書包照 Bag Upgrade Plus 只加床捲掛點（兩件都在 School 家族、BedrollBottom、沒有額外掛點）",
        sf ~= nil and sf == sf2 and sf.name == "School" and sf.base == "BedrollBottom" and #sf.slots == 0)
    -- 本 MOD 的日行背包、遠征框架背包（使用者 2026-11-01 裁定加掛點、只加強化版）：兩種主題都在家族裡，
    -- 組合照它們沿用欄位的登山包、大登山包，床捲照原款
    local function sameSlots(a, b) return a ~= nil and b ~= nil and table.concat(a.slots, ",") == table.concat(b.slots, ",") end
    local dp, ex = fams.DayPack, fams.Expedition
    check("日行背包、遠征框架背包兩種主題的強化版都有掛點，組合照登山包、大登山包，床捲照原款",
        dp ~= nil and ex ~= nil and bagFam.DayPack_Navy == dp and bagFam.DayPack_Olive == dp
        and bagFam.ExpeditionPack_Navy == ex and bagFam.ExpeditionPack_Olive == ex
        and sameSlots(dp, fams.Hiking) and sameSlots(ex, fams.BigHiking)
        and dp.base == "BedrollBottom" and ex.base == "BedrollBottomBig")

    -- AttachmentsProvided：保留強化版原本的床捲掛點（書包原版沒有，照 BUP 加上），接上本 MOD 的掛點
    local apOk, missing = true, {}
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, b in ipairs(f.bags) do
            local name = b .. "_Reinforced"
            local base = field(reinforced[name], "AttachmentsProvided")
            local want = {}
            if f.base then want[1] = f.base end
            for _, s in ipairs(f.slots) do want[#want + 1] = MDB.attachSlotType(f.name, s) end
            local it = env.items["MinidoracatBags." .. name]
            if not reinforced[name] then missing[#missing + 1] = name end
            if not it or it.params.AttachmentsProvided ~= table.concat(want, ";") then apOk = false end
            if base ~= f.base and not (f.name == "School" and base == nil) then apOk = false end
        end
    end
    check("強化版都存在（" .. table.concat(missing, ",") .. "）", #missing == 0)
    check("AttachmentsProvided 保留原本的床捲掛點（書包照 BUP 加上）、接上家族的全部掛點", apOk)
    local baseOk = true
    for name in pairs(own) do
        local it = env.items["MinidoracatBags." .. name]
        if not it or next(it.params) then baseOk = false end
    end
    check("本 MOD 的原款背包都沒被 DoParam（掛點與說明只給強化版）", baseOk)
    -- 說明：有額外掛點的強化版都多一行說明（腳本原本沒有說明，不蓋掉別的），只有床捲的書包沒有
    local tipOk = MDB.ATTACH_TOOLTIP == "Tooltip_MDB_AttachSlots"
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, b in ipairs(f.bags) do
            local it = env.items["MinidoracatBags." .. b .. "_Reinforced"]
            local want = #f.slots > 0 and MDB.ATTACH_TOOLTIP or nil
            if not it or it.params.Tooltip ~= want or field(reinforced[b .. "_Reinforced"], "Tooltip") then tipOk = false end
        end
    end
    check("有額外掛點的強化版都 DoParam 說明 Tooltip_MDB_AttachSlots，書包沒有", tipOk)
    -- AttachmentReplacement：穿著時背後欄位改用「with Bag」位置。原版行李袋沒有，Bag Upgrade Plus 的行李袋 Plus 都加了，強化版照做；
    -- 其他家族的原版腳本本來就有
    local repOk = true
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, b in ipairs(f.bags) do
            local name = b .. "_Reinforced"
            local it = env.items["MinidoracatBags." .. name]
            local eff = (it and it.params.AttachmentReplacement) or field(reinforced[name], "AttachmentReplacement")
            if eff ~= "Bag" then repOk = false end
        end
    end
    check("掛點家族的強化版穿著時都是 AttachmentReplacement = Bag（行李袋照 BUP 加，其他原版就有）", repOk)

    -- 原版物品：AttachmentType 是某個掛點收的類型；沒有 StaticModel 才借模型
    local accepted = {}
    for _, acc in pairs(MDB.ATTACH_ACCEPTS) do for t in pairs(acc) do accepted[t] = true end end
    local atOk, staticOk = true, true
    for ft, t in pairs(MDB.ATTACH_ITEMS) do
        local it = env.items[ft]
        if not accepted[t] or it.params.AttachmentType ~= t then atOk = false end
        local want = MDB.ATTACH_STATIC[ft]
        if ft == "Base.Doll" then
            if it.params.StaticModel ~= nil then staticOk = false end
        elseif it.params.StaticModel ~= want then
            staticOk = false
        end
    end
    -- 本 MOD 照抄的模型（scripts/MDB_AttachModels.txt）也算：只能指向那個檔裡有的
    local modModels = blocks(readFile(F.MODELS), "model")
    local function known(m)
        return m:match("^Base%.") ~= nil or (m:match("^MinidoracatBags%.") ~= nil and modModels[m:match("%.(.+)$")] ~= nil)
    end
    for ft, m in pairs(MDB.ATTACH_STATIC) do
        if not MDB.ATTACH_ITEMS[ft] or not known(m) then staticOk = false end
    end
    check("每個加 AttachmentType 的原版物品都有掛點收", atOk)
    check("沒有 StaticModel、模型不存在（???.）或正是照抄來源的才借模型（全名），別人的不蓋", staticOk)
    -- 拿在手上的校正：布繩、扭扭蟲借本 MOD 照抄的模型，左右手骨（Bip01_Prop1／Prop2）都有自身掛點、兩手一樣；
    -- 照抄來源（ATTACH_STATIC_SOURCE）就是那份原版模型，而且只有這兩件
    local heldOk = true
    for ft, src in pairs(HELD_FIX) do
        local name = (MDB.ATTACH_STATIC[ft] or ""):match("^MinidoracatBags%.(.+)$")
        local a = name and modModels[name] and blocks(modModels[name], "attachment")
        if not a or not a.Bip01_Prop1 or not a.Bip01_Prop2 or a.Bip01_Prop1 ~= a.Bip01_Prop2 then heldOk = false end
        if MDB.ATTACH_STATIC_SOURCE[ft] ~= "Base." .. src then heldOk = false end
    end
    for ft in pairs(MDB.ATTACH_STATIC_SOURCE) do
        if not HELD_FIX[ft] then heldOk = false end
    end
    check("布繩、扭扭蟲借本 MOD 照抄的模型，有左右手骨掛點、兩手相同，照抄來源對得上", heldOk)
    local onlyTwo = true
    for _, it in pairs(env.items) do
        for k in pairs(it.params) do
            if k ~= "AttachmentType" and k ~= "StaticModel" and k ~= "AttachmentsProvided" and k ~= "AttachmentReplacement" and k ~= "Tooltip" then onlyTwo = false end
        end
    end
    check("DoParam 只動 AttachmentType、StaticModel、AttachmentsProvided、AttachmentReplacement、Tooltip", onlyTwo)
    check("飲料與玩偶都有：瓶、罐、玩偶、娃娃、泰迪熊、橡皮鴨",
        MDB.ATTACH_ITEMS["Base.WaterBottle"] == "WaterBottle" and MDB.ATTACH_ITEMS["Base.Pop"] == "Sodacan"
        and MDB.ATTACH_ITEMS["Base.Spiffo"] == "SpiffoPlushie" and MDB.ATTACH_ITEMS["Base.Doll"] == "Doll"
        and MDB.ATTACH_ITEMS["Base.ToyBear"] == "TeddyBear" and MDB.ATTACH_ITEMS["Base.Rubberducky"] == "RubberDuck")
    -- 玩偶扣環上下兩個（使用者 2026-11-01）：有包頂扣環的家族都有包面下緣的，收的類型相同、緊接在後
    local p2Ok = true
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        local at = 0
        for i, s in ipairs(f.slots) do if s == "Plushie" then at = i end end
        if at > 0 and f.slots[at + 1] ~= "Plushie2" then p2Ok = false end
    end
    check("有包頂玩偶扣環的家族都有包面下緣的第二個，收的類型相同", p2Ok and MDB.ATTACH_ACCEPTS.Plushie2 == MDB.ATTACH_ACCEPTS.Plushie)

    -- 穿戴網格：看強化版自己的 ClothingItem XML（主題款照代表款的原版網格產生；日行背包、遠征框架背包是本 MOD 自己的 .X）。
    -- 座標照網格算：家族裡每款的網格要和家族相同；反過來，網格是某個家族的強化版都要在那個家族（座標照網格共用）
    local function meshOf(name)
        local ci = field(reinforced[name], "ClothingItem")
        local xml = ci and readRaw(MEDIA .. "clothing/clothingItems/" .. ci .. ".xml") or ""
        local mesh = xml:match("<m_MaleModel>[^<]-([%w_]+)%.[xX]</m_MaleModel>") or xml:match("<m_MaleModel>[^<]-([%w_]+)</m_MaleModel>")
        return mesh and mesh:lower()
    end
    local badMesh = {}
    for b, f in pairs(bagFam) do
        local mesh = meshOf(b .. "_Reinforced")
        if mesh ~= MESH[f.name] then badMesh[#badMesh + 1] = b .. "(" .. tostring(mesh) .. ")" end
    end
    check("每款背包的穿戴網格和家族相同（座標照網格算）" .. table.concat(badMesh, ","), #badMesh == 0)
    badMesh = {}
    local famOfMesh = {}
    for name, f in pairs(fams) do famOfMesh[MESH[name]] = f end
    for name in pairs(reinforced) do
        local f = famOfMesh[meshOf(name) or ""]
        local stem = name:gsub("_Reinforced$", "")
        if f and bagFam[stem] ~= f then badMesh[#badMesh + 1] = stem .. "(" .. f.name .. ")" end
    end
    check("強化版只要穿戴網格是某個家族的，就在那個家族（座標照網格共用）" .. table.concat(badMesh, ","), #badMesh == 0)

    -- 原版核對
    local v = loadVanilla()
    if v then
        local bad = {}
        for ft in pairs(MDB.ATTACH_ITEMS) do
            local body = v.items[ft:match("%.(.+)$")]
            if MDB.ATTACH_OTHER_MODS[ft] then
                if body then bad[#bad + 1] = ft .. "(原版也有，不該列在其他 MOD)" end
            elseif not body then bad[#bad + 1] = ft .. "(沒有；其他 MOD 的要列進 ATTACH_OTHER_MODS)"
            elseif field(body, "AttachmentType") then bad[#bad + 1] = ft .. "(已有 AttachmentType)" end
        end
        check("原版核對：加 AttachmentType 的物品都存在、原本沒有 AttachmentType " .. table.concat(bad, ","), #bad == 0)
        bad = {}
        for ft, m in pairs(MDB.ATTACH_STATIC) do
            if not MDB.ATTACH_OTHER_MODS[ft] then
                local body, name = v.items[ft:match("%.(.+)$")], m:match("%.(.+)$")
                local exists = (m:match("^Base%.") and v.models[name]) or (m:match("^MinidoracatBags%.") and modModels[name])
                if field(body, "StaticModel") or not exists then bad[#bad + 1] = ft end
            end
        end
        check("原版核對：借模型的物品原本沒有 StaticModel、借的模型存在 " .. table.concat(bad, ","), #bad == 0)
        bad = {}
        for ft, src in pairs(HELD_FIX) do
            local name = (MDB.ATTACH_STATIC[ft] or ""):match("^MinidoracatBags%.(.+)$")
            local mine, van = name and modModels[name], v.models[src]
            if not mine or not van then bad[#bad + 1] = ft
            else
                for _, k in ipairs({ "mesh", "texture", "scale" }) do
                    if field(mine, k) ~= field(van, k) then bad[#bad + 1] = ft .. "." .. k end
                end
            end
        end
        check("原版核對：照抄的模型網格、貼圖、縮放和原版 SheetRope、Plushabug 相同（掛在背包上的樣子不變） " .. table.concat(bad, ","), #bad == 0)
    else
        io.write("  SKIP  原版核對（找不到 " .. PZ .. "）\n")
    end
    -- 其他 MOD 的玩偶：本機有那個 MOD 的 Workshop 副本時，核對物品存在、原本沒有 AttachmentType／StaticModel、借的模型存在、模組是 Base
    -- （MDB_Attach.lua 用 Base.<名稱> 找）。讀編號最大的版本資料夾（遊戲載入不超過遊戲版本的最新那個；這裡不比遊戲版本），69mini 另有 42.0、42.13
    local function verKey(d)
        local a, b, c = d:match("^(%d+)%.?(%d*)%.?(%d*)$")
        return a and tonumber(a) * 1e6 + (tonumber(b) or 0) * 1e3 + (tonumber(c) or 0)
    end
    local OTHER = { ["69mini"] = { root = WORKSHOP .. "/2937786633/mods/69mini/", sub = "/media/scripts/vehicles/" } }
    for mod, o in pairs(OTHER) do
        local best
        for _, d in ipairs(listDir(o.root, "^%d")) do
            if verKey(d) and (not best or verKey(d) > verKey(best)) then best = d end
        end
        local dir = o.root .. (best or "?") .. o.sub
        local items, models = readRaw(dir .. "69mini_vehiclesitems.txt"), readRaw(dir .. "69mini_models.txt")
        if items and models then
            local its, mds, bad = blocks(items, "item"), blocks(models, "model"), {}
            if items:match("module%s+([%w_]+)") ~= "Base" or models:match("module%s+([%w_]+)") ~= "Base" then bad[#bad + 1] = "module" end
            for ft, owner in pairs(MDB.ATTACH_OTHER_MODS) do
                if owner == mod then
                    local body, m = its[ft:match("%.(.+)$")], MDB.ATTACH_STATIC[ft]
                    if not body or field(body, "AttachmentType") or field(body, "StaticModel") or not m or not mds[m:match("%.(.+)$")] then
                        bad[#bad + 1] = ft
                    end
                end
            end
            check(mod .. " 核對（" .. best .. "）：模組 Base、物品存在、原本沒有 AttachmentType 與 StaticModel、借的模型存在 " .. table.concat(bad, ","), #bad == 0)
        else
            io.write("  SKIP  " .. mod .. " 核對（找不到 " .. dir .. "）\n")
        end
    end

    -- client：快捷列定義與模型掛點
    local serverLocations = env.locations
    assert(load(readFile(F.CLIENT), "@MDB_AttachClient.lua"))()
    local defs, defOk = {}, true
    for _, d in ipairs(ISHotbarAttachDefinition) do defs[d.type] = d end
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, slot in ipairs(f.slots) do
            local d = defs[MDB.attachSlotType(f.name, slot)]
            if not d or d.animset ~= "back" or d.replacement then defOk = false
            else
                for t, pose in pairs(MDB.ATTACH_ACCEPTS[slot]) do
                    local loc = d.attachments[t]
                    if loc ~= MDB.attachLocation(f.name, slot, pose) or not serverLocations[loc] then defOk = false end
                end
                for t in pairs(d.attachments) do if not MDB.ATTACH_ACCEPTS[slot][t] then defOk = false end end
            end
        end
    end
    check("每個家族的每個掛點都有快捷列定義，接受的類型對到伺服器也登記過的 AttachedLocation", defOk and #ISHotbarAttachDefinition == 53)

    local maOk = true
    for sex, body in pairs({ M = "MaleBody", F = "FemaleBody" }) do
        local ms = env.models[body]
        if #ms.list ~= poses then maOk = false end
        MDB.eachAttachPose(function(fam, slot, pose)
            local a = ms.byId[MDB.attachModelId(fam, slot, pose)]
            local off, rot = MDB.attachTransform(MDB.ATTACH_ANCHOR[fam][sex][slot], MDB.ATTACH_POSE[pose])
            if not a or a.bone ~= "Bip01_BackPack" then maOk = false return end
            for i = 1, 3 do
                if math.abs(a.offset[i] - off[i]) > 1e-9 or math.abs(a.rotate[i] - rot[i]) > 1e-9 then maOk = false end
            end
        end)
    end
    check("男女身體都有每個模型掛點，掛在 Bip01_BackPack、座標照起點與擺法換算", maOk)
    MDB.installAttachClient()
    check("Lua 重載時找到同名模型掛點只改值，不重複加", #env.models.MaleBody.list == poses)
    -- 模型自身校正：只加在 FIX 指定的擺法上，id 和身體掛點同名，不綁骨頭，旋轉與位移照表（重載後也不重複）
    local fixOk, fixN = true, 0
    for model, fix in pairs(MDB.ATTACH_FIX) do
        local ms, want = env.models[model], 0
        if not ms or not MDB.ATTACH_POSE[fix[1]] then fixOk = false
        else
            MDB.eachAttachPose(function(fam, slot, pose)
                if pose ~= fix[1] then return end
                want = want + 1
                local a = ms.byId[MDB.attachModelId(fam, slot, pose)]
                if not a or a.bone then fixOk = false return end
                for i = 1, 3 do
                    if math.abs(a.rotate[i] - fix[i + 1]) > 1e-9 or math.abs(a.offset[i] - (fix[i + 4] or 0)) > 1e-9 then fixOk = false end
                end
                if math.abs(a.scale - (fix.s or 1)) > 1e-9 then fixOk = false end
            end)
            -- 有縮放的模型另有兩個手骨掛點
            if want == 0 or #ms.list ~= want + (fix.s and 2 or 0) then fixOk = false end
            fixN = fixN + 1
        end
    end
    check("模型自身校正（" .. fixN .. " 個模型）只加在指定擺法、同名、不綁骨頭，旋轉、位移與縮放照表，重載不重複", fixOk and fixN > 0)
    -- 縮小的熊拿在手上也縮：左右手骨掛點縮放和掛在包上相同，不改位置方向。
    -- 使用者 2026-11-01：泰迪熊掛上去縮到和 Spiffo 差不多，所以 TeddyBear 類型借的每個模型都要有縮放
    local heldScaleOk, nTeddy = true, 0
    for ft, at in pairs(MDB.ATTACH_ITEMS) do
        if at == "TeddyBear" then
            nTeddy = nTeddy + 1
            local fix = MDB.ATTACH_FIX[MDB.ATTACH_STATIC[ft] or ""]
            if not fix or not fix.s or fix.s >= 0.8 then heldScaleOk = false end
        end
    end
    for model, fix in pairs(MDB.ATTACH_FIX) do
        if fix.s then
            local ms = env.models[model]
            for _, hand in ipairs({ "Bip01_Prop1", "Bip01_Prop2" }) do
                local a = ms and ms.byId[hand]
                if not a or a.scale ~= fix.s or a.offset[1] ~= 0 or a.offset[2] ~= 0 or a.offset[3] ~= 0
                    or a.rotate[1] ~= 0 or a.rotate[2] ~= 0 or a.rotate[3] ~= 0 then heldScaleOk = false end
            end
        end
    end
    check("泰迪熊（" .. nTeddy .. " 款）掛在包上縮小，拿在手上照同樣比例縮（左右手骨掛點只有縮放）", heldScaleOk and nTeddy == 5)
    local v = loadVanilla()
    if v then
        -- 每個校正的模型都存在，而且真的有物品用它、那個物品的類型會用到這個擺法（不然校正永遠不會生效）
        local poseOf = {}
        for _, acc in pairs(MDB.ATTACH_ACCEPTS) do for t, p in pairs(acc) do poseOf[t] = p end end
        local used = {}
        for name, body in pairs(v.items) do
            local ft = "Base." .. name
            local model = MDB.ATTACH_STATIC[ft] or field(body, "StaticModel") or field(body, "WeaponSprite")
                or (field(body, "WeaponSpritesByIndex") or ""):match("^[^;]+")
            local pose = poseOf[MDB.ATTACH_ITEMS[ft] or field(body, "AttachmentType") or ""]
            if model and pose then used[(model:find("%.") and model or "Base." .. model) .. "|" .. pose] = true end
        end
        local bad = {}
        for model, fix in pairs(MDB.ATTACH_FIX) do
            local otherMod = false
            for ft, m in pairs(MDB.ATTACH_STATIC) do
                if m == model and MDB.ATTACH_OTHER_MODS[ft] then otherMod = true end
            end
            if not otherMod then   -- 其他 MOD 的模型由上面那個 MOD 的核對看
                local name = model:match("%.(.+)$")
                local exists = (model:match("^Base%.") and v.models[name]) or (model:match("^MinidoracatBags%.") and modModels[name])
                if not exists or not used[model .. "|" .. fix[1]] then bad[#bad + 1] = model end
            end
        end
        check("原版核對：校正的模型都存在、有物品會用這個擺法掛它 " .. table.concat(bad, ","), #bad == 0)
    end

    -- 座標表：每個家族、性別、掛點都有起點，面朝向和左右邊一致；每種擺法都有值
    local anOk = true
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, sex in ipairs({ "M", "F" }) do
            for _, slot in ipairs(f.slots) do
                local a = MDB.ATTACH_ANCHOR[f.name] and MDB.ATTACH_ANCHOR[f.name][sex] and MDB.ATTACH_ANCHOR[f.name][sex][slot]
                if not a or #a ~= 4 then anOk = false
                else
                    local side = slot:match("[RL]$") and (slot:sub(-1) == "R" and -1 or 1)
                    if side and (a[2] * side <= 0 or a[4] ~= 90 * side) then anOk = false end
                    if slot == "Flashlight" and a[4] ~= 0 and a[2] * a[4] <= 0 then anOk = false end
                    if a[1] <= 0 then anOk = false end
                end
            end
        end
    end
    local poseOk = true
    MDB.eachAttachPose(function(_, _, pose) if not MDB.ATTACH_POSE[pose] or #MDB.ATTACH_POSE[pose] ~= 6 then poseOk = false end end)
    check("每個家族、男女、掛點都有起點；右邊在 -y、面朝 -90，左邊在 +y、面朝 90；都在背部外側", anOk)
    check("每種擺法都有旋轉與位移", poseOk)

    -- 旋轉換算：JOML rotateXYZ 來回一致
    local E, M, toE = MDB.attachEuler, MDB.attachMul, MDB.attachToEuler
    local rtOk = true
    for _, r in ipairs({ { 10, 20, 30 }, { -95, 40, 170 }, { 180, -60, -90 }, { 0, 0, 90 }, { 33, -80, 12 } }) do
        local m1 = E(r[1], r[2], r[3])
        local m2 = E(toE(m1))
        for i = 1, 3 do for j = 1, 3 do if math.abs(m1[i][j] - m2[i][j]) > 1e-9 then rtOk = false end end end
    end
    local rz = E(0, 0, 90)
    check("rotateXYZ 換算：矩陣→角度→矩陣一致，繞 z 轉 90 度把 +x 轉到 +y",
        rtOk and math.abs(rz[2][1] - 1) < 1e-12 and math.abs(rz[1][1]) < 1e-12)
    local m90 = M(E(90, 0, 0), E(0, 90, 0))
    local ref = E(90, 90, 0)
    local mulOk = true
    for i = 1, 3 do for j = 1, 3 do if math.abs(m90[i][j] - ref[i][j]) > 1e-12 then mulOk = false end end end
    check("矩陣相乘：Rx·Ry 等於 rotateXYZ(x, y, 0)", mulOk)
    local off, rot = MDB.attachTransform({ 0.1, -0.1, 0, -90 }, { 0, 0, 0, 0.02, 0, 0.01 })
    check("右側掛點的朝外位移往 -y、往上位移照舊、旋轉繞 z -90",
        math.abs(off[1] - 0.1) < 1e-9 and math.abs(off[2] + 0.12) < 1e-9 and math.abs(off[3] - 0.01) < 1e-9
        and math.abs(rot[3] + 90) < 1e-9 and math.abs(rot[1]) < 1e-9 and math.abs(rot[2]) < 1e-9)
    -- 面 Rz(-90)·擺法 Rx(90) 把物品 +z 轉到 -x；乘法順序反了會轉到 -y
    local _, rot2 = MDB.attachTransform({ 0, 0, 0, -90 }, { 90, 0, 0, 0, 0, 0 })
    local m2 = E(rot2[1], rot2[2], rot2[3])
    check("面旋轉在外、擺法旋轉在內：Rz(面)·R(擺法)",
        math.abs(m2[1][3] + 1) < 1e-9 and math.abs(m2[2][3]) < 1e-9 and math.abs(m2[3][3]) < 1e-9)

    -- 提示框：同名欄位只列一次，第一行的縮排保留
    local desc = "Tooltip_CanBeAttached <LINE> <INDENT:20> A <LINE> B <LINE> A <LINE> B <LINE> C <LINE> "
    local opt = { notAvailable = true, toolTip = { description = desc } }
    local context = { getOptionFromName = function(_, n) return n == "ContextMenu_Attach" and opt or nil end }
    ISHotbar.doMenuFromInventory(0, {}, context)
    check("提示框去掉重複的欄位名稱",
        opt.toolTip.description == "Tooltip_CanBeAttached <LINE> <INDENT:20> A <LINE> B <LINE> C <LINE> " and env.menuCalls == 1)
    local opt2 = { toolTip = { description = desc } }
    ISHotbar.doMenuFromInventory(0, {}, { getOptionFromName = function() return opt2 end })
    check("掛得上時不動提示", opt2.toolTip.description == desc)

    -- 翻譯：每個掛點類型 16 語都有，只放在 IG_UI.json
    local types = {}
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, s in ipairs(f.slots) do types[#types + 1] = "IGUI_HotbarAttachment_" .. MDB.attachSlotType(f.name, s) end
    end
    for _, lang in ipairs(LANGS) do
        local text = readFile(TRANSLATE .. lang .. "/IG_UI.json")
        local ok = true
        for _, k in ipairs(types) do if not text:find('"' .. k .. '"%s*:%s*"[^"]+"') then ok = false end end
        local other = readFile(TRANSLATE .. lang .. "/ItemName.json") .. readFile(TRANSLATE .. lang .. "/ContextMenu.json")
        check(lang .. "/IG_UI.json 有全部 " .. #types .. " 個掛點名稱，別的檔沒有", ok and not other:find("IGUI_HotbarAttachment_", 1, true))
        -- 說明鍵要在 Tooltip.json（引擎依檔名分表，Translator.java:137-146）
        local tip = readFile(TRANSLATE .. lang .. "/Tooltip.json")
        check(lang .. "/Tooltip.json 有掛點說明 " .. MDB.ATTACH_TOOLTIP, tip:find('"' .. MDB.ATTACH_TOOLTIP .. '"%s*:%s*"[^"]+"') ~= nil)
    end
end

io.write("== 強化版背包額外掛點\n")
suite()

if arg and arg[1] == "--mutants" then
    local mutants = {
        { name = "AttachedLocations 換群組", file = "SHARED", from = 'AttachedLocations.getGroup("Human")', to = 'AttachedLocations.getGroup("Animal")' },
        { name = "沒登記 AttachedLocation", file = "SHARED", from = ":setAttachmentName(MDB.attachModelId(fam, slot, pose))", to = "" },
        { name = "AttachedLocation 放到 client", file = "SHARED", from = "    local group = AttachedLocations.getGroup(\"Human\")\n    MDB.eachAttachPose(function(fam, slot, pose)\n        group:getOrCreateLocation(MDB.attachLocation(fam, slot, pose)):setAttachmentName(MDB.attachModelId(fam, slot, pose))\n    end)\n", to = "" },
        { name = "模型掛點名大寫", file = "SHARED", from = '("mdb_" .. fam .. "_" .. slot .. "_" .. pose):lower()', to = '"mdb_" .. fam .. "_" .. slot .. "_" .. pose' },
        { name = "擺法沒去重", file = "SHARED", from = "if not seen[pose] then", to = "if true then" },
        { name = "床捲掛點被蓋掉", file = "SHARED", from = "local list = { f.base }", to = "local list = {}" },
        { name = "ALICE 床捲名稱錯", file = "SHARED", from = 'base = "BedrollBottomALICE"', to = 'base = "BedrollBottom"' },
        { name = "少一個家族掛點", file = "SHARED", from = '"Plushie", "Plushie2", "UmbrellaR", "Flashlight" } },\n    { name = "Duffel"', to = '"Plushie", "Plushie2", "UmbrellaR" } },\n    { name = "Duffel"' },
        { name = "登山包漏保護傘款", file = "SHARED", from = 'bags = { "Bag_NormalHikingBag_Navy", "Bag_NormalHikingBag_Olive" }', to = 'bags = { "Bag_NormalHikingBag_Navy" }' },
        { name = "行李袋漏保護傘款", file = "SHARED", from = 'bags = { "Bag_DuffelBag_Navy", "Bag_DuffelBag_Olive" }', to = 'bags = { "Bag_DuffelBag_Navy" }' },
        { name = "強化版前綴錯", file = "SHARED", from = '"MinidoracatBags." .. bag .. "_Reinforced"', to = '"Base." .. bag' },
        { name = "沒加 AttachmentType", file = "SHARED", from = 's:DoParam("AttachmentType = " .. kind)', to = "" },
        { name = "已有 StaticModel 也蓋", file = "SHARED", from = 'if model and (not cur or cur:sub(1, 4) == "???." or cur == MDB.ATTACH_STATIC_SOURCE[fullType]) then', to = "if model then" },
        { name = "不存在的模型當成已有", file = "SHARED", from = 'cur:sub(1, 4) == "???." or ', to = "" },
        { name = "是照抄來源也不換", file = "SHARED", from = " or cur == MDB.ATTACH_STATIC_SOURCE[fullType]", to = "" },
        { name = "照抄來源寫錯", file = "SHARED", from = '["Base.Plushabug"] = "Base.Plushabug" }', to = '["Base.Plushabug"] = "Base.SpiffoPlushie" }' },
        { name = "借模型沒寫全名", file = "SHARED", from = '["Base.Spiffo"] = "Base.SpiffoPlushie"', to = '["Base.Spiffo"] = "SpiffoPlushie"' },
        { name = "飲料類型沒有掛點收", file = "SHARED", from = 'local BOTTLES = { WaterBottle = "Bottle",', to = 'local BOTTLES = { WaterBottleX = "Bottle",' },
        { name = "加了已有 AttachmentType 的原版物品", file = "SHARED", from = '["Base.Flask"] = "WaterBottle",', to = '["Base.Flask"] = "WaterBottle", ["Base.Hammer"] = "Hammer",' },
        { name = "定義缺 animset", file = "CLIENT", from = 'animset = "back"', to = 'animset = "belt left"' },
        { name = "定義的位置名稱錯", file = "CLIENT", from = "attachments[itemType] = MDB.attachLocation(f.name, slot, pose)", to = "attachments[itemType] = pose" },
        { name = "模型掛點換骨頭", file = "CLIENT", from = '"Bip01_BackPack", off, rot, 1)', to = '"Bip01_Spine1", off, rot, 1)' },
        { name = "模型掛點只加男生", file = "CLIENT", from = '{ M = "MaleBody", F = "FemaleBody" }', to = '{ M = "MaleBody" }' },
        { name = "重載時重複加", file = "CLIENT", from = "if not a then", to = "if true then" },
        { name = "面旋轉沒套到位移", file = "CLIENT", from = "anchor[i] + face[i][1] * d[1] + face[i][2] * d[2] + face[i][3] * d[3]", to = "anchor[i] + d[i]" },
        { name = "旋轉順序反了", file = "CLIENT", from = "local r = mul(face, euler(pose[1], pose[2], pose[3]))", to = "local r = mul(euler(pose[1], pose[2], pose[3]), face)" },
        { name = "rotateXYZ 換算 y 號錯", file = "CLIENT", from = "{ cy * cz, -cy * sz, sy },", to = "{ cy * cz, -cy * sz, -sy }," },
        { name = "角度換回去 x 號錯", file = "CLIENT", from = "math.atan2(-m[2][3], m[3][3])", to = "math.atan2(m[2][3], m[3][3])" },
        { name = "右側水瓶擺到左邊", file = "CLIENT", from = "BottleR = { 0.044, -0.114, -0.066, -90 }", to = "BottleR = { 0.044, 0.114, -0.066, -90 }" },
        { name = "右側面朝向錯", file = "CLIENT", from = "BottleR = { 0.030, -0.113, -0.057, -90 }", to = "BottleR = { 0.030, -0.113, -0.057, 90 }" },
        { name = "提示框沒去重", file = "CLIENT", from = 'if line == "" or not seen[key] then', to = "if true then" },
        { name = "提示框去重沒看縮排", file = "CLIENT", from = 'local key = line:gsub("^<INDENT:%d+> ", "")', to = "local key = line" },
        { name = "家族指到不存在的強化版", file = "SHARED", from = 'bags = { "Bag_BigHikingBag_Navy", "Bag_BigHikingBag_Olive" }', to = 'bags = { "Bag_BigHikingBag_Navy", "Bag_BigHikingBag_Travel_Olive" }' },
        { name = "書包沒給床捲", file = "SHARED", from = '{ name = "School", base = "BedrollBottom",', to = '{ name = "School",' },
        { name = "書包床捲名稱錯", file = "SHARED", from = '{ name = "School", base = "BedrollBottom",', to = '{ name = "School", base = "BedrollBottomBig",' },
        { name = "漏一款書包", file = "SHARED", from = 'bags = { "Bag_Schoolbag_Navy", "Bag_Schoolbag_Olive" }', to = 'bags = { "Bag_Schoolbag_Navy" }' },
        { name = "行李袋沒加 AttachmentReplacement", file = "SHARED", from = '{ name = "Duffel", replacement = "Bag",', to = '{ name = "Duffel",' },
        { name = "AttachmentReplacement 沒 DoParam", file = "SHARED", from = 'if f.replacement then s:DoParam("AttachmentReplacement = " .. f.replacement) end', to = "" },
        { name = "AttachmentReplacement 名稱錯", file = "SHARED", from = '{ name = "Duffel", replacement = "Bag",', to = '{ name = "Duffel", replacement = "Bags",' },
        { name = "掛得上也改提示", file = "CLIENT", from = "local tip = opt and opt.notAvailable and opt.toolTip", to = "local tip = opt and opt.toolTip" },
        { name = "自身校正沒套位移", file = "CLIENT", from = "local off, s = { fix[5] or 0, fix[6] or 0, fix[7] or 0 }, fix.s or 1", to = "local off, s = { 0, 0, 0 }, fix.s or 1" },
        { name = "自身校正加到每種擺法", file = "CLIENT", from = "if pose == fix[1] then upsert", to = "if true then upsert" },
        { name = "自身校正擺法打錯", file = "CLIENT", from = '["Base.Doll"] = { "Plushie", 90', to = '["Base.Doll"] = { "Plushy", 90' },
        { name = "自身校正寫成物品名", file = "CLIENT", from = '["Base.Pancho"] = {', to = '["Base.PanchoDog"] = {' },
        { name = "布繩沒指向自己的腳本", file = "SHARED", from = '["Base.SheetRope"] = "MinidoracatBags.MDB_SheetRope"', to = '["Base.SheetRope"] = "Base.SheetRope"' },
        { name = "扭扭蟲沒指向自己的腳本", file = "SHARED", from = '["Base.Plushabug"] = "MinidoracatBags.MDB_Plushabug"', to = '["Base.Plushabug"] = "Base.Plushabug"' },
        { name = "指向不存在的本 MOD 模型", file = "SHARED", from = '"MinidoracatBags.MDB_SheetRope"', to = '"MinidoracatBags.MDB_SheetRop"' },
        { name = "手持模型少左手掛點", file = "MODELS", from = "attachment Bip01_Prop2", to = "attachment Bip01_Prop3" },
        { name = "手持模型兩手不一樣", file = "MODELS", from = "offset = 0.0 0.12 0.0", to = "offset = 0.0 0.2 0.0" },
        { name = "手持模型縮放和原版不同", file = "MODELS", from = "scale = 0.15,", to = "scale = 0.2," },
        { name = "手持模型漏抄貼圖", file = "MODELS", from = "texture = WorldItems/SheetRope,", to = "" },
        { name = "背包校正還掛在原版布繩上", file = "CLIENT", from = '["MinidoracatBags.MDB_SheetRope"] = {', to = '["Base.SheetRope"] = {' },
        { name = "翻譯缺鍵", file = "EN", from = '"IGUI_HotbarAttachment_MDB_DuffelBottleR"', to = '"IGUI_HotbarAttachment_MDB_DuffelBottleX"' },
        { name = "繁中缺鍵", file = "CH", from = '"IGUI_HotbarAttachment_MDB_AliceSlot1"', to = '"IGUI_HotbarAttachment_MDB_AliceSlotA"' },
        { name = "日行背包漏保護傘款", file = "SHARED", from = 'bags = { "DayPack_Navy", "DayPack_Olive" }', to = 'bags = { "DayPack_Navy" }' },
        { name = "遠征框架背包床捲名稱錯", file = "SHARED", from = '{ name = "Expedition", base = "BedrollBottomBig",', to = '{ name = "Expedition", base = "BedrollBottom",' },
        { name = "日行背包少一個掛點", file = "SHARED",
            from = 'bags = { "DayPack_Navy", "DayPack_Olive" },\n      slots = { "Slot1", "Slot2", "Slot3", "BottleR", "BottleL", "Plushie", "Plushie2", "UmbrellaL", "Flashlight" } }',
            to = 'bags = { "DayPack_Navy", "DayPack_Olive" },\n      slots = { "Slot1", "Slot2", "Slot3", "BottleR", "BottleL", "Plushie", "Plushie2", "UmbrellaL" } }' },
        { name = "行李袋漏包面下緣玩偶扣環", file = "SHARED",
            from = '"BottleR", "Plushie", "Plushie2", "UmbrellaR", "Flashlight" } },', to = '"BottleR", "Plushie", "UmbrellaR", "Flashlight" } },' },
        { name = "包面下緣玩偶扣環收的類型不同", file = "SHARED", from = "Plushie = PLUSH, Plushie2 = PLUSH,", to = "Plushie = PLUSH, Plushie2 = STRAP," },
        { name = "泰迪熊沒有掛點收", file = "SHARED", from = 'TeddyBear = "Plushie",', to = 'TeddyBearX = "Plushie",' },
        { name = "69mini 的熊沒列來源 MOD", file = "SHARED", from = '["Base.69miniTeddy"] = "69mini" }', to = "}" },
        { name = "包面下緣玩偶扣環漏座標", file = "CLIENT", from = "Plushie2 = { 0.150, 0.000, -0.129, 0 }, ", to = "" },
        { name = "掛在包上的熊沒縮", file = "CLIENT", from = '{ fix[2], fix[3], fix[4] }, s) end', to = '{ fix[2], fix[3], fix[4] }, 1) end' },
        { name = "手上的熊沒縮", file = "CLIENT", from = 'if a then a:setScale(s) else upsert(ms, hand, nil, { 0, 0, 0 }, { 0, 0, 0 }, s) end',
            to = 'if a then a:setScale(1) else upsert(ms, hand, nil, { 0, 0, 0 }, { 0, 0, 0 }, 1) end' },
        { name = "玩具熊沒縮", file = "CLIENT", from = '["Base.ToyBear"] = { "Plushie", 0, 0, 0, s = 0.55 },', to = '["Base.ToyBear"] = { "Plushie", 0, 0, 0 },' },
        { name = "掛點加到原款", file = "SHARED", from = 'sm:getItem("MinidoracatBags." .. bag .. "_Reinforced")', to = 'sm:getItem("MinidoracatBags." .. bag)' },
        { name = "遠征框架背包用了登山包的網格家族", file = "SHARED", from = 'bags = { "ExpeditionPack_Navy", "ExpeditionPack_Olive" }', to = 'bags = { "Bag_NormalHikingBag_Navy", "Bag_NormalHikingBag_Olive" }' },
        { name = "日行背包座標漏女生", file = "CLIENT", from = "F = { Slot1 = { 0.099, 0.055, -0.020, 0 }", to = "F = { SlotX = { 0.099, 0.055, -0.020, 0 }" },
        { name = "沒加說明", file = "SHARED", from = '                if #f.slots > 0 then s:DoParam("Tooltip = " .. MDB.ATTACH_TOOLTIP) end\n', to = "" },
        { name = "說明加到只有床捲的書包", file = "SHARED", from = 'if #f.slots > 0 then s:DoParam("Tooltip = "', to = 'if true then s:DoParam("Tooltip = "' },
        { name = "說明鍵打錯", file = "SHARED", from = 'MDB.ATTACH_TOOLTIP = "Tooltip_MDB_AttachSlots"', to = 'MDB.ATTACH_TOOLTIP = "Tooltip_MDB_AttachSlot"' },
        { name = "繁中缺說明", file = "CHTIP", from = '"Tooltip_MDB_AttachSlots"', to = '"Tooltip_MDB_AttachSlotsX"' },
    }
    io.write("== 突變（每個都應至少讓一項 FAIL）\n")
    local survived = 0
    for _, m in ipairs(mutants) do
        local keepPass, keepFail = pass, fail
        MUTATION, quiet = m, true
        pass, fail = 0, 0
        local ok, err = pcall(suite)
        -- 突變片段不在原始碼裡時 readFile 會丟錯，那不算抓到
        local killed = (not ok and not tostring(err):find("突變片段不在原始碼中", 1, true)) or (ok and fail > 0)
        io.write(string.format("  %s  %s（%s）\n", killed and "KILLED " or "SURVIVED", m.name,
            ok and (fail .. " 項 FAIL") or ("錯誤：" .. tostring(err))))
        if not killed then survived = survived + 1 end
        pass, fail, MUTATION, quiet = keepPass, keepFail, nil, false
    end
    check("所有突變都被抓到", survived == 0)
end

io.write(string.format("結果：%d PASS，%d FAIL\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
