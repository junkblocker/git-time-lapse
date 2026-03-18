" vim: set et fdm=diff fenc=utf-8 ff=unix sts=0 sw=4 ts=4 tw=79 wrap :
function! s:status(str) " {{{
    if ! &cmdheight
        return
    endif
    echo a:str
    redraw
endfunction " }}}
let s:cache = {}
let s:cache_order = []
let s:cache_max = 10

" Tracks commits currently being prefetched: { commit: { left, right, log, done_count } }
let s:inflight = {}

function! s:cache_get(commit)
    " Use has_key + direct access rather than get(..., v:null) because
    " `x isnot v:null` is unreliable in Vim (always returns 0).
    if has_key(s:cache, a:commit)
        return s:cache[a:commit]
    endif
    return v:null
endfunction

function! s:cache_put(commit, data)
    if !has_key(s:cache, a:commit)
        call add(s:cache_order, a:commit)
        if len(s:cache_order) > s:cache_max
            let l:evict = remove(s:cache_order, 0)
            unlet s:cache[l:evict]
        endif
    endif
    let s:cache[a:commit] = a:data
endfunction

" ---- Prefetch helpers -------------------------------------------------------
" Kicks off background jobs to populate the cache for commit at index `pos`.
" Detects Neovim vs Vim 8 via has('nvim') and uses the correct job API for
" each. All three git commands run in parallel; the cache entry is written
" once all three exit successfully. If either API is unavailable (old Vim),
" prefetch is silently skipped — s:display() always falls back to synchronous
" systemlist() for uncached commits.

function! s:prefetch(pos)
    if a:pos < 0 || a:pos >= t:total - 1
        return
    endif
    let l:commit = t:commits[a:pos]
    " Skip if already cached or already in flight
    if has_key(s:cache, l:commit) || has_key(s:inflight, l:commit)
        return
    endif

    " Accumulator: left/right/log lines + per-slot exit codes + completion counter
    let s:inflight[l:commit] = {
        \ 'left': [], 'right': [], 'log': [],
        \ 'exit_codes': [0, 0, 0],
        \ 'done': 0,
        \ }

    let l:path = t:path  " capture tab-local var — closures in Vim/Nvim see l: not t:

    if has('nvim')
        " ---- Neovim: jobstart() ----
        " stdout_buffered collects all output; on_stdout fires once before on_exit.
        " Suppress stderr so git errors (e.g. root commit has no ^) are silent.
        call jobstart(['git', 'show', l:commit . '^:' . l:path], {
            \ 'stdout_buffered': 1,
            \ 'stderr_buffered': 1,
            \ 'on_stdout': {_, data, __ -> s:pfcb_nvim(l:commit, 'left',  data)},
            \ 'on_exit':   {_, code, __ -> s:pfcb_exit(l:commit, 0, code)},
            \ })
        call jobstart(['git', 'show', l:commit . ':' . l:path], {
            \ 'stdout_buffered': 1,
            \ 'stderr_buffered': 1,
            \ 'on_stdout': {_, data, __ -> s:pfcb_nvim(l:commit, 'right', data)},
            \ 'on_exit':   {_, code, __ -> s:pfcb_exit(l:commit, 1, code)},
            \ })
        call jobstart(['git', 'log', '--stat', l:commit . '^..' . l:commit], {
            \ 'stdout_buffered': 1,
            \ 'stderr_buffered': 1,
            \ 'on_stdout': {_, data, __ -> s:pfcb_nvim(l:commit, 'log',   data)},
            \ 'on_exit':   {_, code, __ -> s:pfcb_exit(l:commit, 2, code)},
            \ })
    elseif exists('*job_start')
        " ---- Vim 8+: job_start() ----
        " out_cb fires once per output line; err_io 'null' silences stderr.
        call job_start(['git', 'show', l:commit . '^:' . l:path], {
            \ 'out_cb':  {_, line -> s:pfcb_vim(l:commit, 'left',  line)},
            \ 'exit_cb': {_, code -> s:pfcb_exit(l:commit, 0, code)},
            \ 'err_io':  'null',
            \ })
        call job_start(['git', 'show', l:commit . ':' . l:path], {
            \ 'out_cb':  {_, line -> s:pfcb_vim(l:commit, 'right', line)},
            \ 'exit_cb': {_, code -> s:pfcb_exit(l:commit, 1, code)},
            \ 'err_io':  'null',
            \ })
        call job_start(['git', 'log', '--stat', l:commit . '^..' . l:commit], {
            \ 'out_cb':  {_, line -> s:pfcb_vim(l:commit, 'log',   line)},
            \ 'exit_cb': {_, code -> s:pfcb_exit(l:commit, 2, code)},
            \ 'err_io':  'null',
            \ })
    else
        " No async job API — remove the empty accumulator we just created
        unlet s:inflight[l:commit]
    endif
endfunction

" Neovim stdout callback: stdout_buffered delivers all lines at once.
" Neovim appends a spurious trailing empty string; strip it.
function! s:pfcb_nvim(commit, key, data)
    if !has_key(s:inflight, a:commit)
        return
    endif
    let l:lines = a:data
    if !empty(l:lines) && l:lines[-1] ==# ''
        let l:lines = l:lines[:-2]
    endif
    let s:inflight[a:commit][a:key] = l:lines
endfunction

" Vim 8 stdout callback: fires once per line.
function! s:pfcb_vim(commit, key, line)
    if has_key(s:inflight, a:commit)
        call add(s:inflight[a:commit][a:key], a:line)
    endif
endfunction

" Shared exit callback for both APIs.
" slot: 0=left, 1=right, 2=log. code: process exit code.
" Caches only when all three jobs finished without error.
function! s:pfcb_exit(commit, slot, code)
    if !has_key(s:inflight, a:commit)
        return
    endif
    let l:inf = s:inflight[a:commit]
    let l:inf['exit_codes'][a:slot] = a:code
    let l:inf['done'] += 1
    if l:inf['done'] == 3
        " Only cache if all three git commands succeeded (exit 0).
        " A non-zero exit (e.g. root commit with no parent, deleted file) means
        " the data is incomplete; let s:display() handle it synchronously instead.
        if l:inf['exit_codes'] == [0, 0, 0]
            call s:cache_put(a:commit, [l:inf['left'], l:inf['right'], l:inf['log']])
        endif
        unlet s:inflight[a:commit]
    endif
endfunction

function! s:prefetch_cancel_all()
    " Discard all in-flight accumulators. Any jobs still running will fire
    " their callbacks, which will silently no-op on the missing s:inflight key.
    let s:inflight = {}
endfunction

function! s:display(commit)
    " Serve from cache when the user backtracks over already-visited commits.
    " For large files this avoids re-decompressing blobs from the pack file.
    let l:cached = s:cache_get(a:commit)
    if has_key(s:cache, a:commit)
        let l:left_lines  = l:cached[0]
        let l:right_lines = l:cached[1]
        let l:log_lines   = l:cached[2]
    else
        let l:left_lines  = systemlist('git show ' . shellescape(a:commit . '^:' . t:path))
        let l:right_lines = systemlist('git show ' . shellescape(a:commit . ':' . t:path))
        let l:log_lines   = systemlist('git log --stat ' . shellescape(a:commit . '^..' . a:commit))
        call s:cache_put(a:commit, [l:left_lines, l:right_lines, l:log_lines])
    endif

    " Suppress autocommands while clearing and filling buffers to avoid
    " triggering expensive autocommand chains (LSP, syntax, linters) on every
    " navigation keystroke.
    noautocmd wincmd t
    noautocmd %d
    diffoff
    call setline(1, l:left_lines)
    exe 'doautocmd filetypedetect BufRead ' . s:fnameescape(t:path)

    noautocmd wincmd l
    noautocmd %d
    diffoff
    call setline(1, l:right_lines)
    exe 'doautocmd filetypedetect BufRead ' . s:fnameescape(t:path)

    noautocmd wincmd j
    noautocmd %d
    call setline(1, l:log_lines)
    setfiletype git

    wincmd t
    diffthis

    wincmd l
    diffthis

    " Move back to where we were if it's still there, otherwise go to the top
    if s:here <= line('$')
        exe 'normal! '.s:here . 'gg'
    else
        normal! gg
    endif

    normal z.

    " Some people have reported that you need to do this to make sure the left
    " buffer is in the right place.
    wincmd t
    normal z.

    wincmd j
    normal! gg
    redraw!

    " Kick off background prefetch for the two neighbouring commits so the
    " next keypress is likely a cache hit.
    call s:prefetch(t:current - 1)
    call s:prefetch(t:current + 1)
endfunction

function! s:goto(pos, last)
    call s:status("Processing ... ")
    let t:current = a:pos

    if t:current < 0
        let t:current = 0
        return 0
    elseif t:current >= t:total - 1
        let t:current = t:total - 2
        return 0
    endif

    call s:display(t:commits[t:current])
    if a:last
        call s:status('Ready')
    endif
    return 1
endfunction

function! s:move(amount)
    call s:status("Processing ...")
    let t:current = t:current + a:amount
    call s:goto(t:current, 0)
    redraw!
    call s:status('Ready')
endfunction

function! s:blame()
    call s:status("Processing ...")
    let current = t:commits[t:current]
    let line = line('.')

    let output = system('git blame -p -n -L'.shellescape(line).','.shellescape(line).' '.
                        \shellescape(current).' -- '.shellescape(t:path))
    let results = split(output)

    if results[0] == "fatal:"
        echoerr "Something failed. Returning without doing anything"
        return
    endif

    " O(1) lookup via the index map built in s:get_log()
    let l:idx = get(t:commit_index, results[0], -1)
    if l:idx >= 0
        call s:goto(l:idx, 0)
    endif

    wincmd t
    wincmd l
    exe 'normal! '.results[1] . 'ggz.'
    wincmd j
    call s:status("Ready")
endfunction

function! s:get_log()
    let t:commits = systemlist('git log --no-merges --pretty=format:%H ' . shellescape(t:path))
    let t:total = len(t:commits)

    " Build a hash→index map so s:blame() can jump in O(1) instead of O(N)
    let t:commit_index = {}
    for i in range(t:total)
        let t:commit_index[t:commits[i]] = i
    endfor

    return t:total
endfunction

function! s:fnameescape(path) " {{{
    if (v:version >= 702)
        let l:ret = escape(fnameescape(a:path), '&[<()>]^:')
    else
        " This is not a complete list of escaped character, so it's not as
        " sophisticated as the fnameescape, but this should cover most of the cases
        " and should work for Vim version < 7.2
        let l:ret = escape(a:path, " \t\n*?[{`$\\%#'\"|!<()^:&")
    endif
    " Handle zsh issues
    if &shell =~? 'zsh\(\.exe\)\?$'
        let l:ret = substitute(l:ret, '\\#', '\\\\#', 'g')
    endif
    return l:ret
endfunction

function! s:chdir()
    " Change directory to the workspace toplevel and return path to the
    " current file from there.
    let l:rfile = resolve(expand('%:p'))
    let l:rdir = fnamemodify(l:rfile, ':h')
    exe 'lcd ' . s:fnameescape(l:rdir)
    silent! let l:sourcedir = system('git rev-parse --show-toplevel 2>/dev/null' )
    if !v:shell_error && l:sourcedir != ''
        let l:sourcedir = substitute(l:sourcedir, "[\r\n].*", '', '')
        exe 'lcd ' . s:fnameescape(l:sourcedir)
        return l:rfile[strlen(l:sourcedir)+1:]
    else
        echoerr s:status("Changing to workspace ... failed.")
    endif
endfunction

function! gittimelapse#git_time_lapse()
    call s:status("Processing ...")
    " Open a new tab with a time-lapse view of the file in the current
    " buffer.
    let path = s:chdir()
    let s:here = line('.')

    tabnew
    let t:path = path
    let s:cache = {}
    let s:cache_order = []
    call s:prefetch_cancel_all()

    if s:get_log() <= 1
        echoerr "Insufficient log entries"
        tabclose
        return
    endif

    set buftype=nofile

    new
    set buftype=nofile

    wincmd j
    resize 10
    set winfixheight

    wincmd k
    vnew
    set buftype=nofile

    " The first line in the file is the most recent commit
    let t:current = 0
    call s:display(t:commits[t:current])

    " Go backwards and forwards one commit
    windo map <buffer> <silent> <Left> :call <SID>move(1)<cr>
    windo map <buffer> <silent> <Right> :call <SID>move(-1)<cr>

    " Rewind all the way to the start or end
    windo map <buffer> <silent> <S-Left> :call <SID>goto(t:total - 2, 1)<cr>
    windo map <buffer> <silent> <S-Right> :call <SID>goto(0, 1)<cr>

    windo map <buffer> <silent> <CR> :call <SID>blame()<cr>

    " Go to the top right window (which contains the latest version of the
    " file) and go back to the line we were on when we opened the time-lapse,
    " so we can immediately Blame from there which is a common use-case.
    2 wincmd w
    exe 'normal! '.s:here . 'ggz.'
    call s:status('Ready')
endfunction
