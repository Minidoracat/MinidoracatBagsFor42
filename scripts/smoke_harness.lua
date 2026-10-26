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
-- MOD 的 Lua 在載入時只呼叫 Events.X.Add，另外 MDB_Upgrade 會 require 並包住原版的 ISClothingExtraAction.createItemNew；
-- 其餘引擎全域都在函式被呼叫時才用，那些行為由 scripts/test_legacy.lua、scripts/test_newbags.lua 用各自的假全域測。
local registered = {}
Events = setmetatable({}, {
    __index = function(_, name)
        return { Add = function(fn) registered[#registered + 1] = { name = name, fn = fn } end }
    end,
})
ISClothingExtraAction = { createItemNew = function(_, _, newItem) return newItem end }
package.loaded["TimedActions/ISClothingExtraAction"] = true

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
-- 設計定案：只在開機、開世界、製作、放東西、殭屍死亡時執行 Lua，不掛每幀或每次殭屍更新的事件。
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

local ALLOWED = { "OnGameBoot", "OnPreDistributionMerge", "OnInitGlobalModData", "OnZombieDead" }
local allowed, seen = {}, {}
for _, name in ipairs(ALLOWED) do allowed[name] = true end
for _, r in ipairs(registered) do
    check(allowed[r.name] == true, "只掛允許的事件：" .. r.name)
    check(type(r.fn) == "function", r.name .. " 的 handler 是函式")
    seen[r.name] = (seen[r.name] or 0) + 1
end
for _, name in ipairs(ALLOWED) do check(seen[name] == 1, name .. " 剛好掛一次") end
for _, fn in ipairs({ "acceptLegacy", "acceptFirstAid", "acceptAmmo", "applyTier", "onConvert", "onUpgrade",
                      "onTestTier1", "onTestTier2", "onTestTier3", "addLoot", "reapplyLoot", "onZombieDead", "warnDuplicates", "opt" }) do
    check(type(MDB[fn]) == "function", "MDB." .. fn .. " 存在")
end

-- ===== 情境二：各部分的離線測試，含植入違規 =====
print("情境二：離線測試")
for _, test in ipairs({ "test_legacy.lua", "test_newbags.lua" }) do
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
