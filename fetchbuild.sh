#! /bin/bash
set -e

repo=$1
commit=$2
target_host=$3
bits=$4
build=$5
rootdir=$6

export PATH=/opt/toolchain/bin:${PATH}
export AR=${target_host}-ar
export AS=${target_host}-as
export CC=${target_host}26-clang
export CXX=${target_host}26-clang++
export LD=${target_host}-ld
export STRIP=${target_host}-strip
export LDFLAGS="-pie"
export MAKE_HOST=${target_host}
export HOST=${target_host}
export QEMU_LD_PREFIX=/opt/toolchain/sysroot
export CONFIGURATOR_CC="/usr/bin/gcc"
export BUILD=${build}

if [ "${target_host}" = "arm-linux-androideabi" ]; then
    CC="armv7a-linux-androideabi26-clang"
    CXX="armv7a-linux-androideabi26-clang"
fi

num_jobs=4
if [ -f /proc/cpuinfo ]; then
    num_jobs=$(grep ^processor /proc/cpuinfo | wc -l)
fi

# sqlite
wget https://www.sqlite.org/2018/sqlite-autoconf-3260000.tar.gz
tar xzvf sqlite-autoconf-3260000.tar.gz
cd sqlite-autoconf-3260000
./configure --enable-static --disable-readline --disable-threadsafe --host=${target_host} CC=$CC --prefix=${QEMU_LD_PREFIX}
make -j $num_jobs
make install
cd ..
rm -rf sqlite-autoconf-3260000
rm -rf sqlite-autoconf-3260000.tar.gz

# gmp
wget https://gmplib.org/download/gmp/gmp-6.1.2.tar.bz2
tar xjvf gmp-6.1.2.tar.bz2
cd gmp-6.1.2
./configure --enable-static --disable-assembly --host=${target_host} CC=$CC --prefix=${QEMU_LD_PREFIX}
make -j $num_jobs
make install
cd ..
rm -rf gmp-6.1.2
rm -rf gmp-6.1.2.tar.bz2

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
./configure CONFIGURATOR_CC=${CONFIGURATOR_CC} --prefix=${LNBUILDROOT} --disable-developer --disable-compat --disable-valgrind --enable-static

cp /repo/lightning-gen_header_versions.h gen_header_versions.h
# update arch based on toolchain
sed "s'NDKCOMPILER'${CC}'" /repo/lightning-config.vars > config.vars
sed "s'NDKCOMPILER'${CC}'" /repo/lightning-config.h > ccan/config.h
sed -i "s'LNBUILDROOT'${LNBUILDROOT}'" config.vars

# Path the external deps build
patch -p1 < /repo/lightning-makefile-external-reverts.patch
# patch makefile
patch -p1 < /repo/lightning-makefile.patch
patch -p1 < /repo/lightning-addr.patch
patch -p1 < /repo/lightning-endian.patch

# build external libraries and source
make PIE=1 DEVELOPER=0 || echo "continue"
make clean -C ccan/ccan/cdump/tools
make LDFLAGS="" CC="${CONFIGURATOR_CC}" LDLIBS="-L/usr/local/lib" -C ccan/ccan/cdump/tools
make PIE=1 DEVELOPER=0
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

# update arch based on toolchain
sed -i -e 's/PREFIX=\/opt\/toolchain\/aarch64-linux-android-clang\/sysroot/PREFIX=\/opt\/toolchain\/sysroot/g' ./config.vars
sed -i -e 's/CC=aarch64-linux-android-clang/CC='${CC}'/g' ./config.vars
sed -i -e 's/#define CCAN_COMPILER "aarch64-linux-android-clang"/#define CCAN_COMPILER "'${CC}'"/g' ./ccan/config.h

# patch makefile
git apply ${rootdir}/Makefile.patch

# patch abstracted namespace for socket
git apply ${rootdir}/jsonrpc.patch

# patch endian.h if just defined
git apply ${rootdir}/endian.patch

# build external libraries and source before ccan tools
make PIE=1 DEVELOPER=0 || echo "continue"

# build ccan tools for the host machine
#sed -i -e 's/"ccan_compat.h"/"..\/ccan_compat.h"/g' ccan/config.h
make clean -C ccan/ccan/cdump/tools
make LDFLAGS="" CC="${CONFIGURATOR_CC}" LDLIBS="-L/usr/local/lib" -C ccan/ccan/cdump/tools

# complete the build process
make PIE=1 DEVELOPER=0

#exit from lightning build system
deactivate
cd ..

# pack binaries
export repo_name="${HOST}-lightning"
tar -C lightning/lightningd -cf ${repo_name}.tar lightning_channeld lightning_closingd lightning_connectd lightning_gossipd lightning_hsmd lightning_onchaind lightning_openingd lightningd
tar -C lightning/ -rf ${repo_name}.tar plugins/autoclean plugins/fundchannel plugins/pay
tar -C lightning/cli/ -rf ${repo_name}.tar lightning-cli
xz ${repo_name}.tar