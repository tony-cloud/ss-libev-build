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
SHADOWSOCKS_VER=v3.3.4
CARES_VER=1.12.0

case "$1" in
	arm) BUILD_ARCH=arm; BUILD_HOST=arm-linux-androideabi;;
	arm64) BUILD_ARCH=arm64; BUILD_HOST=aarch64-linux-android;;
	x86) BUILD_ARCH=x86; BUILD_HOST=i686-linux-android;;
	x86_64) BUILD_ARCH=x86_64; BUILD_HOST=x86_64-linux-android;;
    init) prepare_ndk; exit 0;;
	*) __errmsg "unknown arch $1, use default. Support arch: arm, arm64, x86, x86_64";;
esac

uname -a
###############
# init env    #
###############
init_env() {
    export WORK_DIR=$PWD
    export BUILDTOOL_PATH=${WORK_DIR}/android-${BUILD_HOST}
    export NDK=${WORK_DIR}/android
    export SYSROOT="$NDK/sysroot"
    export PATH=$PATH:${BUILDTOOL_PATH}/bin
    export STAGING_DIR=${BUILDTOOL_PATH}
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${BUILDTOOL_PATH}/lib:${BUILDTOOL_PATH}/sysroot/usr/lib
    export BUILD_INCLUDE_PATH=${BUILDTOOL_PATH}/sysroot/usr/include
    if [ $BUILD_ARCH = "arm" ] || [ $BUILD_ARCH = "x86" ]; then
      export CC="${BUILD_HOST}-gcc -m32"
      export CXX="${BUILD_HOST}-g++ -m32"
    else
      export CC=${BUILD_HOST}-gcc
      export CXX=${BUILD_HOST}-g++
    fi
    export CC=${BUILD_HOST}-gcc
    export CXX=${BUILD_HOST}-g++
    export AR=${BUILD_HOST}-ar
    export LD=${BUILD_HOST}-ld
    export RANLIB=${BUILD_HOST}-ranlib
}

init_buildfolder() {
    mkdir build-${BUILD_ARCH}
    cd build-${BUILD_ARCH}
    mkdir insdir
}

prepare_ndk() {
    echo "Prepare ndk..."
    wget https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip
    unzip android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip
    rm -rf android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip ${NDK} ${BUILDTOOL_PATH}
    mv android-ndk-${ANDROID_NDK_VERSION} ${NDK}
    touch .ndk.installed
}

#build ndk
build_ndk() {
    ${NDK}/build/tools/make-standalone-toolchain.sh --arch=${BUILD_ARCH} --platform=android-${ANDROID_PLATFORM} --install-dir=${BUILDTOOL_PATH}
}

build_deps() {
echo "Build mbedtls..."
wget https://tls.mbed.org/download/mbedtls-${LIBMBEDTLS_VER}-gpl.tgz -O mbedtls-${LIBMBEDTLS_VER}.tgz
tar -zxf mbedtls-${LIBMBEDTLS_VER}.tgz
cd mbedtls-${LIBMBEDTLS_VER}
ln -s ../insdir .
make install DESTDIR=$PWD/insdir/mbedtls CC=${CC} AR=${AR} LD=${LD} LDFLAGS=-static
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

echo "Build simple obfs"
git clone https://github.com/shadowsocks/simple-obfs.git
cd simple-obfs
git submodule update --init --recursive
ln -s ../insdir .
./autogen.sh && ./configure --host=${BUILD_HOST} --prefix=$PWD/insdir/simple-obfs --disable-assert --disable-ssp --disable-system-shared-lib --enable-static --disable-documentation --with-pcre=$PWD/insdir/pcre --with-libev=$PWD/insdir/libev LDFLAGS="-Wl -Wno-implicit-function-declaration -Wno-error,-static -static-libgcc -L$PWD/insdir/cares/lib -L$PWD/insdir/libev/lib -L${SYSROOT}/usr/lib -U__ANDROID__ -llog" CFLAGS="-I$PWD/insdir/libev/include -I$PWD/insdir/cares/include -I${BUILD_INCLUDE_PATH} -U__ANDROID__ -Wno-implicit-function-declaration -Wno-error -Wno-deprecated-declarations -fno-strict-aliasing"
make && make install
cd -
}

build_ss() {
    echo "build ss"
    git clone https://github.com/shadowsocks/shadowsocks-libev
    cd shadowsocks-libev
    git checkout -b origin/${SHADOWSOCKS_VER}
    git submodule update --init --recursive
    ln -s ../insdir .
    ./autogen.sh && ./configure --host=${BUILD_HOST} --prefix=$PWD/insdir/shadowsocks-libev --disable-assert --disable-ssp --disable-system-shared-lib --enable-static --disable-documentation --with-mbedtls=$PWD/insdir/mbedtls --with-pcre=$PWD/insdir/pcre --with-sodium=$PWD/insdir/libsodium --with-libev=$PWD/insdir/libev LDFLAGS="-Wl -Wno-implicit-function-declaration -Wno-error,-static -static-libgcc -L$PWD/insdir/cares/lib -L$PWD/insdir/libev/lib -L${SYSROOT}/usr/lib -U__ANDROID__ -llog" CFLAGS="-I$PWD/insdir/libev/include -I$PWD/insdir/cares/include -I${BUILD_INCLUDE_PATH} -U__ANDROID__ -Wno-implicit-function-declaration -Wno-error -Wno-deprecated-declarations -fno-strict-aliasing"
    make && make install
    cd -
    mkdir ../shadowsocks-libev-${BUILD_ARCH}
    cp insdir/shadowsocks-libev/bin/ss-* ../shadowsocks-libev-${BUILD_ARCH}
    cp insdir/simple-obfs/bin/obfs* ../shadowsocks-libev-${BUILD_ARCH}
    cd ..
    tar -zcvf shadowsocks-libev-${SHADOWSOCKS_VER}-${BUILD_ARCH}.tar.gz ./shadowsocks-libev-${BUILD_ARCH}/
    rm -rf build-${BUILD_ARCH}
}

release_assets() {
    USER=${GITHUB_USER}
    REPO="ss-libev-build"
    TAG=${SHADOWSOCKS_VER}
    FILE_NAME=shadowsocks-libev-${SHADOWSOCKS_VER}-${BUILD_ARCH}.tar.gz
    FILE_PATH=$PWD/shadowsocks-libev-${SHADOWSOCKS_VER}-${BUILD_ARCH}.tar.gz
    chmod +x ./ok.sh
    # Create a release if not exist:
    ./ok.sh create_release "$USER" "$REPO" "$TAG" _filter='.upload_url'

    # Find a release by tag then upload a file:
    ./ok.sh list_releases "$USER" "$REPO" \
        | awk -v "tag=$TAG" -F'\t' '$2 == tag { print $3 }' \
        | xargs -I@ ./ok.sh release "$USER" "$REPO" @ _filter='.upload_url' \
        | sed 's/{.*$/?name='"$FILE_NAME"'/' \
        | xargs -I@ ./ok.sh upload_asset @ "$FILE_PATH"
}

########
# main #
########
init_env
init_buildfolder
#prepare ndk if not found
if [ ! -d ${NDK} ]; then
    echo "NDK not found, download."
    prepare_ndk
fi
#build if ndk not found
if [ ! -d ${BUILDTOOL_PATH} ]; then
    echo "NDK found but not build, build it."
    build_ndk
fi
build_deps
build_ss
release_assets
