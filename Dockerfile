FROM ubuntu:22.04

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# ── Base tools ────────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg2 \
    lsb-release \
    software-properties-common \
    build-essential \
    cmake \
    git \
    ca-certificates \
    wget \
    libeigen3-dev \
    libpcl-dev \
    nlohmann-json3-dev \
    tmux \
    python3-pip \
    python3-yaml \
    && rm -rf /var/lib/apt/lists/*

# ── ROS 2 Humble ─────────────────────────────────────────────────────────────
# glass-lio is developed on Jazzy; it builds on Humble like the other ROS 2
# benchmarks. Packages follow glass-lio's package.xml.
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
    http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/ros2.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-desktop \
    ros-humble-tf2-ros \
    ros-humble-pcl-conversions \
    ros-humble-eigen3-cmake-module \
    ros-humble-rosbag2-cpp \
    ros-humble-rosbag2-storage-default-plugins \
    python3-colcon-common-extensions \
    && rm -rf /var/lib/apt/lists/*

# ── rosbags (used to convert ROS 1 bags to ROS 2, if needed) ─────────────────
RUN pip3 install --no-cache-dir "rosbags==0.9.22"

# ── Build colcon workspace (glass-lio + converter) ───────────────────────────
WORKDIR /ros2_ws

# src/glass-lio includes its glass_core submodule (the estimation engine).
COPY ./src/glass-lio              ./src/glass-lio
COPY ./src/glass-lio-to-hdmapping ./src/glass-lio-to-hdmapping

# Preflight check used by the run script.
COPY ./overlay/scripts/ /ros2_ws/scripts/

# Build glass-lio (without its unit tests) and the converter. The final guard
# fails the image build loudly if an executable is missing.
RUN source /opt/ros/humble/setup.bash && \
    colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF && \
    test -f /ros2_ws/install/glasslio/lib/glasslio/glasslio_node && \
    test -f /ros2_ws/install/glass_lio_to_hdmapping/lib/glass_lio_to_hdmapping/listener && \
    test -f /ros2_ws/install/glass_lio_to_hdmapping/lib/glass_lio_to_hdmapping/livox_format_bridge && \
    echo "[build] glasslio_node, converter and livox_format_bridge present"

# ── Non-root user ─────────────────────────────────────────────────────────────
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID ros && \
    useradd -m -u $UID -g $GID -s /bin/bash ros && \
    chown -R $UID:$GID /ros2_ws

RUN echo "source /opt/ros/humble/setup.bash"   >> /root/.bashrc && \
    echo "source /ros2_ws/install/setup.bash"  >> /root/.bashrc && \
    echo "source /opt/ros/humble/setup.bash"   >> /home/ros/.bashrc && \
    echo "source /ros2_ws/install/setup.bash"  >> /home/ros/.bashrc

CMD ["bash"]
