## Context

LiveDocs 已有版本協調（change `add-target-type-version-reconciliation`）：`introspect` 可查已裝套件（r-pkg）與 CLI 版本，docs-router skill 以 context-aware 觸發、defer-to-local 回答。缺口在**語言 runtime 本身**：沒有一條路徑回答「這個專案實際跑哪個 Python/Node/Go/… 版本」。專案普遍把 runtime 釘版（pyenv 版本檔、nvm、go.mod 的 go 指令、Package.swift 的 swift-tools-version、rust-toolchain）；對錯版本回答 = version-skew。

生態已有跨語言的版本管理事實標準（asdf 的 tool-versions、mise、慣用 per-language version 檔），一個 parser 即可覆蓋大量語言的宣告版本。ETag revalidation 讓保持最新的網路成本在內容未變時趨近零。

## Goals / Non-Goals

**Goals:**

- 新增 read-only 的「有效 runtime 版本」偵測，覆蓋幾乎所有語言（宣告版本）+ 對重點語言補實跑版本。
- 對錯版本零容忍：無法可靠解析時誠實回 not-resolved，不回誤導性全域版本。
- 讓 proactive 偵測可負擔：detect 便宜、快取、靜默；surface 只在相關時。
- 維持 MCP read-only 邊界與 defer-to-local 不變式。

**Non-Goals:**

- MCP 不安裝、不切換、不變更 runtime（升級仍由 skill 在明確確認後執行）。
- 不為 Ruby、PHP、Dart、Elixir、Kotlin、Scala 撰寫 depth adapter（通用 pin 層已覆蓋其宣告版本；depth 之後以資料補上）。
- 不做 R runtime 偵測（已有 r-pkg 套件版；R runtime 的 doc-skew 較小）。
- 不改 defer-to-local 與 confirmed-install 兩條既有需求。

## Decisions

### 兩層架構：通用 pin 層加上 depth adapter 層

runtime 版本偵測拆兩層。通用 pin 層是單一 parser，讀跨語言的版本宣告來源（asdf 的 tool-versions 檔、mise 設定檔、各語言慣用的 per-language version 檔），產出「宣告版本」，一個實作覆蓋幾乎所有語言。depth adapter 層針對重點語言補「active toolchain 探測」與「manifest 語意判讀」。

替代方案：為每個語言寫獨立 bespoke resolver。否決理由——在 N≥3 語言時通用層的 code 更少，且不同語言的宣告來源結構高度重疊（版本檔 + manifest），bespoke 會大量重複。

### Precedence 通則：active toolchain 為權威、宣告只作 cross-check

解析「有效版本」的優先序：active toolchain（實際會執行的 runtime，如 active venv 的直譯器、nvm 選定的 node、`go version`、`swift --version`）為權威；其次是 pin 檔（exact 版本字串）；再次是 manifest 宣告，且依其語意處理——directive（如 go.mod 的 go 版本）較權威、constraint（如 Python 的 requires-python `>=3.9`）僅作下限 cross-check、language-mode（如 swift-tools-version，非編譯器版本）不當版本。任一步都先過 `isSafe*` 邊界驗證。全部無法解析 → not-resolved。

替代方案：直接讀 pin 檔字面當版本。否決理由——manifest constraint 不是版本（宣告 `>=3.9` 實跑 3.12，照 3.9 回答即錨錯版）；Swift 的 swift-tools-version 根本不是編譯器版本。

### 觸發拆分：detect 為 eager 快取靜默、surface 為 lazy 且僅在相關時

把既有「context-aware trigger」拆成兩相。detect：進到能解析 runtime 的 cwd 時偵測一次並靜默把答案錨定在有效版本；per-cwd 快取避免每輪重測；ecosystem web-latest 由 ETag revalidation 便宜保持最新。surface：只有在答案 version-sensitive、或實際出現 skew／錯誤時，才提示可升級。

替代方案：維持純 context-aware（要問到版本才觸發）。否決理由——使用者要的是沒問就先對齊；ETag + 快取讓 detect 的成本降到可 eager。替代方案：全 proactive（每輪都 detect 且都 surface）。否決理由——surface 每輪 = context 污染，ETag 管不到 token 成本。

### MCP 只新增 read-only kind、detect/surface 編排留在 docs-router skill

MCP `introspect` 新增一個 runtime kind，單次呼叫回「有效 runtime 版本」，read-only。detect（何時 eager 偵測）、surface（何時提示升級）、per-cwd 快取這些編排與 state 留在 docs-router skill。

替代方案：把觸發/快取/surface 放進 MCP。否決理由——違反既有 MCP read-only 邊界，且把 session/cwd state 放進本應無狀態的工具層。

### 初始 depth adapter 集與通用 pin 層來源

依使用度、想用度、pin 抓得到、跨版 doc-skew 大，初始 depth adapter 為 7 個：Python、Node/TypeScript、Go、Rust、Java、C#/.NET、Swift（Swift 兼作 LiveDocs 自身 dogfood）。這 7 個覆蓋所有結構型態：constraint（Python/Node）、directive（Go）、toolchain 檔（Rust）、SDK pin 檔（.NET 的 SDK 版本檔）、language-mode（Swift）。通用 pin 層來源：asdf 的 tool-versions 檔、mise 設定檔、慣用的 per-language version 檔。

替代方案：一次做所有語言的 depth adapter。否決理由——YAGNI；通用層已達成廣度，depth 只花在最高價值語言。

### per-cwd runtime 快取與失效

detect 的結果以 cwd 為 key 快取，快取 key 併入相關 pin 來源檔的 mtime；cwd 改變或 pin 檔異動即失效。快取存活於 session（in-memory），與 ETag 快取正交（ETag 管網路 revalidation、此快取管本機 introspection 重測）。

替代方案：不快取、每輪重測。否決理由——本機 introspection 的 latency 是 ETag 管不到的成本，每輪重測把它放大。

## Implementation Contract

**Behavior**：呼叫 `introspect`，kind = runtime、target = 語言名或 auto（由 cwd 存在的 manifest 推斷），回傳有效 runtime 版本、來源（哪個 pin 來源命中）、語意（exact/constraint/directive/language-mode/active-toolchain）、解析環境；無法解析時回 not-resolved 與原因，不回全域版本。

**Interface / data shape**：
- `Sources/LiveDocsCore/RuntimeIntrospection.swift`（純核心，無網路）匯出：一個結果型別（resolved 帶 version/source/semantics/env，或 notResolved 帶 reason）、一個通用 pin 層 parser（讀 tool-versions/mise/per-language version 檔）、一個 per-language adapter 抽象（detect(cwd)/sources/probeActive/isSafe）、以及 7 個語言 adapter 的宣告式資料。
- `Sources/CheLiveDocsMCP/RuntimeIntrospect.swift`：MCP 側執行本機探測（呼叫 toolchain 版本指令，injection-guarded，比照既有 RIntrospect）。
- `Sources/CheLiveDocsMCP/Server.swift`：`introspect` 的 kind enum 與 dispatch 新增 runtime。
- `plugins/livedocs/skills/docs-router/SKILL.md`：新增 detect/surface 觸發描述與 per-cwd 快取語意。

**Failure modes**：not-resolved 為一級結果（絕不捏造全域版本，比照 r-pkg 的 not-installed）；不安全的語言名/路徑經 `isSafe*` 拒絕；manifest 為 constraint 而非 exact 版本時，回實跑版本並在違反 constraint 時附 cross-check 警示，而非把 constraint 當版本。

**Acceptance criteria**：
- LiveDocsCore 單元測試涵蓋——通用 pin 層各來源解析（tool-versions/mise/per-language 檔）、precedence（active toolchain 勝過 pin、pin 勝過 manifest、constraint 只 cross-check）、honest-unknown（無來源 → not-resolved）、`isSafe*` 邊界。
- 7 個 adapter 各有 detect/sources/precedence 的 fixture 測試（Swift 以本 repo 自身 dogfood 一則）。
- MCP dispatch 測試：kind=runtime 走到 runtime 路徑、read-only。
- docs-router skill 文件描述 detect（eager/cached/silent）與 surface（lazy/relevant）兩相且 defer-to-local 不變。
- `swift test` 全綠。

**Scope boundaries**：
- In scope：通用 pin 層、7 個 depth adapter、precedence 通則、MCP runtime kind（read-only）、docs-router 的 detect/surface 觸發與 per-cwd 快取語意、CHANGELOG/README 更新。
- Out of scope：安裝/升級 runtime（仍由 skill 明確確認後執行）、Ruby/PHP/Dart/Elixir/Kotlin/Scala 的 depth adapter、R runtime 偵測、修改 defer-to-local 與 confirmed-install 需求。

## Risks / Trade-offs

- [錨錯版本（最高風險）] → precedence 以 active toolchain 為權威 + honest not-resolved 強制；constraint 絕不當 exact 版本。
- [每輪重測本機 introspection 的 latency（ETag 管不到）] → per-cwd 快取，key 併入 pin 檔 mtime。
- [surface 過度提示造成 context 污染] → detect 與 surface 拆開，surface 只在 version-sensitive/skew 時。
- [通用 pin 層對某語言解析不完整] → 該語言仍能由 depth adapter 或誠實 not-resolved 收尾，不 silently 給錯。
- [7 個 adapter 的維護面] → adapter 為宣告式資料 + 單一 probe 指令，非各自一套邏輯，維護面被壓在通用核心。
