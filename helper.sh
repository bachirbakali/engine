#!/usr/bin/env bash

#set -x

awk=awk
sed=sed
grep=grep
if [ "$(uname)" == "Darwin" ] ; then
  grep='ggrep'
  awk='gawk'
  sed='gsed'
fi

function variable_not_found() {
  echo "Required variable not found: $1"
  exit 1
}

function release() {
  test -z $GITLAB_PROJECT_ID && variable_not_found "GITLAB_PROJECT_ID"
  test -z $GITLAB_TOKEN && variable_not_found "GITLAB_TOKEN"
  test -z $GITLAB_PERSONAL_TOKEN && variable_not_found "GITLAB_PERSONAL_TOKEN"
  test -z $GITHUB_BRANCH && variable_not_found "GITHUB_BRANCH"
  GITLAB_REF="main"

  echo "Requesting Gitlab pipeline"
  pipeline_id=$(curl -s -X POST -F "token=$GITLAB_TOKEN" -F "ref=$GITLAB_REF" -F "variables[GITHUB_COMMIT_ID]=$GITHUB_COMMIT_ID" -F "variables[GITHUB_ENGINE_BRANCH_NAME]=$GITHUB_BRANCH" -F "variables[TESTS_TYPE]=$TESTS_TYPE" https://gitlab.com/api/v4/projects/$GITLAB_PROJECT_ID/trigger/pipeline | jq --raw-output '.id')
  if [ $(echo $pipeline_id | egrep -c '^[0-9]+$') -eq 0 ] ; then
    echo "Pipeline ID is not correct, we expected a number and got: $pipeline_id"
    exit 1
  fi
  echo "Pipeline ID: $pipeline_id"
}

urlencode() {
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    
    LC_COLLATE=$old_lc_collate
}

function run_tests() {
  TESTS_TYPE=$1
  test -z $GITLAB_PROJECT_ID && variable_not_found "GITLAB_PROJECT_ID"
  test -z $GITLAB_TOKEN && variable_not_found "GITLAB_TOKEN"
  test -z $GITLAB_PERSONAL_TOKEN && variable_not_found "GITLAB_PERSONAL_TOKEN"
  test -z $GITHUB_BRANCH && variable_not_found "GITHUB_BRANCH"

  GITLAB_REF="dev"
  encoded_branch=$(urlencode $GITLAB_REF)
  if [ $(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "https://gitlab.com/api/v4/projects/$GITLAB_PROJECT_ID/repository/branches/$encoded_branch" | grep -c '404 Branch Not Found') -ne 0 ] ; then
    GITLAB_REF=$GITHUB_BRANCH
  fi

  echo "Requesting Gitlab pipeline"
  pipeline_id=$(curl -s -X POST -F "token=$GITLAB_TOKEN" -F "ref=$GITLAB_REF" -F "variables[GITHUB_COMMIT_ID]=$GITHUB_COMMIT_ID" -F "variables[GITHUB_ENGINE_BRANCH_NAME]=$GITHUB_BRANCH" -F "variables[TESTS_TYPE]=$TESTS_TYPE" https://gitlab.com/api/v4/projects/$GITLAB_PROJECT_ID/trigger/pipeline | jq --raw-output '.id')
  if [ $(echo $pipeline_id | egrep -c '^[0-9]+$') -eq 0 ] ; then
    echo "Pipeline ID is not correct, we expected a number and got: $pipeline_id"
    exit 1
  fi
  sleep 2

  pipeline_status=''
  counter=0
  max_unexpected_status=5
  while [ $counter -le $max_unexpected_status ] ; do
    current_status=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" https://gitlab.com/api/v4/projects/$GITLAB_PROJECT_ID/pipelines/$pipeline_id | jq --raw-output '.detailed_status.text')
    echo "Current pipeline id $pipeline_id status: $current_status"
    case $current_status in
      "created")
        ((counter=$counter+1))
      ;;
      "waiting_for_resource")
        ((counter=$counter+1))
      ;;
      "preparing")
        ((counter=$counter+1))
      ;;
      "pending")
        ((counter=$counter+1))
      ;;
      "running")
        counter=0
      ;;
      "passed")
        echo "Results: Congrats, functional tests succeeded!!!"
        exit 0
      ;;
      "success")
        echo "Results: Congrats, functional tests succeeded!!!"
        exit 0
      ;;
      "failed")
        echo "Results: Functional $TESTS_TYPE tests failed"
        exit 1
      ;;
      "canceled")
        exit 1
      ;;
      "skipped")
        exit 1
      ;;
      "manual")
        exit 1
      ;;
      "scheduled")
        ((counter=$counter+1))
      ;;
      "null")
        ((counter=$counter+1))
      ;;
    esac

    sleep 10
  done

  echo "Results: functional tests failed due to a too high number ($max_unexpected_status) of unexpected status."
  exit 1
}

#set -u

case $1 in
fast_tests)
  run_tests fast
  ;;
full_tests)
  run_tests full
  ;;
release)
  release
  ;;
*)
  echo "Usage:"
  echo "$0 fast_tests: run fast tests"
  echo "$0 full_tests: run full tests (with cloud providers check)"
  ;;
esac
