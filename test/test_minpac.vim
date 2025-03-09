" Tests for minpac.

set rtp^=..
set packpath=.
runtime plugin/minpac.vim


" Tests for minpac#Init()
func Test_minpac_init()
  call delete('pack', 'rf')

  " NOTE: The variables g:minpac#opt and g:minpac#pluglist are not the part
  " of public APIs.  Users should not access these variables.  They should
  " be used only for testing and/or debugging.

  " Default setting
  call minpac#Init()
  call assert_true(isdirectory('pack/minpac/start'))
  call assert_true(isdirectory('pack/minpac/opt'))
  call assert_equal('git', g:minpac#opt.git)
  call assert_equal(1, g:minpac#opt.depth)
  call assert_equal(8, g:minpac#opt.jobs)
  call assert_equal(2, g:minpac#opt.verbose)
  call assert_equal('horizontal', g:minpac#opt.progress_open)
  call assert_equal('horizontal', g:minpac#opt.status_open)
  call assert_equal(v:false, g:minpac#opt.status_auto)
  call assert_equal({}, minpac#GetPlugList())

  let g:minpac#pluglist.foo = 'bar'

  " Change settings
  call minpac#Init({'package_name': 'm', 'git': 'foo', 'depth': 10, 'jobs': 2, 'verbose': 1, 'progress_open': 'tab', 'status_open': 'vertical', 'status_auto': v:true})
  call assert_true(isdirectory('pack/m/start'))
  call assert_true(isdirectory('pack/m/opt'))
  call assert_equal('foo', g:minpac#opt.git)
  call assert_equal(10, g:minpac#opt.depth)
  call assert_equal(2, g:minpac#opt.jobs)
  call assert_equal(1, g:minpac#opt.verbose)
  call assert_equal('tab', g:minpac#opt.progress_open)
  call assert_equal('vertical', g:minpac#opt.status_open)
  call assert_equal(v:true, g:minpac#opt.status_auto)
  call assert_equal({}, minpac#GetPlugList())

  call delete('pack', 'rf')
endfunc

" Tests for minpac#Add() and minpac#GetPlugInfo()
func Test_minpac_add()
  call delete('pack', 'rf')

  call minpac#Init()

  " Default
  call minpac#Add('k-takata/minpac')
  let p = minpac#GetPlugInfo('minpac')
  call assert_equal('https://github.com/k-takata/minpac.git', p.url)
  call assert_match('/pack/minpac/start/minpac$', p.dir)
  call assert_equal(v:false, p.frozen)
  call assert_equal('start', p.type)
  call assert_equal('', p.branch)
  call assert_equal(1, p.depth)
  call assert_equal('', p.do)
  call assert_equal('', p.rev)
  call assert_equal('', p.subdir)
  call assert_equal('', p.pullmethod)

  " With configuration
  call minpac#Add('k-takata/minpac', {'type': 'opt', 'frozen': v:true, 'branch': 'master', 'depth': 10, 'rev': 'abcdef', 'subdir': 'dir', 'pullmethod': 'autostash'})
  let p = minpac#GetPlugInfo('minpac')
  call assert_equal('https://github.com/k-takata/minpac.git', p.url)
  call assert_match('/pack/minpac/opt/minpac$', p.dir)
  call assert_equal(v:true, p.frozen)
  call assert_equal('opt', p.type)
  call assert_equal('master', p.branch)
  call assert_equal(10, p.depth)
  call assert_equal('', p.do)
  call assert_equal('abcdef', p.rev)
  call assert_equal('dir', p.subdir)
  call assert_equal('autostash', p.pullmethod)

  " SSH URL
  call minpac#Add('git@github.com:k-takata/minpac.git', {'name': 'm'})
  let p = minpac#GetPlugInfo('m')
  call assert_equal('git@github.com:k-takata/minpac.git', p.url)
  call assert_match('/pack/minpac/start/m$', p.dir)

  " Non GitHub URL with ".git"
  call minpac#Add('https://example.com/foo.git')
  let p = minpac#GetPlugInfo('foo')
  call assert_equal('https://example.com/foo.git', p.url)

  " Non GitHub URL w/o ".git"
  call minpac#Add('https://example.com/bar')
  let p = minpac#GetPlugInfo('bar')
  call assert_equal('https://example.com/bar', p.url)

  " Wrong type
  try
    call minpac#Add('k-takata/minpac', {'type': 'foo'})
  catch
    call assert_exception("Vim:k-takata/minpac: Wrong type (must be 'start' or 'opt'): foo")
  endtry

  call delete('pack', 'rf')
endfunc

" Tests for minpac#GetPackages()
func s:getnames(plugs)
  return sort(map(a:plugs, {-> substitute(v:val, '^.*[/\\]', '', '')}))
endfunc
func Test_minpac_getpackages()
  call delete('pack', 'rf')

  let plugs = [
	\ './pack/minpac/start/plug0',
	\ './pack/minpac/start/plug1',
	\ './pack/minpac/opt/plug2',
	\ './pack/minpac/opt/plug3',
	\ './pack/foo/start/plug4',
	\ './pack/foo/start/plug5',
	\ './pack/foo/opt/plug6',
	\ './pack/foo/opt/plug7',
	\ ]
  for dir in plugs
    call mkdir(dir, 'p')
  endfor

  " All plugins
  let p = minpac#GetPackages()
  let exp = plugs[:]
  call assert_equal(sort(exp), sort(p))
  " name only
  let p = minpac#GetPackages('', '', '', 1)
  call assert_equal(s:getnames(exp), sort(p))

  " All packages
  let p = minpac#GetPackages('', 'NONE')
  let exp = ['./pack/foo', './pack/minpac']
  call assert_equal(sort(exp), sort(p))
  " name only
  let p = minpac#GetPackages('', 'NONE', '', 1)
  call assert_equal(s:getnames(exp), sort(p))

  " Plugins under minpac
  let p = minpac#GetPackages('minpac')
  let exp = plugs[0 : 3]
  call assert_equal(sort(exp), sort(p))
  " name only
  let p = minpac#GetPackages('minpac', '', '', 1)
  call assert_equal(s:getnames(exp), sort(p))

  " 'start' plugins
  let p = minpac#GetPackages('', 'start')
  let exp = plugs[0 : 1] + plugs[4 : 5]
  call assert_equal(sort(exp), sort(p))
  " name only
  let p = minpac#GetPackages('', 'start', '', 1)
  call assert_equal(s:getnames(exp), sort(p))

  " 'opt' plugins
  let p = minpac#GetPackages('*', 'opt', '')
  let exp = plugs[2 : 3] + plugs[6 : 7]
  call assert_equal(sort(exp), sort(p))
  " name only
  let p = minpac#GetPackages('*', 'opt', '', 1)
  call assert_equal(s:getnames(exp), sort(p))

  " Plugins with 'plug1*' name
  let p = minpac#GetPackages('', '', 'plug1*')
  let exp = plugs[1 : 1]
  call assert_equal(sort(exp), sort(p))
  " name only
  let p = minpac#GetPackages('', '', 'plug1', 1)
  call assert_equal(s:getnames(exp), sort(p))

  " No match
  let p = minpac#GetPackages('minpac', 'opt', 'plug1*')
  let exp = []
  call assert_equal(sort(exp), sort(p))
  " name only
  let p = minpac#GetPackages('minpac', 'opt', 'plug1*', 1)
  call assert_equal(s:getnames(exp), sort(p))

  call delete('pack', 'rf')
endfunc

" let s:seq = 1
" func WriteSeq(name, begin = v:false)
"   let l:fname = 'subtests.log'
"   let l:flags = ''
"   if !a:begin
"     let l:flags = 'a'
"   endif
"
"   call writefile(['Completed subtest #' . s:seq . ': ' . a:name], l:fname, l:flags)
"   let s:seq = s:seq + 1
" endfunc

" Tests for minpac#Update()
func Test_minpac_update()
  call delete('pack', 'rf')

  call minpac#Init()

  " minpac#Update() with hooks using Strings.
  call minpac#Add('k-takata/minpac', {'type': 'opt',
	\ 'do': 'g:post_update = 1'})
  let g:post_update = 0
  let g:finish_update = 0
  call minpac#Update('', {'do': 'g:finish_update = 1'})
  while g:finish_update == 0
    sleep 100m
  endwhile
  call assert_equal(1, g:post_update)
  call assert_true(isdirectory('pack/minpac/opt/minpac'))

  " minpac#Update() with hooks using Funcrefs.
  let l:post_update = 0
  call minpac#Add('k-takata/hg-vim', {'do': {hooktype, name -> [
	\ assert_equal('post-update', hooktype, 'hooktype'),
	\ assert_equal('hg-vim', name, 'name'),
	\ execute('let l:post_update = 1'),
	\ l:post_update
	\ ]}})
  let l:finish_update = 0
  call minpac#Update('', {'do': {hooktype, updated, installed -> [
	\ assert_equal('finish-update', hooktype, 'hooktype'),
	\ assert_equal(0, updated, 'updated'),
	\ assert_equal(1, installed, 'installed'),
	\ execute('let l:finish_update = 1'),
	\ l:finish_update
	\ ]}})
  while l:finish_update == 0
    sleep 100m
  endwhile
  call assert_equal(1, l:post_update)
  call assert_true(isdirectory('pack/minpac/start/hg-vim'))

  call delete('pack', 'rf')
endfunc

" Tests for minpac#Clean()
func Test_minpac_clean()
  call delete('pack', 'rf')

  call minpac#Init()

  let plugs = [
	\ 'pack/minpac/start/plug0',
	\ 'pack/minpac/start/plug1',
	\ 'pack/minpac/opt/plug2',
	\ 'pack/minpac/opt/plug3',
	\ 'pack/minpac/start/minpac',
	\ 'pack/minpac/opt/minpac',
	\ ]
  for dir in plugs
    call mkdir(dir, 'p')
  endfor

  " Just type Enter. All plugins should not be removed.
  call feedkeys(":call minpac#Clean()\<CR>\<CR>", 'x')
  for dir in plugs
    call assert_true(isdirectory(dir))
  endfor

  " Register some plugins
  call minpac#Add('foo', {'name': 'plug0'})
  call minpac#Add('bar/plug2', {'type': 'opt'})
  call minpac#Add('baz/plug3')

  " Type y and Enter. Unregistered plugins should be removed.
  " 'opt/minpac' should not be removed even it is not registered.
  call feedkeys(":call minpac#Clean()\<CR>y\<CR>", 'x')
  call assert_equal(1, isdirectory(plugs[0]))
  call assert_equal(0, isdirectory(plugs[1]))
  call assert_equal(1, isdirectory(plugs[2]))
  call assert_equal(0, isdirectory(plugs[3]))
  call assert_equal(0, isdirectory(plugs[4]))
  call assert_equal(1, isdirectory(plugs[5]))

  " Specify a plugin. It should be removed even it is registered.
  call feedkeys(":call minpac#Clean('plug0')\<CR>y\<CR>", 'x')
  call assert_equal(0, isdirectory(plugs[0]))
  call assert_equal(1, isdirectory(plugs[2]))
  call assert_equal(1, isdirectory(plugs[5]))

  " 'opt/minpac' can be also removed when it is specified.
  call minpac#Add('k-takata/minpac', {'type': 'opt'})
  call feedkeys(":call minpac#Clean('minpa?')\<CR>y\<CR>", 'x')
  call assert_equal(1, isdirectory(plugs[2]))
  call assert_equal(0, isdirectory(plugs[5]))

  " Type can be also specified.
  " Not match
  call minpac#Clean('start/plug2')
  call assert_equal(1, isdirectory(plugs[2]))
  " Match
  call feedkeys(":call minpac#Clean('opt/plug*')\<CR>y\<CR>", 'x')
  call assert_equal(0, isdirectory(plugs[2]))

  call delete('pack', 'rf')
endfunc

" vim: ts=8 sw=2 sts=2
