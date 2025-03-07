vim9script
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8+ (and Neovim)
#
# Maintainer:   Ken Takata
# Created By:   Kristijan Husak
# Last Change:  2020-01-28
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

var results = []
var bufnr = 0
var git_sign = true   # Support --no-show-signature option.
var is_git_sign_set = false

export def Get(opt: dict<any>)
  const bufname = '[minpac status]'
  if bufnr != 0
    exec "silent! bwipe" bufnr
  endif

  const is_update_ran = minpac#impl#is_update_ran()
  var update_count = 0
  var install_count = 0
  var error_count = 0
  var result = []

  for name in keys(g:minpac#pluglist)
    const pluginfo = g:minpac#pluglist[name]
    const dir = pluginfo.dir
    var plugin = {'name': name, 'lines': [], 'status': ''}

    if !isdirectory(dir)
      plugin.status = 'Not installed'
    else
      const cmd = [g:minpac#opt.git, '-C', dir, 'log', '--color=never', '--pretty=format:%h <<<<%D>>>> %s(%cr)', 'HEAD...HEAD@{1}']
      var commits = minpac#impl#system(cmd + (git_sign ? ['--no-show-signature'] : []))

      if !is_git_sign_set
        if commits[0] == 128
          git_sign = false
          commits = minpac#impl#system(cmd)
        else
          git_sign = true
        endif
      endif

      plugin.lines = commits[1]->filter((index, value) => !value->empty())

      plugin.lines->map((index, value) =>
        substitute(value, '^[0-9a-f]\{4,} \zs<<<<\(.*\)>>>> ', (matches) => {
            return matches[1] =~ '^tag: ' ? '(' .. matches[1] .. ') ' : ''
          }, ''))
      
      if !is_update_ran
        plugin.status = 'OK'
      elseif pluginfo.stat.prev_rev != '' && pluginfo.stat.prev_rev != minpac#impl#get_plugin_revision(name)
        update_count += 1
        plugin.status = 'Updated'
      elseif pluginfo.stat.installed == 0
        install_count += 1
        plugin.status = 'Installed'
      elseif pluginfo.stat.errcode != 0
        error_count += 1
        plugin.status = 'Error (' .. pluginfo.stat.errcode .. ')'
      endif
    endif

    result->add(plugin)
  endfor

  # Show items with most lines (commits) first.
  result->sort((first, second) => len(second.lines) - len(first.lines))
  results = result

  var content = []

  if is_update_ran
    content->add(update_count .. ' updated. ' .. install_count .. ' installed. ' .. error_count .. ' failed.')
    content->add('')
  endif

  for item in result
    if item.status->empty()
      continue
    endif

    content->add('- ' .. item.name .. ' - ' .. item.status)
    if item.status =~ '^Error'
      for line in g:minpac#pluglist[item.name].stat.lines
        content->add(' msg: ' .. line)
      endfor
    else
      for line in item.lines
        content->add(' * ' .. line)
      endfor
    endif
    content->add('')
  endfor

  if content->len() > 0 && content[-1]->empty()
    content->remove(-1)
  endif

  if opt.open == 'vertical'
    vertical topleft new
  elseif opt.open == 'horizontal'
    topleft new
  elseif opt.open == 'tab'
    tabnew
  endif

  setf minpac
  append(1, content)
  :1delete _
  Syntax()
  Mappings()
  setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap cursorline nomodifiable nospell
  silent file `=bufname`
  bufnr = bufnr('')
enddef

def Syntax()
  syntax clear
  syn match minpacDash /^-/
  syn match minpacName /\(^- \)\@<=.*/ contains=minpacStatus
  syn match minpacStatus /\(-.*\)\@<=-\s.*$/ contained
  syn match minpacStar /^\s\*/ contained
  syn match minpacCommit /^\s\*\s[0-9a-f]\{7,9} .*/ contains=minpacRelDate,minpacSha,minpacStar
  syn match minpacSha /\(\s\*\s\)\@<=[0-9a-f]\{4,}/ contained nextgroup=minpacTag
  syn match minpacTag / (tag: [^)]*)/ contained
  syn match minpacRelDate /([^)]*)$/ contained
  syn match minpacWarning /^ msg: .*/

  hi def link minpacDash    Special
  hi def link minpacStar    Boolean
  hi def link minpacName    Function
  hi def link minpacSha     Identifier
  hi def link minpacTag     PreProc
  hi def link minpacRelDate Comment
  hi def link minpacStatus  Constant
  hi def link minpacWarning WarningMsg
enddef

def Mappings()
  nnoremap <silent><buffer><nowait> <CR> :call <SID>OpenSha()<CR>
  nnoremap <silent><buffer><nowait> q :q<CR>
  if !exists("no_plugin_maps") && !exists("no_minpac_maps")
    nnoremap <silent><buffer><nowait> <C-j> :call <SID>NextPackage()<CR>
    nnoremap <silent><buffer><nowait> <C-k> :call <SID>PrevPackage()<CR>
  endif
enddef

def NextPackage(): number
  return search('^-\s.*$')
enddef

def PrevPackage(): number
  return search('^-\s.*$', 'b')
enddef

def OpenSha()
  const sha = matchstr(getline('.'), '^\s\*\s\zs[0-9a-f]\{7,9}')
  if sha->empty()
    return
  endif

  const name = FindNameBySha(sha)
  if name->empty()
    return
  endif

  const pluginfo = g:minpac#pluglist[name]
  silent exe 'pedit' sha
  wincmd p
  setlocal previewwindow filetype=git buftype=nofile nobuflisted modifiable
  const sha_content = minpac#impl#system([g:minpac#opt.git, '-C', pluginfo.dir, 'show',
            \ '--no-color', '--pretty=medium', sha
            \ ])

  append(1, sha_content[1])
  :1delete _
  setlocal nomodifiable
  nnoremap <silent><buffer> q :q<CR>
enddef

def FindNameBySha(sha: string): string
  for result in results
    for commit in result.lines
      if commit =~? '^' .. sha
        return result.name
      endif
    endfor
  endfor

  return ''
enddef

# vim: set ts=8 sw=2 et:
