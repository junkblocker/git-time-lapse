function! Display(commit)
	windo %d
	diffoff!
	wincmd t
	exe ':silent :0 read !git show '.a:commit.'^:'.s:path
	exe 'doautocmd filetypedetect BufRead '.s:path

	wincmd l
	exe ':silent :0 read !git show '.a:commit.':'.s:path
	exe 'doautocmd filetypedetect BufRead '.s:path

	wincmd j
	exe ':silent :0 read !git log --stat '.a:commit.'^..'.a:commit
	setfiletype git

	wincmd t
	diffthis
	wincmd l
	diffthis
endfunction

function! Goto(pos)
	let s:current = a:pos

	if s:current < 0
		let s:current = 0
		return 0
	elseif s:current >= g:total - 1
		let s:current = g:total - 2
		return 0
	endif

	call Display(s:commits[s:current])
	return 1
endfunction

function! Move(amount)
	let s:current = s:current + a:amount
	call Goto(s:current)
endfunction

function! GotoNextChange(dir)
	"Rewind or fast-forward to the next change that affects the current line.
	"Doesn't work too well though because the line number has probably changed
	"(if lines above were added or removed)
	let line = getpos(".")[1]

	while 1
		wincmd t
		let before = getline(line)

		wincmd l
		let after = getline(line)

		if before != after || !Move(a:dir)
			break
		endif

	endwhile
endfunction

function! GetLog()
	let tmpfile = tempname()
	exe ':silent :!git log --pretty=format:"\%H" '.s:path.' > '.tmpfile
	let s:commits = readfile(tmpfile)
	call delete(tmpfile)
	let g:total = len(s:commits)

	" The first line in the file is the most recent commit
	let s:current = 0
	call Display(s:commits[s:current])
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
	let s:path = ChDir()

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

	call GetLog()

	" Go backwards and forwards one commit
	map <Left> :call Move(1) <cr>
	map <Right> :call Move(-1) <cr>

	" Rewind all the way to the start or end
	map <S-Left> :call Goto(g:total - 2) <cr>
	map <S-Right> :call Goto(0) <cr>

	map <C-S-Left> :call GotoNextChange(1) <cr>
	map <C-S-Right> :call GotoNextChange(-1) <cr>
endfunction
