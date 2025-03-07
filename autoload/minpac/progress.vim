vim9script
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8+ (and Neovim)
#
# Maintainer:   Ken Takata
# Last Change:  2020-01-28
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

var winid = 0
var bufnr = 0

# Add a message to the minpac progress window
export def AddMsg(type: string, msg: string)
  # Goes to the minpac progress window.
  if !win_gotoid(winid)
    echom 'warning: minpac progress window not found'
    return
  endif

  setlocal modifiable
  const markers = {'': '  ', 'warning': 'W:', 'error': 'E:'}
  append(line('$') - 1, markers[type] .. ' ' .. msg)
  setlocal nomodifiable
  redraw
enddef

# Open the minpac progress window
export def Open(msg: list<string>)
  const bufname = '[minpac progress]'
  if bufnr != 0
    exec "silent! bwipe" bufnr
  endif

  if g:minpac#opt.progress_open == "vertical"
    vertical topleft new
  elseif g:minpac#opt.progress_open == "horizontal"
    topleft new
  elseif g:minpac#opt.progress_open == "tab"
    tabnew
  endif

  winid = win_getid()
  append(0, msg)

  setf minpacprgs
  Syntax()
  Mappings()
  setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nomodifiable nospell
  silent file `=bufname`
  bufnr = bufnr('')
enddef

def Syntax()
  syntax clear
  syn match minpacPrgsTitle     /^## .* ##/
  syn match minpacPrgsError     /^E: .*/
  syn match minpacPrgsWarning   /^W: .*/
  syn match minpacPrgsInstalled /^   Installed:/
  syn match minpacPrgsUpdated   /^   Updated:/
  syn match minpacPrgsUptodate  /^   Already up-to-date:/
  syn region minpacPrgsString start='"' end='"'

  hi def link minpacPrgsTitle     Title
  hi def link minpacPrgsError     ErrorMsg
  hi def link minpacPrgsWarning   WarningMsg
  hi def link minpacPrgsInstalled Constant
  hi def link minpacPrgsUpdated   Special
  hi def link minpacPrgsUptodate  Comment
  hi def link minpacPrgsString    String
enddef

def Mappings()
  nnoremap <silent><buffer><nowait> q :q<CR>
  nnoremap <silent><buffer><nowait> s :call minpac#status()<CR>
enddef

# vim: set ts=8 sw=2 et:
