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
	exe ':silent :0 read !git show "'.a:commit.'^:'.t:path.'"'
	exe 'doautocmd filetypedetect BufRead '.t:path

	wincmd l
	exe ':silent :0 read !git show "'.a:commit.':'.t:path.'"'
	exe 'doautocmd filetypedetect BufRead '.t:path

	wincmd j
	exe ':silent :0 read !git log --stat "'.a:commit.'^..'.a:commit.'"'
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

	let output = system('git blame -p -n -L'.line.','.line.' '.
						\current.' -- '.t:path)

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
	exe ':silent :!git log --no-merges --pretty=format:"\%H" '.t:path.' > '.tmpfile
	let t:commits = readfile(tmpfile)
	call delete(tmpfile)
	let t:total = len(t:commits)
	return t:total
endfunction

function! s:fnameescape(p) " {{{
	return substitute(fnameescape(a:p), '[()]', '\\&', 'g')
endfunction

function! s:ChDir()
	" Change directory to the one with .git in it and return path to the
	" current file from there. If you live in this directory and execute git
	" commands on that path then everything will work.
	let l:rfile = resolve(expand('%:p'))
	let l:rdir = fnamemodify(l:rfile, ':h')
	exe 'lcd ' . s:fnameescape(l:rdir)
	silent! let l:git_dir = system('git rev-parse --git-dir')
	let l:git_dir = resolve(fnamemodify(matchstr(l:git_dir, '^\zs.*\.git\ze'), ':p'))
	let l:sourcedir = fnamemodify(l:git_dir, ':h')
	exe 'lcd ' . s:fnameescape(l:sourcedir)
	return l:rfile[strlen(l:git_dir)-4:]
endfunction

function! TimeLapse()
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
	exe 'windo map <buffer> <Left> :call ' . s:SID . 'Move(1) <cr>'
	exe 'windo map <buffer> <Right> :call ' . s:SID . 'Move(-1) <cr>'

	" Rewind all the way to the start or end
	exe 'windo map <buffer> <S-Left> :call ' . s:SID . 'Goto(t:total - 2) <cr>'
	exe 'windo map <buffer> <S-Right> :call ' . s:SID . 'Goto(0) <cr>'

	exe 'windo map <buffer>  :call ' . s:SID . 'Blame() <cr>'

	" Go to the top right window (which contains the latest version of the
	" file) and go back to the line we were on when we opened the time-lapse,
	" so we can immediately Blame from there which is a common use-case.
	2 wincmd w
	exe ':'.s:here
	normal z.
endfunction
