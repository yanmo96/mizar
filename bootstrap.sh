#!/bin/bash

logout_needed=false

function install-dev-packages {
  echo ""
  echo "Installing dev packages ..."
  sudo apt-get update -y
  sudo apt-get install -y \
    build-essential \
    clang-7 \
    llvm-7 \
    libelf-dev \
    libcmocka-dev \
    lcov \
    scapy \
    pkg-config
}

function install-python {
  echo ""
  echo "Installing python3 dependencies ..."
  sudo apt-get update -y
  sudo apt-get install -y \
    python3-pip \
    python3-apt
}

function install-python-ubuntu-18 {
  echo ""
  echo "Installing python3 dependencies for ubuntu 18.04 ..."

  sudo apt-get update -y
  sudo apt-get install -y \
    python3.7 \
    python3.7-dev

  # kopf no longer available in python3.6 via pip
  sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
  sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.7 2
  sudo update-alternatives --set python3 /usr/bin/python3.7
  # Fix for apt-pkg missing when using python3.7
  sudo ln -s /usr/lib/python3/dist-packages/apt_pkg.cpython-36m-x86_64-linux-gnu.so /usr/lib/python3/dist-packages/apt_pkg.so
}

function install-go-for-mizar {
  echo ""
  echo "Installing go 1.13.9 ..."
  wget -O /tmp/go1.13.9.linux-amd64.tar.gz https://dl.google.com/go/go1.13.9.linux-amd64.tar.gz
  sudo tar -C /usr/local -xzf /tmp/go1.13.9.linux-amd64.tar.gz
  rm -rf /tmp/go1.13.9.linux-amd64.tar.gz
  export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
  cat ~/.profile | grep "PATH" | egrep "/usr/local/go/bin"
  if [ $? -ne 0 ]; then
    echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.profile
    source ~/.profile
  fi
  logout_needed=true
}

function install-docker {
  echo ""
  echo "Installing docker ..."
  sudo apt-get update -y
  sudo apt-get install -y docker.io
  sudo systemctl unmask docker.service
  sudo systemctl unmask docker.socket
  cat /etc/group | grep docker | grep ${USER} &> /dev/null
  if [ $? -ne 0 ]; then
    sudo usermod -aG docker ${USER}
    logout_needed=true
  fi
  sudo systemctl enable docker
  sudo systemctl restart docker
}

function install-kubectl {
  echo ""
  echo "Installing kubectl ..."
  curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x ./kubectl
  sudo mv ./kubectl /usr/local/bin/kubectl
}

function install-kind {
  echo ""
  echo "Installing kind ..."
  pushd /tmp
  ver=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
  curl -Lo kind "https://github.com/kubernetes-sigs/kind/releases/download/$ver/kind-$(uname)-amd64"
  chmod +x kind
  sudo mv kind /usr/local/bin
  popd
}

function install-protobuf-and-pip-deps {
  echo ""
  echo "Installing protobuf dependencies ..."
  sudo apt-get update -y
  sudo apt-get install -y protobuf-compiler libprotobuf-dev
  GO111MODULE="on" go get google.golang.org/protobuf/cmd/protoc-gen-go@v1.26
  GO111MODULE="on" go get google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.1
  GO111MODULE="on" go get github.com/smartystreets/goconvey@v1.6.4
  sudo python3 -m pip install --upgrade pip
  sudo -H pip3 install --upgrade --ignore-installed PyYAML
  sudo pip3 install --upgrade setuptools netaddr docker scapy kubernetes
  sudo pip3 install --upgrade grpcio grpcio-tools
}

# Main bootstrap script
tput setaf 1
echo "NOTE: This script will reboot the system if you opt to allow kernel update."
echo "      If reboot is not required, it will log you out and require re-login for new permissions to take effect."
echo ""
read -n 1 -s -r -p "Press Ctrl-c to quit, any key to continue..."
tput sgr0
echo " "

# Install dev packages
install-dev-packages

# Install python
install-python
cat /etc/os-release | grep VERSION_ID | grep "18.04"
if [ $? -eq 0 ]; then
  install-python-ubuntu-18
fi

# Install go
which go
if [ $? -ne 0 ]; then
  install-go-for-mizar
else
  go_ver=$(go version | go version | awk '{print $3}')
  if [[ "${go_ver}" != "go1.13.9" ]]; then
    install-go-for-mizar
  fi
fi

# Install docker
which docker
if [ $? -ne 0 ]; then
  install-docker
fi

# Install kind
which kind
if [ $? -ne 0 ]; then
  install-kind
fi

# Install kubectl
which kubectl
if [ $? -ne 0 ]; then
  install-kubectl
fi

git submodule update --init --recursive

# Install protobuf dependecies
install-protobuf-and-pip-deps

# Install kernel needed for Mizar (if required)
source ${PWD}/kernelupdate.sh

if [ "$logout_needed" = true ]; then
  PPPID=$(awk '{print $4}' "/proc/$PPID/stat")
  kill $PPPID
fi
