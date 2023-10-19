#!/bin/bash

i=1
while true
do
    DATE=`date "+%Y-%m-%d %H:%M:%S"`
    echo "sleep 0" >> test_apisix_mirror.sh
    git add -u
    git commit -m "auto $i $DATE"
    git push
    echo $DATE
    i=$[$i+1]
    sleep 450
done

