#!/bin/bash
HUGO_VERSION="0.146.0"
curl -L "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.deb" -o hugo_extended_${HUGO_VERSION}_linux-amd64.deb
sudo apt install hugo_extended_${HUGO_VERSION}_linux-amd64.deb
