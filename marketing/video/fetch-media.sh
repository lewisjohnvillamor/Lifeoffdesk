#!/bin/sh
# Downloads the licensed stock media (Mixkit Free License: commercial use and social posts allowed,
# no attribution required; no standalone redistribution, so the files are not committed).
set -e
cd "$(dirname "$0")/public"
mkdir -p music stock
curl -sSL https://assets.mixkit.co/music/963/963.mp3 -o music/just-keep-walking.mp3   # "Just Keep Walking", Michael Ramir C.
curl -sSL https://assets.mixkit.co/videos/42653/42653-1080.mp4 -o /tmp/laptop-src.mp4    # Woman finishes working on her computer
curl -sSL https://assets.mixkit.co/videos/4871/4871-1080.mp4 -o /tmp/park-src.mp4        # Girl walking through a park on a sunny day
ffmpeg -v error -y -ss 3.5 -t 4.5 -i /tmp/laptop-src.mp4 -an -c:v libx264 -crf 20 stock/laptop.mp4
ffmpeg -v error -y -ss 2 -t 5 -i /tmp/park-src.mp4 -an -c:v libx264 -crf 20 stock/park.mp4
