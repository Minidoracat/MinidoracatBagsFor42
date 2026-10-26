-- 直接穿上地上裝滿的背包，內容物全程留在包裡。
-- 原版「穿上」先把背包搬進物品欄，客戶端用 hasRoomFor 檢查，未穿時的重量是自重加全部內容物、不打折，
-- 裝滿的背包就被擋下（ISInventoryTransferAction.lua:110、ItemContainer.java:214-235）；伺服器本身不檢查容量。
-- 這個動作在伺服器（MP，NetTimedAction.java:132-139）或單機（IsoGameCharacter.java:9021-9025）的 complete()
-- 驗證後，從地上搬進物品欄再穿上。選單在 client/MDB_FloorWearMenu.lua。
require "TimedActions/ISBaseTimedAction"
MDB = MDB or {}

-- luautils.walkAdj 視為「已在旁邊、不用走」的範圍（luautils.lua:138-140），選單照它走過去，伺服器照它驗。
-- 不用 Transaction.java:340-341 的 1.1：那是量到格子角落，站在斜對角的格子就超過；
-- 而且搬地上物品時 :305-308 先把來源清掉，那個檢查實際上不會生效。
local REACH = 1.6

-- 伺服器與單機在 complete() 呼叫；客戶端選單只看容量，其他條件都在這裡驗
function MDB.canWearFromFloor(chr, bag)
    if not bag or not instanceof(bag, "InventoryContainer") or bag:canBeEquipped() == nil then return false end
    local wi = bag:getWorldItem()
    local sq = wi and wi:getSquare()
    -- 還在那一格地上：被別人撿走時 world item 會清掉（Transaction.java:305-308、IsoGridSquare.removeWorldObject）
    if not sq or not sq:getWorldObjects():contains(wi) then return false end
    local cur = chr:getCurrentSquare()
    if not cur or cur:getZ() ~= sq:getZ() then return false end
    if math.abs(sq:getX() + 0.5 - chr:getX()) > REACH or math.abs(sq:getY() + 0.5 - chr:getY()) > REACH then return false end
    if not cur:canReachTo(sq) then return false end
    if chr:getVehicle() then return false end
    -- 比照原版交易對地上來源的安全區檢查（TransactionManager.java:138-140）
    return SafeHouse.isSafehouseAllowLoot(sq, chr)
end

-- 一件物品從地上搬到身上容器的原版時間：50 × min(自重, 3)（ISInventoryTransferAction.lua:802-816、Transaction.java:366-381）。
-- 自重取腳本值：伺服器上 getActualWeight() 會回 0（InventoryItem.java:2740-2742），時間由伺服器算（NetTimedAction.java:71-82）。
local function pickupTime(item)
    return 50 * math.min(item:getScriptItem():getActualWeight(), 3)
end

MDB_WearFromFloor = ISBaseTimedAction:derive("MDB_WearFromFloor")

-- MP 客戶端只看物品還在，照原版穿衣服（ISWearClothing.lua:10-11）：伺服器 complete() 成功時，地面移除的封包
-- 可能比完成通知先到（RemoveItemFromSquarePacket.java:83-93），引擎每格先問 isValid 才讀完成（IsoGameCharacter.java:9013-9035），
-- 這時看地上會判成失效、走 stop() 把後面排的動作全清掉（ISBaseTimedAction.lua:63-64）。搶輸時伺服器拒絕，照樣停下。
function MDB_WearFromFloor:isValid()
    if not self.item or self.character:getVehicle() then return false end
    return isClient() or self.item:getWorldItem() ~= nil
end

-- 聲音與物品上的進度照原版穿衣服（ISWearClothing.lua:17-23、:52-80、:82-86、:154-162）：
-- 開始播翻找聲，快穿好時播背包的穿戴聲，停止或完成時收掉翻找聲
function MDB_WearFromFloor:update()
    self.item:setJobDelta(self:getJobDelta())
    if not self.equipSound and self:getJobDelta() > 0.7 and self.item:getEquipSound() then
        self.equipSound = self.character:playSound(self.item:getEquipSound())
    end
end

function MDB_WearFromFloor:start()
    self.item:setJobType(getText("ContextMenu_MDB_WearWithContents") .. " " .. self.item:getName())
    self.item:setJobDelta(0.0)
    self:setActionAnim("WearClothing")
    self:setAnimVariable("WearClothingLocation", WearClothingAnimations[self.item:canBeEquipped()] or "")
    self.character:reportEvent("EventWearClothing")
    self.sound = self.character:playSound("RummageInInventory")
end

-- 原版的 soundNoTrigger 一律是 true，所以只走 stopSound 那一支
function MDB_WearFromFloor:stopSound()
    local emitter = self.character:getEmitter()
    if self.sound and emitter:isPlaying(self.sound) then emitter:stopSound(self.sound) end
end

function MDB_WearFromFloor:stop()
    self.item:setJobDelta(0.0)
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function MDB_WearFromFloor:perform()
    self:stopSound()
    self.item:setJobDelta(0.0)
    triggerEvent("OnClothingUpdated", self.character)
    getPlayerInventory(self.character:getPlayerNum()):refreshBackpacks()
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

function MDB_WearFromFloor:complete()
    local bag, chr = self.item, self.character
    if not MDB.canWearFromFloor(chr, bag) then return false end
    local sq = bag:getWorldItem():getSquare()
    -- 單機是背包面板的地面容器；伺服器重建的地面容器沒設物品的 container（ContainerID.java:392-396、:566-575），另開一個
    local src = bag:getContainer()
    if not src or src:getType() ~= "floor" then src = ItemContainer.new("floor", sq, nil) end
    local inv = chr:getInventory()
    -- 從地上移除並廣播（ISTransferAction.lua:131-160），內容物跟著背包，不另外搬
    ISTransferAction:transferItem(chr, bag, src, inv)
    sendAddItemToContainer(inv, bag)
    -- 位置上原有的背包：引擎先穿上新的、再用 hasRoomFor 判舊背包，舊背包的未穿重量被算兩次（IsoGameCharacter.java:3435-3444、
    -- ItemContainer.java:268），接近負重上限時放得下也會掉到腳下；原版從物品欄穿上也一樣（ISWearClothing.lua:118）。
    -- 這裡照引擎的算法（IsoGameCharacter.getInventoryWeight）先算穿上後的總重，超過才讓引擎丟到腳下（穿戴與掉落都會廣播，:3444-3478）；
    -- 捨入照 hasRoomFor 用 floatingPointCorrection（ItemContainer.java:153-156、:268），剛好放滿時浮點誤差不會讓總重超過上限
    local loc = bag:canBeEquipped()
    local old = chr:getWornItem(loc)
    local after = inv:getCapacityWeight() - bag:getUnequippedWeight() + bag:getEquippedWeight()
    if old then after = after - old:getEquippedWeight() + old:getUnequippedWeight() end
    chr:setWornItem(loc, bag, ItemContainer.floatingPointCorrection(after) > inv:getEffectiveCapacity(chr))
    return true
end

-- 原版「撿起背包＋穿上」，再加上把每件內容物從地上放回穿著的背包；手動「拿出→穿→放回」還多了倒出來那一段。
-- 穿上 50（ISWearClothing.lua:143-152）；搬移部分的靈巧減半、笨手笨腳或戴不便的手套加倍照原版（ISInventoryTransferAction.lua:833-838）。
function MDB_WearFromFloor:getDuration()
    if not self.item then return 0 end
    if self.character:isTimedActionInstant() then return 1 end
    local t = pickupTime(self.item)
    local items = self.item:getInventory():getItems()
    for i = 0, items:size() - 1 do
        t = t + pickupTime(items:get(i))
    end
    if self.character:hasTrait(CharacterTrait.DEXTROUS) then t = t * 0.5 end
    if self.character:hasTrait(CharacterTrait.ALL_THUMBS) or self.character:isWearingAwkwardGloves() then t = t * 2 end
    return 50 + t
end

-- 參數名稱要和欄位名稱一樣：MP 客戶端照 new 的參數名讀欄位送給伺服器，伺服器再用同樣順序呼叫 new（NetTimedAction.java:37-55、:145-165）
function MDB_WearFromFloor:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.maxTime = o:getDuration()
    return o
end
