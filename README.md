# Minidoracat Bags

S.T.A.R.S. 與保護傘主題的 7 款背包，可升三階，並接手 Bag Upgrade Plus 存檔裡的舊背包

Project Zomboid Build 42 MOD。

## 功能

- 兩條產品線：S.T.A.R.S.（深藍與黑色尼龍，警察局取得）與保護傘（橄欖卡其，軍事與醫療地點取得）
- 7 款背包：腰掛工具包、醫療腰包、彈藥背帶、信差側背包、日行背包、遠征框架背包、偵察胸掛
- 原版背包與本 MOD 背包都能升三階，容量變大、負重減輕；幅度與上限是沙盒選項
- 接手 Bag Upgrade Plus：舊存檔裡的背包照樣讀得到（預設只能取出），清空後可改裝成新背包

## 安裝

- Steam Workshop：（首次上傳後補上連結）
- 手動安裝：把 `MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatBagsFor42`

## 開發

- `link_workshop.bat`：手動同步、唯讀狀態與歸檔卸載；MOD 以實體副本放入 `Zomboid\Workshop\` 與 `Zomboid\mods\`，不使用目錄連結
- `PZ_Test.bat`：暗色點選視窗，啟動前增量同步目前 MOD 與家族依賴；首次預設 no-Steam，之後記住各專案的選擇。需要換檔但遊戲仍在執行時拒絕同步與新啟動，不停止既有遊戲；完整驗證與資料邊界見 `../pz-family-docs/tools.md`
- `Publish_Workshop.bat`：發布到 Steam Workshop（需 Steam 用戶端已登入；可選擇只更新內容／封面／簡介；首發仍走遊戲內上傳器）

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.21.0-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
