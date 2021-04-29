#!/bin/bash

script_root="$(dirname $(readlink -f "$0"))"
project_root="$(readlink -f $script_root/../)"
psplash_source_package=$project_root/buildroot/dl/psplash/psplash-*.tar.gz

[ -z $1 ] && echo "Usage: $0 <image path>.png" && exit 1
[ ! -f $1 ] && echo "File $1 does not exist" && exit 1
[ ! -f $psplash_source_package ] && echo "Psplash has not been downloaded yet! Please do a make first!" && exit 1

set -e


echo "getting psplash version"
psplash_version=$(basename $(ls $psplash_source_package) | sed -e 's/.*-\(.*\)-.*/\1/')
echo "psplash version is: $psplash_version"
psplash_version_dir=psplash-$psplash_version
target_header=$psplash_version_dir/psplash-poky-img.h
target_patch_name=0002-custom-splash-image.patch
target_patch_dir=$script_root/../patches/psplash

mkdir -p $script_root/.tmp
cp $1 $script_root/.tmp/image.png
cd $script_root/.tmp

mkdir -p $psplash_version_dir

echo "Creating .h file"
gdk-pixbuf-csource --macros image.png > $target_header.tmp
sed -e "s/MY_PIXBUF/POKY_IMG/g" -e "s/guint8/uint8/g" $target_header.tmp > $target_header && rm $target_header.tmp

echo "Creating patch"
if diff -u /dev/null $target_header > $target_patch_name ; then
  echo "Error"
  exit 1
fi

echo "Copying patch"
mkdir -p $target_patch_dir
cp $target_patch_name $target_patch_dir

echo "Cleaning up"
cd ..
rm -rf .tmp

echo "Making psplash-dirclean for all targets"
output_dirs=$(ls $project_root/outputs)
for i in $output_dirs; do
  cd $project_root/outputs/$i
  echo "* $i"
  make psplash-dirclean
done

echo
echo "Successfully generated patch and placed it in $(readlink -f $target_patch_dir/$target_patch_name)"