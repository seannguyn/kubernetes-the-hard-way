# Provision Infrastructure on AWS

## Virtual Machines (VMs) specification

This tutorial requires four (4) VMs running Debian 12 (bookworm) ARM64.

The following table list the four machines and thier CPU, memory, and storage requirements.

| Name    | Description            | CPU | RAM   | Storage |
|---------|------------------------|-----|-------|---------|
| jumpbox | Administration host    | 1   | 1GB   | 10GB    |
| server  | Kubernetes server      | 1   | 2GB   | 20GB    |
| node-0  | Kubernetes worker node | 1   | 2GB   | 20GB    |
| node-1  | Kubernetes worker node | 1   | 2GB   | 20GB    |

## Architecture
![infrastructure][infrastructure]

## Infrastructure Provisioning Steps

Infrastructure is provisioned by IaC tool `terraform`. All infrastructure code is stored in directory `aws/`.

1. Clone github repository:

```bash
git clone --depth 1 \
  https://github.com/kelseyhightower/kubernetes-the-hard-way.git
```

2. Configure your AWS credentials.

```bash
aws configure
```

3. Provision infrastructure on AWS.

```bash
make up
```

4. Once you have all four machine provisioned, verify the system requirements

```bash
make verify-vm
```

You should see the following output:

```text
jumpbox: #1 SMP Debian 6.1.119-1 (2024-11-22) aarch64 GNU/Linux
server:  #1 SMP Debian 6.1.119-1 (2024-11-22) aarch64 GNU/Linux
node0:   #1 SMP Debian 6.1.119-1 (2024-11-22) aarch64 GNU/Linux
node1:   #1 SMP Debian 6.1.119-1 (2024-11-22) aarch64 GNU/Linux
```

You maybe surprised to see `aarch64` here, but that is the official name for the Arm Architecture 64-bit instruction set. You will often see `arm64` used by Apple, and the maintainers of the Linux kernel, when referring to support for `aarch64`. This tutorial will use `arm64` consistently throughout to avoid confusion.

Next: [setting-up-the-jumpbox](02-jumpbox.md)

[infrastructure]: ../assets/infrastructure.drawio.png