# -*- coding: utf-8 -*-
"""產生強化版背包：物品腳本、ClothingItem XML、fileGuidTable、16 語名稱（物品與液體容器）、配方清單。

用法（repo 根目錄）：
    uv run scripts/gen_reinforced.py           寫入
    uv run scripts/gen_reinforced.py --check   只比對，已提交的檔案和產生結果不同就列出並回 1（遊戲更新後重核用）

來源表是 MDB_Upgrade.lua 的 MDB.REINFORCED_SOURCES（Lua 也用同一張表），要加款式只加那張表再跑本腳本。
每個來源 <模組>.<名稱> 產生 MinidoracatBags.<名稱>_Reinforced：
- 欄位照來源的腳本逐行抄，只改 Weight 0.1、RunSpeedModifier 1.0、ClothingItem（改用自己的名稱）、
  ClothingItemExtra（指向對方的強化版完整 ID），以及液體元件的 ContainerName（MDB_<名稱>_Reinforced）：
  有液體容器的物品，物品欄、提示框與液體面板顯示的是 Fluid_Container_<ContainerName>，不是 ItemName
  （InventoryItem.java:2436-2437、FluidContainer.java:398-404、ISFluidContainerPanel.lua:146-149），
  所以 Fluids.json 另給它和 ItemName 相同的強化版名稱。
- ClothingItem MDB_<名稱>_Reinforced：XML 照來源的 XML，只換 GUID（uuid5，重跑結果不變）；
  名稱是全域對照，不能沿用原版名稱（ScriptManager.java:1883-1891）。
- 名稱＝各語言的來源名稱＋強化標記；繁中的原版名稱照 LangFor42。
- MDB_Reinforced.txt 另有還原與「已升級原版背包改成強化版」兩條配方；MDB_Recipes.txt 三條升級配方的背包清單補上強化版。
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

# 強化標記：照本 MOD 升級配方名稱用的詞（Recipes.json 的 MDB_UpgradeBagTier*）；
# 名詞有陰陽性的語言用「強化版」名詞片語，不必配合每個背包名稱的性別
MARK = {
    "AR": " (versión reforzada)", "CH": "（強化）", "CN": "（强化）", "DE": " (verstärkt)", "EN": " (Reinforced)",
    "ES": " (versión reforzada)", "ES_CL": " (versión reforzada)", "ES_MX": " (versión reforzada)",
    "FR": " (version renforcée)", "JP": "（強化）", "KO": " (강화)", "PL": " (wersja wzmocniona)",
    "PT": " (Versão Reforçada)", "PTBR": " (Versão Reforçada)", "RU": " (укреплённая версия)", "TR": " (Güçlendirilmiş)",
}
LANGS = sorted(MARK)
CN_MISSING = "刚满这该顶数时级"   # 原版簡中字型缺字

ITEM_SCRIPTS = [os.path.join(PZ, "scripts", "generated", "items"), os.path.join(MEDIA, "scripts", "MDB_Items.txt")]
CLOTHING_DIRS = [os.path.join(MEDIA, "clothing", "clothingItems"), os.path.join(PZ, "clothing", "clothingItems")]
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
    return re.findall(r'"([\w]+\.[\w]+)"', body.group(1))


def reinforced(full):
    return f"{MODULE}.{full.split('.', 1)[1]}{SUFFIX}"


def fluid_name(full):
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


def item_text(full, block, mapping):
    """抄來源欄位，只改四個第一層欄位與液體元件的 ContainerName；第一層欄位各要剛好一個"""
    name = full.split(".", 1)[1]
    seen = {"Weight": 0, "RunSpeedModifier": 0, "ClothingItem": 0}
    out, depth = [], 0
    for line in block:
        m = re.match(r"^(\s*)(\w+)(\s*=\s*)(.*?),\s*$", line)
        if depth == 1 and m:
            ind, key, eq, val = m.groups()
            if key == "Weight":
                val = "0.1"
            elif key == "RunSpeedModifier":
                val = "1.0"
            elif key == "ClothingItem":
                val = f"MDB_{name}{SUFFIX}"
            elif key == "ClothingItemExtra":
                extras = []
                for e in val.split(";"):
                    if e not in mapping:
                        sys.exit(f"{full}: ClothingItemExtra {e} 沒有強化版，先把它加進 MDB.REINFORCED_SOURCES")
                    extras.append(mapping[e])
                val = ";".join(extras)
            if key in seen:
                seen[key] += 1
            line = f"{ind}{key}{eq}{val},"
        elif depth == 2 and m and m.group(2) == "ContainerName":
            # 液體容器的物品顯示名稱取 Fluid_Container_<ContainerName>（FluidContainer.java:398-404），不用 ItemName
            line = f"{m.group(1)}ContainerName{m.group(3)}{fluid_name(full)},"
        elif depth == 0 and re.match(r"^\s*item\s+\w+\s*$", line):
            line = re.sub(r"item\s+\w+", f"item {name}{SUFFIX}", line)
        depth += line.count("{") - line.count("}")
        out.append(line)
    bad = [k for k, n in seen.items() if n != 1]
    if bad:
        sys.exit(f"{full}: 欄位 {bad} 不是剛好一個，腳本格式變了，先看原版再改產生器")
    return "\n".join(out)


def clothing_xml(full, block):
    src = next(re.match(r"^\s*ClothingItem\s*=\s*(\w+)", l).group(1) for l in block if re.match(r"^\s*ClothingItem\s*=", l))
    for d in CLOTHING_DIRS:
        p = os.path.join(d, src + ".xml")
        if os.path.isfile(p):
            name = f"MDB_{full.split('.', 1)[1]}{SUFFIX}"
            guid = str(uuid.uuid5(GUID_NS, name))
            xml, n = re.subn(r"<m_GUID>[^<]*</m_GUID>", f"<m_GUID>{guid}</m_GUID>", read(p))
            if n != 1:
                sys.exit(f"{p}: m_GUID 不是剛好一個")
            return name, guid, xml
    sys.exit(f"{full}: 找不到 ClothingItem {src}.xml")


def recipe(name, bags, extra, hooks):
    lines = [f"    craftRecipe {name}", "    {", "        timedAction = SewingCloth,", "        time = 100,",
             "        AllowBatchCraft = false,", "        Tags = AnySurfaceCraft,", "        category = Tailoring,"]
    lines += [f"        {k} = {v}," for k, v in hooks]
    lines += ["        inputs", "        {", f"            item 1 [{';'.join(bags)}] mode:keep flags[IsNotWorn],",
              f"            {extra},", "        }", "        outputs", "        {", "        }", "    }"]
    return "\n".join(lines)


def names_for(full, lang):
    files = [os.path.join(TRANSLATE, lang, "ItemName.json")]
    if full.startswith("Base."):
        files = ([os.path.join(LANGFOR42, "CH", "ItemName.json")] if lang == "CH" else []) + \
                [os.path.join(PZ, "lua", "shared", "Translate", lang, "ItemName.json")]
    for p in files:
        v = json.loads(read(p)).get(full) if os.path.isfile(p) else None
        if v:
            return v
    sys.exit(f"{lang}: 找不到 {full} 的名稱（{files}）")


def build():
    src = sources()
    mapping = {s: reinforced(s) for s in src}
    blocks = item_blocks()
    out = {}

    items, guids, fluid_sources = [], [], []
    for s in src:
        if s not in blocks:
            sys.exit(f"找不到來源物品 {s}")
        items.append(item_text(s, blocks[s], mapping))
        if f"ContainerName = {fluid_name(s)}," in items[-1]:
            fluid_sources.append(s)
        name, guid, xml = clothing_xml(s, blocks[s])
        out[os.path.join(CLOTHING_DIRS[0], name + ".xml")] = xml
        guids.append((name, guid))
    vanilla_guids = set(g.lower() for g in re.findall(r"<guid>\s*([\w-]+)\s*</guid>", read(os.path.join(PZ, "fileGuidTable.xml"))))
    if any(g in vanilla_guids for _, g in guids) or len({g for _, g in guids}) != len(guids):
        sys.exit("GUID 和原版重複或彼此重複")

    rein = [mapping[s] for s in src]
    out[OUT_SCRIPT] = "\n".join([
        "/* 由 scripts/gen_reinforced.py 產生，不要手改；來源表是 MDB_Upgrade.lua 的 MDB.REINFORCED_SOURCES。",
        "   強化版：欄位照原版，自重 0.1、不減速、自己的 ClothingItem；容量、負重減輕、液體由 MDB.applyTier 依階級升。",
        "   不放進戰利品與殭屍掉落；只從升級、舊 Plus 改裝、布吊帶包直接製作取得。",
        "   還原：強化版改回原版，階級、內容物、modData 照舊（MDB.onSwapKeepTier）。",
        "   已升級原版背包改成強化版：給 0.1.0 升過級的原版背包，只換型、階級照舊（OnTest 只放行第 1 階以上）。 */",
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

    for lang in LANGS:
        p = os.path.join(TRANSLATE, lang, "ItemName.json")
        d = {k: v for k, v in json.loads(read(p)).items() if not (k.startswith(MODULE + ".") and k.endswith(SUFFIX))}
        for s in src:
            d[mapping[s]] = names_for(s, lang) + MARK[lang]
            if lang == "CN" and any(c in d[mapping[s]] for c in CN_MISSING):
                sys.exit(f"CN {s} 名稱有原版字型缺的字：{d[mapping[s]]}")
        out[p] = json.dumps(d, ensure_ascii=False, indent=4) + "\n"
        # 液體容器名稱（Translator.java:159 依檔名 Fluids 分表，getFluidText 查 Fluid_ 開頭的鍵，:871-874）
        fp = os.path.join(TRANSLATE, lang, "Fluids.json")
        fd = json.loads(read(fp)) if os.path.isfile(fp) else {}
        fd = {k: v for k, v in fd.items() if not (k.startswith("Fluid_Container_MDB_") and k.endswith(SUFFIX))}
        for s in fluid_sources:
            fd[f"Fluid_Container_{fluid_name(s)}"] = d[mapping[s]]
        out[fp] = json.dumps(fd, ensure_ascii=False, indent=4) + "\n"
    return out


def stale(out):
    """磁碟上有、但這次沒產生的強化版 XML"""
    d = CLOTHING_DIRS[0]
    return [os.path.join(d, f) for f in os.listdir(d)
            if f.startswith("MDB_") and f.endswith(SUFFIX + ".xml") and os.path.join(d, f) not in out]


def main():
    check = "--check" in sys.argv[1:]
    out = build()
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
        print(f"強化版：{len(sources())} 款，更新 {len(rel)} 個檔案" + ("：\n  " + "\n  ".join(rel) if rel else ""))


if __name__ == "__main__":
    main()
