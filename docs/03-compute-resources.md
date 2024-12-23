# Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. In this lab you will provision the machines required for setting up a Kubernetes cluster.

## Machine Database

This tutorial will leverage a text file, which will serve as a machine database, to store the various machine attributes that will be used when setting up the Kubernetes control plane and worker nodes. The following schema represents entries in the machine database, one entry per line:

```text
IPV4_ADDRESS FQDN HOSTNAME POD_SUBNET
```

Each of the columns corresponds to a machine IP address `IPV4_ADDRESS`, fully qualified domain name `FQDN`, host name `HOSTNAME`, and the IP subnet `POD_SUBNET`. Kubernetes assigns one IP address per `pod` and the `POD_SUBNET` represents the unique IP address range assigned to each machine in the cluster for doing so.

Here is an example machine database similar to the one used when creating this tutorial. Notice the IP addresses have been masked out. Your machines can be assigned any IP address as long as each machine is reachable from each other and the `jumpbox`.

```bash
cat machines.txt
```

```text
XXX.XXX.XXX.XXX server.kubernetes.local server
XXX.XXX.XXX.XXX node-0.kubernetes.local node-0 10.200.0.0/24
XXX.XXX.XXX.XXX node-1.kubernetes.local node-1 10.200.1.0/24
```

Now it's your turn to create a `machines.txt` file with the details for the three machines you will be using to create your Kubernetes cluster. Use the example machine database from above and add the details for your machines.

Run these commands to find out about nodes private IP
```bash
echo "server private IP:  $(terraform -chdir=aws output -raw server_private_ip)"  && \
echo "node0 private IP:   $(terraform -chdir=aws output -raw node0_private_ip)"   && \
echo "node1 private IP:   $(terraform -chdir=aws output -raw node1_private_ip)"
```

## Configuring SSH Access

SSH will be used to configure the machines in the cluster. Verify that you have `root` SSH access to each machine listed in your machine database. You may need to enable root SSH access on each node by updating the sshd_config file and restarting the SSH server.

### Enable root SSH Access

As mentioned earlier, we are going to enable `root` access over SSH in order to streamline the steps in this tutorial. Security is a tradeoff, and in this case, we are optimizing for convenience.

Enabling `root` SSH access for `jumpbox`, `server`, `node0`, and `node1` is done in `main.tf`.

Populate `/root/.ssh/known_hosts` on `jumphost`

```bash
while read IP FQDN HOST SUBNET; do
  ssh-keyscan -t ed25519 ${IP} >> /root/.ssh/known_hosts
done < machines.txt
```

Verify SSH public key access is working:

```bash
while read IP FQDN HOST SUBNET; do
  printf "${HOST}: ";
  ssh -n root@${IP} uname -o -m
done < machines.txt
```

```text
server: aarch64 GNU/Linux
node-0: aarch64 GNU/Linux
node-1: aarch64 GNU/Linux
```

## Hostnames

In this section you will assign hostnames to the `server`, `node-0`, and `node-1` machines. The hostname will be used when executing commands from the `jumpbox` to each machine. The hostname also plays a major role within the cluster. Instead of Kubernetes clients using an IP address to issue commands to the Kubernetes API server, those clients will use the `server` hostname instead. Hostnames are also used by each worker machine, `node-0` and `node-1` when registering with a given Kubernetes cluster.

To configure the hostname for each machine, run the following commands on the `jumpbox`.

Set the hostname on each machine listed in the `machines.txt` file:

```bash
while read IP FQDN HOST SUBNET; do
    CMD="sed -i 's/^127.0.0.1.*/127.0.0.1\t${FQDN} ${HOST}/' /etc/hosts"
    ssh -n root@${IP} "$CMD"
    ssh -n root@${IP} hostnamectl hostname ${HOST}
done < machines.txt
```

Verify the hostname is set on each machine:

```bash
while read IP FQDN HOST SUBNET; do
  ssh -n root@${IP} hostname --fqdn
done < machines.txt
```

```text
server.kubernetes.local
node-0.kubernetes.local
node-1.kubernetes.local
```

## Host Lookup Table

In this section you will generate a `hosts` file which will be appended to `/etc/hosts` file on `jumpbox` and to the `/etc/hosts` files on all three cluster members used for this tutorial. This will allow each machine to be reachable using a hostname such as `server`, `node-0`, or `node-1`.

Create a new `hosts` then append a host entry for each machine in the `machines.txt`:

```bash
echo "" > hosts
echo "# Kubernetes The Hard Way" >> hosts
while read IP FQDN HOST SUBNET; do
    ENTRY="${IP} ${FQDN} ${HOST}"
    echo $ENTRY >> hosts
done < machines.txt
```

Review the host entries in the `hosts` file:

```bash
cat hosts
```

```text

# Kubernetes The Hard Way
XXX.XXX.XXX.XXX server.kubernetes.local server
XXX.XXX.XXX.XXX node-0.kubernetes.local node-0
XXX.XXX.XXX.XXX node-1.kubernetes.local node-1
```

## Adding `/etc/hosts` Entries To A Local Machine

In this section you will append the DNS entries from the `hosts` file to the local `/etc/hosts` file on your `jumpbox` machine.

Append the DNS entries from `hosts` to `/etc/hosts`:

```bash
cat hosts >> /etc/hosts
```

Verify that the `/etc/hosts` file has been updated:

```bash
cat /etc/hosts
```

```text
127.0.0.1       localhost
127.0.1.1       jumpbox

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters



# Kubernetes The Hard Way
XXX.XXX.XXX.XXX server.kubernetes.local server
XXX.XXX.XXX.XXX node-0.kubernetes.local node-0
XXX.XXX.XXX.XXX node-1.kubernetes.local node-1
```

At this point you should be able to SSH to each machine listed in the `machines.txt` file using a hostname.

Append entry to `known_hosts` on `jumpbox`
```bash
for host in server node-0 node-1
  do ssh-keyscan -t ed25519 ${host} >> /root/.ssh/known_hosts
done
```

```bash
for host in server node-0 node-1
   do ssh root@${host} uname -o -m -n
done
```

```text
server aarch64 GNU/Linux
node-0 aarch64 GNU/Linux
node-1 aarch64 GNU/Linux
```

## Adding `/etc/hosts` Entries To The Remote Machines

In this section you will append the host entries from `hosts` to `/etc/hosts` on each machine listed in the `machines.txt` text file.

Copy the `hosts` file to each machine and append the contents to `/etc/hosts`:

```bash
while read IP FQDN HOST SUBNET; do
  scp hosts root@${HOST}:~/
  ssh -n \
    root@${HOST} "cat hosts >> /etc/hosts"
done < machines.txt
```

At this point hostnames can be used when connecting to machines from your `jumpbox` machine, or any of the three machines in the Kubernetes cluster. Instead of using IP addresses you can now connect to machines using a hostname such as `server`, `node-0`, or `node-1`.

Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)
