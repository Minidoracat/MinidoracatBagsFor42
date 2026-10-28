# -*- coding: utf-8 -*-
"""產生強化版背包：物品腳本、ClothingItem XML、fileGuidTable、16 語名稱（物品與液體容器）、配方清單、Lua 的主題來源表。

用法（repo 根目錄）：
    uv run scripts/gen_reinforced.py                     寫入
    uv run scripts/gen_reinforced.py --check             只比對，已提交的檔案和產生結果不同就列出並回 1（遊戲更新後重核用）
    uv run scripts/gen_reinforced.py --mirror-map PATH   側背包鏡像對照檔改用 PATH（預設 scripts/satchel_mirror_map.json）
    uv run scripts/gen_reinforced.py --print NAME        只印出檔名為 NAME 的產生結果，不寫檔（測試用）

兩種強化版：
- 主題強化版（原版 80 種來源）：照 scripts/theme_shapes.json（ThemeDesign 的清單檔，格式見檔內 version 1），同網格的來源併成
  一種形狀，每種做 MinidoracatBags.<代表款>_<Navy|Olive>_Reinforced 兩件（使用者 2026-10-27）。
  - 欄位照代表款的腳本逐行抄；Capacity、WeightReduction、液體 Capacity 取同組最高的（中間各階不比合併前低）；
    DisplayCategory = Bag；Icon 照清單檔、拿掉 IconsForTexture；WorldStaticModel 照清單檔的 ground（null 就照代表款）；
    手持模型改用自己的 ClothingItem MDB_<代表款>_<主題>_Reinforced_RHand／_LHand。
  - ClothingItem XML 照代表款，貼圖換成清單檔那一張（textureChoices 只留一個），手持的也是。
  - 名稱＝主題詞照本 MOD 7 款的寫法與語序（THEME_WORDS）＋代表款的原版名稱＋強化標記。
  - MDB_Upgrade.lua 的 MDB.THEME_SOURCES（BEGIN／END 之間）照清單檔的 theme_by_source 產生：升級時照包的顏色選主題；
    原版換穿法的另一面記成 pair，換穿過前後的腰包還原時用。
- 本 MOD 的 18 件：來源表是 MDB_Upgrade.lua 的 MDB.REINFORCED_SOURCES，一款一件 MinidoracatBags.<名稱>_Reinforced，
  欄位照來源（圖示、地面模型、手持模型、放入限制都照抄）。
兩種都改這些：
  - Weight 0.1（沒寫就補在 ItemType 後面；引擎預設是 1.0，Item.java:83）、RunSpeedModifier 1.0（同樣沒寫就補）。
  - CombatSpeedModifier 不是 1 的改成 1.0（使用者 2026-10-26：戰鬥也不減速）；沒寫就不加，引擎預設 1.0（Item.java:374）。
    穿著的背包照腳本值算進人物的戰鬥速度（IsoGameCharacter.java:9868-9869）。
  - ClothingItem 改用自己的名稱（MDB_<物品名>）；名稱是全域對照，不能沿用來源名稱（ScriptManager.java:1883-1891）。
    XML 換 GUID（uuid5，重跑結果不變）。
  - ClothingItemExtra（換穿法）：指向目標的強化版（主題強化版指同主題）；目標沒有強化版就停下來。
  - CanBeEquipped／BodyLocation 是 base:satchel 的改成第二個側背包位置（SATCHEL2，registries.lua 註冊）；
    XML 另照鏡像對照檔改寫男女模型路徑（檔案不存在就照原路徑）：格式 { "<XML 的 m_MaleModel／m_FemaleModel 原字串>":
    "<鏡像模型路徑，同樣寫法>" }，每個鍵都要用得到、值要找得到檔案。
  - 液體元件的 ContainerName 改成自己的 ClothingItem 名稱：有液體容器的物品，物品欄、提示框與液體面板顯示的是
    Fluid_Container_<ContainerName>，不是 ItemName（InventoryItem.java:2436-2437、FluidContainer.java:398-404、
    ISFluidContainerPanel.lua:146-149），裝水時顯示「液體(容器名稱)」，所以 Fluids.json 的容器名稱不帶括號標記，
    把強化寫進名詞片語（FLUID_MARK）。
繁中的原版名稱照 LangFor42，本 MOD 的照自己的翻譯。簡中名稱要原版字型畫得出來。
MDB_Reinforced.txt 另有還原、「已升級背包改成強化版」、換主題三條配方；MDB_Recipes.txt 三條升級配方的背包清單補上強化版。
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
SHAPES = os.path.join(REPO, "scripts", "theme_shapes.json")
THEMES = ("Navy", "Olive")
HANDS = (("ReplaceInPrimaryHand", "_RHand"), ("ReplaceInSecondHand", "_LHand"))

# 強化標記：照本 MOD 升級配方名稱用的詞（Recipes.json 的 MDB_UpgradeBagTier*）；
# 名詞有陰陽性的語言用「強化版」名詞片語，不必配合每個背包名稱的性別
MARK = {
    "AR": " (versión reforzada)", "CH": "（強化）", "CN": "（强化）", "DE": " (verstärkt)", "EN": " (Reinforced)",
    "ES": " (versión reforzada)", "ES_CL": " (versión reforzada)", "ES_MX": " (versión reforzada)",
    "FR": " (version renforcée)", "JP": "（強化）", "KO": " (강화)", "PL": " (wersja wzmocniona)",
    "PT": " (Versão Reforçada)", "PTBR": " (Versão Reforçada)", "RU": " (укреплённая версия)", "TR": " (Güçlendirilmiş)",
}
# 液體容器名稱的強化寫法：裝水時顯示「水(容器名稱)」，名稱再帶括號標記會變成兩層括號，所以把強化寫進名詞片語
# （使用者 2026-10-27 選定）。{n}＝名稱，{l}＝名稱首字改小寫。形容詞照「水袋背包」在各語的性別寫
# （德、波、俄、法、葡（PT）陽性；西、葡（PTBR）陰性），所以只適用 FLUID_SHAPES；出現新的液體容器形狀就停下來補。
FLUID_SHAPES = ("Bag_HydrationBackpack",)
FLUID_MARK = {
    "AR": "{n} reforzada", "CH": "強化{n}", "CN": "强化{n}", "DE": "Verstärkter {n}", "EN": "Reinforced {n}",
    "ES": "{n} reforzada", "ES_CL": "{n} Reforzada", "ES_MX": "{n} reforzada",
    "FR": "{n} renforcé", "JP": "強化{n}", "KO": "강화 {n}", "PL": "Wzmocniony {l}",
    "PT": "{n} Reforçado", "PTBR": "{n} Reforçada", "RU": "Укреплённый {l}", "TR": "Güçlendirilmiş {n}",
}
# 主題詞與語序，照本 MOD 7 款的譯名（例：EN「Umbrella Day Pack」、ES「Mochila de día Umbrella」）；True＝放在名稱前面。
# build() 會核對本 MOD 14 件的譯名都照這張表，對不上就停。液體容器名稱：前置的語言放在整個容器名稱前面，
# 後置的語言放在背包名稱後面、強化詞照舊（例：「Mochila de hidratación S.T.A.R.S. reforzada」）
UMBRELLA = "Umbrella"
THEME_WORDS = {
    "AR": (False, UMBRELLA), "CH": (True, "保護傘"), "CN": (True, "保护伞"), "DE": (True, UMBRELLA), "EN": (True, UMBRELLA),
    "ES": (False, UMBRELLA), "ES_CL": (False, UMBRELLA), "ES_MX": (False, UMBRELLA), "FR": (False, UMBRELLA),
    "JP": (True, "アンブレラ"), "KO": (True, "엄브렐라"), "PL": (False, UMBRELLA), "PT": (False, UMBRELLA),
    "PTBR": (False, UMBRELLA), "RU": (False, "«Амбрелла»"), "TR": (True, UMBRELLA),
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
UPGRADE_LUA = os.path.join(MEDIA, "lua", "shared", "MDB_Upgrade.lua")
LUA_BEGIN = "-- BEGIN gen_reinforced.py"
LUA_END = "-- END gen_reinforced.py"
OWN_XML = re.compile(r"^MDB_\w+" + SUFFIX + r"(_[RL]Hand)?\.xml$")


def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return f.read().replace("\r\n", "\n")


def sources():
    """本 MOD 的強化版來源（MDB.REINFORCED_SOURCES）"""
    body = re.search(r"MDB\.REINFORCED_SOURCES\s*=\s*(\{.*?\})", read(UPGRADE_LUA), re.S)
    if not body:
        sys.exit("MDB_Upgrade.lua 找不到 MDB.REINFORCED_SOURCES")
    src = re.findall(r'"([\w]+\.[\w]+)"', body.group(1))
    if len(set(src)) != len(src) or any(not s.startswith(MODULE + ".") for s in src):
        sys.exit("MDB.REINFORCED_SOURCES 有重複，或不是本 MOD 的背包（原版來源在 scripts/theme_shapes.json）")
    return src


def reinforced(full):
    return f"{MODULE}.{full.split('.', 1)[1]}{SUFFIX}"


def themed(shape, theme):
    return f"{MODULE}.{shape}_{theme}{SUFFIX}"


def own_name(full):
    """強化版自己的 ClothingItem 名稱，也是液體容器名稱"""
    return f"MDB_{full.split('.', 1)[1]}"


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


def fluid_capacity(block):
    """FluidContainer 元件的 Capacity 字串（第一層以下只有它寫 Capacity），沒有就 None"""
    depth = 0
    for line in block:
        m = re.match(r"^\s*Capacity\s*=\s*([\d.]+),\s*$", line)
        if depth == 2 and m:
            return m.group(1)
        depth += line.count("{") - line.count("}")
    return None


def item_text(full, new_name, ci, block, extra, override=None, drop=(), fluid_cap=None):
    """抄來源欄位，只改說明列出的幾項。extra(目標全名) → 目標的強化版（沒有就 None）；override 的欄位整個換值，
    來源沒寫就補；drop 的欄位拿掉。Weight、RunSpeedModifier 沒寫就補，寫兩次以上或沒有 ClothingItem 就停"""
    module = full.split(".", 1)[0]
    override = dict(override or {})
    seen = {"Weight": 0, "RunSpeedModifier": 0, "ClothingItem": 0}
    out, depth, item_type_at, indent = [], 0, None, "        "
    for line in block:
        m = re.match(r"^(\s*)(\w+)(\s*=\s*)(.*?),\s*$", line)
        if depth == 1 and m:
            ind, key, eq, val = m.groups()
            indent = ind
            if key in drop:
                continue
            if key in override:
                val = override.pop(key)
            elif key == "Weight":
                val = "0.1"
            elif key == "RunSpeedModifier":
                val = "1.0"
            elif key == "CombatSpeedModifier" and float(val) != 1.0:
                val = "1.0"
            elif key == "ClothingItem":
                val = ci
            elif key == "ClothingItemExtra":
                extras = []
                for e in val.split(";"):
                    e = e if "." in e else f"{module}.{e}"
                    if not extra(e):
                        sys.exit(f"{full}: ClothingItemExtra {e} 沒有強化版，強化版換穿後會變回非強化版；先讓它有強化版")
                    extras.append(extra(e))
                val = ";".join(extras)
            elif key in ("CanBeEquipped", "BodyLocation") and val.lower() == SATCHEL:
                val = SATCHEL2
            if key in seen:
                seen[key] += 1
            line = f"{ind}{key}{eq}{val},"
            if key == "ItemType":
                item_type_at = len(out)
        elif depth == 2 and m and m.group(2) == "ContainerName":
            line = f"{m.group(1)}ContainerName{m.group(3)}{ci},"
        elif depth == 2 and m and m.group(2) == "Capacity" and fluid_cap:
            line = f"{m.group(1)}Capacity{m.group(3)}{fluid_cap},"
        elif depth == 0 and re.match(r"^\s*item\s+\w+\s*$", line):
            line = re.sub(r"item\s+\w+", f"item {new_name}", line)
        depth += line.count("{") - line.count("}")
        out.append(line)
    bad = [k for k, n in seen.items() if n > 1 or (k == "ClothingItem" and n == 0)]
    if bad or item_type_at is None:
        sys.exit(f"{full}: 欄位 {bad or ['ItemType']} 數量不對，腳本格式變了，先看來源再改產生器")
    add = [(k, v) for k, v in override.items()] + [(k, v) for k, v in (("RunSpeedModifier", "1.0"), ("Weight", "0.1"))
                                                    if seen[k] == 0]
    for key, val in reversed(add):
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


def source_xml(full, ci):
    p = os.path.join(MOD_CLOTHING if full.startswith(MODULE + ".") else PZ_CLOTHING, f"{ci}.xml")
    if not os.path.isfile(p):
        sys.exit(f"{full}: 找不到 ClothingItem {p}")
    return p, read(p)


def texture_choices(xml):
    return re.findall(r"<textureChoices>([^<]*)</textureChoices>", xml)


def clothing_xml(name, p, xml, satchel, mirror, used, texture=None):
    """照來源 XML 換 GUID；satchel 照鏡像對照檔換男女模型；texture 不是 None 時貼圖換成只有這一張"""
    guid = str(uuid.uuid5(GUID_NS, name))
    xml, n = re.subn(r"<m_GUID>[^<]*</m_GUID>", f"<m_GUID>{guid}</m_GUID>", xml)
    if n != 1:
        sys.exit(f"{p}: m_GUID 不是剛好一個")
    if satchel:
        def swap(m):
            if m.group(2) in mirror:
                used.add(m.group(2))
                return f"<{m.group(1)}>{mirror[m.group(2)]}</{m.group(1)}>"
            return m.group(0)
        xml = re.sub(r"<(m_MaleModel|m_FemaleModel)>([^<]*)</\1>", swap, xml)
    if texture is not None:
        # 主題貼圖是換過色的整張，不能再隨機染色或疊原版的貼花；原版代表款都沒有，出現了先看再決定
        if re.search(r"<m_AllowRandom(Tint|Hue)>\s*true|<m_DecalGroup>\s*\S|<m_BaseTextures>", xml, re.I):
            sys.exit(f"{p}: 有隨機染色、貼花或 m_BaseTextures，主題貼圖的換法要另外想")
        tex, first = texture.replace("/", "\\"), [True]

        def one(m):
            keep, first[0] = first[0], False
            return f"{m.group(1)}<textureChoices>{tex}</textureChoices>\n" if keep else ""
        xml, n = re.subn(r"([ \t]*)<textureChoices>[^<]*</textureChoices>\n", one, xml)
        if n == 0:
            sys.exit(f"{p}: 沒有 textureChoices")
    return guid, xml


def recipe(name, bags, extras, hooks):
    lines = [f"    craftRecipe {name}", "    {", "        timedAction = SewingCloth,", "        time = 100,",
             "        AllowBatchCraft = false,", "        Tags = AnySurfaceCraft,", "        category = Tailoring,"]
    lines += [f"        {k} = {v}," for k, v in hooks]
    lines += ["        inputs", "        {", f"            item 1 [{';'.join(bags)}] mode:keep flags[IsNotWorn],"]
    lines += [f"            {e}," for e in extras]
    lines += ["        }", "        outputs", "        {", "        }", "    }"]
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


def theme_word(lang, theme):
    return "S.T.A.R.S." if theme == "Navy" else THEME_WORDS[lang][1]


def with_theme(lang, theme, name):
    w = theme_word(lang, theme)
    return f"{w} {name}" if THEME_WORDS[lang][0] else f"{name} {w}"


def fluid_name(lang, theme, name):
    if THEME_WORDS[lang][0]:
        return f"{theme_word(lang, theme)} " + FLUID_MARK[lang].format(n=name, l=name[:1].lower() + name[1:])
    n = with_theme(lang, theme, name)
    return FLUID_MARK[lang].format(n=n, l=n[:1].lower() + n[1:])


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


def mod_models():
    """本 MOD scripts/*.txt 的 model 全名"""
    out = set()
    sdir = os.path.join(MEDIA, "scripts")
    for f in sorted(os.listdir(sdir)):
        if f.endswith(".txt"):
            text = re.sub(r"/\*.*?\*/", "", read(os.path.join(sdir, f)), flags=re.S)
            for mod, body in re.findall(r"module\s+(\w+)\s*\{(.*)", text, re.S):
                out |= {f"{mod}.{n}" for n in re.findall(r"^\s*model\s+(\w+)\s*$", body, re.M)}
    return out


def load_shapes(blocks, upgrade_vanilla):
    """讀清單檔並核對：成員剛好是升級清單的原版背包、各一次；每個來源的主題數＝它 XML 的 textureChoices 數（沒有就 1）；
    貼圖、圖示、地面模型都存在"""
    data = json.loads(read(SHAPES))
    if data.get("version") != 1:
        sys.exit(f"{SHAPES}: version 要是 1（格式改了先和 ThemeDesign 對過）")
    shapes, members, models = data["shapes"], [], mod_models()
    for s in shapes:
        if s["representative"] != f"Base.{s['key']}" or s["representative"] not in s["members"]:
            sys.exit(f"{s['key']}: key 要是代表款去掉 Base.，代表款要是成員")
        members += s["members"]
        for t in THEMES:
            missing = [p for p in (os.path.join(MEDIA, "textures", s["texture"][t] + ".png"),
                                   os.path.join(MEDIA, "textures", f"Item_{s['icon'][t]}.png")) if not os.path.isfile(p)]
            if s["ground"][t] and s["ground"][t] not in models:
                missing.append(s["ground"][t])
            if missing:
                sys.exit(f"{s['key']} {t}: 找不到 {missing}")
    if len(set(members)) != len(members) or set(members) != upgrade_vanilla:
        sys.exit(f"{SHAPES}: 成員要剛好是升級清單的原版背包、各一次（多 {sorted(set(members) - upgrade_vanilla)}，"
                 f"少 {sorted(upgrade_vanilla - set(members))}）")
    by_source = data["theme_by_source"]
    if set(by_source) != set(members):
        sys.exit(f"{SHAPES}: theme_by_source 的來源和成員不同")
    for src, themes in by_source.items():
        ci = top_fields(blocks[src])["ClothingItem"]
        want = max(1, len(texture_choices(source_xml(src, ci)[1])))
        if len(themes) != want or any(t not in THEMES for t in themes):
            sys.exit(f"{src}: theme_by_source 要有 {want} 個（textureChoices 數），值是 {THEMES}，現在 {themes}")
    return shapes, by_source


def build(mirror_path):
    own = sources()
    blocks = item_blocks()
    for s in own:
        if s not in blocks:
            sys.exit(f"找不到來源物品 {s}")
    recipes_text = read(RECIPES)
    m = re.search(r"craftRecipe MDB_UpgradeBagTier1\b.*?item 1 \[([^\]]+)\]", recipes_text, re.S)
    upgrade_vanilla = {b for b in m.group(1).split(";") if b.startswith("Base.")} if m else set()
    shapes, by_source = load_shapes(blocks, upgrade_vanilla)
    shape_of = {mem: s["key"] for s in shapes for mem in s["members"]}
    mirror, used = load_mirror_map(mirror_path), set()
    out, items, guids = {}, [], []
    fluid_shapes, themed_ids, names = [], [], []   # names：(強化版全名, 取名稱的來源, 主題或 None)

    for s in shapes:
        rep = s["representative"]
        block = [blocks[m] for m in s["members"]]
        f = top_fields(blocks[rep])
        cap = max(int(top_fields(b)["Capacity"]) for b in block)
        wr = max(int(top_fields(b)["WeightReduction"]) for b in block)
        fluids = [fluid_capacity(b) for b in block]
        if any(fluids) and not all(fluids):
            sys.exit(f"{s['key']}: 同組有的有液體容器、有的沒有，先看來源再決定")
        fluid = max(fluids, key=float) if all(fluids) else None
        if fluid:
            fluid_shapes.append(s["key"])
        satchel = f.get("CanBeEquipped", "").lower() == SATCHEL
        for t in THEMES:
            full = themed(s["key"], t)
            ci = own_name(full)
            override = {"Capacity": str(cap), "WeightReduction": str(wr), "DisplayCategory": "Bag", "Icon": s["icon"][t]}
            if s["ground"][t]:
                override["WorldStaticModel"] = s["ground"][t]
            for key, tail in HANDS:
                if key in f:
                    hand = f[key].split()
                    override[key] = " ".join([ci + tail] + hand[1:])
                    p, xml = source_xml(rep, hand[0])
                    hg, hx = clothing_xml(ci + tail, p, xml, False, mirror, used, s["texture"][t])
                    out[os.path.join(MOD_CLOTHING, ci + tail + ".xml")] = hx
                    guids.append((ci + tail, hg))
            items.append(item_text(rep, full.split(".", 1)[1], ci, blocks[rep],
                                   lambda e, t=t: shape_of.get(e) and themed(shape_of[e], t),
                                   override, ("IconsForTexture",), fluid))
            p, xml = source_xml(rep, f["ClothingItem"])
            g, x = clothing_xml(ci, p, xml, satchel, mirror, used, s["texture"][t])
            out[os.path.join(MOD_CLOTHING, ci + ".xml")] = x
            guids.append((ci, g))
            themed_ids.append(full)
            names.append((full, rep, t))
    own_ids = [reinforced(s) for s in own]
    for s, full in zip(own, own_ids):
        ci = own_name(full)
        items.append(item_text(s, full.split(".", 1)[1], ci, blocks[s], lambda e: e in own and reinforced(e)))
        if f"ContainerName = {ci}," in items[-1]:
            sys.exit(f"{s}: 本 MOD 的背包有液體容器，FLUID_MARK 只適用 {FLUID_SHAPES}")
        satchel = top_fields(blocks[s]).get("CanBeEquipped", "").lower() == SATCHEL
        p, xml = source_xml(s, top_fields(blocks[s])["ClothingItem"])
        g, x = clothing_xml(ci, p, xml, satchel, mirror, used)
        out[os.path.join(MOD_CLOTHING, ci + ".xml")] = x
        guids.append((ci, g))
        names.append((full, s, None))
    if tuple(fluid_shapes) != FLUID_SHAPES:
        sys.exit(f"有液體容器的形狀 {fluid_shapes} 和 FLUID_SHAPES 不同：先查新形狀在各語的名詞性別，再改 FLUID_MARK")
    if set(mirror) - used:
        sys.exit(f"{mirror_path}: 這些鍵不是任何強化版側背包 XML 的男女模型路徑：{sorted(set(mirror) - used)}")
    vanilla_guids = set(g.lower() for g in re.findall(r"<guid>\s*([\w-]+)\s*</guid>", read(os.path.join(PZ, "fileGuidTable.xml"))))
    if any(g in vanilla_guids for _, g in guids) or len({g for _, g in guids}) != len(guids):
        sys.exit("GUID 和原版重複或彼此重複")

    rein = themed_ids + own_ids
    vanilla = sorted(upgrade_vanilla)
    out[OUT_SCRIPT] = "\n".join([
        "/* 由 scripts/gen_reinforced.py 產生，不要手改；來源是 scripts/theme_shapes.json（原版 80 種併成的 22 種形狀 × 2 主題）",
        "   與 MDB_Upgrade.lua 的 MDB.REINFORCED_SOURCES（本 MOD 18 件）。",
        "   強化版：欄位照代表款或來源，自重 0.1、不減速、自己的 ClothingItem、側背包穿第二個側背包位置；",
        "   容量、負重減輕、液體由 MDB.applyTier 依階級升。",
        "   不放進戰利品與殭屍掉落；只從升級、舊 Plus 改裝、布吊帶包直接製作取得。",
        "   還原：強化版改回升級前的原款（沒有紀錄就是代表款），階級、內容物照舊（MDB.onSwapKeepTier）。",
        "   已升級背包改成強化版：給 0.1.0 升過級的背包，只換型、階級照舊（OnTest 只放行第 1 階以上）。",
        "   換主題：主題強化版 S.T.A.R.S.／保護傘互換，階級、內容物、液體、改過的名字照舊（MDB.onSwapTheme）。 */",
        "module MinidoracatBags", "{", "    imports", "    {", "        Base", "    }", "",
        "\n\n".join(items), "",
        recipe("MDB_RestoreReinforced", rein, ["item 1 tags[base:scissors] mode:keep flags[IsNotDull;MayDegradeLight]"],
               [("Tooltip", "Tooltip_MDB_RestoreReinforced"), ("OnCreate", "MDB.onSwapKeepTier")]), "",
        recipe("MDB_ReinforceUpgradedBag", vanilla + own, ["item 1 tags[base:sewingneedle] mode:keep"],
               [("OnTest", "MDB.onTestUpgraded"), ("OnCreate", "MDB.onSwapKeepTier")]), "",
        recipe("MDB_SwapReinforcedTheme", themed_ids, ["item 1 tags[base:sewingneedle] mode:keep", "item 1 tags[base:thread]"],
               [("OnCreate", "MDB.onSwapTheme")]),
        "}", ""])

    # 升級配方的背包清單：保留手寫的部分，強化版照表重排在最後
    def fix(mm):
        keep = [b for b in mm.group(2).split(";") if not (b.startswith(MODULE + ".") and b.endswith(SUFFIX))]
        return mm.group(1) + ";".join(keep + rein) + mm.group(3)
    text, n = re.subn(r"(item 1 \[)([^\]]*)(\] mode:keep flags\[IsNotWorn\])", fix, recipes_text)
    if n != 3:
        sys.exit(f"MDB_Recipes.txt 升級配方背包行應有 3 條，找到 {n}")
    out[RECIPES] = text

    # Lua 的主題來源表；pair＝原版換穿法（ClothingItemExtra）的另一面：換穿過前後的腰包還原成原款在那一面的版本，
    # 記下的顏色照用，所以兩面的顏色清單要相同
    def textures(src):
        return texture_choices(source_xml(src, top_fields(blocks[src])["ClothingItem"])[1])
    pair = {}
    for src in by_source:
        x = top_fields(blocks[src]).get("ClothingItemExtra")
        if not x:
            continue
        p = x if "." in x else f"Base.{x}"
        if ";" in x or p not in by_source or shape_of[p] == shape_of[src] or textures(p) != textures(src):
            sys.exit(f"{src}: ClothingItemExtra {x} 要剛好一個、是另一種形狀的成員、顏色清單相同，還原才換得回原款")
        pair[src] = p
    lua = read(UPGRADE_LUA)
    rows = "".join(f'    ["{src}"] = {{ shape = "{shape_of[src]}", themes = {{ {", ".join(chr(34) + t + chr(34) for t in by_source[src])} }}'
                   + (f', pair = "{pair[src]}"' if src in pair else "") + " },\n"
                   for src in sorted(by_source))
    lua, n = re.subn(r"(" + re.escape(LUA_BEGIN) + r"[^\n]*\n)MDB\.THEME_SOURCES = \{\n.*?\}\n(" + re.escape(LUA_END) + ")",
                     lambda mm: mm.group(1) + "MDB.THEME_SOURCES = {\n" + rows + "}\n" + mm.group(2), lua, flags=re.S)
    if n != 1:
        sys.exit(f"MDB_Upgrade.lua 找不到 {LUA_BEGIN}／{LUA_END} 之間的 MDB.THEME_SOURCES")
    out[UPGRADE_LUA] = lua

    gt = re.sub(r"\t<files>\n\t\t<path>media/clothing/clothingItems/MDB_\w+" + SUFFIX + r"(?:_[RL]Hand)?\.xml</path>\n"
                r"\t\t<guid>[\w-]+</guid>\n\t</files>\n", "", read(GUIDTABLE))
    add = "".join(f"\t<files>\n\t\t<path>media/clothing/clothingItems/{n}.xml</path>\n\t\t<guid>{g}</guid>\n\t</files>\n"
                  for n, g in guids)
    out[GUIDTABLE] = gt.replace("</fileGuidTable>", add + "</fileGuidTable>")

    # 名稱。主題詞照本 MOD 的譯名：14 件原款在每個語言都要照 THEME_WORDS 的詞與語序
    glyphs, cn_bad = cn_glyphs(), []
    # 主題詞照本 MOD 原款的譯名沿用（「保护伞」原版字型本來就缺字，原款一樣），不在這裡擋
    if any(ord(c) not in glyphs for c in MARK["CN"] + FLUID_MARK["CN"].replace("{n}", "")):
        sys.exit(f"簡中強化標記 {MARK['CN']}／{FLUID_MARK['CN']} 有原版字型畫不出來的字")
    for lang in LANGS:
        for s in own:
            if s.endswith(SUFFIX) or not re.search(r"_(Navy|Olive)$", s):
                continue
            n, w = names_for(s, lang), theme_word(lang, s.rsplit("_", 1)[1])
            if not (n.startswith(w + " ") if THEME_WORDS[lang][0] else n.endswith(" " + w)):
                sys.exit(f"{lang} {s}「{n}」的主題詞和 THEME_WORDS 不同")
        p = os.path.join(TRANSLATE, lang, "ItemName.json")
        d = {k: v for k, v in json.loads(read(p)).items() if not (k.startswith(MODULE + ".") and k.endswith(SUFFIX))}
        for full, src, theme in names:
            base = names_for(src, lang)
            d[full] = (with_theme(lang, theme, base) if theme else base) + MARK[lang]
            if lang == "CN" and any(c in d[full] for c in CN_AVOID):
                cn_bad.append(f"{full}：{d[full]}")
        out[p] = json.dumps(d, ensure_ascii=False, indent=4) + "\n"
        # 液體容器名稱（Translator.java:159 依檔名 Fluids 分表，getFluidText 查 Fluid_ 開頭的鍵，:871-874）
        fp = os.path.join(TRANSLATE, lang, "Fluids.json")
        fd = json.loads(read(fp)) if os.path.isfile(fp) else {}
        fd = {k: v for k, v in fd.items() if not (k.startswith("Fluid_Container_MDB_") and k.endswith(SUFFIX))}
        for key in fluid_shapes:
            for t in THEMES:
                k = f"Fluid_Container_{own_name(themed(key, t))}"
                fd[k] = fluid_name(lang, t, names_for(f"Base.{key}", lang))
                if lang == "CN" and any(c in fd[k] for c in CN_AVOID):
                    cn_bad.append(f"{k}：{fd[k]}")
        out[fp] = json.dumps(fd, ensure_ascii=False, indent=4) + "\n"
    if cn_bad:
        sys.exit(f"簡中名稱有已知缺字 {CN_AVOID}：\n  " + "\n  ".join(cn_bad))
    return out


def stale(out):
    """磁碟上有、但這次沒產生的強化版 XML"""
    return [os.path.join(MOD_CLOTHING, f) for f in os.listdir(MOD_CLOTHING)
            if OWN_XML.match(f) and os.path.join(MOD_CLOTHING, f) not in out]


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
    count = len(re.findall(r"^    item \w+$", out[OUT_SCRIPT], re.M))
    if check:
        if rel:
            print("強化版產生結果和已提交的檔案不同（跑 uv run scripts/gen_reinforced.py 更新）：\n  " + "\n  ".join(rel))
            sys.exit(1)
        print(f"強化版：{count} 件，產生結果和已提交的檔案一致")
    else:
        print(f"強化版：{count} 件，更新 {len(rel)} 個檔案")


if __name__ == "__main__":
    main()
