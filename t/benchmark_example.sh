#!/bin/bash

#source /raid1/aboyle/.bashrc

echo Beginning Benchmark

for I in {1..100}
do
	let "J = I * I"
	echo -n Testing $J entries... 
	let "J += 2"
	head -n $J snp-TEST20110209-final.vcf > temp.out
	/usr/bin/time -f %E perl RegDB_query.pl multi temp.out RDB | perl apply_score.pl > /dev/null
done

