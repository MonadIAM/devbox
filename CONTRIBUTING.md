# Contributing

----

<details>
<summary><strong>Environment Setup</strong></summary>

> The repository contains only shell (`.sh`) and PowerShell (`.ps1`) scripts

> Requires `Windows 10/11` with `WSL2` and PowerShell run as Administrator
> for testing `setup.ps1`; `provision.sh` runs inside the WSL Ubuntu instance.

[VSCode](https://code.visualstudio.com/) is the recommended editor for development.

#### VSCode Setup
Install the following extensions for proper [EditorConfig](https://editorconfig.org/),
shell, and PowerShell integration:
1. `EditorConfig.EditorConfig`
2. `timonwong.shellcheck`
3. `ms-vscode.powershell`

> Keep `LF` line endings for `.sh` files — `.editorconfig` enforces this,
> `CRLF` breaks script execution inside WSL.

</details>

----

<details>
<summary><strong>Git Hooks</strong></summary>

*Enable git hooks:*
```sh
chmod +x .githooks/*
git config core.hooksPath .githooks
```

#### Checks performed:
 - `commit-msg` — commit message format.
 - `pre-push`   — branch naming format.

> There is no `pre-commit` hook here: the repository has no lint or build
> pipeline, so scripts are validated manually before pushing.

#### Allowed prefixes for commits and branches:
`feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

#### Commit message format:
```text
<type>(<scope>)?[!]: <subject>
```

*Where:*
 - `<type>`    — one of the allowed prefixes above.
 - `<scope>`   — optional scope in parentheses, alphanumeric/`-`.
 - `!`         — optional breaking change marker.
 - `: `        — colon + space are required.
 - `<subject>` — short description.
> Total commit message length is limited to 70 characters.

*Valid commit examples:*
 - `feat: add k3d cluster bootstrap step`
 - `fix(wsl): correct mirrored networking config`
 - `refactor(setup)!: drop legacy firewall rules`
 - `docs: update local deployment section`

#### Branch naming format:
```text
<type>/<slug>
<type>/<scope-or-id>/<slug>
```

*Where:*
 - `<type>`         — one of the prefixes listed above.
 - `/<scope-or-id>` — optional part, alphanumeric/`-`.
 - `/<slug>`        — short description, alphanumeric/`_`/`-`.

*Valid branch examples:*
 - `feat/add-helm-bootstrap`
 - `fix/ssh-service-startup`
 - `chore/bump-k3d-version`
 - `feat/GOTEC-404/expose-registry-port`

> Exceptions: `dev`, `main`, `master`.

</details>

----
