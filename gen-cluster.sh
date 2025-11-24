#!/bin/bash

TALOS_VERSION="v1.9.2"

if [ -f _out/controlplane.yaml ] || [ -f _out/worker.yaml ] || [ -f ./talosconfig ]; then
    echo "ERROR: Existing configuration detected. 
          
Please remove the following files or work out of a different directory:
        
- controlplane.yaml
- worker.yaml
- talosconfig"
    exit 1
fi

while [[ ! -n $CLUSTER_NAME ]]
do
    read -p "Enter a cluster name: " CLUSTER_NAME
done

while [[ ! -n $NODE_IP ]]
do
    read -p "Enter your first node's IP Address: " NODE_IP
done


while [[ ! -n $VIP ]]
do
    read -p "Enter your cluster's Virtual IP Address: " VIP
done

echo
echo "Is this correct?
Cluster Name: $CLUSTER_NAME
First Node IP: $NODE_IP
VIP: $VIP"
echo
read -p "Y/N: " RESPONSE

if [[ "$RESPONSE" == "Y" ]];then

    echo
    echo "Testing connection to node, please wait..."
    echo
    
    if ping -c 4 $NODE_IP; then
    
        # Get schematic ID and generate initial config file
        echo "Fetching schematic ID from factory.talos.dev..."
        SCHEMATIC=$(curl -sX POST --data-binary @schematic.yaml https://factory.talos.dev/schematics)
        SCHEMATIC=$(echo "$SCHEMATIC" | jq '.id' | tr -d '"')
        echo "Schematic ID: $SCHEMATIC"
        
        echo "Generating Talos configuration..."
        talosctl gen config $CLUSTER_NAME https://$NODE_IP:6443 --output-dir _out --install-image=factory.talos.dev/installer/$SCHEMATIC:$TALOS_VERSION
        # Replace VIP placeholder in network-config.yaml BEFORE injecting it
        echo "Preparing network configuration with VIP: $VIP"
        sed "s/placeholder/$VIP/" network-config.yaml > network-config-temp.yaml

        # Add VIP network config to controlplane.yaml
        echo "Injecting network configuration into controlplane.yaml..."
        sed -i '/network: {}/r network-config-temp.yaml' _out/controlplane.yaml && sed -i '/network: {}/d' _out/controlplane.yaml
        rm -f network-config-temp.yaml

        # Note: Longhorn mounts will be applied via talosctl patch after bootstrap
        # This is the recommended approach to avoid sed complexity with YAML structure

        # Apply config to the first node
        echo "Applying configuration to node $NODE_IP..."
        talosctl apply-config -f _out/controlplane.yaml --insecure -n $NODE_IP -e $NODE_IP 
        
        #########################
        # BOOTSTRAP THE CLUSTER #
        #########################
        
        echo "Waiting for Talos API to become available..."
        TIMEOUT=300 # Set the timeout in seconds (5 minutes)
        INTERVAL=5 # Interval between retries in seconds
        START_TIME=$(date +%s)
        
        # Wait for apid to be ready (port 50000)
        while true; do
            if nc -z -w5 $NODE_IP 50000; then
                echo "Talos API is responding on port 50000"
                break
            else
                echo "Waiting for Talos API to become available..."
            fi
            
            sleep $INTERVAL

            # Check if timeout has been reached
            CURRENT_TIME=$(date +%s)
            ELAPSED=$((CURRENT_TIME - START_TIME))
            if [ $ELAPSED -ge $TIMEOUT ]; then
                echo "ERROR: Timeout reached waiting for Talos API. The node may not have applied the configuration correctly."
                echo "Try manually running: talosctl bootstrap -n $NODE_IP -e $VIP --talosconfig=_out/talosconfig"
                exit 1
            fi
        done

        # Additional wait to ensure etcd is ready
        echo "Waiting additional time for etcd to initialize..."
        sleep 10

        # Bootstrap the cluster
        echo "Bootstrapping the cluster..."
        if talosctl bootstrap -n $NODE_IP -e $NODE_IP --talosconfig=_out/talosconfig; then
            echo "Bootstrap successful!"
        else
            echo "WARNING: Bootstrap command failed. This may be normal if the cluster is already bootstrapped."
        fi

        # Wait for Kubernetes API to become available
        echo "Waiting for Kubernetes API to become available..."
        START_TIME=$(date +%s)
        while true; do
            if nc -z -w5 $NODE_IP 6443; then
                echo "Kubernetes API is responding on node $NODE_IP:6443"
                break
            fi
            
            sleep $INTERVAL

            CURRENT_TIME=$(date +%s)
            ELAPSED=$((CURRENT_TIME - START_TIME))
            if [ $ELAPSED -ge $TIMEOUT ]; then
                echo "WARNING: Timeout reached waiting for Kubernetes API on VIP."
                echo "The VIP may take additional time to become active after etcd elections complete."
                break
            fi
        done

        # Retrieve kubeconfig
        echo "Retrieving kubeconfig..."
        if talosctl kubeconfig -n $NODE_IP -e $NODE_IP --talosconfig=_out/talosconfig; then
            echo "Kubeconfig retrieved successfully!"
        else
            echo "WARNING: Failed to retrieve kubeconfig. You may need to wait and try manually:"
            echo "talosctl kubeconfig -n $NODE_IP -e $NODE_IP --talosconfig=_out/talosconfig"
        fi

        # Apply Longhorn mounts patch
        echo
        echo "Applying Longhorn mounts configuration..."
        if talosctl patch machineconfig -p @longhorn-mounts.yaml -n $NODE_IP -e $NODE_IP --talosconfig=_out/talosconfig; then
            echo "✓ Longhorn mounts applied successfully"
        else
            echo "WARNING: Failed to apply Longhorn mounts. You can apply manually with:"
            echo "talosctl patch machineconfig -p @longhorn-mounts.yaml -n $NODE_IP -e $NODE_IP --talosconfig=_out/talosconfig"
        fi

        echo
        echo "=========================================="
        echo "Cluster deployment complete!"
        echo "=========================================="
        echo "Cluster Name: $CLUSTER_NAME"
        echo "Node IP: $NODE_IP"
        echo "VIP: $VIP"
        echo
        echo "Next steps:"
        echo "1. Verify nodes are ready: kubectl get nodes"
        echo "2. Run post-install script for Longhorn, MetalLB, etc.: bash post-install.sh"
        echo
        
    else
        echo
        echo "No connection to node. Exiting script..."
        exit 1
    fi

else
    echo "Exiting script..."
    exit 1
fi