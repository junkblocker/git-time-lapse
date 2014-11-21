git-time-lapse
==============

Fork of git-time-lapse: Perforce-style for vim

You're editing a file which is in a git repository. Press a key which opens a new tab which shows how that commit changed that file in vim's diff mode (:help diff), with a window at the bottom showing the commit message. Left and right arrows move through the history. Shift-left and shift-right go all the way to the end. Return on a line goes back to the last commit that touched that line (using git blame). 

Close the tab when you're bored with it and carry on vimming as usual. You can open as many time-lapse tabs on different files in one vim session as you want. 

Inspired by the "time lapse view" in the Perforce gui which I thought was quite good, although I prefer the vim version.
