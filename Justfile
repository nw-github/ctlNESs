play CMD:
    ctl r -qo . -- "{{CMD}}" -s 4

dump:
    mkdir -p build
    ctl p -qp . -o build/main.c
