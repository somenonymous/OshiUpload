#!/bin/sh

RUNSCRIPTNAME='oshi_run.pl'
BASEDIR=$(dirname "$0")

cd $BASEDIR/../app

ps aux | grep -v grep | grep $RUNSCRIPTNAME || ./$RUNSCRIPTNAME
