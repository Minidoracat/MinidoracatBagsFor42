--[[
煙霧測試骨架：用假的 PZ 全域載入**真正的** MOD Lua，跑行為情境並斷言結果。

    lua scripts/smoke_harness.lua        （repo 根目錄執行；標準 Lua 5.x 即可）

為什麼需要（兩類 luac -p 抓不到的錯誤，皆為正式服實際事故）：
- 改函式簽章漏改呼叫點：語法完全合法，要等該路徑真的執行才炸
  （實例：hotspotKey 兩參數改三參數，刪除成功後的 log 聚合路徑必崩）
- 邏輯回歸：安全把關（範圍／阻隔／保護規則）被改壞時，「執行到並斷言」是唯一防線

限制（必須誠實面對）：這是標準 Lua，不是遊戲的 Kahlua。
- 標準 Lua 有 next/xpcall，Kahlua 沒有——本 harness **測不出**誤用，
  那由 scripts/verify_mod.py 的靜態掃描負責（發版前兩者都要跑）
- Kahlua 專屬行為（table.sort 遞迴深度、Java instance field 不暴露、rawget 呼叫形式、
  每個 table 都是 LinkedHashMap 的記憶體成本）只能靠反編譯查證與實機測試

寫情境的原則：
- 情境要「執行到會炸的路徑」——刪除後的收尾、跨 tick 的第二輪、聚合輸出，都是重災區
- 安全邊界要有**反面**斷言（範圍外／被阻隔／受保護的對象必須存活），不是只測 happy path
- 新防線寫完先「植入違規證明它會抓」再信任它——測不出來的測試等於沒有測試
]]

-- 家族佈局固定，直接填死最省事；scaffold 時由模板替換佔位符
local MEDIA = "MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42/42/media/lua"

-- ===== 假的 PZ 全域：只記錄掛了哪些事件 =====
-- MOD 的 Lua 在載入時只呼叫 Events.X.Add，另外 MDB_Upgrade 會 require 並包住原版的 ISClothingExtraAction.createItemNew，
-- MDB_FloorWear 會 require 原版 ISBaseTimedAction 並 derive 出計時動作，
-- MDB_Attach／MDB_AttachClient 在載入時就登記掛點（AttachedLocations、腳本 DoParam、模型掛點、快捷列定義），也包住 ISHotbar.doMenuFromInventory；
-- 其餘引擎全域都在函式被呼叫時才用，那些行為由 scripts/test_*.lua 用各自的假全域測。
local registered = {}
Events = setmetatable({}, {
    __index = function(_, name)
        return { Add = function(fn) registered[#registered + 1] = { name = name, fn = fn } end }
    end,
})
ISClothingExtraAction = { createItemNew = function(_, _, newItem) return newItem end }
package.loaded["TimedActions/ISClothingExtraAction"] = true
ISBaseTimedAction = { derive = function(self, type) return setmetatable({ Type = type }, { __index = self }) end }
package.loaded["TimedActions/ISBaseTimedAction"] = true
-- MDB_BodyLocations 在載入時把第二個側背包位置加進 Human 群組（行為由 test_newbags.lua 測），這裡只讓它載得起來
local SATCHEL2 = { id = "minidoracatbags:satchel2" }
ResourceLocation = { of = function(id) return id end }
ItemBodyLocation = { SATCHEL = { id = "base:satchel" }, get = function(id) return id == SATCHEL2.id and SATCHEL2 or nil end }
local humanGroup = {}
BodyLocations = { getGroup = function() return {
    getOrCreateLocation = function(_, loc) humanGroup[#humanGroup + 1] = loc end,
    indexOf = function() return -1 end,
    moveLocationToIndex = function() end,
} end }
ISWearClothing = { WalkBodyLocations = {} }
package.loaded["NPCs/BodyLocations"] = true
package.loaded["TimedActions/ISWearClothing"] = true
local locations, doParams, modelAttachments = {}, 0, 0
AttachedLocations = { getGroup = function()
    return { getOrCreateLocation = function(_, name)
        return { setAttachmentName = function(_, id) locations[name] = id end }
    end }
end }
local function vec() return { set = function() end } end
ModelAttachment = { new = function(id)
    modelAttachments = modelAttachments + 1
    local off, rot = vec(), vec()
    return { setBone = function() end, getOffset = function() return off end, getRotate = function() return rot end }
end }
function getScriptManager()
    return {
        getItem = function() return { DoParam = function() doParams = doParams + 1 end, getStaticModel = function() return nil end } end,
        getModelScript = function()
            return { getAttachmentById = function() return nil end, addAttachment = function() end }
        end,
    }
end
ISHotbarAttachDefinition = {}
ISHotbar = { doMenuFromInventory = function() end }
package.loaded["Hotbar/ISHotbarAttachDefinition"] = true
package.loaded["Hotbar/ISHotbar"] = true

-- ===== 測試工具 =====
local failures = 0
local function check(ok, label)
    if ok then print("  PASS  " .. label)
    else failures = failures + 1; print("  FAIL  " .. label) end
end

local WINDOWS = package.config:sub(1, 1) == "\\"
local function listLua(dir)
    local cmd = WINDOWS and ('dir /b /on "' .. dir:gsub("/", "\\") .. '\\*.lua" 2>nul')
        or ('ls "' .. dir .. '"/*.lua 2>/dev/null')
    local files, p = {}, io.popen(cmd)
    for line in p:lines() do
        local name = line:match("([^/\\]+%.lua)$")
        if name then files[#files + 1] = name end
    end
    p:close()
    table.sort(files)
    return files
end

-- ===== 情境一：整包載入，只掛允許的事件（效能不變式）=====
-- 設計定案：只在開機、開世界、製作、放東西、殭屍死亡時執行 Lua，不掛每幀或每次殭屍更新的事件；右鍵選單只在玩家按右鍵時跑。
print("情境一：整包載入")
local loadedCount = 0
for _, dir in ipairs({ "shared", "server", "client" }) do   -- 遊戲也是 shared 先載入
    for _, name in ipairs(listLua(MEDIA .. "/" .. dir)) do
        local chunk, err = loadfile(MEDIA .. "/" .. dir .. "/" .. name)
        check(chunk ~= nil, "解析 " .. dir .. "/" .. name .. (err and ("：" .. err) or ""))
        if chunk then chunk(); loadedCount = loadedCount + 1 end
    end
end
check(loadedCount >= 6, "載入 " .. loadedCount .. " 個 Lua 檔（列目錄失敗時會是 0）")

local ALLOWED = { "OnGameBoot", "OnPreDistributionMerge", "OnInitGlobalModData", "OnZombieDead", "OnFillInventoryObjectContextMenu" }
local allowed, seen = {}, {}
for _, name in ipairs(ALLOWED) do allowed[name] = true end
for _, r in ipairs(registered) do
    check(allowed[r.name] == true, "只掛允許的事件：" .. r.name)
    check(type(r.fn) == "function", r.name .. " 的 handler 是函式")
    seen[r.name] = (seen[r.name] or 0) + 1
end
for _, name in ipairs(ALLOWED) do check(seen[name] == 1, name .. " 剛好掛一次") end
for _, fn in ipairs({ "acceptLegacy", "acceptFirstAid", "acceptAmmo", "applyTier", "swapBag", "keepBag", "onConvertLegacy",
                      "onMakeReinforcedSling", "onSwapKeepTier", "onTestUpgraded", "onUpgrade", "onTestTier1", "onTestTier2", "onTestTier3",
                      "addLoot", "reapplyLoot", "onZombieDead", "warnDuplicates", "opt",
                      "canWearFromFloor", "needsFloorWear", "onFillFloorWearMenu", "addSatchel2Location",
                      "installAttach", "installAttachClient", "attachTransform", "eachAttachPose" }) do
    check(type(MDB[fn]) == "function", "MDB." .. fn .. " 存在")
end
check(type(MDB_WearFromFloor) == "table" and MDB_WearFromFloor.Type == "MDB_WearFromFloor", "計時動作 MDB_WearFromFloor 是同名全域")
check(humanGroup[1] == SATCHEL2 and ISWearClothing.WalkBodyLocations[1] == SATCHEL2,
    "載入時第二個側背包位置加進 Human 群組、可以邊走邊穿脫")
local nLoc, nFix = 0, 0
for _ in pairs(locations) do nLoc = nLoc + 1 end
for _, fix in pairs(MDB.ATTACH_FIX or {}) do   -- 模型自身校正：每個模型在它那種擺法的每個掛點各一個
    MDB.eachAttachPose(function(_, _, pose) if pose == fix[1] then nFix = nFix + 1 end end)
end
check(nLoc > 0 and #ISHotbarAttachDefinition > 0 and nFix > 0 and modelAttachments == 2 * nLoc + nFix and doParams > 0,
    string.format("載入時登記掛點：%d 個 AttachedLocation、%d 個快捷列定義、%d 個模型掛點（身體 %d＋自身校正 %d）、%d 次 DoParam",
        nLoc, #ISHotbarAttachDefinition, modelAttachments, 2 * nLoc, nFix, doParams))

-- ===== 情境二：各部分的離線測試，含植入違規 =====
print("情境二：離線測試")
for _, test in ipairs({ "test_legacy.lua", "test_newbags.lua", "test_floor_wear.lua", "test_attach.lua" }) do
    for _, mode in ipairs({ "", " --mutants" }) do
        local p = io.popen("lua scripts/" .. test .. mode .. " 2>&1")
        local last = ""
        for line in p:lines() do if line:match("%S") then last = line end end
        check(p:close() == true, test .. mode .. "：" .. last)
    end
end

print()
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過")
