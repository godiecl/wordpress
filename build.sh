#!/usr/bin/env bash
time (docker buildx build --progress=plain --tag 4h/wordpress:latest --file Dockerfile .)
