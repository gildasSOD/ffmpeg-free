#!/usr/bin/env bash
# 2019 Michael de Gans

set -e

# change default constants here:
readonly PREFIX=/usr/local  # install prefix, (can be ~/.local for a user install)
readonly DEFAULT_VERSION=4.13.0  # controls the default version (gets reset by the first argument)
readonly CPUS=1  #$(nproc)  # controls the number of jobs

# better board detection. if it has 6 or more cpus, it probably has a ton of ram too
if [[ $CPUS -gt 5 ]]; then
    # something with a ton of ram
    JOBS=$CPUS
else
    JOBS=1  # you can set this to 4 if you have a swap file
    # otherwise a Nano will choke towards the end of the build
fi

cleanup () {
# https://stackoverflow.com/questions/226703/how-do-i-prompt-for-yes-no-cancel-input-in-a-linux-shell-script
    while true ; do
        echo "Do you wish to remove temporary build files in /tmp/build_opencv ? "
        if ! [[ "$1" -eq "--test-warning" ]] ; then
            echo "(Doing so may make running tests on the build later impossible)"
        fi
        read -p "Y/N " yn
        case ${yn} in
            [Yy]* ) rm -rf /tmp/build_opencv ; break;;
            [Nn]* ) exit ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

setup () {
    cd /tmp
    if [[ -d "build_opencv" ]] ; then
        echo "It appears an existing build exists in /tmp/build_opencv"
        cleanup
    fi
    mkdir build_opencv
    cd build_opencv
}

git_source () {
    echo "Getting version '$1' of OpenCV"
    git clone --depth 1 --branch "$1" https://github.com/opencv/opencv.git
    git clone --depth 1 --branch "$1" https://github.com/opencv/opencv_contrib.git
}

install_dependencies () {
    # open-cv has a lot of dependencies, but most can be found in the default
    # package repository or should already be installed (eg. CUDA).
    echo "Installing build dependencies."
    sudo apt-get update
    sudo apt-get dist-upgrade -y --autoremove
    sudo apt-get install -y \
        build-essential \
        cmake \
        git \
        gfortran \
        libatlas-base-dev \
        libavcodec-dev \
        libavformat-dev \
        libcanberra-gtk3-module \
        libdc1394-dev \
        libeigen3-dev \
        libglew-dev \
        libgstreamer-plugins-base1.0-dev \
        libgstreamer-plugins-good1.0-dev \
        libgstreamer1.0-dev \
        libgtk-3-dev \
        libjpeg-dev \
        libjpeg8-dev \
        libjpeg-turbo8-dev \
        liblapack-dev \
        liblapacke-dev \
        libopenblas-dev \
        libpng-dev \
        libpostproc-dev \
        libswscale-dev \
        libtbb-dev \
        libtbb2 \
        libtesseract-dev \
        libtiff-dev \
        libv4l-dev \
        libxine2-dev \
        libxvidcore-dev \
        libx264-dev \
        pkg-config \
        python2-dev python2 python-dev-is-python3\
        python3-dev \
        python3-numpy \
        python3-matplotlib \
        qv4l2 \
        v4l-utils \
        zlib1g-dev

    sudo apt-get install -y libgtkglext1-dev qtbase5-dev libglu1-mesa-dev mesa-common-dev libglew-dev
    
    # python -m pip install --upgrade pip
    # pip install tensorflow
    # pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126 #cuda version 12.6 >nvidia-smi
    # pip install --upgrade setuptools


    # # install nv codec
    # sudo apt-get install make git
    # mkdir -p $HOME/nv-codec-headers_build && cd $HOME/nv-codec-headers_build
    # git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    # cd nv-codec-headers
    # make && sudo make install

}

configure () {



    local CMAKEFLAGS="
        -D BUILD_EXAMPLES=OFF
        -D BUILD_opencv_python3=ON
        -D CMAKE_BUILD_TYPE=RELEASE
        -D CMAKE_INSTALL_PREFIX=${PREFIX}
        -D CUDA_ARCH_BIN=8.7
        -D CUDA_ARCH_PTX=
        -D CUDA_FAST_MATH=ON
        -D CUDNN_VERSION='9.3.0.75'
        -D EIGEN_INCLUDE_PATH=/usr/include/eigen3 
        -D OPENCV_DNN_CUDA=ON
        -D OPENCV_ENABLE_NONFREE=ON
        -D OPENCV_EXTRA_MODULES_PATH=/tmp/build_opencv/opencv_contrib/modules
        -D OPENCV_GENERATE_PKGCONFIG=ON
        -D WITH_CUBLAS=ON
        -D WITH_CUDA=ON
        -D WITH_CUDNN=ON
        -D WITH_GSTREAMER=ON
        -D WITH_LIBV4L=ON
        -D WITH_OPENGL=ON
        -D WITH_NVCUVID=ON
        -D HAVE_NVCUVID=OFF"



    # local CMAKEFLAGS="
    #     -D BUILD_EXAMPLES=OFF
    #     -D BUILD_opencv_python2=ON
    #     -D BUILD_opencv_python3=ON
    #     -D CMAKE_BUILD_TYPE=RELEASE
    #     -D CMAKE_INSTALL_PREFIX=${PREFIX}
    #     -D CUDA_ARCH_BIN=8.7
    #     -D CUDA_ARCH_PTX=
    #     -D CUDA_FAST_MATH=ON
    #     -D CUDNN_VERSION='9.3.0.75'
    #     -D EIGEN_INCLUDE_PATH=/usr/include/eigen3 
    #     -D ENABLE_NEON=ON
    #     -D OPENCV_DNN_CUDA=ON
    #     -D OPENCV_ENABLE_NONFREE=ON
    #     -D OPENCV_EXTRA_MODULES_PATH=/tmp/build_opencv/opencv_contrib/modules
    #     -D OPENCV_GENERATE_PKGCONFIG=ON
    #     -D WITH_CUBLAS=ON
    #     -D WITH_CUDA=ON
    #     -D WITH_CUDNN=ON
    #     -D WITH_GSTREAMER=ON
    #     -D WITH_LIBV4L=ON
    #     -D WITH_OPENGL=ON"






        # -D CUDNN_VERSION=$(python -c "import tensorflow as tf; print(tf.config.list_physical_devices('GPU'))")
        # -D PYTHON3_EXECUTABLE=$(which python)
        # -D PYTHON3_INCLUDE_DIR=$(python -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())")
        # -D PYTHON3_NUMPY_INCLUDE_DIRS=$(python -c "import numpy; print(numpy.get_include())")
        # -D PYTHON3_PACKAGES_PATH=$(python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")

    if [[ "$1" != "test" ]] ; then
        CMAKEFLAGS="
        ${CMAKEFLAGS}
        -D BUILD_PERF_TESTS=OFF
        -D BUILD_TESTS=OFF"
    fi

    echo "cmake flags: ${CMAKEFLAGS}"

    cd opencv
    mkdir build
    cd build
    cmake ${CMAKEFLAGS} .. 2>&1 | tee -a configure.log
}

main () {

    local VER=${DEFAULT_VERSION}

    # parse arguments
    if [[ "$#" -gt 0 ]] ; then
        VER="$1"  # override the version
    fi

    if [[ "$#" -gt 1 ]] && [[ "$2" == "test" ]] ; then
        DO_TEST=1
    fi

    # prepare for the build:
    setup
    # install_dependencies
    git_source ${VER}

    if [[ ${DO_TEST} ]] ; then
        configure test
    else
        configure
    fi

    # start the build
    make -j${JOBS} 2>&1 | tee -a build.log

    if [[ ${DO_TEST} ]] ; then
        make test 2>&1 | tee -a test.log
    fi

    # avoid a sudo make install (and root owned files in ~) if $PREFIX is writable
    if [[ -w ${PREFIX} ]] ; then
        make install 2>&1 | tee -a install.log
    else
        sudo make install 2>&1 | tee -a install.log
    fi

    cleanup --test-warning

    # include libs to environment
    # sudo /bin/bash -c 'echo "/usr/local/lib" >> /etc/ld.so.conf.d/opencv.conf'
    sudo echo "${PREFIX}/lib" >> /etc/ld.so.conf.d/opencv.conf
    sudo ldconfig -v

}

main "$@"
