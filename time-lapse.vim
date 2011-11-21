function! Display(commit)
	windo %d
	diffoff!
	wincmd t
	exe ':silent :0 read !git show '.a:commit.'^:'.t:path
	exe 'doautocmd filetypedetect BufRead '.t:path

	wincmd l
	exe ':silent :0 read !git show '.a:commit.':'.t:path
	exe 'doautocmd filetypedetect BufRead '.t:path

	wincmd j
	exe ':silent :0 read !git log --stat '.a:commit.'^..'.a:commit
	setfiletype git

	wincmd t
	diffthis
	wincmd l
	diffthis
endfunction

function! Goto(pos)
	let t:current = a:pos

	if t:current < 0
		let t:current = 0
		return 0
	elseif t:current >= g:total - 1
		let t:current = g:total - 2
		return 0
	endif

	call Display(t:commits[t:current])
	return 1
endfunction

function! Move(amount)
	let t:current = t:current + a:amount
	call Goto(t:current)
endfunction

function! Blame()
	let current = t:commits[t:current]
	let line = getpos(".")[1]

	let tmpfile = tempname()
	exe ':silent :read !git blame -s -n -L'.line.','.line.' '.
				\current.' -- '.t:path.' > '.tmpfile
	let output = readfile(tmpfile)
	call delete(tmpfile)
	let results = split(output[0])

	if results[0] == "fatal:"
		return
	endif

	for i in range(len(t:commits))
		if t:commits[i] =~ results[0]
			call Goto(i)
			break
		endif
	endfor

	exe ':'.results[1]
	normal z.
endfunction

function! GetLog()
	let tmpfile = tempname()
	exe ':silent :!git log --pretty=format:"\%H" '.t:path.' > '.tmpfile
	let t:commits = readfile(tmpfile)
	call delete(tmpfile)
	let g:total = len(t:commits)

	" The first line in the file is the most recent commit
	let t:current = 0
	call Display(t:commits[t:current])
endfunction

function! ChDir()
	" Change directory to the one with .git in it and return path to the
	" current file from there. If you live in this directory and execute git
	" commands on that path then everything will work.
	cd %:p:h
	let dir = finddir('.git', '.;')
	exe 'cd '.dir.'/..'
	let path = fnamemodify(@%, ':.')
	return path
endfunction

function! TimeLapse()
	" Open a new tab with a time-lapse view of the file in the current
	" buffer.
	let path = ChDir()

	tabnew
	set buftype=nofile

	new
	set buftype=nofile

	wincmd j
	resize 10
	set winfixheight

	wincmd k
	vnew
	set buftype=nofile

	let t:path = path
	call GetLog()

	" Go backwards and forwards one commit
	windo map <buffer> <Left> :call Move(1) <cr>
	windo map <buffer> <Right> :call Move(-1) <cr>

	" Rewind all the way to the start or end
	windo map <buffer> <S-Left> :call Goto(g:total - 2) <cr>
	windo map <buffer> <S-Right> :call Goto(0) <cr>

	windo map <buffer>  :call Blame() <cr>
endfunction
