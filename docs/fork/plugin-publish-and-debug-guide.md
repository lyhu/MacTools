# MacTools 插件上架与本地调试指南

> 本文档基于项目文档 `docs/plugins/plugin-catalog.md`、`docs/plugins/local-native-plugins.md` 以及 `Makefile` 整理。

---

## 一、本地调试流程

### 1. 插件目录结构

插件放在 `Plugins/<PluginName>/` 下，至少包含：

```text
Plugins/Demo/
├── plugin.json          # 插件清单（ID、版本、能力、Bundle 路径、构建 scheme）
├── Sources/             # 插件实现与功能代码
├── Bundle/              # 薄 bundle 入口，锚定 factory
├── Tests/               # 可选 XCTest
├── project.yml          # 可选，仅当插件需要额外构建差异时
└── Resources/           # 可选插件资源（.xcstrings、图片、JSON 等）
```

`plugin.json` 关键字段：`id`（稳定、可读、须与运行时 `PluginMetadata.id` 一致）、`version`、`displayName`、`summary`、`localizedMetadata`、`minHostVersion`、`pluginKitVersion`、`bundleRelativePath`、`factoryClass`、`capabilities`（`primaryPanel`/`componentPanel`/`settings`）、`permissions`、`category`。

### 2. 初始化与生成

```bash
make setup          # 生成 LocalConfig.xcconfig，填入 DEVELOPMENT_TEAM 和 BUNDLE_IDENTIFIER_PREFIX
make generate       # 扫描 Plugins/*/plugin.json 生成 XcodeGen 插件 target
```

### 3. 构建并运行（最常用）

```bash
make run
```

`make run` 会依次：构建主 App → 同步最新 Debug 插件 bundle 到 `build/LocalPlugins/Packages` → 生成 `build/LocalPlugins/catalog.dev.json` → 更新 `~/Library/Application Support/MacTools Dev/Plugins/Installed` → 以可回滚方式替换 `~/Applications/MacTools Dev.app` 并启动。若未设置 `MACTOOLS_PLUGIN_CATALOG_URL` 且本地 catalog 存在，Make 会自动使用 `file://` 本地 catalog。

### 4. 只构建插件（不启动 App）

```bash
make build-plugin # 构建全部本地插件并生成 Debug catalog
make build-plugin PLUGIN=Demo                          # 按目录名构建单个
make build-plugin PLUGIN=com.example.mactools.demo     # 按插件 ID 构建单个
```

产物位于 `build/LocalPlugins/`（`Packages/*.mactoolsplugin` + `catalog.dev.json`）。

### 5. 只同步已构建的 Debug 插件

```bash
make sync-debug-plugins                    # 全部
make sync-debug-plugins PLUGIN=calendar    # 单个，保留其他已安装包
```

### 6. 覆盖目录 / 自定义 URL

```bash
make build-plugin LOCAL_PLUGIN_SOURCE_DIR=/path/to/plugins LOCAL_PLUGIN_BUILD_DIR=/path/to/build
make run MACTOOLS_PLUGIN_CATALOG_URL=file:///path/to/catalog.dev.json
```

### 7. 调试模式说明

- `file://` URL → 本地开发 catalog，**签名可选**。
- `https://` URL → 生产 catalog 策略，**必须带 Ed25519 签名**。

```bash
make run MACTOOLS_PLUGIN_CATALOG_URL=https://mactools.ggbond.app/plugins/catalog.json
```

### 8. 运行测试

```bash
# 最小测试类
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug -derivedDataPath build/DerivedData test -quiet -only-testing:MacToolsTests/<TestClassName>
```

> 注意：普通功能 PR 中**不要**手动提升 `plugin.json.version`，`make release` 流程会自动处理。

---

## 二、上架（发布）流程

推荐使用**增量批量插件发布流程**。

### 1. 运行发布助手

```bash
make release
```

选择 `plugin`、发布模式、`patch`/`minor`/`major`。助手会分析生产 catalog 并展示待合并的 manifest 版本变更。

### 2. 确认后自动执行

- 同步 `main`，按需 bump 变更插件的 manifest
- 将 `release: plugin` changelog 片段编译进 `CHANGELOG.md`
- 运行发布计划检查
- 提交 bump，并推送批量 tag（如 `plugins-1.0.1`）

### 3. GitHub Action 自动完成

- `Plugin Release` workflow 读取当前 PluginKit 版本的 catalog
- `auto` 模式选择：新增插件、manifest 版本高于旧 catalog 的插件、以及共享 `Sources/MacToolsPluginKit/` 代码变更后需重建的插件
- 构建、签名、zip、上传选中的插件包
- 生成 delta catalog 并合并进该 ABI 行的 catalog（未变动的条目保留原 URL/校验和/版本）
- 签名后的 catalog 提交到 `docs/plugins/`（v4 当前为 `docs/plugins/v4/host-1.2/catalog.json`）
- `Deploy Pages` 将签名 catalog 发布到 GitHub Pages

### 4. 控制发布范围

```bash
# 全量重建：在 Plugin Release workflow 手动运行，mode=all
# 受控子集：mode=selected，plugins 传逗号分隔的插件 ID 或目录名
```

### 5. 本地 dry-run 打包（可选）

```bash
make package-plugins-release \
  PLUGIN_CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
  PLUGIN_CATALOG_PRIVATE_KEY_BASE64="$PLUGIN_CATALOG_PRIVATE_KEY_BASE64" \
  PLUGIN_RELEASE_TAG=plugins-1.0.1
```

产物：`build/PluginRelease/Assets/*.mactoolsplugin.zip` + `catalog.json`。

---

## 三、关键注意事项

| 事项 | 说明 |
|------|------|
| **签名凭据** | 发布 catalog 必须带 Ed25519 签名；插件 bundle 需与宿主 Team ID 一致签名。私钥、Developer ID、GitHub token 放环境变量或 CI secrets，**不提交**。 |
| **PluginKit ABI 边界** | `pluginKitVersion` 变化时所有插件必须重建且 manifest 版本递增；catalog 合并会拒绝混合 PluginKit 版本。 |
| **`minHostVersion`** | 插件采用新导出的 PluginKit 类型时，须设为第一个导出该符号的 App 版本。 |
| **共享代码变更** | 修改 `Sources/MacToolsPluginKit/` 对所有插件都是 package-relevant，`make release` 会自动 bump 所有受影响 manifest。 |
| **发布顺序** | 切换新生产 catalog URL 时：先发布新插件批次 → 等 Pages 部署签名 catalog → 再发布 App。`preflight-app-plugin-catalog.swift` 会校验。 |
| **批量 tag** | 通过 `package.url`/`releaseNotesURL` 存储，一个 catalog 可指向不同插件的不同 release tag。 |
| **`--latest=false`** | 插件批量发布不设为 GitHub Latest；只有稳定 `v*` App 发布才可成为 Latest。 |

---

## 四、安装位置与卸载

- 生产安装：`~/Library/Application Support/MacTools/Plugins/`（`Installed/`、`Staging/`、`Data/`、`Caches/`、`Temporary/`）
- Debug 安装：`~/Library/Application Support/MacTools Dev/Plugins/`
- 卸载只删除已安装副本，**不会**删除插件源码目录或本地构建目录
- 已加载的原生代码在进程内不强制卸载，App 重启后才完全释放