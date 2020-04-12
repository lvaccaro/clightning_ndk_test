#! /bin/bash
set -e

repo=$1
commit=$2
reponame=$3
rename=$4
configextra=$5
target_host=$6
bits=$7

unpackdep() {
    archive=$(basename $1)
    curl -sL -o ${archive} $1
    echo "$2 ${archive}" | sha256sum --check
    tar xf ${archive}
    rm ${archive}
}

# build deps
BUILDROOT=$PWD/build_root
mkdir -p $BUILDROOT

export ANDROID_NDK_HOME=/opt/android-ndk-r20b
export PATH=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:${PATH}
export AR=${target_host/v7a}-ar
export AS=${target_host}24-clang
export CC=${target_host}24-clang
export CXX=${target_host}24-clang++
export LD=${target_host/v7a}-ld
export STRIP=${target_host/v7a}-strip
export LDFLAGS="-pie"
export MAKE_HOST=${target_host}
export HOST=${target_host}
export QEMU_LD_PREFIX=/opt/toolchain/sysroot
export CONFIGURATOR_CC="/usr/bin/gcc"
export BUILD=${build}

NDKARCH=arm
BUILD=armv7
if [ "$target_host" = "i686-linux-android" ]; then
    NDKARCH=x86
    BUILD=x86
elif [ "$target_host" = "x86_64-linux-android" ]; then
    NDKARCH=x86_64
    BUILD=x86_64
elif [ "$target_host" = "aarch64-linux-android" ]; then
    NDKARCH=arm64
    BUILD=aarch64
fi
export NDKARCH=${NDKARCH}
export BUILD=${BUILD}

num_jobs=4
if [ -f /proc/cpuinfo ]; then
    num_jobs=$(grep ^processor /proc/cpuinfo | wc -l)
fi

# build sqlite
if [ ! -d "sqlite-autoconf-3260000" ]; then
  unpackdep https://www.sqlite.org/2018/sqlite-autoconf-3260000.tar.gz 5daa6a3fb7d1e8c767cd59c4ded8da6e4b00c61d3b466d0685e35c4dd6d7bf5d
  cd sqlite-autoconf-3260000
  ./configure --enable-static --disable-readline --disable-threadsafe --host=${target_host} CC=$CC --prefix=${BUILDROOT}
  make -j $num_jobs
  make install
  cd ..
fi

# build gmp
if [ ! -d "gmp-6.1.2" ]; then
  unpackdep https://gmplib.org/download/gmp/gmp-6.1.2.tar.bz2 5275bb04f4863a13516b2f39392ac5e272f5e1bb8057b18aec1c9b79d73d8fb2
  cd gmp-6.1.2
  ./configure --enable-static --disable-assembly --host=${target_host} CC=$CC --prefix=${BUILDROOT}
  make -j $num_jobs
  make install
  cd ..
fi

# build libevent
if [ ! -d "libevent-release-2.1.11-stable" ]; then
  unpackdep https://github.com/libevent/libevent/archive/release-2.1.11-stable.tar.gz 229393ab2bf0dc94694f21836846b424f3532585bac3468738b7bf752c03901e
  cd libevent-release-2.1.11-stable
  ./autogen.sh
  ./configure --prefix=${BUILDROOT} --enable-static --disable-samples \
              --disable-openssl --disable-shared --disable-libevent-regress --disable-debug-mode \
              --disable-dependency-tracking --host $target_host
  make -o configure install -j${num_jobs}
  cd ..
fi

# build zlib
if [ ! -d "zlib-1.2.11" ]; then
  unpackdep https://github.com/madler/zlib/archive/v1.2.11.tar.gz 629380c90a77b964d896ed37163f5c3a34f6e6d897311f1df2a7016355c45eff
  cd zlib-1.2.11
  ./configure --static --prefix=${BUILDROOT}
  make -o configure install -j${num_jobs}
  cd ..
fi

# build openssl
if [ ! -d "openssl-OpenSSL_1_1_1d" ]; then
  unpackdep https://github.com/openssl/openssl/archive/OpenSSL_1_1_1d.tar.gz 23011a5cc78e53d0dc98dfa608c51e72bcd350aa57df74c5d5574ba4ffb62e74
  cd openssl-OpenSSL_1_1_1d
  SSLOPT="no-gost no-shared no-dso no-ssl3 no-idea no-hw no-dtls no-dtls1 \
          no-weak-ssl-ciphers no-comp -fvisibility=hidden no-err no-psk no-srp"

  if [ "$bits" = "64" ]; then
      SSLOPT="$SSLOPT enable-ec_nistp_64_gcc_128"
  fi
  ./Configure android-$NDKARCH --prefix=${BUILDROOT} $SSLOPT
  make depend
  make -j${num_jobs} 2> /dev/null
  make install_sw
  cd ..
fi

# build curl
if [ ! -d "curl-7.69.1" ]; then
  unpackdep https://github.com/curl/curl/releases/download/curl-7_69_1/curl-7.69.1.tar.gz 01ae0c123dee45b01bbaef94c0bc00ed2aec89cb2ee0fd598e0d302a6b5e0a98
  cd curl-7.69.1
  ./configure --enable-static --disable-shared --prefix=${BUILDROOT} --target=${target_host} --host=${target_host} --with-ssl=${BUILDROOT} --with-zlib=${BUILDROOT}
  make -j ${num_jobs}
  make install
  cd ..
fi

# download lightning
git clone $repo lightning
cd lightning
git checkout v0.8.1

# set virtualenv
python3 -m virtualenv venv
. venv/bin/activate
pip install -r requirements.txt

# set standard cc for the configurator
sed -i 's/$CC ${CWARNFLAGS-$BASE_WARNFLAGS} $CDEBUGFLAGS $COPTFLAGS -o $CONFIGURATOR $CONFIGURATOR.c/$CONFIGURATOR_CC ${CWARNFLAGS-$BASE_WARNFLAGS} $CDEBUGFLAGS $COPTFLAGS -o $CONFIGURATOR $CONFIGURATOR.c/g' configure
sed -i 's/-Wno-maybe-uninitialized/-Wno-uninitialized/g' configure
./configure CONFIGURATOR_CC=${CONFIGURATOR_CC} --prefix=${BUILDROOT} --disable-developer --disable-compat --disable-valgrind --enable-static

cp /repo/lightning-gen_header_versions.h gen_header_versions.h
# update arch based on toolchain
sed "s'NDKCOMPILER'${CC}'" /repo/lightning-config.vars > config.vars
sed "s'NDKCOMPILER'${CC}'" /repo/lightning-config.h > ccan/config.h
sed -i "s'BUILDROOT'${BUILDROOT}'" config.vars

# Path the external deps build
patch -p1 < /repo/lightning-makefile-external-reverts.patch
# patch makefile
patch -p1 < /repo/lightning-makefile.patch
patch -p1 < /repo/lightning-addr.patch
patch -p1 < /repo/lightning-endian.patch

# add esplora plugin
git clone https://github.com/lvaccaro/esplora_clnd_plugin.git
cp esplora_clnd_plugin/esplora.c plugins/
cp esplora_clnd_plugin/Makefile plugins/
sed -i 's/PLUGINS=/PLUGINS=plugins\/esplora /g' Makefile
sed -i 's/LDLIBS = /LDLIBS = -lcurl -lssl -lcrypto /g' Makefile

# build external libraries and source
make -j $num_jobs PIE=1 DEVELOPER=0 || echo "continue"
make clean -C ccan/ccan/cdump/tools
make -j $num_jobs LDFLAGS="" CC="${CONFIGURATOR_CC}" LDLIBS="-L/usr/local/lib" -C ccan/ccan/cdump/tools
make -j $num_jobs PIE=1 DEVELOPER=0
deactivate
cd ..


export CFLAGS="-flto"
export LDFLAGS="$CFLAGS -pie -static-libstdc++ -fuse-ld=lld"
# build core
git clone $repo ${reponame}
cd ${reponame}
git checkout $commit
patch -p1 < /repo/0001-android-patches.patch

# run configure
./configure CONFIGURATOR_CC=/usr/bin/gcc --prefix=${QEMU_LD_PREFIX} --disable-developer --disable-compat --disable-valgrind --enable-static

# change settings
cp ${rootdir}/config.vars .
cp ${rootdir}/config.h ./ccan
cp ${rootdir}/gen_header_versions.h .

# build tor
unpackdep https://github.com/torproject/tor/archive/tor-0.4.2.5.tar.gz 94ad248f4d852a8f38bd8902a12b9f41897c76e389fcd5b8a7d272aa265fd6c9
cd tor-tor-0.4.2.5
./autogen.sh
TOROPT="--disable-system-torrc --disable-asciidoc --enable-static-tor --enable-static-openssl \
        --with-zlib-dir=$BUILDROOT --disable-systemd --disable-zstd \
        --enable-static-libevent --enable-static-zlib --disable-system-torrc \
        --with-openssl-dir=$BUILDROOT --disable-unittests \
        --with-libevent-dir=$BUILDROOT --disable-lzma \
        --disable-tool-name-check --disable-rust \
        --disable-largefile ac_cv_c_bigendian=no \
        --disable-module-dirauth"

./configure $TOROPT --prefix=${BUILDROOT} --host=$target_host --disable-android
make -o configure install -j${num_jobs}
$STRIP $BUILDROOT/bin/tor
mv $BUILDROOT/bin/tor ../${reponame}/depends/${target_host/v7a/}/bin
cd ..

# packaging
if [ "${reponame}" != "${rename}" ]; then
    mv ${reponame}/depends/${target_host/v7a/}/bin/${reponame}d ${reponame}/depends/${target_host/v7a/}/bin/${rename}d
    mv ${reponame}/depends/${target_host/v7a/}/bin/${reponame}-cli ${reponame}/depends/${target_host/v7a/}/bin/${rename}-cli
    outputtar=/repo/${target_host/v7a/}_${rename}.tar
else
    outputtar=/repo/${target_host/v7a/}_$(basename $(dirname ${repo})).tar
fi
tar -cf ${outputtar} -C ${reponame}/depends/${target_host/v7a/}/bin ${rename}d ${rename}-cli tor
tar -rf ${outputtar} -C lightning/lightningd lightning_channeld lightning_closingd lightning_connectd lightning_gossipd lightning_hsmd lightning_onchaind lightning_openingd lightningd
tar -rf ${outputtar} -C lightning plugins/autoclean plugins/fundchannel plugins/pay plugins/bcli plugins/esplora
tar -rf ${outputtar} -C lightning/cli lightning-cli
xz ${outputtar}
