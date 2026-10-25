"""背包產線共用：路徑、深藍調色參數、仿射擬合。Blender 內外都能 import（只用 numpy）。"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEMP_ROOT = os.path.join(REPO, "temp", "bags")
PZ = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media"
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
TRIPO_ROOT = "D:/github/tripo-refs/collections/MinidoracatBagsFor42/items"
# 深藍調色（7 款共用，只放這裡）：Tripo 的藍色布料 飽和度×NAVY_S、亮度×NAVY_V，色相固定 0.625。
# 2026-10-25 使用者看實機對照（ServerPatch temp/bags-design/ingame/navy/）選「中」；另兩版是 0.70/0.82（太暗近黑）、0.72/1.20
NAVY_S, NAVY_V = 0.70, 1.00

sys.path.insert(0, HERE)
import xio  # noqa: E402


def temp(name):
    """每款的中間產物資料夾；產物在 <temp>/out/media（結構同 MOD 的 media/）。"""
    return os.path.join(TEMP_ROOT, name)


def out(name):
    return os.path.join(temp(name), "out", "media")


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
