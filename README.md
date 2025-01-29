# Talos Scripts

A script for generating a Talos configuration and bootstrapping a kubernetes cluster:

Creates and bootstraps a cluster with desired extensions installed and patches applied. With the schematic provided, this will install the [Tailscale](https://github.com/siderolabs/extensions/tree/main/network/tailscale),[iscsi-tools](https://github.com/siderolabs/extensions/tree/main/storage/iscsi-tools), and [util-linux-tools](https://github.com/siderolabs/extensions/tree/main/tools/util-linux) extensions. You can modify [schematic.yaml](schematic.yaml) to suit your extension needs. 

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
Once the cluster is bootstrapped, add additional control plane nodes:
```
talosctl apply-config -f controlplane.yaml --insecure -n <node-ip>
```

Add worker nodes:
```
talosctl apply-config -f worker.yaml --insecure -n <node-ip>
```
#### Installing Longhorn
You can install [Longhorn](https://longhorn.io) with the following:

1. Apply the necessary Longhorn mounts (run this command on each node):
```
talosctl patch machineconfig -p @longhorn-mounts.yaml -n <node-ip>
```

2. Create longhorn namespace and add pod security labels:
```
kubectl create ns longhorn-system && kubectl label namespace longhorn-system pod-security.kubernetes.io/enforce=privileged
```

3. Install Longhorn and Longhorn pod security policies:
```
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.2/deploy/longhorn.yaml && kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/podsecuritypolicy.yaml
```

4. Verify longhorn was installed:
```
kubectl get pods \
--namespace longhorn-system \
--watch
```

The ouput should look like this:
```
NAME                                                READY   STATUS    RESTARTS   AGE
longhorn-ui-b7c844b49-w25g5                         1/1     Running   0          2m41s
longhorn-manager-pzgsp                              1/1     Running   0          2m41s
longhorn-driver-deployer-6bd59c9f76-lqczw           1/1     Running   0          2m41s
longhorn-csi-plugin-mbwqz                           2/2     Running   0          100s
csi-snapshotter-588457fcdf-22bqp                    1/1     Running   0          100s
csi-snapshotter-588457fcdf-2wd6g                    1/1     Running   0          100s
csi-provisioner-869bdc4b79-mzrwf                    1/1     Running   0          101s
csi-provisioner-869bdc4b79-klgfm                    1/1     Running   0          101s
csi-resizer-6d8cf5f99f-fd2ck                        1/1     Running   0          101s
csi-provisioner-869bdc4b79-j46rx                    1/1     Running   0          101s
csi-snapshotter-588457fcdf-bvjdt                    1/1     Running   0          100s
csi-resizer-6d8cf5f99f-68cw7                        1/1     Running   0          101s
csi-attacher-7bf4b7f996-df8v6                       1/1     Running   0          101s
csi-attacher-7bf4b7f996-g9cwc                       1/1     Running   0          101s
csi-attacher-7bf4b7f996-8l9sw                       1/1     Running   0          101s
csi-resizer-6d8cf5f99f-smdjw                        1/1     Running   0          101s
instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc   1/1     Running   0          114s
engine-image-ei-df38d2e5-cv6nc   
```
