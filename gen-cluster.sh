#!/bin/bash

TALOS_VERSION="v1.9.2"

if [ -f ./controlplane.yaml ] || [ -f ./worker.yaml ] || [ -f ./talosconfig ]; then
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
        SCHEMATIC=$(curl -sX POST --data-binary @schematic.yaml https://factory.talos.dev/schematics)
        SCHEMATIC=$(echo "$SCHEMATIC" | jq '.id' | tr -d '"')
        talosctl gen config $CLUSTER_NAME https://$NODE_IP:6443 --install-image=factory.talos.dev/installer/$SCHEMATIC:$TALOS_VERSION

        # Append extension-config.yaml (tailscale config) to controlplane.yaml
        cat controlplane.yaml extension-config.yaml > temp.txt
        mv temp.txt controlplane.yaml -f

        # Append extension-config.yaml (tailscale config) to worker.yaml
        cat worker.yaml extension-config.yaml > temp.txt
        mv temp.txt worker.yaml -f

        # Replace machine network config with network-config.yaml contents
        sed -i '/network: {}/r network-config.yaml' controlplane.yaml && sed -i '/network: {}/d' controlplane.yaml

        # Replace endpoint string with VIP in worker.yaml
        sed -i -E "s/(endpoint: https:\/\/)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:6443)/\1$VIP\2/" controlplane.yaml
        sed -i -E "s/(endpoint: https:\/\/)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:6443)/\1$VIP\2/" worker.yaml

        # Apply config, bootstrap the cluster and retrieve kubeconfig
        talosctl apply-config -f controlplane.yaml --insecure -n $NODE_IP -e $NODE_IP
        
        #########################
        # BOOTSTRAP THE CLUSTER #
        #########################

        TIMEOUT=180 # Set the timeout in seconds (e.g., 5 minutes)
        INTERVAL=5 # Interval between retries in seconds
        START_TIME=$(date +%s)
        while true; do
            if nc -z -w5 $NODE_IP 50000; then
                echo
                echo "Cluster ready! Bootstrapping and retrieving kubeconfig..."
                talosctl bootstrap -n $NODE_IP -e $NODE_IP --talosconfig=./talosconfig
                talosctl kubeconfig -n $NODE_IP -e $NODE_IP --talosconfig=./talosconfig
                break
            else
                echo "Cluster not ready for bootstrap. Will continue to retry until timeout..."
            fi
            
            sleep $INTERVAL

            # Check if timeout has been reached
            CURRENT_TIME=$(date +%s)
            ELAPSED=$((CURRENT_TIME - START_TIME))
            if [ $ELAPSED -ge $TIMEOUT ]; then
                echo "Timeout reached while checking connection to cluster. Unable to bootstrap. Try running -- talosctl bootstrap -n $NODE_IP -e $NODE_IP --talosconfig=./talosconfig"
                break
            fi
        done
    else
        echo
        echo "No connection to node. Exiting script..."
        exit 1
    fi

echo "Cluster deployed. Try running -- kubectl get nodes"

else
    echo "Exiting script..."
    exit 1
fi