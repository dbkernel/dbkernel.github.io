#!/bin/bash
cd websource
hugo
mv public/* ../
rm -rf public
cd ..

