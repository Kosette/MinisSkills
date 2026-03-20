#!/bin/sh
# github-sync-helper: reusable GitHub sync workflows for Minis
# Requirements: git, python3, env GITHUB_TOKEN
set -e

# ---------- helpers ----------
err() { printf '%s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing command: $1"; exit 1; }
}

need_env() {
  name="$1"
  eval "val=\${$name-}"
  [ -n "$val" ] || { err "missing env: $name"; exit 1; }
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

ensure_git_identity() {
  # Keep it local to repo; do not fail if already set
  if [ -z "$(git config user.name || true)" ]; then
    git config user.name "mowenyun"
  fi
  if [ -z "$(git config user.email || true)" ]; then
    git config user.email "mowenyun@users.noreply.github.com"
  fi
}

ensure_askpass() {
  need_env GITHUB_TOKEN
  ASKPASS="/var/minis/workspace/.git_askpass.sh"
  if [ ! -f "$ASKPASS" ]; then
    cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) echo "x-access-token" ;;
  *Password*) echo "$GITHUB_TOKEN" ;;
  *) echo "" ;;
esac
EOF
    chmod +x "$ASKPASS"
  fi
  export GIT_ASKPASS="$ASKPASS"
  export GIT_TERMINAL_PROMPT=0
}

usage() {
  cat <<'EOF'
Usage:
  sh gh_sync.sh init
  sh gh_sync.sh clone --url <url> [--dir <path>]
  sh gh_sync.sh remotes
  sh gh_sync.sh add-remote --name <n> --url <url>
  sh gh_sync.sh set-remote-url --name <n> --url <url>
  sh gh_sync.sh remove-remote --name <n>
  sh gh_sync.sh add-upstream --upstream <owner/repo>
  sh gh_sync.sh status
  sh gh_sync.sh diff [--staged]
  sh gh_sync.sh log [--n <k>]
  sh gh_sync.sh branches
  sh gh_sync.sh create-branch --name <b> [--from <ref>]
  sh gh_sync.sh checkout --name <b>
  sh gh_sync.sh add [--path <p>]
  sh gh_sync.sh commit --message <m>
  sh gh_sync.sh fetch [--remote <n>]
  sh gh_sync.sh pull [--remote <n>] [--branch <b>]
  sh gh_sync.sh push [--remote <n>] [--branch <b>]
  sh gh_sync.sh stash [--save <msg> | --pop | --apply | --list]
  sh gh_sync.sh tag --name <tag> [--message <msg>]
  sh gh_sync.sh submodule [--add <url> <path> | --update | --status]
  sh gh_sync.sh delete-branches --keep <branch>
  sh gh_sync.sh empty-dir --dir <path>
  sh gh_sync.sh restore-dir --src <path> --dst <path>
  sh gh_sync.sh push-main
  sh gh_sync.sh pr --upstream <owner/repo> --head <owner:branch> --base <branch> --title <t> --body <b>
EOF
}

cmd="$1"; shift || true

need_cmd git
need_cmd python3

ROOT="$(repo_root)"
[ -n "$ROOT" ] || { err "not inside a git repo"; exit 1; }
cd "$ROOT"

enable_table_summary() {
  # call: enable_table_summary; then append to $SUMMARY
  SUMMARY=""
}

add_row() {
  # add_row idx col2 col3 col4
  i="$1"; c2="$2"; c3="$3"; c4="$4"
  SUMMARY="$SUMMARY
| $i | $c2 | $c3 | $c4 |"
}

print_summary() {
  printf '%s\n' "| 序号 | 动作 | 结果 | 备注 |"
  printf '%s\n' "|---:|---|---|---|"
  printf '%s\n' "$SUMMARY" | sed '1{/^$/d;}'
}

enable_table_summary

case "$cmd" in
  init)
    git init >\/dev\/null 2>&1 || true
    add_row 1 init "OK" "initialized"
    ;;

  clone)
    url=""; dir=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --url) url="$2"; shift 2;;
        --dir) dir="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$url" ] || { err "--url required"; usage; exit 1; }
    if [ -n "$dir" ]; then
      git clone "$url" "$dir" >\/dev\/null
      add_row 1 clone "OK" "$url -> $dir"
    else
      git clone "$url" >\/dev\/null
      add_row 1 clone "OK" "$url"
    fi
    ;;

  add-remote)
    name=""; url=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --name) name="$2"; shift 2;;
        --url) url="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$name" ] && [ -n "$url" ] || { err "--name and --url required"; usage; exit 1; }
    git remote add "$name" "$url"
    add_row 1 add-remote "OK" "$name=$url"
    ;;

  set-remote-url)
    name=""; url=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --name) name="$2"; shift 2;;
        --url) url="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$name" ] && [ -n "$url" ] || { err "--name and --url required"; usage; exit 1; }
    git remote set-url "$name" "$url"
    add_row 1 set-remote-url "OK" "$name=$url"
    ;;

  remove-remote)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --name) name="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$name" ] || { err "--name required"; usage; exit 1; }
    git remote remove "$name"
    add_row 1 remove-remote "OK" "$name"
    ;;

  status)
    s="$(git status --porcelain 2>\/dev\/null || true)"
    if [ -n "$s" ]; then
      add_row 1 status "DIRTY" "$(printf '%s' "$s" | tr '\n' '; ' | sed 's/; $//')"
    else
      add_row 1 status "CLEAN" "no changes"
    fi
    ;;

  diff)
    staged=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --staged) staged=1; shift 1;;
        *) break;;
      esac
    done
    if [ "$staged" -eq 1 ]; then
      d="$(git diff --staged --name-status)"
    else
      d="$(git diff --name-status)"
    fi
    add_row 1 diff "OK" "$(printf '%s' "$d" | tr '\n' '; ' | sed 's/; $//')"
    ;;

  log)
    n=10
    while [ $# -gt 0 ]; do
      case "$1" in
        --n) n="$2"; shift 2;;
        *) break;;
      esac
    done
    l="$(git log -n "$n" --oneline 2>\/dev\/null || true)"
    add_row 1 log "OK" "$(printf '%s' "$l" | tr '\n' '; ' | sed 's/; $//')"
    ;;

  create-branch)
    name=""; from=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --name) name="$2"; shift 2;;
        --from) from="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$name" ] || { err "--name required"; usage; exit 1; }
    if [ -n "$from" ]; then
      git checkout -b "$name" "$from" >\/dev\/null
    else
      git checkout -b "$name" >\/dev\/null
    fi
    add_row 1 create-branch "OK" "$name"
    ;;

  checkout)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --name) name="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$name" ] || { err "--name required"; usage; exit 1; }
    git checkout "$name" >\/dev\/null
    add_row 1 checkout "OK" "$name"
    ;;

  add)
    path="-A"
    while [ $# -gt 0 ]; do
      case "$1" in
        --path) path="$2"; shift 2;;
        *) break;;
      esac
    done
    git add "$path"
    add_row 1 add "OK" "$path"
    ;;

  commit)
    msg=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --message) msg="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$msg" ] || { err "--message required"; usage; exit 1; }
    ensure_git_identity
    git commit -m "$msg" >\/dev\/null
    add_row 1 commit "OK" "$msg"
    ;;

  fetch)
    remote="origin"
    while [ $# -gt 0 ]; do
      case "$1" in
        --remote) remote="$2"; shift 2;;
        *) break;;
      esac
    done
    git fetch "$remote" >\/dev\/null
    add_row 1 fetch "OK" "$remote"
    ;;

  pull)
    remote="origin"; br=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --remote) remote="$2"; shift 2;;
        --branch) br="$2"; shift 2;;
        *) break;;
      esac
    done
    if [ -n "$br" ]; then
      git pull "$remote" "$br" >\/dev\/null
      add_row 1 pull "OK" "$remote/$br"
    else
      git pull >\/dev\/null
      add_row 1 pull "OK" "default"
    fi
    ;;

  push)
    remote="origin"; br=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --remote) remote="$2"; shift 2;;
        --branch) br="$2"; shift 2;;
        *) break;;
      esac
    done
    ensure_askpass
    if [ -n "$br" ]; then
      git push "$remote" "$br" >\/dev\/null
      add_row 1 push "OK" "$remote/$br"
    else
      git push >\/dev\/null
      add_row 1 push "OK" "default"
    fi
    ;;

  stash)
    sub="list"
    while [ $# -gt 0 ]; do
      case "$1" in
        --pop) sub="pop"; shift 1;;
        --apply) sub="apply"; shift 1;;
        --save) sub="save"; msg="$2"; shift 2;;
        --list) sub="list"; shift 1;;
        *) break;;
      esac
    done
    case "$sub" in
      save) git stash push -m "${msg:-wip}" >\/dev\/null; add_row 1 stash "OK" "saved";;
      pop) git stash pop >\/dev\/null || true; add_row 1 stash "OK" "popped";;
      apply) git stash apply >\/dev\/null || true; add_row 1 stash "OK" "applied";;
      list) l="$(git stash list || true)"; add_row 1 stash "OK" "$(printf '%s' "$l" | tr '\n' '; ' | sed 's/; $//')";;
    esac
    ;;

  tag)
    name=""; msg=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --name) name="$2"; shift 2;;
        --message) msg="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$name" ] || { err "--name required"; usage; exit 1; }
    if [ -n "$msg" ]; then
      git tag -a "$name" -m "$msg"
    else
      git tag "$name"
    fi
    add_row 1 tag "OK" "$name"
    ;;

  submodule)
    action="status"; url=""; path=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --add) action="add"; url="$2"; path="$3"; shift 3;;
        --update) action="update"; shift 1;;
        --status) action="status"; shift 1;;
        *) break;;
      esac
    done
    case "$action" in
      add)
        [ -n "$url" ] && [ -n "$path" ] || { err "--add <url> <path> required"; exit 1; }
        git submodule add "$url" "$path" >\/dev\/null
        add_row 1 submodule "OK" "add $path"
        ;;
      update)
        git submodule update --init --recursive >\/dev\/null
        add_row 1 submodule "OK" "update"
        ;;
      status)
        s="$(git submodule status 2>\/dev\/null || true)"
        add_row 1 submodule "OK" "$(printf '%s' "$s" | tr '\n' '; ' | sed 's/; $//')"
        ;;
    esac
    ;;

  remotes)
    out="$(git remote -v 2>/dev/null || true)"
    add_row 1 remotes "OK" "$(printf '%s' "$out" | tr '\n' '; ' | sed 's/; $//')"
    ;;

  add-upstream)
    upstream=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --upstream) upstream="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$upstream" ] || { err "--upstream required"; usage; exit 1; }
    if git remote get-url upstream >/dev/null 2>&1; then
      add_row 1 add-upstream "SKIP" "upstream already exists"
    else
      git remote add upstream "https://github.com/$upstream.git"
      add_row 1 add-upstream "OK" "$upstream"
    fi
    ;;

  branches)
    l="$(git branch --format='%(refname:short)' | tr '\n' ', ' | sed 's/, $//')"
    r="$(git branch -r --format='%(refname:short)' | tr '\n' ', ' | sed 's/, $//')"
    add_row 1 local "OK" "$l"
    add_row 2 remote "OK" "$r"
    ;;

  delete-branches)
    keep="main"
    while [ $# -gt 0 ]; do
      case "$1" in
        --keep) keep="$2"; shift 2;;
        *) break;;
      esac
    done
    ensure_askpass
    # local delete
    i=1
    for b in $(git branch --format='%(refname:short)'); do
      [ "$b" = "$keep" ] && continue
      git branch -D "$b" >/dev/null 2>&1 || true
      add_row "$i" "delete local branch" "OK" "$b"
      i=$((i+1))
    done
    # remote delete (origin only)
    for rb in $(git branch -r --format='%(refname:short)' | grep '^origin/' | sed 's#^origin/##'); do
      [ "$rb" = "$keep" ] && continue
      git push origin --delete "$rb" >/dev/null 2>&1 || true
      add_row "$i" "delete remote branch" "OK" "origin/$rb"
      i=$((i+1))
    done
    ;;

  empty-dir)
    dir=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --dir) dir="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$dir" ] || { err "--dir required"; usage; exit 1; }
    ensure_git_identity
    mkdir -p "$dir"
    # remove tracked files (including dotfiles)
    git rm -r --ignore-unmatch "$dir"/* "$dir"/.[!.]* "$dir"/..?* >/dev/null 2>&1 || true
    mkdir -p "$dir"
    : > "$dir/.gitkeep"
    git add "$dir/.gitkeep"
    add_row 1 empty-dir "OK" "$dir (kept via .gitkeep)"
    ;;

  restore-dir)
    src=""; dst=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --src) src="$2"; shift 2;;
        --dst) dst="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$src" ] && [ -n "$dst" ] || { err "--src and --dst required"; usage; exit 1; }
    ensure_git_identity
    [ -d "$src" ] || { err "src not found: $src"; exit 1; }
    mkdir -p "$dst"
    # delete placeholder if any
    rm -f "$dst/.gitkeep" || true
    # remove tracked files under dst
    git rm -r --ignore-unmatch "$dst"/* "$dst"/.[!.]* "$dst"/..?* >/dev/null 2>&1 || true
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
    # make common scripts executable if present
    find "$dst"/scripts -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
    git add -A "$dst"
    add_row 1 restore-dir "OK" "$src -> $dst"
    ;;

  push-main)
    ensure_askpass
    ensure_git_identity
    git checkout main >/dev/null 2>&1 || true
    git pull --ff-only origin main >/dev/null 2>&1 || true
    git push origin main >/dev/null
    add_row 1 push-main "OK" "pushed to origin/main"
    ;;

  pr)
    upstream=""; head=""; base="main"; title=""; body=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --upstream) upstream="$2"; shift 2;;
        --head) head="$2"; shift 2;;
        --base) base="$2"; shift 2;;
        --title) title="$2"; shift 2;;
        --body) body="$2"; shift 2;;
        *) break;;
      esac
    done
    [ -n "$upstream" ] && [ -n "$head" ] && [ -n "$title" ] || { err "--upstream --head --title required"; usage; exit 1; }
    need_env GITHUB_TOKEN
    url="$(python3 -c 'import os,json,urllib.request,urllib.error; tok=os.environ["GITHUB_TOKEN"]; upstream=os.environ["UP"]; owner,repo=upstream.split("/",1); payload={"title":os.environ["TITLE"],"head":os.environ["HEAD"],"base":os.environ.get("BASE","main"),"body":os.environ.get("BODY","")}; data=json.dumps(payload).encode("utf-8"); api="https://api.github.com"; req=urllib.request.Request(f"{api}/repos/{owner}/{repo}/pulls",data=data,method="POST"); req.add_header("Authorization","Bearer "+tok); req.add_header("Accept","application/vnd.github+json"); req.add_header("User-Agent","minis"); req.add_header("Content-Type","application/json");
try:
 resp=json.load(urllib.request.urlopen(req,timeout=30)); print(resp.get("html_url",""))
except urllib.error.HTTPError as e:
 err=e.read().decode("utf-8","ignore"); print("HTTP %s"%e.code); print(err[:300])' )" || true
    if printf '%s' "$url" | grep -q '^https://'; then
      add_row 1 pr "OK" "$url"
    else
      add_row 1 pr "FAIL" "$(printf '%s' "$url" | tr '\n' ' ' | sed 's/  */ /g')"
      print_summary
      exit 1
    fi
    ;;

  *)
    usage
    exit 1
    ;;
esac

print_summary
