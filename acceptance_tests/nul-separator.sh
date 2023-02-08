#!/bin/bash

setUp() {
    rm test*.yml || true
}


## We need to compare files as arguments in bash
## can't use NUL characters.
assertFileSame() {
    local fileA="$1" fileB="$2"

    assertEquals "$(cat "$fileA" | hd)" \
                 "$(cat "$fileB" | hd)"
}


read-0() {
    local eof="" IFS=''
    while [ "$1" ]; do
        read -r -d '' -- "$1" || eof=1
        shift
    done
    [ -z "$eof" ]
}


read-0-err() {
    local ret="$1" eof="" idx=0 last=
    read -r -- "${ret?}" <<<""
    shift
    while [ "$1" ]; do
        read -r -d '' -- "$1" || {
            eof="$1"
            [ -z "${!ret}" ] && {
                read -r -- "${ret?}" <<<"${!eof}"
                last=$idx
            }
        }
        ((idx++))
        shift
    done
    [ -z "$eof" ] || {
        if [ "$last" != 0 ]; then
            echo "Error: read-0-err couldn't fill all value" >&2
            read -r -- "${ret?}" <<<"127"
        fi
        false
    }
}

wyq() {
    local exp="$1"
    ./yq e -0 "$1"
    printf "%s" "$?"
}

wyq-r() {
    local exp="$1"
    ./yq e -0 -r=false "$1"
    printf "%s" "$?"
}

testBasicUsageRaw() {
  cat >test.yml <<EOL
a: foo
b: bar
EOL

  printf "foo\0bar\0" >expected.out

  assertFileSame <(cat expected.out) \
                 <(./yq e -0 '.a, .b' test.yml)

  rm expected.out
}

testBasicUsage() {
  cat >test.yml <<EOL
a: foo
b: bar
EOL

  read-0 a b < <(./yq e -0 '.a, .b' test.yml)

  assertEquals "foo" "$a"
  assertEquals "bar" "$b"

}

testBasicUsageJson() {
  cat >test.yml <<EOL
a:
  x: foo
b: bar
EOL

  read-0 a b < <(./yq e -0 -o=json '.a, .b' test.yml)

  assertEquals '{
  "x": "foo"
}' "$a"
  assertEquals '"bar"' "$b"

}

testFailWithValueContainingNUL() {
  cat >test.yml <<EOL
a: "foo\u0000bar"
b: 1
c: |
  wiz
  boom
EOL

  read-0 a b c < <(./yq e -0 '.a, .b, .c' test.yml)
  errlvl="$?"
  assertNotEquals "0" "$errlvl"

  ## using -r=false solves the issue but keeps all in yaml

  read-0 a b c < <(./yq e -0 -r=false '.a, .b, .c' test.yml)
  errlvl="$?"
  assertEquals "0" "$errlvl"

  assertEquals '"foo\0bar"' "$a"
  assertEquals '1' "$b"
  assertEquals '|
  wiz
  boom' "$c"
}

testDistinguishBetweenEOFAndFailure() {
    cat >test.yml <<EOL
- yay
- wiz
- "foo\0bar"
- hop
- pow
EOL

    res=""
    while read-0 a || ! ret="$a"; do
        res+="$a:"
    done < <(./yq e -0 '.[]' test.yml; printf "%s" "$?")

    assertEquals "1" "$ret"
    assertEquals "yay:wiz:" "$res"

    cat >test.yml <<EOL
- yay
- wiz
- hop
- pow
EOL

    res=""
    while read-0 a || ! ret="$a"; do
        res+="$a:"
    done < <(./yq e -0 '.[]' test.yml; printf "%s" "$?")
    assertEquals "0" "$ret"
    assertEquals "yay:wiz:hop:pow:" "$res"

}

testDistinguishBetweenEOFAndFailure2() {
    cat >test.yml <<EOL
- yay
- wiz
- "foo\0bar"
- hop
- pow
EOL

    res=""
    while read-0 a || ! ret="$a"; do
        res+="$a:"
    done < <(./yq e -0 '.[]' test.yml; printf "$?")

    assertEquals "1" "$ret"
    assertEquals "yay:wiz:" "$res"

    cat >test.yml <<EOL
- yay
- wiz
- hop
- pow
EOL

    res=""
    while read-0 a || ! ret="$a"; do
        res+="$a:"
    done < <(./yq e -0 '.[]' test.yml; printf "$?")
    assertEquals "0" "$ret"
    assertEquals "yay:wiz:hop:pow:" "$res"

}

testDistinguishBetweenEOFAndFailure3() {
    cat >test.yml <<EOL
- yay
- wiz
- "foo\0bar"
- hop
- pow
EOL

    res=""
    while read-0-err E a b; do
        res+="$a: $b;"
    done < <(wyq '.[]' < test.yml)

    assertEquals "1" "$E"
    assertEquals "yay: wiz;" "$res"

    cat >test.yml <<EOL
- yay
- wiz
- hop
- pow
EOL

    res=""
    while read-0-err E a b; do
        res+="$a: $b;"
    done < <(wyq '.[]' < test.yml)

    assertEquals "0" "$E"
    assertEquals "yay: wiz;hop: pow;" "$res"


    cat >test.yml <<EOL
- yay
- wiz
- hop
- pow
- kwak
EOL

    res=""
    while read-0-err E a b; do
        res+="$a: $b;"
    done < <(wyq '.[]' < test.yml)

    assertEquals "127" "$E"
    assertEquals "yay: wiz;hop: pow;" "$res"

}


source ./scripts/shunit2