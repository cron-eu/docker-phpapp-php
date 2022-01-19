# Overwrite default Debian .bashrc to have a global PS1 applied

shopt -s histappend
export PROMPT_COMMAND='history -a'
export HISTSIZE=10000

cd "/app"
