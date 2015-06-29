#!/bin/sh

PKGNAM=kernel-headers
BUILD=${BUILD:-1}
TARGET=${TARGET:-aarch64}
SYSROOT=/usr/gnemul/$TARGET

if [ ! -d arch -o ! -r Makefile -o ! -r Kconfig ]; then
	echo "looks like $(pwd) is not a kernel source directory"
	echo "please cd into a directory containing the kernel source"
	exit 1
fi

if [ -z "$VERSION" ]; then
	if [ -d .git ]; then
		VERSION=$(git describe | sed -e 's/^v//' | tr '-' '_')
	else
		VERSION=$(basename $(pwd) | sed -e 's/^linux-//')
	fi
fi

if [ "x$1" = 'x-h' ]
then
	echo "usage: $0 [package]"
	exit 1
fi

if [ "x$1" = "xpackage" ]; then
	package=y
	shift
else
	package=n
fi

LARCH=$TARGET
case "$TARGET" in
	i?86)		TARGET=i486; LARCH="x86" ;;
	x86_64|x32)	LARCH="x86" ;;
	arm64|aarch64)	LARCH="arm64" ;;
	arm*)		LARCH=arm ;;
	mips64)		LARCH=mips ;;
	powerpc*)	LARCH=powerpc ;;
esac

TMPDIR=/tmp/package-$PKGNAM
rm -Rf $TMPDIR
mkdir -p $TMPDIR

make O=$TMPDIR ARCH=$LARCH INSTALL_HDR_PATH=./$SYSROOT/usr headers_install
rm -Rf $TMPDIR/arch $TMPDIR/include $TMPDIR/scripts
find $TMPDIR -name .install -o -name ..install.cmd | xargs rm -f
mv $TMPDIR/$SYSROOT/usr/include/asm{,-$LARCH}
ln -s asm-$LARCH $TMPDIR/$SYSROOT/usr/include/asm

[ "$package" = "y" ] || exit 0

mkdir $TMPDIR/install
cat > $TMPDIR/install/slack-desc << _EOF
$PKGNAM-$TARGET: kernel-headers for $TARGET (Linux kernel include files)
$PKGNAM-$TARGET:
$PKGNAM-$TARGET: These are the include files from the Linux kernel.
$PKGNAM-$TARGET:
$PKGNAM-$TARGET: You'll need these to cross-compile most system software
$PKGNAM-$TARGET: for Linux. Installed in a directory used for cross-
$PKGNAM-$TARGET: compilation to not interfer with the system headers.
$PKGNAM-$TARGET:
$PKGNAM-$TARGET: v$VERSION for $TARGET by Andre Przywara <osp@andrep.de>
$PKGNAM-$TARGET:
_EOF

(	cd $TMPDIR; \
	makepkg -c y -l y /tmp/$PKGNAM-$TARGET-$VERSION-noarch-$BUILD.txz \
)
