#!/bin/bash

SUFFIX=${1}_${2}
TGT=run.${SUFFIX}

rm -rf ${TGT}
mkdir ${TGT}

ln robot.pddl ${TGT}
ln ff ${TGT}
ln run-ff.sh ${TGT}
../domainTranslate 1 robot.hpddl > ${TGT}/robot.hpddl

cd ${TGT}
for ((i=1;i<=${3};i+=1)); do
  ../../genRobot1 ${1} ${2} prob${i}
done
