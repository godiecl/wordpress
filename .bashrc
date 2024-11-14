# ~/.bashrc: executed by bash(1) for non-login shells.

PS1='🐳  \[\033[1;36m\]\h \[\033[1;34m\]\W\[\033[0;35m\] \[\033[1;36m\]# \[\033[0m\] '
umask 022

# colorized:
export SHELL
export LS_OPTIONS='--color=auto'
eval $(dircolors ~/.dircolors)
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'

# Some more alias to avoid making mistakes:
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
