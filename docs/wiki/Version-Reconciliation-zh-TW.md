> [English](Version-Reconciliation) | 繁體中文

# 版本協調流程 — 自動偵測更新

當一個目標同時有 web-latest 和本機已裝版時, LiveDocs 偵測落差並提供升級。貫穿每個分支的規則:

> 以你的本機已裝版回答。web-latest 只用來判斷你是否落後、以及提供升級, 不當答案本身。

```mermaid
flowchart TD
    Q["文件查詢"] --> C{"per-question 分類:<br/>有沒有本機、<br/>version-matched 的源?"}
    C -->|"web-only<br/>(Claude Code、SaaS、hosted docs)"| W["查 web-latest<br/>(不協調、<br/>不問升級)"]
    C -->|"has-local<br/>(已裝套件 / CLI)"| T{"context-aware 觸發?<br/>在用到的專案裡,或<br/>版本 / 升級 / debug 問題"}
    T -->|"否"| W
    T -->|"是"| L["introspect: 本機已裝版<br/>(READ-ONLY, cwd-scoped)"]
    L --> V["latest_version: web-latest"]
    V --> CMP{"已裝 vs 最新"}
    CMP -->|"相同"| LOCAL["以本機<br/>已裝版回答"]
    CMP -->|"web 較新"| U{"升級?<br/>(需明確確認)"}
    U -->|"不升"| LOCAL
    U -->|"升"| INS["skill 執行安裝<br/>(MCP 維持 read-only)"]
    INS --> LOCAL
```

## 說明

- 分類是 per-question。同一工具可兼兩者:「怎麼設定 Claude Code」是 web-only;「已裝的 `claude` 有什麼 flag」是 has-local。
- context-aware 觸發只在必要時啟動(在用到的專案內, 或版本 / 升級 / debug 問題), 以控 latency。
- installed 解析是 cwd-scoped: npm `node_modules`、Python venv、或當前專案的 R `.libPaths()`, 不誤用 global。
- install 是需確認的 mutation, 由 skill 在明確確認後執行。MCP 本身維持 read-only; 它只 introspect, 從不安裝。

另見: [Primary-Source 光譜](Primary-Source-Spectrum-zh-TW), 產品邊界。
