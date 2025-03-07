vim9script
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8+ (and Neovim)
#
# Maintainer:   Ken Takata
# Last Change:  2020-02-01
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

def GetGitDir(dir: string): string
  var gitdir = dir .. '/.git'
  if isdirectory(gitdir)
    return gitdir
  endif

  try
    const line = readfile(gitdir)[0]

    if line =~ '^gitdir: '
      gitdir = line[8 : ]

      if !isabsolutepath(gitdir)
        gitdir = dir .. '/' .. gitdir
      endif

      if isdirectory(gitdir)
        return gitdir
      endif
    endif

  catch
  endtry

  return null_string
enddef

export def GetRevision(dir: string): string
  const gitdir = GetGitDir(dir)
  if gitdir->empty()
    return null_string
  endif

  try
    const head_file = gitdir .. '/HEAD'
    const line = readfile(head_file)[0]

    if line =~ '^ref: '
      const ref = line[5 : ]

      const ref_file = gitdir .. '/' .. ref
      if filereadable(ref_file)
        return readfile(ref_file)[0]
      endif

      const packed_refs_file = gitdir .. '/packed-refs'
      for packed_line in readfile(packed_refs_file)
        if packed_line =~ ' ' .. ref .. '$'
          return substitute(packed_line, '^\([0-9a-f]\+\) .*$', '\1', '')
        endif
      endfor

      return null_string
    endif

    return line
  catch
  endtry

  return null_string
enddef

export def GetBranch(dir: string): string
  const gitdir = GetGitDir(dir)
  if gitdir->empty()
    return null_string
  endif

  try
    const line = readfile(gitdir .. '/HEAD')[0]
    if line =~ '^ref: refs/heads/'
      return line[16 : ]
    endif
  catch
  endtry

  return null_string
enddef

# vim: set ts=8 sw=2 et:
