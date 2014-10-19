#!/bin/sh
export PERL5LIB=$( cd "$( dirname "$0" )" && pwd )/../lib
perl -MFlowTiMeter::Shell -${DEBUG1:+d}exec shell "$@" 
