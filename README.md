# @monadiam/devbox

WSL2 devbox for running the local MonadIAM `k3s` stand on a Windows machine.

----

<details>
<summary><strong>Local Deployment</strong></summary>

1. Run PowerShell as Administrator.

2. Create and edit local config:

```powershell
copy .env.example .env
notepad .env
```

3. Provision WSL:

```powershell
.\setup.ps1
```

On first install, finish Linux user setup in the Ubuntu window. The script waits and continues automatically.

4. Restart WSL:

```powershell
wsl --shutdown
```

5. Verify from WSL:

```sh
docker info
k3d version
kubectl version --client
helm version --short
systemctl status ssh
```

</details>

----

<details>
<summary><strong>What It Configures</strong></summary>

| Area          | Description                                            |
|:--------------|:-------------------------------------------------------|
| WSL2          | CPU, memory, swap, mirrored networking, systemd.       |
| Linux         | Base packages, Docker, k3d, kubectl, Helm, SSH server. |
| Network       | IPv4 DNS precedence and Windows firewall rules.        |
| Remote access | SSH endpoint for connecting from another machine.      |

</details>

----
