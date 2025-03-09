vim9script
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8+ (and Neovim)
#
# Maintainer:   Ken Takata
# Last Change:  2020-08-22
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

import autoload '../autoload/minpac.vim' as minpac_al

if exists('g:loaded_minpac')
  finish
endif
g:loaded_minpac = 1

g:minpac#getpackages = minpac_al.GetPackages
g:minpac#init = minpac_al.Init
g:minpac#add = minpac_al.Add
g:minpac#update = minpac_al.Update
g:minpac#clean = minpac_al.Clean
g:minpac#status = minpac_al.Status
g:minpac#getpluginfo = minpac_al.GetPlugInfo
g:minpac#getpluglist = minpac_al.GetPlugList
g:minpac#abort = minpac_al.Abort
