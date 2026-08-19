#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
private_root=${PRIVATE_OPS_ROOT:?Set PRIVATE_OPS_ROOT to the local private-operations checkout.}
private_remote=${PRIVATE_OPS_REMOTE:?Set PRIVATE_OPS_REMOTE to the private repository URL.}

if [ ! -d "$private_root/.git" ]; then
    git clone "$private_remote" "$private_root"
fi

sync_path() {
    source_path="$project_root/$1"
    target_path="$private_root/$1"
    [ -e "$source_path" ] || return 0
    mkdir -p "$(dirname "$target_path")"
    rsync -a "$source_path" "$target_path"
}

# These paths are operational context, not public product source. They remain
# usable in their existing local locations and are mirrored to the private repo.
for path in \
    .taskmaster state .superdesign Artifacts Screenshots Prototypes \
    docs/course-setup-spec.md .agents/commands .claude/commands
do
    sync_path "$path"
done

git -C "$private_root" add -A -- \
    .taskmaster state .superdesign Artifacts Screenshots Prototypes \
    docs/course-setup-spec.md .agents/commands .claude/commands

if git -C "$private_root" diff --cached --quiet; then
    echo "Private context already up to date."
    exit 0
fi

git -C "$private_root" -c user.name='Flowmap Operations' -c user.email='ops@flowmap.invalid' \
    commit -m 'Synchronise private Flowmap context' >/dev/null
git -C "$private_root" push origin HEAD
echo "Private context synchronised."
