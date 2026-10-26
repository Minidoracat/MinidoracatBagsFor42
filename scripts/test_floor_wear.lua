-- 離線測試：直接穿上地上裝滿的背包（shared/MDB_FloorWear.lua、client/MDB_FloorWearMenu.lua、ContextMenu 翻譯）。
--   lua scripts/test_floor_wear.lua             選單條件、伺服器驗證各分支、動作時間、聲音與進度、翻譯鍵
--   lua scripts/test_floor_wear.lua --mutants   另對 MOD 檔案植入錯誤，確認測試抓得到
-- 用假的 PZ 全域載入真正的 MOD Lua。引擎模擬：
-- - NetTimedAction 照 new 的參數名讀動作欄位送給伺服器，伺服器以全域名 Type 重建（NetTimedAction.java:37-55、:145-165）。
-- - getActualWeight() 在伺服器回 0（顯示名稱等於全名，InventoryItem.java:2740-2742），假物品的實例自重一律 0。
-- - ISTransferAction:transferItem 從地上移除 world item 並放進目的容器（ISTransferAction.lua:131-160）。
-- 執行目錄：repo 根。

local MEDIA = "MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42/42/media/lua/"
local TRANSLATE = MEDIA .. "shared/Translate/"
local F = {
    ACT = MEDIA .. "shared/MDB_FloorWear.lua",
    MENU = MEDIA .. "client/MDB_FloorWearMenu.lua",
    EN = TRANSLATE .. "EN/ContextMenu.json",
}
local LANGS = { "AR", "CH", "CN", "DE", "EN", "ES", "ES_CL", "ES_MX", "FR", "JP", "KO", "PL", "PT", "PTBR", "RU", "TR" }
local KEY = "ContextMenu_MDB_WearWithContents"

local MUTATION
local function readFile(path)
    local fh = assert(io.open(path, "rb"), "找不到檔案：" .. path)
    local text = fh:read("*a")
    fh:close()
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

-- ===== 假引擎 =====
local env
local function log(...) env.log[#env.log + 1] = { ... } end
local function calls(name)
    local out = {}
    for _, c in ipairs(env.log) do if c[1] == name then out[#out + 1] = c end end
    return out
end
local function javaList(arr)
    return {
        size = function() return #arr end,
        get = function(_, i) return arr[i + 1] end,
        contains = function(_, o) for _, v in ipairs(arr) do if v == o then return true end end return false end,
    }
end

local function resetEnv()
    env = { log = {}, walkOk = true }
    Events = setmetatable({}, { __index = function(t, k)
        local e = { handlers = {} }
        function e.Add(f) e.handlers[#e.handlers + 1] = f end
        rawset(t, k, e)
        return e
    end })
    MDB, MDB_WearFromFloor = nil, nil
    ISBaseTimedAction = {}
    function ISBaseTimedAction:derive(type)
        local o = setmetatable({}, { __index = self })
        o.Type = type
        return o
    end
    -- 原版 ISBaseTimedAction.lua:173-184
    function ISBaseTimedAction.new(self, character)
        local o = setmetatable({}, self)
        self.__index = self
        o.character = character
        o.stopOnWalk, o.stopOnRun, o.maxTime = true, true, -1
        return o
    end
    function ISBaseTimedAction.perform(self) log("basePerform", self) end
    function ISBaseTimedAction.stop(self) log("baseStop", self) end
    function ISBaseTimedAction:getJobDelta() return self.jobDelta or 0 end
    function ISBaseTimedAction:setActionAnim(anim) self.anim = anim end
    function ISBaseTimedAction:setAnimVariable(k, v) self.animVar = { k, v } end
    package.loaded["TimedActions/ISBaseTimedAction"] = true
end

function isServer() return true end
function isClient() return false end
function instanceof(o, cls) return type(o) == "table" and rawget(o, "__class") == cls end
function getText(key) return key end
function getSpecificPlayer(n) return env.players[n] end
function sendAddItemToContainer(c, item) log("sendAdd", c, item) end
function triggerEvent(name, ...) log("event", name, ...) end
CharacterTrait = { DEXTROUS = "dextrous", ALL_THUMBS = "allthumbs" }
WearClothingAnimations = {}
ItemContainer = { new = function(type, sq, parent)
    local c = { type = type, sq = sq, parent = parent }
    function c:getType() return self.type end
    log("newContainer", c)
    return c
end }
SafeHouse = { isSafehouseAllowLoot = function(sq, chr)
    log("safehouse", sq, chr)
    return not sq.safehouseDenied
end }
ISTransferAction = {}
function ISTransferAction:transferItem(chr, item, src, dest)
    log("transfer", chr, item, src, dest)
    local wi = item.worldItem
    for i, o in ipairs(wi.sq.wos) do if o == wi then table.remove(wi.sq.wos, i) break end end
    item.worldItem = nil
    dest.items[#dest.items + 1] = item
    return item
end
luautils = { walkAdj = function(chr, sq) log("walkAdj", chr, sq) return env.walkOk end }
ISTimedActionQueue = { add = function(a) log("queue", a) return a end }
ISInventoryPane = { getActualItems = function(items) return items end }
ISInventoryPage = {}
function getPlayerInventory() return { refreshBackpacks = function() log("refresh") end } end

local function newSquare(x, y, z)
    local sq = { x = x, y = y, z = z, wos = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getWorldObjects() return javaList(self.wos) end
    function sq:canReachTo(other) return not other.walled end
    return sq
end
local function newItem(scriptWeight)
    local it = { __class = "Food" }
    local script = { getActualWeight = function() return scriptWeight end }
    function it:getScriptItem() return script end
    function it:getActualWeight() return 0 end
    function it:getWorldItem() return self.worldItem end
    function it:canBeEquipped() return nil end
    function it:getName() return "Bag" end
    function it:setJobType(t) self.jobType = t end
    function it:setJobDelta(d) self.jobDelta = d end
    function it:getEquipSound() return self.equipSound end
    return it
end
local FLOOR = { getType = function() return "floor" end }
local function newBag(scriptWeight, contentWeights, sq)
    local b = newItem(scriptWeight)
    b.__class, b.loc, b.container, b.items = "InventoryContainer", "base:back", FLOOR, {}
    for i, w in ipairs(contentWeights or {}) do b.items[i] = newItem(w) end
    function b:canBeEquipped() return self.loc end
    function b:getContainer() return self.container end
    function b:getInventory() local items = self.items return { getItems = function() return javaList(items) end } end
    if sq then
        b.worldItem = { sq = sq, getSquare = function(wi) return wi.sq end }
        sq.wos[#sq.wos + 1] = b.worldItem
    end
    return b
end
local function newPlayer(x, y, sq, roomFor)
    local p = { x = x, y = y, sq = sq, traits = {}, worn = {} }
    p.inv = { items = {}, hasRoomFor = function(_, chr, item) log("hasRoomFor", chr, item) return roomFor end }
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getCurrentSquare() return self.sq end
    function p:getInventory() return self.inv end
    function p:getVehicle() return self.vehicle end
    function p:getPlayerNum() return 0 end
    function p:hasTrait(t) return self.traits[t] == true end
    function p:isTimedActionInstant() return self.instant == true end
    function p:isWearingAwkwardGloves() return self.awkward == true end
    function p:setWornItem(loc, item) log("wear", loc, item) if loc then self.worn[loc] = item end end
    function p:reportEvent(e) log("reportEvent", e) end
    -- 播放中的聲音記在 playing；emitter 停掉後就不在了
    p.playing = {}
    function p:playSound(name)
        log("playSound", name)
        local id = #env.log
        self.playing[id] = true
        return id
    end
    p.emitter = {
        isPlaying = function(_, id) return p.playing[id] == true end,
        stopSound = function(_, id) log("stopSound", id) p.playing[id] = nil end,
    }
    function p:getEmitter() return self.emitter end
    return p
end

local function loadLua(key) assert(load(readFile(F[key]), "@" .. F[key]))() end
local function loadAll()
    resetEnv()
    loadLua("ACT"); loadLua("MENU")
end

-- 站在背包那一格正中央的玩家與地上裝滿的背包
local function scene(px, py, pz)
    local sq = newSquare(10, 10, 0)
    local bag = newBag(1.0, { 1, 2, 5, 0.1 }, sq)
    local chr = newPlayer(px or 10.5, py or 10.5, newSquare(math.floor(px or 10.5), math.floor(py or 10.5), pz or 0), false)
    env.players = { [0] = chr }
    return chr, bag, sq
end
local function completeWith(chr, bag)
    env.log = {}
    local ok = MDB_WearFromFloor:new(chr, bag):complete()
    return ok, #calls("transfer") > 0 or #calls("wear") > 0
end

-- ===== 套件 =====
local function suite()
    loadAll()

    -- 載入與 NetTimedAction 的約定
    check("MDB_WearFromFloor 的 Type 是同名全域", MDB_WearFromFloor.Type == "MDB_WearFromFloor"
        and _G[MDB_WearFromFloor.Type] == MDB_WearFromFloor)
    local handlers = Events.OnFillInventoryObjectContextMenu.handlers
    check("右鍵選單事件剛好掛一次", #handlers == 1 and handlers[1] == MDB.onFillFloorWearMenu)
    do
        local chr, bag = scene()
        local a = MDB_WearFromFloor:new(chr, bag)
        local args, i = {}, 2
        while true do
            local name = debug.getlocal(MDB_WearFromFloor.new, i)
            if not name then break end
            args[#args + 1] = name
            i = i + 1
        end
        check("new 的參數名與欄位一致（客戶端照參數名讀欄位送伺服器）", #args == 2
            and a[args[1]] == chr and a[args[2]] == bag)
        check("new 算好 maxTime", a.maxTime == a:getDuration())
    end

    -- 右鍵選單
    local function menuFor(items, roomFor, walkOk)
        local sq = newSquare(10, 10, 0)
        local chr = newPlayer(10.5, 10.5, sq, roomFor)
        env.players = { [0] = chr }
        env.walkOk = walkOk ~= false
        local opts = {}
        local context = { addOption = function(_, name, target, fn, param) opts[#opts + 1] = { name = name, target = target, fn = fn, param = param } end }
        env.log = {}
        MDB.onFillFloorWearMenu(0, context, items(sq))
        return opts, chr
    end
    local opts, chr = menuFor(function(sq) return { newBag(1.0, { 1 }, sq) } end, false)
    check("地上放不進物品欄的背包：出現選項", #opts == 1 and opts[1].name == KEY and opts[1].target == chr)
    check("選單照原版用 hasRoomFor 判斷", #calls("hasRoomFor") == 1)
    opts = menuFor(function(sq) return { newBag(1.0, { 1 }, sq) } end, true)
    check("物品欄放得下（原版穿上會成功）：不出現", #opts == 0)
    opts = menuFor(function() return { newBag(1.0, { 1 }) } end, false)
    check("不在地上的背包：不出現", #opts == 0)
    opts = menuFor(function(sq) local b = newBag(1.0, { 1 }, sq) b.loc = nil return { b } end, false)
    check("不能穿的容器：不出現", #opts == 0)
    opts = menuFor(function(sq) local it = newItem(1) it.worldItem = { sq = sq } return { it } end, false)
    check("不是容器：不出現", #opts == 0)
    local target
    opts = menuFor(function(sq)
        target = newBag(1.0, { 1 }, sq)
        return { newItem(1), target, newBag(1.0, {}, sq) }
    end, false)
    check("多選時只加一個選項，對第一個符合的背包", #opts == 1 and opts[1].param == target)

    -- 點選項：先走過去再排動作
    opts, chr = menuFor(function(sq) target = newBag(1.0, { 1 }, sq) return { target } end, false)
    env.log = {}
    opts[1].fn(opts[1].target, opts[1].param)
    local walks, queued = calls("walkAdj"), calls("queue")
    check("點選項先走到背包那一格旁邊", #walks == 1 and walks[1][2] == chr and walks[1][3] == target.worldItem.sq)
    check("走得到就排入穿上動作", #queued == 1 and queued[1][2].item == target and queued[1][2].character == chr
        and getmetatable(queued[1][2]).__index == MDB_WearFromFloor)
    opts = menuFor(function(sq) return { newBag(1.0, { 1 }, sq) } end, false, false)
    env.log = {}
    opts[1].fn(opts[1].target, opts[1].param)
    check("走不到就不排動作", #calls("queue") == 0)

    -- 伺服器 complete()：成功
    do
        local chr, bag, sq = scene()
        local contents = { table.unpack(bag.items) }
        local ok = completeWith(chr, bag)
        local tr, sent, worn = calls("transfer"), calls("sendAdd"), calls("wear")
        check("成功：complete 回 true", ok == true)
        check("成功：用原版 transferItem 從地上搬進物品欄", #tr == 1 and tr[1][2] == chr and tr[1][3] == bag
            and tr[1][4] == FLOOR and tr[1][5] == chr.inv)
        check("成功：背包離開地上", bag.worldItem == nil and #sq.wos == 0)
        check("成功：整件送給客戶端物品欄", #sent == 1 and sent[1][2] == chr.inv and sent[1][3] == bag)
        check("成功：穿在背包自己的位置", #worn == 1 and worn[1][2] == "base:back" and worn[1][3] == bag
            and chr.worn["base:back"] == bag)
        local order = {}
        for _, c in ipairs(env.log) do if c[1] == "transfer" or c[1] == "sendAdd" or c[1] == "wear" then order[#order + 1] = c[1] end end
        check("成功：順序是搬移→送出→穿上", table.concat(order, ",") == "transfer,sendAdd,wear")
        local same = #bag.items == #contents
        for i = 1, #contents do same = same and bag.items[i] == contents[i] end
        check("成功：內容物全程留在包裡", same)
        check("成功：安全區檢查用背包那一格與玩家", #calls("safehouse") == 1 and calls("safehouse")[1][2] == sq
            and calls("safehouse")[1][3] == chr)
    end

    -- 地面容器：伺服器重建的地面容器沒設物品的 container
    for _, case in ipairs({ { "沒有", nil }, { "不是地面", { getType = function() return "none" end } } }) do
        local chr, bag, sq = scene()
        bag.container = case[2]
        completeWith(chr, bag)
        local nc, tr = calls("newContainer"), calls("transfer")
        check("物品的容器" .. case[1] .. "時另開那一格的地面容器", #nc == 1 and nc[1][2].type == "floor" and nc[1][2].sq == sq
            and nc[1][2].parent == nil and #tr == 1 and tr[1][4] == nc[1][2])
    end

    -- 伺服器 complete()：拒絕的分支，一個都不能搬也不能穿
    local function rejects(name, setup, px, py, pz)
        local chr, bag, sq = scene(px, py, pz)
        local item = setup and setup(chr, bag, sq)
        if item == false then item = nil elseif item == nil then item = bag end
        local ok, touched = completeWith(chr, item)
        check("拒絕：" .. name, ok == false and not touched)
    end
    local function accepts(name, px, py)
        local chr, bag = scene(px, py)
        check("接受：" .. name, completeWith(chr, bag) == true)
    end
    accepts("站在斜對角的格子（walkAdj 不會再走）", 11.5, 11.5)
    accepts("站在旁邊格子的遠端", 12.1, 9.0)
    rejects("X 方向超過 walkAdj 的範圍", nil, 12.2, 10.5)
    rejects("Y 方向超過 walkAdj 的範圍", nil, 10.5, 8.8)
    rejects("不同樓層", nil, 10.5, 10.5, 1)
    rejects("中間有牆", function(_, _, sq) sq.walled = true end)
    rejects("坐在車上", function(chr) chr.vehicle = {} end)
    rejects("安全區不允許拿取", function(_, _, sq) sq.safehouseDenied = true end)
    rejects("已經不在地上", function(_, bag) bag.worldItem = nil end)
    rejects("world item 已從那一格移除（被別人撿走）", function(_, _, sq) sq.wos = {} end)
    rejects("不能穿的容器", function(_, bag) bag.loc = nil end)
    rejects("不是容器", function(_, bag) bag.__class = "Clothing" end)
    rejects("伺服器解析不到物品", function() return false end)
    do
        local chr = scene()
        env.log = {}
        local a = MDB_WearFromFloor:new(chr, nil)
        check("解析不到物品時時間為 0、complete 回 false", a.maxTime == 0 and a:complete() == false)
    end

    -- 客戶端 isValid
    do
        local chr, bag = scene()
        local a = MDB_WearFromFloor:new(chr, bag)
        check("isValid：背包還在地上", a:isValid() == true)
        bag.worldItem = nil
        check("isValid：背包離開地上就停", a:isValid() == false)
        bag.worldItem = { sq = newSquare(10, 10, 0), getSquare = function(wi) return wi.sq end }
        chr.vehicle = {}
        check("isValid：上車就停", a:isValid() == false)
    end

    -- 動作時間：穿上 50 ＋ 搬移 50×min(腳本自重, 3)，背包本身與每件內容物各算一次
    do
        local chr, bag = scene()
        local base = 50 * (1 + 1 + 2 + 3 + 0.1)
        local function dur() return MDB_WearFromFloor:new(chr, bag):getDuration() end
        local function near(a, b) return math.abs(a - b) < 1e-9 end
        check("時間：50 + 50×Σmin(腳本自重,3) = " .. (50 + base) .. "（實例自重 0 也照算）", near(dur(), 50 + base))
        chr.traits.dextrous = true
        check("時間：靈巧的搬移部分減半", near(dur(), 50 + base * 0.5))
        chr.traits.dextrous, chr.traits.allthumbs = nil, true
        check("時間：笨手笨腳的搬移部分加倍", near(dur(), 50 + base * 2))
        chr.traits.allthumbs, chr.awkward = nil, true
        check("時間：戴不便的手套搬移部分加倍", near(dur(), 50 + base * 2))
        chr.awkward, chr.instant = nil, true
        check("時間：即時動作模式為 1", dur() == 1)
        local empty = newBag(0.8, {}, newSquare(10, 10, 0))
        chr.instant = nil
        check("時間：空背包＝原版撿起加穿上", near(MDB_WearFromFloor:new(chr, empty):getDuration(), 50 + 50 * 0.8))
    end

    -- 完成後刷新背包面板
    do
        local chr, bag = scene()
        env.log = {}
        MDB_WearFromFloor:new(chr, bag):perform()
        check("perform：刷新背包欄並交回佇列", #calls("refresh") == 1 and #calls("basePerform") == 1)
    end

    -- 聲音與物品上的進度，照原版穿衣服（ISWearClothing.lua:17-23、:52-86、:154-162）
    do
        local chr, bag = scene()
        bag.equipSound = "PutOnBag"
        local a = MDB_WearFromFloor:new(chr, bag)
        env.log = {}
        a:start()
        local sounds = calls("playSound")
        check("start：播翻找聲", #sounds == 1 and sounds[1][2] == "RummageInInventory" and a.sound ~= nil)
        check("start：物品顯示動作名稱、進度歸零", bag.jobType == KEY .. " Bag" and bag.jobDelta == 0)
        check("start：穿衣動畫", a.anim == "WearClothing" and a.animVar[1] == "WearClothingLocation")
        a.jobDelta = 0.5
        a:update()
        check("update：物品進度跟著動作", bag.jobDelta == 0.5 and #calls("playSound") == 1)
        a.jobDelta = 0.8
        a:update()
        a.jobDelta = 0.9
        a:update()
        sounds = calls("playSound")
        check("update：過 0.7 播一次背包的穿戴聲", #sounds == 2 and sounds[2][2] == "PutOnBag")
        local rummage = a.sound
        a:perform()
        local stops = calls("stopSound")
        check("perform：收掉翻找聲、進度歸零", #stops == 1 and stops[1][2] == rummage and bag.jobDelta == 0)

        chr, bag = scene()
        a = MDB_WearFromFloor:new(chr, bag)
        env.log = {}
        a:start()
        a.jobDelta = 0.9
        a:update()
        check("update：沒有穿戴聲的背包不播", #calls("playSound") == 1)
        a:stop()
        stops = calls("stopSound")
        check("stop：收掉翻找聲、進度歸零、交回原版 stop", #stops == 1 and stops[1][2] == a.sound
            and bag.jobDelta == 0 and #calls("baseStop") == 1)
        env.log = {}
        a:stop()
        check("stop：聲音已經停了就不再停", #calls("stopSound") == 0)
    end

    -- 翻譯：16 語都有鍵，只放在 ContextMenu.json
    for _, lang in ipairs(LANGS) do
        local path = TRANSLATE .. lang .. "/ContextMenu.json"
        local text = readFile(path)
        check(lang .. "/ContextMenu.json 有 " .. KEY, text:find('"' .. KEY .. '"%s*:%s*"[^"]+"') ~= nil)
        for _, other in ipairs({ "ItemName.json", "Recipes.json" }) do
            check(lang .. "/" .. other .. " 沒有加這個鍵", not readFile(TRANSLATE .. lang .. "/" .. other):find(KEY, 1, true))
        end
    end
end

io.write("== 穿上地上裝滿的背包\n")
suite()

if arg and arg[1] == "--mutants" then
    local mutants = {
        { name = "距離放寬", file = "ACT", from = "local REACH = 1.6", to = "local REACH = 99" },
        { name = "不檢查樓層", file = "ACT", from = "cur:getZ() ~= sq:getZ()", to = "false" },
        { name = "不檢查牆", file = "ACT", from = "if not cur:canReachTo(sq) then return false end", to = "" },
        { name = "不檢查車上", file = "ACT", from = "if chr:getVehicle() then return false end", to = "" },
        { name = "不檢查安全區", file = "ACT", from = "return SafeHouse.isSafehouseAllowLoot(sq, chr)", to = "return true" },
        { name = "不檢查可穿", file = "ACT", from = " or bag:canBeEquipped() == nil", to = "" },
        { name = "不檢查還在那一格", file = "ACT", from = " or not sq:getWorldObjects():contains(wi)", to = "" },
        { name = "complete 不驗", file = "ACT", from = "if not MDB.canWearFromFloor(chr, bag) then return false end", to = "" },
        { name = "沒用地面容器", file = "ACT", from = 'if not src or src:getType() ~= "floor" then', to = "if not src then" },
        { name = "不送物品欄", file = "ACT", from = "    sendAddItemToContainer(inv, bag)\n", to = "" },
        { name = "不穿上", file = "ACT", from = "chr:setWornItem(bag:canBeEquipped(), bag)", to = "" },
        { name = "時間不加內容物", file = "ACT", from = "t = t + pickupTime(items:get(i))", to = "" },
        { name = "時間用實例自重", file = "ACT", from = "item:getScriptItem():getActualWeight()", to = "item:getActualWeight()" },
        { name = "時間不封頂", file = "ACT", from = "math.min(item:getScriptItem():getActualWeight(), 3)", to = "item:getScriptItem():getActualWeight()" },
        { name = "靈巧不減半", file = "ACT", from = "t = t * 0.5", to = "t = t" },
        { name = "手套不加倍", file = "ACT", from = " or self.character:isWearingAwkwardGloves()", to = "" },
        { name = "沒加穿上時間", file = "ACT", from = "return 50 + t", to = "return t" },
        { name = "沒算 maxTime", file = "ACT", from = "o.maxTime = o:getDuration()", to = "" },
        { name = "參數名和欄位不一致", file = "ACT", from = "new(character, item)\n    local o = ISBaseTimedAction.new(self, character)\n    o.item = item",
          to = "new(character, bag)\n    local o = ISBaseTimedAction.new(self, character)\n    o.item = bag" },
        { name = "Type 不是全域名", file = "ACT", from = 'derive("MDB_WearFromFloor")', to = 'derive("MDB_FloorWear")' },
        { name = "isValid 不看地上", file = "ACT", from = "self.item:getWorldItem() ~= nil and ", to = "" },
        { name = "沒播翻找聲", file = "ACT", from = '    self.sound = self.character:playSound("RummageInInventory")\n', to = "" },
        { name = "停止不收聲", file = "ACT", from = "    self:stopSound()\n    ISBaseTimedAction.stop(self)", to = "    ISBaseTimedAction.stop(self)" },
        { name = "完成不收聲", file = "ACT", from = "    self:stopSound()\n    self.item:setJobDelta(0.0)\n    triggerEvent", to = "    self.item:setJobDelta(0.0)\n    triggerEvent" },
        { name = "停了還再停", file = "ACT", from = "if self.sound and emitter:isPlaying(self.sound) then", to = "if self.sound then" },
        { name = "進度沒跟著動作", file = "ACT", from = "    self.item:setJobDelta(self:getJobDelta())\n", to = "" },
        { name = "停止進度沒歸零", file = "ACT", from = "    self.item:setJobDelta(0.0)\n    self:stopSound()\n    ISBaseTimedAction.stop", to = "    self:stopSound()\n    ISBaseTimedAction.stop" },
        { name = "穿戴聲重複播", file = "ACT", from = "if not self.equipSound and ", to = "if " },
        { name = "穿戴聲太早", file = "ACT", from = "self:getJobDelta() > 0.7", to = "self:getJobDelta() > 0.4" },
        { name = "選單有空間也出現", file = "MENU", from = "\n        and not chr:getInventory():hasRoomFor(chr, item)", to = "" },
        { name = "選單不限地上", file = "MENU", from = "item:getWorldItem() ~= nil and ", to = "" },
        { name = "選單不限可穿", file = "MENU", from = " and item:canBeEquipped() ~= nil", to = "" },
        { name = "選單不走過去", file = "MENU", from = "if luautils.walkAdj(chr, bag:getWorldItem():getSquare()) then", to = "if true then" },
        { name = "選單多個選項", file = "MENU", from = "            return\n", to = "" },
        { name = "選單鍵拼錯", file = "MENU", from = 'getText("ContextMenu_MDB_WearWithContents")', to = 'getText("ContextMenu_MDB_WearWithContent")' },
        { name = "沒掛事件", file = "MENU", from = "Events.OnFillInventoryObjectContextMenu.Add(MDB.onFillFloorWearMenu)", to = "" },
        { name = "翻譯缺鍵", file = "EN", from = '"ContextMenu_MDB_WearWithContents"', to = '"ContextMenu_MDB_WearX"' },
    }
    io.write("== 突變（每個都應至少讓一項 FAIL）\n")
    local survived = 0
    for _, m in ipairs(mutants) do
        local keepPass, keepFail = pass, fail
        MUTATION, quiet = m, true
        pass, fail = 0, 0
        local ok, err = pcall(suite)
        local killed = (not ok) or fail > 0
        io.write(string.format("  %s  %s（%s）\n", killed and "KILLED " or "SURVIVED", m.name,
            ok and (fail .. " 項 FAIL") or ("錯誤：" .. tostring(err))))
        if not killed then survived = survived + 1 end
        pass, fail, MUTATION, quiet = keepPass, keepFail, nil, false
    end
    check("所有突變都被抓到", survived == 0)
end

io.write(string.format("結果：%d PASS，%d FAIL\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
