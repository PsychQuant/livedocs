## 1. Installed-version introspection (MCP, read-only)

- [x] 1.1 加 `introspect` 的 installed-version mode（R 先做 `r-pkg`）：輸入 {package, ecosystem} → 回 {installed_version, resolved_env}，**維持 read-only MCP**（絕不安裝）。Verify: 對已裝的 `dplyr` 呼叫回真實 `packageVersion`；unit test 斷言無任何 mutation 呼叫。
- [x] 1.2 cwd-project-scoped 環境解析（R `.libPaths()`）+ 套件名 guard `^[A-Za-z0-9.]+$`。Verify: 在有/無專案 lib 的 cwd 各測一次；malicious 名（`../x`）回 nil。
- [x] 1.3 找不到已裝版時回 "not installed in current context"（不誤報 global）。Verify: 對未安裝套件呼叫，斷言回 not-installed 而非 fabricated 版本。

## 2. docs-router classifier + branch

- [x] 2.1 per-question classification：對每個查詢輸出 `has-local | web-only`（不是 per-target）。Verify: skill fixture — Claude Code「設 MCP」→ web-only、「`claude` flag」→ has-local。
- [x] 2.2 web-only 分支：直查 web latest，不協調、不問升級。Verify: web-only 查詢的 trace 無任何 introspect/installed 呼叫。

## 3. Version reconciliation state machine (has-local)

- [x] 3.1 context-aware trigger gating：只在「用到該套件的專案內」或「版本/升級/debug 形狀問題」才進協調。Verify: bare 概念題（無專案）→ 跳過本機查詢、直接 web latest。
- [x] 3.2 defer-to-local terminal invariant 三分支（相同/不升→local；升→確認→local）。Verify: 三個 scenario 各一測，斷言答案來源恆為 local；web 僅用於升級判斷。
- [x] 3.3 skill-executed install + 確認：升級由 skill/model 在 user 確認後跑安裝指令；未確認則零 mutation。Verify: 模擬「web 較新」→ 斷言先要 confirm；拒絕 → 環境不變。

## 4. Verification & wiring

- [x] 4.1 端到端 dogfood：以 R 套件（本機已裝 vs CRAN latest）跑完整 has-local 流程 + 一個 web-only（Claude Code）流程。Verify: 手動 assert 兩路徑各自正確、context7 未被呼叫。
- [x] 4.2 `spectra validate --strict` 全綠 + specs 的所有 Scenario 有對應測試或 dogfood 斷言。Verify: `spectra validate --strict` exit 0。
