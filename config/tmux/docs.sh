#!/usr/bin/env bash
# Rust std docs: pick any item from the local rustdoc index, open it in Zen.
set -u

COLORS="--color=bg:-1,bg+:-1,prompt:#f6c177,pointer:#eb6f92,header:#6e6a86"
RUST_STD=$(rustc --print sysroot 2>/dev/null)/share/doc/rust/html/std
IDX=${XDG_CACHE_HOME:-$HOME/.cache}/tmux-docs/rust-std.tsv

# Every std item plus the keyword pages, as "name<TAB>file". Rebuilt when the
# toolchain's all.html is newer than the cache.
if [ ! -f "$IDX" ] || [ "$IDX" -ot "$RUST_STD/all.html" ]; then
    mkdir -p "${IDX%/*}" || exit 1
    {
        grep -o '<a href="[^"]*">[^<]*</a>' "$RUST_STD/all.html" |
            awk -v root="$RUST_STD" '{
                href=$0; sub(/^<a href="/, "", href); sub(/">.*$/, "", href)
                name=$0; sub(/^.*">/, "", name); sub(/<\/a>$/, "", name)
                if (href ~ /^[^\.].*\.html$/) printf "%s\t%s/%s\n", name, root, href
            }'
        for f in "$RUST_STD"/keyword.*.html; do
            name=${f##*/keyword.}
            printf 'keyword %s\t%s\n' "${name%.html}" "$f"
        done
    } > "$IDX.tmp" && mv "$IDX.tmp" "$IDX" || exit 1
fi

sel=$(fzf --delimiter='\t' --with-nth=1 \
    --prompt="  rust std ❯ " \
    --header="enter: open in Zen" \
    $COLORS < "$IDX") || exit 0
[ -n "$sel" ] || exit 0

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
zen-browser --new-tab "file://$(cut -f2 <<<"$sel")" >/dev/null 2>&1
