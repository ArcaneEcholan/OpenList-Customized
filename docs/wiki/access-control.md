# Access control model

OpenList uses **layered** access control. A request must pass auth, path scope, meta/path rules, and (for many actions) a user permission bit.

## Layers overview

```text
1. Role          who you are (guest / general / admin)
2. Permission    what actions you may perform (bitmask)
3. Meta / path   where those rules apply (password, hide, allowlists)
4. Endpoint      auth middleware + action-specific checks
```

Frontend **hides** buttons with `userCan(...)` / admin checks.  
Backend **enforces** the same ideas again — UI hide is not security.

---

## 1. Role

`User.role` (`OpenList/internal/model/user.go`):

| Role | Meaning |
|------|---------|
| Guest | Anonymous / limited |
| General | Normal logged-in user |
| Admin | Admin APIs (`AuthAdmin`); many UI gates treat admin as allowed |

Admin is special-cased in middleware and frontend (`UserMethods.is_admin`).

Users also have a `base_path`. Paths are joined with `user.JoinPath(...)` so requests cannot escape that subtree.

---

## 2. User permission bitmask

`User.permission` is an `int32` bitfield. Backend helpers: `user.CanRename()`, `CanWriteContent()`, …  
Frontend mirror: `UserPermissions` / `userCan("rename")` in `OpenList-Frontend/src/types/user.ts`.

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | `see_hides` | See names matching meta hide rules |
| 1 | `access_without_password` | Skip meta folder password |
| 2 | `offline_download` | Create offline download tasks |
| 3 | `write_content` | mkdir / upload |
| 4 | `rename` | Rename |
| 5 | `move` | Move |
| 6 | `copy` | Copy |
| 7 | `delete` | Remove |
| 8 | `webdav_read` | WebDAV read |
| 9 | `webdav_manage` | WebDAV write |
| 10 | `ftp_read` | FTP/SFTP login + read |
| 11 | `ftp_manage` | FTP/SFTP write |
| 12 | `read_archives` | Open / list archives |
| 13 | `decompress` | Extract archives |
| 14 | `share` | Create shares |
| 15 | `customize_share_id` | Custom share IDs |

There is **no** dedicated bit for “Detail Information” today. That feature only requires path access (`CanAccess`).

---

## 3. Meta / path rules

Per-path **Meta** (`OpenList/internal/model/meta.go`) adds folder-level policy on top of the user bitmask:

| Field | Role |
|-------|------|
| `Password` + `PSub` | Folder password (unless bit 1) |
| `Hide` + `HSub` | Regex hide of child names (unless bit 0) |
| `ReadUsers` + `ReadUsersSub` | Read allowlist of user IDs |
| `WriteUsers` + `WriteUsersSub` | Write allowlist of user IDs |
| `Write` + `WSub` | Meta-level write enable for path / subpaths |

Helpers in `OpenList/server/common/check.go`:

| Function | Purpose |
|----------|---------|
| `CanAccess` | Browse/read gate: hide + `CanRead` + password |
| `CanRead` | Meta `ReadUsers` allowlist |
| `CanWrite` | Meta `WriteUsers` allowlist |
| `CanWriteContentBypassUserPerms` | `meta.Write` covers this path |

### Write combination (typical)

For upload / mkdir-style ops, handlers generally require:

1. `(user.CanWriteContent() || CanWriteContentBypassUserPerms(meta, path))`
2. **and** `CanWrite(user, meta, path)` (whitelist)

`meta.Write` can bypass the user **write_content** bit, but **not** the WriteUsers whitelist when that list is set.

---

## 4. Request gating pattern

Typical `/fs/*` flow:

1. **Auth middleware** — logged in (or guest session) for the route group  
2. **JoinPath** — path stays under `user.base_path`  
3. **CanAccess** — meta hide / read allowlist / password  
4. **Action bit** — e.g. rename → `CanRename()`, share → `CanShare()`  

Some endpoints are admin-only (`middlewares.AuthAdmin`), e.g. `/fs/link`.

Share links and signed download URLs use separate paths (`/sd/...`, `/d/...`) with their own verification.

---

## 5. Frontend wiring

| Mechanism | Where |
|-----------|--------|
| `userCan("rename")` etc. | Context menu / toolbar visibility |
| `objStore.write` / write bypass | Storage/meta write flags from list API |
| `isShare()` | Hide many actions on share pages |
| `UserMethods.is_admin(me())` | Package download, some admin-only UI |

Always assume a crafted API call can skip the UI — backend checks are authoritative.

---

## 6. Adding a new gated action

Checklist:

1. Pick the next free permission bit (currently **16**) in `user.go` + `UserPermissions`  
2. Add i18n under `users.permissions.*`  
3. Enforce on the handler (`user.CanXxx()` or equivalent)  
4. Hide the UI with `userCan("…")`  
5. Decide whether admin always bypasses (usual pattern: yes in UI)

If the action should only need “can open this path”, reuse `CanAccess` only (like Detail Information today) and document that choice.

---

## Key source files

| Area | Path |
|------|------|
| Bits + role | `OpenList/internal/model/user.go` |
| Meta | `OpenList/internal/model/meta.go` |
| Access helpers | `OpenList/server/common/check.go` |
| Auth middleware | `OpenList/server/middlewares/auth.go` |
| Frontend bits | `OpenList-Frontend/src/types/user.ts` |
| Frontend helper | `OpenList-Frontend/src/store/user.ts` (`userCan`) |
