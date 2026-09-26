# OpenList workspace

Parent repository that vendors the official projects as submodules.

| Path | Remote |
|------|--------|
| `OpenList/` | `git@github.com:ArcaneEcholan/OpenList.git` |
| `OpenList-Frontend/` | `git@github.com:ArcaneEcholan/OpenList-Frontend.git` |

```bash
git clone --recurse-submodules <this-repo-url>
./build.sh
```

## Docs

- [Wiki](./docs/wiki/) — access control model and other monorepo notes
- [Charts](./docs/chart/) — design diagrams

## Code modification workflow

Do **feature work inside the submodules**, not as loose files in the parent.

1. **Edit in the submodule** on a feature branch (never commit directly on `main` for your changes):

   ```bash
   cd OpenList   # or OpenList-Frontend
   git checkout main
   git pull
   git checkout -b feat/your-feature
   # ... edit, test ...
   git add -A
   git commit -m "feat: your change"
   ```

2. **Update the monorepo** so it pins the new submodule commit:

   ```bash
   cd ..   # back to monorepo root
   git add OpenList OpenList-Frontend   # only the ones you changed
   git status   # should show submodule pointer updates (mode 160000)
   git commit -m "chore: bump OpenList submodule for feat/your-feature"
   ```

3. **Build** (optional, from monorepo root):

   ```bash
   ./build.sh
   ```

### Notes

- Parent repo only records which submodule SHAs are checked out. Real history lives in each submodule.
- To contribute upstream: push the submodule feature branch to your fork and open a PR against `OpenListTeam/OpenList` or `OpenListTeam/OpenList-Frontend`.
- Keep monorepo-only files (`build.sh`, root `docs/`, …) out of upstream PRs.
- After `git pull` on the parent, run `git submodule update --init --recursive` so submodule checkouts match the pinned commits.
