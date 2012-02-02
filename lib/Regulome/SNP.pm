package Regulome::SNP;
use Mojo::Base 'Mojolicious::Controller';

sub id {
	my $self = shift;

	my $rsid  = $self->param('id');
	my $coord = $self->app->snpdb->getSNPbyRsid($rsid);
	$self->to('/not_found') unless $coord;

	$self->snp_table($coord,$rsid);
}

sub rsid_from_coord {
	my $self = shift;
	my $chr = $self->param('chr');
	$chr =~ tr/[xy]/[XY]/;
	$chr = "chr$chr" unless $chr =~ /^chr/;
	my $nt  = $self->param('nt');
	my $rsid = $self->app->snpdb->getRsid([$chr, $nt]) || 'n/a';

	return ($chr, $nt, $rsid);
}
sub coord {
	my $self = shift;

	my ($chr,$nt,$rsid)= $self->rsid_from_coord;
	$self->snp_table([$chr, $nt], $rsid);
}

sub ajax_rsid {
	my $self = shift;
	my ($chr,$nt,$rsid)= $self->rsid_from_coord;

	$self->render(json=>{ rsid => $rsid });	
}
=pod
Protein binding
=============
Include the following data rows:
	TF_(cell type)_(TF)[_(Condition)]
	MANUAL_(annotation) that matches 'binding_site'. Can provide "MANUAL_(cell type)_(TF)_(binding_site)_method"

Columns:
	* Method
		TF = ChIP-seq
		Manual = can be parsed 'method' from name
	* Location
	* Bound protein
		for both, parsed (TF) from name.  Also can include POL2 and histone deactetylases, not exclusively TF
	* Cell type
		for both, parsed (cell type) from name.
	* Additional info
		for TF, parse (condition)
	* Reference
		NCP000 = ENCODE if no paper
		MANUAL = PMID# (no need to have PMID preface)

Conserved motifs
==============
Include the following data rows:
	FP_(cell type)_(TF)
	PWM_(TF)

Columns:
	* Method
		FP = Footprinting
		PWM = What software or method was used?
	* Location
	* Motif
		for both, parsed from (TF)
		for PWM, add LOGO?
	* Cell type
		for FP, parsed (cell type)
	* Reference
		FP: PMID
		PWM: Is there a reference?

Single nucleotides
===============
Include the following data rows:
	VAL_(cell type)_(TF)_(additional info)
	eQTL_(cell type)_(gene target)
	MANUAL_(annotation) that matches 'SNV'

Columns:	
	* Method
		VAL = Validated SNP
		eQTL = eQTL
		MANUAL = leave blank
	* Location
	* Affected gene
		for VAL, parse (TF)
		for eQTL, parse (gene target)
	* Cell type
		parsed from name
	* Additional Info
		for VAL, parse (additional info)
	* Reference
		for all, PMID, no need to have PMID preface


Chromatin conformation
===================
Include the following data rows:
	DNase_(cell type)[_(Condition)]

Columns:	
	* Method
		DNase = DNase hyersensitivity
	* Location
	* Affected gene
		for VAL, parse (TF)
		for eQTL, parse (gene target)
	* Cell type
		parsed from name
	* Additional info
		parse (condition)
	* Reference
		PMID?


Other
====
Include the following data rows:
	Rest of MANUAL annotations.  Can provide "MANUAL_(cell type)_(annotation)_method"

Columns:	
	* Method
		parse method
	* Location
	* Cell type
		parsed from name
	* Annotation
		parse (annotation)
	* Reference
		PMID, no need to have PMID preface
=cut
sub snp_table {

	my $self  = shift;
	my $coord = shift;
	my ($chr, $nt) = ($coord->[0], $coord->[1]);
	my $rsid = shift;

	my $res = $self->app->rdb->process($coord);
	
	my $sections = [
		 { title => 'Protein Binding',
		   table_id    => 'protein_binding',
		   methods => { TF => 1, MANUALTF => 1},
		   data_table => [],
		 },    
		 { title => 'Conserved motifs',
		   table_id    => 'motifs',
		   methods => { FP => 1, PWM => 1, MANUALFP => 1, MANUALPWM => 1},
		   data_table => [],
		 },    
		 { title => 'Single nucleotides',
		   table_id    => 'snt',
		   methods => { VAL => 1, eQTL => 1, MANUALSNV => 1},
		   data_table => [],
		 },    
		 { title => 'Chromatin conformation',
		   table_id    => 'chromatin',
		   methods => { DNase => 1},
		   data_table => [],
		 },    
		 { title => 'Other',
		   table_id    => 'other',
		   methods => { Other => 1},
		   data_table => [],
		 },    
	];
	
	my $score = $self->app->rdb->full_score($res,$chr);
	
	for my $sect (@$sections) {
		my @data = ();
		my @dtColumns = ();

		for my $method (keys %{$sect->{methods}}) {	
			my $mapping = $self->app->rdb->data_mapping->{$method};
			
			my @columns = map keys %$_, (@{ $mapping->{columns} });
			
		    @dtColumns = map ({ sTitle => $_, sClass => 'aligncenter'}, @columns) unless @dtColumns;
		    ## all methods in section must have the same columns!
			for my $hit (@{ $score->{$method}->{hits} }) {
				push @data, [ map $hit->{$_}, (@columns) ];
			}
		}
		if (@data) {
			$sect->{data_table} = Mojo::JSON->new->encode(
													{
														aaData => \@data,
														aoColumns => \@dtColumns,
														bJQueryUI => 'true',
														bFilter   => 0,
														bSort     => 0,
														bInfo     => 0,
														bLengthChange => 0,
														bPaginate => 0,
														iDisplayLength => scalar @data,
													}	
														);
		} else {
			$sect = {}; # empty the hash
		}
	}

	$self->stash(
				  {
					snpid => $rsid,
					score => $score,
					chr   => $chr,
					pos   => $nt,
					sections => $sections,
				  }
	);
	$self->render(template => 'SNP/snp');
}
1;
