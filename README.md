# k8s-cluster-setup

This repository provides automated scripts to install and configure a Kubernetes cluster on **CentOS Stream 9** using **kubeadm**, **containerd**, and **Calico CNI**.

---

## 🧩 Project Structure

```bash
k8s-cluster-setup/
├── install_k8s_master.sh   # Script for initializing the control-plane (master) node
├── install_k8s_worker.sh   # Script for joining worker nodes to the cluster
├── LICENSE                 # Project license (MIT)
└── README.md               # This file
```

## 🚀 Features
* Installs Kubernetes v1.33.0 on CentOS Stream 9
* Uses containerd as the container runtime
* Configures system settings (sysctl, SELinux, swap, kernel modules)
* Initializes the control-plane with `kubeadm`
* Sets up Calico for networking
* Automatically generates join scripts for control-plane and worker nodes

## ⚙️ Prerequisites

* CentOS Stream 9 (minimal install recommended)
* Root or sudo access
* Internet connectivity (for package and image downloads)

## 📦 Installation

**On the Control Plane Node**

```bash
chmod +x install_k8s_master.sh
sudo ./install_k8s_master.sh
```

This script will:

* Install required packages and configure system settings
* Initialize the cluster with `kubeadm`
* Apply the Calico CNI
* Remove the NoSchedule taint so pods can run on the master (optional)
* Create `setup_k8s_control_plane.sh` and `setup_k8s_worker.sh` join scripts

**On Worker Nodes**

After running the master script, copy and run the generated setup_k8s_worker.sh on each worker node:

```bash
chmod +x setup_k8s_worker.sh
sudo ./setup_k8s_worker.sh
```

## 📄 License
This project is licensed under the [MIT License](LICENSE).