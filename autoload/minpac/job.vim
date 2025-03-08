vim9script
# Author: Prabir Shrestha <mail at prabir dot me>
# Website: https://github.com/prabirshrestha/async.vim
# License: The MIT License {{{
#   The MIT License (MIT)
#
#   Copyright (c) 2016 Prabir Shrestha
#
#   Permission is hereby granted, free of charge, to any person obtaining a copy
#   of this software and associated documentation files (the "Software"), to deal
#   in the Software without restriction, including without limitation the rights
#   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#   copies of the Software, and to permit persons to whom the Software is
#   furnished to do so, subject to the following conditions:
#
#   The above copyright notice and this permission notice shall be included in all
#   copies or substantial portions of the Software.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#   SOFTWARE.
# }}}

# In Vim9script cpoptions is automatically defaulted when a script starts and
# restored at the end. So no need to set cpo&vim

# TODO: Remove nvimjob support since Vim9script doesn't work on Neovim
# TODO: Use new Vim9script enum for the job type below
var jobidseq = 0
var jobs = {}                               # { job, opts, type: 'vimjob|nvimjob'}
const job_type_nvimjob = 'nvimjob'
const job_type_vimjob = 'vimjob'
const job_error_unsupported_job_type = -2   # unsupported job type

def JobSupportedTypes()
  var supported_types = []
  if has('nvim')
    supported_types += [job_type_nvimjob]
  endif
  if !has('nvim') && has('job') && has('channel') && has('lambda')
    supported_types += [job_type_vimjob]
  endif
  return supported_types
enddef

def JobSupportsType(type: string)
  return index(JobSupportedTypes(), type) >= 0
enddef

def OutCb(jobid: number, opts: dict<any>, job: channel, data: string)
  if has_key(opts, 'on_stdout')
    opts.on_stdout(jobid, split(data, "\n", 1), 'stdout')
  endif
enddef

def ErrCb(jobid: number, opts: dict<any>, job: channel, data: string)
  if has_key(opts, 'on_stderr')
    opts.on_stderr(jobid, split(data, "\n", 1), 'stderr')
  endif
enddef

def ExitCb(jobid: number, opts: dict<any>, job: channel, status: number)
  if has_key(opts, 'on_exit')
    opts.on_exit(jobid, status, 'exit')
  endif
  if has_key(jobs, jobid)
    remove(jobs, jobid)
  endif
enddef

def OnStdout(jobid: number, data: list<any>, event: string)
  if has_key(jobs, jobid)
    const jobinfo = jobs[jobid]
    if has_key(jobinfo.opts, 'on_stdout')
      jobinfo.opts.on_stdout(jobid, data, event)
    endif
  endif
enddef

def OnStderr(jobid: number, data: list<any>, event: string)
  if has_key(jobs, jobid)
    const jobinfo = jobs[jobid]
    if has_key(jobinfo.opts, 'on_stderr')
      jobinfo.opts.on_stderr(jobid, data, event)
    endif
  endif
enddef

def OnExit(jobid: number, status: number, event: string)
  if has_key(jobs, jobid)
    const jobinfo = jobs[jobid]
    if has_key(jobinfo.opts, 'on_exit')
      jobinfo.opts.on_exit(jobid, status, event)
    endif
  endif
enddef

def JobStart(cmd: list<string>, opts: dict<any>): number
  var jobtypes = JobSupportedTypes()
  var jobtype = ''

  if has_key(opts, 'type')
    if type(opts.type) == v:t_string
      if !JobSupportsType(opts.type)
        return job_error_unsupported_job_type
      endif
      jobtype = opts.type
    else
      jobtypes = opts.type
    endif
  endif

  if empty(jobtype)
    # find the best jobtype
    for jobtype2 in jobtypes
      if JobSupportsType(jobtype2)
        jobtype = jobtype2
      endif
    endfor
  endif

  if jobtype ==? ''
    return job_error_unsupported_job_type
  endif

  if jobtype == job_type_nvimjob
    throw "nvimjob unimplemented"
    # var job = jobstart(cmd, {
    #   'on_stdout': function('OnStdout'),
    #   'on_stderr': function('OnStderr'),
    #   'on_exit': function('OnExit')
    # })
    # if job <= 0
    #   return job
    # endif
    # const jobid = job # nvimjobid and internal jobid is same
    # jobs[jobid] = {
    #        'type': s:job_type_nvimjob,
    #        'opts': a:opts,
    #        }
    # jobs[jobid].job = job
  elseif jobtype == job_type_vimjob
    jobidseq += 1
    const jobid = jobidseq
    var job  = job_start(cmd, {
      'out_cb': function('OutCb', [jobid, opts]),
      'err_cb': function('ErrCb', [jobid, opts]),
      'exit_cb': function('ExitCb', [jobid, opts]),
      'mode': 'raw',
    })
    if job_status(job) !=? 'run'
      return -1
    endif
    jobs[jobid] = {
      'type': job_type_vimjob,
      'opts': opts,
      'job': job,
      'channel': job_getchannel(job),
      'buffer': ''
    }
  else
    return job_error_unsupported_job_type
  endif

  return jobid
enddef

def JobStop(jobid: number)
  if has_key(jobs, jobid)
    const jobinfo = jobs[jobid]
    if jobinfo.type == job_type_nvimjob
      throw "nvimjob unsupported"
      # call jobstop(a:jobid)
    elseif jobinfo.type == job_type_vimjob
      job_stop(jobs[jobid].job)
    endif
    if has_key(jobs, jobid)
      remove(jobs, jobid)
    endif
  endif
enddef

def JobSend(jobid: number, data: string)
  const jobinfo = jobs[jobid]
  if jobinfo.type == job_type_nvimjob
    throw "nvimjob unsupported"
    # call jobsend(a:jobid, a:data)
  elseif jobinfo.type == job_type_vimjob
    const jobinfo.buffer ..= data
    FlushVimSendraw(jobid, -1)
  endif
enddef

def FlushVimSendraw(jobid: number, timer: number)
  # https://github.com/vim/vim/issues/2548
  # https://github.com/natebosch/vim-lsc/issues/67#issuecomment-357469091
  const jobinfo = jobs[jobid]
  if len(jobinfo.buffer) <= 1024
    ch_sendraw(jobinfo.channel, jobinfo.buffer)
    jobinfo.buffer = ''
  else
    const to_send = jobinfo.buffer[:1023]
    const jobinfo.buffer = jobinfo.buffer[1024:]
    ch_sendraw(jobinfo.channel, to_send)
    timer_start(1, function('FlushVimSendraw', [jobid]))
  endif
enddef

def JobWaitSingle(jobid: number, _timeout: float, start: number): number
  if !has_key(jobs, jobid)
    return -3
  endif

  const jobinfo = jobs[jobid]
  if jobinfo.type == job_type_nvimjob
    throw "nvimjob unimpl"
    # const timeout = timeout - reltimefloat(reltime(start)) * 1000
    # return jobwait([a:jobid], float2nr(l:timeout))[0]
  elseif jobinfo.type == job_type_vimjob
    const timeout = _timeout / 1000.0
    try
      while timeout < 0 || reltimefloat(reltime(start)) < timeout
        const info = job_info(jobinfo.job)
        if info.status == 'dead'
          return info.exitval
        elseif info.status == 'fail'
          return -3
        endif
        sleep 1m
      endwhile
    catch /^Vim:Interrupt$/
      return -2
    endtry
  endif
  return -1
enddef

def JobWait(jobids: list<number>, timeout: float)
  const start = reltime()
  var exitcode = 0
  var ret = []
  for jobid in jobids
    if exitcode != -2  # Not interrupted.
      exitcode = JobWaitSingle(jobid, timeout, start)
    endif
    ret += [exitcode]
  endfor
  return ret
enddef

# public apis {{{
def JobWait2(jobids: list<number>, ...rest: list<any>)
  const timeout = get(rest, 0, -1)
  return JobWait(jobids, timeout)
enddef

g:minpac#job#start = JobStart
g:minpac#job#stop = JobStop
g:minpac#job#send = JobSend
g:minpac#job#wait = JobWait2
# }}}

# vim: set ts=8 sw=2 et:
