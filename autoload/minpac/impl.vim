vim9script
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8+ (and Neovim)
#
# Maintainer:   Ken Takata
# Last Change:  2024-12-06
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

var joblist = []        # Jobs that are currently running.
var jobqueue = []       # Jobs that are waiting to be started.
var remain_plugins = 0
var timer_id = -1

var updated_plugins = 0
var installed_plugins = 0
var Finish_update_hook: any
var error_plugins = 0

var save_more_to_set = false
var save_more = false

# vim9script
# def F(a: number, b: string): number
#   echo a .. ', ' .. b
#   return 100
# enddef
# g:abc#xyz#f = F
# echo F(-50, 'hobo')
# echo abc#xyz#f(-500, 'hobov2')
# echo string(F)
# echo string(g:abc#xyz#f)
# echo F == g:abc#xyz#f

# Get a list of package/plugin directories.
export def GetPackages(...rest: list<any>): list<string>
  var packname = get(rest, 0, '')
  var packtype = get(rest, 1, '')
  var plugname = get(rest, 2, '')
  const nameonly = get(rest, 3, false)

  if packname->empty() | packname = '*' | endif
  if packtype->empty() | packtype = '*' | endif
  if plugname->empty() | plugname = '*' | endif

  var pat = ''
  if packtype == 'NONE'
    pat = 'pack/' .. packname
  else
    pat = 'pack/' .. packname .. '/' .. packtype .. '/' .. plugname
  endif

  var ret = filter(globpath(&packpath, pat, 0, 1), (key, value) => isdirectory(value))
  if nameonly
    map(ret, (key, value) => substitute(value, '^.*[/\\]', '', ''))
  endif
  return ret
enddef


def EchoXVerbose(level: number, echocmd: string, type: string, msg: string)
  if g:minpac#opt.verbose >= level
    if g:minpac#opt.progress_open == 'none'
      if type == 'warning'
        echohl WarningMsg
      elseif type == 'error'
        echohl ErrorMsg
      endif
      exec echocmd .. " '" .. substitute(msg, "'", "''", "g") .. "'"
      echohl None
    else
      minpac#progress#AddMsg(type, msg)
    endif
  endif
enddef

def EchoVerbose(level: number, type: string, msg: string)
  EchoXVerbose(level, 'echo', type, msg)
enddef

def EchoMVerbose(level: number, type: string, msg: string)
  EchoXVerbose(level, 'echom', type, msg)
enddef

def EchoErrVerbose(level: number, msg: string)
  EchoXVerbose(level, 'echoerr', 'error', msg)
enddef

if has('win32')
  def QuoteCmds(cmds: list<string>): list<string>
    # If space (or brace) is found, surround the argument with "".
    # Assuming double quotations are not used elsewhere.
    # (Brace needs to be quoted for msys2/git.)
    return join(map(cmds, (key, value) => {
      (value =~ '[ {]') ? '"' .. value .. '"' : value
    }), ' ')
  enddef
else
  def QuoteCmds(cmds: list<string>): list<string>
    return cmds
  enddef
endif

# Replacement for system().
# This doesn't open an extra window on MS-Windows.
export def System(cmds: list<string>): list<any>
  var out = []
  var ret = -1
  const quote_cmds = QuoteCmds(cmds)
  EchoMVerbose(4, '', 'system: cmds=' .. string(quote_cmds))
  const job = minpac#job#Start(quote_cmds, {
    'on_stdout': (id, mes, ev) => extend(out, mes)
  })
  if job > 0
    # It worked!
    ret = minpac#job#Wait([job])[0]
    sleep 5m    # Wait for out_cb. (not sure this is enough.)
  endif
  return [ret, out]
enddef

# Execute git command on the specified plugin directory.
def ExecPluginCmd(name: string, cmd: list<string>, mes: string): string
  const pluginfo = g:minpac#pluglist[name]
  const dir = pluginfo.dir
  const res = System([g:minpac#opt.git, '-C', dir]
    + ['-c', 'core.fsmonitor=false'] + cmd)
  if res[0] == 0 && len(res[1]) > 0
    call EchoMVerbose(4, '', mes .. ': ' .. res[1][0])
    return res[1][0]
  else
    # Error
    return ''
  endif
enddef

# Get the revision of the specified plugin.
export def GetPluginRevision(name: string): string
  const rev = minpac#git#GetRevision(g:minpac#pluglist[name].dir)
  if rev != null_string
    EchoMVerbose(4, '', 'revision (' .. name .. '): ' .. rev)
    return rev
  endif
  return ExecPluginCmd(name, ['rev-parse', 'HEAD'], 'revision')
enddef

# Get the exact tag name of the specified plugin.
def GetPluginTag(name: string): string
  return ExecPluginCmd(name, ['describe', '--tags', '--exact-match'], 'tag')
enddef

# Get the latest tag name of the specified plugin. Sorted by version number.
def GetPluginLatestTag(name: string, tag: string): string
  return ExecPluginCmd(name, ['tag', '--list', '--sort=-version:refname', tag], 'latest tag')
enddef

# Get the branch name of the specified plugin.
def GetPluginBranch(name: string): string
  const branch = minpac#git#GetBranch(g:minpac#pluglist[name].dir)
  if branch != null_string
    EchoMVerbose(4, '', 'branch: ' .. branch)
    return branch
  endif
  return ExecPluginCmd(name, ['symbolic-ref', '--short', 'HEAD'], 'branch')
enddef


def DecrementPluginCount()
  remain_plugins -= 1
  if remain_plugins == 0
    timer_stop(timer_id)
    timer_id = -1

    # `minpac#update()` is finished.
    InvokeHook('finish-update', [updated_plugins, installed_plugins], Finish_update_hook)

    # Show the status.
    if error_plugins + updated_plugins + installed_plugins > 0
      if g:minpac#opt.progress_open != 'none'
        EchoMVerbose(1, '', '')   # empty line
      endif
    endif
    if error_plugins > 0
      EchoMVerbose(1, 'warning', 'Error plugins: ' .. error_plugins)
    else
      var mes = 'All plugins are up to date.'
      if updated_plugins + installed_plugins > 0
        mes ..= ' (Updated: ' .. updated_plugins .. ', Newly installed: ' .. installed_plugins .. ')'
      endif
      EchoMVerbose(1, '', mes)
    endif
    if g:minpac#opt.progress_open != 'none'
      EchoMVerbose(1, '', '(Type "q" to close this window. Type "s" to open the status window.)')
    endif

    # Open the status window.
    if updated_plugins + installed_plugins > 0
      if g:minpac#opt.status_auto
        minpac#status()
      endif
    endif

    # Restore the pager.
    if save_more_to_set
      &more = save_more
      save_more_to_set = false
    endif
  endif
enddef

# vim9script
# var Ref = (a: string): string => ''
# def F()
# enddef
# echo Ref
# Ref = function('chdir')
# echo Ref

var Chdir = function('chdir')

if !exists('*chdir')
  Chdir = (dir: string): string => {
    const cdcmd = haslocaldir() ? ((haslocaldir() == 1) ? 'lcd' : 'tcd') : 'cd'
    const pwd = getcwd()
    execute cdcmd fnameescape(dir)
    return pwd
  }
endif

def InvokeHook(hooktype: string, args: list<any>, hook: any)
  if hook->empty()   # works for v:t_func too
    # writefile([
    #   'RETURNED!!!:',
    #   printf('0: %s (%s)', hooktype, typename(hooktype)),
    #   printf('1: %s (%s)', args, typename(args)),
    #   printf('2: %s (%s)', hook, typename(hook)),
    # ], '/dev/shm/minpac-invokehook.log', '')
    return
  endif

  var pwd = ''
  if hooktype == 'post-update'
    const name = args[0]
    const pluginfo = g:minpac#pluglist[name]
    noautocmd pwd = Chdir(pluginfo.dir)
  endif
  try
    if type(hook) == v:t_func
      call(hook, [hooktype] + args)
    elseif type(hook) == v:t_string
      execute hook
    endif
  catch
    EchoMVerbose(1, 'error', v:throwpoint)
    EchoMVerbose(1, 'error', v:exception)
  finally
    if hooktype == 'post-update'
      noautocmd Chdir(pwd)
    endif
  endtry
enddef

def IsHelptagsOld(dir: string): bool
  var txts = glob(dir .. '/*.txt', 1, 1) + glob(dir .. '/*.[a-z][a-z]x', 1, 1)
  var tags = glob(dir .. '/tags', 1, 1) + glob(dir .. '/tags-[a-z][a-z]', 1, 1)
  const txt_newest = max(map(txts, (_, value) => getftime(value)))
  const tag_oldest = min(map(tags, (_, value) => getftime(value)))
  return txt_newest > tag_oldest
enddef

def GenerateHelptags(dir: string)
  const docdir = dir .. '/doc'
  if IsHelptagsOld(docdir)
    silent! execute 'helptags' fnameescape(docdir)
  endif
enddef

def AddRtp(dir: string)
  if empty(&rtp)
    &rtp = dir
  else
    &rtp ..= ',' .. dir
  endif
enddef

var CreateLink = (target: string, link: string) => {
  System(['ln', '-sf', target, link])
}

if has('win32')
  CreateLink = (target: string, link: string) => {
    if isdirectory(target)
      delete(target)
    endif
    System(['cmd.exe', '/c', 'mklink', '/J',
      substitute(link, '/', '\', 'g'),
      substitute(target, '/', '\', 'g')
    ])
  }
endif

def HandleSubdir(pluginfo: dict<any>)
  var workdir = ''
  if pluginfo.type == 'start'
    workdir = g:minpac#opt.minpac_start_dir_sub
  else
    workdir = g:minpac#opt.minpac_opt_dir_sub
  endif
  if !isdirectory(workdir)
    mkdir(workdir, 'p')
  endif
  noautocmd const pwd = Chdir(workdir)
  try
    if !isdirectory(pluginfo.name)
      CreateLink(pluginfo.dir .. '/' .. pluginfo.subdir,
        pluginfo.name)
    endif
  finally
    noautocmd Chdir(pwd)
  endtry
enddef

# vim9script
# class MyClass
#   var data: list<number>
#
#   def Mylen(): number
#      return len(this.data)
#   enddef
# endclass
# var myclass = MyClass.new([0, 1, 2, 3])
# echo myclass.Mylen()

def JobExitCb(self: dict<any>, id: number, errcode: number, event: string)
  # Remove myself from s:joblist.
  filter(joblist, (_, value) => value != id)

  var err = 1
  var pluginfo = g:minpac#pluglist[self.name]
  pluginfo.stat.errcode = errcode
  if errcode == 0
    const dir = pluginfo.dir
    # Check if the plugin directory is available.
    if isdirectory(dir)
      # Check if it is actually updated (or installed).
      var updated = 1
      if pluginfo.stat.prev_rev != '' && pluginfo.stat.upd_method != 2
        if pluginfo.stat.prev_rev == GetPluginRevision(self.name)
          updated = 0
        endif
      endif

      if updated
        if pluginfo.stat.upd_method == 2
          var rev = pluginfo.rev
          if rev == ''
            # If no branch or tag is specified, consider as the master branch.
            rev = 'master'
          endif
          if self.seq == 0
            # Check out the specified revison (or branch).
            if rev =~ '\*'
              # If it includes '*', consider as the latest matching tag.
              rev = GetPluginLatestTag(self.name, rev)
              if rev == ''
                error_plugins += 1
                EchoMVerbose(1, 'error', 'Error while updating "' .. self.name .. '".  No tags found.')
                DecrementPluginCount()
                return
              endif
            endif
            const cmd = [g:minpac#opt.git, '-C', dir,
              '-c', 'core.fsmonitor=false',
              'checkout', rev, '--']
            EchoMVerbose(3, '', 'Checking out the revison: ' .. self.name
                   .. ': ' .. rev)
            StartJob(cmd, self.name, self.seq + 1)
            return
          elseif self.seq == 1
              && GetPluginBranch(self.name) == rev
            # Checked out the branch. Update to the upstream.
            const cmd = [g:minpac#opt.git, '-C', dir,
              '-c', 'core.fsmonitor=false',
              'merge', '--quiet', '--ff-only', '@{u}']
            EchoMVerbose(3, '', 'Update to the upstream: ' .. self.name)
            StartJob(cmd, self.name, self.seq + 1)
            return
          endif
        endif
        if pluginfo.stat.submod == 0
          pluginfo.stat.submod = 1
          if filereadable(dir .. '/.gitmodules')
            # Update git submodule.
            const cmd = [g:minpac#opt.git, '-C', dir,
              '-c', 'core.fsmonitor=false',
              'submodule', '--quiet', 'update', '--init', '--recursive']
            EchoMVerbose(3, '', 'Updating submodules: ' .. self.name)
            StartJob(cmd, self.name, self.seq + 1)
            return
          endif
        endif

        GenerateHelptags(dir)

        if pluginfo.subdir != ''
          call HandleSubdir(pluginfo)
        endif

        InvokeHook('post-update', [self.name], pluginfo.do)
      else
        # Even the plugin is not updated, generate helptags if it is not found.
        GenerateHelptags(dir)
      endif

      if pluginfo.stat.installed
        if updated
          updated_plugins += 1
          EchoMVerbose(1, '', 'Updated: ' .. self.name)
        else
          EchoMVerbose(3, '', 'Already up-to-date: ' .. self.name)
        endif
      else
        installed_plugins += 1
        EchoMVerbose(1, '', 'Installed: ' .. self.name)
      endif
      err = 0
    endif
  endif
  if err
    error_plugins += 1
    EchoMVerbose(1, 'error', 'Error while updating "' .. self.name .. '".  Error code: ' .. errcode)
  endif

  DecrementPluginCount()
enddef

def JobErrCb(self: dict<any>, id: number, message: list<string>, event: string)
  var mes = copy(message)
  if len(mes) > 0 && mes[-1]->empty()
    # Remove the last empty line. It is redundant.
    remove(mes, -1)
  endif
  for line in mes
    const line2 = substitute(line, "\t", '        ', 'g')
    add(g:minpac#pluglist[self.name].stat.lines, line2)
    EchoMVerbose(2, 'warning', self.name .. ': ' .. line2)
  endfor
enddef

def StartJobCore(cmds: list<string>, name: string, seq: number): number
  const quote_cmds = QuoteCmds(cmds)
  EchoMVerbose(4, '', 'start_job: cmds=' .. string(quote_cmds))
  var self = {
    'name': name,
    'seq': seq
  }
  self.on_stderr = function('JobErrCb', [self])
  self.on_exit = function('JobExitCb', [self])
  const job = minpac#job#Start(quote_cmds, self)
  if job > 0
    # It worked!
    joblist += [job]
    return 0
  else
    EchoMVerbose(1, 'error', 'Fail to execute: ' .. cmds[0])
    DecrementPluginCount()
    return 1
  endif
enddef

def TimerWorker(timer: number): number
  if (len(joblist) >= g:minpac#opt.jobs) || (len(jobqueue) == 0)
    return 0
  endif
  const job = remove(jobqueue, 0)
  return StartJobCore(job[0], job[1], job[2])
enddef

def StartJob(cmds: list<string>, name: string, seq: number, ...rest: list<any>): number
  if len(joblist) > 1
    sleep 20m
  endif
  if g:minpac#opt.jobs > 0
    if len(joblist) >= g:minpac#opt.jobs
      if timer_id == -1
        timer_id = timer_start(500, function('TimerWorker'), {'repeat': -1})
      endif
      # Add the job to s:jobqueue.
      jobqueue += [[cmds, name, seq]]
      return 0
    endif
  endif
  return StartJobCore(cmds, name, seq)
enddef

def IsSameCommit(a: string, b: string): bool
  const _min = min([len(a), len(b)]) - 1
  return a[0 : _min] == b[0 : _min]
enddef

# Check the status of the plugin.
# return: 0: No need to update.
#         1: Need to update by pull.
#         2: Need to update by fetch & checkout.
def CheckPluginStatus(name: string): number
  var pluginfo = g:minpac#pluglist[name]
  pluginfo.stat.prev_rev = GetPluginRevision(name)
  const branch = GetPluginBranch(name)

  if pluginfo.rev->empty()
    # No branch or tag is specified.
    if branch->empty()
      # Maybe a detached head. Need to update by fetch & checkout.
      return 2
    else
      # Need to update by pull.
      return 1
    endif
  endif
  if branch == pluginfo.rev
    # Same branch. Need to update by pull.
    return 1
  endif
  if GetPluginTag(name) == pluginfo.rev
    # Same tag. No need to update.
    return 0
  endif
  if IsSameCommit(pluginfo.stat.prev_rev, pluginfo.rev)
    # Same commit ID. No need to update.
    return 0
  endif

  # Need to update by fetch & checkout.
  return 2
enddef

# Check whether the type was changed. If it was changed, rename the directory.
def PreparePluginDir(pluginfo: dict<any>)
  const dir = pluginfo.dir
  if !isdirectory(dir)
    var dirtmp = ''
    if pluginfo.type == 'start'
      dirtmp = substitute(dir, '/start/\ze[^/]\+$', '/opt/', '')
    else
      dirtmp = substitute(dir, '/opt/\ze[^/]\+$', '/start/', '')
    endif
    if isdirectory(dirtmp)
      # The type was changed (start <-> opt).
      rename(dirtmp, dir)
    endif
  endif

  # Check subdir.
  if pluginfo.subdir != ''
    const name = pluginfo.name
    var [subdir, otherdir] = ['', '']
    if pluginfo.type == 'start'
      subdir = g:minpac#opt.minpac_start_dir_sub .. '/' .. name
      otherdir = g:minpac#opt.minpac_opt_dir_sub .. '/' .. name
    else
      subdir = g:minpac#opt.minpac_opt_dir_sub .. '/' .. name
      otherdir = g:minpac#opt.minpac_start_dir_sub .. '/' .. name
    endif
    if isdirectory(otherdir) && !isdirectory(subdir)
      # The type was changed (start <-> opt).
      delete(otherdir)
      HandleSubdir(pluginfo)
    endif
  endif
enddef

# Update a single plugin.
def UpdateSinglePlugin(name: string, force: number): number
  if !has_key(g:minpac#pluglist, name)
    EchoErrVerbose(1, 'Plugin not registered: ' .. name)
    DecrementPluginCount()
    return 1
  endif

  var pluginfo = g:minpac#pluglist[name]
  const dir = pluginfo.dir
  const url = pluginfo.url
  pluginfo.stat.errcode = 0
  pluginfo.stat.lines = []
  pluginfo.stat.prev_rev = ''
  pluginfo.stat.submod = 0

  PreparePluginDir(pluginfo)
  var cmd = []
  if isdirectory(dir)
    pluginfo.stat.installed = 1
    if pluginfo.frozen && !force
      EchoMVerbose(3, '', 'Skipped: ' .. name)
      DecrementPluginCount()
      return 0
    endif

    const ret = CheckPluginStatus(name)
    pluginfo.stat.upd_method = ret
    if ret == 0
      # No need to update.
      EchoMVerbose(3, '', 'Already up-to-date: ' .. name)
      DecrementPluginCount()
      return 0
    elseif ret == 1
      # Same branch. Update by pull.
      EchoVerbose(3, '', 'Updating (pull): ' .. name)
      cmd = [g:minpac#opt.git, '-C', dir,
        '-c', 'core.fsmonitor=false',
        'pull', '--quiet']
      if pluginfo.pullmethod == 'autostash'
        cmd += ['--rebase', '--autostash']
      else
        cmd += ['--ff-only', '--rebase=false']
      endif
    elseif ret == 2
      # Different branch. Update by fetch & checkout.
      EchoVerbose(3, '', 'Updating (fetch): ' .. name)
      cmd = [g:minpac#opt.git, '-C', dir,
        '-c', 'core.fsmonitor=false',
        'fetch', '--depth', '999999']
    endif
  else
    pluginfo.stat.installed = 0
    if pluginfo.rev == ''
      pluginfo.stat.upd_method = 1
    else
      pluginfo.stat.upd_method = 2
    endif
    EchoVerbose(3, '', 'Cloning ' .. name)

    cmd = [g:minpac#opt.git,
      '-c', 'core.fsmonitor=false',
      'clone', '--quiet', url, dir, '--no-single-branch']
    if pluginfo.depth > 0 && pluginfo.rev == ''
      cmd += ['--depth=' .. pluginfo.depth]
    endif
    if pluginfo.branch != ''
      cmd += ['--branch=' .. pluginfo.branch]
    endif
  endif
  return StartJob(cmd, name, 0)
enddef

def StartUpdate(names: list<string>, force: number, id: number)
  for name in names
    UpdateSinglePlugin(name, force)
  endfor
enddef

# Update all or specified plugin(s).
export def Update(...rest: list<any>): bool
  if g:minpac#opt.progress_open != 'none'
    minpac#progress#Open(['## minpac update progress ##', ''])
  endif
  var opt = extend(copy(get(rest, 1, {})), {'do': ''}, 'keep')

  var force = 0
  var names = []
  if rest->len() == 0 || (type(rest[0]) == v:t_string && rest[0]->empty())
    names = keys(g:minpac#pluglist)
  elseif type(rest[0]) == v:t_string
    names = [rest[0]]
    force = 1
  elseif type(rest[0]) == v:t_list
    names = rest[0]
    force = 1
  else
    EchoErrVerbose(1, 'Wrong parameter type. Must be a String or a List of Strings.')
    return false
  endif

  if remain_plugins > 0
    EchoMVerbose(1, '', 'Previous update has not been finished.')
    return false
  endif
  remain_plugins = len(names)
  error_plugins = 0
  updated_plugins = 0
  installed_plugins = 0
  Finish_update_hook = opt.do

  if g:minpac#opt.progress_open == 'none'
    # Disable the pager temporarily to avoid jobs being interrupted.
    if !save_more_to_set
      save_more = &more
      save_more_to_set = true
    endif
    set nomore
  endif

  timer_start(1, function('StartUpdate', [names, force]))
  return true
enddef


# Check if the dir matches specified package name and plugin names.
def MatchPlugin(dir: string, packname: string, plugnames: list<string>): bool
  var plugname = '\%(' .. join(plugnames, '\|') .. '\)'
  plugname = substitute(plugname, '\.', '\\.', 'g')
  plugname = substitute(plugname, '\*', '.*', 'g')
  plugname = substitute(plugname, '?', '.', 'g')
  var pat = ''
  if plugname =~ '/'
    pat = '/pack/' .. packname .. '\%(-sub\)\?' .. '/' .. plugname .. '$'
  else
    pat = '/pack/' .. packname .. '\%(-sub\)\?' .. '/\%(start\|opt\)/' .. plugname .. '$'
  endif
  if has('win32')
    pat = substitute(pat, '/', '[/\\\\]', 'g')
    # case insensitive matching
    return dir =~? pat
  else
    # case sensitive matching
    return dir =~ pat
  endif
enddef

# Remove plugins that are not registered.
export def Clean(...rest: list<any>): bool
  var plugin_dirs = minpac#getpackages(g:minpac#opt.package_name)
    + minpac#getpackages(g:minpac#opt.package_name .. '-sub')

  var to_remove = []
  if rest->len() > 0
    # Going to remove only specified plugins.
    var names = []
    if type(rest[0]) == v:t_string
      names = [rest[0]]
    elseif type(rest[0]) == v:t_list
      names = rest[0]
    else
      echoerr 'Wrong parameter type. Must be a String or a List of Strings.'
      return false
    endif
    to_remove = filter(plugin_dirs,
      (_, value) => MatchPlugin(value, g:minpac#opt.package_name, names))
  else
    # Remove all plugins that are not registered.
    const safelist = map(keys(g:minpac#pluglist),
      (_, value) => g:minpac#pluglist[value].type .. '/' .. value)
    + ['opt/minpac']  # Don't remove itself.
    to_remove = filter(plugin_dirs,
      (_, value) => !MatchPlugin(value, g:minpac#opt.package_name, safelist))
  endif

  if len(to_remove) == 0
    echo 'Already clean.'
    return true
  endif

  # Show the list of plugins to be removed.
  for item in to_remove
    echo item
  endfor

  const dir = (len(to_remove) > 1) ? 'directories' : 'directory'

  var err = 0
  if !g:minpac#opt.confirm || input('Removing the above ' .. dir .. '. [y/N]? ') =~? '^y'
    echo "\n"
    for item in to_remove
      if delete(item, 'rf') != 0
        echohl ErrorMsg
        echom 'Clean failed: ' .. item
        echohl None
        err = 1
      endif
    endfor
    if err == 0
      echo 'Successfully cleaned.'
    endif
  else
    echo "\n" .. 'Not cleaned.'
  endif

  return err == 0
enddef

export def IsUpdateRan(): bool
  return exists('installed_plugins')
enddef

export def Abort()
  jobqueue = []
  for job in joblist
    minpac#job#Stop(job)
  endfor
  joblist = []
  remain_plugins = 0
  if timer_id != -1
    timer_stop(timer_id)
    timer_id = -1
  endif
enddef

# vim: set ts=8 sw=2 et:
