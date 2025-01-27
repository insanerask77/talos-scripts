# Talos Scripts

A collection of scripts for managing creating and managing a [Talos](https://talos.dev) linux cluster.

## [gen-cluster.sh](gen-cluster.sh)
Creates and bootstraps a cluster with desired extensions installed and patches applied. With the schematic provided, this will install the [Tailscale](https://github.com/siderolabs/extensions/tree/main/network/tailscale) and [iscsi-tools](https://github.com/siderolabs/extensions/tree/main/storage/iscsi-tools) extensions. You can modify [schematic.yaml](schematic.yaml) to suit your extension needs. 

#### Prerequisites
You will need a node booted to the [Talos ISO](https://www.talos.dev/v1.9/introduction/getting-started/#acquire-the-talos-linux-image-and-boot-machines). This can be a virtual machine or a physical machine. Ensure you have network access to this node. 

#### Usage
If using the Tailscale extension, you will need to generate a Tailscale [authkey](https://tailscale.com/kb/1085/auth-keys) and add it to the extension-config.yaml file. You can do this easily with the following commands. Replace enter-your-authkey-here with your authkey. Ensure you include *tskey-auth*.

```
MY_AUTHKEY=enter-your-authkey-here
cp EXAMPLE-extension-config.yaml extension-config.yaml && sed -i -e s/placeholder/$MY_AUTHKEY/ extension-config.yaml
```

You will also need to modify the network-config.yaml file with your desired virtual IP:

```
MY_VIP=enter-your-vip-here
cp EXAMPLE-network-config.yaml network-config.yaml && sed -i -e s/placeholder/$MY_VIP/ network-config.yaml
```

Ensure the script is executable:
```
chmod +x ./gen-cluster.sh
```

Then, run the script

```
gen-cluster.sh
```
