> [English](Home) | 繁體中文

# LiveDocs

給 AI agent 用的 primary-source-first 即時文件。任何 library 都直接從它的權威源頭抓最新文件, 不經過預建的 stale 索引, 也不靠凍在訓練 cutoff 的參數記憶。

## 為什麼

模型對一個 library 的認識, 是凍在訓練 cutoff 的參數記憶; 預建索引(如 context7)落後於它的重爬。LiveDocs 每次直達 live primary source, 還能對齊你本機實際安裝的版本。

## 對 context7

context7 是以覆蓋率排序、週期性重爬的索引; LiveDocs 直接抓 live registry, 所以「現在最新版是多少」這種問題, 它*就是*回傳今天的 release(by construction)。差距顯現在快速更新的 library 上。對六個(npm / PyPI / crates)2026-07-02 實測, context7 top-ranked 的預設匹配反映當前 release 的比例是 **0/6** —— 要嘛落後一個版本(react → v18 對 19.2.7; vite → 8.0.10 對 8.1.3), 要嘛**根本沒版本**(fastapi / pydantic / tokio / serde: top match 是一個沒有版本號的文件頁)。LiveDocs 每次都回傳精確的當前版本。

| 快速更新 library 上 | LiveDocs | context7(預設匹配) |
|---------------------|----------|---------------------|
| 反映當前 release(6 個 library) | 6/6(live registry, by construction) | 0/6 |
| 來源 | live registry / primary docs | 週期性重爬的索引 |

誠實範圍:只量**新鮮度**, 且刻意挑「快速更新」的 library —— 這是重爬索引最吃虧的情境, 不是中立取樣。LiveDocs 那一側 by construction 就是 registry(它即時抓), 所以這裡真正的發現是 context7 預設匹配的過時程度。context7 的主場是文件 / snippet 廣度(這裡不量), 而且當前版本常常存在於某個 lower-ranked 條目裡。方法與逐 library 數據:
[`evals/docs-router`](https://github.com/PsychQuant/livedocs/tree/main/evals/docs-router)。更深的定位:[對 context7](https://github.com/PsychQuant/livedocs/blob/main/docs/positioning.md)。

## 安裝

```
/plugin marketplace add PsychQuant/livedocs
/plugin install livedocs@livedocs-marketplace
```

之後用 `docs-router` skill, 它會把問題路由到對的工具。

## 工具

| 工具 | 用途 |
|------|------|
| `resolve_source` | 某 library 的 ranked primary sources(fidelity 優先)。 |
| `fetch_docs` | 某 source URL 的逐字 raw 內容。 |
| `latest_version` | 從 registry 拿最新版 + changelog/repo(9 生態:npm/pypi/crates/go/rubygems/jsr/packagist/maven/cran), 支援版本 pin。 |
| `introspect` | OpenAPI / GraphQL schema、已裝 CLI 的 `--help`、已裝 R 套件的版本(`kind:"r-pkg"`)、或專案的有效語言 runtime 版本(`kind:"runtime"`, Python/Node/Go/Rust/Java/.NET/Swift)。Read-only。 |

## 說明頁

- [版本協調流程](Version-Reconciliation-zh-TW): 自動偵測更新流程。
- [Primary-Source 光譜](Primary-Source-Spectrum-zh-TW): LiveDocs 是什麼、不是什麼。
- [測試](Testing-zh-TW): 測試套件（151 個 test）與各自覆蓋範圍。

## 其他

- [定位, 對 context7](https://github.com/PsychQuant/livedocs/blob/main/docs/positioning.md)
- [CHANGELOG](https://github.com/PsychQuant/livedocs/blob/main/CHANGELOG.md)
