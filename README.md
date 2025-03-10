# zig-coreutils [![CI](https://github.com/leecannon/zig-coreutils/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/leecannon/zig-coreutils/actions/workflows/main.yml)

A single executable implementation of various coreutils.

Compatibility with GNU coreutils is only a nice to have it is not a requirement.
Wherever their options are annoying, force inefficent implementation or are very rarely used then differences are acceptable.

Any tools not in GNU coreutils are acceptable as well.

Currently POSIX only to ease development.

---

## Progress

### Subcommands completed:
 * basename
 * clear
 * dirname
 * false
 * groups
 * nprocs
 * touch
 * true
 * whoami
 * yes

### Subcommands todo:
 * [
 * b2sum
 * base32
 * base64
 * basenc
 * cat
 * chcon
 * chgrp
 * chmod
 * chown
 * chroot
 * cksum
 * comm
 * cp
 * csplit
 * cut
 * date
 * dd
 * df
 * diff
 * dir
 * dircolors
 * dirname
 * du
 * echo
 * env
 * expand
 * expr
 * factor
 * false
 * fmt
 * fold
 * hash
 * head
 * hostid
 * id
 * install
 * join
 * link
 * ln
 * logname
 * ls
 * md5sum
 * mkdir
 * mkfifo
 * mknod
 * mktemp
 * mv
 * nice
 * nl
 * nohup
 * nproc
 * numfmt
 * od
 * paste
 * patch
 * pathchk
 * pinky
 * pr
 * printenv
 * printf
 * ptx
 * pwd
 * readlink
 * realpath
 * rm
 * rmdir
 * runcon
 * sed
 * seq
 * sha1sum
 * sha224sum
 * sha256sum
 * sha384sum
 * sha512sum
 * shred
 * shuf
 * sleep
 * sort
 * split
 * stat
 * stdbuf
 * stty
 * sum
 * sync
 * tac
 * tail
 * tee
 * test
 * time
 * timeout
 * tr
 * truncate
 * tsort
 * tty
 * uname
 * unexpand
 * uniq
 * unlink
 * uptime
 * users
 * vdir
 * wc
 * who
