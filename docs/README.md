# Zeta 文档 · Zeta documentation

| 语言 | 入口 |
| --- | --- |
| 中文 | [docs/zh/README.md](./zh/README.md) |
| English | [docs/en/README.md](./en/README.md) |

## 目录约定

两个语言目录的**子目录结构完全一致**，同一份文档在两边同名：

```
docs/
├── zh/                     中文
│   ├── README.md
│   ├── architecture/       架构总览、分层设计、工程规范、迁移文档
│   ├── guides/             开发者文档、术语表、国际化指南
│   ├── product/            产品需求、故障排查与数据说明
│   ├── protocols/          Provider 协议基线
│   ├── release/            发版流程
│   ├── history/            已退役能力与开发流水，仅存档
│   └── images/             截图与拍摄清单
└── en/                     English — same subdirectories, same filenames
```

- 文件名不带语言后缀；语言由所在目录决定。
- 新增文档必须**同时**在 `zh/` 与 `en/` 下创建同名文件。
- 唯一例外是 `history/`：归档文档保持原语言，另一侧只放指向它的说明。

Both language trees use **identical subdirectory structures and identical filenames**; the language is
determined by the directory, not by a filename suffix. New documents must be created on both sides.
The sole exception is `history/`, where archived documents keep their original language and the other
side carries a pointer.
