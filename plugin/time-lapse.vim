" vim: sw=4 ts=4 noexpandtab
function! s:get_SID_prefix()
	" Get SID via this function's assigned prefix
	return matchstr(expand('<sfile>'), '<SNR>\d\+_')
endfunction

let s:SID = s:get_SID_prefix()
delfunction s:get_SID_prefix

function! s:Display(commit)
	" clears all input in every buffer of the tab
	windo %d
	diffoff!
	wincmd t
	exe ':silent :0 read !git show '.s:fnameescape(a:commit.'^:'.t:path)
	exe 'doautocmd filetypedetect BufRead '.s:fnameescape(t:path)

	wincmd l
	exe ':silent :0 read !git show '.s:fnameescape(a:commit.':'.t:path)
	exe 'doautocmd filetypedetect BufRead '.s:fnameescape(t:path)

	wincmd j
	exe ':silent :0 read !git log --stat '.s:fnameescape(a:commit.'^..'.a:commit)
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
endfunction

function! s:Goto(pos)
	let t:current = a:pos

	if t:current < 0
		let t:current = 0
		return 0
	elseif t:current >= t:total - 1
		let t:current = t:total - 2
		return 0
	endif

	call s:Display(t:commits[t:current])
	return 1
endfunction

function! s:Move(amount)
	let t:current = t:current + a:amount
	call s:Goto(t:current)
endfunction

function! s:Blame()
	let current = t:commits[t:current]
	let line = line('.')

	let output = system('git blame -p -n -L'.shellescape(line).','.shellescape(line).' '.
						\shellescape(current).' -- '.shellescape(t:path))

	let results = split(output)

	if results[0] == "fatal:"
		return
	endif

	for i in range(len(t:commits))
		if t:commits[i] =~ results[0]
			call s:Goto(i)
			break
		endif
	endfor

	wincmd t
	wincmd l
	exe ':'.results[1]
	normal z.
	wincmd j
endfunction

function! s:GetLog()
	let tmpfile = tempname()
	exe ':silent :!git log --no-merges --pretty=format:"\%H" '.s:fnameescape(t:path).' > '.s:fnameescape(tmpfile)
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

function! s:ChDir()
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
	endif
endfunction

function! s:git_time_lapse()
	" Open a new tab with a time-lapse view of the file in the current
	" buffer.
	let path = s:ChDir()
	let s:here = line('.')

	tabnew
	let t:path = path

	if s:GetLog() <= 1
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
	call s:Display(t:commits[t:current])

	" Go backwards and forwards one commit
	exe 'windo map <buffer> <silent> <Left> :call ' . s:SID . 'Move(1) <cr>'
	exe 'windo map <buffer> <silent> <Right> :call ' . s:SID . 'Move(-1) <cr>'

	" Rewind all the way to the start or end
	exe 'windo map <buffer> <silent> <S-Left> :call ' . s:SID . 'Goto(t:total - 2) <cr>'
	exe 'windo map <buffer> <silent> <S-Right> :call ' . s:SID . 'Goto(0) <cr>'

	exe 'windo map <buffer> <silent> <CR> :call ' . s:SID . 'Blame() <cr>'

	" Go to the top right window (which contains the latest version of the
	" file) and go back to the line we were on when we opened the time-lapse,
	" so we can immediately Blame from there which is a common use-case.
	2 wincmd w
	exe ':'.s:here
	normal z.
endfunction

com! -nargs=0 GitTimeLapse call s:git_time_lapse()
noremap  <silent> <script> <Plug>(git-time-lapse)  :<C-u>call <SID>git_time_lapse()<CR>
