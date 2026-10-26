-- 離線測試：舊 Bag Upgrade Plus 外殼、放入鎖、改裝配方、重複定義警告、翻譯鍵。
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
local GROUP_OF_EQUIP = { ["base:back"] = "Back", ["base:satchel"] = "Satchel",
    ["base:fannypackfront"] = "Fanny", ["base:fannypackback"] = "Fanny" }
local OUTPUT = { Back = "ExpeditionPack", Satchel = "CourierSatchel", Fanny = "ToolBeltPouch" }

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
local function bootLua()
    MDB, SandboxVars, printed, bootHandlers = nil, nil, {}, {}
    Events = { OnGameBoot = { Add = function(fn) bootHandlers[#bootHandlers + 1] = fn end } }
    -- MDB_Upgrade 會 require 並包住原版的換穿法；行為由 test_newbags.lua 測，這裡只讓它載得起來
    ISClothingExtraAction = { createItemNew = function(_, _, newItem) return newItem end }
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
                check(ft .. "：改裝組與 CanBeEquipped 一致", GROUP_OF_EQUIP[f.CanBeEquipped] == (group == "back" and "Back"
                    or group == "satchel" and "Satchel" or "Fanny"))
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

    -- 6. 改裝配方：每種外觀各自剛好涵蓋每個背包外殼一次，水瓶不在裡面
    for _, look in ipairs({ "Navy", "Olive" }) do
        local covered, dup, wrong = {}, {}, {}
        for g, out in pairs(OUTPUT) do
            local name = "MDB_ConvertLegacy" .. g .. "_" .. look
            local r = recipes[name]
            check(name .. "：存在", r ~= nil)
            if r then
                local bagLine = r.inputs[1] or ""
                for ft in (bagLine:match("%[(.-)%]") or ""):gmatch("[^;]+") do
                    if covered[ft] then dup[#dup + 1] = ft end
                    covered[ft] = true
                    local it = items[ft]
                    if not it or GROUP_OF_EQUIP[it.fields.CanBeEquipped] ~= g then wrong[#wrong + 1] = ft end
                end
                check(name .. "：舊背包 flags[IsEmpty;IsNotWorn]", bagLine:find("flags[IsEmpty;IsNotWorn]", 1, true) ~= nil)
                local needle, thread = false, false
                for i = 2, #r.inputs do
                    local l = r.inputs[i]
                    needle = needle or (l:find("tags[base:sewingneedle]", 1, true) and l:find("mode:keep", 1, true)) ~= nil
                    thread = thread or l:match("^item 2 tags%[base:thread%],?$") ~= nil
                end
                check(name .. "：縫衣針 keep、線 2 用量", needle and thread and #r.inputs == 3)
                check(name .. "：產出 MinidoracatBags." .. out .. "_" .. look,
                    #r.outputs == 1 and r.outputs[1]:match("^item 1 (%S-),?$") == "MinidoracatBags." .. out .. "_" .. look)
                check(name .. "：OnCreate = MDB.onConvert、無技能門檻", r.fields.OnCreate == "MDB.onConvert"
                    and r.fields.SkillRequired == nil and r.fields.NeedToBeLearn == nil)
            end
        end
        local notCovered = {}
        for _, s in ipairs(SHELLS) do
            if s[3] ~= "bottle" and not covered[s[1]] then notCovered[#notCovered + 1] = s[1] end
            if s[3] == "bottle" and covered[s[1]] then wrong[#wrong + 1] = s[1] end
        end
        check(look .. "：每個背包外殼都涵蓋（缺：" .. table.concat(notCovered, ",") .. "）", #notCovered == 0)
        check(look .. "：沒有重複（" .. table.concat(dup, ",") .. "）", #dup == 0)
        check(look .. "：沒有錯組或水瓶（" .. table.concat(wrong, ",") .. "）", #wrong == 0)
    end
    local convertCount = 0
    for _ in pairs(recipes) do convertCount = convertCount + 1 end
    check("改裝配方剛好 6 條", convertCount == 6)

    -- 7. acceptLegacy：鎖開、鎖關、沙盒缺席
    SandboxVars = { MinidoracatBags = { LockLegacyBags = true } }
    check("鎖住：不收", MDB.acceptLegacy({}, {}) == false)
    SandboxVars = { MinidoracatBags = { LockLegacyBags = false } }
    check("鎖關：照收", MDB.acceptLegacy({}, {}) == true)
    SandboxVars = {}
    check("沙盒沒有本 MOD 的表：當成鎖住", MDB.acceptLegacy({}, {}) == false)
    SandboxVars = nil
    check("SandboxVars 缺席：當成鎖住", MDB.acceptLegacy({}, {}) == false)

    -- 8. onConvert：以 MaxTier 呼叫 applyTier（假的 applyTier）
    local calls = {}
    MDB.applyTier = function(bag, tier) calls[#calls + 1] = { bag = bag, tier = tier } end
    local bagA, bagB = { id = "A" }, { id = "B" }
    local data = { getAllCreatedItems = function() return javaList({ bagA, bagB }) end }
    SandboxVars = { MinidoracatBags = { MaxTier = 2 } }
    MDB.onConvert(data, {})
    check("onConvert：第一個產出物、MaxTier=2", #calls == 1 and calls[1].bag == bagA and calls[1].tier == 2)
    calls = {}
    SandboxVars = nil
    MDB.onConvert(data, {})
    check("onConvert：沙盒缺席時用預設 3", #calls == 1 and calls[1].tier == 3)
    calls = {}
    MDB.onConvert({ getAllCreatedItems = function() return javaList({}) end }, {})
    check("onConvert：沒有產出物時不呼叫", #calls == 0)

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

    -- 10. 翻譯：40 個外殼名稱、說明、6 條改裝配方在 16 個語言的正式檔都有鍵（引擎依檔名分表，Translator.java:137-146）
    local want = { ItemName = {}, Tooltip = { "Tooltip_MDB_LegacyBag" }, Recipes = {} }
    for _, s in ipairs(SHELLS) do want.ItemName[#want.ItemName + 1] = s[1] end
    for g in pairs(OUTPUT) do
        for _, look in ipairs({ "Navy", "Olive" }) do want.Recipes[#want.Recipes + 1] = "MDB_ConvertLegacy" .. g .. "_" .. look end
    end
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
    check("翻譯：外殼名稱、說明、6 條改裝配方在 16 個語言都有鍵（缺：" .. table.concat(missingKeys, ",") .. "）", #missingKeys == 0)
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
        { name = "改裝放進水瓶", file = C, from = "[BagUpgradePlus.SatchelPlus;", to = "[Base.WaterBottleFull;BagUpgradePlus.SatchelPlus;" },
        { name = "改裝背包放錯組", file = C, from = "[BagUpgradePlus.SatchelPlus;", to = "[BagUpgradePlus.ALICEpackPlus;BagUpgradePlus.SatchelPlus;" },
        { name = "改裝拿掉 IsEmpty", file = C, from = "flags[IsEmpty;IsNotWorn]", to = "flags[IsNotWorn]" },
        { name = "線改成整捲銷毀", file = C, from = "item 2 tags[base:thread],", to = "item 2 tags[base:thread] mode:destroy," },
        { name = "產出外觀錯", file = C, from = "item 1 MinidoracatBags.ExpeditionPack_Navy,", to = "item 1 MinidoracatBags.ExpeditionPack_Olive," },
        { name = "OnCreate 名稱打錯", file = C, from = "OnCreate = MDB.onConvert,", to = "OnCreate = MDB.onConvrt," },
        { name = "鎖永遠放行", file = "MDB_Legacy.lua", from = 'return MDB.opt("LockLegacyBags") == false', to = "return true" },
        { name = "鎖永遠擋", file = "MDB_Legacy.lua", from = 'return MDB.opt("LockLegacyBags") == false', to = "return false" },
        { name = "改裝固定給 3 階", file = "MDB_Legacy.lua", from = 'MDB.opt("MaxTier")', to = "3" },
        { name = "改裝取最後一個產出物", file = "MDB_Legacy.lua", from = "created:get(0)", to = "created:get(created:size() - 1)" },
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
