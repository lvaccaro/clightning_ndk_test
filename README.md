# clightning_ndk


Android cross-compilation of [c-lightning](https://github.com/ElementsProject/lightning) for Android >= 24 Api.

Build status: [![Build Status](https://travis-ci.com/lvaccaro/clightning_ndk.svg?branch=master)](https://travis-ci.com/lvaccaro/clightning_ndk)


### Get binaries
Download the artifacts from the latest github tagged release.

The package `<host>_lightning.tar.xz` contains: ligthning deamons, ligthning default plugins, `ligthning-cli` and `bitcoin-cli`.

### Build from sources
To build c-lightning follow the following instructions:

```bash
bash build_deps.sh
export REPO=https://github.com/ElementsProject/lightning.git
export COMMIT=v0.7.3
export TOOLCHAIN=aarch64-linux-android-clang
export TARGETHOST=aarch64-linux-android
export BITS=64
bash fetchbuild.sh $REPO $COMMIT $TOOLCHAIN $TARGETHOST $BITS $PWD
```

Note:

- `build_deps.sh`: download android ndk toolchain
- `fetchbuild.sh`: download and build sqlite, gmplib and c-lightning
- `<host>-lightning.tar.xz`: the generated archive contains the binary

To build `bitcoin-cli` from sources, compile bitcoin_ndk enabling bitcoin tools, [diff commit for enabling build tools](https://github.com/lvaccaro/bitcoin_ndk/commit/35b63e11ed6efc9d9dbc787759fd0e8b0b8311f4).

### Push to the device
Push all the binary to the android device, using `/data/local/tmp/``for testing

```bash
adb push lightningd/lightningd /data/local/tmp/
adb push lightningd/lightning_channeld /data/local/tmp/
adb push lightningd/lightning_closingd /data/local/tmp/
adb push lightningd/lightning_connectd /data/local/tmp/
adb push lightningd/lightning_gossipd /data/local/tmp/
adb push lightningd/lightning_hsmd /data/local/tmp/
adb push lightningd/lightning_onchaind /data/local/tmp/
adb push lightningd/lightning_openingd /data/local/tmp/
adb push plugins/autoclean /data/local/tmp/plugins/
adb push plugins/fundchannel /data/local/tmp/plugins/
adb push plugins/pay /data/local/tmp/plugins/
adb push bitcoin-cli /data/local/tmp/
```

### Run on the device
Connect to adb and run the `lightningd` deamon

```bash
adb shell
cd /data/local/tmp
chmod +x *
./lightningd --lightning-dir=/sdcard/tmp/ --testnet --bitcoin-rpcconnect=*** --bitcoin-rpcuser=*** --bitcoin-rpcpassword=*** --bitcoin-rpcport=18332 --bitcoin-cli=/data/local/tmp/bitcoin-cli --bitcoin-datadir=/sdcard/tmp/ --plugin-dir=/data/local/tmp/plugins --log-level=debug
```

### Local testing
Run cli command in an adb shell, as the following

```bash
./lightning-cli --lightning-dir=/sdcard/tmp/  newaddr
```

### Dependencies
* sqlite lib [sqlite-autoreconf-3260000](https://www.sqlite.org/2018/sqlite-autoconf-3260000.tar.gz)
* gmp lib [gmp-6.1.2](https://gmplib.org/download/gmp/gmp-6.1.2.tar.bz2)
* android ndk [android-ndk-r20](https://dl.google.com/android/repository/android-ndk-r20-linux-x86_64.zip)


### References
* [INSTALL.md](https://github.com/ElementsProject/lightning/blob/master/doc/INSTALL.md#to-cross-compile-for-android)  of clightning to cross-compile c-lightning for Android
* [bitcoin_ndk](https://github.com/greenaddress/bitcoin_ndk/): ndk build of bitcoin core, knots and liquid
* [abcore](https://github.com/greenaddress/abcore/): ABCore - Android Bitcoin Core

### Acknowledgement
Thanks [domegabri](https://github.com/domegabri) to test this project on Android devices, and [dieeasy](https://github.com/dieeasy) from inbitcoin to test channels and pay invoices with [globular](https://gitlab.com/inbitcoin/globular).