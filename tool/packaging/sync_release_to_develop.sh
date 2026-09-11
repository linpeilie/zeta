#!/usr/bin/env bash
# Run after publication and tag verification, in the release checkout.
set -euo pipefail

tag="${1:?Release tag is required}"
release_commit="${2:?Release commit is required}"
git check-ref-format "refs/tags/${tag}"
[[ "${release_commit}" =~ ^[0-9a-f]{40}$ ]] || exit 1
git diff --quiet
git diff --cached --quiet

fail() {
  echo "::error::$*" >&2
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '\nRelease is published, but main → develop synchronization failed: %s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
}

git fetch --no-tags origin "refs/tags/${tag}"
[[ "$(git rev-parse 'FETCH_HEAD^{commit}')" == "$release_commit" ]] || fail 'Release tag does not match the release commit.'

for attempt in 1 2 3; do
  git fetch --no-tags origin \
    refs/heads/main:refs/remotes/origin/main \
    refs/heads/develop:refs/remotes/origin/develop
  main_commit="$(git rev-parse refs/remotes/origin/main)"
  develop_commit="$(git rev-parse refs/remotes/origin/develop)"
  git merge-base --is-ancestor "$release_commit" "$main_commit" || fail 'Release commit is not an ancestor of main.'

  if git merge-base --is-ancestor "$main_commit" "$develop_commit"; then
    result="$develop_commit"
    break
  fi

  git checkout --detach "$develop_commit"
  if ! git -c user.name='github-actions[bot]' \
    -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    -c commit.gpgsign=false merge --ff --no-edit \
    -m "chore: merge main into develop after ${tag}" "$main_commit"; then
    git merge --abort || true
    fail 'Merge failed. Resolve main/develop conflicts before rerunning the release job.'
  fi

  if git push origin HEAD:refs/heads/develop; then
    result="$(git rev-parse HEAD)"
    break
  fi

  git fetch --no-tags origin refs/heads/develop:refs/remotes/origin/develop
  [[ "$(git rev-parse refs/remotes/origin/develop)" != "$develop_commit" ]] || \
    fail 'Push rejected. Check workflow write permissions and develop branch protection.'
  echo "develop advanced during push; retrying (${attempt}/3)."
done

[[ -n "${result:-}" ]] || fail 'develop kept advancing; rerun the release job to retry.'
echo "Synchronized main ${main_commit} into develop ${result}."
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '\nMerged main `%s` into develop `%s` after tag `%s` (already synchronized on reruns).\n' \
    "$main_commit" "$result" "$tag" >> "$GITHUB_STEP_SUMMARY"
fi
