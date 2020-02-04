" vim: sw=4 ts=4 noexpandtab
com! -nargs=0 GitTimeLapse call gittimelapse#git_time_lapse()
noremap  <silent> <script> <Plug>(git-time-lapse)  :<C-u>call git-time-lapse#git_time_lapse()<CR>
