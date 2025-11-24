#!/bin/bash

# Post-installation script for Talos cluster
# Automates installation of Longhorn, MetalLB, and Traefik

set -e  # Exit on error

echo "=========================================="
echo "Talos Cluster Post-Installation Script"
echo "=========================================="
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster. Please ensure kubeconfig is set correctly."
    exit 1
fi

echo "✓ Cluster connection verified"
echo

#########################
# INSTALL LONGHORN      #
#########################

read -p "Install Longhorn storage? (Y/N): " INSTALL_LONGHORN
if [[ "$INSTALL_LONGHORN" == "Y" ]]; then
    echo
    echo "Installing Longhorn..."
    
    # Create namespace and add pod security labels
    echo "Creating longhorn-system namespace..."
    kubectl create ns longhorn-system 2>/dev/null || echo "Namespace already exists"
    kubectl label namespace longhorn-system pod-security.kubernetes.io/enforce=privileged --overwrite
    
    # Install Longhorn
    echo "Applying Longhorn manifests..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.2/deploy/longhorn.yaml
    
    # Apply pod security policies
    echo "Applying Longhorn pod security policies..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/podsecuritypolicy.yaml
    
    echo "✓ Longhorn installation initiated"
    echo "  Monitor with: kubectl get pods --namespace longhorn-system --watch"
    echo
fi

#########################
# INSTALL METALLB       #
#########################

read -p "Install MetalLB load balancer? (Y/N): " INSTALL_METALLB
if [[ "$INSTALL_METALLB" == "Y" ]]; then
    echo
    echo "Installing MetalLB..."
    
    # Install MetalLB
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
    
    echo "✓ MetalLB installed"
    echo
    echo "You need to configure MetalLB with an IP address pool."
    echo "Example configuration (save as metallb-config.yaml):"
    echo
    cat << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.30.200-10.0.30.220  # Change this to your IP range
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - lab-pool
EOF
    echo
    read -p "Do you want to create this config now? (Y/N): " CREATE_METALLB_CONFIG
    if [[ "$CREATE_METALLB_CONFIG" == "Y" ]]; then
        read -p "Enter IP address range (e.g., 10.0.30.200-10.0.30.220): " IP_RANGE
        
        cat > metallb-config.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
  - $IP_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - lab-pool
EOF
        
        kubectl apply -f metallb-config.yaml
        echo "✓ MetalLB configured with IP range: $IP_RANGE"
    else
        echo "  Apply manually with: kubectl apply -f metallb-config.yaml"
    fi
    echo
fi

#########################
# INSTALL TRAEFIK       #
#########################

read -p "Install Traefik ingress controller? (Y/N): " INSTALL_TRAEFIK
if [[ "$INSTALL_TRAEFIK" == "Y" ]]; then
    echo
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        echo "WARNING: helm not found. Traefik installation requires Helm."
        echo "Install Helm from: https://helm.sh/docs/intro/install/"
        echo "Skipping Traefik installation..."
    else
        echo "Installing Traefik..."
        
        # Add Traefik helm repo
        helm repo add traefik https://helm.traefik.io/traefik
        helm repo update
        
        # Create traefik namespace
        kubectl create namespace traefik 2>/dev/null || echo "Namespace already exists"
        
        echo
        echo "Traefik can be configured with various options."
        echo "A basic installation will be performed. For advanced configuration,"
        echo "create a values.yaml file and install with:"
        echo "  helm install traefik traefik/traefik -n traefik -f values.yaml"
        echo
        
        read -p "Proceed with basic Traefik installation? (Y/N): " PROCEED_TRAEFIK
        if [[ "$PROCEED_TRAEFIK" == "Y" ]]; then
            # Basic Traefik installation
            helm install traefik traefik/traefik \
                --namespace traefik \
                --set "ports.web.redirectTo.port=websecure" \
                --set "service.type=LoadBalancer"
            
            echo "✓ Traefik installed"
            echo "  Check status with: kubectl get pods -n traefik"
            echo "  Get LoadBalancer IP: kubectl get svc -n traefik"
        fi
    fi
    echo
fi

echo "=========================================="
echo "Post-installation complete!"
echo "=========================================="
echo
echo "Useful commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  kubectl get svc -A"
echo
echo "For Longhorn UI access, you may want to set up an ingress or port-forward:"
echo "  kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
echo
