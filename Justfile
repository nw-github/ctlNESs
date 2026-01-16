play CMD:
    ctl r -o1 . -- "{{CMD}}" -s 4

dump:
    mkdir -p build
    ctl p -vo build/ctlness.c

sanitize ROM:
    ctl r -vpo2 --ccargs " -fsanitize=address -fPIE -pie" . -- -v "{{ROM}}"
