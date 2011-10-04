#!/bin/bash

#source ~/perl5/perlbrew/etc/bashrc

echo Beginning Benchmark

for I in {1..100}
do
	let "J = I * I"
	echo -n Testing $J entries... 
	let "J += 2"
	head -n $J ../RegulomeDB/data/snp-TEST20110209-final.vcf > temp.out
	/usr/bin/time -f %E perl ../RegulomeDB/RegDB_query.pl multi temp.out ../RDB | perl ../RegulomeDB/apply_score.pl > /dev/null
done

