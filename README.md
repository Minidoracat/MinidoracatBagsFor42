# Minidoracat Bags

S.T.A.R.S. 與保護傘主題的 7 款戰術背包，可升三階，並接手 Bag Upgrade Plus 存檔裡的舊背包

Project Zomboid Build 42 MOD。

## 功能

- 兩條產品線：S.T.A.R.S.（深藍尼龍）與保護傘（橄欖卡其），7 款都有自製模型與圖示，兩種外觀數值相同
- 7 款背包：腰掛工具包、醫療腰包、彈藥背帶、信差側背包、日行背包、遠征框架背包、偵察胸掛
- 專用收納：醫療腰包只收急救類物品；彈藥背帶只收散裝子彈與霰彈（不收盒裝）並加快裝填；偵察胸掛不收單件重量超過 1.3 的物品
- 取得：警察局出 S.T.A.R.S.，軍事與醫療地點出保護傘；警察、軍人、醫護殭屍死亡時也可能掉落；也能用縫紉配方製作
- 升級：原版背包與本 MOD 背包都能用縫紉升三階，容量變大、負重減輕；幅度、上限與最高階是沙盒選項
- 接手 Bag Upgrade Plus（主版、Realistic 版、CloudBag 與舊分支）：舊存檔裡的背包照樣讀得到（預設只能取出），清空後可改裝成新背包（直接是最高階）

完整說明（數值、取得地點、配方、沙盒選項、已知限制）見 Steam 指南：繁中 https://steamcommunity.com/sharedfiles/filedetails/?id=3827498698 、英文 https://steamcommunity.com/sharedfiles/filedetails/?id=3827498713 （稿源 [`STEAM_GUIDE.md`](STEAM_GUIDE.md)、[`STEAM_GUIDE_EN.md`](STEAM_GUIDE_EN.md)）。

## 從 Bag Upgrade Plus 換裝

1. 備份存檔。
2. 同一次重啟：停用所有 Bag Upgrade Plus（`BagUpgradePlusUpdated`、`BagUpgradePlusRealistic`、`BagUpgradePlus`、`CloudBag`），啟用 `MinidoracatBagsFor42`。兩者不要同時開（console 會出現 `WARNING: another Bag Upgrade Plus is loaded`）。
3. 不要先拿掉 Bag Upgrade Plus 開服再補裝本 MOD：那段期間被讀進遊戲的舊背包會連同內容物被刪除，換上本 MOD 也找不回來。

Bag Upgrade Plus EFT 相容版（3781184534）不支援。完整步驟見 Steam 指南的「伺服器換裝」章。

## 安裝

- Steam Workshop：https://steamcommunity.com/sharedfiles/filedetails/?id=3827497087
- 手動安裝：把 `MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatBagsFor42`

## 開發

- `link_workshop.bat`：手動同步、唯讀狀態與歸檔卸載；MOD 以實體副本放入 `Zomboid\Workshop\` 與 `Zomboid\mods\`，不使用目錄連結
- `PZ_Test.bat`：暗色點選視窗，啟動前增量同步目前 MOD 與家族依賴；首次預設 no-Steam，之後記住各專案的選擇。需要換檔但遊戲仍在執行時拒絕同步與新啟動，不停止既有遊戲；完整驗證與資料邊界見 `../pz-family-docs/tools.md`
- `Publish_Workshop.bat`：發布到 Steam Workshop（需 Steam 用戶端已登入；可選擇只更新內容／封面／簡介；首發仍走遊戲內上傳器）

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.21.0-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
