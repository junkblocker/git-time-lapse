=================
`git-time-lapse`_
=================

Fork of `git-time-lapse: Perforce-style`_ for vim

Description
===========

You're editing a file which is in a git repository. Press a key which opens a
new tab which shows how that commit changed that file in vim's diff mode (:help
diff), with a window at the bottom showing the commit message. Left and right
arrows move through the history. Shift-left and shift-right go all the way to
the end. Return on a line goes back to the last commit that touched that line
(using git blame).

Close the tab when you're bored with it and carry on vimming as usual. You can
open as many time-lapse tabs on different files in one vim session as you want.

Inspired by the "time lapse view" in the Perforce gui.


Use
===

Map a key in your .vimrc, e.g.:

.. code:: vim

      nmap <Leader>gt <Plug>(git-time-lapse)

or use the command:

.. code:: vim

      :GitTimeLapse

to run it.

.. _`git-time-lapse`:
   https://github.com/junkblocker/git-time-lapse

.. _`git-time-lapse: Perforce-style`:
   http://vim.sourceforge.net/scripts/script.php?script_id=3849
