# Positron on Slurm

## Purpose

The LG Gram uses the separate [`YONGHUNI/positron-slurm`](https://github.com/YONGHUNI/positron-slurm) repository to run the Positron Remote SSH backend, Python console, and Native Notebook kernels **inside a Slurm allocation** on UGA Sapelo2.

The Nix configuration pins that repository as a flake input and exposes three commands through Home Manager:

```text
positron-slurm-start
positron-slurm-tunnel
positron-slurm-stop
```

The normal path is:

```text
Gram
  → positron-slurm-start
  → one persistent SSH ControlMaster to Sapelo
  → sbatch
  → Slurm-selected compute node
  → job-local sshd inside the Slurm cgroup
  → local 127.0.0.1:22022 forward
  → Positron Remote SSH target: sapelo-slurm
  → positron-server / kcserver / Python kernel
```

The important property is that Positron is not attached to a normal compute-node SSH session outside Slurm. The job-local `sshd` is started by the batch job itself, so processes launched through Positron inherit the Slurm job cgroup and resource restrictions.

## Nix-managed configuration

The Home Manager integration is defined in `home/positron-slurm.nix`. It installs the helper commands and generates `~/.config/positron-slurm/config` with the current defaults:

```bash
LOGIN_TARGET="sapelo"
SHARED_DIR="/work/whlab/ys01849/.positron-slurm"
LOCAL_PORT=22022
PARTITION="inter_p"
```

The SSH targets are part of the normal Nix-managed `~/.ssh/config`:

```text
sapelo        → sapelo2.gacrc.uga.edu
sapelo-slurm  → 127.0.0.1:22022
```

`sapelo-slurm` is intentionally a localhost target. The helper creates the tunnel from that fixed local endpoint to the dynamically allocated compute node and job-local SSH port.

## Updating the helper

The `positron-slurm` repository is pinned by `flake.lock`. After updating that repository:

```bash
cd ~/nix-config
nix flake update positron-slurm
sudo nixos-rebuild switch --flake .#gram
```

Inspect the pinned revision with:

```bash
nix flake metadata --json \
  | jq -r '.locks.nodes["positron-slurm"].locked.rev'
```

Because `nix flake update positron-slurm` modifies `flake.lock`, commit the updated lock file after testing.

## `positron-slurm-start`

Start a default session from any local directory:

```bash
positron-slurm-start
```

| Resource | Default |
| --- | --- |
| Partition | `inter_p` |
| Tasks | 1 |
| CPUs per task | 4 |
| Memory | 16 GiB |
| Wall time | 4 hours |
| GPU | none |

A successful launch looks similar to:

```text
Submitted Positron Slurm job 48850834
Waiting for endpoint...
Job 48850834: RUNNING
HOST=c4-16
PORT=30834
JOB=48850834
Positron Slurm tunnel ready
LOCAL=127.0.0.1:22022
REMOTE=c4-16:30834
JOB=48850834

Connect Positron to SSH target: sapelo-slurm
```

The compute node is chosen by Slurm. A hostname such as `c4-16` or `rb7-12` is discovered after allocation; it is not hard-coded by the helper.

After the command finishes, connect in Positron with `Remote SSH → sapelo-slurm`.

### Custom CPU and memory resources

Normal `sbatch` options can be passed directly to `positron-slurm-start`:

```bash
positron-slurm-start \
  --cpus-per-task=8 \
  --mem=32G \
  --time=08:00:00
```

To choose another partition:

```bash
positron-slurm-start \
  --partition=batch \
  --cpus-per-task=8 \
  --mem=32G \
  --time=08:00:00
```

If a partition is supplied on the command line, it replaces the configured default `inter_p`.

### GPU example: `hu_p`, two GPUs

A tested two-GPU Hu-lab session is:

```bash
positron-slurm-start \
  --partition=hu_p \
  --nodes=1 \
  --gres=gpu:2 \
  --cpus-per-task=8 \
  --mem=64G \
  --time=01:00:00
```

One observed allocation was:

```text
HOST=rb7-12
Partition=hu_p
NumCPUs=8
AllocTRES=cpu=8,mem=64G,node=1,billing=8,gres/gpu=2,gres/gpu:l40s=2
```

Verify GPU allocation from the Positron terminal:

```bash
hostname
echo "JOB=$SLURM_JOB_ID"
scontrol show job "$SLURM_JOB_ID" | \
  grep -oE 'Partition=[^ ]+|NumNodes=[^ ]+|NumCPUs=[^ ]+|AllocTRES=[^ ]+|TresPerNode=[^ ]+'
nvidia-smi -L
```

With PyTorch installed in the project Pixi environment, a Native Notebook can verify visibility:

```python
import os
import torch

print("CUDA_VISIBLE_DEVICES:", os.environ.get("CUDA_VISIBLE_DEVICES"))
print("CUDA available:", torch.cuda.is_available())
print("GPU count:", torch.cuda.device_count())

for i in range(torch.cuda.device_count()):
    props = torch.cuda.get_device_properties(i)
    print(i, torch.cuda.get_device_name(i), props.total_memory / 1024**3, "GiB")
```

## `positron-slurm-tunnel`

`positron-slurm-start` normally creates the tunnel automatically. If the Slurm session is already alive but the local tunnel needs to be recreated:

```bash
positron-slurm-tunnel
```

The command reads `/work/whlab/ys01849/.positron-slurm/current`, which contains values such as:

```text
HOST=rb7-12
PORT=35998
JOB=48855998
```

and forwards:

```text
127.0.0.1:22022
    ↓
Sapelo login connection
    ↓
rb7-12:35998
```

If the same tunnel is already active, the command reports that it is ready instead of creating a duplicate.

## `positron-slurm-stop`

End the current session with:

```bash
positron-slurm-stop
```

It reads the current Slurm job ID, runs `scancel`, closes the Sapelo ControlMaster and its forwarding rule, and removes local cached state. Use this instead of leaving the allocation running after closing Positron.

## Verify that Positron is inside Slurm

Inside a Positron remote terminal:

```bash
hostname
echo "$SLURM_JOB_ID"
cat /proc/$$/cgroup
```

For the batch-based launcher, a healthy cgroup looks like:

```text
0::/system.slice/slurmstepd.scope/job_48850834/step_batch/user/task_0
```

Inspect Slurm's view of the allocation with:

```bash
sacct -j "$SLURM_JOB_ID" \
  --format=JobID,Partition,State,Elapsed,Timelimit,NCPUS,ReqMem,AllocTRES
```

### CPU affinity from Python

`os.cpu_count()` may report the node-wide logical CPU count. Use the affinity mask for CPUs actually available to the process:

```python
import os

print("Node-visible CPU count:", os.cpu_count())
print("Allocated CPU count:", len(os.sched_getaffinity(0)))
print("Allowed CPUs:", sorted(os.sched_getaffinity(0)))
print("SLURM_CPUS_PER_TASK:", os.environ.get("SLURM_CPUS_PER_TASK"))
```

A tested 4-CPU allocation returned `Cpus_allowed_list: 8,20,22,24`.

### Verify worker processes

For a running Python or multiprocessing workload:

```bash
ps -u "$USER" -o pid,ppid,psr,pcpu,pmem,cmd \
  --sort=-pcpu | head -20
```

Then inspect selected notebook/worker PIDs:

```bash
for pid in PID1 PID2 PID3 PID4; do
    echo "=== PID $pid ==="
    cat /proc/$pid/cgroup
    grep Cpus_allowed_list /proc/$pid/status
done
```

All workers should remain in the same Slurm job cgroup and share the Slurm-assigned CPU set.

### Native Notebook check

```python
import os
import pathlib
import socket
import sys

print("Python:", sys.executable)
print("Host:", socket.gethostname())
print("Job:", os.environ.get("SLURM_JOB_ID"))
print("Cgroup:", pathlib.Path("/proc/self/cgroup").read_text().strip())
```

The interpreter should be the selected project/Pixi Python, the host should be the allocated compute node, and the job/cgroup should match the submitted Slurm job.

## ControlMaster behavior

Sapelo has occasionally shown unreliable or repeated login/authentication behavior. The helpers therefore keep one explicit SSH ControlMaster at:

```text
~/.cache/positron-slurm/login-master.sock
```

The same authenticated connection is reused for `sbatch`, `squeue` polling, endpoint discovery, local port forwarding, and `scancel`. This is independent of the normal SSH configuration's default ControlMaster policy.

## Runtime state

Shared state on Sapelo:

```text
/work/whlab/ys01849/.positron-slurm/
├── current
├── ssh_host_ed25519_key
├── slurm-<job>.out
└── slurm-<job>.err
```

Node-local SSH runtime:

```text
/lscratch/ys01849/positron-sshd/<job-id>/
├── sshd_config
├── sshd.log
└── sshd.pid
```

Local Gram state:

```text
~/.cache/positron-slurm/
├── login-master.sock
└── current
```

## Pixi and rootless Nix

`positron-slurm` manages Slurm/SSH/Positron transport, not project dependencies. Project Python/R/CUDA dependencies remain project-local in Pixi/Nix environments. Rootless Nix on Sapelo is maintained separately.

## Current limitation and future cleanup

The fixed endpoint `sapelo-slurm → 127.0.0.1:22022` is currently a compatibility layer because every Slurm allocation gets a dynamic compute-node host and job-local SSH port.

Future simplification is tracked in [`YONGHUNI/positron-slurm` issue #1](https://github.com/YONGHUNI/positron-slurm/issues/1). The plan is to revisit direct system-OpenSSH routing after Positron's native OpenSSH transport reaches the stable/Nix installation path and is validated with Sapelo authentication.

Until then, keep the working ControlMaster plus localhost-forward architecture.

## Troubleshooting

### `sbatch` is not found

The helper deliberately runs Slurm commands through a remote login shell. Manual check:

```bash
ssh sapelo 'bash -lc "command -v sbatch"'
```

### Job stays pending

```bash
ssh sapelo 'bash -lc "squeue -u $USER"'
```

A GPU or large-memory request may remain pending until suitable resources become available.

### Local port 22022 is already in use

```bash
ss -ltnp | grep ':22022'
positron-slurm-stop
```

Then start a fresh session.

### Positron reaches the wrong machine

```bash
hostname
echo "$SLURM_JOB_ID"
cat /proc/$$/cgroup
```

The host must be a compute node and the cgroup must contain the expected Slurm job ID.

### Positron server data

The tested Slurm setup uses `/work/whlab/ys01849/.positron-server-slurm`, kept separate from login-node Positron server state.
