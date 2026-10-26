-- 離線測試：新背包（物品腳本、製作與升級配方、升級 Lua、放入限制、戰利品、殭屍死亡掉落、沙盒選項、翻譯鍵）。
--   lua scripts/test_newbags.lua             行為與腳本不變式
--   lua scripts/test_newbags.lua --mutants   另對 MOD 檔案植入錯誤，確認測試抓得到
-- 用假的 PZ 全域載入真正的 MOD Lua；腳本不變式直接解析 MOD 的 .txt 與原版 media/scripts、clothing、fileGuidTable。
-- 引擎模擬：
-- - InventoryContainer.getCapacity＝min(容量, 50, (int)(50－背包重量))（InventoryContainer.java:79-86、ItemContainer.java:158-170）；
--   setWeightReduction 夾在 0～100（InventoryContainer.java:138-141）。
-- - sendReplaceItemInContainer 只在伺服器有作用（LuaManager.java:12404-12412）。
-- - 換穿法的 ISClothingExtraAction.createItemNew 只搬 modData，新物品維持腳本預設容量（ISClothingExtraAction.lua:107-109）。
-- - OnTest 對每個符合輸入的候選物品各呼叫一次（CraftRecipeManager.java:781-783）。
-- - 原版 ProceduralDistributions.lua 原樣載入，Events.OnPreDistributionMerge（與單機讀檔的 OnInitGlobalModData）觸發後檢查清單。
-- 執行目錄：repo 根。

local PZ = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media/"
local MEDIA = "MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42/42/media/"
local TRANSLATE = MEDIA .. "lua/shared/Translate/"
local F = {
    UPG = MEDIA .. "lua/shared/MDB_Upgrade.lua",
    FIL = MEDIA .. "lua/shared/MDB_Filters.lua",
    LOOT = MEDIA .. "lua/server/MDB_Loot.lua",
    ZD = MEDIA .. "lua/server/MDB_ZombieDrops.lua",
    ITEMS = MEDIA .. "scripts/MDB_Items.txt",
    RECIPES = MEDIA .. "scripts/MDB_Recipes.txt",
    SANDBOX = MEDIA .. "sandbox-options.txt",
    GUIDTABLE = MEDIA .. "fileGuidTable.xml",
    MODELS = MEDIA .. "scripts/MDB_Models.txt",
    DAYPACK_XML = MEDIA .. "clothing/clothingItems/MDB_DayPack_Navy.xml",
    DAYPACK_LHAND_XML = MEDIA .. "clothing/clothingItems/MDB_DayPack_Olive_LHand.xml",
    CHESTRIG_XML = MEDIA .. "clothing/clothingItems/MDB_ScoutChestRig_Navy.xml",
    I18N_RECIPES = TRANSLATE .. "EN/Recipes.json",
    I18N_ITEMS = TRANSLATE .. "EN/ItemName.json",
    REIN = MEDIA .. "scripts/MDB_Reinforced.txt",
    REIN_XML = MEDIA .. "clothing/clothingItems/MDB_Bag_Satchel_Reinforced.xml",
}
-- conventions.md「介面語系」：12 種語言＋ES 的 AR／ES_CL／ES_MX、PTBR 的 PT
local LANGS = { "AR", "CH", "CN", "DE", "EN", "ES", "ES_CL", "ES_MX", "FR", "JP", "KO", "PL", "PT", "PTBR", "RU", "TR" }

local MUTATION
local function readFile(path, optional)
    local fh = io.open(path, "rb")
    if not fh then
        if optional then return nil end
        error("找不到檔案：" .. path)
    end
    local text = fh:read("*a")
    fh:close()
    if MUTATION and F[MUTATION.file] == path then
        local s, e = text:find(MUTATION.from, 1, true)
        if not s then error("突變片段不在原始碼中：" .. MUTATION.name) end
        text = text:sub(1, s - 1) .. MUTATION.to .. text:sub(e + 1)
    end
    return text
end
local function listFiles(dir, pattern)
    local out = {}
    local p = io.popen('dir /s /b "' .. dir:gsub("/", "\\") .. pattern .. '" 2>nul')
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local pass, fail = 0, 0
local quiet = false
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1 end
    if not quiet then io.write((cond and "  PASS  " or "  FAIL  ") .. name .. "\n") end
end

-- ===== 腳本解析 =====
local function stripComments(s) return (s:gsub("/%*.-%*/", "")) end
local function blockEnd(text, open)
    local depth, pos = 0, open
    while true do
        local s, _, c = text:find("([{}])", pos)
        if not s then return #text end
        depth = depth + (c == "{" and 1 or -1)
        if depth == 0 then return s end
        pos = s + 1
    end
end
-- 回傳 { name, module, fields（第一層 key = value）, lines（內層各行，含所屬區段） }
local function parseBlocks(text, kind)
    text = stripComments(text)
    local modules = {}
    for mpos, mname in text:gmatch("()module%s+([%w_]+)") do modules[#modules + 1] = { mpos, mname } end
    local out = {}
    for spos, name, open in text:gmatch("()%f[%w]" .. kind .. "%s+([%w_]+)%s*(){") do
        local body = text:sub(open + 1, blockEnd(text, open) - 1)
        local module
        for _, m in ipairs(modules) do if m[1] < spos then module = m[2] end end
        local b = { name = name, module = module, fields = {}, lines = {} }
        local depth, section = 0, nil
        for line in (body .. "\n"):gmatch("([^\n]*)\n") do
            if depth == 0 then
                local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*,?%s*$")
                if k then b.fields[k] = v end
                local sec = line:match("^%s*(%a+)%s*$")
                if sec then section = sec end
            elseif depth == 1 and line:match("%S") and not line:match("^%s*[{}]%s*$") then
                b.lines[#b.lines + 1] = { section = section, text = line:match("^%s*(.-)%s*,?%s*$") }
            end
            local _, opens = line:gsub("{", "")
            local _, closes = line:gsub("}", "")
            depth = depth + opens - closes
        end
        out[#out + 1] = b
    end
    return out
end

-- 原版（不突變，只解析一次）
local VAN = { items = {}, tags = {}, clothing = {}, guids = {}, outfits = {} }
for _, path in ipairs(listFiles(PZ .. "scripts/", "*.txt")) do
    local fh = io.open(path, "rb"); local text = fh:read("*a"); fh:close()
    for _, b in ipairs(parseBlocks(text, "item")) do
        VAN.items[(b.module or "Base") .. "." .. b.name] = b
        for t in (b.fields.Tags or ""):gmatch("[^;]+") do VAN.tags[t:lower()] = true end
    end
end
for _, path in ipairs(listFiles(PZ .. "clothing/clothingItems/", "*.xml")) do
    VAN.clothing[path:match("([^\\/]+)%.xml$")] = true
end
do
    local fh = io.open(PZ .. "fileGuidTable.xml", "rb"); local t = fh:read("*a"); fh:close()
    for g in t:gmatch("<guid>%s*(.-)%s*</guid>") do VAN.guids[g:lower()] = true end
    fh = io.open(PZ .. "clothing/clothing.xml", "rb"); t = fh:read("*a"); fh:close()
    for n in t:gmatch("<m_Name>(.-)</m_Name>") do VAN.outfits[n] = true end
end

-- ===== 規格（AGENTS.md「設計定案」的表） =====
local MODELS = {
    ToolBeltPouch = { eq = "base:fannypackfront", cap = { 3, 49 }, wr = { 80, 100 }, w = 0.3, run = 0.98 },
    MedicHipPouch = { eq = "base:fannypackback", cap = { 4, 49 }, wr = { 85, 100 }, w = 0.3, run = 0.99, accept = "MDB.acceptFirstAid" },
    AmmoBandolier = { eq = "base:ammostrap", cap = { 4, 49 }, wr = { 85, 100 }, w = 0.3, run = 0.98, accept = "MDB.acceptAmmo",
        tags = "base:reloadfastbullets;base:reloadfastmagazines;base:reloadfastshells" },
    CourierSatchel = { eq = "base:satchel", cap = { 14, 49 }, wr = { 70, 100 }, w = 0.6, run = 0.99 },
    DayPack = { eq = "base:back", cap = { 20, 49 }, wr = { 75, 100 }, w = 0.8, run = 0.97, attach = "BedrollBottom" },
    ExpeditionPack = { eq = "base:back", cap = { 30, 49 }, wr = { 80, 100 }, w = 1.0, run = 0.95, attach = "BedrollBottomBig" },
    ScoutChestRig = { eq = "base:webbing", cap = { 6, 49 }, wr = { 85, 100 }, w = 0.5, run = 0.98, maxSize = "1.3" },
}
local SKINS = { "Navy", "Olive" }
-- 有強化版的 38 種原版背包（全是 Base.）
local REIN_SPEC = {
    "Bag_SurvivorBag", "Bag_ALICEpack", "Bag_ALICEpack_Army", "Bag_ALICEpack_DesertCamo", "Bag_DuffelBag", "Bag_MedicalBag",
    "Bag_Military", "Bag_Police", "Bag_Sheriff", "Bag_SWAT", "Bag_BreakdownBag", "Bag_BurglarBag", "Bag_BaseballBag",
    "Bag_TennisBag", "Bag_WeaponBag", "Bag_InmateEscapedBag", "Bag_MoneyBag", "Bag_WorkerBag", "Bag_ShotgunBag",
    "Bag_ShotgunSawnoffBag", "Bag_ShotgunDblBag", "Bag_ShotgunDblSawnoffBag", "Bag_FoodCanned", "Bag_FoodSnacks", "Bag_ToolBag",
    "Bag_FannyPackBack", "Bag_FannyPackFront", "Bag_HydrationBackpack", "Bag_HydrationBackpack_Camo", "Bag_NormalHikingBag",
    "Bag_BigHikingBag", "Bag_HikingBag_Travel", "Bag_Schoolbag", "Bag_Satchel", "Bag_Satchel_Fishing", "Bag_Satchel_Medical",
    "Bag_Satchel_Military", "Bag_SheetSlingBag",
}
local LOOT_SPEC = {
    { "PoliceStorageArmor", "_Navy", { DayPack = 1, CourierSatchel = 1, ScoutChestRig = 1, ToolBeltPouch = 1.5, AmmoBandolier = 1, MedicHipPouch = 0.5, ExpeditionPack = 0.3 } },
    { "PoliceStorageGuns", "_Navy", { AmmoBandolier = 3, ScoutChestRig = 1.5, ToolBeltPouch = 1.5, DayPack = 1, CourierSatchel = 1, ExpeditionPack = 0.2 } },
    { "PoliceLockers", "_Navy", { ToolBeltPouch = 1.5, MedicHipPouch = 0.2, CourierSatchel = 0.2, DayPack = 0.2, ScoutChestRig = 0.2, AmmoBandolier = 0.2, ExpeditionPack = 0.05 } },
    { "PoliceStorageOutfit", "_Navy", { DayPack = 0.1, CourierSatchel = 0.1, ToolBeltPouch = 0.2 } },
    { "ArmySurplusBackpacks", "_Olive", { DayPack = 10, CourierSatchel = 10, ScoutChestRig = 6, ToolBeltPouch = 6, MedicHipPouch = 6, AmmoBandolier = 4, ExpeditionPack = 4 } },
    { "ArmyStorageOutfit", "_Olive", { DayPack = 0.3, CourierSatchel = 0.3, ToolBeltPouch = 0.3, ScoutChestRig = 0.2, AmmoBandolier = 0.2, MedicHipPouch = 0.1, ExpeditionPack = 0.05 } },
    { "LockerArmyBedroom", "_Olive", { DayPack = 0.1, ScoutChestRig = 0.1, CourierSatchel = 0.1, ExpeditionPack = 0.03 } },
    { "ArmyBunkerLockers", "_Olive", { DayPack = 0.03, ScoutChestRig = 0.02, ExpeditionPack = 0.01 } },
    { "ArmyStorageMedical", "_Olive", { MedicHipPouch = 0.3 } },
    { "HospitalLockers", "_Olive", { MedicHipPouch = 1, DayPack = 0.2, CourierSatchel = 0.1 } },
    { "HospitalRoomShelves", "_Olive", { MedicHipPouch = 0.5 } },
    { "NurseOutfit", "_Olive", { MedicHipPouch = 1 } },
}
local OUTFIT_SPEC = {
    Police = "_Navy", PoliceRiot = "_Navy", PoliceState = "_Navy", Police_SWAT = "_Navy", Sheriff_Deputy = "_Navy",
    ArmyCamoDesert = "_Olive", ArmyCamoGreen = "_Olive", ArmyInstructor = "_Olive", ArmyServiceUniform = "_Olive",
    Doctor = "medic", Nurse = "medic", AmbulanceDriver = "medic",
}
local SANDBOX_SPEC = {
    LockLegacyBags = { "boolean", "true" }, MaxTier = { "integer", "3", "0", "3" },
    FullCapacityPercent = { "integer", "100", "0", "100" }, FullWeightReduction = { "integer", "100", "0", "100" },
    LootMultiplier = { "double", "1.0", "0.0", "10.0" },
}

-- ===== 假引擎 =====
local env = {}
local function resetEnv()
    env = { server = false, client = false, sent = {}, replaced = {}, rand = {}, randCalls = 0, printed = {}, parsed = 0 }
    Events = setmetatable({}, { __index = function(t, k)
        local e = { handlers = {} }
        function e.Add(f) e.handlers[#e.handlers + 1] = f end
        rawset(t, k, e)
        return e
    end })
    MDB = nil
    SandboxVars = { MinidoracatBags = { LockLegacyBags = true, MaxTier = 3, FullCapacityPercent = 100,
        FullWeightReduction = 100, LootMultiplier = 1 } }
    -- MDB_Upgrade 會 require 並包住原版的 createItemNew；每次載入給新表，突變才不會吃到上一輪的包裝。
    -- 照原版（ISClothingExtraAction.lua:66-112）搬內容物、改名、液體（依新容量截斷）、modData（先清空再複製，InventoryItem.java:3003-3011）
    ISClothingExtraAction = {}
    function ISClothingExtraAction:createItemNew(item, newItem)
        if env.failCopy then error("copy failed") end
        for _, c in ipairs(item.contents or {}) do newItem.contents[#newItem.contents + 1] = c end
        item.contents = {}
        newItem.name = item.name
        if item.fc and newItem.fc then newItem.fc:copyFluidsFrom(item.fc) end
        if item:hasModData() then
            newItem.md = {}
            for k, v in pairs(item:getModData()) do newItem.md[k] = v end
        end
        return newItem
    end
    package.loaded["TimedActions/ISClothingExtraAction"] = true
end
function isServer() return env.server end
function isClient() return env.client end
ItemPickerJava = { Parse = function() env.parsed = env.parsed + 1 end }
function sendReplaceItemInContainer(c, a, b) env.sent[#env.sent + 1] = { c, a, b } end
function replaceItemInContainer(c, a, b) env.replaced[#env.replaced + 1] = { c, a, b } end
function copyClothingItem(item, newItem) ISClothingExtraAction:createItemNew(item, newItem) end
function instanceof(o, cls) return type(o) == "table" and rawget(o, "__class") == cls end
function ZombRand(n)
    env.randCalls = env.randCalls + 1
    local v = table.remove(env.rand, 1) or 0
    assert(v < n, "ZombRand stub value out of range")
    return v
end
ItemTag = setmetatable({ AMMO = "base:ammo", SHOTGUN_SHELL = "base:shotgunshell" },
    { __index = function(_, k) error("unknown ItemTag " .. tostring(k)) end })
local rawPrint = print
function print(...) env.printed[#env.printed + 1] = table.concat({ ... }, " ") end

local function diag(line) if not quiet then rawPrint(line) end end

local function loadLua(key) assert(load(readFile(F[key]), "@" .. F[key]))() end
local function loadAll()
    resetEnv()
    loadLua("FIL"); loadLua("UPG"); loadLua("LOOT"); loadLua("ZD")
end
local function resolve(path)
    local v = _G
    for part in path:gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

local function newContainer()
    local c = { items = {} }
    function c:AddItem(i) self.items[#self.items + 1] = i; i.container = self; return i end
    function c:Remove(i)
        for k, v in ipairs(self.items) do if v == i then table.remove(self.items, k); i.container = nil; return end end
    end
    return c
end
local CONTAINER = newContainer()
local PLAYER = { getInventory = function() return CONTAINER end }
-- weight＝腳本自重；instanceWeight 模擬 getActualWeight()（伺服器上顯示名稱等於全名時回 0，InventoryItem.java:2740-2742）
local function newBag(cap, wr, weight, fullType)
    local b = { __class = "InventoryContainer", cap = cap, wr = wr, weight = weight, md = {}, container = CONTAINER,
        contents = {}, fullType = fullType, name = "name of " .. tostring(fullType), custom = false }
    local script = {}
    function script:getActualWeight() return weight end
    function script:getDisplayName() return "name of " .. tostring(fullType) end
    function b:getDisplayName() return self.name end
    function b:setName(n) self.name = n end
    function b:isCustomName() return self.custom end
    function b:setCustomName(c) self.custom = c end
    function b:hasModData() return next(self.md) ~= nil end
    function b:getModData() return self.md end
    function b:getCapacity() return math.min(self.cap, 50, math.floor(50 - self.weight)) end
    function b:setCapacity(c) self.cap = c end
    function b:getWeightReduction() return self.wr end
    function b:setWeightReduction(w) self.wr = math.max(0, math.min(100, w)) end
    function b:getActualWeight() return self.instanceWeight or self.weight end
    function b:getScriptItem() return script end
    function b:getContainer() return self.container end
    function b:getFluidContainer() return self.fc end
    function b:getFullType() return self.fullType end
    return b
end
-- FluidContainer：setCapacity 下限 0.05，縮小時按比例截斷（FluidContainer.java:683-696）；
-- copyFluidsFrom 先清空再加，超過容量的截掉（:179-194、:929-932）
local function newFluid(capacity, amount)
    local fc = { capacity = capacity, amount = amount or 0 }
    function fc:getCapacity() return self.capacity end
    function fc:getAmount() return self.amount end
    function fc:setCapacity(c)
        local old = self.capacity
        self.capacity = math.max(c, 0.05)
        if self.amount > self.capacity then self.amount = self.capacity * self.amount / old end
    end
    function fc:copyFluidsFrom(o) self.amount = math.min(o.amount, self.capacity) end
    return fc
end
-- instanceItem：照腳本（本 MOD 的物品與強化版、原版）建背包；腳本由 suite 解析後放進 SCRIPT_BLOCKS
local SCRIPT_BLOCKS = {}
function instanceItem(full)
    local s = SCRIPT_BLOCKS[full] or VAN.items[full]
    assert(s, "instanceItem: unknown item " .. tostring(full))
    local b = newBag(tonumber(s.fields.Capacity), tonumber(s.fields.WeightReduction), tonumber(s.fields.Weight), full)
    b.container = nil
    for _, l in ipairs(s.lines) do
        local c = l.text:match("^Capacity = ([%d.]+)$")   -- 第一層以下只有 FluidContainer 元件寫 Capacity
        if c then b.fc = newFluid(tonumber(c)) end
    end
    return b
end
local function vanillaItem(fullType)
    local b = VAN.items[fullType]
    assert(b, "vanilla item missing: " .. fullType)
    local tags = {}
    for t in (b.fields.Tags or ""):gmatch("[^;]+") do tags[t:lower()] = true end
    return {
        getDisplayCategory = function() return b.fields.DisplayCategory end,
        hasTag = function(_, tag) assert(tag ~= nil, "hasTag(nil)"); return tags[tag] == true end,
    }
end
local function javaList(arr)
    return { size = function() return #arr end, get = function(_, i) return arr[i + 1] end }
end

-- ===== 套件 =====
local function suite()
    local items = {}
    for _, b in ipairs(parseBlocks(readFile(F.ITEMS), "item")) do items[b.module .. "." .. b.name] = b end
    local recipes = {}
    for _, b in ipairs(parseBlocks(readFile(F.RECIPES), "craftRecipe")) do recipes[b.name] = b end
    local rein, reinRecipes = {}, {}
    for _, b in ipairs(parseBlocks(readFile(F.REIN), "item")) do rein[b.module .. "." .. b.name] = b end
    for _, b in ipairs(parseBlocks(readFile(F.REIN), "craftRecipe")) do reinRecipes[b.name] = b end
    SCRIPT_BLOCKS = {}
    for full, b in pairs(items) do SCRIPT_BLOCKS[full] = b end
    for full, b in pairs(rein) do SCRIPT_BLOCKS[full] = b end
    local function exists(full)
        return items[full] ~= nil or rein[full] ~= nil or VAN.items[full] ~= nil
    end

    -- 1. 物品欄位
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    check("items: exactly 14", count == 14)
    for k, s in pairs(MODELS) do
        for _, skin in ipairs(SKINS) do
            local full = "MinidoracatBags." .. k .. "_" .. skin
            local b = items[full]
            local f = b and b.fields or {}
            check(full .. ": fields match table", b ~= nil and f.CanBeEquipped == s.eq and tonumber(f.Capacity) == s.cap[1]
                and tonumber(f.WeightReduction) == s.wr[1] and tonumber(f.Weight) == s.w and tonumber(f.RunSpeedModifier) == s.run
                and f.ItemType == "base:container" and f.AcceptItemFunction == s.accept and f.AttachmentsProvided == s.attach
                and f.MaxItemSize == s.maxSize and f.ClothingItem == "MDB_" .. k .. "_" .. skin)
            if s.tags then check(full .. ": tags exact, no base:ammocase", f.Tags == s.tags) end
        end
    end

    -- 2. ClothingItem：不與原版同名、有 XML、GUID 對得上且不重複
    local guidOf = {}
    for path, g in readFile(F.GUIDTABLE):gmatch("<path>%s*(.-)%s*</path>%s*<guid>%s*(.-)%s*</guid>") do guidOf[path] = g:lower() end
    local seenGuid, clothingOk, dupOk = {}, true, true
    for full, b in pairs(items) do
        local ci = b.fields.ClothingItem
        local xmlPath = "media/clothing/clothingItems/" .. tostring(ci) .. ".xml"
        local xml = readFile(MEDIA .. "clothing/clothingItems/" .. tostring(ci) .. ".xml", true)
        local g = xml and xml:match("<m_GUID>%s*(.-)%s*</m_GUID>")
        local ok = ci and not VAN.clothing[ci] and xml and g and guidOf[xmlPath] == g:lower() and not VAN.guids[g:lower()]
        if not ok then clothingOk = false; diag("    clothing problem: " .. full .. " " .. tostring(ci)) end
        if g then
            if seenGuid[g:lower()] then dupOk = false end
            seenGuid[g:lower()] = true
        end
    end
    check("clothing: unique non-vanilla names, XML present, GUID registered", clothingOk)
    check("clothing: GUIDs unique and not vanilla", dupOk)

    -- 2a. 強化版（scripts/gen_reinforced.py 產生）：剛好 38 款；欄位逐一照原版，只差自重 0.1、跑速 1.0、自己的 ClothingItem、
    --     腰包 ClothingItemExtra 指向對方的強化版；FluidContainer 照原版；XML 照原版只換 GUID（全新、登記、不重複）
    local reinCount, reinFieldsOk, reinXmlOk = 0, true, true
    for _ in pairs(rein) do reinCount = reinCount + 1 end
    check("reinforced: exactly 38 items", reinCount == #REIN_SPEC)
    local function plainXml(x) return (x:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("<m_GUID>[^<]*</m_GUID>", "")) end
    for _, s in ipairs(REIN_SPEC) do
        local full = "MinidoracatBags." .. s .. "_Reinforced"
        local r, v = rein[full], VAN.items["Base." .. s]
        local ok = r ~= nil and v ~= nil
        if ok then
            local want = {}
            for k, val in pairs(v.fields) do want[k] = val end
            want.Weight, want.RunSpeedModifier, want.ClothingItem = "0.1", "1.0", "MDB_" .. s .. "_Reinforced"
            if want.ClothingItemExtra then
                want.ClothingItemExtra = want.ClothingItemExtra:gsub("^Base%.(.+)$", "MinidoracatBags.%1_Reinforced")
            end
            for k, val in pairs(want) do
                if r.fields[k] ~= val then ok = false; diag("    reinforced " .. s .. " " .. k .. "=" .. tostring(r.fields[k]) .. " want " .. val) end
            end
            for k in pairs(r.fields) do if want[k] == nil then ok = false; diag("    reinforced " .. s .. " extra field " .. k) end end
            ok = ok and #r.lines == #v.lines
            for i, l in ipairs(v.lines) do ok = ok and r.lines[i] ~= nil and r.lines[i].text == l.text end
        end
        if not ok then reinFieldsOk = false end
        local ci = "MDB_" .. s .. "_Reinforced"
        local xml = readFile(MEDIA .. "clothing/clothingItems/" .. ci .. ".xml", true)
        local vxml = v and readFile(PZ .. "clothing/clothingItems/" .. v.fields.ClothingItem .. ".xml", true)
        local g = xml and xml:match("<m_GUID>%s*(.-)%s*</m_GUID>")
        if not (xml and vxml and plainXml(xml) == plainXml(vxml) and not VAN.clothing[ci] and g
            and guidOf["media/clothing/clothingItems/" .. ci .. ".xml"] == g:lower() and not VAN.guids[g:lower()]
            and not seenGuid[g:lower()]) then
            reinXmlOk = false; diag("    reinforced clothing problem: " .. ci)
        end
        if g then seenGuid[g:lower()] = true end
    end
    check("reinforced: fields copy vanilla except Weight 0.1, RunSpeedModifier 1.0, own ClothingItem, fanny extra -> reinforced",
        reinFieldsOk)
    check("reinforced: ClothingItem XML = vanilla XML with a new registered unique GUID, name not vanilla", reinXmlOk)
    check("reinforced: never in loot or zombie drops", not readFile(F.LOOT):find("Reinforced", 1, true)
        and not readFile(F.ZD):find("Reinforced", 1, true))
    -- 還原與「已升級原版背包改成強化版」：背包 keep＋不能穿著、沒有產出，換型在 OnCreate
    local function bagSet(r)
        local set, n, line = {}, 0, nil
        for _, l in ipairs(r and r.lines or {}) do
            if l.section == "inputs" and l.text:find("mode:keep flags[IsNotWorn]", 1, true) then line = l.text end
        end
        for x in (line and line:match("%[(.-)%]") or ""):gmatch("[^;]+") do set[x] = true; n = n + 1 end
        return set, n
    end
    local function hasLine(r, text)
        for _, l in ipairs(r and r.lines or {}) do if l.text == text then return true end end
        return false
    end
    local function noOutputs(r)
        for _, l in ipairs(r and r.lines or {}) do if l.section == "outputs" then return false end end
        return r ~= nil
    end
    local rset, rn = bagSet(reinRecipes.MDB_RestoreReinforced)
    local mset, mn = bagSet(reinRecipes.MDB_ReinforceUpgradedBag)
    local covered = rn == #REIN_SPEC and mn == #REIN_SPEC
    for _, s in ipairs(REIN_SPEC) do covered = covered and rset["MinidoracatBags." .. s .. "_Reinforced"] and mset["Base." .. s] end
    local rr, mr = reinRecipes.MDB_RestoreReinforced, reinRecipes.MDB_ReinforceUpgradedBag
    local recipeCount = 0
    for _ in pairs(reinRecipes) do recipeCount = recipeCount + 1 end
    check("restore / reinforce-upgraded recipes: exactly these 2, bag lists cover all 38 (reinforced / vanilla)",
        recipeCount == 2 and covered == true)
    check("MDB_RestoreReinforced: scissors kept, no other input, no outputs, MDB.onSwapKeepTier, no OnTest",
        rr ~= nil and #rr.lines == 2 and hasLine(rr, "item 1 tags[base:scissors] mode:keep flags[IsNotDull;MayDegradeLight]")
        and noOutputs(rr) and rr.fields.OnCreate == "MDB.onSwapKeepTier" and rr.fields.OnTest == nil)
    check("MDB_ReinforceUpgradedBag: needle kept, no outputs, OnTest MDB.onTestUpgraded, MDB.onSwapKeepTier",
        mr ~= nil and #mr.lines == 2 and hasLine(mr, "item 1 tags[base:sewingneedle] mode:keep") and noOutputs(mr)
        and mr.fields.OnTest == "MDB.onTestUpgraded" and mr.fields.OnCreate == "MDB.onSwapKeepTier")

    -- 2b. 自製資產的款式（scripts/blender/bags/build.py）：圖示、地面模型、左右手、穿戴模型、貼圖都指向 MOD 自己的檔，
    --     而且檔案存在。xml 的模型路徑要寫 media\ 開頭與副檔名（PopTemplateManager.java:272-275、FileTask_AbstractLoadModel.java:53-87）。
    --     scale 照各自借用的原版地面模型（models_items.txt／models_clothes.txt）；hands＝原版有手持模型的款式；
    --     alt＝原版有 m_Alt*Model 的款式（胸掛：穿外套時換用，PopTemplateManager.java:73-76），沒有的款式 XML 也不能有
    local OWN = {
        { name = "DayPack", scale = "0.4", hands = true },        -- HikingBag_Ground（models_items.txt:3664-3668）
        { name = "ExpeditionPack", scale = "0.4", hands = true }, -- BigHikingBag_Ground（models_items.txt:3601-3605）
        { name = "CourierSatchel", scale = "0.08", hands = true }, -- Satchel_Military_Ground（models_items.txt:8919-8924）
        { name = "ScoutChestRig", scale = "0.15", alt = true },   -- ChestRig_Ground（models_clothes.txt:1661-1666）
        { name = "MedicHipPouch", scale = "0.4" },                -- FannyPack_Ground（models_items.txt:3670-3674）
        { name = "ToolBeltPouch", scale = "0.4" },                -- FannyPack_Ground（models_items.txt:3670-3674）
        { name = "AmmoBandolier", scale = "0.4" },                -- AmmoStrap_Ground_Shells（models_items.txt:5241-5246）
    }
    local models = {}
    for _, b in ipairs(parseBlocks(readFile(F.MODELS), "model")) do models[b.module .. "." .. b.name] = b end
    local function fileExists(rel)
        local fh = io.open(MEDIA .. rel, "rb")
        if fh then fh:close() end
        return fh ~= nil
    end
    local function xmlOk(name, male, female, tex, alt)
        local xml = readFile(MEDIA .. "clothing/clothingItems/" .. name .. ".xml", true)
        if not xml then return false end
        local g = xml:match("<m_GUID>%s*(.-)%s*</m_GUID>")
        local texs = {}
        for t in xml:gmatch("<textureChoices>%s*(.-)%s*</textureChoices>") do texs[#texs + 1] = t end
        local function modelFile(tag)
            local p = xml:match("<" .. tag .. ">%s*(.-)%s*</" .. tag .. ">")
            return p and (p:gsub("\\", "/"):gsub("^media/", "")) or ""
        end
        local ok = g and guidOf["media/clothing/clothingItems/" .. name .. ".xml"] == g:lower() and not VAN.guids[g:lower()]
            and not VAN.clothing[name]
            and modelFile("m_MaleModel") == "models_X/Skinned/BackPacks/" .. male .. ".X" and fileExists(modelFile("m_MaleModel"))
            and modelFile("m_FemaleModel") == "models_X/Skinned/BackPacks/" .. female .. ".X" and fileExists(modelFile("m_FemaleModel"))
            and #texs == 1 and texs[1] == "Clothes\\Bag\\" .. tex and fileExists("textures/Clothes/Bag/" .. tex .. ".png")
            and (alt and modelFile("m_AltMaleModel") == "models_X/Skinned/BackPacks/" .. alt[1] .. ".X" and fileExists(modelFile("m_AltMaleModel"))
                and modelFile("m_AltFemaleModel") == "models_X/Skinned/BackPacks/" .. alt[2] .. ".X" and fileExists(modelFile("m_AltFemaleModel"))
                or not alt and modelFile("m_AltMaleModel") == "" and modelFile("m_AltFemaleModel") == "")
        if not ok then diag("    own-asset clothing problem: " .. name) end
        return ok
    end
    for _, own in ipairs(OWN) do
        local B = own.name
        for _, skin in ipairs(SKINS) do
            local f = (items["MinidoracatBags." .. B .. "_" .. skin] or { fields = {} }).fields
            local m = models[f.WorldStaticModel or ""]
            local P = "MDB_" .. B .. "_"
            check(B .. "_" .. skin .. ": own icon, ground model (no texture, scale " .. own.scale .. ")" .. (own.hands and ", hand ClothingItems" or ""),
                f.Icon == P .. skin and fileExists("textures/Item_" .. P .. skin .. ".png")
                and m ~= nil and fileExists("models_X/" .. tostring(m.fields.mesh) .. ".fbx") and m.fields.texture == nil
                and m.fields.scale == own.scale
                and (not own.hands or f.ReplaceInPrimaryHand == P .. skin .. "_RHand holdingbagright"
                    and f.ReplaceInSecondHand == P .. skin .. "_LHand holdingbagleft"))
            local tex = P .. skin
            check(B .. "_" .. skin .. ": worn" .. (own.alt and " (with alt)" or "") .. (own.hands and " and hand" or "") .. " ClothingItems use own .X and one own texture",
                xmlOk(P .. skin, P .. "M", P .. "F", tex, own.alt and { P .. "ALT_M", P .. "ALT_F" })
                and (not own.hands or xmlOk(P .. skin .. "_RHand", P .. "RHand", P .. "RHand", tex)
                    and xmlOk(P .. skin .. "_LHand", P .. "LHand", P .. "LHand", tex)))
        end
    end

    -- 3. 配方
    local expectNames = { MDB_UpgradeBagTier1 = true, MDB_UpgradeBagTier2 = true, MDB_UpgradeBagTier3 = true }
    for k in pairs(MODELS) do for _, s in ipairs(SKINS) do expectNames["MDB_Make" .. k .. "_" .. s] = true end end
    local namesOk = true
    for n in pairs(expectNames) do if not recipes[n] then namesOk = false end end
    for n in pairs(recipes) do if not expectNames[n] then namesOk = false end end
    check("recipes: exactly the 17 expected names", namesOk)
    local refsOk, threadOk = true, true
    for name, r in pairs(recipes) do
        for _, l in ipairs(r.lines) do
            local list = l.text:match("^item%s+%d+%s+%[(.-)%]")
            if list then
                for full in list:gmatch("[^;]+") do
                    if not exists(full) then refsOk = false; diag("    missing item: " .. name .. " " .. full) end
                end
            end
            local tags = l.text:match("tags%[(.-)%]")
            if tags then
                for t in tags:gmatch("[^;]+") do
                    if not VAN.tags[t:lower()] then refsOk = false; diag("    unknown tag: " .. name .. " " .. t) end
                end
            end
            local out = l.section == "outputs" and l.text:match("^item%s+%d+%s+([%w_.]+)")
            if out and not exists(out) then refsOk = false; diag("    missing output: " .. name .. " " .. out) end
            if l.text:find("Thread", 1, true) or (l.text:find("base:thread", 1, true) and l.text:find("mode:destroy", 1, true)) then
                threadOk = false
            end
        end
    end
    check("recipes: every input/output item and tag exists", refsOk)
    check("recipes: thread only as tags[base:thread] without destroy", threadOk)
    for k in pairs(MODELS) do
        local fabric = {}
        for _, s in ipairs(SKINS) do
            local r = recipes["MDB_Make" .. k .. "_" .. s]
            local outOk = false
            for _, l in ipairs(r and r.lines or {}) do
                if l.section == "outputs" and l.text == "item 1 MinidoracatBags." .. k .. "_" .. s then outOk = true end
                if l.text:find("FabricRoll", 1, true) or l.text:find("TarpPiece", 1, true) then fabric[s] = l.text:match("%[(.-)%]") end
            end
            check("MDB_Make" .. k .. "_" .. s .. ": outputs its own bag", outOk)
        end
        check("MDB_Make" .. k .. ": Navy and Olive use different fabric", fabric.Navy and fabric.Olive and fabric.Navy ~= fabric.Olive)
    end
    -- 升級配方：背包清單＝原版可穿戴、無 AcceptItemFunction 的容器＋14 件新背包＋38 件強化版
    local expectBags = {}
    for full, b in pairs(VAN.items) do
        if b.fields.ItemType == "base:container" and b.fields.CanBeEquipped and not b.fields.AcceptItemFunction then expectBags[full] = true end
    end
    for k in pairs(MODELS) do for _, s in ipairs(SKINS) do expectBags["MinidoracatBags." .. k .. "_" .. s] = true end end
    for _, s in ipairs(REIN_SPEC) do expectBags["MinidoracatBags." .. s .. "_Reinforced"] = true end
    for t = 1, 3 do
        local r = recipes["MDB_UpgradeBagTier" .. t]
        local bagLine, outputs = nil, 0
        for _, l in ipairs(r and r.lines or {}) do
            if l.section == "inputs" and l.text:find("Bag_Schoolbag", 1, true) then bagLine = l.text end
            if l.section == "outputs" then outputs = outputs + 1 end
        end
        local got, setOk = {}, bagLine ~= nil
        for full in (bagLine and bagLine:match("%[(.-)%]") or ""):gmatch("[^;]+") do got[full] = true end
        for full in pairs(expectBags) do if not got[full] then setOk = false; diag("    upgrade missing: " .. full) end end
        for full in pairs(got) do if not expectBags[full] then setOk = false; diag("    upgrade extra: " .. full) end end
        check("MDB_UpgradeBagTier" .. t .. ": bag list = wearable vanilla containers + 14 new + 38 reinforced", setOk)
        check("MDB_UpgradeBagTier" .. t .. ": bag is keep + IsNotWorn, outputs empty", bagLine ~= nil
            and bagLine:find("mode:keep", 1, true) and bagLine:find("flags[IsNotWorn]", 1, true) and outputs == 0)
        check("MDB_UpgradeBagTier" .. t .. ": Tailoring " .. (t + 1) .. ", hooks wired", r ~= nil
            and r.fields.SkillRequired == "Tailoring:" .. (t + 1) and r.fields.OnTest == "MDB.onTestTier" .. t
            and r.fields.OnCreate == "MDB.onUpgrade")
    end

    -- 4. 沙盒選項
    local sb = stripComments(readFile(F.SANDBOX))
    local sbOk = sb:find("VERSION = 1,", 1, true) ~= nil
    for k, spec in pairs(SANDBOX_SPEC) do
        local body = sb:match("option MinidoracatBags%." .. k .. "%s*(%b{})")
        local want = body and body:find("type = " .. spec[1], 1, true) and body:find("default = " .. spec[2] .. ",", 1, true)
            and body:find("page = MinidoracatBags,", 1, true) and body:find("translation = MinidoracatBags" .. k .. ",", 1, true)
        if spec[3] then want = want and body:find("min = " .. spec[3] .. ",", 1, true) and body:find("max = " .. spec[4] .. ",", 1, true) end
        if not want then sbOk = false; diag("    sandbox option wrong: " .. k) end
    end
    check("sandbox: 6 options with spec type/default/range", sbOk)

    -- 5. 翻譯：每個鍵在 16 個語言的正式檔、而且在對的檔（引擎依檔名分表，Translator.java:137-146）
    local want = { Sandbox = { "Sandbox_MinidoracatBags" }, ItemName = {}, Recipes = {}, Tooltip = {} }
    for k in pairs(SANDBOX_SPEC) do
        want.Sandbox[#want.Sandbox + 1] = "Sandbox_MinidoracatBags" .. k
        want.Sandbox[#want.Sandbox + 1] = "Sandbox_MinidoracatBags" .. k .. "_tooltip"
    end
    for full in pairs(items) do want.ItemName[#want.ItemName + 1] = full end
    for full in pairs(rein) do want.ItemName[#want.ItemName + 1] = full end
    for n in pairs(expectNames) do want.Recipes[#want.Recipes + 1] = n end
    for n in pairs(reinRecipes) do want.Recipes[#want.Recipes + 1] = n end
    for _, r in pairs(recipes) do if r.fields.Tooltip then want.Tooltip[#want.Tooltip + 1] = r.fields.Tooltip end end
    local i18nOk = true
    for _, lang in ipairs(LANGS) do
        for file, keys in pairs(want) do
            local have = {}
            for k in (readFile(TRANSLATE .. lang .. "/" .. file .. ".json", true) or ""):gmatch('\n%s*"([^"]+)"%s*:') do have[k] = true end
            for _, k in ipairs(keys) do
                if not have[k] then i18nOk = false; diag("    i18n missing: " .. lang .. "/" .. file .. ".json " .. k) end
            end
        end
    end
    check("i18n: items, recipes, tooltips, sandbox keys in all 16 Translate folders", i18nOk)

    -- 6. Lua 載入與函式名解析
    loadAll()
    local fnOk = true
    local function want(path)
        if path and type(resolve(path)) ~= "function" then fnOk = false; diag("    unresolved: " .. path) end
    end
    for _, b in pairs(items) do want(b.fields.AcceptItemFunction) end
    for _, r in pairs(recipes) do want(r.fields.OnTest); want(r.fields.OnCreate) end
    for _, r in pairs(reinRecipes) do want(r.fields.OnTest); want(r.fields.OnCreate) end
    check("every AcceptItemFunction/OnTest/OnCreate resolves to a function", fnOk)

    -- 7. applyTier：最高階升滿（預設 49／100），中間平均分配，四捨五入
    local TIERS = {
        ToolBeltPouch = { { 3, 80 }, { 18, 87 }, { 34, 93 }, { 49, 100 } },
        MedicHipPouch = { { 4, 85 }, { 19, 90 }, { 34, 95 }, { 49, 100 } },
        AmmoBandolier = { { 4, 85 }, { 19, 90 }, { 34, 95 }, { 49, 100 } },
        CourierSatchel = { { 14, 70 }, { 26, 80 }, { 37, 90 }, { 49, 100 } },
        DayPack = { { 20, 75 }, { 30, 83 }, { 39, 92 }, { 49, 100 } },
        ExpeditionPack = { { 30, 80 }, { 36, 87 }, { 43, 93 }, { 49, 100 } },
        ScoutChestRig = { { 6, 85 }, { 20, 90 }, { 35, 95 }, { 49, 100 } },
    }
    local function walk(base, baseWr, w, want)
        local seq, ok = newBag(base, baseWr, w), true
        for t = 0, #want - 1 do
            local fresh = newBag(base, baseWr, w)
            MDB.applyTier(fresh, t)
            MDB.applyTier(seq, t)
            local c, r = want[t + 1][1], want[t + 1][2]
            if fresh.cap ~= c or fresh.wr ~= r or seq.cap ~= c or seq.wr ~= r or fresh.md.MDB_tier ~= t then
                ok = false; diag(string.format("    tier %d: got %d/%d, want %d/%d", t, fresh.cap, fresh.wr, c, r))
            end
        end
        return ok and seq.md.MDB_cap == base and seq.md.MDB_wr == baseWr
    end
    for k, s in pairs(MODELS) do
        local f = items["MinidoracatBags." .. k .. "_Navy"].fields
        local want = TIERS[k]
        check(k .. ": tiers 0-3 = " .. want[1][1] .. "/" .. want[1][2] .. " -> " .. want[4][1] .. "/" .. want[4][2]
            .. " (table " .. s.cap[2] .. "/" .. s.wr[2] .. ")",
            want[4][1] == s.cap[2] and want[4][2] == s.wr[2]
            and walk(tonumber(f.Capacity), tonumber(f.WeightReduction), tonumber(f.Weight), want))
    end
    check("applyTier: vanilla school bag (weight 1.0) 15/70 -> 26/80 -> 38/90 -> 49/100",
        walk(15, 70, 1.0, { { 15, 70 }, { 26, 80 }, { 38, 90 }, { 49, 100 } }))
    check("applyTier: weight 2.0, 28/85 -> 35/90 -> 41/95 -> 48/100 (cap 50 - weight)",
        walk(28, 85, 2.0, { { 28, 85 }, { 35, 90 }, { 41, 95 }, { 48, 100 } }))
    local big = newBag(45, 85, 1.2)
    MDB.applyTier(big, 3)
    check("applyTier: capacity capped at 50 - bag weight", big.cap == 48)
    local sv0 = newBag(20, 75, 0.8); sv0.instanceWeight = 0
    MDB.applyTier(sv0, 3)
    check("applyTier: cap uses the script weight when getActualWeight() is 0 (server)", sv0.cap == 49)
    local o = SandboxVars.MinidoracatBags
    o.MaxTier = 1
    check("applyTier: MaxTier 1 fills at tier 1", walk(3, 80, 0.3, { { 3, 80 }, { 49, 100 } }))
    o.MaxTier = 2
    check("applyTier: MaxTier 2 splits in halves (3/80 -> 26/90 -> 49/100)", walk(3, 80, 0.3, { { 3, 80 }, { 26, 90 }, { 49, 100 } }))
    local over = newBag(3, 80, 0.3); MDB.applyTier(over, 3)
    check("applyTier: tier above MaxTier stays full", over.cap == 49 and over.wr == 100)
    o.MaxTier = 0
    local zero = newBag(20, 75, 0.8); zero.fc = newFluid(2.0); MDB.applyTier(zero, 3)
    check("applyTier: MaxTier 0 keeps original values", zero.cap == 20 and zero.wr == 75 and zero.fc.capacity == 2.0)
    o.MaxTier = 3
    o.FullCapacityPercent = 50
    check("applyTier: FullCapacityPercent 50 fills half the gap (3 -> 26 at full)",
        walk(3, 80, 0.3, { { 3, 80 }, { 11, 87 }, { 18, 93 }, { 26, 100 } })
        and walk(20, 75, 0.8, { { 20, 75 }, { 25, 83 }, { 30, 92 }, { 35, 100 } }))
    o.FullCapacityPercent = 0
    local none = newBag(20, 75, 0.8); MDB.applyTier(none, 3)
    check("applyTier: FullCapacityPercent 0 keeps the original capacity", none.cap == 20 and none.wr == 100)
    o.FullCapacityPercent = 100
    o.FullWeightReduction = 90
    check("applyTier: FullWeightReduction 90 is the full value", walk(4, 85, 0.3, { { 4, 85 }, { 19, 87 }, { 34, 88 }, { 49, 90 } }))
    o.FullWeightReduction = 50
    check("applyTier: FullWeightReduction below original never lowers it", walk(14, 70, 0.6, { { 14, 70 }, { 26, 70 }, { 37, 70 }, { 49, 70 } }))
    o.FullWeightReduction = 100
    -- 液體：BUP 水袋 5 升
    local function fluidSteps(base)
        local b, got = newBag(20, 75, 0.8), {}
        b.fc = newFluid(base)
        for t = 1, 3 do MDB.applyTier(b, t); got[t] = b.fc.capacity end
        return got, b
    end
    local function near(a, b) return math.abs(a - b) < 1e-3 end
    local wbag, wb = fluidSteps(2.0)
    check("applyTier: water bag fluid 2.0 -> 3.0 -> 4.0 -> 5.0, base kept", near(wbag[1], 3.0) and near(wbag[2], 4.0)
        and near(wbag[3], 5.0) and wb.md.MDB_fluid == 2.0)
    local camo = fluidSteps(3.0)
    check("applyTier: camo water bag fluid 3.0 -> 3.667 -> 4.333 -> 5.0", near(camo[1], 3.667) and near(camo[2], 4.333) and near(camo[3], 5.0))
    local large = fluidSteps(6.0)
    check("applyTier: fluid above 5.0 is never lowered", near(large[3], 6.0))
    o.FullCapacityPercent = 50
    local halfFluid = fluidSteps(2.0)
    check("applyTier: FullCapacityPercent 50 -> fluid 3.5 at full", near(halfFluid[3], 3.5))
    o.FullCapacityPercent = 100
    local dry = newBag(20, 75, 0.8)
    check("applyTier: bag without fluid container does not error", pcall(MDB.applyTier, dry, 1) and dry.md.MDB_fluid == nil)
    env.sent = {}
    local sp = newBag(20, 75, 0.8); MDB.applyTier(sp, 1)
    check("applyTier: single player sends nothing", #env.sent == 0)
    env.server = true
    local sv = newBag(20, 75, 0.8); MDB.applyTier(sv, 1)
    check("applyTier: server resends whole item", #env.sent == 1 and env.sent[1][1] == CONTAINER
        and env.sent[1][2] == sv and env.sent[1][3] == sv)
    local floor = newBag(20, 75, 0.8); floor.container = nil
    check("applyTier: no container on server does not error", pcall(MDB.applyTier, floor, 1) and #env.sent == 1)
    env.server = false

    -- 8. OnTest 與 onUpgrade
    local tool = { __class = "HandWeapon" }
    local b0, b1, b2 = newBag(20, 75, 0.8), newBag(20, 75, 0.8), newBag(20, 75, 0.8)
    b1.md.MDB_tier = 1; b2.md.MDB_tier = 2
    check("OnTest: non-bag inputs pass all tiers", MDB.onTestTier1(tool) and MDB.onTestTier2(tool) and MDB.onTestTier3(tool))
    check("OnTest: tier gate (0->1 only)", MDB.onTestTier1(b0) and not MDB.onTestTier2(b0) and not MDB.onTestTier3(b0))
    check("OnTest: tier gate (1->2, 2->3)", MDB.onTestTier2(b1) and not MDB.onTestTier1(b1) and MDB.onTestTier3(b2) and not MDB.onTestTier2(b2))
    SandboxVars.MinidoracatBags.MaxTier = 2
    check("OnTest: MaxTier 2 blocks tier 3", not MDB.onTestTier3(b2) and MDB.onTestTier2(b1))
    SandboxVars.MinidoracatBags.MaxTier = 0
    check("OnTest: MaxTier 0 blocks all, tools still pass", not MDB.onTestTier1(b0) and MDB.onTestTier1(tool))
    SandboxVars.MinidoracatBags.MaxTier = 3
    local ub = newBag(30, 80, 1.2)
    local data = { getAllKeepInputItems = function() return javaList({ tool, ub }) end }
    MDB.onUpgrade(data, nil)
    check("onUpgrade: first keep bag goes 0 -> 1", ub.md.MDB_tier == 1 and ub.cap == 36 and ub.wr == 87)
    MDB.onUpgrade(data, nil); MDB.onUpgrade(data, nil)
    check("onUpgrade: reaches tier 3 = 48/100 (weight 1.2)", ub.md.MDB_tier == 3 and ub.cap == 48 and ub.wr == 100)
    MDB.onUpgrade(data, nil)
    check("onUpgrade: never above MaxTier", ub.md.MDB_tier == 3)

    -- 8b. 換穿法（腰包前背↔後背）：Bag_FannyPackFront／Back 都是容量 1、負重減輕 85、自重 0.2（container.txt:805-853）
    local function swapped(old, fluid)
        local n = newBag(1, 85, 0.2); n.container = nil   -- 新物品還沒放進容器
        if fluid then n.fc = newFluid(fluid) end
        return ISClothingExtraAction:createItemNew(old, n)
    end
    local front = newBag(1, 85, 0.2); front.fc = newFluid(2.0)
    for t = 1, 3 do MDB.applyTier(front, t) end
    env.server, env.sent = true, {}
    local back = swapped(front, 2.0)
    env.server = false
    check("swap: tier-3 fanny pack keeps 49/100 and 5.0 L after front<->back, nothing resent",
        front.cap == 49 and back.cap == 49 and back.wr == 100 and near(back.fc.capacity, 5.0) and back.md.MDB_tier == 3
        and #env.sent == 0)
    local plain = swapped(newBag(1, 85, 0.2), 2.0)
    check("swap: never-upgraded bag keeps script defaults", plain.cap == 1 and plain.wr == 85 and plain.fc.capacity == 2.0
        and next(plain.md) == nil)
    local dropped = newBag(1, 85, 0.2)
    dropped.md = { MDB_tier = 2, MDB_cap = 1, MDB_wr = 85, MDB_fluid = 2.0 }; dropped.fc = newFluid(2.0)
    local fixed = swapped(dropped, 2.0)
    check("swap: bag that already lost its tier (defaults + modData) is restored to tier 2 = 33/95, 4.0 L",
        fixed.cap == 33 and fixed.wr == 95 and near(fixed.fc.capacity, 4.0))

    -- 8c. 強化版：對照表、各階數值、升級換型、還原、腰包換穿、0.1.0 升過級的原版背包
    local specOk = #(MDB.REINFORCED_SOURCES or {}) == #REIN_SPEC
    for _, s in ipairs(REIN_SPEC) do
        local r = MDB.REINFORCED["Base." .. s]
        specOk = specOk and r == "MinidoracatBags." .. s .. "_Reinforced" and MDB.ORIGINAL[r] == "Base." .. s
    end
    check("REINFORCED_SOURCES = the 38 vanilla bags, REINFORCED / ORIGINAL map both ways", specOk)
    local tiersOk = true
    for _, s in ipairs(REIN_SPEC) do
        local b = instanceItem("MinidoracatBags." .. s .. "_Reinforced")
        for t = 1, 3 do MDB.applyTier(b, t) end
        if not (b.weight == 0.1 and b.cap == 49 and b.wr == 100) then tiersOk = false; diag("    reinforced tier 3: " .. s) end
    end
    check("reinforced: all 38 weigh 0.1 and reach 49/100 at tier 3", tiersOk)
    check("reinforced ALICE (weight 0.1): 28/85 -> 35/90 -> 42/95 -> 49/100",
        walk(28, 85, 0.1, { { 28, 85 }, { 35, 90 }, { 42, 95 }, { 49, 100 } }))

    -- 放進主物品欄、裝東西、改名、帶自訂 modData 的背包
    local function stocked(full, md, water)
        CONTAINER.items = {}
        local b = CONTAINER:AddItem(instanceItem(full))
        b.contents, b.name, b.custom = { "nail", "apple" }, "My Bag", true   -- 玩家改過名
        b.md = md or {}
        b.md.custom = "kept"
        if water then b.fc.amount = water end
        return b
    end
    local function keepData(bag) return { getAllKeepInputItems = function() return javaList({ tool, bag }) end } end
    local function swapped(old, newType)
        local new = CONTAINER.items[1]
        return #CONTAINER.items == 1 and new ~= old and new.fullType == newType and old.container == nil
            and new.contents[1] == "nail" and new.contents[2] == "apple" and #old.contents == 0
            and new.name == "My Bag" and new.custom == true and new.md.custom == "kept", new
    end
    local A, RA = "Base.Bag_ALICEpack", "MinidoracatBags.Bag_ALICEpack_Reinforced"
    env.sent, env.replaced = {}, {}
    local old = stocked(A)
    MDB.onUpgrade(keepData(old), PLAYER)
    local okSwap, new = swapped(old, RA)
    check("upgrade (SP): vanilla tier 0 -> reinforced tier 1 = 35/90, contents/name/modData moved, old removed",
        okSwap and new.md.MDB_tier == 1 and new.cap == 35 and new.wr == 90)
    check("upgrade (SP): no replace packet, action queue updated once",
        #env.sent == 0 and #env.replaced == 1 and env.replaced[1][1] == CONTAINER and env.replaced[1][2] == old and env.replaced[1][3] == new)
    env.server, env.sent, env.replaced = true, {}, {}
    old = stocked(A, { MDB_tier = 1, MDB_cap = 28, MDB_wr = 85 })   -- 0.1.0 升到第 1 階：換穿法包裝也會套一次 applyTier
    MDB.onUpgrade(keepData(old), PLAYER)
    okSwap, new = swapped(old, RA)
    check("upgrade (server): tier 1 vanilla -> reinforced tier 2 = 42/95, exactly one replace (container, old, new)",
        okSwap and new.md.MDB_tier == 2 and new.cap == 42 and new.wr == 95 and #env.sent == 1
        and env.sent[1][1] == CONTAINER and env.sent[1][2] == old and env.sent[1][3] == new and #env.replaced == 0)
    env.sent = {}
    MDB.onUpgrade(keepData(new), PLAYER)
    check("upgrade (server): reinforced bag upgrades in place, one replace of itself",
        CONTAINER.items[1] == new and new.md.MDB_tier == 3 and new.cap == 49 and #env.sent == 1 and env.sent[1][2] == new)
    env.server = false
    old = stocked("Base.Bag_HydrationBackpack", nil, 2.0)
    MDB.onUpgrade(keepData(old), PLAYER)
    okSwap, new = swapped(old, "MinidoracatBags.Bag_HydrationBackpack_Reinforced")
    check("upgrade: water bag 2.0 L full -> reinforced tier 1 with 3.0 L capacity, water kept",
        okSwap and near(new.fc.capacity, 3.0) and near(new.fc.amount, 2.0))
    old = stocked(A)
    old.name, old.custom = "Bloody, name of " .. A, false   -- 沒改名，getName() 帶染血前綴
    MDB.onUpgrade(keepData(old), PLAYER)
    new = CONTAINER.items[1]
    check("upgrade: un-renamed bag gets the reinforced script name (no stale prefix), not marked custom",
        new.fullType == RA and new.name == "name of " .. RA and new.custom == false)
    SandboxVars.MinidoracatBags.MaxTier = 0
    old = stocked(A)
    MDB.onUpgrade(keepData(old), PLAYER)
    SandboxVars.MinidoracatBags.MaxTier = 3
    check("upgrade: MaxTier 0 does not swap", CONTAINER.items[1] == old and #CONTAINER.items == 1)

    -- 還原：階級、內容物、modData 照舊；水袋 5 升不截斷
    env.server, env.sent = true, {}
    old = stocked(RA)
    MDB.applyTier(old, 2)
    env.sent = {}
    MDB.onSwapKeepTier(keepData(old), PLAYER)
    okSwap, new = swapped(old, A)
    check("restore (server): reinforced tier 2 -> vanilla tier 2 = 41/95 (top 48), one replace",
        okSwap and new.md.MDB_tier == 2 and new.cap == 41 and new.wr == 95 and #env.sent == 1 and env.sent[1][3] == new)
    env.server = false
    old = stocked("MinidoracatBags.Bag_HydrationBackpack_Reinforced")
    MDB.applyTier(old, 3)
    old.fc.amount = 5.0
    MDB.onSwapKeepTier(keepData(old), PLAYER)
    okSwap, new = swapped(old, "Base.Bag_HydrationBackpack")
    check("restore: tier-3 water bag keeps 5.0 L capacity and all 5.0 L of water",
        okSwap and new.md.MDB_tier == 3 and near(new.fc.capacity, 5.0) and near(new.fc.amount, 5.0))

    -- 強化版腰包換前後（原版換穿法 → 包裝依 MDB_tier 重算）
    local front = instanceItem("MinidoracatBags.Bag_FannyPackFront_Reinforced")
    for t = 1, 3 do MDB.applyTier(front, t) end
    local back = ISClothingExtraAction:createItemNew(front, instanceItem("MinidoracatBags.Bag_FannyPackBack_Reinforced"))
    check("reinforced fanny pack front -> back keeps tier 3 = 49/100", back.md.MDB_tier == 3 and back.cap == 49 and back.wr == 100)

    -- 0.1.0 升過級的原版背包：改成強化版、階級照舊；第 0 階不放行
    local v0, v3 = instanceItem(A), instanceItem(A)
    v3.md = { MDB_tier = 3, MDB_cap = 28, MDB_wr = 85 }; v3.cap, v3.wr = 48, 100
    check("onTestUpgraded: tools pass, tier 0 blocked, tier 1+ passes",
        MDB.onTestUpgraded(tool) and not MDB.onTestUpgraded(v0) and MDB.onTestUpgraded(v3))
    old = stocked(A, { MDB_tier = 3, MDB_cap = 28, MDB_wr = 85 })
    old.cap, old.wr = 48, 100
    MDB.onSwapKeepTier(keepData(old), PLAYER)
    okSwap, new = swapped(old, RA)
    check("0.1.0 tier-3 vanilla -> reinforced stays tier 3 (49/100), no further upgrade",
        okSwap and new.md.MDB_tier == 3 and new.cap == 49 and new.wr == 100
        and not MDB.onTestTier1(new) and not MDB.onTestTier2(new) and not MDB.onTestTier3(new))

    -- 換型中途出錯：舊背包與內容物原地不動，之後的升級照常重送
    env.server, env.sent = true, {}
    old = stocked(A)
    env.failCopy = true
    local failed = not pcall(MDB.swapBag, old, RA, 1, PLAYER)
    env.failCopy = false
    check("swap error: old bag and contents stay, nothing sent", failed and old.container == CONTAINER
        and old.contents[1] == "nail" and #env.sent == 0)
    MDB.applyTier(old, 1)
    check("swap error: later applyTier on the server still resends", #env.sent == 1)
    env.server = false
    CONTAINER.items = {}

    -- 9. 放入限制（原版物品的真實 tag 與分類）
    check("acceptFirstAid: bandage, disinfectant, pills accepted", MDB.acceptFirstAid(nil, vanillaItem("Base.Bandage"))
        and MDB.acceptFirstAid(nil, vanillaItem("Base.Disinfectant")) and MDB.acceptFirstAid(nil, vanillaItem("Base.Pills")))
    check("acceptFirstAid: hammer, ammo, first aid kit container rejected", not MDB.acceptFirstAid(nil, vanillaItem("Base.Hammer"))
        and not MDB.acceptFirstAid(nil, vanillaItem("Base.Bullets9mm")) and not MDB.acceptFirstAid(nil, vanillaItem("Base.FirstAidKit_Military")))
    check("acceptAmmo: loose bullets and shells accepted", MDB.acceptAmmo(nil, vanillaItem("Base.Bullets9mm"))
        and MDB.acceptAmmo(nil, vanillaItem("Base.ShotgunShells")) and MDB.acceptAmmo(nil, vanillaItem("Base.308Bullets")))
    check("acceptAmmo: ammo boxes and cartons rejected", not MDB.acceptAmmo(nil, vanillaItem("Base.Bullets9mmBox"))
        and not MDB.acceptAmmo(nil, vanillaItem("Base.ShotgunShellsBox")) and not MDB.acceptAmmo(nil, vanillaItem("Base.Bullets9mmCarton"))
        and not MDB.acceptAmmo(nil, vanillaItem("Base.Hammer")))
    local ammoOk = true
    for full, b in pairs(VAN.items) do
        if b.fields.DisplayCategory == "Ammo" and (full:find("Box", 1, true) or full:find("Carton", 1, true)) then
            if MDB.acceptAmmo(nil, vanillaItem(full)) then ammoOk = false; diag("    ammo box accepted: " .. full) end
        end
    end
    check("acceptAmmo: every vanilla ammo Box/Carton rejected", ammoOk)

    -- 10. 戰利品
    local function loadPD()
        -- 原版清單引用其他分配檔定義的 ClutterTables、BagsAndContainers 等表；這裡只需要它們存在
        local stub = setmetatable({}, { __index = function() return {} end })
        local pdEnv = setmetatable({}, { __index = function(_, k) local v = _G[k]; if v == nil then return stub end; return v end })
        local pdPath = PZ .. "lua/server/Items/ProceduralDistributions.lua"
        assert(loadfile(pdPath, "t", pdEnv))()
        ProceduralDistributions = pdEnv.ProceduralDistributions
    end
    local function runLoot(mult)
        loadPD()
        local before = {}
        for name, l in pairs(ProceduralDistributions.list) do if l.items then before[name] = #l.items end end
        SandboxVars.MinidoracatBags.LootMultiplier = mult
        for _, h in ipairs(Events.OnPreDistributionMerge.handlers) do h() end
        local added = {}
        for name, l in pairs(ProceduralDistributions.list) do
            if l.items and #l.items ~= before[name] then
                added[name] = {}
                for i = before[name] + 1, #l.items, 2 do added[name][l.items[i]] = l.items[i + 1] end
            end
        end
        SandboxVars.MinidoracatBags.LootMultiplier = 1
        return added
    end
    check("loot: one OnPreDistributionMerge handler", #Events.OnPreDistributionMerge.handlers == 1)
    for _, mult in ipairs({ 1, 2 }) do
        local added = runLoot(mult)
        local ok = true
        for _, spec in ipairs(LOOT_SPEC) do
            local got = added[spec[1]] or {}
            local n = 0
            for _ in pairs(got) do n = n + 1 end
            local m = 0
            for model, wgt in pairs(spec[3]) do
                m = m + 1
                local full = "MinidoracatBags." .. model .. spec[2]
                if not items[full] or math.abs((got[full] or -1) - wgt * mult) > 1e-9 then ok = false; diag("    loot wrong: " .. spec[1] .. " " .. full) end
            end
            if n ~= m then ok = false; diag("    loot extra entries: " .. spec[1]) end
        end
        local lists = 0
        for _ in pairs(added) do lists = lists + 1 end
        check("loot x" .. mult .. ": right lists, suffix and weights; nothing else touched", ok and lists == #LOOT_SPEC
            and added.CampingStoreBackpacks == nil)
    end
    local none = runLoot(0)
    local any = false
    for _ in pairs(none) do any = true end
    check("loot x0: nothing added", not any)

    -- 10b. 單機讀檔：merge 時沙盒還是預設值，OnInitGlobalModData 才是存檔值（bags-sandbox-sp-1025c）
    check("loot: one OnInitGlobalModData handler", #Events.OnInitGlobalModData.handlers == 1)
    local function session(atMerge, saved, server, client)
        loadPD()
        env.server, env.client, env.parsed = server or false, client or false, 0
        SandboxVars.MinidoracatBags.LootMultiplier = atMerge
        for _, h in ipairs(Events.OnPreDistributionMerge.handlers) do h() end
        SandboxVars.MinidoracatBags.LootMultiplier = saved
        for _, h in ipairs(Events.OnInitGlobalModData.handlers) do h(false) end
        SandboxVars.MinidoracatBags.LootMultiplier = 1
        env.server, env.client = false, false
        local got, n = {}, 0
        for name, l in pairs(ProceduralDistributions.list) do
            for i = 1, #(l.items or {}) - 1, 2 do
                local it = l.items[i]
                if type(it) == "string" and it:sub(1, 16) == "MinidoracatBags." then
                    got[name] = got[name] or {}
                    got[name][it] = l.items[i + 1]
                    n = n + 1
                end
            end
        end
        return got, n, env.parsed
    end
    local function weightsAre(got, n, mult)
        local want = 0
        for _, spec in ipairs(LOOT_SPEC) do
            for model, wgt in pairs(spec[3]) do
                want = want + 1
                local g = got[spec[1]] and got[spec[1]]["MinidoracatBags." .. model .. spec[2]]
                if mult > 0 and (g == nil or math.abs(g - wgt * mult) > 1e-9) then return false end
            end
        end
        return n == (mult > 0 and want or 0)
    end
    local g, n, parsed = session(1, 2)
    check("loot SP load: merge x1 then saved x2 -> x2, one Parse", weightsAre(g, n, 2) and parsed == 1)
    g, n, parsed = session(2, 2)
    check("loot SP new game: x2 stays x2 (not x4), no Parse", weightsAre(g, n, 2) and parsed == 0)
    g, n, parsed = session(1, 0)
    check("loot SP load: saved x0 removes entries, one Parse", weightsAre(g, n, 0) and parsed == 1)
    g, n, parsed = session(0, 3)
    check("loot SP load: merge x0 then saved x3 -> x3, one Parse", weightsAre(g, n, 3) and parsed == 1)
    g, n, parsed = session(1, 2, true)
    check("loot MP server: OnInitGlobalModData does nothing", weightsAre(g, n, 1) and parsed == 0)
    g, n, parsed = session(1, 2, false, true)
    check("loot MP client: OnInitGlobalModData does nothing", weightsAre(g, n, 1) and parsed == 0)

    -- 11. 殭屍死亡掉落
    check("zombie: one OnZombieDead handler", #Events.OnZombieDead.handlers == 1)
    local function kill(outfit, rands)
        local added = {}
        env.rand = rands or { 0, 0 }
        env.randCalls = 0
        local z = { getOutfitName = function() return outfit end,
            getInventory = function() return { AddItem = function(_, n) added[#added + 1] = n end } end }
        Events.OnZombieDead.handlers[1](z)
        return added
    end
    local clsOk = true
    for outfit, kind in pairs(OUTFIT_SPEC) do
        if not VAN.outfits[outfit] then clsOk = false; diag("    outfit not in clothing.xml: " .. outfit) end
        for idx = 0, 6 do
            local got = kill(outfit, { 0, idx })
            local name = got[1]
            local good = #got == 1 and items[name] ~= nil
            if kind == "medic" then good = good and name == "MinidoracatBags.MedicHipPouch_Olive"
            else good = good and name:sub(-#kind) == kind end
            if not good then clsOk = false; diag("    zombie drop wrong: " .. outfit .. " " .. tostring(name)) end
        end
    end
    check("zombie: police -> _Navy, army -> _Olive, medics -> MedicHipPouch_Olive", clsOk)
    check("zombie: civilian and nil outfits drop nothing", #kill("Tourist") == 0 and #kill(nil) == 0)
    check("zombie: 3% roll boundary", #kill("Police", { 299, 0 }) == 1 and #kill("Police", { 300 }) == 0)
    SandboxVars.MinidoracatBags.LootMultiplier = 2
    local doubled = #kill("Police", { 599, 0 }) == 1 and #kill("Police", { 600 }) == 0
    SandboxVars.MinidoracatBags.LootMultiplier = 0
    local off = #kill("Police", { 0, 0 }) == 0
    SandboxVars.MinidoracatBags.LootMultiplier = 1
    check("zombie: LootMultiplier scales chance; 0 turns off", doubled and off)
    env.client = true
    local cl = kill("Police", { 0, 0 })
    check("zombie: MP client does nothing (no roll, no item)", #cl == 0 and env.randCalls == 0)
    env.client = false
end

rawPrint("== 新背包")
suite()

-- 產生器：已提交的強化版檔案和 scripts/gen_reinforced.py 的產生結果一致（遊戲或 LangFor42 更新後會在這裡失敗）
local function genCheck()
    local p = io.popen("uv run --quiet scripts/gen_reinforced.py --check 2>&1")
    local out = p:read("a")
    local ok = p:close() == true
    if not ok and not quiet then rawPrint(out) end
    return ok
end
check("gen_reinforced.py --check: committed files match the generator", genCheck())

if arg and arg[1] == "--mutants" then
    local mutants = {
        { name = "容量不四捨五入", file = "UPG", from = " + 50) / 100)", to = ") / 100)" },
        { name = "上限不扣自重", file = "UPG", from = "math.floor(50 - bag:getScriptItem():getActualWeight())", to = "50" },
        { name = "上限用實例自重", file = "UPG", from = "bag:getScriptItem():getActualWeight()", to = "bag:getActualWeight()" },
        { name = "容量不乘 FullCapacityPercent", file = "UPG", from = "* pct + 50) / 100)", to = "* 100 + 50) / 100)" },
        { name = "階內不四捨五入", file = "UPG", from = "* t * 2 + m) / (2 * m))", to = "* t * 2) / (2 * m))" },
        { name = "階數沒夾在 MaxTier", file = "UPG", from = "math.min(tier, maxTier)", to = "tier" },
        { name = "分母寫死 3", file = "UPG", from = "local m = math.max(maxTier, 1)", to = "local m = 3" },
        { name = "負重減輕被調低", file = "UPG", from = 'math.max(md.MDB_wr, MDB.opt("FullWeightReduction"))', to = 'MDB.opt("FullWeightReduction")' },
        { name = "液體目標錯", file = "UPG", from = "local FULL_FLUID = 5.0", to = "local FULL_FLUID = 4.0" },
        { name = "液體不乘 FullCapacityPercent", file = "UPG", from = "* pct / 100", to = "" },
        { name = "液體每次重讀 base", file = "UPG", from = "if md.MDB_fluid == nil then", to = "if true then" },
        { name = "每次重讀 base", file = "UPG", from = "if md.MDB_cap == nil then", to = "if true then" },
        { name = "不記階級", file = "UPG", from = "md.MDB_tier = tier", to = "" },
        { name = "伺服器不重送", file = "UPG", from = "sendReplaceItemInContainer(container, bag, bag)", to = "" },
        { name = "單機也重送", file = "UPG", from = "if isServer() and container and not swapping then", to = "if container and not swapping then" },
        { name = "非背包輸入被擋", file = "UPG", from = 'if not instanceof(item, "InventoryContainer") then return true end', to = 'if not instanceof(item, "InventoryContainer") then return false end' },
        { name = "OnTest 不看 MaxTier", file = "UPG", from = 'return tier <= MDB.opt("MaxTier") and', to = "return" },
        { name = "OnTest 階級差一", file = "UPG", from = "tierOf(item) == tier - 1", to = "tierOf(item) <= tier - 1" },
        { name = "onUpgrade 不看 MaxTier", file = "UPG", from = 'if tier > MDB.opt("MaxTier") then return end', to = "" },
        { name = "換穿法沒包裝", file = "UPG", from = "function ISClothingExtraAction:createItemNew(item, newItem)", to = "function MDB:unusedCreateItemNew(item, newItem)" },
        { name = "升級不換型", file = "UPG", from = "local target = MDB.REINFORCED[bag:getFullType()]", to = "local target = nil" },
        { name = "換型途中照送", file = "UPG", from = "if isServer() and container and not swapping then", to = "if isServer() and container then" },
        { name = "換型最後不送", file = "UPG", from = "        sendReplaceItemInContainer(cont, old, new)\n", to = "" },
        { name = "單機不換動作佇列", file = "UPG", from = "        replaceItemInContainer(cont, old, new)", to = "" },
        { name = "舊背包沒移除", file = "UPG", from = "    cont:Remove(old)", to = "" },
        { name = "液體沒在容量設好後重搬", file = "UPG", from = "if ofc and nfc then nfc:copyFluidsFrom(ofc) end", to = "" },
        { name = "出錯沒復原旗標", file = "UPG", from = "    swapping = false\n    if not ok", to = "    if not ok" },
        { name = "新背包沒先放進容器", file = "UPG", from = "    cont:AddItem(new)\n", to = "" },
        { name = "改名旗標沒搬", file = "UPG", from = "            new:setCustomName(true)\n", to = "" },
        { name = "沒改名也沿用舊名", file = "UPG", from = "            new:setName(new:getScriptItem():getDisplayName())\n", to = "" },
        { name = "還原掉級", file = "UPG", from = "MDB.ORIGINAL[ft] or MDB.REINFORCED[ft], tierOf(bag)", to = "MDB.ORIGINAL[ft] or MDB.REINFORCED[ft], 0" },
        { name = "第 0 階也能改強化版", file = "UPG", from = "tierOf(item) >= 1", to = "tierOf(item) >= 0" },
        { name = "對照表少一款", file = "UPG", from = '"Base.Bag_SWAT", ', to = "" },
        { name = "強化版自重錯", file = "REIN", from = "Weight = 0.1,", to = "Weight = 0.2," },
        { name = "強化版跑速沒改", file = "REIN", from = "RunSpeedModifier = 1.0,", to = "RunSpeedModifier = 0.94," },
        { name = "強化版沿用原版 ClothingItem", file = "REIN", from = "ClothingItem = MDB_Bag_Satchel_Reinforced,", to = "ClothingItem = Bag_Satchel," },
        { name = "強化腰包換穿指回原版", file = "REIN", from = "ClothingItemExtra = MinidoracatBags.Bag_FannyPackBack_Reinforced,", to = "ClothingItemExtra = Base.Bag_FannyPackBack," },
        { name = "強化版多一個欄位", file = "REIN", from = "ClothingItem = MDB_Bag_Satchel_Reinforced,", to = "ClothingItem = MDB_Bag_Satchel_Reinforced,\n        AcceptItemFunction = MDB.acceptAmmo," },
        { name = "強化版水袋容量改了", file = "REIN", from = "Capacity = 2.0,", to = "Capacity = 5.0," },
        { name = "還原配方漏一款", file = "REIN", from = "MinidoracatBags.Bag_SWAT_Reinforced;", to = "" },
        { name = "還原配方可用穿著中的背包", file = "REIN", from = "_Reinforced] mode:keep flags[IsNotWorn],", to = "_Reinforced] mode:keep," },
        { name = "改強化版配方沒 OnTest", file = "REIN", from = "OnTest = MDB.onTestUpgraded,", to = "" },
        { name = "強化版 XML 換了模型", file = "REIN_XML", from = "<m_MaleModel>", to = "<m_MaleModel>x" },
        { name = "升級清單漏強化版", file = "RECIPES", from = "MinidoracatBags.Bag_SWAT_Reinforced;", to = "" },
        { name = "翻譯缺強化版名稱", file = "I18N_ITEMS", from = '"MinidoracatBags.Bag_SWAT_Reinforced"', to = '"MinidoracatBags.Bag_SWATX_Reinforced"' },
        { name = "彈藥背帶收彈藥盒", file = "FIL", from = "return item:hasTag(ItemTag.AMMO)", to = 'return item:getDisplayCategory() == "Ammo"' },
        { name = "彈藥背帶不收霰彈", file = "FIL", from = "return item:hasTag(ItemTag.AMMO)", to = "return item:hasTag(ItemTag.AMMO) and not item:hasTag(ItemTag.SHOTGUN_SHELL)" },
        { name = "醫療腰包分類錯", file = "FIL", from = '== "FirstAid"', to = '== "Medical"' },
        { name = "警局清單放 Olive", file = "LOOT", from = '{ "PoliceLockers", "_Navy"', to = '{ "PoliceLockers", "_Olive"' },
        { name = "權重不乘倍率", file = "LOOT", from = "table.insert(items, pairsList[j + 1] * mult)", to = "table.insert(items, pairsList[j + 1])" },
        { name = "倍率 0 仍加", file = "LOOT", from = "                if mult > 0 then", to = "                if true then" },
        { name = "單機不重算", file = "LOOT", from = "Events.OnInitGlobalModData.Add(MDB.reapplyLoot)", to = "" },
        { name = "MP 也重算", file = "LOOT", from = "if isClient() or isServer() then return end", to = "" },
        { name = "沒改也 Parse", file = "LOOT", from = 'if setLoot(MDB.opt("LootMultiplier")) then', to = 'if setLoot(MDB.opt("LootMultiplier")) or true then' },
        { name = "已相同仍重建", file = "LOOT", from = "if seen[name] or want[name] ~= items[k + 1] then same = false end", to = "same = false" },
        { name = "有改不 Parse", file = "LOOT", from = "        ItemPickerJava.Parse()", to = "" },
        { name = "放進露營店", file = "LOOT", from = '{ "NurseOutfit"', to = '{ "CampingStoreBackpacks"' },
        { name = "客戶端也掉落", file = "ZD", from = "if isClient() then return end", to = "" },
        { name = "SWAT 掉 Olive", file = "ZD", from = 'Police_SWAT = "_Navy"', to = 'Police_SWAT = "_Olive"' },
        { name = "醫護沒分類", file = "ZD", from = 'Nurse = "medic", ', to = "" },
        { name = "掉落不乘倍率", file = "ZD", from = 'CHANCE_BP * MDB.opt("LootMultiplier")', to = "CHANCE_BP" },
        { name = "ClothingItem 沿用原版名", file = "ITEMS", from = "ClothingItem = MDB_ScoutChestRig_Navy,", to = "ClothingItem = Bag_ChestRig," },
        { name = "AcceptItemFunction 拼錯", file = "ITEMS", from = "AcceptItemFunction = MDB.acceptAmmo,", to = "AcceptItemFunction = MDB.acceptAmmos," },
        { name = "彈藥背帶加 ammocase", file = "ITEMS", from = "base:reloadfastshells,", to = "base:reloadfastshells;base:ammocase," },
        { name = "容量和表不符", file = "ITEMS", from = "Capacity = 30,", to = "Capacity = 31," },
        { name = "配方輸入不存在", file = "RECIPES", from = "item 1 [Base.Buckle],", to = "item 1 [Base.Buckel]," },
        { name = "升級清單漏原版背包", file = "RECIPES", from = "Base.Bag_ALICEpack;", to = "" },
        { name = "升級可用穿著中的背包", file = "RECIPES", from = "mode:keep flags[IsNotWorn],", to = "mode:keep," },
        { name = "OnTest 名稱拼錯", file = "RECIPES", from = "OnTest = MDB.onTestTier2,", to = "OnTest = MDB.onTestTeir2," },
        { name = "線材整捲銷毀", file = "RECIPES", from = "item 2 tags[base:thread],", to = "item 2 [Base.Thread] mode:destroy," },
        { name = "fileGuidTable 對不上", file = "GUIDTABLE", from = "MDB_ToolBeltPouch_Navy.xml</path>", to = "MDB_ToolBeltPouch_NavyX.xml</path>" },
        { name = "日行包手持借回原版", file = "ITEMS", from = "ReplaceInPrimaryHand = MDB_DayPack_Navy_RHand holdingbagright,", to = "ReplaceInPrimaryHand = Bag_HikingBag_RHand holdingbagright," },
        { name = "日行包地面模型沒帶 module", file = "ITEMS", from = "WorldStaticModel = MinidoracatBags.MDB_DayPack_Ground,", to = "WorldStaticModel = MDB_DayPack_Ground," },
        { name = "日行包圖示借回原版", file = "ITEMS", from = "Icon = MDB_DayPack_Olive,", to = "Icon = Hiking_Green," },
        { name = "地面模型 mesh 拼錯", file = "MODELS", from = "mesh = WorldItems/Clothing/MDB_DayPack_Ground,", to = "mesh = WorldItems/Clothing/MDB_Daypack_Grnd," },
        { name = "日行包 XML 借回原版模型", file = "DAYPACK_XML", from = "MDB_DayPack_M.X", to = "M_HikingBag.X" },
        { name = "日行包 XML 兩張貼圖", file = "DAYPACK_XML", from = "</clothingItem>", to = "\t<textureChoices>Clothes\\Bag\\MDB_DayPack_Olive</textureChoices>\n</clothingItem>" },
        { name = "左手模型路徑沒副檔名", file = "DAYPACK_LHAND_XML", from = "MDB_DayPack_LHand.X</m_MaleModel>", to = "MDB_DayPack_LHand</m_MaleModel>" },
        { name = "遠征包左手借回原版", file = "ITEMS", from = "ReplaceInSecondHand = MDB_ExpeditionPack_Olive_LHand holdingbagleft,", to = "ReplaceInSecondHand = Bag_BigHikingBag_LHand holdingbagleft," },
        { name = "胸掛 Alt 模型借回原版", file = "CHESTRIG_XML", from = "MDB_ScoutChestRig_ALT_M.X", to = "Bob_ChestRig_ALT.x" },
        { name = "沙盒預設值錯", file = "SANDBOX", from = "max = 3, default = 3,", to = "max = 3, default = 2," },
        { name = "翻譯缺鍵", file = "I18N_RECIPES", from = '"MDB_UpgradeBagTier3"', to = '"MDB_UpgradeBagTierX"' },
    }
    rawPrint("== 突變（每個都應至少讓一項 FAIL）")
    local survived = 0
    for _, m in ipairs(mutants) do
        local keepPass, keepFail = pass, fail
        MUTATION, quiet = m, true
        pass, fail = 0, 0
        local ok, err = pcall(suite)
        local killed = (not ok) or fail > 0
        rawPrint(string.format("  %s  %s（%s）", killed and "KILLED " or "SURVIVED", m.name,
            ok and (fail .. " 項 FAIL") or ("錯誤：" .. tostring(err))))
        if not killed then survived = survived + 1 end
        pass, fail, MUTATION, quiet = keepPass, keepFail, nil, false
    end
    check("所有突變都被抓到", survived == 0)

    -- 產生器 --check 抓得到差異：暫時改一份產生的 XML，跑完立刻還原
    local path = F.REIN_XML
    local fh = io.open(path, "rb"); local original = fh:read("a"); fh:close()
    fh = io.open(path, "wb"); fh:write((original:gsub("<m_Static>", "<m_Static>x", 1))); fh:close()
    quiet = true
    local caught = not genCheck()
    quiet = false
    fh = io.open(path, "wb"); fh:write(original); fh:close()
    rawPrint(string.format("  %s  產生器 --check 發現手改的強化版 XML", caught and "KILLED " or "SURVIVED"))
    check("產生器 --check 抓得到手改的產生檔", caught)
end

rawPrint(string.format("結果：%d PASS，%d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
