#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=go122 # -$(date +%s)
COMMIT_MSG="Use Go 1.22"

REPO_ROOT=/tmp/kubedb-repo-refresher

API_REF=${API_REF:-c5efabadb}

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    changed=($(git diff --name-only))
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    diff=($(echo ${changed[@]} ${gomodfiles[@]} | tr ' ' '\n' | sort | uniq -u))
    return ${#diff[@]}
}

refresh() {
    echo "refreshing repository: $1"
    rm -rf $REPO_ROOT
    mkdir -p $REPO_ROOT
    pushd $REPO_ROOT
    git clone --no-tags --no-recurse-submodules --depth=1 git@github.com:$1.git
    name=$(ls -b1)
    cd $name
    git checkout -b $PR_BRANCH

    sed -i 's/?=\ 1.20/?=\ 1.21/g' Makefile
    sed -i 's/?=\ 1.21/?=\ 1.22/g' Makefile
    sed -i 's|appscode/gengo:release-1.25|appscode/gengo:release-1.29|g' Makefile
    sed -i 's/goconst,//g' Makefile
    sed -i 's|gcr.io/distroless/static-debian11|gcr.io/distroless/static-debian12|g' Makefile
    sed -i 's|debian:bullseye|debian:bookworm|g' Makefile

    pushd .github/workflows/ && {
        # update GO
        sed -i 's/Go\ 1.20/Go\ 1.21/g' *
        sed -i 's/go-version:\ ^1.20/go-version:\ ^1.21/g' *
        sed -i 's/go-version:\ 1.20/go-version:\ 1.21/g' *
        sed -i "s/go-version:\ '1.20'/go-version:\ '1.21'/g" *

        sed -i 's/Go\ 1.21/Go\ 1.22/g' *
        sed -i 's/go-version:\ ^1.21/go-version:\ ^1.22/g' *
        sed -i 's/go-version:\ 1.21/go-version:\ 1.22/g' *
        sed -i "s/go-version:\ '1.21'/go-version:\ '1.22'/g" *
        popd
    }

    if repo_uptodate; then
        echo "Repository $1 is up-to-date."
    else
        git add --all
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin HEAD -f
        hub pull-request \
            --message "$COMMIT_MSG" \
            --message "Signed-off-by: $(git config --get user.name) <$(git config --get user.email)>" || true
        # gh pr create \
        #     --base master \
        #     --fill \
        #     --label automerge \
        #     --reviewer tamalsaha
    fi
    popd
}

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "Correct usage: $SCRIPT_NAME <path_to_repos_list>"
    exit 1
fi

if [ -x $GITHUB_TOKEN ]; then
    echo "Missing env variable GITHUB_TOKEN"
    exit 1
fi

# ref: https://linuxize.com/post/how-to-read-a-file-line-by-line-in-bash/#using-file-descriptor
while IFS=, read -r -u9 repo cmd; do
    if [ -z "$repo" ]; then
        continue
    fi
    refresh "$repo" "$cmd"
    echo "################################################################################"
done 9<$1
