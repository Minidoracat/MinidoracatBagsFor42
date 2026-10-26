-- 跑一次 MDB_Attach.lua＋MDB_AttachClient.lua（假引擎），把遊戲會加上的模型掛點與資料表寫成 JSON，給 preview.py 算圖用。
-- lua scripts/blender/attach/dump_attach.lua temp/attach.json      （在 repo 根目錄跑）
local LUA = "MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42/42/media/lua/"
local out = assert(arg[1], "usage: lua dump_attach.lua <out.json>")

local models = {}
local function vec()
    local v = { 0, 0, 0 }
    function v:set(x, y, z) self[1], self[2], self[3] = x, y, z end
    return v
end
ModelAttachment = { new = function(id)
    local a = { id = id, off = vec(), rot = vec() }
    function a:setBone(b) self.bone = b end
    function a:getOffset() return self.off end
    function a:getRotate() return self.rot end
    return a
end }
function getScriptManager()
    return {
        getItem = function() return nil end,
        getModelScript = function(_, name)
            models[name] = models[name] or { byId = {}, list = {} }
            local ms = models[name]
            function ms:getAttachmentById(id) return self.byId[id] end
            function ms:addAttachment(a) self.byId[a.id] = a; self.list[#self.list + 1] = a end
            return ms
        end,
    }
end
AttachedLocations = { getGroup = function()
    return { getOrCreateLocation = function() return { setAttachmentName = function() end } end }
end }
ISHotbarAttachDefinition, ISHotbar = {}, { doMenuFromInventory = function() end }
package.loaded["Hotbar/ISHotbarAttachDefinition"], package.loaded["Hotbar/ISHotbar"] = true, true
dofile(LUA .. "shared/MDB_Attach.lua")
dofile(LUA .. "client/MDB_AttachClient.lua")

local function json(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local s = {}
            for i = 1, #v do s[i] = json(v[i]) end
            return "[" .. table.concat(s, ",") .. "]"
        end
        local keys, s = {}, {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do s[#s + 1] = string.format("%q:%s", k, json(v[k])) end
        return "{" .. table.concat(s, ",") .. "}"
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "number" then
        return string.format("%.6f", v)
    end
    return tostring(v)
end

local attach = {}
for name, ms in pairs(models) do
    attach[name] = {}
    for _, a in ipairs(ms.list) do attach[name][a.id] = { bone = a.bone or "", off = { a.off[1], a.off[2], a.off[3] }, rot = { a.rot[1], a.rot[2], a.rot[3] } } end
end
local fams = {}
for _, f in ipairs(MDB.ATTACH_FAMILIES) do fams[#fams + 1] = { name = f.name, slots = f.slots } end
local f = assert(io.open(out, "w"))
f:write(json({ attach = attach, accepts = MDB.ATTACH_ACCEPTS, families = fams, items = MDB.ATTACH_ITEMS, static = MDB.ATTACH_STATIC }))
f:close()
print("wrote " .. out)
