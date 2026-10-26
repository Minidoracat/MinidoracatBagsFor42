-- 離線測試：強化版背包的額外快捷列掛點（shared/MDB_Attach.lua、client/MDB_AttachClient.lua、IG_UI 翻譯）。
--   lua scripts/test_attach.lua             四層定義互相對得上、伺服器有 AttachedLocations、DoParam 清單、座標換算、翻譯鍵
--   lua scripts/test_attach.lua --mutants   另對 MOD 檔案植入錯誤，確認測試抓得到
-- 有遊戲本體時（PZ_PATH，預設 D:/SteamLibrary/steamapps/common/ProjectZomboid）另對原版腳本核對：
-- 加 AttachmentType 的物品原本沒有這欄、借來的模型存在、每款背包的穿戴網格和家族相同。沒有就略過那幾項。
-- 執行目錄：repo 根。

local MEDIA = "MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42/42/media/"
local TRANSLATE = MEDIA .. "lua/shared/Translate/"
local F = {
    SHARED = MEDIA .. "lua/shared/MDB_Attach.lua",
    CLIENT = MEDIA .. "lua/client/MDB_AttachClient.lua",
    REINF = MEDIA .. "scripts/MDB_Reinforced.txt",
    EN = TRANSLATE .. "EN/IG_UI.json",
    CH = TRANSLATE .. "CH/IG_UI.json",
}
local LANGS = { "AR", "CH", "CN", "DE", "EN", "ES", "ES_CL", "ES_MX", "FR", "JP", "KO", "PL", "PT", "PTBR", "RU", "TR" }
local PZ = (os.getenv("PZ_PATH") or "D:/SteamLibrary/steamapps/common/ProjectZomboid"):gsub("\\", "/")

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
        for k in pairs(blocks(readRaw(root .. n), "model")) do vanilla.models[k] = true end
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
    local a = { id = id, offset = newVec(), rotate = newVec() }
    function a:getId() return self.id end
    function a:setBone(b) self.bone = b end
    function a:getOffset() return self.offset end
    function a:getRotate() return self.rotate end
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
            -- 原版 model（FIX 校正的對象）用到才建；身體兩個先建好
            getModelScript = function(_, n)
                if not env.models[n] and n:match("^Base%.") then env.models[n] = newModelScript(n) end
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

-- 強化版物品：MDB_Reinforced.txt 裡的每一件；外加原版物品。Base.Doll 假裝已有 StaticModel（驗「有就不蓋」）；
-- Base.BorisBadger 假裝寫了不存在的模型、解析成「???.」（Bag Upgrade Plus 並存時的樣子），驗「畫不出來就改借」
local SEED_STATIC = { ["Base.Doll"] = "SomeoneElsesDoll", ["Base.BorisBadger"] = "???.PlushieBadger_Static" }
local function seedItems(reinforced, attachItems)
    for name in pairs(reinforced) do env.items["MinidoracatBags." .. name] = newScriptItem("MinidoracatBags." .. name) end
    for ft in pairs(attachItems) do env.items[ft] = newScriptItem(ft, SEED_STATIC[ft]) end
end

local load = loadstring or load

-- Bag Upgrade Plus 有額外掛點的 28 款（BUPResearch 第 1.1 節；書包只有原版床捲，不動）
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
-- 家族 → 原版穿戴網格（clothingItems/<ClothingItem>.xml 的 m_MaleModel）
local MESH = { Alice = "m_alice_pack", Duffel = "m_duffelbag", Hiking = "m_hikingbag", BigHiking = "m_bighikingbag" }

local function suite()
    resetEnv()
    local reinforced = blocks(readFile(F.REINF), "item")
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
    seedItems(reinforced, attachItems)
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
    for b, set in pairs(BUP_BAGS) do
        local f = bagFam[b]
        if not f or table.concat(f.slots, ",") ~= table.concat(BUP_SETS[set], ",") then setOk = false end
    end
    check("Bag Upgrade Plus 的 28 款各歸一個家族，掛點組合照 BUP（ALICE、行李袋、登山包三種）", setOk)
    check("書包不加掛點", bagFam.Bag_Schoolbag == nil)

    -- AttachmentsProvided：保留強化版原本的床捲掛點，接上本 MOD 的掛點
    local apOk, missing = true, {}
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, b in ipairs(f.bags) do
            local name = b .. "_Reinforced"
            local base = field(reinforced[name], "AttachmentsProvided")
            local want = {}
            if base then want[1] = base end
            for _, s in ipairs(f.slots) do want[#want + 1] = MDB.attachSlotType(f.name, s) end
            local it = env.items["MinidoracatBags." .. name]
            if not reinforced[name] then missing[#missing + 1] = name end
            if not it or it.params.AttachmentsProvided ~= table.concat(want, ";") then apOk = false end
            if (base or false) ~= (f.base or false) then apOk = false end
        end
    end
    check("強化版都存在（" .. table.concat(missing, ",") .. "）", #missing == 0)
    check("AttachmentsProvided 保留原本的床捲掛點、接上家族的全部掛點", apOk)

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
    for ft, m in pairs(MDB.ATTACH_STATIC) do
        if not MDB.ATTACH_ITEMS[ft] or not m:match("^Base%.") then staticOk = false end
    end
    check("每個加 AttachmentType 的原版物品都有掛點收", atOk)
    check("沒有 StaticModel 或模型不存在（???.）的才借模型（全名），已有的不蓋", staticOk)
    local onlyTwo = true
    for _, it in pairs(env.items) do
        for k in pairs(it.params) do
            if k ~= "AttachmentType" and k ~= "StaticModel" and k ~= "AttachmentsProvided" then onlyTwo = false end
        end
    end
    check("DoParam 只動 AttachmentType、StaticModel、AttachmentsProvided", onlyTwo)
    check("飲料與玩偶都有：瓶、罐、玩偶、娃娃",
        MDB.ATTACH_ITEMS["Base.WaterBottle"] == "WaterBottle" and MDB.ATTACH_ITEMS["Base.Pop"] == "Sodacan"
        and MDB.ATTACH_ITEMS["Base.Spiffo"] == "SpiffoPlushie" and MDB.ATTACH_ITEMS["Base.Doll"] == "Doll")

    -- 原版核對
    local v = loadVanilla()
    if v then
        local bad = {}
        for ft in pairs(MDB.ATTACH_ITEMS) do
            local body = v.items[ft:match("%.(.+)$")]
            if not body then bad[#bad + 1] = ft .. "(沒有)"
            elseif field(body, "AttachmentType") then bad[#bad + 1] = ft .. "(已有 AttachmentType)" end
        end
        check("原版核對：加 AttachmentType 的物品都存在、原本沒有 AttachmentType " .. table.concat(bad, ","), #bad == 0)
        bad = {}
        for ft, m in pairs(MDB.ATTACH_STATIC) do
            local body = v.items[ft:match("%.(.+)$")]
            if field(body, "StaticModel") or not v.models[m:match("%.(.+)$")] then bad[#bad + 1] = ft end
        end
        check("原版核對：借模型的物品原本沒有 StaticModel、借的模型存在 " .. table.concat(bad, ","), #bad == 0)
        bad = {}
        for b, f in pairs(bagFam) do
            local ci = field(v.items[b], "ClothingItem")
            local xml = ci and readRaw(PZ .. "/media/clothing/clothingItems/" .. ci .. ".xml") or ""
            local mesh = xml:match("<m_MaleModel>[^<]-([%w_]+)</m_MaleModel>")
            if not mesh or mesh:lower() ~= MESH[f.name] then bad[#bad + 1] = b .. "(" .. tostring(mesh) .. ")" end
        end
        check("原版核對：每款背包的穿戴網格和家族相同（座標照網格算）" .. table.concat(bad, ","), #bad == 0)
        bad = {}
        local famOfMesh = {}
        for name, f in pairs(fams) do famOfMesh[MESH[name]] = f end
        for name in pairs(reinforced) do
            local src = name:gsub("_Reinforced$", "")
            local ci = v.items[src] and field(v.items[src], "ClothingItem")
            local xml = ci and readRaw(PZ .. "/media/clothing/clothingItems/" .. ci .. ".xml") or ""
            local mesh = xml:match("<m_MaleModel>[^<]-([%w_]+)</m_MaleModel>")
            local f = mesh and famOfMesh[mesh:lower()]
            if f and bagFam[src] ~= f then bad[#bad + 1] = src .. "(" .. f.name .. ")" end
        end
        check("原版核對：強化版只要穿戴網格是某個家族的，就在那個家族（座標照網格共用）" .. table.concat(bad, ","), #bad == 0)
    else
        io.write("  SKIP  原版核對（找不到 " .. PZ .. "）\n")
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
    check("每個家族的每個掛點都有快捷列定義，接受的類型對到伺服器也登記過的 AttachedLocation", defOk and #ISHotbarAttachDefinition == 31)

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
            end)
            if want == 0 or #ms.list ~= want then fixOk = false end
            fixN = fixN + 1
        end
    end
    check("模型自身校正（" .. fixN .. " 個模型）只加在指定擺法、同名、不綁骨頭，旋轉與位移照表，重載不重複", fixOk and fixN > 0)
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
            if not v.models[model:match("%.(.+)$")] or not used[model .. "|" .. fix[1]] then bad[#bad + 1] = model end
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
        { name = "少一個家族掛點", file = "SHARED", from = '"Plushie", "UmbrellaR", "Flashlight" } },\n    { name = "Duffel"', to = '"Plushie", "UmbrellaR" } },\n    { name = "Duffel"' },
        { name = "旅行登山包歸大登山包", file = "SHARED", from = 'bags = { "Bag_NormalHikingBag", "Bag_HikingBag_Travel" }', to = 'bags = { "Bag_NormalHikingBag" }' },
        { name = "漏一款行李袋", file = "SHARED", from = '"Bag_FoodSnacks", "Bag_ToolBag", "Bag_DuffelBagTINT" }', to = '"Bag_FoodSnacks", "Bag_DuffelBagTINT" }' },
        { name = "強化版前綴錯", file = "SHARED", from = '"MinidoracatBags." .. bag .. "_Reinforced"', to = '"Base." .. bag' },
        { name = "沒加 AttachmentType", file = "SHARED", from = 's:DoParam("AttachmentType = " .. kind)', to = "" },
        { name = "已有 StaticModel 也蓋", file = "SHARED", from = 'if model and (not cur or cur:sub(1, 4) == "???.") then', to = "if model then" },
        { name = "不存在的模型當成已有", file = "SHARED", from = '(not cur or cur:sub(1, 4) == "???.")', to = "not cur" },
        { name = "借模型沒寫全名", file = "SHARED", from = '["Base.Spiffo"] = "Base.SpiffoPlushie"', to = '["Base.Spiffo"] = "SpiffoPlushie"' },
        { name = "飲料類型沒有掛點收", file = "SHARED", from = 'local BOTTLES = { WaterBottle = "Bottle",', to = 'local BOTTLES = { WaterBottleX = "Bottle",' },
        { name = "加了已有 AttachmentType 的原版物品", file = "SHARED", from = '["Base.Flask"] = "WaterBottle",', to = '["Base.Flask"] = "WaterBottle", ["Base.Hammer"] = "Hammer",' },
        { name = "定義缺 animset", file = "CLIENT", from = 'animset = "back"', to = 'animset = "belt left"' },
        { name = "定義的位置名稱錯", file = "CLIENT", from = "attachments[itemType] = MDB.attachLocation(f.name, slot, pose)", to = "attachments[itemType] = pose" },
        { name = "模型掛點換骨頭", file = "CLIENT", from = '"Bip01_BackPack", off, rot)', to = '"Bip01_Spine1", off, rot)' },
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
        { name = "家族漏同網格的背包", file = "SHARED", from = '"Bag_ToolBag", "Bag_DuffelBagTINT" }', to = '"Bag_ToolBag" }' },
        { name = "掛得上也改提示", file = "CLIENT", from = "local tip = opt and opt.notAvailable and opt.toolTip", to = "local tip = opt and opt.toolTip" },
        { name = "自身校正沒套位移", file = "CLIENT", from = "local off = { fix[5] or 0, fix[6] or 0, fix[7] or 0 }", to = "local off = { 0, 0, 0 }" },
        { name = "自身校正加到每種擺法", file = "CLIENT", from = "if pose == fix[1] then upsert", to = "if true then upsert" },
        { name = "自身校正擺法打錯", file = "CLIENT", from = '["Base.Doll"] = { "Plushie", 90', to = '["Base.Doll"] = { "Plushy", 90' },
        { name = "自身校正寫成物品名", file = "CLIENT", from = '["Base.Pancho"] = {', to = '["Base.PanchoDog"] = {' },
        { name = "翻譯缺鍵", file = "EN", from = '"IGUI_HotbarAttachment_MDB_DuffelBottleR"', to = '"IGUI_HotbarAttachment_MDB_DuffelBottleX"' },
        { name = "繁中缺鍵", file = "CH", from = '"IGUI_HotbarAttachment_MDB_AliceSlot1"', to = '"IGUI_HotbarAttachment_MDB_AliceSlotA"' },
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
