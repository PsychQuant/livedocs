## Context

LiveDocs 走 skill-first：web-authoritative 查詢由 auto-trigger 的 `docs-router` skill（WebFetch）處理，只有本機/協定 authoritative 來源留給 MCP `introspect`（read-only）。本 change 定義「一個查詢同時牽涉 web-latest 與本機已裝版」時的協調流程，以及「根本沒有本機版」（Claude Code 功能、SaaS）的直查路徑。決策全部承接 discussion.md 的 4 個 resolution。

## Goals / Non-Goals

**Goals**
- 讓 has-local 查詢在照 web 文件操作前，先意識到本機版本落差（擋 version-skew bug）。
- web-only 查詢維持零開銷（不做無意義的本機查詢）。

**Non-Goals**
- MCP 不做安裝/升級（維持 read-only）。
- 不整合 context7（維持外部 reference）。
- 不解決跨多環境的自動選擇（一次只認 cwd-scoped 的當前環境）。
- 不做 web-only 的版本 pin（web-only 恆 latest）。

## Decisions

### Decision: Per-question classification (not per-target)
分類以「這個查詢」為單位，而非整個 target。同一 target 可兼有 web-only（功能/設定）與 has-local（CLI flag / API）問題。**替代方案** per-target 較簡單但把 Claude Code 這類混合體歸一格會失準——rejected。

### Decision: cwd-project-scoped installed resolution
「已裝版本」從當前專案脈絡解析（cwd 的 `node_modules` / active venv·conda / 預設 `.libPaths()`）。**替代方案** global-only（多環境會回錯版）與 explicit-env-param（每次要指定，太吵）皆 rejected；無法解析時回報 "not installed in current context" 而非誤報 global。

### Decision: Context-aware reconciliation trigger
只在「在用到該套件的專案內」或「版本/升級/debug 形狀的問題」才進協調。**替代方案** always-dual-query（使用者自己指出 loading 會變重）與 explicit-opt-in（漏用）皆 rejected。

### Decision: Skill-executed install, read-only MCP
升級安裝由 skill/model 在 user 確認後執行（跑 ecosystem 安裝指令）；MCP 只 introspect、不 mutate。**替代方案** MCP 自帶 install tool 較 self-contained 但讓 MCP 變環境-mutating、違背 read-only 定位——rejected。

### Decision: Defer-to-local terminal invariant
協調 state machine 的每個分支終點恆為「以 local 為準」；web 只 gate 升級決策，不當答案。這是回答保真的核心：答案要對齊使用者**實際會跑的那一版**。

## Implementation Contract

- **`introspect` installed-version mode（MCP, read-only）**：輸入 = {package/CLI 名, ecosystem}；輸出 = {installed_version, help?（若可得）, resolved_env（哪個環境解析出來的）}；找不到 → 明確 "not installed in current context"；**絕不執行安裝**。R 先做（`Rscript -e 'packageVersion(...)'` + 套件名限 `^[A-Za-z0-9.]+$`），npm/pip/CLI 同法。
- **`docs-router` skill classifier + branch**：對每個查詢輸出 has-local | web-only；web-only → 直查 web latest；has-local + context-aware 命中 → 進協調 state machine。
- **協調 state machine**：introspect(installed) + web latest → 依 defer-to-local invariant 分三支（相同/不升→local；升→確認→skill 執行安裝→local）。
- 驗收：per-question 分類、三分支不變式、context-aware gating、install 需確認、MCP 不 mutate —— 皆對應 specs 的 Scenario。

## Risks / Trade-offs

- [per-question 分類可能誤判混合查詢] → 由 skill 依「問的是功能/設定 vs 已裝行為」判；模糊時偏向 web-only（較安全、零開銷），使用者可追問。
- [Rscript / 環境探測有 startup latency] → 由 context-aware trigger 限制只在必要時跑。
- [cwd-scoped 解析在非專案 cwd 會 miss] → 回 "not installed in current context"，退回 web latest，不誤報。

## Open Questions

- npm/pip 的 installed 解析細節（monorepo workspace、pyenv shims）留待 implement 時逐一驗；R 先落地。

## Migration Plan

純新增行為，無 breaking；分階段：先 introspect installed（R）→ classifier + web-only 直查 → 協調 state machine + install 確認。無需 rollback（feature-additive）。
