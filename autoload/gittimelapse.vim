" vim: set et fdm=diff fenc=utf-8 ff=unix sts=0 sw=4 ts=4 tw=79 wrap :
function! s:status(str) " {{{
    if ! &cmdheight
        return
    endif
    echo a:str
    redraw
endfunction " }}}
function! s:display(commit)
    " clears all input in every buffer of the tab
    windo %d
    diffoff!
    wincmd t
    exe ':silent :0 read !git show '.a:commit.s:fnameescape('^:').s:fnameescape(t:path)
    exe 'doautocmd filetypedetect BufRead '.s:fnameescape(t:path)

    wincmd l
    exe ':silent :0 read !git show '.a:commit.s:fnameescape(':').s:fnameescape(t:path)
    exe 'doautocmd filetypedetect BufRead '.s:fnameescape(t:path)

    wincmd j
    exe ':silent :0 read !git log --stat '.a:commit.s:fnameescape('^..').a:commit
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
    exe ':silent :!git log --no-merges ' . s:fnameescape('--pretty=format:%H'). ' '.s:fnameescape(t:path).' > '.s:fnameescape(s:tmpfile)

    let results = split(output)

    if results[0] == "fatal:"
        echoerr "Something failed. Returning without doing anything"
        return
    endif

    for i in range(len(t:commits))
        if t:commits[i] =~ results[0]
            call s:goto(i, 0)
            break
        endif
    endfor

    wincmd t
    wincmd l
    exe 'normal! '.results[1] . 'ggz.'
    wincmd j
    call s:status("Ready")
endfunction

function! s:get_log()
    let s:tmpfile = tempname()
    exe ':silent :!git log --no-merges ' . s:fnameescape('--pretty=format:%H'). ' '.s:fnameescape(t:path).' > '.s:fnameescape(s:tmpfile)
    let t:commits = readfile(s:tmpfile)
    call delete(s:tmpfile)
    let t:total = len(t:commits)
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

    windo map <buffer> <silent> <CR> :call <SID>move(0)<cr>

    " Go to the top right window (which contains the latest version of the
    " file) and go back to the line we were on when we opened the time-lapse,
    " so we can immediately Blame from there which is a common use-case.
    2 wincmd w
    exe 'normal! '.s:here . 'ggz.'
    call s:status('Ready')
endfunction
