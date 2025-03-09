vim9script
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8+ (and Neovim)
#
# Maintainer:   Ken Takata
# Last Change:  2020-08-22
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

# Get a list of package/plugin directories.
export def GetPackages(...rest: list<any>): list<string>
  return call("minpac#impl#GetPackages", rest)
enddef


def EnsureInitialization()
  if !exists('g:minpac#opt')
    echohl WarningMsg
    echom 'Minpac has not been initialized. Use the default values.'
    echohl None
    call Init()
  endif
enddef

# Initialize minpac.
export def Init(...rest: list<any>)
  var opt = extend(copy(get(rest, 0, {})),
    {'dir': '', 'package_name': 'minpac', 'git': 'git', 'depth': 1,
      'jobs': 8, 'verbose': 2, 'confirm': true,
      'progress_open': 'horizontal', 'status_open': 'horizontal',
      'status_auto': false}, 'keep')

  g:minpac#opt = opt
  g:minpac#pluglist = {}

  var packdir = opt.dir
  if packdir->empty()
    # If 'dir' is not specified, the first directory of 'packpath' is used.
    packdir = split(&packpath, ',')[0]
  endif

  opt.minpac_dir = packdir .. '/pack/' .. opt.package_name
  opt.minpac_start_dir = opt.minpac_dir .. '/start'
  opt.minpac_opt_dir = opt.minpac_dir .. '/opt'

  # directories for 'subdir'
  opt.minpac_dir_sub = packdir .. '/pack/' .. opt.package_name .. '-sub'
  opt.minpac_start_dir_sub = opt.minpac_dir_sub .. '/start'
  opt.minpac_opt_dir_sub = opt.minpac_dir_sub .. '/opt'

  if !isdirectory(packdir)
    echoerr 'Pack directory not available: ' .. packdir
    return
  endif
  if !isdirectory(opt.minpac_start_dir)
    mkdir(opt.minpac_start_dir, 'p')
  endif
  if !isdirectory(opt.minpac_opt_dir)
    mkdir(opt.minpac_opt_dir, 'p')
  endif
enddef


# Register the specified plugin.
export def Add(plugname: string, ...rest: list<any>)
  EnsureInitialization()
  var opt = extend(copy(get(rest, 0, {})),
    {'name': '', 'type': 'start', 'depth': g:minpac#opt.depth,
      'frozen': false, 'branch': '', 'rev': '', 'do': '', 'subdir': '',
      'pullmethod': ''}, 'keep')

  # URL
  if plugname =~? '^[-._0-9a-z]\+\/[-._0-9a-z]\+$'
    opt.url = 'https://github.com/' .. plugname .. '.git'
  else
    opt.url = plugname
  endif

  # Name of the plugin
  if opt.name == ''
    opt.name = matchstr(opt.url, '[/\\]\zs[^/\\]\+$')
    opt.name = substitute(opt.name, '\C\.git$', '', '')
  endif
  if opt.name == ''
    echoerr 'Cannot extract the plugin name. (' .. plugname .. ')'
    return
  endif

  # Loading type / Local directory
  if opt.type == 'start'
    opt.dir = g:minpac#opt.minpac_start_dir .. '/' .. opt.name
  elseif opt.type == 'opt'
    opt.dir = g:minpac#opt.minpac_opt_dir .. '/' .. opt.name
  else
    echoerr plugname .. ": Wrong type (must be 'start' or 'opt'): " .. opt.type
    return
  endif

  # Check pullmethod
  if opt.pullmethod != '' && opt.pullmethod != 'autostash'
    echoerr plugname .. ": Wrong pullmethod (must be empty or 'autostash'): " .. opt.pullmethod
    return
  endif

  # Initialize the status
  opt.stat = {'errcode': 0, 'lines': [], 'prev_rev': '', 'installed': -1}

  # Add to pluglist
  g:minpac#pluglist[opt.name] = opt
enddef


# Update all or specified plugin(s).
export def Update(...rest: list<any>): bool
  EnsureInitialization()
  return call("minpac#impl#Update", rest)
enddef


# Remove plugins that are not registered.
export def Clean(...rest: list<any>): bool
  EnsureInitialization()
  return call("minpac#impl#Clean", rest)
enddef

export def Status(...rest: list<any>)
  EnsureInitialization()
  const opt = extend(copy(get(rest, 0, {})),
    {'open': g:minpac#opt.status_open}, 'keep')
  # return minpac#status#Get(opt)
  minpac#status#Get(opt)
enddef


# Get information of specified plugin. Mainly for debugging.
export def GetPlugInfo(name: string)
  EnsureInitialization()
  return g:minpac#pluglist[name]
enddef


# Get a list of plugin information. Mainly for debugging.
export def GetPlugList()
  return g:minpac#pluglist
enddef

# Abort updating the plugins.
export def Abort()
  # return minpac#impl#Abort()
  minpac#impl#Abort()
enddef

# vim: set ts=8 sw=2 et:
