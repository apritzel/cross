#!/bin/sh
#
# script for building cross binutils packages
# skip to CONFIGURE line below for the interesting part
#

PKGNAM=binutils
VERSION=${VERSION:-"2.25"}
BUILD=${BUILD:-"1"}
CC=${CC:-"gcc"}

TARGET=${TARGET:-"aarch64"}
SYSROOT=/usr/gnemul/$TARGET

if [ -z "$NUMJOBS" ]
then
	NUMJOBS=`getconf _NPROCESSORS_ONLN 2> /dev/null`
	if [ $? -ne 0 ]
	then
		NUMJOBS=`grep -c ^processor /proc/cpuinfo 2> /dev/null`
		[ $? -ne 0 ] && NUMJOBS=2
	fi
	NUMJOBS=$((NUMJOBS*2))
fi

[ -f /etc/debian_version ] && system="debian"
[ -f /etc/slackware-version ] && system="slackware"

usage() {
	echo "usage: $0 help|build|package|repackage|deb|slackpkg [source path]"
}

case "$1" in
	-h|help) usage
		 echo " [source path]"
		 exit 0
		;;
	build) package="" ;;
	deb) package="debian" ;;
	slackpkg) package="slackware" ;;
	package) package="$system" ;;
	repackage) skipbuild="1"; package="$system" ;;
	*) echo "unknown command: \"$1\""; usage; exit 2 ;;
esac
shift

if [ -d "$1" ]
then
	SRC_PATH="$1"
else
	testdir=../${PKGNAM}.git
	[ -f "$testdir/configure" ] && SRC_PATH="$testdir"
	testdir=../${PKGNAM}-gdb.git
	[ -f "$testdir/configure" ] && SRC_PATH="$testdir"
	testdir=../${PKGNAM}
	[ -f "$testdir/configure" ] && SRC_PATH="$testdir"
	testdir=../${PKGNAM}-gdb
	[ -f "$testdir/configure" ] && SRC_PATH="$testdir"
	testdir=../${PKGNAM}-${VERSION}
	[ -f "$testdir/configure" ] && SRC_PATH="$testdir"
fi

if [ ! -d "$SRC_PATH" -a -z "$skipbuild" ]
then
	echo "Error: could not find source directory."
	echo "Give the source path as an argument."
	exit 1
fi

HARCH=`uname -m`
case "$HARCH" in
	i?86) HARCH=i486 ;;
	aarch64) HBITS="64" ;;
	x86_64) HBITS="64"; [ "$system" = "debian" ] && HARCH="amd64" ;;
	arm*) HARCH=arm ;;
esac
HTRIPLET=`$CC -dumpmachine`

case "$system" in
	slackware) vendor="slackware"; os="linux"; slackware="slackware-" ;;
	*) vendor="linux"; os="gnu"; HBITS="" ;;
esac

if [ -z "$TRIPLET" ]
then
	TRIPLET=${TARGET}-${vendor}-${os}
	case "$TARGET" in
		armhf) TRIPLET=arm-${slackware}linux-gnueabihf;;
		arm) TRIPLET=arm-${slackware}linux-gnueabi;;
		openwrt) TRIPLET=mips-openwrt-linux-uclibc;;
		x32) TRIPLET=x86_64-${slackware}linux-gnux32;;
	esac
fi

HOST_OPTS="--prefix=/usr --with-gnu-ld --with-gnu-as"
case "$system" in
	slackware)
		LIBDIR="lib$HBITS"
		HOST_OPTS="$HOST_OPTS --disable-multiarch"
		;;
	debian)
		LIBDIR="lib/$HTRIPLET"
		HOST_OPTS="$HOST_OPTS --enable-multiarch"
		;;
esac
HOST_OPTS="$HOST_OPTS --libdir=/usr/$LIBDIR"

LIBPATH=/usr/$TRIPLET/lib$HBITS
LIBPATH="$LIBPATH:$SYSROOT/usr/local/$LIBDIR"
LIBPATH="$LIBPATH:$SYSROOT/$LIBDIR"
LIBPATH="$LIBPATH:$SYSROOT/usr/$LIBDIR"

#
# CONFIGURE
#

if [ -z "$skipbuild" ]
then
	if ! $SRC_PATH/configure $HOST_OPTS --target=$TRIPLET \
		--build=$HTRIPLET --host=$HTRIPLET \
		--enable-plugins --enable-threads --disable-nls \
		--enable-gold=yes --enable-ld=default \
		--disable-bootstrap --disable-shared --enable-multilib \
		--with-sysroot=$SYSROOT \
		--with-lib-path=$LIBPATH
	then
		echo -e "\nconfigure failed, aborting."
		exit 2
	fi

	if ! make -j"$NUMJOBS"
	then
		echo -e "\nbuild failed, aborting."
		exit 3
	fi

	rm -Rf ./root
	mkdir root
	if ! make DESTDIR=`pwd`/root install
	then
		echo -e "\ninstallation failed, aborting."
		exit 4
	fi

	CROSSLD=./root/usr/bin/${TRIPLET}-ld
	if [ ! -x $CROSSLD ] || $CROSSLD -v | grep -qv "$VERSION\$"
	then
		echo -e "\ncross ld binary failing"
		exit 5
	fi
fi

[ -z "$package" ] && exit 0

(	cd root
	rm -Rf usr/include usr/man usr/info usr/share
	find ./ | xargs file | grep -e "executable" -e "shared object" \
		| grep ELF | cut -f 1 -d : \
		| xargs strip --strip-unneeded 2> /dev/null
)

if [ "$package" = "slackware" ]
then

	SLACKVER=`. /etc/os-release; echo $VERSION`
	PKGNAME="$PKGNAM-$TARGET"
	mkdir root/install
	cat > root/install/slack-desc << _EOF
$PKGNAME: binutils for the $TARGET architecture
$PKGNAME:
$PKGNAME: Binutils is a collection of binary utilities.  It includes "as"
$PKGNAME: (the portable GNU assembler), "ld" (the GNU linker), and other
$PKGNAME: utilities for creating and working with binary programs.
$PKGNAME: This version deals and creates with binaries and object files
$PKGNAME: for the $TARGET architecture.
$PKGNAME: Target is: $TRIPLET
$PKGNAME: sysroot: $SYSROOT
$PKGNAME: Version $VERSION for Slackware$HBITS $SLACKVER
$PKGNAME:
_EOF

	(cd root; makepkg -c y -l y ../$PKGNAME-$VERSION-$HARCH-$BUILD.txz)
	exit 0
fi

[ "$package" = "debian" ] || exit 1

mkdir -p debian/control
(	cd root
	find * -type f | sort | xargs md5sum > ../debian/control/md5sums
	tar c -z --owner=root --group=root -f ../debian/data.tar.gz ./
)
SIZE=`du -s root | cut -f1`

[ -f debian/control/control ] || cat > debian/control/control << _EOF
Package: $PKGNAM-$TRIPLET
Source: $PKGNAM
Version: $VERSION
Installed-Size: $SIZE
Maintainer: Andre Przywara <osp@andrep.de>
Architecture: $HARCH
Depends: libc6, zlib1g (>= 1:1.1.4)
Built-Using: binutils
Section: devel
Priority: extra
Description: GNU binary utilities, for $TRIPLET target
 This package provides GNU assembler, linker and binary utilities
 for the $TRIPLET target, for use in a cross-compilation environment.
 .
 You don't need this package unless you plan to cross-compile programs
 for $TRIPLET.
_EOF

(cd debian/control; tar c -z --owner=root --group=root -f ../control.tar.gz *)
echo "2.0" > debian/debian-binary
PKGNAME=${PKGNAM}-${TRIPLET}_${VERSION}-${BUILD}_${HARCH}.deb
rm -f $PKGNAME
(cd debian; ar q ../$PKGNAME debian-binary control.tar.gz data.tar.gz)
