#!/bin/bash

#source ~/perl5/perlbrew/etc/bashrc

echo Beginning Benchmark

for I in {10..100}
do
	let "J = I * I"
	echo -n Testing $J entries... 
	let "J += 2"
	head -n $J ./data/snp-TEST20110209-final.vcf > temp.out
	/usr/bin/time perl ../data/RegulomeDB/script/RegDB_query.pl multi temp.out ../data/REgulomeDB  > /dev/null
done

