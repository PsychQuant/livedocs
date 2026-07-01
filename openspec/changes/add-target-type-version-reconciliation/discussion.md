# Discussion — target-type taxonomy + version reconciliation

> Discuss 階段：先把 assumptions 對齊、open questions 拍板，再寫 proposal。
> 承接 issue PsychQuant/livedocs#1 + 其 diagnosis comment。

## 背景

LiveDocs 走 **skill-first** 再設計：web-authoritative 的文件查詢交給 auto-trigger 的 `docs-router` skill（WebFetch），只有「本機/協定 authoritative」的來源留給 MCP `introspect`（CLI / GraphQL / 已裝套件）。本 change 定義「一個 target 同時有 web-latest 與 local-installed 兩版」時的處理流程 —— 以及**哪些 target 根本沒有 local 版**。

## 已對齊的決策（對話中確認）

1. **context7 不整合進 binary** —— 它是 lossy/lagging index，正是 LiveDocs 要取代的；只當 skill 層外部 reference。
2. **分工原則：primary source 住在哪就用什麼**。web（docs 站 / registry / repo raw）→ skill + WebFetch；本機 binary（CLI `--help`）/ 非-GET 協定（GraphQL）/ 已裝套件 → MCP `introspect`。
3. **Target-type 分類是流程第一步**（issue #1 diagnosis 的核心修正）：
   - **has-local**（installed package / installed CLI）→ 走版本協調 state machine。
   - **web-only**（Claude Code 功能·設定、SaaS API、hosted docs）→ 直接查 web latest，**跳過協調、不問升級**（你不「安裝」web 文件）。
4. **版本協調 state machine（has-local）**：
   1. 查本機安裝版本 2. 查 web 最新版本 3. 比對：
   - 相同 → 以 local 為準
   - web 較新 → 問要不要升級：不升 → 以 local 為準；升 → 安裝新版 → 以 local 為準
   - **關鍵不變式：每個分支終點都是「以 local 為準」。web 只 gate 升級決策，local 才是回答的權威。**
5. **install 是需 user 明確確認的 mutation**（不可靜默安裝）。
6. **`introspect` 加 installed mode**（R 先做 `r-pkg`，npm/pip/CLI 同法）。

## Open Questions（待拍板 —— 每題附建議）

### Q1. 分類粒度：per-target 還是 per-question？
同一 target 可能兼有 web-only 問題與 local 問題（Claude Code：「怎麼設 MCP」= web；「`claude` 有什麼 flag」= local）。
- **(建議) per-question**：對每個查詢問「這個問題存不存在 local、version-matched 的權威源」。較準，但分類判斷多一步。
- per-target：整個 target 分一次類。簡單但粗（Claude Code 只能歸一格）。

### Q2. 「installed」的環境解析
npm 看 cwd 的 `node_modules`、python 看 venv/conda、R 看 `.libPaths()`。
- **(建議) cwd-project-scoped**：從當前專案脈絡解析已裝版（cwd 的 node_modules / active venv / 預設 libPaths）。貼「你正在這個專案裡工作」。
- explicit env param：caller 傳環境/路徑。
- global/default only：最簡但多環境會錯。

### Q3. 觸發策略：何時才雙查（進協調）？
- **(建議) context-aware**：只在「在用到該套件的專案裡」或「問題是版本/升級/debug 形狀」時觸發。避免 latency + 非專案雜訊。
- always dual-query：最簡、最重。
- explicit opt-in：只有 flag/使用者要求才做。

### Q4. install 動作歸誰執行？
- **(建議) skill/model 執行 + 確認**：install 會改環境、且 harness-dependent；skill 編排、model 在 user 確認後跑安裝指令（`npm i` / `install.packages()` / `pip install`）。**MCP 維持 read-only introspect**。
- MCP 執行 install：MCP 多一個 mutating tool，較 self-contained 但 MCP 變成會改環境（違背它 read-only 的定位）。

## Resolutions（2026-07-01 使用者拍板）

- **Q1 → per-question**：對每個查詢分類「這問題有沒有 local version-matched 權威源」，不是整個 target 一次分。
- **Q2 → cwd-project-scoped**：從當前專案脈絡解析已裝版（cwd 的 node_modules / active venv / 預設 `.libPaths()`）。
- **Q3 → context-aware trigger**：只在「在用到該套件的專案裡」或「問題是版本/升級/debug 形狀」時才雙查/協調。
- **Q4 → skill/model 執行 install + 確認**：MCP 維持 **read-only** introspect；升級由 skill 編排、model 在 user 確認後跑安裝指令。

## 下一步
Discuss 完成。進 `spectra propose`（proposal + specs delta + design + tasks），依上述 4 個 resolution 定契約。
