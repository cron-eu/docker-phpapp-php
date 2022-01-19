PS1_ENV=

# Add some environment information to the prompt to avoid doing stuff in wrong container

if [ ! -z "$ENV" ]
then
    if [ ! -z "$ECS_CONTAINER_METADATA_URI" ]
    then
        PS1_ENV=" (ECS|$ENV)"
    elif [ -f "/.dockerenv" ]
    then
        PS1_ENV=" (Docker|$ENV)"
    else
        PS1_ENV=" ($ENV)"
    fi
fi

export PS1="\[\e]0;\u@\h: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]$PS1_ENV:\[\033[01;34m\]\w\[\033[00m\]\\$ "
