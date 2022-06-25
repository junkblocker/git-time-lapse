" vim: sw=4 ts=4 noexpandtab
com! -nargs=0 GitTimeLapse call gittimelapse#git_time_lapse()
noremap  <silent> <script> <Plug>(git-time-lapse)  :<C-u>call gittimelapse#git_time_lapse()<CR>
