#!/bin/bash

# Run this from project root directory
go mod vendor

# Download only the dependencies that are not yet available in Debian
MODULES=(
  "github.com/kovidgoyal/dbus"
  "github.com/kovidgoyal/imaging"
  "github.com/kovidgoyal/go-parallel"
  "github.com/kovidgoyal/go-shm"
  "github.com/hako/durafmt"
)

# Loop through each module
for MODULE in "${MODULES[@]}"
do
  rm -rf debian/vendor/"$MODULE"
  mkdir -p debian/vendor/"$MODULE"
  cp --archive --update --verbose vendor/"$MODULE"/* debian/vendor/"$MODULE"/
  rm -rf vendor/"$MODULE"
done
