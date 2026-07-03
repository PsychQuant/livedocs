## Why

look-up 的 explicit-doc-lookup 契約把第一個 argument token 分成三形態（URL → Language → Package），有兩個 argument-space 缺口（PR #34 verify 實證）：

1. **語言固定集永久遮蔽同名套件**：`go`/`swift`/`r` 等 token 一律被分類成 Language，無法強制查同名的**套件**。現行 workaround 只有「改用 docs URL 或散文詢問」，笨拙且不 deterministic。
2. **第一 token 之外無 ecosystem 欄位**：named-only ecosystems（cran/crates/maven/go modules/…）完全依賴 calling agent 從裸 token 推斷生態系，無 escape hatch 讓使用者**明說**。

需要一個顯式、deterministic 的 ecosystem/shape hint，讓使用者主動指定生態系、繞過遮蔽。

## What Changes

- 新增 **`eco:name` 前綴 hint 語法**：`cran:dplyr`、`npm:go`、`crates:serde@1.0.100`。`<known-ecosystem>:` 前綴集合有限可枚舉，deterministic。
- **disambiguation 規則（三條件）**：在**第一個 `:`** 切一次，(a) 前綴 case-insensitively 等於某個 known ecosystem、(b) remainder 非空、(c) remainder 首字非 `/` → 判為 hint；任一不成立則整個 token（含冒號）落到 URL/Language/Package。條件 (c) 把 hint 與 URL scheme（`npm://x` 的 `:` 後接 `//`）分開；條件 (b) 讓裸 `npm:`/`cran:` 不算 hint。remainder **逐字**當套件名、不再重跑分類，故含冒號的 Maven coordinate（`maven:group:artifact`）保持完整。
- **precedence 插在 URL 之後、Language 之前**：hint 是使用者的顯式意圖，勝過 Language 固定集的遮蔽（`go:` 前綴的 `go` 走 Package/該生態系，而非 Language runtime introspect）。
- hint 與既有 version pin 正交組合：`crates:serde@1.0.100` → ecosystem crates + version 1.0.100（沿用既有 `name@version` 解析）。
- **同步更新既有 pin scenario 以對齊 #36 已出貨行為**：published spec 目前的 scenario「Version pin outside npm/pypi is surfaced as not applied」在 #36（crates/go/rubygems 已 honor pin、回 pin_honored）之後為**假**；本 change 的 MODIFIED Requirement 1 必須整段重寫，藉此把該 scenario 改為描述 pin_honored 誠實 surfacing（crates/go/rubygems honor；jsr/packagist/maven/cran latest-only），一併消除 #36 遺留的 spec drift（#36 為 Plan-tier、未帶 spec delta）。

## Ordering / dependency（跨 change 同 requirement 協調）

本 change **依賴** `add-r-runtime-adapter-and-js-alias`（issue #35）。**兩個 change 都對同一個 Requirement「Explicit invocation routes deterministically by argument shape」帶 MODIFIED delta**：#35 的版本是三形態（URL/Language/Package）+ R runtime 更新；本 change 的版本是四形態（加 ecosystem-hint）+ 相同的 R runtime 更新（撰寫時**已把 #35 的整段內容納入為基底**再疊加 hint）。本 change 的 delta **取代（supersede）** #35 的：它含 #35 的全部內容、**新增** ecosystem-hint 形態、**並反轉（invert）**那條在 #36 出貨後已成假的 pin scenario（「Version pin outside npm/pypi is surfaced as not applied」→「Version pin honesty is surfaced per ecosystem」）。因為含這個 scenario 反轉，本 delta 並非 #35 的純 add-only superset，而是「內容 superset + 一條 scenario 反轉」——如遇疑義，以本 change 為權威。

- **兩種順序要分開講**：(1) **git merge order** = #35 → #36 → #37（stacked branch 強制）；(2) **OpenSpec archive order** = #35 → #37。**#36 是 Plan-tier、無 spec delta，因此沒有 archive step**（它只是 merge/behavior 依賴，不參與 archive）——所以 archive 序只涉及 #35 與 #37 兩個 change。
- **風險**：Spectra 的 MODIFIED delta 在 archive 時**整段取代** requirement。若**逆序** archive（先 `/spectra-archive add-ecosystem-hint-syntax` 再 archive #35），#35 的三形態 delta 會把本 change 覆蓋、連帶還原 #36 已消的舊 pin scenario——grammar + pin 的**雙重回退**。正序（#35 先、#37 後）則最終為本 change 的四形態版本。
- **safeguard（放在會被讀到的地方）**：published-spec 的回退風險**無法**用「agent 跑 SKILL.md 故 runtime 正確」來緩解（那只緩解 runtime，不緩解 published spec）。真正的守門是 **/idd-all Phase 6 aggregate report 與本 PR body 明確標註 archive 順序 = #35 先於 #37**，由**人工** archiver 在 archive 前讀到。誠實邊界：#35 自己的 change 目錄**未**鏡射此約束（在已 verified 的 stacked #35 branch 上補 note 會觸發 rebase 級聯，代價 > 收益）；故此約束依賴 Phase 6 人工 checkpoint，而非 change-dir 內的機械 guard。若真的逆序 archive 了，補救是重跑 `/spectra-archive add-ecosystem-hint-syntax` 還原本 change 的四形態版本。
- **mitigant（僅限 runtime 面）**：agent 實際執行的是 SKILL.md，其 grammar 不論 spec archive 順序皆正確——所以即使 published spec 暫時回退，**agent 行為不受影響**（此點僅緩解 runtime，不緩解 published-spec 正確性）。
- SKILL.md 分類規則新增 hint 步驟、shape examples 新增 hint 列、把「同名遮蔽」段落改寫為指向 hint escape hatch。
- CHANGELOG entry + plugin shell minor version bump（skill 契約變更；MCP binary 不變）。

## Non-Goals (optional)

- **CLI 強制形態**（如 `cli:go` 強制查 Go 的 CLI flags）本 change **不做**。使用者「查同名 CLI」的深層需求只在 package 側被 hint 覆蓋。spec Requirement 1 rule 2 明文「The hint selects a package ecosystem only; it never reaches a URL, a CLI, or a runtime」已在**規範層**排除 hint 走 CLI（並非另立 Non-Goals 段落）；CLI 強制語法是否納入待後續 issue 決定。
- 不新增/改動任何 MCP engine runtime code —— 這是純 prose 契約（spec + skill）變更。
- 不擴充 known-ecosystem 集合本身（沿用既有 9 個 registry 的 ecosystem id：npm/pypi/crates/go/rubygems/jsr/packagist/maven/cran）。
- 斜線形（`eco/name`）與 `pkg:` purl-like 形已評估並否決：斜線形與 Go module path（`github.com/x/y`）衝突需額外排除規則；`pkg:` 較長。選定 `eco:` 前綴因其歧義邊界最小（三條件：已知前綴 + remainder 非空 + remainder 首字非 `/`）。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `explicit-doc-lookup`: Requirement 1（argument-shape classification）新增 ecosystem-hint 形態、precedence 插入 URL 與 Language 之間，並把 pin scenario 對齊 #36 的 pin_honored 行為。

## Impact

- Affected specs: `explicit-doc-lookup`（MODIFIED Requirement 1：precedence + hint scenario + example rows + pin scenario 對齊）
- Affected code:
  - Modified:
    - plugins/livedocs/skills/look-up/SKILL.md（分類規則新增 hint 步驟、shape examples、遮蔽段落改寫）
    - CHANGELOG.md（新 entry）
    - plugins/livedocs/.claude-plugin/plugin.json（plugin shell minor version bump）
    - .claude-plugin/marketplace.json（version 同步）
  - New: (none)
  - Removed: (none)
