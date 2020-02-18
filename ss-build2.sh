#!/bin/sh

###############
# config area #
###############
ANDROID_NDK_VERSION=r20b
ANDROID_PLATFORM=29
BUILD_HOST=aarch64-linux-android
BUILD_ARCH=arm64
LIBSODIUM_VER=1.0.16
LIBMBEDTLS_VER=2.6.0
PCRE_VER=8.41
SHADOWSOCKS_VER=3.3.4
CARES_VER=1.12.0

###############
# init env    #
###############
export WORK_DIR=$PWD
export BUILDTOOL_PATH=${WORK_DIR}/android-${BUILD_HOST}
export NDK=${WORK_DIR}/android
export SYSROOT="$NDK/sysroot"
export PATH=$PATH:${BUILDTOOL_PATH}/bin

export STAGING_DIR=${BUILDTOOL_PATH}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${BUILDTOOL_PATH}/lib:${BUILDTOOL_PATH}/sysroot/usr/lib
export BUILD_INCLUDE_PATH=${BUILDTOOL_PATH}/sysroot/usr/include
export CC=${BUILD_HOST}-gcc
export CXX=${BUILD_HOST}-g++
export AR=${BUILD_HOST}-ar
export LD=${BUILD_HOST}-ld
export RANLIB=${BUILD_HOST}-ranlib

mkdir insdir

#build ndk
build_ndk() {
    echo "Build ndk..."
    wget https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip
    unzip android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip
    rm -rf android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip ${NDK} ${BUILDTOOL_PATH}
    mv android-ndk-${ANDROID_NDK_VERSION} ${NDK}
    ${NDK}/build/tools/make-standalone-toolchain.sh --arch=${BUILD_ARCH} --platform=android-${ANDROID_PLATFORM} --install-dir=${BUILDTOOL_PATH}
}

build_deps() {
echo "Build mbedtls..."
wget https://tls.mbed.org/download/mbedtls-${LIBMBEDTLS_VER}-gpl.tgz -O mbedtls-${LIBMBEDTLS_VER}.tgz
tar -zxf mbedtls-${LIBMBEDTLS_VER}.tgz
cd mbedtls-${LIBMBEDTLS_VER}
ln -s ../insdir .
make install DESTDIR=$PWD/insdir/mbedtls CC=${BUILD_HOST}-gcc AR=${BUILD_HOST}-ar LD=${BUILD_HOST}-ld LDFLAGS=-static
cd -

echo "Build libsodium..."
wget https://github.com/jedisct1/libsodium/releases/download/${LIBSODIUM_VER}/libsodium-${LIBSODIUM_VER}.tar.gz -O libsodium-${LIBSODIUM_VER}.tar.gz
tar -zxf libsodium-${LIBSODIUM_VER}.tar.gz
cd libsodium-${LIBSODIUM_VER}
ln -s ../insdir .
./configure --host=${BUILD_HOST} --prefix=$PWD/insdir/libsodium --disable-ssp --disable-shared
make && make install
cd -

echo "Build pcre..."
wget https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VER}.tar.gz -O pcre-${PCRE_VER}.tar.gz
tar -zxf pcre-${PCRE_VER}.tar.gz
cd pcre-${PCRE_VER}
ln -s ../insdir .
./configure --host=${BUILD_HOST} --enable-pcre8 --enable-pcre16 --enable-pcre32 --disable-cpp --prefix=$PWD/insdir/pcre --disable-shared --enable-utf8 --enable-unicode-properties
make && make install
cd -

echo "Build libev..."
wget https://github.com/shadowsocks/libev/archive/master.zip -O libev.zip
unzip libev.zip
cd libev-master
ln -s ../insdir .
#./autogen.sh
./configure --host=${BUILD_HOST} --prefix=$PWD/insdir/libev --disable-shared
make && make install
cd -

echo "Build c-ares..."
wget https://c-ares.haxx.se/download/c-ares-${CARES_VER}.tar.gz -O c-ares-${CARES_VER}.tar.gz
tar -zxf c-ares-${CARES_VER}.tar.gz
cd c-ares-${CARES_VER}
ln -s ../insdir .
./configure --host=${BUILD_HOST} LDFLAGS=-static --prefix=$PWD/insdir/cares
make && make install
cd -
}
build_ndk
build_deps

echo "build ss"
git clone https://github.com/shadowsocks/shadowsocks-libev
cd shadowsocks-libev
git submodule update --init --recursive
ln -s ../insdir .
./autogen.sh && ./configure --host=${BUILD_HOST} --prefix=$PWD/insdir/shadowsocks-libev --disable-assert --disable-ssp --disable-system-shared-lib --enable-static --disable-documentation --with-mbedtls=$PWD/insdir/mbedtls --with-pcre=$PWD/insdir/pcre --with-sodium=$PWD/insdir/libsodium LDFLAGS="-Wl -Wno-implicit-function-declaration -Wno-error,-static -static-libgcc -L$PWD/insdir/cares/lib -L$PWD/insdir/libev/lib -L${SYSROOT}/usr/lib -U__ANDROID__ -llog" CFLAGS="-I$PWD/insdir/libev/include -I$PWD/insdir/cares/include -I${BUILD_INCLUDE_PATH} -U__ANDROID__ -Wno-implicit-function-declaration -Wno-error -Wno-deprecated-declarations -fno-strict-aliasing"
make && make install
