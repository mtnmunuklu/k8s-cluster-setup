#!/bin/bash

# Kubernetes 1.33.0 installation and control-plane setup on CentOS Stream 9

RED="\e[31m"
GREEN="\e[32m"
ENDCOLOR="\e[0m"

echo -e "${GREEN}Starting Kubernetes v1.33.0 setup...${ENDCOLOR}"

# 0. Reset Kubernetes and remove configs
sudo kubeadm reset -f
sudo systemctl stop kubelet
sudo systemctl stop containerd
sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/cni /opt/cni /var/lib/cni /var/run/kubernetes ~/.kube
sudo ip link delete cni0 || true
sudo ip link delete flannel.1 || true
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

# 1. Add Kubernetes repo
echo -e "${GREEN}Adding Kubernetes repository...${ENDCOLOR}"
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
EOF

# 2. SELinux permissive
echo -e "${GREEN}Setting SELinux to permissive mode...${ENDCOLOR}"
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# 3. Disable swap
echo -e "${GREEN}Disabling swap...${ENDCOLOR}"
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo swapoff -a

# 4. Load kernel modules
echo -e "${GREEN}Loading required kernel modules...${ENDCOLOR}"
sudo modprobe overlay
sudo modprobe br_netfilter
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

# 5. Apply sysctl settings
echo -e "${GREEN}Applying sysctl settings for Kubernetes...${ENDCOLOR}"
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# 6. Install containerd
echo -e "${GREEN}Installing containerd...${ENDCOLOR}"
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 7. Install Kubernetes components
echo -e "${GREEN}Installing kubelet, kubeadm, and kubectl (v1.33.0)...${ENDCOLOR}"
sudo dnf install -y kubelet-1.33.0 kubeadm-1.33.0 kubectl-1.33.0
sudo systemctl enable --now kubelet

# 8. Configure firewall (optional)
if ! systemctl is-active --quiet firewalld; then
  echo -e "${GREEN}Installing and starting firewalld...${ENDCOLOR}"
  sudo dnf install -y firewalld
  sudo systemctl enable --now firewalld
fi

echo -e "${GREEN}Configuring firewall rules...${ENDCOLOR}"
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=10251/tcp
sudo firewall-cmd --permanent --add-port=10252/tcp
sudo firewall-cmd --reload

# 9. Pull Kubernetes control plane images
echo -e "${GREEN}Pulling Kubernetes control plane images...${ENDCOLOR}"
sudo kubeadm config images pull --cri-socket unix:///run/containerd/containerd.sock --kubernetes-version v1.33.0

# 10. Initialize Kubernetes cluster
echo -e "${GREEN}Initializing Kubernetes cluster...${ENDCOLOR}"
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --upload-certs \
  --kubernetes-version=v1.33.0 \
  --control-plane-endpoint=$(hostname) \
  --ignore-preflight-errors=all \
  --cri-socket=unix:///run/containerd/containerd.sock

# 11. Configure kubectl for current user
echo -e "${GREEN}Configuring kubectl access for local user...${ENDCOLOR}"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
echo "export KUBECONFIG=\$HOME/.kube/config" >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config

# 12. Apply Calico CNI
echo -e "${GREEN}Applying Calico CNI...${ENDCOLOR}"
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

# 13. Remove taint from control-plane node
echo -e "${GREEN}Removing NoSchedule taint from control-plane node...${ENDCOLOR}"
kubectl taint nodes $(hostname) node-role.kubernetes.io/control-plane:NoSchedule- || true

# 14. Label node as control-plane
echo -e "${GREEN}Labeling node as control-plane...${ENDCOLOR}"
kubectl label nodes $(hostname -s) "kubernetes.io/role=control-plane" --overwrite

# 15. Generate join commands
echo -e "${GREEN}Generating kubeadm join command and certificate key...${ENDCOLOR}"
JOINCOMMAND=$(kubeadm token create --print-join-command)
CERTIFICATEKEY=$(kubeadm init phase upload-certs --upload-certs | grep -v -e "certificate" -e "Namespace")

# 16. Create join scripts
echo -e "${GREEN}Creating control plane join script...${ENDCOLOR}"
cat <<EOF | sudo tee setup_k8s_control_plane.sh
#!/bin/bash
${JOINCOMMAND} --control-plane --certificate-key ${CERTIFICATEKEY} \
  --node-name \$(hostname -s)
EOF
chmod +x setup_k8s_control_plane.sh

echo -e "${GREEN}Creating worker node join script...${ENDCOLOR}"
cat <<EOF | sudo tee setup_k8s_worker.sh
#!/bin/bash
${JOINCOMMAND} \
  --node-name \$(hostname -s)
EOF
chmod +x setup_k8s_worker.sh

echo -e "${GREEN}Kubernetes control plane setup complete!${ENDCOLOR}"
echo -e "${GREEN}Use the generated scripts to join additional nodes.${ENDCOLOR}"