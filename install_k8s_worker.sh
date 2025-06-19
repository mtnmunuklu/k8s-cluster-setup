#!/bin/bash

# Kubernetes 1.33.0 Worker Node Installation Script

GREEN="\e[32m"
ENDCOLOR="\e[0m"

echo -e "${GREEN}Starting Kubernetes v1.33.0 installation (Worker Node)...${ENDCOLOR}"

# 1. Add Kubernetes repository
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
EOF

# 2. Set SELinux to permissive and disable swap
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo swapoff -a

# 3. Load kernel modules and apply sysctl settings
sudo modprobe overlay
sudo modprobe br_netfilter
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# 4. Install containerd
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 5. Install Kubernetes components
sudo dnf install -y kubelet-1.33.0 kubeadm-1.33.0 kubectl-1.33.0
sudo systemctl enable --now kubelet

echo -e "${GREEN}Kubernetes worker node installation completed successfully.${ENDCOLOR}"
echo -e "${GREEN}To join this node to the cluster, run the kubeadm join command provided by the control-plane node.${ENDCOLOR}"
