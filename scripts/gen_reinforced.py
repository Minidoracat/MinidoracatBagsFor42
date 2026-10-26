# -*- coding: utf-8 -*-
"""產生強化版背包：物品腳本、ClothingItem XML、fileGuidTable、16 語名稱（物品與液體容器）、配方清單。

用法（repo 根目錄）：
    uv run scripts/gen_reinforced.py                     寫入
    uv run scripts/gen_reinforced.py --check             只比對，已提交的檔案和產生結果不同就列出並回 1（遊戲更新後重核用）
    uv run scripts/gen_reinforced.py --mirror-map PATH   側背包鏡像對照檔改用 PATH（預設 scripts/satchel_mirror_map.json）
    uv run scripts/gen_reinforced.py --print NAME        只印出檔名為 NAME 的產生結果，不寫檔（測試用）

來源表是 MDB_Upgrade.lua 的 MDB.REINFORCED_SOURCES（Lua 也用同一張表），要加款式只加那張表再跑本腳本。
每個來源 <模組>.<名稱>（原版或本 MOD 的背包）產生 MinidoracatBags.<名稱>_Reinforced：
- 欄位照來源的腳本逐行抄，只改這些：
  - Weight 0.1（來源沒寫就補在 ItemType 後面；引擎預設是 1.0，Item.java:83）、RunSpeedModifier 1.0（同樣沒寫就補）。
  - ClothingItem 改用自己的名稱 MDB_<名稱>_Reinforced。
  - ClothingItemExtra（換穿法）：目標也是來源時指向目標的強化版；目標不是來源就停下來，要先把它加進來源表。
  - CanBeEquipped／BodyLocation 是 base:satchel 的改成第二個側背包位置（SATCHEL2，registries.lua 註冊）。
  - 液體元件的 ContainerName 改成 MDB_<名稱>_Reinforced：有液體容器的物品，物品欄、提示框與液體面板顯示的是
    Fluid_Container_<ContainerName>，不是 ItemName（InventoryItem.java:2436-2437、FluidContainer.java:398-404、
    ISFluidContainerPanel.lua:146-149），所以 Fluids.json 另給它和 ItemName 相同的強化版名稱。
- ClothingItem MDB_<名稱>_Reinforced：XML 照來源的 XML，換 GUID（uuid5，重跑結果不變）；名稱是全域對照，
  不能沿用來源名稱（ScriptManager.java:1883-1891）。側背包另照鏡像對照檔改寫男女模型路徑（檔案不存在就照原路徑）：
  格式 { "<來源 XML 的 m_MaleModel／m_FemaleModel 原字串>": "<鏡像模型路徑，同樣寫法>" }，每個鍵都要用得到、值要找得到檔案。
- 名稱＝各語言的來源名稱＋強化標記；繁中的原版名稱照 LangFor42，本 MOD 的照自己的翻譯。簡中名稱要原版字型畫得出來。
- MDB_Reinforced.txt 另有還原與「已升級背包改成強化版」兩條配方；MDB_Recipes.txt 三條升級配方的背包清單補上強化版。
"""
import json
import os
import re
import sys
import uuid

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(REPO, "MOD", "MinidoracatBagsFor42", "Contents", "mods", "MinidoracatBagsFor42", "42", "media")
PZ = os.path.join(os.environ.get("PZ_PATH", r"D:\SteamLibrary\steamapps\common\ProjectZomboid"), "media")
LANGFOR42 = os.path.join(os.path.dirname(REPO), "MinidoracatLangFor42", "MOD", "MinidoracatLangFor42", "Contents",
                         "mods", "MinidoracatLangFor42", "42", "media", "lua", "shared", "Translate")

MODULE = "MinidoracatBags"
SUFFIX = "_Reinforced"
GUID_NS = uuid.UUID("5a0d3c1e-6b7f-4c52-9f1e-4d42b0a7c3e1")   # 固定命名空間：同名稱永遠得到同一個 GUID
SATCHEL = "base:satchel"
SATCHEL2 = "minidoracatbags:satchel2"   # 和 registries.lua、MDB_BodyLocations.lua 同一個 ID
DEFAULT_MIRROR_MAP = os.path.join(REPO, "scripts", "satchel_mirror_map.json")

# 強化標記：照本 MOD 升級配方名稱用的詞（Recipes.json 的 MDB_UpgradeBagTier*）；
# 名詞有陰陽性的語言用「強化版」名詞片語，不必配合每個背包名稱的性別
MARK = {
    "AR": " (versión reforzada)", "CH": "（強化）", "CN": "（强化）", "DE": " (verstärkt)", "EN": " (Reinforced)",
    "ES": " (versión reforzada)", "ES_CL": " (versión reforzada)", "ES_MX": " (versión reforzada)",
    "FR": " (version renforcée)", "JP": "（強化）", "KO": " (강화)", "PL": " (wersja wzmocniona)",
    "PT": " (Versão Reforçada)", "PTBR": " (Versão Reforçada)", "RU": " (укреплённая версия)", "TR": " (Güçlendirilmiş)",
}
LANGS = sorted(MARK)
CN_FONTS = ("zomboidSmallChinese.fnt", "zomboidMediumChinese.fnt", "zomboidLargeChinese.fnt")   # fonts/CN/fonts.txt 的六種 UI 字型
CN_AVOID = "刚满这该顶数时级"   # 本 MOD 簡中譯文已知要避開的缺字

ITEM_SCRIPTS = [os.path.join(PZ, "scripts", "generated", "items"), os.path.join(MEDIA, "scripts", "MDB_Items.txt")]
MOD_CLOTHING = os.path.join(MEDIA, "clothing", "clothingItems")
PZ_CLOTHING = os.path.join(PZ, "clothing", "clothingItems")
OUT_SCRIPT = os.path.join(MEDIA, "scripts", "MDB_Reinforced.txt")
RECIPES = os.path.join(MEDIA, "scripts", "MDB_Recipes.txt")
GUIDTABLE = os.path.join(MEDIA, "fileGuidTable.xml")
TRANSLATE = os.path.join(MEDIA, "lua", "shared", "Translate")


def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return f.read().replace("\r\n", "\n")


def sources():
    lua = read(os.path.join(MEDIA, "lua", "shared", "MDB_Upgrade.lua"))
    body = re.search(r"MDB\.REINFORCED_SOURCES\s*=\s*(\{.*?\})", lua, re.S)
    if not body:
        sys.exit("MDB_Upgrade.lua 找不到 MDB.REINFORCED_SOURCES")
    src = re.findall(r'"([\w]+\.[\w]+)"', body.group(1))
    if len(set(src)) != len(src):
        sys.exit("MDB.REINFORCED_SOURCES 有重複")
    return src


def reinforced(full):
    return f"{MODULE}.{full.split('.', 1)[1]}{SUFFIX}"


def own_name(full):
    """強化版自己的 ClothingItem 名稱，也是液體容器名稱"""
    return f"MDB_{full.split('.', 1)[1]}{SUFFIX}"


def item_blocks():
    """{完整 ID: 區塊行（含 item 行到結尾大括號）}；來源是原版 generated/items 與本 MOD 物品腳本"""
    files = []
    for p in ITEM_SCRIPTS:
        files += [os.path.join(p, f) for f in sorted(os.listdir(p)) if f.endswith(".txt")] if os.path.isdir(p) else [p]
    out = {}
    for path in files:
        lines = re.sub(r"/\*.*?\*/", "", read(path), flags=re.S).split("\n")
        module, i = None, 0
        while i < len(lines):
            m = re.match(r"^\s*module\s+(\w+)", lines[i])
            if m:
                module = m.group(1)
            m = re.match(r"^\s*item\s+(\w+)\s*$", lines[i])
            if m and module:
                depth, j = 0, i + 1
                while True:
                    depth += lines[j].count("{") - lines[j].count("}")
                    if depth == 0:
                        break
                    j += 1
                out[f"{module}.{m.group(1)}"] = lines[i:j + 1]
                i = j
            i += 1
    return out


def top_fields(block):
    """第一層欄位 {key: value}"""
    out, depth = {}, 0
    for line in block:
        m = re.match(r"^\s*(\w+)\s*=\s*(.*?),\s*$", line)
        if depth == 1 and m:
            out[m.group(1)] = m.group(2)
        depth += line.count("{") - line.count("}")
    return out


def item_text(full, block, mapping):
    """抄來源欄位，只改說明列出的幾項；Weight、RunSpeedModifier 沒寫就補，寫兩次以上或沒有 ClothingItem 就停"""
    name, module = full.split(".", 1)[1], full.split(".", 1)[0]
    seen = {"Weight": 0, "RunSpeedModifier": 0, "ClothingItem": 0}
    out, depth, item_type_at, indent = [], 0, None, "        "
    for line in block:
        m = re.match(r"^(\s*)(\w+)(\s*=\s*)(.*?),\s*$", line)
        if depth == 1 and m:
            ind, key, eq, val = m.groups()
            indent = ind
            if key == "Weight":
                val = "0.1"
            elif key == "RunSpeedModifier":
                val = "1.0"
            elif key == "ClothingItem":
                val = own_name(full)
            elif key == "ClothingItemExtra":
                extras = []
                for e in val.split(";"):
                    e = e if "." in e else f"{module}.{e}"
                    if e not in mapping:
                        sys.exit(f"{full}: ClothingItemExtra {e} 不在 MDB.REINFORCED_SOURCES，強化版換穿後會變回非強化版；先把它加進來源表")
                    extras.append(mapping[e])
                val = ";".join(extras)
            elif key in ("CanBeEquipped", "BodyLocation") and val.lower() == SATCHEL:
                val = SATCHEL2
            if key in seen:
                seen[key] += 1
            line = f"{ind}{key}{eq}{val},"
            if key == "ItemType":
                item_type_at = len(out)
        elif depth == 2 and m and m.group(2) == "ContainerName":
            line = f"{m.group(1)}ContainerName{m.group(3)}{own_name(full)},"
        elif depth == 0 and re.match(r"^\s*item\s+\w+\s*$", line):
            line = re.sub(r"item\s+\w+", f"item {name}{SUFFIX}", line)
        depth += line.count("{") - line.count("}")
        out.append(line)
    bad = [k for k, n in seen.items() if n > 1 or (k == "ClothingItem" and n == 0)]
    if bad or item_type_at is None:
        sys.exit(f"{full}: 欄位 {bad or ['ItemType']} 數量不對，腳本格式變了，先看來源再改產生器")
    for key, val in (("RunSpeedModifier", "1.0"), ("Weight", "0.1")):
        if seen[key] == 0:
            out.insert(item_type_at + 1, f"{indent}{key} = {val},")
    return "\n".join(out)


def model_file_exists(path):
    """XML 模型路徑找得到檔案：media\\ 開頭是相對於 42/；否則相對於 media/models_X，可省略副檔名（MOD 或原版）"""
    p = path.replace("\\", "/")
    roots = [os.path.dirname(MEDIA), os.path.dirname(PZ)] if p.lower().startswith("media/") else \
        [os.path.join(MEDIA, "models_X"), os.path.join(PZ, "models_X")]
    return any(os.path.isfile(os.path.join(r, p) + ext) for r in roots for ext in ("", ".X", ".x", ".fbx", ".FBX", ".glb"))


def load_mirror_map(path):
    if not os.path.isfile(path):
        return {}
    data = json.loads(read(path))
    if not isinstance(data, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in data.items()):
        sys.exit(f"{path}: 要是「原模型路徑 → 鏡像模型路徑」的字串對照")
    missing = [v for v in data.values() if not model_file_exists(v)]
    if missing:
        sys.exit(f"{path}: 找不到鏡像模型 {missing}")
    return data


def clothing_xml(full, block, mirror, used):
    src = top_fields(block).get("ClothingItem")
    p = os.path.join(MOD_CLOTHING if full.startswith(MODULE + ".") else PZ_CLOTHING, f"{src}.xml")
    if not os.path.isfile(p):
        sys.exit(f"{full}: 找不到 ClothingItem {p}")
    name = own_name(full)
    guid = str(uuid.uuid5(GUID_NS, name))
    xml, n = re.subn(r"<m_GUID>[^<]*</m_GUID>", f"<m_GUID>{guid}</m_GUID>", read(p))
    if n != 1:
        sys.exit(f"{p}: m_GUID 不是剛好一個")
    if top_fields(block).get("CanBeEquipped", "").lower() == SATCHEL:
        def swap(m):
            if m.group(2) in mirror:
                used.add(m.group(2))
                return f"<{m.group(1)}>{mirror[m.group(2)]}</{m.group(1)}>"
            return m.group(0)
        xml = re.sub(r"<(m_MaleModel|m_FemaleModel)>([^<]*)</\1>", swap, xml)
    return name, guid, xml


def recipe(name, bags, extra, hooks):
    lines = [f"    craftRecipe {name}", "    {", "        timedAction = SewingCloth,", "        time = 100,",
             "        AllowBatchCraft = false,", "        Tags = AnySurfaceCraft,", "        category = Tailoring,"]
    lines += [f"        {k} = {v}," for k, v in hooks]
    lines += ["        inputs", "        {", f"            item 1 [{';'.join(bags)}] mode:keep flags[IsNotWorn],",
              f"            {extra},", "        }", "        outputs", "        {", "        }", "    }"]
    return "\n".join(lines)


def names_for(full, lang):
    """遊戲在這個語言顯示的來源名稱：語言檔沒有的鍵退回英文（Translator.java:340-354，16 語都沒有 base 語言）"""
    if full.startswith("Base."):
        vanilla = os.path.join(PZ, "lua", "shared", "Translate", "{}", "ItemName.json")
        files = ([os.path.join(LANGFOR42, "CH", "ItemName.json")] if lang == "CH" else []) + \
                [vanilla.format(lang), vanilla.format("EN")]
    else:
        files = [os.path.join(TRANSLATE, lang, "ItemName.json"), os.path.join(TRANSLATE, "EN", "ItemName.json")]
    for p in files:
        v = json.loads(read(p)).get(full) if os.path.isfile(p) else None
        if v:
            return v
    sys.exit(f"{lang}: 找不到 {full} 的名稱（{files}）")


def cn_glyphs():
    """簡中六種 UI 字型、各字級都畫得出的字（verify_mod.py 的字型規則只對原版 CN 字型取交集）"""
    sets = []
    for size in ("1x", "2x", "3x", "4x"):
        for fn in CN_FONTS:
            p = os.path.join(PZ, "fonts", "CN", size, fn)
            if os.path.isfile(p):
                sets.append({int(x) for x in re.findall(r"^char id=(\d+)", read(p), re.M)})
    if not sets:
        sys.exit("找不到原版簡中字型，無法檢查缺字（設定 PZ_PATH）")
    return set.intersection(*sets)


def build(mirror_path):
    src = sources()
    mapping = {s: reinforced(s) for s in src}
    blocks = item_blocks()
    mirror, used = load_mirror_map(mirror_path), set()
    out = {}

    items, guids, fluid_sources = [], [], []
    for s in src:
        if s not in blocks:
            sys.exit(f"找不到來源物品 {s}")
        items.append(item_text(s, blocks[s], mapping))
        if f"ContainerName = {own_name(s)}," in items[-1]:
            fluid_sources.append(s)
        name, guid, xml = clothing_xml(s, blocks[s], mirror, used)
        out[os.path.join(MOD_CLOTHING, name + ".xml")] = xml
        guids.append((name, guid))
    if set(mirror) - used:
        sys.exit(f"{mirror_path}: 這些鍵不是任何側背包來源 XML 的男女模型路徑：{sorted(set(mirror) - used)}")
    vanilla_guids = set(g.lower() for g in re.findall(r"<guid>\s*([\w-]+)\s*</guid>", read(os.path.join(PZ, "fileGuidTable.xml"))))
    if any(g in vanilla_guids for _, g in guids) or len({g for _, g in guids}) != len(guids):
        sys.exit("GUID 和原版重複或彼此重複")

    rein = [mapping[s] for s in src]
    out[OUT_SCRIPT] = "\n".join([
        "/* 由 scripts/gen_reinforced.py 產生，不要手改；來源表是 MDB_Upgrade.lua 的 MDB.REINFORCED_SOURCES。",
        "   強化版：欄位照來源，自重 0.1、不減速、自己的 ClothingItem、側背包穿第二個側背包位置；",
        "   容量、負重減輕、液體由 MDB.applyTier 依階級升。",
        "   不放進戰利品與殭屍掉落；只從升級、舊 Plus 改裝、布吊帶包直接製作取得。",
        "   還原：強化版改回來源，階級、內容物、modData 照舊（MDB.onSwapKeepTier）。",
        "   已升級背包改成強化版：給 0.1.0 升過級的背包，只換型、階級照舊（OnTest 只放行第 1 階以上）。 */",
        "module MinidoracatBags", "{", "    imports", "    {", "        Base", "    }", "",
        "\n\n".join(items), "",
        recipe("MDB_RestoreReinforced", rein, "item 1 tags[base:scissors] mode:keep flags[IsNotDull;MayDegradeLight]",
               [("OnCreate", "MDB.onSwapKeepTier")]), "",
        recipe("MDB_ReinforceUpgradedBag", src, "item 1 tags[base:sewingneedle] mode:keep",
               [("OnTest", "MDB.onTestUpgraded"), ("OnCreate", "MDB.onSwapKeepTier")]),
        "}", ""])

    # 升級配方的背包清單：保留手寫的部分，強化版照表重排在最後
    text = read(RECIPES)

    def fix(m):
        keep = [b for b in m.group(2).split(";") if not (b.startswith(MODULE + ".") and b.endswith(SUFFIX))]
        return m.group(1) + ";".join(keep + rein) + m.group(3)
    text, n = re.subn(r"(item 1 \[)([^\]]*)(\] mode:keep flags\[IsNotWorn\])", fix, text)
    if n != 3:
        sys.exit(f"MDB_Recipes.txt 升級配方背包行應有 3 條，找到 {n}")
    out[RECIPES] = text

    gt = re.sub(r"\t<files>\n\t\t<path>media/clothing/clothingItems/MDB_\w+" + SUFFIX + r"\.xml</path>\n\t\t<guid>[\w-]+</guid>\n\t</files>\n",
                "", read(GUIDTABLE))
    add = "".join(f"\t<files>\n\t\t<path>media/clothing/clothingItems/{n}.xml</path>\n\t\t<guid>{g}</guid>\n\t</files>\n"
                  for n, g in guids)
    out[GUIDTABLE] = gt.replace("</fileGuidTable>", add + "</fileGuidTable>")

    # 簡中：來源名稱照遊戲本來的樣子沿用（原版簡中名稱本身就有字型缺的字，例如「军」，遊戲顯示原版物品時一樣缺）；
    # 我們加上的強化標記一定要畫得出來，整個名稱也不能有已知缺字 CN_AVOID
    glyphs, cn_bad = cn_glyphs(), []
    if any(ord(c) not in glyphs for c in MARK["CN"]):
        sys.exit(f"簡中強化標記 {MARK['CN']} 有原版字型畫不出來的字")
    for lang in LANGS:
        p = os.path.join(TRANSLATE, lang, "ItemName.json")
        d = {k: v for k, v in json.loads(read(p)).items() if not (k.startswith(MODULE + ".") and k.endswith(SUFFIX))}
        for s in src:
            d[mapping[s]] = names_for(s, lang) + MARK[lang]
            if lang == "CN" and any(c in d[mapping[s]] for c in CN_AVOID):
                cn_bad.append(f"{s}：{d[mapping[s]]}")
        out[p] = json.dumps(d, ensure_ascii=False, indent=4) + "\n"
        # 液體容器名稱（Translator.java:159 依檔名 Fluids 分表，getFluidText 查 Fluid_ 開頭的鍵，:871-874）
        fp = os.path.join(TRANSLATE, lang, "Fluids.json")
        fd = json.loads(read(fp)) if os.path.isfile(fp) else {}
        fd = {k: v for k, v in fd.items() if not (k.startswith("Fluid_Container_MDB_") and k.endswith(SUFFIX))}
        for s in fluid_sources:
            fd[f"Fluid_Container_{own_name(s)}"] = d[mapping[s]]
        out[fp] = json.dumps(fd, ensure_ascii=False, indent=4) + "\n"
    if cn_bad:
        sys.exit(f"簡中名稱有已知缺字 {CN_AVOID}：\n  " + "\n  ".join(cn_bad))
    return out


def stale(out):
    """磁碟上有、但這次沒產生的強化版 XML"""
    return [os.path.join(MOD_CLOTHING, f) for f in os.listdir(MOD_CLOTHING)
            if f.startswith("MDB_") and f.endswith(SUFFIX + ".xml") and os.path.join(MOD_CLOTHING, f) not in out]


def arg_value(flag):
    args = sys.argv[1:]
    if flag in args:
        i = args.index(flag)
        if i + 1 >= len(args):
            sys.exit(f"{flag} 後面要接值")
        return args[i + 1]
    return None


def main():
    check = "--check" in sys.argv[1:]
    out = build(arg_value("--mirror-map") or DEFAULT_MIRROR_MAP)
    show = arg_value("--print")
    if show:
        hits = [c for p, c in out.items() if os.path.basename(p) == show]
        if len(hits) != 1:
            sys.exit(f"產生結果裡沒有 {show}")
        sys.stdout.buffer.write(hits[0].encode("utf-8"))
        return
    diff = []
    for path, content in out.items():
        old = read(path) if os.path.isfile(path) else None
        if old != content:
            diff.append(path)
            if not check:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(content)
    for path in stale(out):
        diff.append(path + "（多餘）")
        if not check:
            os.remove(path)
    rel = [os.path.relpath(p, REPO) for p in diff]
    if check:
        if rel:
            print("強化版產生結果和已提交的檔案不同（跑 uv run scripts/gen_reinforced.py 更新）：\n  " + "\n  ".join(rel))
            sys.exit(1)
        print(f"強化版：{len(sources())} 款，產生結果和已提交的檔案一致")
    else:
        print(f"強化版：{len(sources())} 款，更新 {len(rel)} 個檔案")


if __name__ == "__main__":
    main()
