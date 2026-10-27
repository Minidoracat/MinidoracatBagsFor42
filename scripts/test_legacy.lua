-- 離線測試：舊 Bag Upgrade Plus 外殼、放入鎖、改裝成強化版、強化版布吊帶包直接製作、重複定義警告、翻譯鍵。
--   lua scripts/test_legacy.lua             腳本不變式與 Lua 行為
--   lua scripts/test_legacy.lua --mutants   另對腳本與 Lua 植入違規，確認測試抓得到
-- 直接解析真的 MDB_Legacy.txt／MDB_Convert.txt、原版 media/scripts，並以假的 PZ 全域載入真的 MOD Lua。
-- 引擎對照：AcceptItemFunction 找不到函式時照收（ItemContainer.java:296-304），所以要斷言函式解析得到；
-- ClothingItem 名稱→物品的對照後放覆蓋先放（ScriptManager.java:1883-1891），所以不能和原版重名。

local MEDIA = "MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42/42/media/"
local PZ = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media/"
local MOD_ID = "MinidoracatBagsFor42"
local TRANSLATE = MEDIA .. "lua/shared/Translate/"
-- conventions.md「介面語系」：12 種語言＋ES 的 AR／ES_CL／ES_MX、PTBR 的 PT
local LANGS = { "AR", "CH", "CN", "DE", "EN", "ES", "ES_CL", "ES_MX", "FR", "JP", "KO", "PL", "PT", "PTBR", "RU", "TR" }

local rawPrint = print
local pass, fail, quiet = 0, 0, false
local MUTATION, mutantHit = nil, false
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1 end
    if not quiet then rawPrint((cond and "  PASS  " or "  FAIL  ") .. name) end
end

-- 讀檔；突變模式下對指定檔案植入一次替換
local function source(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a"):gsub("^\239\187\191", ""):gsub("\r\n", "\n")
    f:close()
    if MUTATION and path:sub(-#MUTATION.file) == MUTATION.file then
        local i, j = s:find(MUTATION.from, 1, true)
        if i then
            s = s:sub(1, i - 1) .. MUTATION.to .. s:sub(j + 1)
            mutantHit = true
        end
    end
    return s
end

-- ===== 腳本解析：module／item／craftRecipe，欄位只取該區塊第一層 =====
local function parseScript(text, items, recipes)
    text = text:gsub("/%*.-%*/", "")
    local stack, pending, module = {}, nil, nil
    for raw in text:gmatch("[^\n]+") do
        local line = raw:match("^%s*(.-)%s*$")
        local top = stack[#stack]
        local opener = line:match("^(.-)%s*{$")
        if opener then
            if opener ~= "" then pending = opener end
            local kind, name = (pending or ""):match("^(%S+)%s*(.*)$")
            local frame = { kind = kind }
            if kind == "module" then
                module = name
            elseif kind == "item" and top and top.kind == "module" then
                frame.obj = { module = module, name = name, fields = {}, components = {} }
                items[module .. "." .. name] = frame.obj
            elseif kind == "craftRecipe" then
                frame.obj = { name = name, fields = {}, inputs = {}, outputs = {} }
                recipes[name] = frame.obj
            elseif kind == "component" and top and top.obj then
                top.obj.components[name] = true
            elseif (kind == "inputs" or kind == "outputs") and top and top.obj then
                frame.list = top.obj[kind]
            end
            stack[#stack + 1] = frame
            pending = nil
        elseif line == "}" then
            stack[#stack] = nil
        elseif line ~= "" then
            if top and top.list then
                top.list[#top.list + 1] = line
            else
                local k, v = line:match("^([%w_]+)%s*=%s*(.-)%s*,?$")
                if k then
                    if top and top.obj then top.obj.fields[k] = v end
                else
                    pending = line
                end
            end
        end
    end
end

local WINDOWS = package.config:sub(1, 1) == "\\"
local function listDir(dir)
    local out = {}
    local p = io.popen(WINDOWS and ('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul') or ('ls "' .. dir .. '" 2>/dev/null'))
    for name in p:read("a"):gmatch("[^\r\n]+") do out[#out + 1] = name end
    p:close()
    return out
end

local vanillaItems = {}
for _, f in ipairs(listDir(PZ .. "scripts/generated/items")) do
    if f:match("%.txt$") then parseScript(source(PZ .. "scripts/generated/items/" .. f), vanillaItems, {}) end
end
local vanillaGuids = {}
for g in source(PZ .. "fileGuidTable.xml"):gmatch("<guid>%s*([%w%-]+)%s*</guid>") do vanillaGuids[g:lower()] = true end

-- 舊全名 → 原版同款、改裝組（LegacyMap 表；Base／ExtraCraft 吊帶包同款 Bag_SheetSlingBag）
local SHELLS = {
    { "BagUpgradePlus.ALICEpackPlus", "Bag_ALICEpack", "back" },
    { "BagUpgradePlus.ALICEpack_CamoPlus", "Bag_ALICEpack_Army", "back" },
    { "BagUpgradePlus.ALICEpack_DesertCamoPlus", "Bag_ALICEpack_DesertCamo", "back" },
    { "BagUpgradePlus.DuffelPlus", "Bag_DuffelBag", "back" },
    { "BagUpgradePlus.MedicalPlus", "Bag_MedicalBag", "back" },
    { "BagUpgradePlus.MilitaryPlus", "Bag_Military", "back" },
    { "BagUpgradePlus.PolicePlus", "Bag_Police", "back" },
    { "BagUpgradePlus.SheriffPlus", "Bag_Sheriff", "back" },
    { "BagUpgradePlus.SWATPlus", "Bag_SWAT", "back" },
    { "BagUpgradePlus.BreakdownBagPlus", "Bag_BreakdownBag", "back" },
    { "BagUpgradePlus.BurglarBagPlus", "Bag_BurglarBag", "back" },
    { "BagUpgradePlus.BaseballBagPlus", "Bag_BaseballBag", "back" },
    { "BagUpgradePlus.TennisBagPlus", "Bag_TennisBag", "back" },
    { "BagUpgradePlus.WeaponBagPlus", "Bag_WeaponBag", "back" },
    { "BagUpgradePlus.InmateEscapedBagPlus", "Bag_InmateEscapedBag", "back" },
    { "BagUpgradePlus.MoneyBagPlus", "Bag_MoneyBag", "back" },
    { "BagUpgradePlus.WorkerBagPlus", "Bag_WorkerBag", "back" },
    { "BagUpgradePlus.ShotgunBagPlus", "Bag_ShotgunBag", "back" },
    { "BagUpgradePlus.ShotgunSawnoffBagPlus", "Bag_ShotgunSawnoffBag", "back" },
    { "BagUpgradePlus.ShotgunDblBagPlus", "Bag_ShotgunDblBag", "back" },
    { "BagUpgradePlus.ShotgunDblSawnoffBagPlus", "Bag_ShotgunDblSawnoffBag", "back" },
    { "BagUpgradePlus.FoodCannedPlus", "Bag_FoodCanned", "back" },
    { "BagUpgradePlus.FoodSnacksPlus", "Bag_FoodSnacks", "back" },
    { "BagUpgradePlus.ToolBagPlus", "Bag_ToolBag", "back" },
    { "BagUpgradePlus.FannyPackFrontPlus", "Bag_FannyPackFront", "fanny" },
    { "BagUpgradePlus.FannyPackBackPlus", "Bag_FannyPackBack", "fanny" },
    { "BagUpgradePlus.HydrationBackpackPlus", "Bag_HydrationBackpack", "back" },
    { "BagUpgradePlus.HydrationBackpackPlus_Camo", "Bag_HydrationBackpack_Camo", "back" },
    { "BagUpgradePlus.HikingBagPlus", "Bag_NormalHikingBag", "back" },
    { "BagUpgradePlus.BigHikingBagplus", "Bag_BigHikingBag", "back" },
    { "BagUpgradePlus.BigHikingBagPlus_Travel", "Bag_HikingBag_Travel", "back" },
    { "BagUpgradePlus.SchoolbagPlus", "Bag_Schoolbag", "back" },
    { "BagUpgradePlus.SatchelPlus", "Bag_Satchel", "satchel" },
    { "BagUpgradePlus.Satchel_FishingPlus", "Bag_Satchel_Fishing", "satchel" },
    { "BagUpgradePlus.Satchel_MedicalPlus", "Bag_Satchel_Medical", "satchel" },
    { "BagUpgradePlus.Satchel_MilitaryPlus", "Bag_Satchel_Military", "satchel" },
    { "Base.SheetSlingBagPlus", "Bag_SheetSlingBag", "back" },
    { "ExtraCraft.SheetSlingBagPlus", "Bag_SheetSlingBag", "back" },
    { "Base.WaterBottleFull", "WaterBottle", "bottle" },
    { "Base.WaterPopBottle", "WaterBottle", "bottle" },
}
local COPIED = { "DisplayCategory", "ItemType", "Weight", "RunSpeedModifier", "Capacity", "WeightReduction",
    "CanBeEquipped", "Icon", "IconsForTexture", "WorldStaticModel", "AttachmentsProvided", "SoundParameter", "Tags" }

local function resolve(path)
    local v = _G
    for part in path:gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

local function javaList(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

local printed
local bootHandlers
local env
local function bootLua()
    MDB, SandboxVars, printed, bootHandlers = nil, nil, {}, {}
    env = { server = false, sent = {}, replaced = {}, added = {} }
    Events = { OnGameBoot = { Add = function(fn) bootHandlers[#bootHandlers + 1] = fn end } }
    -- MDB_Upgrade 會 require 並包住原版的換穿法。照原版搬顏色（textureChoice、染色）、內容物、液體（依新容量截斷）、
    -- modData（ISClothingExtraAction.lua:66-112）
    ISClothingExtraAction = {}
    function ISClothingExtraAction:createItemNew(item, newItem)
        newItem.visual.choice, newItem.visual.tint = item.visual.choice, item.visual.tint
        for _, c in ipairs(item.contents) do newItem.contents[#newItem.contents + 1] = c end
        item.contents = {}
        if item.fc and newItem.fc then newItem.fc.amount = math.min(item.fc.amount, newItem.fc.capacity) end
        if next(item.md) then
            newItem.md = {}
            for k, v in pairs(item.md) do newItem.md[k] = v end
        end
        return newItem
    end
    package.loaded["TimedActions/ISClothingExtraAction"] = true
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        printed[#printed + 1] = table.concat(parts, "\t")
    end
    for _, f in ipairs({ "MDB_Guard.lua", "MDB_Legacy.lua", "MDB_Upgrade.lua" }) do
        local code = source(MEDIA .. "lua/shared/" .. f)
        assert(code, "missing " .. f)
        assert(load(code, "@" .. f))()
    end
end

-- ===== 假背包（只模擬 swapBag／applyTier 用到的方法）=====
function isServer() return env.server end
function sendReplaceItemInContainer(c, a, b) env.sent[#env.sent + 1] = { c, a, b } end
-- 只在伺服器有作用（LuaManager.java:12370-12374）
function sendAddItemToContainer(c, i) if env.server then env.added[#env.added + 1] = { c, i } end end
function replaceItemInContainer(c, a, b) env.replaced[#env.replaced + 1] = { c, a, b } end
function copyClothingItem(item, newItem) ISClothingExtraAction:createItemNew(item, newItem) end
function instanceof(o, cls) return type(o) == "table" and rawget(o, "__class") == cls end
local INV = { items = {} }
function INV:AddItem(i) self.items[#self.items + 1] = i; i.container = self; return i end
function INV:Remove(i) for k, v in ipairs(self.items) do if v == i then table.remove(self.items, k); i.container = nil end end end
local PLAYER = { getInventory = function() return INV end }
local function newFluid(capacity, amount)
    local fc = { capacity = capacity, amount = amount or 0 }
    function fc:getCapacity() return self.capacity end
    function fc:getAmount() return self.amount end
    function fc:setCapacity(c)
        local old = self.capacity
        self.capacity = math.max(c, 0.05)
        if self.amount > self.capacity then self.amount = self.capacity * self.amount / old end   -- FluidContainer.java:683-696
    end
    function fc:copyFluidsFrom(o) self.amount = math.min(o.amount, self.capacity) end
    return fc
end
local function newBag(fullType, cap, wr, weight, fluid)
    local b = { __class = "InventoryContainer", fullType = fullType, cap = cap, wr = wr, md = {}, contents = {},
        fc = fluid and newFluid(fluid), visual = { choice = -1 } }
    local script = { getActualWeight = function() return weight end, getDisplayName = function() return "name of " .. fullType end }
    b.name = script.getDisplayName()
    function b.visual:getTextureChoice() return self.choice end
    function b.visual:setTextureChoice(c) self.choice = c end
    function b.visual:getTint() return self.tint end
    function b.visual:setTint(t) self.tint = t end
    function b:getFullType() return self.fullType end
    function b:getDisplayName() return self.name end
    function b:setName(n) self.name = n end
    function b:isCustomName() return self.custom == true end
    function b:setCustomName(c) self.custom = c end
    function b:getModData() return self.md end
    function b:hasModData() return next(self.md) ~= nil end
    function b:getCapacity() return math.min(self.cap, math.floor(50 - weight)) end
    function b:setCapacity(c) self.cap = c end
    function b:getWeightReduction() return self.wr end
    function b:setWeightReduction(w) self.wr = w end
    function b:getScriptItem() return script end
    function b:getContainer() return self.container end
    function b:getFluidContainer() return self.fc end
    function b:getVisual() return self.visual end
    function b:synchWithVisual() end
    return b
end
-- 強化版：照 MDB_Reinforced.txt 的容量、負重減輕、液體容量，自重 0.1（欄位由 test_newbags.lua 逐一驗）；原版（還原用）照原版腳本
local VANILLA_FLUID = { ["Base.Bag_HydrationBackpack"] = 2.0, ["Base.Bag_HydrationBackpack_Camo"] = 3.0 }
local reinItems, reinFluid
function instanceItem(full)
    if not reinItems then
        reinItems, reinFluid = {}, {}
        local text = source(MEDIA .. "scripts/MDB_Reinforced.txt")
        parseScript(text, reinItems, {})
        for name, body in text:gmatch("item%s+([%w_]+)%s*(%b{})") do
            local fc = body:match("component FluidContainer%s*(%b{})")
            reinFluid["MinidoracatBags." .. name] = fc and tonumber(fc:match("Capacity = ([%d.]+)"))
        end
    end
    local r, v = reinItems[full], vanillaItems[full]
    assert(r or v, "instanceItem: unknown bag " .. tostring(full))
    local f = (r or v).fields
    return newBag(full, tonumber(f.Capacity), tonumber(f.WeightReduction), r and 0.1 or tonumber(f.Weight or "1.0"),
        r and reinFluid[full] or VANILLA_FLUID[full])
end

local function suite()
    local items, recipes = {}, {}
    parseScript(source(MEDIA .. "scripts/MDB_Legacy.txt"), items, recipes)
    parseScript(source(MEDIA .. "scripts/MDB_Convert.txt"), items, recipes)
    bootLua()
    print = rawPrint

    -- 1. 40 個全名都在，沒有多的
    local expected, count = {}, 0
    for _, s in ipairs(SHELLS) do expected[s[1]] = s end
    local missing, extra = {}, {}
    for _, s in ipairs(SHELLS) do if not items[s[1]] then missing[#missing + 1] = s[1] end end
    for ft in pairs(items) do
        count = count + 1
        if not expected[ft] then extra[#extra + 1] = ft end
    end
    check("40 個舊全名都有外殼（缺：" .. table.concat(missing, ",") .. "）", #missing == 0)
    check("沒有多餘物品（多：" .. table.concat(extra, ",") .. "）", #extra == 0 and count == 40)

    -- 2. 不定義、不覆寫原版物品
    local clash = {}
    for ft in pairs(items) do if vanillaItems[ft] then clash[#clash + 1] = ft end end
    check("沒有和原版同名的物品（" .. table.concat(clash, ",") .. "）", #clash == 0)

    -- 2b. 舊模組不 import：BUP 配方檔寫 module Base { imports { BagUpgradePlus } }，這邊再 import Base 就成環，
    --     Base 查不到的名稱在兩個模組間無限遞迴（ScriptBucket.get 依 imports 往下查），伺服器開機 StackOverflowError（E2E bags-coexist-1025a）
    local legacyText = source(MEDIA .. "scripts/MDB_Legacy.txt"):gsub("/%*.-%*/", "")
    local importing = {}
    for name, body in legacyText:gmatch("module%s+(%S+)%s*(%b{})") do
        if name ~= "Base" and body:match("^{%s*imports%s*{") then importing[#importing + 1] = name end
    end
    check("舊模組不寫 imports（有：" .. table.concat(importing, ",") .. "）", #importing == 0)

    -- 3. 欄位：鎖、原版同款數值、禁用欄位
    local guardSet = {}
    for _, ft in ipairs(MDB.LEGACY_SHELLS or {}) do guardSet[ft] = true end
    for _, s in ipairs(SHELLS) do
        local ft, vname, group = s[1], s[2], s[3]
        local it = items[ft]
        local v = vanillaItems["Base." .. vname]
        if it and v then
            local f = it.fields
            if group == "bottle" then
                check(ft .. "：水瓶不鎖", f.AcceptItemFunction == nil)
                check(ft .. "：base:normal、AttachmentType WaterBottle、FluidContainer",
                    f.ItemType == "base:normal" and f.AttachmentType == "WaterBottle" and it.components.FluidContainer)
                check(ft .. "：Weight 等於原版 Base.WaterBottle", f.Weight == v.fields.Weight)
            else
                check(ft .. "：AcceptItemFunction = MDB.acceptLegacy", f.AcceptItemFunction == "MDB.acceptLegacy")
                check(ft .. "：Tooltip 說明只能取出", f.Tooltip == "Tooltip_MDB_LegacyBag")
                local diff = {}
                for _, k in ipairs(COPIED) do
                    if f[k] ~= v.fields[k] then diff[#diff + 1] = k .. "=" .. tostring(f[k]) .. "/" .. tostring(v.fields[k]) end
                end
                check(ft .. "：數值與外觀照原版 " .. vname .. "（" .. table.concat(diff, " ") .. "）", #diff == 0)
                check(ft .. "：FluidContainer 與原版一致", (it.components.FluidContainer or false) == (v.components.FluidContainer or false))
                check(ft .. "：沒有 BodyLocation／ClothingItemExtra",
                    f.BodyLocation == nil and f.ClothingItemExtra == nil and f.ClothingItemExtraOption == nil)
            end
            check(ft .. "：guard 清單有它", guardSet[ft] == true)
        end
    end
    check("guard 清單剛好 40 個", #(MDB.LEGACY_SHELLS or {}) == 40)

    -- 4. 函式名都解析得到（找不到時容器照收、配方不跑 OnCreate）
    local unresolved = {}
    for ft, it in pairs(items) do
        for _, k in ipairs({ "AcceptItemFunction", "OnCreate" }) do
            local fn = it.fields[k]
            if fn and fn:match("^MDB%.") and type(resolve(fn)) ~= "function" then unresolved[#unresolved + 1] = ft .. "." .. k end
        end
    end
    for name, r in pairs(recipes) do
        for _, k in ipairs({ "OnCreate", "OnTest" }) do
            local fn = r.fields[k]
            if fn and type(resolve(fn)) ~= "function" then unresolved[#unresolved + 1] = name .. "." .. k end
        end
    end
    check("AcceptItemFunction／OnCreate 都解析得到（" .. table.concat(unresolved, ",") .. "）", #unresolved == 0)

    -- 5. ClothingItem：不和原版重名、每個都有 XML（內容照原版同款）與 GUID
    local guidText = source(MEDIA .. "fileGuidTable.xml") or ""
    local guidOf = {}
    for path, g in guidText:gmatch("<path>([^<]+)</path>%s*<guid>([^<]+)</guid>") do guidOf[path] = g end
    local seenGuid, clothingSeen = {}, {}
    for _, s in ipairs(SHELLS) do
        local it = items[s[1]]
        local c = it and it.fields.ClothingItem
        if c and not clothingSeen[c] then
            clothingSeen[c] = true
            check(c .. "：原版沒有同名 ClothingItem", io.open(PZ .. "clothing/clothingItems/" .. c .. ".xml") == nil)
            local xml = source(MEDIA .. "clothing/clothingItems/" .. c .. ".xml")
            local vc = vanillaItems["Base." .. s[2]].fields.ClothingItem
            local vxml = source(PZ .. "clothing/clothingItems/" .. vc .. ".xml") or ""
            local g = xml and xml:match("<m_GUID>([^<]+)</m_GUID>")
            local strip = function(x) return (x:gsub("<m_GUID>[^<]+</m_GUID>", "")) end
            check(c .. "：XML 存在且照原版 " .. vc, xml ~= nil and strip(xml) == strip(vxml))
            check(c .. "：fileGuidTable 與 XML 一致、全新且不重複",
                g ~= nil and guidOf["media/clothing/clothingItems/" .. c .. ".xml"] == g
                and not vanillaGuids[g:lower()] and not seenGuid[g])
            if g then seenGuid[g] = true end
        end
    end

    -- 6. 改裝配方：一條涵蓋 38 個背包外殼各一次、不含水瓶；背包 keep（OnCreate 換型）、不能穿著、不必清空
    local r = recipes.MDB_ConvertLegacyBag
    check("MDB_ConvertLegacyBag：存在", r ~= nil)
    local covered, dup, wrong = {}, {}, {}
    local bagLine = r and r.inputs[1] or ""
    for ft in (bagLine:match("%[(.-)%]") or ""):gmatch("[^;]+") do
        if covered[ft] then dup[#dup + 1] = ft end
        covered[ft] = true
        if not items[ft] or (expected[ft] and expected[ft][3] == "bottle") then wrong[#wrong + 1] = ft end
    end
    local notCovered = {}
    for _, s in ipairs(SHELLS) do
        if s[3] ~= "bottle" and not covered[s[1]] then notCovered[#notCovered + 1] = s[1] end
    end
    check("改裝：38 個背包外殼都涵蓋（缺：" .. table.concat(notCovered, ",") .. "）", #notCovered == 0)
    check("改裝：沒有重複（" .. table.concat(dup, ",") .. "）", #dup == 0)
    check("改裝：沒有水瓶或不存在的物品（" .. table.concat(wrong, ",") .. "）", #wrong == 0)
    check("改裝：舊背包 mode:keep flags[IsNotWorn]（不必清空）", bagLine:match("%] mode:keep flags%[IsNotWorn%],?$") ~= nil)
    local needle, thread = false, false
    for i = 2, #(r and r.inputs or {}) do
        local l = r.inputs[i]
        needle = needle or (l:find("tags[base:sewingneedle]", 1, true) and l:find("mode:keep", 1, true)) ~= nil
        thread = thread or l:match("^item 2 tags%[base:thread%],?$") ~= nil
    end
    check("改裝：縫衣針 keep、線 2 用量", r ~= nil and needle and thread and #r.inputs == 3)
    check("改裝：沒有產出（OnCreate 換型）、OnCreate = MDB.onConvertLegacy、無技能門檻", r ~= nil and #r.outputs == 0
        and r.fields.OnCreate == "MDB.onConvertLegacy" and r.fields.SkillRequired == nil and r.fields.NeedToBeLearn == nil)
    -- 38 個舊外殼全部有對應：LEGACY_TARGET＝BUP 升級配方的對照表，對到的原版背包都有強化版；
    -- 外殼 XML 的顏色數和對到的原版相同（改裝照外殼的顏色查原版那張主題表）
    local mapWrong, mapCount = {}, 0
    for _ in pairs(MDB.LEGACY_TARGET or {}) do mapCount = mapCount + 1 end
    for _, s in ipairs(SHELLS) do
        local target = (MDB.LEGACY_TARGET or {})[s[1]]
        if s[3] ~= "bottle" then
            local xml = source(MEDIA .. "clothing/clothingItems/" .. tostring(items[s[1]] and items[s[1]].fields.ClothingItem) .. ".xml") or ""
            local n = 0
            for _ in xml:gmatch("<textureChoices>") do n = n + 1 end
            local ts = MDB.THEME_SOURCES[target or ""]
            if target ~= "Base." .. s[2] or not MDB.reinforcedOf(target) or not ts or #ts.themes ~= math.max(n, 1) then
                mapWrong[#mapWrong + 1] = s[1]
            end
        end
    end
    check("改裝對照：38 個外殼各對到原版同款、有強化版、顏色數和原版相同（錯：" .. table.concat(mapWrong, ",") .. "）",
        #mapWrong == 0 and mapCount == 38)
    -- 強化版布吊帶包直接製作：BUP 同材料（床單 1、鈔票 5），不需工具與技能
    local sl = recipes.MDB_MakeSheetSlingBag_Reinforced
    check("布吊帶包直接製作：床單 1＋鈔票 5、沒有工具、無技能門檻", sl ~= nil and #sl.inputs == 2
        and sl.inputs[1]:match("^item 1 %[Base%.Sheet%],?$") ~= nil and sl.inputs[2]:match("^item 5 %[Base%.Money%],?$") ~= nil
        and sl.fields.SkillRequired == nil and sl.fields.NeedToBeLearn == nil)
    check("布吊帶包直接製作：RemoveResultItems、outputs 只顯示強化版圖示、OnCreate = MDB.onMakeReinforcedSling", sl ~= nil
        and #sl.outputs == 1 and sl.outputs[1]:match("^item 1 (%S-),?$") == "MinidoracatBags.Bag_SheetSlingBag_Olive_Reinforced"
        and (";" .. (sl.fields.Tags or "") .. ";"):find(";RemoveResultItems;", 1, true) ~= nil
        and sl.fields.OnCreate == "MDB.onMakeReinforcedSling")
    local convertCount = 0
    for _ in pairs(recipes) do convertCount = convertCount + 1 end
    check("MDB_Convert.txt 剛好 2 條配方", convertCount == 2)

    -- 7. acceptLegacy：鎖開、鎖關、沙盒缺席
    SandboxVars = { MinidoracatBags = { LockLegacyBags = true } }
    check("鎖住：不收", MDB.acceptLegacy({}, {}) == false)
    SandboxVars = { MinidoracatBags = { LockLegacyBags = false } }
    check("鎖關：照收", MDB.acceptLegacy({}, {}) == true)
    SandboxVars = {}
    check("沙盒沒有本 MOD 的表：當成鎖住", MDB.acceptLegacy({}, {}) == false)
    SandboxVars = nil
    check("SandboxVars 缺席：當成鎖住", MDB.acceptLegacy({}, {}) == false)

    -- 8. onConvertLegacy：38 個外殼的每種顏色都換成對應原版那個顏色的主題強化版、給 MaxTier，原款記成對應的原版（假的 swapBag）。
    --    主題照清單檔（scripts/theme_shapes.json 的 theme_by_source）
    local themeTable = {}
    for src, list in source("scripts/theme_shapes.json"):match('"theme_by_source"%s*:%s*(%b{})'):gmatch('"(Base%.[%w_]+)"%s*:%s*(%b[])') do
        themeTable[src] = {}
        for t in list:gmatch('"(%a+)"') do themeTable[src][#themeTable[src] + 1] = t end
    end
    local swaps = {}
    local realSwap = MDB.swapBag
    MDB.swapBag = function(bag, newType, tier, chr) swaps[#swaps + 1] = { bag = bag, type = newType, tier = tier, chr = chr } end
    local tool = { __class = "HandWeapon" }
    local function keepData(bag) return { getAllKeepInputItems = function() return javaList({ tool, bag }) end } end
    local allOk, nColors = true, 0
    SandboxVars = { MinidoracatBags = { MaxTier = 2 } }
    for _, s in ipairs(SHELLS) do
        local target = "Base." .. s[2]
        for i, theme in ipairs(s[3] ~= "bottle" and themeTable[target] or {}) do
            nColors = nColors + 1
            swaps = {}
            local shell = newBag(s[1], 49, 100, 0.1)
            shell.visual.choice = i - 1
            MDB.onConvertLegacy(keepData(shell), PLAYER)
            local w = swaps[1]
            local shape = (MDB.THEME_SOURCES[target] or {}).shape
            if not (#swaps == 1 and w.bag == shell and w.type == "MinidoracatBags." .. tostring(shape) .. "_" .. theme .. "_Reinforced"
                and w.tier == 2 and w.chr == PLAYER and shell.md.MDB_origin == target and shell.md.MDB_originTex == i - 1) then
                allOk = false
                if not quiet then rawPrint("    convert wrong: " .. s[1] .. " color " .. i .. " -> " .. tostring(w and w.type)) end
            end
        end
    end
    check("onConvertLegacy：38 個外殼的每種顏色（" .. nColors .. "）都換成對應原版那個顏色的主題強化版、MaxTier=2、記下對應的原版與顏色",
        allOk and nColors > 38)
    swaps, SandboxVars = {}, nil
    MDB.onConvertLegacy(keepData(newBag("BagUpgradePlus.SatchelPlus", 49, 100, 0.1)), PLAYER)
    check("onConvertLegacy：沙盒缺席時用預設 3", #swaps == 1 and swaps[1].tier == 3)
    MDB.swapBag = realSwap

    -- 8b. 真的換型：舊水袋 5 升水、內容物、modData 都在；伺服器只送一次 replace
    local function convertWater(maxTier)
        INV.items, env.sent = {}, {}
        SandboxVars = { MinidoracatBags = { MaxTier = maxTier } }
        local shell = INV:AddItem(newBag("BagUpgradePlus.HydrationBackpackPlus", 49, 100, 1.0, 5.0))
        shell.fc.amount, shell.contents, shell.md = 5.0, { "bandage" }, { note = "kept" }
        shell.name, shell.custom = "My Plus", true
        MDB.onConvertLegacy(keepData(shell), PLAYER)
        return INV.items[1], shell
    end
    env.server = true
    local new, shell = convertWater(3)
    check("改裝水袋（伺服器）：強化版第 3 階 49／100、液體 5.0 升、5 升水全在",
        #INV.items == 1 and new.fullType == "MinidoracatBags.Bag_HydrationBackpack_Navy_Reinforced" and new.md.MDB_tier == 3
        and new.cap == 49 and new.wr == 100 and math.abs(new.fc.capacity - 5.0) < 1e-6 and math.abs(new.fc.amount - 5.0) < 1e-6)
    check("改裝水袋：內容物、modData、玩家改的名稱搬過去，舊背包移除、只送一次 replace",
        new.contents[1] == "bandage" and new.md.note == "kept" and new.name == "My Plus" and new.custom == true
        and shell.container == nil
        and #env.sent == 1 and env.sent[1][1] == INV and env.sent[1][2] == shell and env.sent[1][3] == new)
    env.server = false
    new = convertWater(0)
    check("改裝（MaxTier 0）：強化版第 0 階＝水袋組的起始值 12／85；照公式 3.0 升裝不下舊水袋的 5 升，容量留 5 升、水不少",
        new.md.MDB_tier == 0 and new.cap == 12 and new.wr == 85
        and math.abs(new.fc.capacity - 5.0) < 1e-6 and math.abs(new.fc.amount - 5.0) < 1e-6 and #env.replaced == 1)
    -- 改裝後還原：換回對應的原版（不是代表款以外的別款、也不是外殼）
    MDB.onSwapKeepTier(keepData(new), PLAYER)
    check("改裝後還原：換回對應的原版水袋、階級照舊", INV.items[1].fullType == "Base.Bag_HydrationBackpack" and INV.items[1].md.MDB_tier == 0)
    INV.items = {}

    -- 8c. 強化版布吊帶包直接製作：自己建、給 MaxTier、放進主物品欄；伺服器只整件送一次（加入），不另送 replace
    local function craftSling(maxTier)
        INV.items, env.sent, env.added = {}, {}, {}
        SandboxVars = { MinidoracatBags = { MaxTier = maxTier } }
        MDB.onMakeReinforcedSling({}, PLAYER)
        return INV.items[1]
    end
    env.server = true
    local sling = craftSling(3)
    check("布吊帶包直接製作（伺服器）：主物品欄裡一個第 3 階 49／100 的強化版",
        #INV.items == 1 and sling.fullType == "MinidoracatBags.Bag_SheetSlingBag_Olive_Reinforced"
        and sling.md.MDB_tier == 3 and sling.cap == 49 and sling.wr == 100)
    check("布吊帶包直接製作（伺服器）：只送一次加入（主物品欄、這個背包），沒有 replace",
        #env.added == 1 and env.added[1][1] == INV and env.added[1][2] == sling and #env.sent == 0)
    env.server = false
    sling = craftSling(0)
    check("布吊帶包直接製作（MaxTier 0，單機）：第 0 階＝布吊帶包組的起始值 14／60（獸皮吊帶包最高），不送封包",
        #INV.items == 1 and sling.md.MDB_tier == 0 and sling.cap == 14 and sling.wr == 60 and #env.added == 0)
    INV.items = {}

    -- 9. guard：定義被蓋掉、合併、BUP 啟用時印警告；乾淨時不印
    check("guard 掛在 OnGameBoot", #bootHandlers == 1 and bootHandlers[1] == MDB.warnDuplicates)
    local function runGuard(activeMods, tweak)
        local scripts = {}
        for _, ft in ipairs(MDB.LEGACY_SHELLS or {}) do
            local s = { modID = MOD_ID }
            if tweak and tweak[ft] then for k, v in pairs(tweak[ft]) do s[k] = v end end
            scripts[ft] = {
                getModID = function() return s.modID end,
                getBodyLocation = function() return s.bodyLocation end,
                getClothingItemExtra = function() return s.extra end,
            }
        end
        getScriptManager = function() return { getItem = function(_, ft) return scripts[ft] end } end
        getActivatedMods = function()
            return { contains = function(_, id) for _, m in ipairs(activeMods) do if m == id then return true end end return false end }
        end
        printed = {}
        print = function(...) printed[#printed + 1] = table.concat({ ... }, "\t") end
        for _, fn in ipairs(bootHandlers) do fn() end
        print = rawPrint
        return printed
    end
    local out = runGuard({ MOD_ID })
    check("guard：乾淨時不印", #out == 0)
    out = runGuard({ MOD_ID }, { ["BagUpgradePlus.ALICEpackPlus"] = { modID = "BagUpgradePlusUpdated" } })
    check("guard：被後載入的定義蓋掉 → 印一行", #out == 1 and out[1]:find("[MinidoracatBagsFor42] WARNING", 1, true) == 1
        and out[1]:find("BagUpgradePlus.ALICEpackPlus", 1, true) ~= nil)
    out = runGuard({ MOD_ID }, { ["BagUpgradePlus.SatchelPlus"] = { bodyLocation = "base:satchel" } })
    check("guard：先載入的定義合併進 BodyLocation → 印", #out == 1 and out[1]:find("SatchelPlus", 1, true) ~= nil)
    out = runGuard({ MOD_ID }, { ["BagUpgradePlus.FannyPackFrontPlus"] = { extra = javaList({ "Base.FannyPackBackPlus" }) } })
    check("guard：合併進 ClothingItemExtra → 印", #out == 1 and out[1]:find("FannyPackFrontPlus", 1, true) ~= nil)
    for _, id in ipairs({ "BagUpgradePlusUpdated", "\\BagUpgradePlusRealistic", "BagUpgradePlus", "BagUpgradePlusEFTCompat", "CloudBag" }) do
        out = runGuard({ MOD_ID, id })
        check("guard：" .. id .. " 啟用 → 印", #out == 1 and out[1]:find((id:gsub("^\\", "")), 1, true) ~= nil)
    end

    -- 10. 翻譯：40 個外殼名稱、說明、2 條配方在 16 個語言的正式檔都有鍵（引擎依檔名分表，Translator.java:137-146）
    local want = { ItemName = {}, Tooltip = { "Tooltip_MDB_LegacyBag" },
        Recipes = { "MDB_ConvertLegacyBag", "MDB_MakeSheetSlingBag_Reinforced" } }
    for _, s in ipairs(SHELLS) do want.ItemName[#want.ItemName + 1] = s[1] end
    local missingKeys = {}
    for _, lang in ipairs(LANGS) do
        for file, keys in pairs(want) do
            local have = {}
            for k in (source(TRANSLATE .. lang .. "/" .. file .. ".json") or ""):gmatch('\n%s*"([^"]+)"%s*:') do have[k] = true end
            for _, k in ipairs(keys) do
                if not have[k] then missingKeys[#missingKeys + 1] = lang .. "/" .. file .. ".json " .. k end
            end
        end
    end
    check("翻譯：外殼名稱、說明、2 條配方在 16 個語言都有鍵（缺：" .. table.concat(missingKeys, ",") .. "）", #missingKeys == 0)
end

rawPrint("== 舊 BUP 外殼與改裝")
suite()

if arg and arg[1] == "--mutants" then
    local L = "scripts/MDB_Legacy.txt"
    local C = "scripts/MDB_Convert.txt"
    local mutants = {
        { name = "外殼少一個", file = L, from = "    item MoneyBagPlus\n", to = "    item MoneyBagPlusX\n" },
        { name = "舊模組 import Base", file = L, from = "module BagUpgradePlus\n{\n", to = "module BagUpgradePlus\n{\n    imports\n    {\n        Base\n    }\n\n" },
        { name = "拿掉一個背包的鎖", file = L, from = "        AcceptItemFunction = MDB.acceptLegacy,\n", to = "" },
        { name = "鎖函式名打錯", file = L, from = "AcceptItemFunction = MDB.acceptLegacy", to = "AcceptItemFunction = MDB.acceptLegacyX" },
        { name = "Weight 改回 BUP 的 0.1", file = L, from = "Weight = 2.0,", to = "Weight = 0.1," },
        { name = "RunSpeedModifier 改回 1.0", file = L, from = "RunSpeedModifier = 0.94,", to = "RunSpeedModifier = 1.0," },
        { name = "加 BodyLocation", file = L, from = "CanBeEquipped = base:satchel,", to = "CanBeEquipped = base:satchel,\n        BodyLocation = base:satchel," },
        { name = "加 ClothingItemExtra", file = L, from = "CanBeEquipped = base:fannypackfront,", to = "CanBeEquipped = base:fannypackfront,\n        ClothingItemExtra = BagUpgradePlus.FannyPackBackPlus," },
        { name = "沿用原版 ClothingItem", file = L, from = "ClothingItem = Bag_SheetSlingBagPlus,", to = "ClothingItem = Bag_SheetSlingBag," },
        { name = "水瓶拿掉 AttachmentType", file = L, from = "        AttachmentType = WaterBottle,\n", to = "" },
        { name = "覆寫原版物品", file = L, from = "item WaterPopBottle\n", to = "item WaterBottle\n" },
        { name = "XML 少一份", file = "Bag_DuffelPlus.xml", from = "<clothingItem>", to = "<clothingItemX>" },
        { name = "fileGuidTable 對不上", file = "fileGuidTable.xml", from = "<guid>", to = "<guid>0" },
        { name = "改裝漏一個背包", file = C, from = "BagUpgradePlus.DuffelPlus;", to = "" },
        { name = "改裝放進水瓶", file = C, from = "[BagUpgradePlus.ALICEpackPlus;", to = "[Base.WaterBottleFull;BagUpgradePlus.ALICEpackPlus;" },
        { name = "改裝重複一個背包", file = C, from = "[BagUpgradePlus.ALICEpackPlus;", to = "[BagUpgradePlus.ALICEpackPlus;BagUpgradePlus.ALICEpackPlus;" },
        { name = "改裝可用穿著中的背包", file = C, from = "] mode:keep flags[IsNotWorn],", to = "] mode:keep," },
        { name = "改裝消耗舊背包", file = C, from = "] mode:keep flags[IsNotWorn],", to = "] flags[IsNotWorn]," },
        { name = "改裝又要清空", file = C, from = "] mode:keep flags[IsNotWorn],", to = "] mode:keep flags[IsEmpty;IsNotWorn]," },
        { name = "線改成整捲銷毀", file = C, from = "item 2 tags[base:thread],", to = "item 2 tags[base:thread] mode:destroy," },
        { name = "改裝多一個產出", file = C, from = "OnCreate = MDB.onConvertLegacy,", to = "OnCreate = MDB.onConvertLegacy,\n        outputs\n        {\n            item 1 Base.Bag_ALICEpack,\n        }" },
        { name = "OnCreate 名稱打錯", file = C, from = "OnCreate = MDB.onConvertLegacy,", to = "OnCreate = MDB.onConvrtLegacy," },
        { name = "布吊帶包產出原版", file = C, from = "item 1 MinidoracatBags.Bag_SheetSlingBag_Olive_Reinforced,", to = "item 1 Base.Bag_SheetSlingBag," },
        { name = "布吊帶包多要工具", file = C, from = "item 5 [Base.Money],", to = "item 5 [Base.Money],\n            item 1 tags[base:scissors] mode:keep," },
        { name = "布吊帶包鈔票數錯", file = C, from = "item 5 [Base.Money]", to = "item 4 [Base.Money]" },
        { name = "布吊帶包要技能", file = C, from = "OnCreate = MDB.onMakeReinforcedSling,", to = "OnCreate = MDB.onMakeReinforcedSling,\n        SkillRequired = Tailoring:1," },
        { name = "布吊帶包沒 RemoveResultItems", file = C, from = "CanBeDoneInDark;RemoveResultItems,", to = "CanBeDoneInDark," },
        { name = "鎖永遠放行", file = "MDB_Legacy.lua", from = 'return MDB.opt("LockLegacyBags") == false', to = "return true" },
        { name = "鎖永遠擋", file = "MDB_Legacy.lua", from = 'return MDB.opt("LockLegacyBags") == false', to = "return false" },
        { name = "改裝固定給 3 階", file = "MDB_Legacy.lua", from = 'MDB.LEGACY_TARGET[bag:getFullType()], MDB.opt("MaxTier")', to = "MDB.LEGACY_TARGET[bag:getFullType()], 3" },
        { name = "改裝不換型", file = "MDB_Legacy.lua", from = 'MDB.toReinforced(bag, MDB.LEGACY_TARGET[bag:getFullType()], MDB.opt("MaxTier"), character)', to = 'MDB.applyTier(bag, MDB.opt("MaxTier"))' },
        { name = "改裝換成外殼自己的強化版", file = "MDB_Legacy.lua", from = "MDB.toReinforced(bag, MDB.LEGACY_TARGET[bag:getFullType()],", to = "MDB.toReinforced(bag, bag:getFullType()," },
        { name = "改裝不照外殼顏色", file = "MDB_Upgrade.lua", from = "choice = v and v:getTextureChoice() or -1", to = "choice = -1" },
        { name = "改裝沒記原款", file = "MDB_Upgrade.lua", from = "md.MDB_origin, md.MDB_originTex = sourceType, choice", to = "md.MDB_originTex = choice" },
        { name = "對照表錯一款", file = "MDB_Legacy.lua", from = '["BagUpgradePlus.SWATPlus"] = "Base.Bag_SWAT"', to = '["BagUpgradePlus.SWATPlus"] = "Base.Bag_Police"' },
        { name = "對照表少一款", file = "MDB_Legacy.lua", from = '    ["BagUpgradePlus.MoneyBagPlus"] = "Base.Bag_MoneyBag",\n', to = "" },
        { name = "直接製作固定 3 階", file = "MDB_Legacy.lua", from = 'MDB.applyTier(bag, MDB.opt("MaxTier"))', to = "MDB.applyTier(bag, 3)" },
        { name = "直接製作沒放進主物品欄", file = "MDB_Legacy.lua", from = "    inv:AddItem(bag)\n", to = "" },
        { name = "直接製作伺服器沒送", file = "MDB_Legacy.lua", from = "    sendAddItemToContainer(inv, bag)\n", to = "" },
        { name = "直接製作先放進容器才套階級（多送 replace）", file = "MDB_Legacy.lua",
            from = '    MDB.applyTier(bag, MDB.opt("MaxTier"))\n    local inv = character:getInventory()\n    inv:AddItem(bag)\n',
            to = '    local inv = character:getInventory()\n    inv:AddItem(bag)\n    MDB.applyTier(bag, MDB.opt("MaxTier"))\n' },
        { name = "直接製作產出別款", file = "MDB_Legacy.lua", from = 'instanceItem(MDB.reinforcedOf("Base.Bag_SheetSlingBag"))', to = 'instanceItem(MDB.reinforcedOf("Base.Bag_ALICEpack"))' },
        { name = "換型液體沒重搬", file = "MDB_Upgrade.lua", from = "            nfc:copyFluidsFrom(ofc)\n", to = "" },
        { name = "換型不搬內容物", file = "MDB_Upgrade.lua", from = "        copyClothingItem(old, new)\n", to = "" },
        { name = "guard 不比 modID", file = "MDB_Guard.lua", from = "s:getModID() ~= MOD_ID", to = "false" },
        { name = "guard 不看合併欄位", file = "MDB_Guard.lua", from = "s:getBodyLocation() ~= nil or ", to = "" },
        { name = "guard 不看啟用的 BUP", file = "MDB_Guard.lua", from = 'mods:contains(id) or mods:contains("\\\\" .. id)', to = "false" },
        { name = "guard 清單少一個", file = "MDB_Guard.lua", from = '"Base.WaterPopBottle", ', to = "" },
        { name = "guard 沒掛事件", file = "MDB_Guard.lua", from = "Events.OnGameBoot.Add(MDB.warnDuplicates)", to = "" },
        { name = "翻譯缺外殼名稱", file = "/EN/ItemName.json", from = '"BagUpgradePlus.MoneyBagPlus"', to = '"BagUpgradePlus.MoneyBagPlusX"' },
    }
    rawPrint("== 突變（每個都應至少讓一項 FAIL）")
    local survived = 0
    for _, m in ipairs(mutants) do
        local keepPass, keepFail = pass, fail
        MUTATION, mutantHit, quiet = m, false, true
        pass, fail = 0, 0
        local ok, err = pcall(suite)
        print = rawPrint
        local killed = mutantHit and ((not ok) or fail > 0)
        rawPrint(string.format("  %s  %s（%s）", killed and "KILLED  " or "SURVIVED", m.name,
            not mutantHit and "替換字串沒命中" or ok and (fail .. " 項 FAIL") or ("錯誤：" .. tostring(err))))
        if not killed then survived = survived + 1 end
        pass, fail, MUTATION, quiet = keepPass, keepFail, nil, false
    end
    check("所有突變都被抓到", survived == 0)
end

rawPrint(string.format("結果：%d PASS，%d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
