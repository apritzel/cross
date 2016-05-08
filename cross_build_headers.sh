#!/bin/sh

PKGNAM=kernel-headers
BUILD=${BUILD:-1}
TARGET=${TARGET:-aarch64}
TMP=${TMP:-/tmp}

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
	arm64|aarch64*)	LARCH="arm64" ;;
	arm*)		LARCH=arm ;;
	mips64)		LARCH=mips ;;
	powerpc*)	LARCH=powerpc ;;
	sparc*)		LARCH=sparc ;;
	hppa*)		LARCH=parisc ;;
esac

TMPDIR=$TMP/package-$PKGNAM
rm -Rf $TMPDIR
mkdir -p $TMPDIR

make O=$TMPDIR ARCH=$LARCH INSTALL_HDR_PATH=./usr headers_install
rm -Rf $TMPDIR/arch $TMPDIR/include $TMPDIR/scripts
find $TMPDIR -name .install -o -name ..install.cmd | xargs rm -f
mv $TMPDIR/usr/include/asm{,-$LARCH}
ln -s asm-$LARCH $TMPDIR/usr/include/asm

[ "$package" = "y" ] || exit 0

mkdir $TMPDIR/install
cat > $TMPDIR/install/slack-desc << _EOF
$PKGNAM: kernel-headers (Linux kernel include files)
$PKGNAM:
$PKGNAM: These are the include files from the Linux kernel.
$PKGNAM:
$PKGNAM: You'll need these to compile most system software for Linux.
$PKGNAM:
$PKGNAM: v$VERSION for $TARGET packaged by Andre Przywara <osp@andrep.de>
$PKGNAM:
_EOF

(	cd $TMPDIR; \
	makepkg -c y -l y /tmp/$PKGNAM-$VERSION-$TARGET-$BUILD.txz \
)
