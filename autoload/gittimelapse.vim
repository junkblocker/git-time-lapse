" vim: set et fdm=diff fenc=utf-8 ff=unix sts=0 sw=4 ts=4 tw=79 wrap :
" String display width utilities {{{
" The string display width functions were imported from vital.vim
" https://github.com/vim-jp/vital.vim (Public Domain)
if exists('*strdisplaywidth')
    " Use builtin function.
    function! s:wcswidth(str) " {{{
        return strdisplaywidth(a:str)
    endfunction
  " }}}
else
    function! s:wcswidth(str) " {{{
        if a:str =~# '^[\x00-\x7f]*$'
        return 2 * strlen(a:str)
                \ - strlen(substitute(a:str, '[\x00-\x08\x0b-\x1f\x7f]', '', 'g'))
        end

        let l:mx_first = '^\(.\)'
        let l:str = a:str
        let l:width = 0
        while 1
        let l:ucs = char2nr(substitute(l:str, l:mx_first, '\1', ''))
        if l:ucs == 0
            break
        endif
        let l:width += s:_wcwidth(l:ucs)
        let l:str = substitute(l:str, l:mx_first, '', '')
        endwhile
        return l:width
    endfunction
    " }}}
    function! s:_wcwidth(ucs) " UTF-8 only. {{{
        let l:ucs = a:ucs
        if l:ucs > 0x7f && l:ucs <= 0xff
            return 4
        endif
        if l:ucs <= 0x08 || 0x0b <= l:ucs && l:ucs <= 0x1f || l:ucs == 0x7f
            return 2
        endif
        if (l:ucs >= 0x1100
            \  && (l:ucs <= 0x115f
            \  || l:ucs == 0x2329
            \  || l:ucs == 0x232a
            \  || (l:ucs >= 0x2e80 && l:ucs <= 0xa4cf
            \      && l:ucs != 0x303f)
            \  || (l:ucs >= 0xac00 && l:ucs <= 0xd7a3)
            \  || (l:ucs >= 0xf900 && l:ucs <= 0xfaff)
            \  || (l:ucs >= 0xfe30 && l:ucs <= 0xfe6f)
            \  || (l:ucs >= 0xff00 && l:ucs <= 0xff60)
            \  || (l:ucs >= 0xffe0 && l:ucs <= 0xffe6)
            \  || (l:ucs >= 0x20000 && l:ucs <= 0x2fffd)
            \  || (l:ucs >= 0x30000 && l:ucs <= 0x3fffd)
            \  ))
            return 2
        endif
        return 1
    endfunction
  " }}}
endif
function! s:strwidthpart(str, width) " {{{
    if a:width <= 0
        return ''
    endif
    let l:ret = a:str
    let l:width = s:wcswidth(a:str)
    while l:width > a:width
        let char = matchstr(l:ret, '.$')
        let l:ret = l:ret[: -1 - len(char)]
        let l:width -= s:wcswidth(char)
    endwhile

    return l:ret
endfunction
" }}}
function! s:truncate(str, width) " {{{
    if a:str =~# '^[\x20-\x7e]*$'
        return len(a:str) < a:width ?
                    \ printf('%-'.a:width.'s', a:str) : strpart(a:str, 0, a:width)
    endif

    let l:ret = a:str
    let l:width = s:wcswidth(a:str)
    if l:width > a:width
        let l:ret = s:strwidthpart(l:ret, a:width)
        let l:width = s:wcswidth(l:ret)
    endif

    if l:width < a:width
        let l:ret .= repeat(' ', a:width - l:width)
    endif

    return l:ret
endfunction
" }}}
function! s:status(str) " {{{
    if ! &cmdheight
        return
    endif
    redraw
    echo s:truncate(a:str, &columns * min([&cmdheight, 1]) - 1)
endfunction
function! s:display(commit)
    call s:status('Displaying commit ' . a:commit)
    " clears all input in every buffer of the tab
    windo %d
    diffoff!
    wincmd t
    call s:status('Gathering commit content ...')
    exe ':silent :0 read !git show '.a:commit.s:fnameescape('^:').s:fnameescape(t:path)
    exe 'doautocmd filetypedetect BufRead '.s:fnameescape(t:path)

    wincmd l
    call s:status('Gathering commit content ...')
    exe ':silent :0 read !git show '.a:commit.s:fnameescape(':').s:fnameescape(t:path)
    exe 'doautocmd filetypedetect BufRead '.s:fnameescape(t:path)

    wincmd j
    call s:status('Gathering commit log ...')
    exe ':silent :0 read !git log --stat '.a:commit.s:fnameescape('^..').a:commit
    call s:status('Gathered commit log')
    setfiletype git

    wincmd t
    diffthis

    wincmd l
    diffthis

    " Move back to where we were if it's still there, otherwise go to the top
    if s:here <= line('$')
        exe ':'.s:here
    else
        :0
    endif

    normal z.

    " Some people have reported that you need to do this to make sure the left
    " buffer is in the right place.
    wincmd t
    normal z.

    wincmd j
    :0
    redraw!
endfunction

function! s:goto(pos)
    let t:current = a:pos

    if t:current < 0
        let t:current = 0
        return 0
    elseif t:current >= t:total - 1
        let t:current = t:total - 2
        return 0
    endif

    call s:display(t:commits[t:current])
    return 1
endfunction

function! s:move(amount)
    let t:current = t:current + a:amount
    call s:goto(t:current)
    redraw!
endfunction

function! s:blame()
    call s:status('Collecting blame ... ')
    let current = t:commits[t:current]
    let line = line('.')

    let output = system('git blame -p -n -L'.shellescape(line).','.shellescape(line).' '.
                        \shellescape(current).' -- '.shellescape(t:path))

    let results = split(output)

    if results[0] == "fatal:"
        return
    endif
    call s:status('Collected blame')

    for i in range(len(t:commits))
        if t:commits[i] =~ results[0]
            call s:goto(i)
            break
        endif
    endfor

    wincmd t
    wincmd l
    exe ':'.results[1]
    normal z.
    wincmd j
endfunction

function! s:get_log()
    call s:status('Collecting log ... ')
    let tmpfile = tempname()
    exe ':silent :!git log --no-merges ' . s:fnameescape('--pretty=format:"%H"'). ' '.s:fnameescape(t:path).' > '.s:fnameescape(tmpfile)
    let t:commits = readfile(tmpfile)
    call delete(tmpfile)
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
    call s:status("Changing to workspace ...")
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
        call s:status("Changing to workspace ... failed.")
    endif
endfunction

function! gittimelapse#git_time_lapse()
    call s:status("Starting ...")
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
    windo map <buffer> <silent> <S-Left> :call <SID>goto(t:total - 2)<cr>
    windo map <buffer> <silent> <S-Right> :call <SID>goto(0)<cr>

    windo map <buffer> <silent> <CR> :call <SID>blame()<cr>

    " Go to the top right window (which contains the latest version of the
    " file) and go back to the line we were on when we opened the time-lapse,
    " so we can immediately Blame from there which is a common use-case.
    2 wincmd w
    exe ':'.s:here
    normal z.
endfunction
