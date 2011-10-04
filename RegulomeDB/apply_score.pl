#!/usr/bin/perl

while($line = <>) {
	chomp($line);
	@temp = split("\t", $line);
	$temp[4] =~ s/\s+//g;

	if($temp[4] eq "0") {
			print join("\t", @temp) . "\t5\n";
	} else {
	$vals = $temp[4];
	#scoring scheme
	# 1 -> known to cause heteroallelic binidng
	# 1.1 -> ChIP_seq + motif + footprints + DNase + eQTL
	# 1.2 -> ChIP_seq + motif + footprint + DNase + eQTL
	# 1.3 -> ChIP_seq + motif + footprint + DNase
	# 1.4 -> ChIP_seq + motif + DNase
	# 1.5 -> ChIP_seq + non-matched motif + DNase
	# 2 -> ChIP_seq + DNase
	# 3 -> ChIP_seq or DNase
	# 4 -> other
	
	$PWM = 0;
	%PWMs = ();
	$DNase = 0;
	$footprint = 0;
	%footprints = ();
	$eqtl = 0;
	$manual = 0;
	$chip = 0;
	%chips = ();
	
	@items = split('\+', $vals);
	foreach $item (@items) {
		if($item =~ /PWM/) {
			$PWM = 1;
			$item =~ s/PWM_//;
			$PWMs{$item} = 1;
		} elsif($item =~ /DNase/) {
			$DNase = 1;
		} elsif($item =~ /FP/) {
			$footprint = 1;
			$item =~ s/FP_.*_//;
			$footprints{$item} = 1;
		} elsif($item =~ /eQTL/) {
			$eqtl = 1;
		} elsif($item =~ /MANUAL/) {
			$manual = 1;
		} elsif($item =~ /^TF/) {
			$chip = 1;
			$item =~ s/TF_.*?_//;
			$item =~ s/_.*//;
			$chips{$item} = 1;
		}
	}
	
	$pwmmatched = 0;
	$fpmatched = 0;
	foreach $key (keys %chips) {
		if(exists $PWMs{$key}) {
			$pwmmatched = 1;
		}
		if(exists $footprints{$key}) {
			$fpmatched = 1;
		}
	}
	
	$score = 4;
	if($chip == 1 || $DNase == 1) {
		$score = 3;
	} 

	if($chip == 1 && $DNase == 1) {
		$score = 2;
	} 

	if($chip == 1 && $DNase == 1 && $PWM == 1) {
		$score = 1.5;
	} 

	if($chip == 1 && $DNase == 1 && $PWM == 1 && $pwmmatched == 1) {
		$score = 1.4;
	} 

	if($chip == 1 && $DNase == 1 && $PWM == 1 && $pwmmatched == 1 && $footprint == 1) {
		$score = 1.3;
	} 

	if($chip == 1 && $DNase == 1 && $PWM == 1 && $pwmmatched == 1 && $footprint == 1 && $eqtl == 1) {
		$score = 1.2;
	} 

	if($chip == 1 && $DNase == 1 && $PWM == 1 && $pwmmatched == 1 && $footprint == 1 && $eqtl == 1 && $fpmatched == 1) {
		$score = 1.1;
	} 

	print join("\t", @temp) . "\t" . $score . "\n";
	}	
}
