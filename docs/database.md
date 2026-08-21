# 统一数据库

## 目标

`UnifiedDatabase`（`lib/core/database/unified_database.dart`）让 Android、iOS、Windows、macOS、Linux 与 Web 使用同一份 SQLite schema、迁移编号和参数化 SQL。业务代码不得再根据平台分别实现 SQLite 与 IndexedDB 仓储。

| 平台 | 引擎与持久化 |
| --- | --- |
| Android / iOS / Windows / macOS / Linux | Drift 打开的 `gotoim.sqlite`，位于应用 Documents 目录 |
| Web | SQLite WASM；优先 OPFS，浏览器不支持时由 Drift 回退到 IndexedDB 持久化 |

Web 的 IndexedDB 只承载 WASM SQLite 文件，并不存放另一套对象表或业务查询逻辑。因此表名、索引、事务语义和 CRUD SQL 与原生端一致。

## 初始化与注入

应用启动时在 `bootstrap()` 创建并执行迁移，然后以 `unifiedDatabaseProvider` 注入。业务仓储通过 Provider 取得 `UnifiedDatabase`；测试可通过 `DatabaseConnection(NativeDatabase.memory())` 构造内存实例。

```dart
final database = ref.read(unifiedDatabaseProvider);
await database.insertDiagnosticRecord(
  id: 'local-1',
  title: '缓存项',
  payload: {'source': 'feature'},
);
final records = await database.readDiagnosticRecords();
```

所有值使用 `?` 参数绑定。`clearTable()` 仅允许已知的受管表，不接受 UI/H5 传入的任意表名或 SQL。

## Schema 迁移

当前 `PRAGMA user_version` 为 `1`，迁入参考客户端的表和查询索引：

- `Settings`、`LoginUsers`
- `Owners`、`ChatObjects`
- `Friends`、`Members`、`Messages`
- `diagnostic_records`（开发验证 CRUD）

原项目中 `ChatObjects` 与 `Owners` 都使用了全局 SQLite 索引名 `idx_name`；SQLite 的索引名在整个数据库内必须唯一，因此迁移中分别命名为 `idx_chat_objects_name`、`idx_owners_name`，避免第二个索引被静默跳过。

新增 schema 的流程：提高 `schemaVersion`，在 `_initialize()` 中按旧版本顺序添加只增量、可恢复的迁移，最后写入 `PRAGMA user_version`。禁止通过删除数据库来升级；用户数据清除必须是显式、可确认的产品功能。

## Web 资源

`web/sqlite3.wasm` 与 `web/drift_worker.js` 必须与 Drift 版本一起发布。`UnifiedDatabase.openDefault()` 使用它们启动 Web SQLite。Web 首次打开需要下载约 1 MB 的 WASM/worker；资源缺失、被缓存服务器错误改写 MIME 类型或被 CSP 拦截时，数据库初始化会失败并以启动错误体现。

## 开发诊断中心

Debug 模式的“开发诊断中心 → 统一数据库测试”提供：

1. schema、表名、行数、DDL 与实际存储方式查看；
2. `diagnostic_records` 的 INSERT / SELECT / UPDATE / DELETE / 清表；
3. 独立 `diagnostic_scratch` 的 CREATE / DROP；
4. 可选中、可复制的 JSON 成功/失败结果。

诊断页只会清空 `diagnostic_records`，不会触碰聊天、联系人或登录数据。
