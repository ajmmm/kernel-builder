# builder

Shell entrypoints for building kernels, Golang RPMs, and local Linux trees, plus
automation for bringing up a Fedora cloud dev VM on Parallels.

## Entry Points

- `build_kernel.sh` builds `kernel-ajm` RPMs for Enterprise Linux sources.
- `build_golang.sh` builds `golang-ajm` RPMs for Enterprise Linux sources.
- `build_linux.sh` builds and optionally installs a Linux kernel from a source tree.
- `build_vm.sh` manages a Fedora cloud dev VM on Parallels for local development.

## Layout

- `config/` contains shared, non-distro-specific configuration such as Parallels defaults and generic kernel configs.
- `lib/build.sh` contains shared RPM build helpers used by the build entrypoints.
- `lib/vm.sh` contains shared helpers for the Parallels/cloud-init workflow.
- `<target>/vm.conf` contains target-specific VM defaults.
- `<target>/cloud-init/` contains target-specific `user-data` and `meta-data`.

## VM Workflow

The VM automation is intentionally split between:

- `prlctl` for VM lifecycle
- `cloud-init` for guest bootstrapping
- `build_vm.sh` as the repo entrypoint

Typical flow:

```bash
./build_vm.sh --target fc43/fedora image
./build_vm.sh --target fc43/fedora seed
./build_vm.sh --target fc43/fedora create
./build_vm.sh --target fc43/fedora boot
./build_vm.sh --target fc43/fedora ssh-config
```

Or all at once:

```bash
make up
```

The default VM target is `fc43/fedora`, backed by [fc43/fedora/vm.conf](/Users/almcwill/Develop/builder/fc43/fedora/vm.conf), [fc43/fedora/cloud-init/user-data](/Users/almcwill/Develop/builder/fc43/fedora/cloud-init/user-data), and [fc43/fedora/cloud-init/meta-data](/Users/almcwill/Develop/builder/fc43/fedora/cloud-init/meta-data). Add another target by creating a new repo-relative target path such as `fc43/minimal/` or `fc44/fedora/`, then pass `--target` or set `VM_TARGET`.
