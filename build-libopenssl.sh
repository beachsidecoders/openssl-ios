#!/bin/sh
#
# openssl project ios build script
#
# portions based on krzyzanowskim/OpenSSL build script (https://github.com/krzyzanowskim/OpenSSL/blob/master/build.sh)
#
# usage 
#   ./build-libopenssl.sh
#
# options
#   -s [full path to openssl source directory]
#   -o [full path to openssl output directory]
#
# license
# The MIT License (MIT)
# 
# Copyright (c) 2016 Beachside Coders LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

# see http://stackoverflow.com/a/3915420/318790
function realpath { echo $(cd $(dirname "$1"); pwd)/$(basename "$1"); }
__FILE__=`realpath "$0"`
__DIR__=`dirname "${__FILE__}"`

# set -x

IOS_SDK_VERSION=`xcrun -sdk iphoneos --show-sdk-version`
DEVELOPER=`xcode-select -print-path`
IOS_DEPLOYMENT_VERSION="9.0"

# default
SSL_SRC_DIR=${__DIR__}/openssl
SSL_OUTPUT_DIR=${__DIR__}/libopenssl

while getopts s:o: opt; do
  case $opt in
    s)
      SSL_SRC_DIR=$OPTARG
      ;;
    o)
      SSL_OUTPUT_DIR=$OPTARG
      ;;
  esac
done

SSL_LOG_DIR=${SSL_OUTPUT_DIR}/log
SSL_INCLUDE_OUTPUT_DIR=${SSL_OUTPUT_DIR}/include
SSL_LIB_OUTPUT_DIR=${SSL_OUTPUT_DIR}/lib
SSL_BUILD_DIR=${__DIR__}/build


function prepare_build () {
  echo "Preparing build..."

  # remove old output
  if [ -d ${SSL_LOG_DIR} ]; then
      rm -rf ${SSL_LOG_DIR}
  fi

  if [ -d ${SSL_INCLUDE_OUTPUT_DIR} ]; then
      rm -rf ${SSL_INCLUDE_OUTPUT_DIR}
  fi

  if [ -d ${SSL_LIB_OUTPUT_DIR} ]; then
      rm -rf ${SSL_LIB_OUTPUT_DIR}
  fi

  if [ -d ${SSL_BUILD_DIR} ]; then
      rm -rf ${SSL_BUILD_DIR}
  fi

  # create output
  if [ ! -d ${SSL_OUTPUT_DIR} ]; then
      mkdir ${SSL_OUTPUT_DIR}
  fi

  # create log directory
  if [ ! -d ${SSL_LOG_DIR} ]; then
      mkdir ${SSL_LOG_DIR}
  fi

  # create build directory
  if [ ! -d ${SSL_BUILD_DIR} ]; then
      mkdir ${SSL_BUILD_DIR}
  fi
}

function build_arch () {
  ARCH=$1

  # setup and create source working directory
  SSL_SRC_WORKING_DIR=${SSL_BUILD_DIR}/openssl-src
  rm -rf ${SSL_SRC_WORKING_DIR}
  rsync -av --exclude=.git ${SSL_SRC_DIR}/ ${SSL_SRC_WORKING_DIR} > "${SSL_LOG_DIR}/${ARCH}.log" 2>&1

  pushd . > /dev/null
  cd ${SSL_SRC_WORKING_DIR}

  if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
    PLATFORM="iPhoneSimulator"
  else
    PLATFORM="iPhoneOS"
  fi

  export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
  export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
  export BUILD_TOOLS="${DEVELOPER}"
  export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"

  # fix header for Swift
  sed -ie "s/BIGNUM \*I,/BIGNUM \*i,/g" crypto/rsa/rsa.h

  # fix ui_openssl.c 
  if [[ "$PLATFORM" == "iPhoneOS" ]]; then
    sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
  fi

  # configure
  if [ "$ARCH" == "x86_64" ]; then
    ./Configure darwin64-x86_64-cc --openssldir="${SSL_BUILD_DIR}/openssl-${ARCH}" >> "${SSL_LOG_DIR}/${ARCH}.log" 2>&1
  else
    ./Configure iphoneos-cross -no-asm --openssldir="${SSL_BUILD_DIR}/openssl-${ARCH}" >> "${SSL_LOG_DIR}/${ARCH}.log" 2>&1
  fi

  # patch makefile (add -isysroot to CC=)
  sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -arch $ARCH -mios-simulator-version-min=${IOS_DEPLOYMENT_VERSION} -miphoneos-version-min=${IOS_DEPLOYMENT_VERSION} !" "Makefile"

  echo "Building ${ARCH}..."

  make >> "${SSL_LOG_DIR}/${ARCH}.log" 2>&1
  make install >> "${SSL_LOG_DIR}/${ARCH}.log" 2>&1
  
  popd > /dev/null
  
  rm -rf ${SSL_SRC_WORKING_DIR}
}

function build_openssl () {
  build_arch "armv7"
  build_arch "armv7s"
  build_arch "arm64"
  build_arch "i386"
  build_arch "x86_64"
}

function lipo_libs () {
  echo "Lipo libs..."

  if [ ! -d ${SSL_LIB_OUTPUT_DIR} ]; then
      mkdir ${SSL_LIB_OUTPUT_DIR}
  fi

  # libcryto.a
  xcrun -sdk iphoneos lipo -arch armv7  ${SSL_BUILD_DIR}/openssl-armv7/lib/libcrypto.a \
                           -arch armv7s ${SSL_BUILD_DIR}/openssl-armv7s/lib/libcrypto.a \
                           -arch arm64  ${SSL_BUILD_DIR}/openssl-arm64/lib/libcrypto.a \
                           -arch i386   ${SSL_BUILD_DIR}/openssl-i386/lib/libcrypto.a \
                           -arch x86_64 ${SSL_BUILD_DIR}/openssl-x86_64/lib/libcrypto.a \
                           -create -output ${SSL_LIB_OUTPUT_DIR}/libcrypto.a


  # libssl.a
  xcrun -sdk iphoneos lipo -arch armv7  ${SSL_BUILD_DIR}/openssl-armv7/lib/libssl.a \
                           -arch armv7s ${SSL_BUILD_DIR}/openssl-armv7s/lib/libssl.a \
                           -arch arm64  ${SSL_BUILD_DIR}/openssl-arm64/lib/libssl.a \
                           -arch i386   ${SSL_BUILD_DIR}/openssl-i386/lib/libssl.a \
                           -arch x86_64 ${SSL_BUILD_DIR}/openssl-x86_64/lib/libssl.a \
                           -create -output ${SSL_LIB_OUTPUT_DIR}/libssl.a

}

function copy_include () {
  if [ ! -d ${SSL_INCLUDE_OUTPUT_DIR} ]; then
    mkdir ${SSL_INCLUDE_OUTPUT_DIR}
  fi

  cp -r ${SSL_BUILD_DIR}/openssl-arm64/include/openssl ${SSL_INCLUDE_OUTPUT_DIR}
}

function package_openssl () {
  lipo_libs
  copy_include
}

function clean_up_build () {
  echo "Cleaning up..."

  if [ -d ${SSL_BUILD_DIR} ]; then
      rm -rf ${SSL_BUILD_DIR}
  fi
}

echo "Build openssl..."
prepare_build
build_openssl
package_openssl
clean_up_build
echo "Done."

