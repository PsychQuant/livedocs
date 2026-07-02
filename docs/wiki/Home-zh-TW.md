> [English](Home) | 繁體中文

# LiveDocs

給 AI agent 用的 primary-source-first 即時文件。任何 library 都直接從它的權威源頭抓最新文件, 不經過預建的 stale 索引, 也不靠凍在訓練 cutoff 的參數記憶。

## 為什麼

模型對一個 library 的認識, 是凍在訓練 cutoff 的參數記憶; 預建索引(如 context7)落後於它的重爬。LiveDocs 每次直達 live primary source, 還能對齊你本機實際安裝的版本。

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
- [測試](Testing-zh-TW): 測試套件（139 個 test）與各自覆蓋範圍。

## 其他

- [定位, 對 context7](https://github.com/PsychQuant/livedocs/blob/main/docs/positioning.md)
- [CHANGELOG](https://github.com/PsychQuant/livedocs/blob/main/CHANGELOG.md)
