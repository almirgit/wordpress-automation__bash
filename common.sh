#!/usr/bin/env bash

# Unlike functions in “real” programming languages, Bash functions don’t allow you to return a value when called. 

success () {
  echo "--> Success: $1"
}

failure () {
  >&2 echo "--> ERROR: $1"
}

function check_defined () {
  varname=$1
  if [ -z "${!varname}" ]; then
    failure "Variable '$varname' is not defined or empty"
    return 0
  fi
  #echo $varname is NOT empty: ${!varname}
  return 1
}


