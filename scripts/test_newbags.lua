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
    I18N_FLUIDS = TRANSLATE .. "EN/Fluids.json",
    REIN = MEDIA .. "scripts/MDB_Reinforced.txt",
    CONVERT = MEDIA .. "scripts/MDB_Convert.txt",
    REIN_XML = MEDIA .. "clothing/clothingItems/MDB_Bag_Satchel_Navy_Reinforced.xml",
    REIN_HAND_XML = MEDIA .. "clothing/clothingItems/MDB_Bag_DuffelBag_Olive_Reinforced_LHand.xml",
    SHAPES = "scripts/theme_shapes.json",
    REG = MEDIA .. "registries.lua",
    BODYLOC = MEDIA .. "lua/shared/MDB_BodyLocations.lua",
    GEN = "scripts/gen_reinforced.py",
    VARIANT_XML = MEDIA .. "clothing/clothingItems/MDB_MedicHipPouchFront_Olive.xml",
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
-- 腰包換穿變體：欄位抄原款，只換穿戴位置（CanBeEquipped＝BodyLocation）與 ClothingItem；和原款 ClothingItemExtra 互指
local VARIANTS = {
    ToolBeltPouchBack = { of = "ToolBeltPouch", loc = "base:fannypackback" },
    MedicHipPouchFront = { of = "MedicHipPouch", loc = "base:fannypackfront" },
}
local SWAP_FIELDS = { CanBeEquipped = true, BodyLocation = true, ClothingItem = true, ClothingItemExtra = true,
    ClothingItemExtraOption = true, ClothingExtraSubmenu = true }
local SKINS = { "Navy", "Olive" }
-- 強化版的來源＝升級配方清單裡的全部背包（原版可穿戴、沒有 AcceptItemFunction 的容器 80 種＋本 MOD 18 件）；suite 開頭算出。
-- 本 MOD 的一款一件 reinOf；原版的依穿戴網格併成形狀，每種兩件 themedOf（使用者 2026-10-27）
local REIN_SPEC, VANILLA_SPEC, OWN_SPEC = {}, {}, {}
local SATCHEL2 = "minidoracatbags:satchel2"   -- 第二個側背包位置（registries.lua）
local function reinOf(full) return "MinidoracatBags." .. full:match("[^.]+$") .. "_Reinforced" end
local function themedOf(shape, theme) return "MinidoracatBags." .. shape .. "_" .. theme .. "_Reinforced" end
local function ciOf(full) return "MDB_" .. full:match("[^.]+$") end   -- 強化版全名 → 它的 ClothingItem
local function isVanillaBag(b)
    return b.fields.ItemType == "base:container" and b.fields.CanBeEquipped ~= nil and b.fields.AcceptItemFunction == nil
end
-- 主題分類的固定點（使用者 2026-10-27：警用、警長、特警用 S.T.A.R.S.；軍用、ALICE、迷彩、醫療、自製與天然材質用保護傘；
-- 多色的照那個包的顏色：行李袋第 2 色是綠色 duffelbaggreen）。完整的 160 種在清單檔，下面另和它逐一比對
local THEME_SPEC = {
    ["Base.Bag_Police"] = { "Navy" }, ["Base.Bag_Sheriff"] = { "Navy" }, ["Base.Bag_SWAT"] = { "Navy" },
    ["Base.Bag_Military"] = { "Olive" }, ["Base.Bag_MedicalBag"] = { "Olive" }, ["Base.Bag_ALICEpack"] = { "Olive" },
    ["Base.Bag_ALICEpack_DesertCamo"] = { "Olive" }, ["Base.Bag_HideSatchel"] = { "Olive" }, ["Base.Bag_SheetSlingBag"] = { "Olive" },
    ["Base.Bag_Schoolbag_Medical"] = { "Olive", "Olive" },
    ["Base.Bag_DuffelBag"] = { "Navy", "Olive", "Navy", "Navy", "Navy", "Navy", "Navy" },
}
-- 原版地面模型寫死貼圖的 4 種網格：主題款用 ThemeDesign 的模型腳本 MinidoracatBags.MDB_<形狀>_<主題>_Ground，其他照代表款
local GROUND_OWN = { Bag_ChestRig = true, Bag_Satchel_Leather = true, Bag_CrudeLeatherBag = true, Bag_ClothSatchel_Cotton = true }
-- 清單檔的 theme_by_source：{ 來源 = { 主題, ... } }
local function readThemeTable(text)
    local out = {}
    for src, list in text:match('"theme_by_source"%s*:%s*(%b{})'):gmatch('"(Base%.[%w_]+)"%s*:%s*(%b[])') do
        out[src] = {}
        for t in list:gmatch('"(%a+)"') do out[src][#out[src] + 1] = t end
    end
    return out
end
-- 側背包鏡像對照檔（scripts/satchel_mirror_map.json，SatchelMirror 交付；沒有就照原模型路徑）。模型路徑裡沒有引號
local MIRROR_MAP = "scripts/satchel_mirror_map.json"
local function readMirrorMap(path)
    local fh = io.open(path, "rb")
    if not fh then return {} end
    local text = fh:read("*a"); fh:close()
    local map = {}
    local un = function(s) return (s:gsub("\\/", "/"):gsub("\\\\", "\\")) end
    for k, v in text:gmatch('"([^"]*)"%s*:%s*"([^"]*)"') do map[un(k)] = un(v) end
    return map
end
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
    -- 照原版（ISClothingExtraAction.lua:66-112）搬顏色（textureChoice、染色）、內容物、改名、液體（依新容量截斷）、
    -- modData（先清空再複製，InventoryItem.java:3003-3011）
    ISClothingExtraAction = {}
    function ISClothingExtraAction:createItemNew(item, newItem)
        if env.failCopy then error("copy failed") end
        if item.visual and newItem.visual then
            newItem.visual:setTint(item.visual:getTint())
            newItem.visual:setTextureChoice(item.visual:getTextureChoice())
        end
        for _, c in ipairs(item.contents or {}) do newItem.contents[#newItem.contents + 1] = c end
        item.contents = {}
        if env.failAfterMove then error("failed after moving the contents") end
        local shown = item.getName and item:getName() or item.name   -- 原版寫入 getName()（帶染血等前綴），不搬改名旗標
        if shown ~= item:getScriptItem():getDisplayName() then newItem.name = shown end
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
    function c:DoRemoveItem(i) self:Remove(i) end
    return c
end
local CONTAINER = newContainer()
local PLAYER = { getInventory = function() return CONTAINER end }
-- ItemVisual：textureChoice 與染色。single＝ClothingItem 只有一張貼圖、不能隨機染色（主題強化版）：一畫就把超出範圍的
-- textureChoice 改成 0（只能選那一張）、染色變白（ItemVisual.java:153-166、:185-196）。這裡讀的時候就照畫過的回，還原時只能靠 modData 的紀錄
local function newTint(r, g, b)
    local t = { r = r, g = g, b = b }
    function t:getRedFloat() return self.r end
    function t:getGreenFloat() return self.g end
    function t:getBlueFloat() return self.b end
    return t
end
local WHITE = newTint(1, 1, 1)
ImmutableColor = { decode = function(s)   -- ImmutableColor.java:102-119：低 8 位紅、再來綠、藍
    local n = assert(math.tointeger(tonumber(s)), "ImmutableColor.decode: not an integer string " .. tostring(s))
    return newTint((n % 256) / 255, (n // 256 % 256) / 255, (n // 65536 % 256) / 255)
end }
local function newVisual(single)
    local v = { choice = -1, tint = WHITE, single = single }
    function v:getTextureChoice() return self.single and 0 or self.choice end
    function v:setTextureChoice(c) self.choice = c end
    function v:getTint() return self.single and WHITE or self.tint end
    function v:setTint(t) self.tint = t end
    return v
end
local function isThemed(full)
    local theme = tostring(full):match("^MinidoracatBags%.Bag_.+_(%a+)_Reinforced$")
    return theme == "Navy" or theme == "Olive"
end
-- weight＝腳本自重；instanceWeight 模擬 getActualWeight()（伺服器上顯示名稱等於全名時回 0，InventoryItem.java:2740-2742）
local function newBag(cap, wr, weight, fullType)
    local b = { __class = "InventoryContainer", cap = cap, wr = wr, weight = weight, md = {}, container = CONTAINER,
        contents = {}, fullType = fullType, name = "name of " .. tostring(fullType), custom = false,
        visual = newVisual(isThemed(fullType)) }
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
    function b:getWorldItem() return self.worldItem end
    function b:setWorldItem(w) self.worldItem = w end
    function b:getFluidContainer() return self.fc end
    function b:getFluidContainerFromSelfOrWorldItem() return self.fc or (self.worldItem and self.worldItem.fc) end
    -- 世界旋轉存在物品上（InventoryItem.java:4220-4242）；沒設過時 X／Y 是 0、Z 是 -1（:279-281）
    for _, a in ipairs({ "X", "Y", "Z" }) do
        b["setWorld" .. a .. "Rotation"] = function(self, r) self["rot" .. a] = r end
        b["getWorld" .. a .. "Rotation"] = function(self) return self["rot" .. a] or (a == "Z" and -1 or 0) end
    end
    -- 內容物容器：copyClothingItem 用 takeItemsFrom 整批搬（ISClothingExtraAction.lua:74-75、ItemContainer.java:2646-2652）
    function b:getItemContainer()
        local owner = self
        return { owner = owner, takeItemsFrom = function(c, other)
            for _, it in ipairs(other.owner.contents) do c.owner.contents[#c.owner.contents + 1] = it end
            other.owner.contents = {}
        end }
    end
    function b:getFullType() return self.fullType end
    function b:getVisual() return self.visual end
    function b:synchWithVisual() end
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
    -- 腳本沒寫 Weight 時引擎預設 1.0（Item.java:83）
    local b = newBag(tonumber(s.fields.Capacity), tonumber(s.fields.WeightReduction), tonumber(s.fields.Weight) or 1.0, full)
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
    local function srcBlock(full) return VAN.items[full] or items[full] end
    VANILLA_SPEC, OWN_SPEC = {}, {}
    for full, b in pairs(VAN.items) do if isVanillaBag(b) then VANILLA_SPEC[#VANILLA_SPEC + 1] = full end end
    for k in pairs(MODELS) do for _, s in ipairs(SKINS) do OWN_SPEC[#OWN_SPEC + 1] = "MinidoracatBags." .. k .. "_" .. s end end
    for v in pairs(VARIANTS) do for _, s in ipairs(SKINS) do OWN_SPEC[#OWN_SPEC + 1] = "MinidoracatBags." .. v .. "_" .. s end end
    table.sort(VANILLA_SPEC); table.sort(OWN_SPEC)
    REIN_SPEC = {}
    for _, s in ipairs(VANILLA_SPEC) do REIN_SPEC[#REIN_SPEC + 1] = s end
    for _, s in ipairs(OWN_SPEC) do REIN_SPEC[#REIN_SPEC + 1] = s end
    local isSource = {}
    for _, s in ipairs(REIN_SPEC) do isSource[s] = true end
    -- 形狀（MDB_Upgrade.lua 的 MDB.THEME_SOURCES，產生器照清單檔寫的）：形狀 → 成員；主題強化版 44 件＋本 MOD 18 件
    loadAll()
    local themeSources, shapes, shapeOf = MDB.THEME_SOURCES or {}, {}, {}
    for src, s in pairs(themeSources) do
        shapes[s.shape] = shapes[s.shape] or {}
        table.insert(shapes[s.shape], src)
        shapeOf[src] = s.shape
    end
    local THEMED_SPEC, REIN_ITEMS = {}, {}   -- 主題強化版全名 → { shape, theme }；強化版全名 → 取欄位的來源（代表款或本 MOD 原款）
    for shape in pairs(shapes) do
        for _, t in ipairs(SKINS) do
            THEMED_SPEC[themedOf(shape, t)] = { shape = shape, theme = t }
            REIN_ITEMS[themedOf(shape, t)] = "Base." .. shape
        end
    end
    for _, s in ipairs(OWN_SPEC) do REIN_ITEMS[reinOf(s)] = s end
    local themeTable = readThemeTable(readFile(F.SHAPES))

    -- 1. 物品欄位
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    check("items: exactly 18 (14 + 4 fanny swap variants)", count == 18)
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

    -- 1a. 腰包換穿變體：欄位逐一抄原款，只差 SWAP_FIELDS；兩邊 ClothingItemExtra 互指，
    --     換穿選項與子選單照原版同一位置的腰包（container.txt:805-853）
    local vanFanny = {}
    for _, n in ipairs({ "Bag_FannyPackFront", "Bag_FannyPackBack" }) do
        local f = VAN.items["Base." .. n].fields
        vanFanny[f.BodyLocation] = f
    end
    local function paired(f, other)
        local van = vanFanny[f.BodyLocation or ""]
        return van ~= nil and f.CanBeEquipped == f.BodyLocation and f.ClothingItemExtra == other
            and f.ClothingItemExtraOption == van.ClothingItemExtraOption and f.ClothingExtraSubmenu == van.ClothingExtraSubmenu
    end
    for v, spec in pairs(VARIANTS) do
        for _, skin in ipairs(SKINS) do
            local vf, bf = "MinidoracatBags." .. v .. "_" .. skin, "MinidoracatBags." .. spec.of .. "_" .. skin
            local a, b = (items[vf] or { fields = {} }).fields, (items[bf] or { fields = {} }).fields
            local same = items[vf] ~= nil and items[bf] ~= nil
            for k, val in pairs(b) do
                if not SWAP_FIELDS[k] and a[k] ~= val then same = false; diag("    variant " .. vf .. " " .. k .. "=" .. tostring(a[k])) end
            end
            for k in pairs(a) do if not SWAP_FIELDS[k] and b[k] == nil then same = false; diag("    variant " .. vf .. " extra " .. k) end end
            check(vf .. ": fields copy " .. bf .. " except wear location and ClothingItem", same
                and a.CanBeEquipped == spec.loc and a.ClothingItem == "MDB_" .. v .. "_" .. skin)
            check(bf .. " <-> " .. vf .. ": ClothingItemExtra point at each other, option/submenu as vanilla fanny packs",
                paired(a, bf) and paired(b, vf) and a.BodyLocation ~= b.BodyLocation)
        end
    end
    -- 變體和它們的強化版：不進戰利品、殭屍掉落、任何配方產出（只靠換穿、升級與改裝取得；升級清單與 OnCreate 換型的背包行可以有）
    local onlyBase = true
    for v in pairs(VARIANTS) do
        for _, key in ipairs({ "LOOT", "ZD", "RECIPES", "CONVERT", "REIN" }) do
            local text = readFile(F[key])
            if key == "REIN" then text = text:gsub("%f[%w]item%s+[%w_]+%s*%b{}", "") end   -- 物品定義本身不算
            text = text:gsub("item 1 %[[^%]]*%] mode:keep flags%[IsNotWorn%]", "")   -- keep 背包行（升級、還原、改裝）
            if text:find(v, 1, true) then onlyBase = false; diag("    variant in " .. key .. ": " .. v) end
        end
    end
    check("variants and their reinforced versions never in loot, zombie drops, or any recipe output", onlyBase)

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

    -- 2a. 強化版（scripts/gen_reinforced.py 產生）
    --   原版 80 種依穿戴網格（ClothingItem XML 的 m_MaleModel）併成形狀，每種 Navy／Olive 兩件；本 MOD 18 件一款一件。
    --   欄位逐一照代表款（本 MOD 的照來源），只差：自重 0.1（沒寫也補）、跑速與戰鬥速度 1.0、自己的 ClothingItem、換穿法指向目標的
    --   強化版（主題款同主題）、側背包改穿第二個側背包位置、FluidContainer 換 ContainerName。主題款另外：Capacity、WeightReduction、
    --   液體容量取同組最高（中間各階不比合併前低）、DisplayCategory = Bag、Icon 換主題圖示（沒有 IconsForTexture）、手持換自己的
    --   ClothingItem、4 種網格的地面模型換主題款。XML 照來源換 GUID（全新、登記、不重複），主題款貼圖只剩主題那一張，
    --   側背包另照鏡像對照檔換男女模型
    local function xmlOf(full, ci)
        local dir = full:find("^MinidoracatBags%.") and (MEDIA .. "clothing/clothingItems/") or (PZ .. "clothing/clothingItems/")
        return ci and readFile(dir .. ci .. ".xml", true)
    end
    local function meshOf(full)
        local b = VAN.items[full]
        local path = (b and xmlOf(full, b.fields.ClothingItem) or ""):match("<m_MaleModel>([^<]*)</m_MaleModel>") or ""
        local m = path:gsub("%.[Xx]$", ""):match("([%w_]+)$")   -- 檔名，不含副檔名
        return m and m:lower()
    end
    local function nChoices(xml)
        local n = 0
        for _ in (xml or ""):gmatch("<textureChoices>") do n = n + 1 end
        return n
    end
    local function mediaFile(rel)
        local fh = io.open(MEDIA .. rel, "rb")
        if fh then fh:close() end
        return fh ~= nil
    end
    local modModels = {}
    for _, path in ipairs(listFiles(MEDIA .. "scripts/", "*.txt")) do
        local fh = io.open(path, "rb"); local text = fh:read("*a"); fh:close()
        for _, b in ipairs(parseBlocks(text, "model")) do modModels[b.module .. "." .. b.name] = true end
    end

    -- 形狀：80 種各在一種形狀裡、和代表款同網格，同網格的都在同一種；每種顏色一個主題，和清單檔與使用者的分類一致，
    --       每種顏色升級後都有對應的強化版
    local nShapes, groupOk, meshShape = 0, true, {}
    for shape, members in pairs(shapes) do
        nShapes = nShapes + 1
        local mesh = meshOf("Base." .. shape)
        if not mesh or meshShape[mesh] or not VAN.items["Base." .. shape] then groupOk = false; diag("    shape problem: " .. shape) end
        if mesh then meshShape[mesh] = shape end
        for _, m in ipairs(members) do
            if meshOf(m) ~= mesh then groupOk = false; diag("    " .. m .. " mesh " .. tostring(meshOf(m)) .. " not " .. tostring(mesh)) end
        end
    end
    local colorOk, everyColorOk, nColors = true, true, 0
    for _, src in ipairs(VANILLA_SPEC) do
        local s = themeSources[src]
        if not s then groupOk = false; diag("    no shape: " .. src)
        else
            local want = math.max(1, nChoices(xmlOf(src, VAN.items[src].fields.ClothingItem)))
            local json = themeTable[src] or {}
            if #s.themes ~= want or table.concat(s.themes, ",") ~= table.concat(json, ",") then
                colorOk = false; diag("    themes " .. src .. ": " .. table.concat(s.themes, ",") .. " want " .. want .. " = " .. table.concat(json, ","))
            end
            if THEME_SPEC[src] and table.concat(s.themes, ",") ~= table.concat(THEME_SPEC[src], ",") then colorOk = false; diag("    spec " .. src) end
            for i, t in ipairs(s.themes) do
                nColors = nColors + 1
                local r = MDB.reinforcedOf and MDB.reinforcedOf(src, i - 1)
                if r ~= themedOf(s.shape, t) or not rein[r] then everyColorOk = false; diag("    color " .. i .. " of " .. src .. " -> " .. tostring(r)) end
            end
        end
    end
    check("shapes: all " .. #VANILLA_SPEC .. " vanilla sources merged by worn mesh into " .. nShapes .. " shapes (one per mesh, keyed by the representative)",
        groupOk and #VANILLA_SPEC == 80 and nShapes == 22)
    check("shapes: one theme per texture choice (" .. nColors .. "), same as theme_shapes.json and the user's classification (police/sheriff/SWAT Navy, military/medical/natural Olive)",
        colorOk and nColors == 160)
    check("shapes: every vanilla source in every color upgrades to an existing reinforced bag of its theme", everyColorOk)

    local reinCount, nThemed, reinFieldsOk, reinXmlOk, artOk = 0, 0, true, true, true
    for _ in pairs(rein) do reinCount = reinCount + 1 end
    for _ in pairs(THEMED_SPEC) do nThemed = nThemed + 1 end
    local allThere = true
    for full in pairs(REIN_ITEMS) do if not rein[full] then allThere = false; diag("    reinforced missing: " .. full) end end
    check("reinforced: 22 shapes x 2 themes = 44, plus one per own bag (14 + 4 swap variants), nothing else",
        nThemed == 44 and allThere and reinCount == nThemed + #OWN_SPEC and #OWN_SPEC == 18)
    local mirror = readMirrorMap(MIRROR_MAP)
    local function plainXml(x) return (x:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("<m_GUID>[^<]*</m_GUID>", "")) end
    local function mirrored(x)
        for _, tag in ipairs({ "m_MaleModel", "m_FemaleModel" }) do
            x = x:gsub("<" .. tag .. ">([^<]*)</" .. tag .. ">", function(path)
                if mirror[path] then return "<" .. tag .. ">" .. mirror[path] .. "</" .. tag .. ">" end
            end)
        end
        return x
    end
    local function themedXml(x, th)
        local tex, first = "Clothes\\Bag\\MDB_" .. th.shape .. "_" .. th.theme, true
        return (x:gsub("([ \t]*)<textureChoices>[^<]*</textureChoices>\r?\n", function(ind)
            if not first then return "" end
            first = false
            return ind .. "<textureChoices>" .. tex .. "</textureChoices>\n"
        end))
    end
    local function xmlMatches(name, vxml)
        local xml = readFile(MEDIA .. "clothing/clothingItems/" .. name .. ".xml", true)
        local g = xml and xml:match("<m_GUID>%s*(.-)%s*</m_GUID>")
        local ok = xml and vxml and plainXml(xml) == plainXml(vxml) and not VAN.clothing[name] and g
            and guidOf["media/clothing/clothingItems/" .. name .. ".xml"] == g:lower() and not VAN.guids[g:lower()]
            and not seenGuid[g:lower()]
        if g then seenGuid[g:lower()] = true end
        if not ok then diag("    reinforced clothing problem: " .. name) end
        return ok
    end
    local HAND = { { "ReplaceInPrimaryHand", "_RHand" }, { "ReplaceInSecondHand", "_LHand" } }
    local satchelSources, satchel2Count, pairCount, srcPairs = 0, 0, 0, 0
    for full, src in pairs(REIN_ITEMS) do
        local r, v, th, ci = rein[full], srcBlock(src), THEMED_SPEC[full], ciOf(full)
        local ok = r ~= nil and v ~= nil
        local satchel = v ~= nil and v.fields.CanBeEquipped == "base:satchel"
        if satchel then satchelSources = satchelSources + 1 end
        if v and v.fields.ClothingItemExtra then srcPairs = srcPairs + 1 end
        if ok then
            local want, fluidCap = {}, nil
            for k, val in pairs(v.fields) do want[k] = val end
            want.Weight, want.RunSpeedModifier, want.ClothingItem = "0.1", "1.0", ci
            -- 戰鬥也不減速：來源有寫且不是 1 才改成 1.0；沒寫就不加（引擎預設 1.0，Item.java:374）
            if want.CombatSpeedModifier and tonumber(want.CombatSpeedModifier) ~= 1 then want.CombatSpeedModifier = "1.0" end
            if th then
                local cap, wr = 0, 0
                for _, m in ipairs(shapes[th.shape]) do
                    local mf = VAN.items[m].fields
                    cap, wr = math.max(cap, tonumber(mf.Capacity)), math.max(wr, tonumber(mf.WeightReduction))
                    for _, l in ipairs(VAN.items[m].lines) do
                        local c = l.text:match("^Capacity = ([%d.]+)$")
                        if c and (not fluidCap or tonumber(c) > tonumber(fluidCap)) then fluidCap = c end
                    end
                end
                want.Capacity, want.WeightReduction, want.DisplayCategory = tostring(cap), tostring(wr), "Bag"
                want.Icon, want.IconsForTexture = "MDB_" .. th.shape .. "_" .. th.theme, nil
                if GROUND_OWN[th.shape] then want.WorldStaticModel = "MinidoracatBags.MDB_" .. th.shape .. "_" .. th.theme .. "_Ground" end
                for _, h in ipairs(HAND) do
                    if want[h[1]] then want[h[1]] = (want[h[1]]:gsub("^%S+", ci .. h[2])) end
                end
                local texOk = mediaFile("textures/Item_" .. want.Icon .. ".png")
                    and mediaFile("textures/Clothes/Bag/MDB_" .. th.shape .. "_" .. th.theme .. ".png")
                    and (not GROUND_OWN[th.shape] or modModels[want.WorldStaticModel])
                if not texOk then artOk = false; diag("    theme art missing: " .. full) end
            end
            if want.ClothingItemExtra then
                local target = want.ClothingItemExtra:find(".", 1, true) and want.ClothingItemExtra or (v.module .. "." .. want.ClothingItemExtra)
                want.ClothingItemExtra = th and shapeOf[target] and themedOf(shapeOf[target], th.theme)
                    or not th and isSource[target] and reinOf(target) or "(target has no reinforced version: " .. target .. ")"
            end
            if want.CanBeEquipped == "base:satchel" then want.CanBeEquipped = SATCHEL2 end
            if want.BodyLocation == "base:satchel" then want.BodyLocation = SATCHEL2 end
            for k, val in pairs(want) do
                if r.fields[k] ~= val then ok = false; diag("    reinforced " .. full .. " " .. k .. "=" .. tostring(r.fields[k]) .. " want " .. val) end
            end
            for k in pairs(r.fields) do if want[k] == nil then ok = false; diag("    reinforced " .. full .. " extra field " .. k) end end
            ok = ok and #r.lines == #v.lines
            -- 液體元件照來源，只有 ContainerName 改成自己的（顯示名稱取 Fluid_Container_<ContainerName>，FluidContainer.java:398-404）
            for i, l in ipairs(v.lines) do
                local wantLine = l.text:gsub("^ContainerName = .*$", "ContainerName = " .. ci)
                if fluidCap then wantLine = wantLine:gsub("^Capacity = .*$", "Capacity = " .. fluidCap) end
                if not (r.lines[i] ~= nil and r.lines[i].text == wantLine) then ok = false; diag("    reinforced " .. full .. " line " .. l.text) end
            end
            if r.fields.CanBeEquipped == SATCHEL2 then satchel2Count = satchel2Count + 1 end
            -- 換穿法成對：目標的強化版也指回這一款
            local x = r.fields.ClothingItemExtra
            if x then
                pairCount = pairCount + 1
                if not (rein[x] and rein[x].fields.ClothingItemExtra == full) then ok = false; diag("    extra not paired: " .. full) end
            end
        end
        if not ok then reinFieldsOk = false end
        local vxml = v and xmlOf(src, v.fields.ClothingItem)
        if vxml and satchel then vxml = mirrored(vxml) end
        if vxml and th then vxml = themedXml(vxml, th) end
        if not xmlMatches(ci, vxml) then reinXmlOk = false end
        for _, h in ipairs(th and v and HAND or {}) do
            local hand = v.fields[h[1]] and v.fields[h[1]]:match("^%S+")
            if hand and not xmlMatches(ci .. h[2], themedXml(xmlOf(src, hand) or "", th)) then reinXmlOk = false end
        end
    end
    check("reinforced: fields copy the representative / own source except Weight 0.1, RunSpeed/CombatSpeed 1.0, own ClothingItem, extra -> paired reinforced, satchel -> "
        .. SATCHEL2 .. "; themed: highest Capacity/WeightReduction/fluid of the shape, DisplayCategory Bag, theme Icon, own hand ClothingItems, theme ground model for 4 meshes",
        reinFieldsOk)
    check("reinforced: theme icons, textures and ground models exist", artOk)
    local slowCombat = {}
    for full, r in pairs(rein) do
        local c = tonumber(r.fields.CombatSpeedModifier or "1")
        if not c or c < 1 then slowCombat[#slowCombat + 1] = full end
    end
    check("reinforced: no CombatSpeedModifier below 1 (" .. table.concat(slowCombat, ",") .. ")", #slowCombat == 0)
    check("reinforced: every satchel (" .. satchelSources .. " = 3 shapes x 2 + 2 own) wears in " .. SATCHEL2 .. ", no reinforced bag uses base:satchel",
        satchelSources == 8 and satchel2Count == satchelSources and not readFile(F.REIN):find("base:satchel", 1, true))
    -- 成對數照來源算：原版前、後腰包各一種形狀 × 2 主題，本 MOD 兩款腰包 × 2 外觀 × 前後
    check("reinforced: every swap pair (" .. pairCount .. " items = 2 themed fanny shapes x 2 + 8 own) points at each other's reinforced version",
        pairCount == srcPairs and pairCount == 12)
    check("reinforced: ClothingItem XML (worn and in hand) = source XML with only the theme texture (satchels via mirror map if present) and a new registered unique GUID",
        reinXmlOk)
    check("reinforced: never in loot or zombie drops", not readFile(F.LOOT):find("Reinforced", 1, true)
        and not readFile(F.ZD):find("Reinforced", 1, true))
    -- 還原、「已升級原版背包改成強化版」、換主題：背包 keep＋不能穿著、沒有產出，換型在 OnCreate
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
    local tset, tn = bagSet(reinRecipes.MDB_SwapReinforcedTheme)
    local covered = rn == reinCount and mn == #REIN_SPEC and tn == nThemed
    for full in pairs(REIN_ITEMS) do covered = covered and rset[full] and (tset[full] or not THEMED_SPEC[full]) end
    for _, s in ipairs(REIN_SPEC) do covered = covered and mset[s] end
    local rr, mr, tr = reinRecipes.MDB_RestoreReinforced, reinRecipes.MDB_ReinforceUpgradedBag, reinRecipes.MDB_SwapReinforcedTheme
    local recipeCount = 0
    for _ in pairs(reinRecipes) do recipeCount = recipeCount + 1 end
    check("restore / reinforce-upgraded / swap-theme recipes: exactly these 3; bags = all " .. reinCount .. " reinforced / all "
        .. #REIN_SPEC .. " sources / the " .. nThemed .. " themed ones", recipeCount == 3 and covered == true)
    check("MDB_RestoreReinforced: scissors kept, no other input, no outputs, MDB.onSwapKeepTier, no OnTest",
        rr ~= nil and #rr.lines == 2 and hasLine(rr, "item 1 tags[base:scissors] mode:keep flags[IsNotDull;MayDegradeLight]")
        and noOutputs(rr) and rr.fields.OnCreate == "MDB.onSwapKeepTier" and rr.fields.OnTest == nil)
    check("MDB_ReinforceUpgradedBag: needle kept, no outputs, OnTest MDB.onTestUpgraded, MDB.onSwapKeepTier",
        mr ~= nil and #mr.lines == 2 and hasLine(mr, "item 1 tags[base:sewingneedle] mode:keep") and noOutputs(mr)
        and mr.fields.OnTest == "MDB.onTestUpgraded" and mr.fields.OnCreate == "MDB.onSwapKeepTier")
    check("MDB_SwapReinforcedTheme: needle kept + thread 1, no skill, no outputs, MDB.onSwapTheme, no OnTest",
        tr ~= nil and #tr.lines == 3 and hasLine(tr, "item 1 tags[base:sewingneedle] mode:keep") and hasLine(tr, "item 1 tags[base:thread]")
        and noOutputs(tr) and tr.fields.OnCreate == "MDB.onSwapTheme" and tr.fields.OnTest == nil and tr.fields.SkillRequired == nil)

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
    -- 變體：圖示、地面模型（欄位已和原款相同）與貼圖沿用原款，穿戴 .X 是自己的（build.py <變體>）
    for v, spec in pairs(VARIANTS) do
        for _, skin in ipairs(SKINS) do
            local P = "MDB_" .. v .. "_"
            check(v .. "_" .. skin .. ": worn ClothingItem uses own .X and the " .. spec.of .. " texture",
                xmlOk(P .. skin, P .. "M", P .. "F", "MDB_" .. spec.of .. "_" .. skin))
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
    -- 升級配方：背包清單＝原版可穿戴、無 AcceptItemFunction 的容器 80 種＋14 件新背包＋4 件換穿變體（也就是全部強化版來源）
    --          ＋全部強化版（主題 44 件、本 MOD 18 件）
    local expectBags = {}
    for _, s in ipairs(REIN_SPEC) do expectBags[s] = true end
    for full in pairs(REIN_ITEMS) do expectBags[full] = true end
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
        check("MDB_UpgradeBagTier" .. t .. ": bag list = 80 wearable vanilla containers + 14 new + 4 variants + all 62 reinforced", setOk)
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
    -- 強化版水袋：Fluids.json（引擎依檔名分表，Translator.java:159）有 Fluid_Container_<ContainerName>。裝水時顯示「液體(容器名稱)」，
    -- 所以 16 語的容器名稱都不帶括號（不會變兩層），而且含該語的強化詞（使用者 2026-10-27 選定）
    local FLUID_WORD = { AR = "reforzada", CH = "強化", CN = "强化", DE = "Verstärkt", EN = "Reinforced", ES = "reforzada",
        ES_CL = "Reforzada", ES_MX = "reforzada", FR = "renforcé", JP = "強化", KO = "강화", PL = "Wzmocnion", PT = "Reforçad",
        PTBR = "Reforçad", RU = "Укреплённ", TR = "Güçlendirilmiş" }
    local fluidNames, fluidOk = {}, true
    for full, b in pairs(rein) do
        for _, l in ipairs(b.lines) do
            local cn = l.text:match("^ContainerName = (%S+)$")
            if cn then fluidNames[full] = cn end
        end
    end
    local function jsonValue(text, key)
        return text and text:match('\n%s*"' .. key:gsub("%p", "%%%0") .. '"%s*:%s*"(.-)"%s*,?\n')
    end
    local fluidCount = 0
    for full, cn in pairs(fluidNames) do
        fluidCount = fluidCount + 1
        for _, lang in ipairs(LANGS) do
            local fluid = jsonValue(readFile(TRANSLATE .. lang .. "/Fluids.json", true), "Fluid_Container_" .. cn)
            local word = FLUID_WORD[lang]
            if not fluid or fluid:find("[()]") or fluid:find("（", 1, true) or fluid:find("）", 1, true)
                or not word or not fluid:find(word, 1, true) then
                fluidOk = false; diag("    fluid container name: " .. lang .. " " .. cn .. " = " .. tostring(fluid))
            end
        end
    end
    check("reinforced water bags: Fluid_Container_<ContainerName> in 16 Fluids.json has the reinforced word and no brackets",
        fluidOk and fluidCount == 2)
    -- 換穿變體在 16 語和原款同名
    local variantNameOk = true
    for v, spec in pairs(VARIANTS) do
        for _, skin in ipairs(SKINS) do
            for _, lang in ipairs(LANGS) do
                local text = readFile(TRANSLATE .. lang .. "/ItemName.json", true)
                local a = jsonValue(text, "MinidoracatBags." .. v .. "_" .. skin)
                if not a or a ~= jsonValue(text, "MinidoracatBags." .. spec.of .. "_" .. skin) then
                    variantNameOk = false; diag("    variant name: " .. lang .. " " .. v .. "_" .. skin)
                end
            end
        end
    end
    check("variants: ItemName in 16 languages = their original pouch", variantNameOk)
    -- 主題強化版的名稱：主題詞與語序照本 MOD 7 款的譯名（從日行背包兩款與它的強化版算出前後、保護傘的詞、強化標記），
    -- 兩個主題只差主題詞；英文另核對＝主題詞＋代表款的原版名稱＋標記。水袋的容器名稱也帶主題詞（使用者 2026-10-27）
    local vanEN = readFile(PZ .. "lua/shared/Translate/EN/ItemName.json", true)
    local themeNameOk = true
    for _, lang in ipairs(LANGS) do
        local text = readFile(TRANSLATE .. lang .. "/ItemName.json", true)
        local fluids = readFile(TRANSLATE .. lang .. "/Fluids.json", true)
        local navy = jsonValue(text, "MinidoracatBags.DayPack_Navy") or ""
        local olive = jsonValue(text, "MinidoracatBags.DayPack_Olive") or ""
        local prefix = navy:sub(1, 11) == "S.T.A.R.S. "
        local base = prefix and navy:sub(12) or navy:sub(1, -12)
        local words = { Navy = "S.T.A.R.S.", Olive = prefix and olive:sub(1, #olive - #base - 1) or olive:sub(#base + 2) }
        local mark = (jsonValue(text, "MinidoracatBags.DayPack_Navy_Reinforced") or ""):sub(#navy + 1)
        for full, th in pairs(THEMED_SPEC) do
            local name, w = jsonValue(text, full) or "", words[th.theme]
            local core = #mark > 0 and name:sub(-#mark) == mark and name:sub(1, -#mark - 1) or ""
            local bare = prefix and core:sub(1, #w + 1) == w .. " " and core:sub(#w + 2)
                or not prefix and core:sub(-#w - 1) == " " .. w and core:sub(1, -#w - 2)
            local other = themedOf(th.shape, th.theme == "Navy" and "Olive" or "Navy")
            local otherBare = (jsonValue(text, other) or ""):sub(1, -#mark - 1)
            local ok = bare and bare ~= "" and otherBare:find(bare, 1, true) ~= nil
                and (lang ~= "EN" or bare == jsonValue(vanEN, "Base." .. th.shape))
            local fc = full:find("Hydration", 1, true) and jsonValue(fluids, "Fluid_Container_" .. ciOf(full))
            if fc and not fc:find(w, 1, true) then ok = false end
            if not ok then themeNameOk = false; diag("    themed name: " .. lang .. " " .. full .. " = " .. name) end
        end
    end
    check("themed reinforced names (and water bag container names) carry the theme word in the order of the own 7 bags, English = theme + vanilla name + (Reinforced)",
        themeNameOk)

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
    -- 本 MOD 腰包與換穿變體互換（第 2 階往返）：階級、容量、負重減輕照舊，換完還能升第 3 階
    local variantSwapOk = true
    for v, spec in pairs(VARIANTS) do
        for _, skin in ipairs(SKINS) do
            local base, var = "MinidoracatBags." .. spec.of .. "_" .. skin, "MinidoracatBags." .. v .. "_" .. skin
            local a = instanceItem(base)
            MDB.applyTier(a, 1); MDB.applyTier(a, 2)
            local b = ISClothingExtraAction:createItemNew(a, instanceItem(var))
            local c = ISClothingExtraAction:createItemNew(b, instanceItem(base))
            local want = TIERS[spec.of][3]
            for _, x in ipairs({ b, c }) do
                if not (x.md.MDB_tier == 2 and x.cap == want[1] and x.wr == want[2]) then
                    variantSwapOk = false; diag(string.format("    variant swap %s: tier %s %d/%d", var, tostring(x.md.MDB_tier), x.cap, x.wr))
                end
            end
            local ok3 = MDB.onTestTier3(b) and not MDB.onTestTier2(b)
            MDB.applyTier(b, 3)
            if not (ok3 and b.cap == 49 and b.wr == 100) then variantSwapOk = false; diag("    variant tier 3 after swap: " .. var) end
        end
    end
    check("own fanny pouches <-> swap variants keep tier 2 both ways and still upgrade to 49/100", variantSwapOk)

    -- 8c. 強化版：對照表、各階數值、升級換型（照顏色選主題、記下原款）、還原（換回原款與顏色）、換主題、腰包換穿、
    --     0.1.0 升過級的原版背包
    local specOk = #(MDB.REINFORCED_SOURCES or {}) == #OWN_SPEC
    for _, s in ipairs(OWN_SPEC) do
        local r = MDB.REINFORCED[s]
        specOk = specOk and r == reinOf(s) and MDB.ORIGINAL[r] == s and MDB.reinforcedOf(s) == r
    end
    for full, th in pairs(THEMED_SPEC) do
        local t = MDB.THEMED[full]
        specOk = specOk and MDB.ORIGINAL[full] == "Base." .. th.shape and t and t.shape == th.shape and t.theme == th.theme
    end
    check("REINFORCED_SOURCES = the 18 own bags (REINFORCED / ORIGINAL both ways); the 44 themed ones restore to the representative by default",
        specOk)
    local tiersOk, nTiers = true, 0
    for full in pairs(REIN_ITEMS) do
        nTiers = nTiers + 1
        local b = instanceItem(full)
        for t = 1, 3 do MDB.applyTier(b, t) end
        if not (b.weight == 0.1 and b.cap == 49 and b.wr == 100) then tiersOk = false; diag("    reinforced tier 3: " .. full) end
    end
    check("reinforced: all " .. nTiers .. " weigh 0.1 and reach 49/100 at tier 3", tiersOk and nTiers == 62)
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
    local A, RA = "Base.Bag_ALICEpack", "MinidoracatBags.Bag_ALICEpack_Olive_Reinforced"
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
    okSwap, new = swapped(old, "MinidoracatBags.Bag_HydrationBackpack_Navy_Reinforced")
    check("upgrade: water bag 2.0 L full -> reinforced tier 1 with 3.667 L (base = the camo pack's 3.0 L), water kept",
        okSwap and near(new.fc.capacity, 3.667) and near(new.fc.amount, 2.0) and new.md.MDB_fluid == 3.0)
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
    old = stocked("MinidoracatBags.Bag_HydrationBackpack_Navy_Reinforced")
    MDB.applyTier(old, 3)
    old.fc.amount = 5.0
    MDB.onSwapKeepTier(keepData(old), PLAYER)
    okSwap, new = swapped(old, "Base.Bag_HydrationBackpack")
    check("restore: tier-3 water bag keeps 5.0 L capacity and all 5.0 L of water",
        okSwap and new.md.MDB_tier == 3 and near(new.fc.capacity, 5.0) and near(new.fc.amount, 5.0))
    -- 一般水袋（2 升）的主題款從組內最高的 3 升起算：第 1 階 3.667 升裝滿再還原，照原款公式只有 3 升。
    -- 換型不倒水，容量留在換型前的值；空的照原款自己的值
    old = stocked("Base.Bag_HydrationBackpack", nil, 2.0)
    MDB.onUpgrade(keepData(old), PLAYER)
    old = CONTAINER.items[1]
    old.fc.amount = old.fc.capacity
    MDB.onSwapKeepTier(keepData(old), PLAYER)
    okSwap, new = swapped(old, "Base.Bag_HydrationBackpack")
    check("restore: full tier-1 water bag (3.667 L) -> plain water bag (formula 3.0 L) keeps 3.667 L capacity and all the water",
        okSwap and new.md.MDB_tier == 1 and near(new.fc.capacity, 3.667) and near(new.fc.amount, 3.667) and new.md.MDB_fluid == 2.0)
    old = stocked("Base.Bag_HydrationBackpack")
    MDB.onUpgrade(keepData(old), PLAYER)
    MDB.onSwapKeepTier(keepData(CONTAINER.items[1]), PLAYER)
    new = CONTAINER.items[1]
    check("restore: empty tier-1 water bag -> plain water bag at its own formula 3.0 L",
        new.fullType == "Base.Bag_HydrationBackpack" and new.md.MDB_tier == 1 and near(new.fc.capacity, 3.0))

    -- 每個原版來源的每種顏色：升級換成那個顏色的主題款，記下原款與顏色；還原換回原款、同一個顏色、階級照舊
    local colorUpOk, colorBackOk = true, true
    for _, src in ipairs(VANILLA_SPEC) do
        for i, t in ipairs(themeTable[src] or {}) do
            CONTAINER.items = {}
            local b = CONTAINER:AddItem(instanceItem(src))
            b.visual.choice = i - 1
            MDB.onUpgrade(keepData(b), PLAYER)
            local up = CONTAINER.items[1]
            if not (up.fullType == themedOf(shapeOf[src] or "?", t) and up.md.MDB_origin == src and up.md.MDB_originTex == i - 1
                and up.md.MDB_tier == 1) then
                colorUpOk = false; diag("    upgrade color " .. i .. " of " .. src .. " -> " .. up.fullType)
            end
            MDB.onSwapKeepTier(keepData(up), PLAYER)
            local back = CONTAINER.items[1]
            if not (back.fullType == src and back.visual:getTextureChoice() == i - 1 and back.md.MDB_tier == 1) then
                colorBackOk = false; diag("    restore color " .. i .. " of " .. src .. " -> " .. back.fullType .. " " .. back.visual:getTextureChoice())
            end
        end
    end
    check("upgrade: every vanilla source in every color (160) -> reinforced of that color's theme, original and color recorded", colorUpOk)
    check("restore: every one of them goes back to the recorded original in the same color, tier kept", colorBackOk)
    -- 階級的基準換成新背包自己的：側背包組最高 13（皮側背包），釣具側背包 12、自重 1.0
    old = stocked("Base.Bag_Satchel_Fishing")
    MDB.onUpgrade(keepData(old), PLAYER)
    new = CONTAINER.items[1]
    local upCap = new.cap
    MDB.onSwapKeepTier(keepData(new), PLAYER)
    local fish = CONTAINER.items[1]
    check("tier base follows the new bag: fishing satchel tier 1 -> themed 25/77 (base 13) -> restored fishing satchel 24/77 (base 12)",
        new.fullType == "MinidoracatBags.Bag_Satchel_Leather_Olive_Reinforced" and upCap == 25 and fish.fullType == "Base.Bag_Satchel_Fishing"
        and fish.md.MDB_tier == 1 and fish.cap == 24 and fish.wr == 77 and fish.md.MDB_cap == 12)
    -- 隨機染色的原版（小偷袋）：主題款一畫就變白，還原時換回記下的染色
    old = stocked("Base.Bag_BurglarBag")
    old.visual.tint = newTint(0.2, 0.4, 0.6)
    MDB.onUpgrade(keepData(old), PLAYER)
    MDB.onSwapKeepTier(keepData(CONTAINER.items[1]), PLAYER)
    local tint = CONTAINER.items[1].visual:getTint()
    check("restore: randomly tinted burglar bag gets its recorded tint back",
        CONTAINER.items[1].fullType == "Base.Bag_BurglarBag" and math.abs(tint.r - 0.2) < 0.003
        and math.abs(tint.g - 0.4) < 0.003 and math.abs(tint.b - 0.6) < 0.003)
    -- 沒有紀錄、或記的不是這個形狀：還原成代表款
    local LT = "MinidoracatBags.Bag_Satchel_Leather_Navy_Reinforced"
    old = stocked(LT)
    MDB.onSwapKeepTier(keepData(old), PLAYER)
    local plainBack = CONTAINER.items[1].fullType
    old = stocked(LT, { MDB_origin = "Base.Bag_DuffelBag", MDB_originTex = 3 })
    MDB.onSwapKeepTier(keepData(old), PLAYER)
    check("restore: no record -> representative; a record of another shape is ignored",
        plainBack == "Base.Bag_Satchel_Leather" and CONTAINER.items[1].fullType == "Base.Bag_Satchel_Leather")

    -- 換主題：S.T.A.R.S.↔保護傘，階級、容量、內容物、改過的名字、記下的原款、液體照舊；伺服器只送一次
    local DN, DO = "MinidoracatBags.Bag_DuffelBag_Navy_Reinforced", "MinidoracatBags.Bag_DuffelBag_Olive_Reinforced"
    env.server, env.sent = true, {}
    old = stocked(DN, { MDB_origin = "Base.Bag_Police", MDB_originTex = 0 })
    MDB.applyTier(old, 2)
    local capBefore = old.cap
    env.sent = {}
    MDB.onSwapTheme(keepData(old), PLAYER)
    okSwap, new = swapped(old, DO)
    check("swap theme (server): Navy duffel tier 2 -> Olive, same tier/capacity, contents, custom name, recorded original, one replace",
        okSwap and new.md.MDB_tier == 2 and new.cap == capBefore and new.md.MDB_origin == "Base.Bag_Police" and #env.sent == 1
        and env.sent[1][2] == old and env.sent[1][3] == new)
    MDB.onSwapTheme(keepData(new), PLAYER)
    check("swap theme: and back to Navy", CONTAINER.items[1].fullType == DN and CONTAINER.items[1].md.MDB_tier == 2)
    env.server = false
    old = stocked(DN)
    old.custom, old.name = false, "name of " .. DN
    MDB.onSwapTheme(keepData(old), PLAYER)
    check("swap theme: un-renamed bag gets the other theme's name", CONTAINER.items[1].name == "name of " .. DO)
    old = stocked("MinidoracatBags.Bag_HydrationBackpack_Olive_Reinforced")
    MDB.applyTier(old, 3)
    old.fc.amount = 5.0
    MDB.onSwapTheme(keepData(old), PLAYER)
    new = CONTAINER.items[1]
    check("swap theme: tier-3 water bag keeps 5.0 L capacity and all the water",
        new.fullType == "MinidoracatBags.Bag_HydrationBackpack_Navy_Reinforced" and near(new.fc.capacity, 5.0) and near(new.fc.amount, 5.0))
    local untouched = true
    for _, full in ipairs({ "MinidoracatBags.DayPack_Navy_Reinforced", "MinidoracatBags.DayPack_Navy", A }) do
        old = stocked(full)
        MDB.onSwapTheme(keepData(old), PLAYER)
        untouched = untouched and CONTAINER.items[1] == old
    end
    check("swap theme: own bags (reinforced or not) and vanilla bags are left alone", untouched)

    -- 強化版腰包換前後（原版換穿法 → 包裝依 MDB_tier 重算）
    local front = instanceItem("MinidoracatBags.Bag_FannyPackFront_Navy_Reinforced")
    for t = 1, 3 do MDB.applyTier(front, t) end
    local back = ISClothingExtraAction:createItemNew(front, instanceItem("MinidoracatBags.Bag_FannyPackBack_Navy_Reinforced"))
    check("reinforced fanny pack front -> back keeps tier 3 = 49/100", back.md.MDB_tier == 3 and back.cap == 49 and back.wr == 100)
    -- 獸皮腰包（1／65）升級成保護傘腰包（組內最高 1／85），換穿到後背照樣是保護傘款、階級照舊
    old = stocked("Base.Bag_FannyPackFront_Hide")
    MDB.onUpgrade(keepData(old), PLAYER)
    local hide = CONTAINER.items[1]
    MDB.applyTier(hide, 2)
    local hideX = (rein[hide.fullType] or { fields = {} }).fields.ClothingItemExtra
    local hideBack = SCRIPT_BLOCKS[hideX] and ISClothingExtraAction:createItemNew(hide, instanceItem(hideX))
    check("hide fanny pack -> Umbrella fanny front (base 1/85), swapped to its back keeps tier 2 = 33/95",
        hide.fullType == "MinidoracatBags.Bag_FannyPackFront_Olive_Reinforced" and hideBack
        and hideBack.fullType == "MinidoracatBags.Bag_FannyPackBack_Olive_Reinforced" and hideBack.md.MDB_tier == 2
        and hideBack.cap == 33 and hideBack.wr == 95)
    -- 換穿過前後再還原：記的是升級時那一面的原款，還原成它在這一面的版本（原版換穿法的另一面），顏色照記下的
    CONTAINER.items = {}
    CONTAINER:AddItem(hideBack)
    MDB.onSwapKeepTier(keepData(hideBack), PLAYER)
    new = CONTAINER.items[1]
    check("hide fanny pack upgraded on the front, swapped to the back, restored -> hide fanny pack (back), tier 2",
        new.fullType == "Base.Bag_FannyPackBack_Hide" and new.md.MDB_tier == 2 and new.md.MDB_origin == "Base.Bag_FannyPackBack_Hide")
    old = stocked("Base.Bag_FannyPackFront")
    old.visual.choice = 2
    MDB.onUpgrade(keepData(old), PLAYER)
    local frontUp = CONTAINER.items[1]
    local backUp = ISClothingExtraAction:createItemNew(frontUp, instanceItem("MinidoracatBags.Bag_FannyPackBack_Navy_Reinforced"))
    CONTAINER.items = {}
    CONTAINER:AddItem(backUp)
    MDB.onSwapKeepTier(keepData(backUp), PLAYER)
    new = CONTAINER.items[1]
    check("fanny pack in its 3rd color upgraded, swapped front -> back, restored -> vanilla back fanny pack in the 3rd color",
        new.fullType == "Base.Bag_FannyPackBack" and new.visual:getTextureChoice() == 2 and new.md.MDB_tier == 1)
    -- 改過名的腰包換穿再升級（E2EWear H5）：換穿要帶著改名旗標與不帶前綴的名字，升級才會沿用
    old = stocked("Base.Bag_FannyPackFront")   -- 改名 My Bag、第 0 階（沒有 MDB_tier）
    function old:getName() return "Bloody, " .. self.name end
    local renamedBack = ISClothingExtraAction:createItemNew(old, instanceItem("Base.Bag_FannyPackBack"))
    check("renamed tier-0 fanny pack front -> back keeps the custom flag and the name without the bloody prefix",
        renamedBack.name == "My Bag" and renamedBack.custom == true)
    CONTAINER.items = {}
    CONTAINER:AddItem(renamedBack)
    MDB.onUpgrade(keepData(renamedBack), PLAYER)
    new = CONTAINER.items[1]
    check("renamed fanny pack swapped to the back, then upgraded: reinforced back tier 1 keeps the name",
        new.fullType == "MinidoracatBags.Bag_FannyPackBack_Navy_Reinforced" and new.md.MDB_tier == 1
        and new.name == "My Bag" and new.custom == true)

    -- 本 MOD 的背包也是來源：第一次升級換成自己的強化版（日行背包 20／75，自重 0.1 → 第 1 階 30／83）
    local D, RD = "MinidoracatBags.DayPack_Navy", "MinidoracatBags.DayPack_Navy_Reinforced"
    env.server, env.sent = true, {}
    old = stocked(D)
    MDB.onUpgrade(keepData(old), PLAYER)
    okSwap, new = swapped(old, RD)
    check("upgrade (server): own DayPack tier 0 -> DayPack_Navy_Reinforced tier 1 = 30/83, one replace",
        okSwap and new.md.MDB_tier == 1 and new.cap == 30 and new.wr == 83 and #env.sent == 1 and env.sent[1][3] == new)
    env.sent = {}
    MDB.onSwapKeepTier(keepData(new), PLAYER)
    local restored = CONTAINER.items[1]
    check("restore: own reinforced DayPack -> DayPack_Navy keeps tier 1 (weight 0.8: 20/75 -> 30/83)",
        restored.fullType == D and restored.md.MDB_tier == 1 and restored.cap == 30 and restored.wr == 83 and #env.sent == 1)
    env.server = false
    -- 強化版醫療腰包照樣只收醫療用品（AcceptItemFunction 照抄）
    check("own reinforced MedicHipPouch keeps AcceptItemFunction = MDB.acceptFirstAid",
        rein["MinidoracatBags.MedicHipPouch_Olive_Reinforced"] ~= nil
        and rein["MinidoracatBags.MedicHipPouch_Olive_Reinforced"].fields.AcceptItemFunction == "MDB.acceptFirstAid")

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

    -- 8c. 地上（含桌面）的背包：Neat Crafting 的「製作」不先搬進物品欄，背包直接當輸入（正式服 0.2.0 每次都在伺服器丟例外）。
    --     伺服器上 getContainer() 是 nil（ContainerID.java:392-396、:566-575）；單機是背包面板的地面容器。
    --     放上地面時液體元件搬到世界物品上，移除時搬回來（IsoWorldInventoryObject.java:103-105、:650-653）
    local function floorSquare()
        local sq = { objs = {}, removed = {} }
        function sq:AddWorldInventoryItem(item, x, y, z, transmit)   -- IsoGridSquare.java:6071-6146：transmit 預設 true
            local wi = { item = item, sq = self, x = x, y = y, z = z, sent = transmit == false and 0 or 1, fc = item.fc }
            item.fc = nil
            -- 建構子把 X／Y 旋轉歸零、Z 沒設過時隨機給（IsoWorldInventoryObject.java:74-78）
            item.rotX, item.rotY = 0, 0
            if not item.rotZ or item.rotZ < 0 then item.rotZ = 42 end
            function wi:getSquare() return self.sq end
            function wi:getOffX() return self.x end
            function wi:getOffY() return self.y end
            function wi:getOffZ() return self.z end
            function wi:transmitCompleteItemToClients() self.sent = self.sent + 1 end
            function wi:setIgnoreRemoveSandbox(v) self.ignore = v end
            function wi:isIgnoreRemoveSandbox() return self.ignore == true end
            function wi:setExtendedPlacement(v) self.ext = v end
            function wi:isExtendedPlacement() return self.ext == true end
            function wi:hasComponent(t) return t == ComponentType.FluidContainer and self.fc ~= nil end
            -- SWAP_ITEM 送的是物品自己的存檔（IsoWorldInventoryObject.java:158-166）：記下送出當下物品身上的數值與液體元件
            function wi:sendObjectChange(change)
                local it = self.item
                self.changes = self.changes or {}
                self.changes[#self.changes + 1] = { change = change, cap = it.cap, wr = it.wr, fc = it.fc,
                    fcap = it.fc and it.fc.capacity, famount = it.fc and it.fc.amount }
            end
            self.objs[#self.objs + 1] = wi
            item.worldItem = wi
            return item
        end
        function sq:transmitRemoveItemFromSquare(wi) self.removed[#self.removed + 1] = wi end
        function sq:removeWorldObject(wi)
            wi.item.fc, wi.fc = wi.fc, nil
            for k, v in ipairs(self.objs) do if v == wi then table.remove(self.objs, k); return end end
        end
        return sq
    end
    local function onFloor(full, floorC)
        local sq, b = floorSquare(), instanceItem(full)
        b.contents, b.md = { "nail", "apple" }, { custom = "kept" }
        sq:AddWorldInventoryItem(b, 0.3, 0.6, 0.1)
        if floorC then floorC:AddItem(b) end
        return b, sq, b.worldItem
    end
    DesignationZoneAnimal = { removeItemFromGround = function(wi) env.groundRemoved = wi end }
    ComponentType = { FluidContainer = "FluidContainer" }
    IsoObjectChange = { SWAP_ITEM = "SWAP_ITEM" }
    GameEntityFactory = { TransferComponent = function(src, dst, t)   -- GameEntityFactory.java:68-81
        if t ~= ComponentType.FluidContainer then error("unexpected component " .. tostring(t)) end
        dst.fc, src.fc = src.fc, nil
    end }
    env.server, env.sent, env.replaced = true, {}, {}
    local oldWi, sq
    old, sq, oldWi = onFloor(A)
    old.rotX, old.rotY, old.rotZ, oldWi.ignore, oldWi.ext = 10, 20, 135, true, true   -- 玩家用「放置」擺過（ISDropWorldItemAction.lua:81-87）
    MDB.onUpgrade(keepData(old), PLAYER)
    local nwi = sq.objs[1]
    check("floor (MP server, no container): reinforced bag on the same spot with the contents, old world item removed",
        #sq.objs == 1 and nwi.item ~= old and nwi.item.fullType == RA and nwi.x == 0.3 and nwi.y == 0.6 and nwi.z == 0.1
        and nwi.item.contents[1] == "nail" and #old.contents == 0 and nwi.item.md.custom == "kept"
        and nwi.item.md.MDB_tier == 1 and nwi.item.cap == 35 and nwi.item.wr == 90
        and sq.removed[1] == oldWi and env.groundRemoved == oldWi and old.worldItem == nil)
    check("floor (MP server): new world item sent once, no container packets, no SWAP_ITEM during the swap",
        nwi.sent == 1 and nwi.changes == nil and #env.sent == 0 and #env.replaced == 0)
    check("floor (MP server): placed rotation and the keep-from-cleanup / extended-placement flags carried over",
        nwi.item.rotX == 10 and nwi.item.rotY == 20 and nwi.item.rotZ == 135 and nwi.ignore == true and nwi.ext == true)
    old, sq, oldWi = onFloor(RA)
    old.md.MDB_tier, old.md.MDB_cap, old.md.MDB_wr, old.cap, old.wr = 3, 28, 85, 49, 100
    MDB.onSwapTheme(keepData(old), PLAYER)
    nwi = sq.objs[1]
    check("floor (MP server): theme swap on the ground -> Navy, tier 3 49/100, contents kept",
        #sq.objs == 1 and nwi.item.fullType == "MinidoracatBags.Bag_ALICEpack_Navy_Reinforced" and nwi.item.md.MDB_tier == 3
        and nwi.item.cap == 49 and nwi.item.wr == 100 and nwi.item.contents[1] == "nail" and nwi.sent == 1 and old.worldItem == nil)
    local HY, HN = "MinidoracatBags.Bag_HydrationBackpack_Olive_Reinforced", "MinidoracatBags.Bag_HydrationBackpack_Navy_Reinforced"
    old = stocked(HY)
    MDB.applyTier(old, 3)
    CONTAINER.items = {}
    old.container, old.fc.amount = nil, 4.0
    sq = floorSquare()
    sq:AddWorldInventoryItem(old, 0.3, 0.6, 0.1)
    MDB.onSwapTheme(keepData(old), PLAYER)
    nwi = sq.objs[1]
    check("floor (MP server): water bag theme swap on the ground keeps 5.0 L capacity and the 4.0 L of water",
        #sq.objs == 1 and nwi.item.fullType == HN and nwi.fc and near(nwi.fc.capacity, 5.0) and near(nwi.fc.amount, 4.0) and nwi.item.fc == nil)
    old, sq = stocked("Base.Bag_HydrationBackpack", nil, 2.0), floorSquare()
    CONTAINER.items = {}
    old.container = nil
    sq:AddWorldInventoryItem(old, 0.3, 0.6, 0.1)
    MDB.onUpgrade(keepData(old), PLAYER)
    nwi = sq.objs[1]
    check("floor (MP server): first upgrade of a water bag on the ground -> tier 1 capacity 3.667, 2.0 L kept",
        #sq.objs == 1 and nwi.item.fullType == HN and near(nwi.fc.capacity, 3.0 + 2.0 / 3) and near(nwi.fc.amount, 2.0))
    old, sq, oldWi = onFloor(A)
    env.failCopy = true
    failed = not pcall(MDB.swapBag, old, RA, 1, PLAYER)
    env.failCopy = false
    check("floor swap error before moving: only the old bag on the ground with its contents, nothing sent or removed",
        failed and #sq.objs == 1 and sq.objs[1] == oldWi and old.worldItem == oldWi and #sq.removed == 0 and old.contents[1] == "nail")
    old, sq, oldWi = onFloor(A)
    env.failAfterMove = true
    failed = not pcall(MDB.swapBag, old, RA, 1, PLAYER)
    env.failAfterMove = false
    check("floor swap error after moving: contents back in the old bag, the unsent new one taken off the square",
        failed and #sq.objs == 1 and sq.objs[1] == oldWi and old.worldItem == oldWi and #sq.removed == 0
        and old.contents[1] == "nail" and old.contents[2] == "apple")
    -- 已經是強化版的背包在地上原地升階（只 applyTier、不換型）：伺服器送世界物品的 SWAP_ITEM，客戶端換上收到的那份、ID 照舊
    -- （IsoWorldInventoryObject.java:115-153、:175-180）；送的當下液體元件要在物品上，送完搬回世界物品
    local function tierOnFloor(full, tier, water)
        local s, b = floorSquare(), instanceItem(full)
        MDB.applyTier(b, tier)   -- 還沒放上地面，不送
        b.contents, b.md.custom = { "nail", "apple" }, "kept"
        if water then b.fc.amount = water end
        s:AddWorldInventoryItem(b, 0.3, 0.6, 0.1)
        return b, s, b.worldItem
    end
    env.sent, env.replaced = {}, {}
    old, sq, oldWi = tierOnFloor(RA, 1)
    local cap1 = old.cap
    MDB.onUpgrade(keepData(old), PLAYER)
    local ch = oldWi.changes or {}
    check("floor (MP server): reinforced bag upgraded in place -> tier 2, one SWAP_ITEM with the new values, nothing else sent or removed",
        #sq.objs == 1 and sq.objs[1] == oldWi and oldWi.item == old and old.md.MDB_tier == 2 and old.cap > cap1
        and #ch == 1 and ch[1].change == "SWAP_ITEM" and ch[1].cap == old.cap and ch[1].wr == old.wr
        and oldWi.sent == 1 and #sq.removed == 0 and #env.sent == 0 and #env.replaced == 0 and old.contents[1] == "nail" and old.md.custom == "kept")
    old, sq, oldWi = tierOnFloor(HN, 1, 2.0)
    local wfc = oldWi.fc
    MDB.onUpgrade(keepData(old), PLAYER)
    ch = oldWi.changes or {}
    check("floor (MP server): water bag upgraded in place -> the SWAP_ITEM carries the fluid (4.333 capacity, 2.0 L), then it is back on the world item",
        #ch == 1 and ch[1].fc == wfc and near(ch[1].fcap, 3.0 + 4.0 / 3) and near(ch[1].famount, 2.0)
        and oldWi.fc == wfc and old.fc == nil and old.md.MDB_tier == 2)
    old, sq, oldWi = tierOnFloor(RA, 2)
    old.container = CONTAINER   -- 兩樣都有時以地上為準
    MDB.onUpgrade(keepData(old), PLAYER)
    check("floor (MP server): a world item wins over a container: SWAP_ITEM only", #(oldWi.changes or {}) == 1 and #env.sent == 0)
    old.container = nil
    env.server, env.sent, env.replaced = false, {}, {}
    local floorC = newContainer()
    old, sq, oldWi = onFloor(A, floorC)
    MDB.onUpgrade(keepData(old), PLAYER)
    check("floor (SP, inventory-pane floor container): swapped on the ground, old one out of the floor container, nothing sent",
        #sq.objs == 1 and sq.objs[1].item.fullType == RA and sq.objs[1].sent == 0 and #floorC.items == 0 and old.worldItem == nil
        and #env.sent == 0 and #env.replaced == 0)
    old, sq, oldWi = tierOnFloor(RA, 1)
    MDB.onUpgrade(keepData(old), PLAYER)
    check("floor (SP): in-place upgrade on the ground sends nothing", old.md.MDB_tier == 2 and oldWi.changes == nil and #env.sent == 0)
    old = instanceItem(A)
    old.contents = { "nail" }
    local okNowhere, errNowhere = pcall(MDB.swapBag, old, RA, 1, PLAYER)
    check("bag neither in a container nor on the ground: refused with a clear error, contents untouched",
        not okNowhere and tostring(errNowhere):find("neither in a container nor on the ground", 1, true) ~= nil and old.contents[1] == "nail")

    -- 8d. 第二個側背包位置：registries.lua 註冊（非 base、先查再註冊），MDB_BodyLocations.lua 加進 Human 群組、排在 base:satchel
    --     後面、不設互斥／隱藏、可以邊走邊穿脫；沒註冊到時不把 nil 傳給 getOrCreateLocation
    local function bodyLocEnv(groupIds)
        local reg, e = {}, { registered = 0, rules = 0, nilCalls = 0 }
        ResourceLocation = { of = function(id)
            local ns, p = id:match("^([^:]+):(.+)$")
            if not ns then ns, p = "base", id end
            return { ns = ns:lower(), id = (ns .. ":" .. p):lower() }
        end }
        ItemBodyLocation = {}
        function ItemBodyLocation.get(rl) return reg[rl.id] end
        function ItemBodyLocation.register(id)   -- RegistryReset.java:15-21、Registry.java:30-39
            local rl = ResourceLocation.of(id)
            if rl.ns == "base" then error("Default namespace 'base' is not allowed!") end
            if reg[rl.id] then error("Tried to register duplicate object: " .. rl.id) end
            e.registered = e.registered + 1
            reg[rl.id] = { id = rl.id }
            return reg[rl.id]
        end
        for _, id in ipairs({ "base:fannypackback", "base:ammostrap", "base:satchel", "base:shoulderholster", "base:back" }) do
            reg[id] = { id = id }
        end
        ItemBodyLocation.SATCHEL = reg["base:satchel"]
        local group = { list = {} }
        for _, id in ipairs(groupIds) do group.list[#group.list + 1] = reg[id] end
        function group:getOrCreateLocation(loc)
            if loc == nil then e.nilCalls = e.nilCalls + 1 end
            for _, l in ipairs(self.list) do if l == loc then return l end end
            self.list[#self.list + 1] = loc
        end
        function group:indexOf(loc)
            for i, l in ipairs(self.list) do if l == loc then return i - 1 end end
            return -1
        end
        function group:moveLocationToIndex(loc, index)   -- BodyLocationGroup.java:53-62
            if index < 0 or index >= #self.list then return end
            local i = self:indexOf(loc)
            if i >= 0 then table.insert(self.list, index + 1, table.remove(self.list, i + 1)) end
        end
        function group:setExclusive() e.rules = e.rules + 1 end
        function group:setHideModel() e.rules = e.rules + 1 end
        BodyLocations = { getGroup = function(name) assert(name == "Human"); return group end }
        ISWearClothing = { WalkBodyLocations = { reg["base:satchel"] } }
        package.loaded["NPCs/BodyLocations"] = true
        package.loaded["TimedActions/ISWearClothing"] = true
        e.group, e.reg = group, reg
        return e
    end
    local function ids(list) local t = {} for i, l in ipairs(list) do t[i] = l.id end return table.concat(t, ",") end
    local groupIds = { "base:fannypackback", "base:ammostrap", "base:satchel", "base:shoulderholster", "base:back" }
    local be = bodyLocEnv(groupIds)
    local regOk = pcall(function() loadLua("REG"); loadLua("REG") end)
    check("registries.lua: registers " .. SATCHEL2 .. " once (non-base namespace; second run skips instead of throwing)",
        regOk and be.registered == 1 and be.reg[SATCHEL2] ~= nil)
    loadLua("BODYLOC")
    check("MDB_BodyLocations: " .. SATCHEL2 .. " right after base:satchel in the Human group, no exclusive/hide rules",
        ids(be.group.list) == "base:fannypackback,base:ammostrap,base:satchel," .. SATCHEL2 .. ",base:shoulderholster,base:back"
        and be.rules == 0)
    check("MDB_BodyLocations: can be put on while walking like base:satchel (ISWearClothing.WalkBodyLocations)",
        ISWearClothing.WalkBodyLocations[2] == be.reg[SATCHEL2])
    be = bodyLocEnv({ "base:fannypackback", "base:back" })
    loadLua("REG"); loadLua("BODYLOC")
    check("MDB_BodyLocations: without base:satchel in the group it is appended last",
        ids(be.group.list) == "base:fannypackback,base:back," .. SATCHEL2)
    be = bodyLocEnv(groupIds)
    env.printed = {}
    loadLua("BODYLOC")   -- registries.lua 沒跑
    check("MDB_BodyLocations: unregistered location -> no getOrCreateLocation(nil), group unchanged, one error line",
        be.nilCalls == 0 and ids(be.group.list) == table.concat(groupIds, ",") and #env.printed == 1
        and env.printed[1]:find("[MinidoracatBagsFor42] ERROR", 1, true) == 1)
    check("satchel2 ID is the same in registries.lua, MDB_BodyLocations.lua, gen_reinforced.py and the reinforced scripts",
        MDB.SATCHEL2_ID == SATCHEL2 and readFile(F.REG):find('"' .. SATCHEL2 .. '"', 1, true) ~= nil
        and readFile(F.GEN):find('SATCHEL2 = "' .. SATCHEL2 .. '"', 1, true) ~= nil
        and readFile(F.REIN):find("CanBeEquipped = " .. SATCHEL2 .. ",", 1, true) ~= nil)

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

-- 側背包鏡像對照檔（SatchelMirror 交付）：存在時改寫強化版側背包 XML 的男女模型，不存在時照原路徑，--check 都比對。
-- 用暫存的對照檔跑產生器：真正的對照檔（有的話）加上一個測試鍵，只有用到那個模型的強化版側背包 XML 會變
local function gen(args)
    local p = io.popen("uv run --quiet scripts/gen_reinforced.py " .. args .. " 2>&1")
    local out = p:read("a")
    return p:close() == true, out
end
do
    local tmpDir = os.getenv("TEMP") or os.getenv("TMPDIR") or "."
    local mapPath = tmpDir .. "/mdb_mirror_test.json"
    local function writeMap(map)
        local parts = {}
        for k, v in pairs(map) do parts[#parts + 1] = '"' .. k:gsub("\\", "\\\\") .. '": "' .. v:gsub("\\", "\\\\") .. '"' end
        local fh = assert(io.open(mapPath, "wb")); fh:write("{" .. table.concat(parts, ", ") .. "}"); fh:close()
    end
    local real = readMirrorMap(MIRROR_MAP)
    local okAbsent = gen('--check --mirror-map "' .. tmpDir .. '/mdb_no_such_mirror_map.json"')
    check("mirror map absent: generator keeps the source model paths", okAbsent == (next(real) == nil))
    -- 測試鍵：某個強化版側背包來源的男模型（真對照檔有這個鍵時，覆蓋它的值）；值：原版大背包的男模型
    local reinText = readFile(F.REIN)
    local back = {}
    for k, v in pairs(real) do back[v] = k end
    local satchelXml, testKey, current = {}, nil, nil
    for name, body in reinText:gmatch("item%s+([%w_]+)%s*(%b{})") do
        if body:find("CanBeEquipped = " .. SATCHEL2 .. ",", 1, true) then
            local ci = body:match("ClothingItem = ([%w_]+),")
            local xml = readFile(MEDIA .. "clothing/clothingItems/" .. ci .. ".xml", true) or ""
            satchelXml[ci .. ".xml"] = xml
            local male = xml:match("<m_MaleModel>([^<]*)</m_MaleModel>")
            if male and male ~= "" and not testKey then testKey, current = back[male] or male, male end
        end
    end
    local testValue = "media\\models_X\\Skinned\\BackPacks\\M_ALICE_Pack.X"
    local expected = {}
    for file, xml in pairs(satchelXml) do
        if xml:find(">" .. current .. "<", 1, true) then expected[file] = true end
    end
    local map = {}
    for k, v in pairs(real) do map[k] = v end
    map[testKey] = testValue
    writeMap(map)
    local okMap, out = gen('--check --mirror-map "' .. mapPath .. '"')
    local listed, onlyExpected = {}, true
    for file in out:gmatch("(MDB_[%w_]+_Reinforced%.xml)") do
        listed[file] = true
        if not expected[file] then onlyExpected = false end
    end
    local allListed = next(expected) ~= nil
    for file in pairs(expected) do allListed = allListed and listed[file] == true end
    check("mirror map present: --check reports exactly the reinforced satchel XMLs using the mapped model",
        not okMap and onlyExpected and allListed and not out:find("MDB_Reinforced.txt", 1, true))
    local anyFile = next(expected)
    local okPrint, printed = gen('--mirror-map "' .. mapPath .. '" --print ' .. (anyFile or "none"))
    check("mirror map present: generated satchel XML uses the mirror model and keeps everything else",
        okPrint and printed:find("<m_MaleModel>" .. testValue .. "</m_MaleModel>", 1, true) ~= nil
        and not printed:find(">" .. testKey .. "<", 1, true)
        and printed:gsub("<m_MaleModel>[^<]*</m_MaleModel>", "") == satchelXml[anyFile]:gsub("<m_MaleModel>[^<]*</m_MaleModel>", ""))
    map[testKey] = nil
    map["media\\models_X\\Skinned\\BackPacks\\M_ALICE_Pack.X"] = testValue
    writeMap(map)
    local okStale, staleOut = gen('--check --mirror-map "' .. mapPath .. '"')
    check("mirror map with a key no satchel uses: generator stops", not okStale and staleOut:find("M_ALICE_Pack", 1, true) ~= nil)
    map = {}
    for k, v in pairs(real) do map[k] = v end
    map[testKey] = "media\\models_X\\Skinned\\BackPacks\\MDB_NoSuchMirror.X"
    writeMap(map)
    local okMissing, missingOut = gen('--check --mirror-map "' .. mapPath .. '"')
    check("mirror map pointing at a missing model: generator stops", not okMissing and missingOut:find("MDB_NoSuchMirror", 1, true) ~= nil)
    os.remove(mapPath)
end

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
        { name = "單機也重送", file = "UPG", from = "if isServer() and not swapping then", to = "if not swapping then" },
        { name = "地上升階不重送", file = "UPG", from = "            wi:sendObjectChange(IsoObjectChange.SWAP_ITEM)\n", to = "" },
        { name = "地上升階走容器重送", file = "UPG", from = "local wi, container = bag:getWorldItem(), bag:getContainer()", to = "local wi, container = nil, bag:getContainer()" },
        { name = "地上升階送出時液體不在物品上", file = "UPG", from = "            if fluid then GameEntityFactory.TransferComponent(wi, bag, ComponentType.FluidContainer) end\n", to = "" },
        { name = "地上升階送完液體沒搬回地上", file = "UPG", from = "            if fluid then GameEntityFactory.TransferComponent(bag, wi, ComponentType.FluidContainer) end\n", to = "" },
        { name = "非背包輸入被擋", file = "UPG", from = 'if not instanceof(item, "InventoryContainer") then return true end', to = 'if not instanceof(item, "InventoryContainer") then return false end' },
        { name = "OnTest 不看 MaxTier", file = "UPG", from = 'return tier <= MDB.opt("MaxTier") and', to = "return" },
        { name = "OnTest 階級差一", file = "UPG", from = "tierOf(item) == tier - 1", to = "tierOf(item) <= tier - 1" },
        { name = "onUpgrade 不看 MaxTier", file = "UPG", from = 'if tier > MDB.opt("MaxTier") then return end', to = "" },
        { name = "換穿法沒包裝", file = "UPG", from = "function ISClothingExtraAction:createItemNew(item, newItem)", to = "function MDB:unusedCreateItemNew(item, newItem)" },
        { name = "升級不換型", file = "UPG", from = "    if MDB.reinforcedOf(ft) then\n", to = "    if false then\n" },
        { name = "換型途中照送", file = "UPG", from = "if isServer() and not swapping then", to = "if isServer() then" },
        { name = "換型最後不送", file = "UPG", from = "        sendReplaceItemInContainer(cont, old, new)\n", to = "" },
        { name = "單機不換動作佇列", file = "UPG", from = "        replaceItemInContainer(cont, old, new)", to = "" },
        { name = "舊背包沒移除", file = "UPG", from = "    cont:Remove(old)", to = "" },
        { name = "液體沒在容量設好後重搬", file = "UPG", from = "            nfc:copyFluidsFrom(ofc)\n", to = "" },
        { name = "出錯沒復原旗標", file = "UPG", from = "    swapping = false\n    if not ok", to = "    if not ok" },
        { name = "新背包沒先放進容器", file = "UPG", from = "    cont:AddItem(new)\n", to = "" },
        { name = "地上沒帶 X 旋轉", file = "UPG", from = "        new:setWorldXRotation(old:getWorldXRotation())\n", to = "" },
        { name = "地上沒帶 Y 旋轉", file = "UPG", from = "        new:setWorldYRotation(old:getWorldYRotation())\n", to = "" },
        { name = "地上沒帶 Z 旋轉", file = "UPG", from = "        new:setWorldZRotation(old:getWorldZRotation())\n", to = "" },
        { name = "地上沒帶防清除旗標", file = "UPG", from = "        new:getWorldItem():setIgnoreRemoveSandbox(wi:isIgnoreRemoveSandbox())\n", to = "" },
        { name = "地上沒帶延伸擺放旗標", file = "UPG", from = "        new:getWorldItem():setExtendedPlacement(wi:isExtendedPlacement())\n", to = "" },
        { name = "地上沒先放新背包", file = "UPG", from = "        wi:getSquare():AddWorldInventoryItem(new, wi:getOffX(), wi:getOffY(), wi:getOffZ(), false)\n", to = "" },
        { name = "地上新背包放錯位置", file = "UPG", from = "wi:getOffX(), wi:getOffY(), wi:getOffZ()", to = "0.5, 0.5, 0" },
        { name = "地上新背包做完前就送", file = "UPG", from = "wi:getOffZ(), false)", to = "wi:getOffZ())" },
        { name = "地上新背包沒送", file = "UPG", from = "if isServer() then new:getWorldItem():transmitCompleteItemToClients() end", to = "" },
        { name = "地上舊背包沒移除", file = "UPG", from = "        sq:removeWorldObject(wi)\n", to = "" },
        { name = "地上舊背包移除沒廣播", file = "UPG", from = "        sq:transmitRemoveItemFromSquare(wi)\n", to = "" },
        { name = "地上沒清動物分區紀錄", file = "UPG", from = "        DesignationZoneAnimal.removeItemFromGround(wi)\n", to = "" },
        { name = "舊背包留著世界物品參照", file = "UPG", from = "        old:setWorldItem(nil)\n", to = "" },
        { name = "單機地面容器沒移除", file = "UPG", from = "if cont then cont:DoRemoveItem(old) end", to = "" },
        { name = "沒容器也沒在地上照做", file = "UPG", from = "if not wi and not cont then error(", to = "if false then error(" },
        { name = "地上背包走容器分支", file = "UPG", from = "    local wi = old:getWorldItem()\n", to = "    local wi = nil\n" },
        { name = "地上液體只看物品本身", file = "UPG", from = "local ofc = old:getFluidContainerFromSelfOrWorldItem()", to = "local ofc = old:getFluidContainer()" },
        { name = "套階級不看地上的液體", file = "UPG", from = "local fc = bag:getFluidContainerFromSelfOrWorldItem()", to = "local fc = bag:getFluidContainer()" },
        { name = "出錯沒搬回內容物", file = "UPG", from = "            old:getItemContainer():takeItemsFrom(new:getItemContainer())\n", to = "" },
        { name = "出錯沒撤掉新背包", file = "UPG", from = "            wi:getSquare():removeWorldObject(nwi)\n", to = "" },
        { name = "換穿沒搬改名旗標", file = "UPG", from = "        newItem:setCustomName(true)\n", to = "" },
        { name = "換穿沿用帶前綴的名字", file = "UPG", from = "        newItem:setName(item:getDisplayName())\n", to = "" },
        { name = "沒改名也沿用舊名", file = "UPG", from = "            new:setName(new:getScriptItem():getDisplayName())\n", to = "" },
        { name = "還原掉級", file = "UPG", from = "MDB.swapBag(bag, back, tierOf(bag), character)", to = "MDB.swapBag(bag, back, 0, character)" },
        { name = "第 0 階也能改強化版", file = "UPG", from = "tierOf(item) >= 1", to = "tierOf(item) >= 0" },
        { name = "主題表少一款", file = "UPG", from = '    ["Base.Bag_SWAT"] = { shape = "Bag_DuffelBag", themes = { "Navy" } },\n', to = "" },
        { name = "對照表少本 MOD 一款", file = "UPG", from = '"MinidoracatBags.DayPack_Navy", ', to = "" },
        { name = "本 MOD 背包升級不換型", file = "UPG", from = "    if MDB.reinforcedOf(ft) then\n", to = "    if MDB.THEME_SOURCES[ft] then\n" },
        { name = "胸掛沒補自重", file = "REIN", from = "    item Bag_ChestRig_Navy_Reinforced\n    {\n        DisplayCategory = Bag,\n        ItemType = base:container,\n        Weight = 0.1,\n", to = "    item Bag_ChestRig_Navy_Reinforced\n    {\n        DisplayCategory = Bag,\n        ItemType = base:container,\n" },
        { name = "強化側背包穿回原版位置", file = "REIN", from = "CanBeEquipped = minidoracatbags:satchel2,", to = "CanBeEquipped = base:satchel," },
        { name = "主題腰包換穿指回原版", file = "REIN", from = "ClothingItemExtra = MinidoracatBags.Bag_FannyPackFront_Olive_Reinforced,", to = "ClothingItemExtra = Base.Bag_FannyPackFront," },
        { name = "腰包換穿換了主題", file = "REIN", from = "ClothingItemExtra = MinidoracatBags.Bag_FannyPackBack_Navy_Reinforced,", to = "ClothingItemExtra = MinidoracatBags.Bag_FannyPackBack_Olive_Reinforced," },
        { name = "本 MOD 強化版丟了放入限制", file = "REIN", from = "AcceptItemFunction = MDB.acceptFirstAid,", to = "" },
        { name = "強化版前腰醫療包丟了放入限制", file = "REIN", from = "        AcceptItemFunction = MDB.acceptFirstAid,\n    }\n\n    item AmmoBandolier_Navy_Reinforced", to = "    }\n\n    item AmmoBandolier_Navy_Reinforced" },
        { name = "強化版變體換穿指回非強化", file = "REIN", from = "ClothingItemExtra = MinidoracatBags.ToolBeltPouch_Navy_Reinforced,", to = "ClothingItemExtra = MinidoracatBags.ToolBeltPouch_Navy," },
        { name = "強化版原款換穿沒成對", file = "REIN", from = "ClothingItemExtra = MinidoracatBags.MedicHipPouchFront_Olive_Reinforced,", to = "ClothingItemExtra = MinidoracatBags.MedicHipPouchFront_Navy_Reinforced," },
        { name = "對照表少變體", file = "UPG", from = '"MinidoracatBags.ToolBeltPouchBack_Olive",', to = "" },
        { name = "強化版變體成了配方產出", file = "CONVERT", from = "item 1 MinidoracatBags.Bag_SheetSlingBag_Olive_Reinforced,", to = "item 1 MinidoracatBags.MedicHipPouchFront_Navy_Reinforced," },
        { name = "強化版變體被放進戰利品", file = "LOOT", from = '{ "NurseOutfit"', to = '{ "MedicHipPouchFront_Olive_Reinforced", "x" }, { "NurseOutfit"' },
        { name = "註冊用 base 命名空間", file = "REG", from = 'ItemBodyLocation.register("minidoracatbags:satchel2")', to = 'ItemBodyLocation.register("satchel2")' },
        { name = "註冊沒先查", file = "REG", from = 'if not ItemBodyLocation.get(ResourceLocation.of("minidoracatbags:satchel2")) then', to = "if true then" },
        { name = "位置沒移到側背包後面", file = "BODYLOC", from = "        group:moveLocationToIndex(loc, satchel + 1)", to = "" },
        { name = "位置排在側背包前面", file = "BODYLOC", from = "satchel + 1)", to = "satchel)" },
        { name = "位置 ID 和註冊不同", file = "BODYLOC", from = 'MDB.SATCHEL2_ID = "minidoracatbags:satchel2"', to = 'MDB.SATCHEL2_ID = "minidoracatbags:satchel3"' },
        { name = "沒註冊也傳 nil", file = "BODYLOC", from = "    if not loc then", to = "    if false then" },
        { name = "位置不能邊走邊穿", file = "BODYLOC", from = "    table.insert(ISWearClothing.WalkBodyLocations, loc)\n", to = "" },
        { name = "位置設了互斥", file = "BODYLOC", from = "    table.insert(ISWearClothing.WalkBodyLocations, loc)\n", to = "    table.insert(ISWearClothing.WalkBodyLocations, loc)\n    group:setExclusive(loc, ItemBodyLocation.SATCHEL)\n" },
        { name = "強化版自重錯", file = "REIN", from = "Weight = 0.1,", to = "Weight = 0.2," },
        { name = "強化版跑速沒改", file = "REIN", from = "RunSpeedModifier = 1.0,", to = "RunSpeedModifier = 0.94," },
        { name = "產生器不改戰鬥速度（胸掛）", file = "REIN", from = "        CombatSpeedModifier = 1.0,\n        Researchablerecipes = MakeTarpChestRig,", to = "        CombatSpeedModifier = 0.99,\n        Researchablerecipes = MakeTarpChestRig," },
        { name = "產生器不改戰鬥速度（背帶）", file = "REIN", from = "CombatSpeedModifier = 1.0,", to = "CombatSpeedModifier = 0.98," },
        { name = "強化版沿用原版 ClothingItem", file = "REIN", from = "ClothingItem = MDB_Bag_Satchel_Navy_Reinforced,", to = "ClothingItem = Bag_Satchel," },
        { name = "強化版多一個欄位", file = "REIN", from = "ClothingItem = MDB_Bag_Satchel_Navy_Reinforced,", to = "ClothingItem = MDB_Bag_Satchel_Navy_Reinforced,\n        AcceptItemFunction = MDB.acceptAmmo," },
        { name = "強化版水袋容量改了", file = "REIN", from = "Capacity = 3.0,", to = "Capacity = 5.0," },
        { name = "水袋液體容量沒取組內最高", file = "REIN", from = "Capacity = 3.0,", to = "Capacity = 2.0," },
        { name = "強化版水袋沿用原版容器名", file = "REIN", from = "ContainerName = MDB_Bag_HydrationBackpack_Navy_Reinforced,", to = "ContainerName = HydrationBackpack," },
        { name = "液體容器名稱缺鍵", file = "I18N_FLUIDS", from = '"Fluid_Container_MDB_Bag_HydrationBackpack_Olive_Reinforced"', to = '"Fluid_Container_MDB_X"' },
        { name = "液體容器名稱帶括號", file = "I18N_FLUIDS", from = '"S.T.A.R.S. Reinforced Hydration Pack"', to = '"S.T.A.R.S. Hydration Pack (Reinforced)"' },
        { name = "液體容器名稱沒有強化詞", file = "I18N_FLUIDS", from = '"S.T.A.R.S. Reinforced Hydration Pack"', to = '"S.T.A.R.S. Hydration Pack"' },
        { name = "液體容器名稱沒有主題詞", file = "I18N_FLUIDS", from = '"Umbrella Reinforced Hydration Pack"', to = '"Reinforced Hydration Pack"' },
        { name = "還原配方漏一款", file = "REIN", from = "MinidoracatBags.Bag_GolfBag_Olive_Reinforced;", to = "" },
        { name = "還原配方可用穿著中的背包", file = "REIN", from = "_Reinforced] mode:keep flags[IsNotWorn],", to = "_Reinforced] mode:keep," },
        { name = "改強化版配方沒 OnTest", file = "REIN", from = "OnTest = MDB.onTestUpgraded,", to = "" },
        { name = "強化版 XML 換了模型", file = "REIN_XML", from = "<m_MaleModel>", to = "<m_MaleModel>x" },
        { name = "升級清單漏強化版", file = "RECIPES", from = "MinidoracatBags.Bag_GolfBag_Olive_Reinforced;", to = "" },
        { name = "翻譯缺強化版名稱", file = "I18N_ITEMS", from = '"MinidoracatBags.Bag_GolfBag_Olive_Reinforced"', to = '"MinidoracatBags.Bag_GolfBagX_Olive_Reinforced"' },
        -- 合併與主題（使用者 2026-10-27）
        { name = "升級不照顏色選主題", file = "UPG", from = "s.themes[(choice or 0) + 1] or s.themes[1]", to = "s.themes[1]" },
        { name = "顏色索引差一", file = "UPG", from = "s.themes[(choice or 0) + 1]", to = "s.themes[(choice or 0) + 2]" },
        { name = "主題表顏色錯", file = "UPG", from = '["Base.Bag_DuffelBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Olive"', to = '["Base.Bag_DuffelBag"] = { shape = "Bag_DuffelBag", themes = { "Navy", "Navy"' },
        { name = "主題表形狀錯", file = "UPG", from = '["Base.Bag_HideSatchel"] = { shape = "Bag_ClothSatchel_Cotton"', to = '["Base.Bag_HideSatchel"] = { shape = "Bag_Satchel_Leather"' },
        { name = "升級沒記原款", file = "UPG", from = "md.MDB_origin, md.MDB_originTex = sourceType, choice", to = "md.MDB_originTex = choice" },
        { name = "還原不看紀錄", file = "UPG", from = "    if t and s and s.shape == t.shape then back = md.MDB_origin end\n", to = "" },
        { name = "還原沒核對形狀", file = "UPG", from = "if t and s and s.shape == t.shape then", to = "if t and s then" },
        { name = "還原沒換回顏色", file = "UPG", from = "            v:setTextureChoice(md.MDB_originTex or -1)\n", to = "" },
        { name = "還原沒換回染色", file = "UPG", from = "            if md.MDB_originTint then v:setTint(ImmutableColor.decode(md.MDB_originTint)) end\n", to = "" },
        { name = "換型沿用舊基準", file = "UPG", from = "        md.MDB_cap, md.MDB_wr, md.MDB_fluid = cap, wr, fluid\n", to = "" },
        { name = "換主題沒換", file = "UPG", from = 't.theme == "Navy" and "Olive" or "Navy"', to = "t.theme" },
        { name = "換主題掉級", file = "UPG", from = '"Olive" or "Navy"), tierOf(bag), character)', to = '"Olive" or "Navy"), 0, character)' },
        { name = "換型截掉液體", file = "UPG", from = "            if ofc:getAmount() > nfc:getCapacity() then nfc:setCapacity(ofc:getCapacity()) end\n", to = "" },
        { name = "還原沒走換穿對應", file = "UPG", from = "s.shape ~= t.shape and s.pair and", to = "false and" },
        { name = "主題表少換穿對應", file = "UPG", from = ', pair = "Base.Bag_FannyPackBack_Hide" },', to = " }," },
        { name = "換主題配方漏一款", file = "REIN", from = "inputs\n        {\n            item 1 [MinidoracatBags.Bag_DuffelBag_Navy_Reinforced;MinidoracatBags.Bag_DuffelBag_Olive_Reinforced;MinidoracatBags.Bag_ClothSatchel_Cotton_Navy_Reinforced;", to = "inputs\n        {\n            item 1 [MinidoracatBags.Bag_DuffelBag_Navy_Reinforced;MinidoracatBags.Bag_ClothSatchel_Cotton_Navy_Reinforced;" },
        { name = "換主題配方消耗針", file = "REIN", from = "            item 1 tags[base:sewingneedle] mode:keep,\n            item 1 tags[base:thread],", to = "            item 1 tags[base:sewingneedle],\n            item 1 tags[base:thread]," },
        { name = "換主題配方要技能", file = "REIN", from = "OnCreate = MDB.onSwapTheme,", to = "OnCreate = MDB.onSwapTheme,\n        SkillRequired = Tailoring:1," },
        { name = "主題強化版容量沒取組內最高", file = "REIN", from = "    item Bag_SheetSlingBag_Navy_Reinforced\n    {\n        DisplayCategory = Bag,\n        ItemType = base:container,\n        Weight = 0.1,\n        Icon = MDB_Bag_SheetSlingBag_Navy,\n        CanBeEquipped = base:back,\n        CanHaveHoles = false,\n        Capacity = 14,", to = "    item Bag_SheetSlingBag_Navy_Reinforced\n    {\n        DisplayCategory = Bag,\n        ItemType = base:container,\n        Weight = 0.1,\n        Icon = MDB_Bag_SheetSlingBag_Navy,\n        CanBeEquipped = base:back,\n        CanHaveHoles = false,\n        Capacity = 10," },
        { name = "主題強化版用了別的主題圖示", file = "REIN", from = "Icon = MDB_Bag_Schoolbag_Olive,", to = "Icon = MDB_Bag_Schoolbag_Navy," },
        { name = "主題地面模型換回原版", file = "REIN", from = "WorldStaticModel = MinidoracatBags.MDB_Bag_CrudeLeatherBag_Olive_Ground,", to = "WorldStaticModel = CrudeLeatherBag_Ground," },
        { name = "手持沿用原版 ClothingItem", file = "REIN", from = "ReplaceInPrimaryHand = MDB_Bag_GolfBag_Navy_Reinforced_RHand holdingbagright,", to = "ReplaceInPrimaryHand = Bag_GolfBag_RHand holdingbagright," },
        { name = "強化版 XML 貼圖沒換", file = "REIN_XML", from = "Clothes\\Bag\\MDB_Bag_Satchel_Navy", to = "clothes\\bag\\satchel" },
        { name = "手持 XML 貼圖是另一個主題", file = "REIN_HAND_XML", from = "MDB_Bag_DuffelBag_Olive", to = "MDB_Bag_DuffelBag_Navy" },
        { name = "主題詞放錯邊", file = "I18N_ITEMS", from = '"S.T.A.R.S. Duffel Bag (Reinforced)"', to = '"Duffel Bag S.T.A.R.S. (Reinforced)"' },
        { name = "主題名稱少主題詞", file = "I18N_ITEMS", from = '"Umbrella Duffel Bag (Reinforced)"', to = '"Duffel Bag (Reinforced)"' },
        { name = "清單檔分類和產生結果不同", file = "SHAPES", from = '"Base.Bag_Police": [\n   "Navy"', to = '"Base.Bag_Police": [\n   "Olive"' },
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
        { name = "工具包換穿指回原版腰包", file = "ITEMS", from = "ClothingItemExtra = MinidoracatBags.ToolBeltPouchBack_Navy,", to = "ClothingItemExtra = Base.Bag_FannyPackBack," },
        { name = "變體沒指回原款", file = "ITEMS", from = "ClothingItemExtra = MinidoracatBags.MedicHipPouch_Olive,", to = "ClothingItemExtra = MinidoracatBags.MedicHipPouch_Navy," },
        { name = "換穿選項前後顛倒", file = "ITEMS", from = "ClothingItemExtraOption = FannyPack_WearBack,\n        ClothingExtraSubmenu = FannyPack_WearFront,", to = "ClothingItemExtraOption = FannyPack_WearFront,\n        ClothingExtraSubmenu = FannyPack_WearBack," },
        { name = "變體穿戴位置沒改", file = "ITEMS", from = "CanBeEquipped = base:fannypackback,\n        CanHaveHoles = false,\n        Capacity = 3,", to = "CanBeEquipped = base:fannypackfront,\n        CanHaveHoles = false,\n        Capacity = 3," },
        { name = "變體容量和原款不同", file = "ITEMS", from = "Capacity = 4,\n        WeightReduction = 85,\n        RunSpeedModifier = 0.99,\n        ClothingItem = MDB_MedicHipPouchFront_Navy,", to = "Capacity = 5,\n        WeightReduction = 85,\n        RunSpeedModifier = 0.99,\n        ClothingItem = MDB_MedicHipPouchFront_Navy," },
        { name = "變體少放入限制", file = "ITEMS", from = "        AcceptItemFunction = MDB.acceptFirstAid,\n    }\n\n    /* 自製模型（scripts/blender/bags/build.py）；欄位照原版 Base.AmmoStrap_Shells */", to = "    }\n\n    /* 自製模型（scripts/blender/bags/build.py）；欄位照原版 Base.AmmoStrap_Shells */" },
        { name = "變體 XML 換了貼圖", file = "VARIANT_XML", from = "MDB_MedicHipPouch_Olive</textureChoices>", to = "MDB_MedicHipPouchFront_Olive</textureChoices>" },
        { name = "變體 XML 借原款模型", file = "VARIANT_XML", from = "MDB_MedicHipPouchFront_M.X", to = "MDB_MedicHipPouch_M.X" },
        { name = "變體 GUID 沒登記", file = "GUIDTABLE", from = "MDB_ToolBeltPouchBack_Olive.xml</path>", to = "MDB_ToolBeltPouchBack_OliveX.xml</path>" },
        { name = "升級清單漏變體", file = "RECIPES", from = "MinidoracatBags.MedicHipPouchFront_Olive;", to = "" },
        { name = "變體名稱和原款不同", file = "I18N_ITEMS", from = '"MinidoracatBags.ToolBeltPouchBack_Navy": "S.T.A.R.S. Tool Belt Pouch"', to = '"MinidoracatBags.ToolBeltPouchBack_Navy": "S.T.A.R.S. Tool Belt Pouch (Back)"' },
        { name = "變體放進警局戰利品", file = "LOOT", from = '"CourierSatchel", 0.1, "ToolBeltPouch", 0.2 } },', to = '"CourierSatchel", 0.1, "ToolBeltPouch", 0.2, "ToolBeltPouchBack", 0.1 } },' },
    }
    rawPrint("== 突變（每個都應至少讓一項 FAIL）")
    local survived = 0
    for _, m in ipairs(mutants) do
        local keepPass, keepFail = pass, fail
        MUTATION, quiet = m, true
        pass, fail = 0, 0
        local ok, err = pcall(suite)
        -- 突變片段不在原始碼裡時 readFile 會丟錯，那不算抓到
        local killed = (not ok and not tostring(err):find("突變片段不在原始碼中", 1, true)) or (ok and fail > 0)
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
