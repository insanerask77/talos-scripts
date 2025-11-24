# Talos Cluster Automation Scripts

Automated deployment scripts for Talos Linux clusters with VIP, Longhorn storage, MetalLB, Traefik, and Tailscale support.

Based on the guide: [Deploy Talos Linux with Local VIP, Tailscale, Longhorn, MetalLB and Traefik](https://notes.joshrnoll.com/notes/deploy-talos-linux-with-local-vip-tailscale-longhorn-metallb-and-traefik/)

## Features

- ✅ Automated Talos cluster deployment with Virtual IP (VIP)
- ✅ Custom system extensions (iSCSI tools, util-linux-tools, Tailscale)
- ✅ Longhorn storage mounts pre-configured
- ✅ Proper bootstrap timing and error handling
- ✅ Post-installation automation for Longhorn, MetalLB, Traefik, and Tailscale

## Prerequisites

1. **Install talosctl**:
   ```bash
   # macOS
   brew install siderolabs/tap/talosctl
   
   # Linux
   curl -sL https://talos.dev/install | sh
   ```

2. **Boot VM(s) to Talos ISO**: Follow the [Talos Getting Started Guide](https://www.talos.dev/v1.9/introduction/getting-started/)

3. **Network Planning**:
   - Decide on a cluster name (e.g., `talos-cluster`)
   - Choose a VIP address in the same subnet as your nodes (e.g., `10.0.30.25`)
   - Note the IP address of your first node (e.g., `192.168.18.49`)

## Quick Start

### 1. Clone and Configure

```bash
git clone <this-repo>
cd talos-scripts
```

### 2. Review Configuration Files

**schematic.yaml** - System extensions to include:
```yaml
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/iscsi-tools
            - siderolabs/util-linux-tools
            - siderolabs/tailscale
```

**network-config.yaml** - Network configuration template:
```yaml
    network:
        interfaces:
            - deviceSelector:
                physical: true
              dhcp: true
              vip:
                ip: placeholder
```

**longhorn-mounts.yaml** - Longhorn storage mounts:
```yaml
machine:
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
```

### 3. Deploy Cluster

```bash
# Make sure no existing configs exist
rm -f controlplane.yaml worker.yaml talosconfig

# Run the deployment script
bash gen-cluster.sh
```

The script will:
1. Prompt for cluster name, node IP, and VIP
2. Fetch the schematic ID from factory.talos.dev
3. Generate Talos configurations with the VIP as the endpoint
4. Inject network configuration with your VIP
5. Add Longhorn mounts to both controlplane and worker configs
6. Apply the configuration to your first node
7. Wait for Talos API to become available
8. Bootstrap the cluster
9. Wait for Kubernetes API on the VIP
10. Retrieve and configure kubeconfig

### 4. Verify Deployment

```bash
# Check cluster nodes
kubectl get nodes

# Check all pods
kubectl get pods -A
```

### 5. Post-Installation (Optional)

Run the post-installation script to install additional components:

```bash
bash post-install.sh
```

This interactive script will guide you through installing:
- **Longhorn**: Distributed block storage
- **MetalLB**: Load balancer for bare metal
- **Traefik**: Ingress controller
- **Tailscale Operator**: VPN integration

## What Was Fixed

The original script had several critical issues that have been resolved:

### 1. YAML Parsing Error
**Problem**: VIP placeholder was replaced AFTER config was applied, causing "control characters are not allowed" error.

**Solution**: 
- Changed `talosctl gen config` to use VIP directly as endpoint
- VIP placeholder in `network-config.yaml` is replaced BEFORE injection
- Uses temporary file to avoid sed issues

### 2. Missing Longhorn Mounts
**Problem**: Longhorn mount configuration was commented out and never applied.

**Solution**: Uncommented and properly integrated Longhorn mounts into both controlplane and worker configs.

### 3. Bootstrap Timing Issues
**Problem**: Script tried to bootstrap before cluster was ready, causing certificate errors.

**Solution**:
- Added proper waiting for Talos API (port 50000)
- Added additional wait time for etcd initialization
- Added waiting for Kubernetes API on VIP
- Better error handling with informative messages

### 4. Certificate Authentication Errors
**Problem**: Bootstrap happened too early, before certificates were properly generated.

**Solution**: 
- Increased timeout to 5 minutes
- Added explicit wait for etcd readiness
- Proper error messages for troubleshooting

## File Structure

```
talos-scripts/
├── gen-cluster.sh           # Main cluster deployment script
├── post-install.sh          # Post-installation automation
├── schematic.yaml           # System extensions configuration
├── network-config.yaml      # VIP network configuration template
├── longhorn-mounts.yaml     # Longhorn storage mounts
└── README.md               # This file
```

## Troubleshooting

### Cluster Bootstrap Fails

If bootstrap fails, you can manually retry:

```bash
talosctl bootstrap -n <NODE_IP> -e <NODE_IP> --talosconfig=./talosconfig
```

### VIP Not Responding

The VIP requires etcd to be running and elections to complete. This can take a few minutes after bootstrap. Wait and check:

```bash
# Check if VIP is responding
ping <VIP>

# Check etcd status
talosctl -n <NODE_IP> service etcd status
```

### Kubeconfig Retrieval Fails

If kubeconfig retrieval fails, wait a bit and retry manually:

```bash
talosctl kubeconfig -n <NODE_IP> -e <VIP> --talosconfig=./talosconfig
```

### Longhorn Pods Not Starting

Ensure the Longhorn mounts were applied correctly:

```bash
# Check node configuration
talosctl -n <NODE_IP> get machineconfig -o yaml | grep -A 10 longhorn

# Verify mounts on the node
talosctl -n <NODE_IP> ls /var/lib/longhorn
```

### MetalLB Not Assigning IPs

Ensure you've created the IPAddressPool and L2Advertisement:

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

## Adding Additional Nodes

After the first node is deployed, you can add more nodes:

### Control Plane Nodes

```bash
talosctl apply-config -f controlplane.yaml --insecure -n <NEW_NODE_IP>
```

### Worker Nodes

```bash
talosctl apply-config -f worker.yaml --insecure -n <NEW_NODE_IP>
```

## Advanced Configuration

### Custom Talos Version

Edit `gen-cluster.sh` and change:

```bash
TALOS_VERSION="v1.9.2"  # Change to desired version
```

### Additional System Extensions

Edit `schematic.yaml` and add extensions:

```yaml
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/iscsi-tools
            - siderolabs/util-linux-tools
            - siderolabs/tailscale
            - siderolabs/your-extension  # Add here
```

Then regenerate the schematic ID.

## Resources

- [Talos Linux Documentation](https://www.talos.dev/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)

## Contributing

Feel free to submit issues and enhancement requests!

## License

MIT License - Feel free to use and modify as needed.
