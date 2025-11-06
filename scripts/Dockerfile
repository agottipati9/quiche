FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    lsb-release \
    software-properties-common \
    git \
    wget \
    gpg \
    ca-certificates \
    python3 \
    python3-pip \
    cmake \
    # mahimahi dependencies
    build-essential \
    protobuf-compiler \
    libprotobuf-dev \
    autotools-dev \
    iptables \
    iproute2 \
    dh-autoreconf \
    pkg-config \
    dnsmasq-base \
    apache2-bin \
    apache2-dev \
    debhelper \
    libssl-dev \
    ssl-cert \
    libxcb-present-dev \
    libcairo2-dev \
    libpango1.0-dev \
    # Added dependencies for Bazel
    curl \
    gnupg \
    apt-transport-https \
    clang \
    libicu-dev \
    lld \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Bazel
RUN curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /usr/share/keyrings/bazel-archive-keyring.gpg && \
    # Add Bazel source list
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
    # Update again after adding new repo
    apt-get update && \
    # Install the specific Bazel version you listed
    apt-get install -y bazel-8.2.1 && \
    ln -s /usr/bin/bazel-8.2.1 /usr/bin/bazel && \
    # === Clean Up ===
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create a non-root user 'appuser' and add its local bin to the PATH
RUN useradd -m -s /bin/bash appuser
ENV HOME=/home/appuser
ENV PATH="$HOME/.local/bin:$PATH"

# Set up the working directory and give ownership to the new user
RUN mkdir -p /opt/ && chown -R appuser:appuser /opt/

RUN pip3 install \
    --break-system-packages \
    mysql-connector-python \
    fire \
    openai \
    pandas \
    numpy \
    tqdm

# Install Quiche
WORKDIR ${HOME}
RUN git clone --recursive https://github.com/agottipati9/quiche && \
    cd quiche && \
    CC=clang bazel build -c opt //...

WORKDIR ${HOME}
RUN git clone https://github.com/ravinet/mahimahi && \
    cd mahimahi && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install 

WORKDIR ${HOME}