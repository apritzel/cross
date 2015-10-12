#!/bin/sh

PKGNAM=glibc
VERSION=${VERSION:-"2.22"}
BUILD=${BUILD:-"1"}

TARGET=${TARGET:-"aarch64"}
SYSROOT=/usr/gnemul/$TARGET

NUMJOBS=${NUMJOBS:-"8"}
NUMJOBS="-j$NUMJOBS"

if [ "x$1" = "x-h" ]; then
	echo "usage: $0 [package] [multiarch] [source path]"
	exit 1
fi

multiarch=0
[ -f /etc/debian_version ] && system="debian"
[ -f /etc/slackware-version ] && system="slackware"
[ "x$system" = "xdebian" ] && multiarch=1
SRC_PATH=""
package=""
while [ $# -gt 0 ]
do
	case "$1" in
		debian) package="debian" ;;
		slackware) package="slackware" ;;
		package) package="$system" ;;
		multiarch) multiarch=1 ;;
		nomultiarch) multiarch=0 ;;
		*) [ -d "$1" ] && SRC_PATH="$1" ;;
	esac
	shift
done

if [ -z "$SRC_PATH" ]
then
        testdir=../${PKGNAM}.git
        [ -d "$testdir" ] && SRC_PATH="$testdir"
        testdir=../${PKGNAM}
        [ -d "$testdir" ] && SRC_PATH="$testdir"
        testdir=../${PKGNAM}-${VERSION}
        [ -d "$testdir" ] && SRC_PATH="$testdir"
	[ -n "$SRC_PATH" ] && echo "autodetected source directory as \"$SRC_PATH\""
fi

if [ ! -d "$SRC_PATH" ]
then
        echo "Error: could not find source directory."
        echo "Give the source path as an argument."
        exit 1
fi

MARCH=`uname -m`
case "$MARCH" in
	i?86) MARCH=i486 ;;
	x86_64) [ "$system" = "debian" ] && MARCH="amd64" ;;
	arm*) MARCH=arm ;;
esac
HTRIPLET=`gcc -dumpmachine`

case "$system" in
	slackware) vendor="slackware"; os="linux"; slackware="slackware-" ;;
	*) vendor="linux"; os="gnu" ;;
esac

BITNESS=""
TRIPLET=${TARGET}-${vendor}-${os}
case "$TARGET" in
        x86_64|aarch64|powerpc64|powerpc64le) BITNESS="64";;
	x32) TRIPLET=x86_64-${slackware}linux-gnux32; BITNESS="x32"; ABI_VARIANT="-mx32";;
        armhf) TRIPLET=arm-${slackware}linux-gnueabihf;;
        arm) TRIPLET=arm-${slackware}linux-gnueabi;;
        openwrt) TRIPLET=mips-openwrt-linux-uclibc;;
esac

HOST_OPTS="--prefix=/usr --with-gnu-ld --with-gnu-as"
if [ "$multiarch" -eq 0 ]
then
	LIBDIR="lib$BITNESS"
	HOST_OPTS="$HOST_OPTS --disable-multiarch"
else
	LIBDIR="lib/$TRIPLET"
	HOST_OPTS="$HOST_OPTS --enable-multiarch"
fi
HOST_OPTS="$HOST_OPTS --libdir=/usr/$LIBDIR"

CC=${CC:-"${TRIPLET}-gcc"}
[ -n "$ABI_VARIANT" ] && export CC="$CC $ABI_VARIANT"

CFLAGS="-O2 -DBOOTSTRAP_GCC" \
$SRC_PATH/configure \
  libc_cv_forced_unwind=yes libc_cv_c_cleanup=yes libc_cv_gnu89_inline=yes \
  libc_cv_ssp=no \
  $HOST_OPTS \
  --host=$TRIPLET \
  --build=$HTRIPLET \
  --without-cvs \
  --disable-nls \
  --disable-sanity-checks \
  --enable-obsolete-rpc \
  --disable-profile \
  --disable-debug \
  --without-selinux \
  --with-tls \
  --enable-kernel=3.7.0 \
  --with-headers=$SYSROOT/usr/include \
  --enable-hacker-mode

make $NUMJOBS

[ -d ./root ] && rm -Rf ./root
mkdir root
make DESTDIR=`pwd`/root install

[ -z "$package" ] && exit 0

(	cd root
	rm -f usr/info/dir
	gzip -9 usr/info/* 2> /dev/null
	find ./ | xargs file | grep -e "executable" -e "shared object" \
		| grep ELF | cut -f 1 -d : \
		| xargs ${TRIPLET}-strip --strip-unneeded 2> /dev/null
)

if [ "$package" = "slackware" ]
then
	mkdir root/install
	cat > root/install/slack-desc << _EOF
$PKGNAM: glibc (GNU C libraries)
$PKGNAM:
$PKGNAM: This package contains the GNU C libraries and header files.  The GNU
$PKGNAM: C library was written originally by Roland McGrath, and is currently
$PKGNAM: maintained by Ulrich Drepper.  Some parts of the library were
$PKGNAM: contributed or worked on by other people.
$PKGNAM:
$PKGNAM: You'll need this package to compile programs.
$PKGNAM:
_EOF

	(cd root; makepkg -c y -l y ../$PKGNAM-$VERSION-$TARGET-$BUILD.txz)
	exit 0
fi

[ "$package" = "debian" ] || exit 1

mkdir debian debian/control
(	cd root
	find * -type f | sort | xargs md5sum > ../debian/control/md5sums
	tar c -z --owner=root --group=root -f ../debian/data.tar.gz ./
)
SIZE=`du -s root | cut -f1`

cat > debian/control/control << _EOF
Package: $PKGNAM
Source: $PKGNAM
Version: $VERSION
Installed-Size: $SIZE
Maintainer: Andre Przywara <osp@andrep.de>
Architecture: $TARGET
Depends:
Provides: ${PKGNAM}-${VERSION}
Section: libs
Priority: required
Description: GNU C library: Shared libraries and headers
 Contains the standard libraries that are used by nearly all programs on
 the system. This package includes shared versions of the standard C library
 and the standard math library, as well as many others.
 Also contains the respective header files.
_EOF

(cd debian/control; tar c -z --owner=root --group=root -f ../control.tar.gz *)
echo "2.0" > debian/debian-binary
(cd debian; ar q ../${PKGNAM}_${VERSION}-${BUILD}_${TARGET}.deb debian-binary control.tar.gz data.tar.gz)
