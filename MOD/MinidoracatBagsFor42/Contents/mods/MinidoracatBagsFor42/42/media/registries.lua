-- 第二個側背包位置：強化版側背包穿這裡，可以和原版側背包（base:satchel）同時穿（使用者 2026-10-26 決定要做）。
-- 引擎在讀物品腳本之前執行各 MOD 的 42/media/registries.lua（ModRegistries.java:9-24；開遊戲 GameWindow.java:201、
-- 重載 Core.java:3930、離開遊戲 IngameState.java:1045、伺服器 GameServer.java:1446），物品腳本的 CanBeEquipped
-- 才解析得到（Item.java:2530-2531，找不到就靜默變成不能穿）。重載前會清掉非 base 的註冊（Registry.java:61-71）。
-- MOD 只能註冊非 base 命名空間（RegistryReset.java:15-21），ID 一律轉小寫（ResourceLocation.java:14-32）。
-- 重複註冊會丟例外（Registry.java:30-39），所以先查再註冊。
-- ID 和 scripts/gen_reinforced.py 的 SATCHEL2、shared/MDB_BodyLocations.lua 相同。
if not ItemBodyLocation.get(ResourceLocation.of("minidoracatbags:satchel2")) then
    ItemBodyLocation.register("minidoracatbags:satchel2")
end
