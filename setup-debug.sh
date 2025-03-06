#!/usr/bin/env bash
set -xeuo pipefail

# Ensure you run this script from the root project folder

dir_debug=debug
dir_fundamental=$dir_debug/fundamental
file_init=$dir_debug/init.vim

mkdir $dir_debug
mkdir $dir_fundamental
mkdir -p $dir_fundamental/pack/minpac/opt

ln -s $PWD $PWD/$dir_fundamental/pack/minpac/opt/

cat > $file_init <<- EOF
set nocompatible

packadd minpac
call minpac#init()
call minpac#add('k-takata/minpac', {'type': 'opt'})
call minpac#add('vim-jp/syntax-vim-ex')
call minpac#add('tyru/open-browser.vim')

command! PackUpdate call minpac#update()
command! PackClean  call minpac#clean()
command! PackStatus call minpac#status()
EOF

echo vim --clean \"+set runtimepath^=\$PWD/$dir_fundamental\" \"+set packpath^=\$PWD/$dir_fundamental\" \"+source \$PWD/$file_init\"
