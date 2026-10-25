"""日行背包產線共用：路徑、原版網格的分段、仿射擬合。Blender 內外都能 import（只用 numpy）。"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEMP = os.path.join(REPO, "temp", "bags")
OUT = os.path.join(TEMP, "out", "media")          # 產物，結構同 MOD 的 media/
PZ = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media"
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
TRIPO = "D:/github/tripo-refs/collections/MinidoracatBagsFor42/items/日行背包(DayPack)/model"
MEDIA = os.path.join(REPO, "MOD", "MinidoracatBagsFor42", "Contents", "mods", "MinidoracatBagsFor42", "42", "media")
STRAP0 = 251   # 原版 M/F/RHand 第 251 號以後是兩條肩帶（連通塊 251-325、326-398），面 264-411
BELT0 = 195    # 本體連通塊 195-250 是繞到前面的腰帶，新背包不要
Y0 = 0.5625   # 原版日行包本體底部 y；新本體底部對齊這裡
LEAN = 0.17   # 本體背板後傾（z += LEAN·(y−Y0)），照原版背板斜率，否則被身體背面頂穿；地面模型擬合前要先去掉

sys.path.insert(0, HERE)
import xio  # noqa: E402


def fit_affine(A, B):
    """最小平方 B ≈ A·L + t；殘差 >5×中位數（且 >2 mm 單位）的點當離群剔除後重擬一次。
    回 (L 3x3, t, 每點殘差, 離群點索引)。原版 F／RHand 各有第 16、35 號兩點被美術另外推過（約 9、21 mm 單位）。"""
    Ah = np.c_[A, np.ones(len(A))]
    keep = np.ones(len(A), bool)
    for _ in range(2):
        X, *_ = np.linalg.lstsq(Ah[keep], B[keep], rcond=None)
        r = np.linalg.norm(Ah @ X - B, axis=1)
        keep = r < max(0.002, 5 * np.median(r))
    return X[:3], X[3], r, np.nonzero(~keep)[0]
