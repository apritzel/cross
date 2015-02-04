#!/bin/sh
#
# script for building cross GCC packages
# skip to CONFIGURE line below for the interesting part
#

PKGNAM=gcc
VERSION=${VERSION:-"4.9.2"}
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

usage() {
	echo -n "usage: $0 help|build|package|repackage|deb|slackpkg"
	echo " stage[12] [source path]"
}

[ -f /etc/debian_version ] && system="debian"
[ -f /etc/slackware-version ] && system="slackware"

case "$1" in
	-h|help) usage; exit 0 ;;
	deb) package="debian" ;;
	slackpkg) package="slackware" ;;
	package) package=$system ;;
	build) package="" ;;
	repackage) skipbuild="1"; package="$system" ;;
	*) echo "unknown command: \"$1\""; usage; exit 2 ;;
esac
shift

if [ $# -eq 0 -a -z "$skipbuild" ]
then
	echo "require stage1 or stage2 specifier"
	usage
	exit 1
fi

if [ -z "$skipbuild" ]
then
	stage="$1"
	shift
else
	stage="skipbuild"
fi

if [ -d "$1" ]
then
	SRC_PATH="$1"
else
	testdir=../${PKGNAM}.git
	[ -f "$testdir/configure" ] && SRC_PATH="$testdir"
	testdir=../${PKGNAM}
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
HTRIPLET=`${CC} -dumpmachine`

case "$system" in
	slackware) vendor="slackware"; os="linux"; slackware="slackware-" ;;
	*) vendor="linux"; os="gnu"; HBITS="" ;;
esac

TARGET_LD_SUFFIX=""
TRIPLET=${TARGET}-${vendor}-${os}
case "$TARGET" in
	x86_64|aarch64) TARGET_LD_SUFFIX="64" ;;
	armhf) TRIPLET=arm-${slackware}linux-gnueabihf
		ADD_OPTS="--with-arch=armv7-a --with-float=hard" ;;
	arm) TRIPLET=arm-${slackware}linux-gnueabi
		ADD_OPTS="--with-float=softfp" ;;
	openwrt) TRIPLET=mips-openwrt-linux-uclibc ;;
	mips64) ADD_OPTS="--with-abi=64" ;;
esac

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

#
# CONFIGURE
#

[ -d ./root ] && rm -Rf ./root
mkdir root
case "$stage" in
	stage1)
		$SRC_PATH/configure $HOST_OPTS --target=$TRIPLET \
			--build=$HTRIPLET --host=$HTRIPLET \
			--disable-shared --disable-threads \
			--disable-bootstrap --enable-multilib \
			--with-sysroot=$SYSROOT --with-newlib --without-headers \
			--enable-languages=c --disable-nls \
			--disable-libgomp --disable-libitm --disable-libquadmath \
			--disable-libsanitizer --disable-libssp --disable-libvtv \
			--disable-libcilkrts --disable-libatomic --with-system-zlib \
			$ADD_OPTS

#			--with-lib-path=/usr/$TRIPLET/lib$LIBDIRSUFFIX:$SYSROOT/usr/local/lib$LIBDIRSUFFIX:$SYSROOT/lib$LIBDIRSUFFIX:$SYSROOT/usr/lib$LIBDIRSUFFIX

		make -j$NUMJOBS all-gcc all-target-libgcc
		make DESTDIR=$(pwd)/root install-gcc install-target-libgcc
		PKGDESC1="This compiler has no notion of a libc, so it just works for"
		PKGDESC2="self-hosting binaries like the Linux kernels or bootloaders."
		PKGNAME="$PKGNAM-stage1"
		;;
	stage2)
		$SRC_PATH/configure $HOST_OPTS --target=$TRIPLET \
			--host=$HTRIPLET --build=$HTRIPLET \
			--with-sysroot=$SYSROOT --disable-bootstrap \
			--enable-languages=c --enable-multilib \
			--enable-shared --disable-nls --with-system-zlib \
			$ADD_OPTS

#			--with-lib-path=/usr/$TRIPLET/lib$LIBDIRSUFFIX:/usr/local/lib$LIBDIRSUFFIX:/lib$LIBDIRSUFFIX:/usr/lib$LIBDIRSUFFIX
		make -j$NUMJOBS
		make DESTDIR=$(pwd)/root install
		PKGDESC1="This compiler requires a set of target libraries installed"
		PKGDESC2="in $SYSROOT to create user-land binaries."
		PKGNAME="$PKGNAM"
		;;
	skipbuild)
		PKGDESC1="This compiler has no notion of a libc, so it just works for"
		PKGDESC2="self-hosting binaries like the Linux kernels or bootloaders."
		PKGNAME="$PKGNAM-stage1"
		;;
	*)
		echo "unknown stage \"$1\""
		exit 2
		;;
esac

mkdir -p root/usr/gnemul/$TARGET

[ -z "$package" ] && exit 0

(cd root
	rm -Rf usr/include usr/man usr/info
	rm -Rf usr/share/man usr/share/info
	rmdir usr/share 2> /dev/null
	rm -f usr/$LIBDIR/libiberty.a
	find ./ | xargs file | grep -e "executable" -e "shared object" \
	| grep ELF | cut -f 1 -d : | xargs strip --strip-unneeded 2> /dev/null
)

if [ "$package" = "slackware" ]
then
	PKGNAME="${PKGNAME}-${TRIPLET}"
	mkdir root/install
	cat > root/install/slack-desc << _EOF
$PKGNAME: $TARGET-gcc (GNU C cross compiler)
$PKGNAME:
$PKGNAME: GCC is the GNU Compiler Collection. This is a version 4 compiler
$PKGNAME: generating code for CPUs using the $TARGET architecture.
$PKGNAME: $PKGDESC1
$PKGNAME: $PKGDESC2
$PKGNAME: Target is: $TRIPLET
$PKGNAME: Version $VERSION
$PKGNAME:
_EOF
	(cd root; makepkg -c y -l y ../$PKGNAME-$VERSION-$HARCH-$BUILD.txz)
	exit 0
fi

[ "$package" = "debian" ] || exit 1

mkdir debian debian/control
(	cd root
	find * -type f | sort | xargs md5sum > ../debian/control/md5sums
	tar c -J --owner=root --group=root -f ../debian/data.tar.xz ./
)
SIZE=`du -s root | cut -f1`

cat > debian/control/control << _EOF
Package: $PKGNAME-$TRIPLET
Source: $PKGNAM-$VERSION
Version: $VERSION
Installed-Size: $SIZE
Maintainer: Andre Przywara <osp@andrep.de>
Architecture: $HARCH
Depends: binutils-aarch64-linux-gnu (>= 2.21.1), libc6, libgmp10, libmpc2, libmpfr4 (>= 2.4.0), zlib1g (>= 1:1.1.4)
Built-Using: binutils
Section: devel
Priority: extra
Description: GNU C compiler for the $TRIPLET target
 This is the GNU C compiler, a fairly portable optimizing compiler for C.
 .
 This package contains the C cross-compiler for the $TARGET architecture.
 $PKGDESC1
 $PKGDESC2
_EOF

(cd debian/control; tar c -z --owner=root --group=root -f ../control.tar.gz *)
echo "2.0" > debian/debian-binary
(cd debian; ar q ../${PKGNAM}-${TRIPLET}_${VERSION}-${BUILD}_${HARCH}.deb debian-binary control.tar.gz data.tar.xz)
