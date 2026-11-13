# Skills

Agent skills for Claude Code. Each skill is a self-contained directory with a `SKILL.md` manifest.

## Available Skills

### [dostr-core](dostr-core/SKILL.md)

> Dostr Dart packages: relay connections, REQ and EVENT on chosen relays, the outbox model, signers, accounts and one package per NIP.

#### 🚀 Install dostr-core

```bash
npx skills add nogringo/dostr --skill dostr-core
```

| Reference | Description |
| --------- | ----------- |
| [Setup](dostr-core/references/setup.md) | `pub add`, `RelayManager` and its options, lifecycle |
| [Requests](dostr-core/references/requests.md) | `RelayReqs`, `RelayPublishes`, fetchers and `UrlSet` |
| [Accounts](dostr-core/references/accounts.md) | Signers, pending requests, `Accounts` |
| [Usecases](dostr-core/references/usecases.md) | Which package for which NIP |

---

## Adding a Skill

1. Create `skills/<name>/` directory
2. Add `SKILL.md` with frontmatter (`name`, `description`, `metadata`)
3. Add `references/` sub-files for detailed sections
4. Add entry to this README
