# Overwrite default Debian .bashrc to have a global PS1 applied

shopt -s histappend
export PROMPT_COMMAND='history -a'
export HISTSIZE=10000

if [[ $- == *i* ]]; then
    # Interative shell, print out some information
    URL=$(env | egrep "BASE_?URL" | head -1 | cut -f 2 -d "=")
    test ! -z "$ENV" && figlet "$ENV" && printf "\n"
    test ! -z "$ENV" && printf "%15s: %s\n" "ENV" "$ENV"
    test ! -z "$AWS_LOG_GROUP" && printf "%15s: %s\n" "AWS_LOG_GROUP" "$AWS_LOG_GROUP"
    test ! -z "$URL" && printf "%15s: %s\n" "BASE_URL" "$URL"
    test ! -z "$TYPO3_CONTEXT" && printf "%15s: %s\n" "TYPO3_CONTEXT" "$TYPO3_CONTEXT"
    test ! -z "$FLOW_CONTEXT" && printf "%15s: %s\n" "FLOW_CONTEXT" "$FLOW_CONTEXT"
    test ! -z "$PHP_VERSION" && printf "%15s: %s\n" "PHP_VERSION" "$PHP_VERSION"
    test ! -z "$GIT_VERSION" && printf "%15s: %s\n" "GIT_VERSION" "$GIT_VERSION"
    printf "\n"
fi

cd "/app"
