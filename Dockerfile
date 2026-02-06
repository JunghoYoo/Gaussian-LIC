# Base image: Ubuntu 20.04 (Required for ROS Noetic) + CUDA 12.8
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu20.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# ---------------------------------------------------------
# 1. Install Basic Tools & ROS Noetic
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    curl \
    gnupg2 \
    lsb-release \
    tzdata \
    git \
    build-essential \
    cmake \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Add ROS Noetic sources and keys
RUN sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list' && \
    curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | apt-key add -

# Install ROS Noetic Desktop Full
RUN apt-get update && apt-get install -y \
    ros-noetic-desktop-full \
    python3-rosdep \
    python3-rosinstall \
    python3-rosinstall-generator \
    python3-wstool \
    python3-catkin-tools \
    && rm -rf /var/lib/apt/lists/*

RUN rosdep init && rosdep update
RUN echo "source /opt/ros/noetic/setup.bash" >> /root/.bashrc

# ---------------------------------------------------------
# 2. Build OpenCV 4.10.0 (RTX 5090 / CUDA 12.8 Optimized)
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    pkg-config \
    libjpeg-dev libpng-dev libtiff-dev \
    libavcodec-dev libavformat-dev libswscale-dev libv4l-dev \
    libxvidcore-dev libx264-dev \
    python3-dev python3-pip python3-numpy \
    libeigen3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN wget -O opencv.tar.gz https://github.com/opencv/opencv/archive/refs/tags/4.10.0.tar.gz && \
    tar -zxvf opencv.tar.gz && rm opencv.tar.gz && \
    wget -O opencv_contrib.tar.gz https://github.com/opencv/opencv_contrib/archive/refs/tags/4.10.0.tar.gz && \
    tar -zxvf opencv_contrib.tar.gz && rm opencv_contrib.tar.gz

WORKDIR /tmp/opencv-4.10.0/build
RUN cmake -D CMAKE_BUILD_TYPE=RELEASE \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D OPENCV_EXTRA_MODULES_PATH=/tmp/opencv_contrib-4.10.0/modules \
    -D WITH_CUDA=ON \
    -D WITH_CUDNN=ON \
    -D OPENCV_DNN_CUDA=ON \
    -D ENABLE_FAST_MATH=1 \
    -D CUDA_FAST_MATH=1 \
    -D WITH_CUBLAS=1 \
    -D BUILD_opencv_python3=ON \
    -D BUILD_opencv_python2=OFF \
    -D PYTHON3_EXECUTABLE=$(which python3) \
    -D CUDA_ARCH_BIN=10.0 \
    .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    rm -rf /tmp/opencv-4.10.0 /tmp/opencv_contrib-4.10.0

# ---------------------------------------------------------
# 3. Install Livox SDK (Prerequisite for livox_ros_driver)
# ---------------------------------------------------------
WORKDIR /root/Software
RUN git clone https://github.com/Livox-SDK/Livox-SDK.git && \
    cd Livox-SDK && \
    mkdir -p build && cd build && \
    cmake .. && \
    make -j$(nproc) && \
    make install

# ---------------------------------------------------------
# 4. Install Ceres, Glog, Gflags, SuiteSparse
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    libceres-dev \
    libgoogle-glog-dev \
    libgflags-dev \
    libatlas-base-dev \
    libsuitesparse-dev \
    libflann-dev \
    libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# 5. Build PCL 1.13.0 (Required by Coco-LIC)
# ---------------------------------------------------------
WORKDIR /root/Software
RUN wget https://github.com/PointCloudLibrary/pcl/archive/refs/tags/pcl-1.13.0.tar.gz && \
    tar -zxvf pcl-1.13.0.tar.gz && rm pcl-1.13.0.tar.gz && \
    cd pcl-pcl-1.13.0 && \
    mkdir build && cd build && \
    cmake -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/root/Software/pcl_1.13 \
        -D PCL_QT_VERSION=5 \
        -D WITH_QT=OFF \
        -D WITH_OPENGL=OFF \
        -D WITH_VTK=ON \
        -D WITH_LIBUSB=OFF \
        -D WITH_PCAP=OFF \
        -D BUILD_TESTS=OFF \
        -D BUILD_EXAMPLES=OFF \
        .. && \
    make -j$(nproc) && \
    make install 

# ---------------------------------------------------------
# 6. Install LibTorch (PyTorch C++ Nightly for CUDA 12.x)
# ---------------------------------------------------------
WORKDIR /root/Software
RUN wget -O libtorch-cxx11-abi-shared-with-deps-2.7.0+cu128.zip "https://download.pytorch.org/libtorch/cu128/libtorch-cxx11-abi-shared-with-deps-2.7.0%2Bcu128.zip" && \
    unzip libtorch-cxx11-abi-shared-with-deps-2.7.0+cu128.zip && \
    rm libtorch-cxx11-abi-shared-with-deps-2.7.0+cu128.zip

# Set ENV so CMake can find LibTorch automatically in subsequent steps
#ENV CMAKE_PREFIX_PATH="/root/Software/libtorch:${CMAKE_PREFIX_PATH}"

# ---------------------------------------------------------
# 7. Setup 'catkin_coco' (Coco-LIC + Drivers)
# ---------------------------------------------------------
WORKDIR /root/catkin_coco/src

RUN git clone https://github.com/Livox-SDK/livox_ros_driver.git && \
    git clone https://github.com/APRIL-ZJU/Coco-LIC.git && \
    git clone -b 1.7.4 https://github.com/ros-perception/perception_pcl.git

WORKDIR /root/catkin_coco

# RUN /bin/bash -c "source /opt/ros/noetic/setup.bash && \
#                   catkin_make -DCMAKE_PREFIX_PATH='/opt/ros/noetic;/root/Software/libtorch;/root/Software/pcl_1.13'"

# ---------------------------------------------------------
# 8. Setup 'catkin_gaussian' (Gaussian-LIC)
# ---------------------------------------------------------
WORKDIR /root/catkin_gaussian/src
RUN git clone https://github.com/APRIL-ZJU/Gaussian-LIC.git

WORKDIR /root/catkin_gaussian
# We must source catkin_coco so Gaussian-LIC can find livox_ros_driver
# RUN /bin/bash -c "source /opt/ros/noetic/setup.bash && \
#                   source /root/catkin_coco/devel/setup.bash && \
#                   catkin_make -DCMAKE_PREFIX_PATH='/opt/ros/noetic;/root/Software/libtorch'"

# ---------------------------------------------------------
# 9. Final Entrypoint
# ---------------------------------------------------------
RUN echo "source /root/catkin_coco/devel/setup.bash" >> /root/.bashrc
RUN echo "source /root/catkin_gaussian/devel/setup.bash" >> /root/.bashrc

CMD ["bash"]