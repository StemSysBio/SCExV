package stefans_libs::GeneGroups::R_table;

#  Copyright (C) 2014-05-15 Stefan Lang

#  This program is free software; you can redistribute it
#  and/or modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation;
#  either version 3 of the License, or (at your option) any later version.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

#  You should have received a copy of the GNU General Public License
#  along with this program; if not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use POSIX;
use stefans_libs::flexible_data_structures::data_table;
use base 'data_table';

use GD;
use stefans_libs::plot::color;
use stefans_libs::plot::Font;
use stefans_libs::plot::axis;

=head1 General description

This lib reads the PCR csv files, calculated some tests and exports the dfiles as data tables.

=cut

sub new {

	my ( $class, $hash ) = @_;

	my ($self);
	unless ( ref($hash) eq "HASH" ) {
		$hash = { 'debug' => $hash };
	}
	$self = {
		'debug'           => $hash->{'debug'},
		'arraySorter'     => arraySorter->new(),
		'sample_postfix'  => '',
		'header_position' => {},
		'default_value'   => [],
		'header'          => [],
		'data'            => [],
		'index'           => {},
		'xa'              => {},
		'ya'              => {},
		'last_warning'    => '',
		'subsets'         => {}
	};
	bless $self, "stefans_libs::GeneGroups::R_table";

	$self->string_separator();          ##init
	$self->line_separator('"?\s"?');    ##init

	$self->init_rows( $hash->{'nrow'} )     if ( defined $hash->{'nrow'} );
	$self->read_file( $hash->{'filename'} ) if ( defined $hash->{'filename'} );
	return $self;
}

sub __process_line_No_Header {
	my ( $self, $line ) = @_;
	chomp($line);

	$line =~ s/^"\s+/"/;
	$line =~ s/\s+"/"/;
	$line =~ s/""/" "/g;
	$line =~ s/^"//;
	$line =~ s/"$//;
	$line =~ s/^Samples//;
	my $sep = $self->line_separator();
	$self->Add_2_Header( [ 'Samples', split( /$sep/, $line ) ] );
	return 1;
}

sub __check_line {
	my ( $self, $line ) = @_;
	return $self->{'use'} if ( defined $self->{'use'} );
	my @tmp = split( /(")/, $line );
	$self->{'use'}   = [];
	$self->{'split'} = [];
	my $next;
	if ( $tmp[0] eq "" && $tmp[1] eq '"' ) {
		push( @{ $self->{'use'} }, 0, 0, 'use' );
		$next = 3;
	}
	else {
		push( @{ $self->{'use'} }, 'split' );
		$next = 1;
	}
#	print "'" . join( "','", @tmp ) . "'\n";
	my $max = @tmp;
	while ( $next < @tmp ) {
		if ( $next + 2 < $max ) {
			if ( join( ";", @tmp[ $next .. $next + 2 ] ) eq '"; ;"'
				&& $tmp[ $next + 4 ] eq '"' )
			{
				push( @{ $self->{'use'} }, 0, 0, 0, 'use' );
				$next += 4;
				next;
			}
			elsif ($tmp[$next] eq '"'
				&& $tmp[ $next + 2 ] eq '"'
				&& $next + 3 == $max )
			{
				push( @{ $self->{'use'} }, 0, 'use', 0 );
				$next += 3;
				next;
			}
			elsif ( $tmp[$next] eq '"' && $tmp[ $next + 2 ] eq '"' ) {
				push( @{ $self->{'use'} }, 0, 'split' );
				$next += 2;
				next;
			}
		}
		elsif ( $tmp[$next] eq '"' ) {
			push( @{ $self->{'use'} }, 0, 'split' );
			$next += 2;
		}
		else {
			push( @{ $self->{'use'} }, 'split' );
			$next++;
		}
	}
	return $self->{'use'};
	## all quoted entries have to be accomplished by two " and a separator between two "

}

sub __split_line {
	my ( $self, $line ) = @_;
	chomp($line);
	unless ( defined $self->{'use'} ) {
		$self->__check_line($line);
	}
	my ( @tmp, @line, @split );
	@tmp = split( /(")/, $line );
	for ( my $i = 0 ; $i < @tmp ; $i++ ) {
		if ( @{ $self->{'use'} }[$i] eq "use" ) {
			push( @line, $tmp[$i] );
		}
		elsif ( @{ $self->{'use'} }[$i] eq "split" ) {
			@split = split( " ", $tmp[$i] );
			pop(@split)   unless ( defined $split[ @split - 1 ] );
			shift(@split) unless ( defined $split[0] );
			push( @line, @split );
		}
		## nothing else to do?
	}
	return \@line;
}

sub axies {
	my ( $self, $geneX, $geneY ) = @_;
	unless ( defined $self->{'xa'}->{$geneX} ) {
		$self->{'xa'}->{$geneX} = axis->new( 'x', 0, 800, '', 'min' );
		map {
			$self->{'xa'}->{$geneX}->Max($_);
			$self->{'xa'}->{$geneX}->Min($_)
		} @{ $self->GetAsArray($geneX) };
		$self->{'xa'}->{$geneX}->max_value( $self->{'xa'}->{$geneX}->Max() );
		$self->{'xa'}->{$geneX}->min_value( $self->{'xa'}->{$geneX}->Min() );
		$self->{'xa'}->{$geneX}->resolveValue( $self->{'xa'}->{$geneX}->Min() );
	}
	unless ( defined $self->{'ya'}->{$geneY} ) {
		$self->{'ya'}->{$geneY} = axis->new( 'y', 0, 800, '', 'min' );
		map {
			$self->{'ya'}->{$geneY}->Max($_);
			$self->{'ya'}->{$geneY}->Min($_)
		} @{ $self->GetAsArray($geneY) };
		$self->{'ya'}->{$geneY}->max_value( $self->{'ya'}->{$geneY}->Max() );
		$self->{'ya'}->{$geneY}->min_value( $self->{'ya'}->{$geneY}->Min() );
		$self->{'ya'}->{$geneY}->resolveValue( $self->{'ya'}->{$geneY}->Min() );
	}
	return ( $self->{'xa'}->{$geneX}, $self->{'ya'}->{$geneY} );
}

sub plotXY_fixed_Colors {
	my ( $self, $filename, $geneX, $geneY, $colors ) = @_;
	Carp::confess(
		"I need an R_table object contining the color information at start up")
	  unless ( ref($colors) eq ref($self) );
	## the two tables have the same order of samples.
	$geneX ||= '';
	$geneY ||= '';
	unless ( defined $self->Header_Position($geneX) ) {
		$geneX = @{ $self->{'header'} }[1];
	}
	unless ( defined $self->Header_Position($geneY) ) {
		$geneY = @{ $self->{'header'} }[2];
	}
	my $im = new GD::Image( 800, 800 );
	my ( $xaxis, $yaxis ) = $self->axies( $geneX, $geneY );
	my ( $xpos, $ypos, @colors, $id );
	($xpos) = $self->Header_Position($geneX);
	($ypos) = $self->Header_Position($geneY);
	$id = 0;
	my $order = $colors->createIndex('colorname');
	## create the color information using the R rainbow!
	my $map = root->filemap($filename);
	my $color =
	  $self->rainbow_colors( $map->{'path'}, $im, scalar( keys %$order ) );
	  
	while ( my ( $col, $lines ) = each %$order ) {
		my $this_color = $color->{$col};
		foreach my $i (@$lines) {

 #print "on line $i: xpos $xpos value ".@{ @{ $self->{'data'} }[$i] }[$xpos]." and ypos $ypos value ".@{ @{ $self->{'data'} }[$i] }[$ypos] ." together with the color $this_color\n";
			$im->filledRectangle(
				$xaxis->resolveValue( @{ @{ $self->{'data'} }[$i] }[$xpos] ) -
				  2,
				$yaxis->resolveValue( @{ @{ $self->{'data'} }[$i] }[$ypos] ) -
				  2,
				$xaxis->resolveValue( @{ @{ $self->{'data'} }[$i] }[$xpos] ) +
				  2,
				$yaxis->resolveValue( @{ @{ $self->{'data'} }[$i] }[$ypos] ) +
				  2,
				$this_color
			);
		}
	}
	$xaxis->plot(
		$im,
		$yaxis->resolveValue(
			( $yaxis->min_value() + $yaxis->max_value() ) / 2
		),
		$color->{'black'}
	);
	$yaxis->plot(
		$im,
		$xaxis->resolveValue(
			( $xaxis->min_value() + $xaxis->max_value() ) / 2
		),
		$color->{'black'}
	);
	$self->writePicture( $im, $filename );
	open( OUT, ">" . $filename . ".info" );

	print OUT "X\t" . $xaxis->min_value() . "\t" . $xaxis->max_value() . "\n";
	print OUT "Y\t" . $yaxis->min_value() . "\t" . $yaxis->max_value() . "\n";
	close(OUT);

#Carp::confess ( "I used the colors ".join(", ", @colors ) . "\$GeneGroups = ".root->print_perl_var_def( {map { $_ => $GeneGroups->{$_} } keys %$GeneGroups } ).";\n".$GeneGroups->AsString()."\n"  );
	return ( $xaxis, $yaxis );
}

=head2 rainbow_colors ($im, $n)

This function uses R to create a rainbow color set.
It returns a plot color object that is initialized with this color set.

=cut

sub rainbow_colors {
	my ( $self, $path, $im, $n ) = @_;
	Carp::confess("Path problems? $path\n") unless ( -d $path );
	return color->new( $im, 'white', "$path/rainbow_$n.cols" )
	  if ( -f "$path/rainbow_$n.cols" );
	open( OUT, ">$path/rainbow_$n.R" ) or Carp::confess($!);
	print OUT "cols <- rainbow($n)\n"
	  . "write.table (cbind( names = cols, t(col2rgb( cols ) )), file='$path/rainbow_$n.cols', sep='\\t',  row.names=F,quote=F )\n";
	close(OUT);
	system("R CMD BATCH $path/rainbow_$n.R");
	unlink("$path/rainbow_$n.R");
	unlink("$path/rainbow_$n.Rout");
	return color->new( $im, 'white', "$path/rainbow_$n.cols" );
}

sub plotXY {
	my ( $self, $filename, $geneX, $geneY, $GeneGroups ) = @_;
	my $im = new GD::Image( 800, 800 );
	my ( $xaxis, $yaxis ) = $self->axies( $geneX, $geneY );
	my ( $xpos, $ypos, @colors, $id );
	($xpos) = $self->Header_Position($geneX);
	($ypos) = $self->Header_Position($geneY);
	$id = 0;
	## Small R script to determine the colours I want to plot in....
	my $cols = $GeneGroups->nGroup() + 1;
	$cols++ if ( $cols == 0 );
	my $map = root->filemap($filename);
	my $color = $self->rainbow_colors( $map->{'path'}, $im, $cols );

	foreach my $group_table ( $GeneGroups->splice_expression_table($self) ) {
		$colors[$id] = $color->getNextColor() unless ( defined $colors[$id] );
		if ( defined $group_table->{'group_area'} )
		{    ## the not grouped do not have this value
			$im->rectangle(
				$xaxis->resolveValue( $group_table->{'group_area'}->{'x1'} ),
				$yaxis->resolveValue( $group_table->{'group_area'}->{'y1'} ),
				$xaxis->resolveValue( $group_table->{'group_area'}->{'x2'} ),
				$yaxis->resolveValue( $group_table->{'group_area'}->{'y2'} ),
				$colors[$id]
			);
		}
		for ( my $i = 0 ; $i < $group_table->Lines() ; $i++ ) {
			$im->filledRectangle(
				$xaxis->resolveValue(
					@{ @{ $group_table->{'data'} }[$i] }[$xpos]
				  ) - 2,
				$yaxis->resolveValue(
					@{ @{ $group_table->{'data'} }[$i] }[$ypos]
				  ) - 2,
				$xaxis->resolveValue(
					@{ @{ $group_table->{'data'} }[$i] }[$xpos]
				  ) + 2,
				$yaxis->resolveValue(
					@{ @{ $group_table->{'data'} }[$i] }[$ypos]
				  ) + 2,
				$colors[$id]
			);
		}
		$id++;
	}

	$xaxis->plot(
		$im,
		$yaxis->resolveValue(
			( $yaxis->min_value() + $yaxis->max_value() ) / 2
		),
		$color->{'black'}
	);
	$yaxis->plot(
		$im,
		$xaxis->resolveValue(
			( $xaxis->min_value() + $xaxis->max_value() ) / 2
		),
		$color->{'black'}
	);
	$self->writePicture( $im, $filename );
	open( OUT, ">" . $filename . ".info" );
	print OUT "X\t" . $xaxis->min_value() . "\t" . $xaxis->max_value() . "\n";
	print OUT "Y\t" . $yaxis->min_value() . "\t" . $yaxis->max_value() . "\n";
	close(OUT);

	return ( $xaxis, $yaxis );
}

sub writePicture {
	my ( $self, $im, $pictureFileName ) = @_;

	# Das Bild speichern
	my ( @temp, $path );
	@temp = split( "/", $pictureFileName );
	pop @temp;
	$path = join( "/", @temp );

	#print "We print to path $path\n";
	Carp::confess(
"You gave me a shitty filename containing line ends - why??\n'$pictureFileName'\n"
	) if ( $pictureFileName =~ m/\n/ );
	mkdir($path) unless ( -d $path );
	$pictureFileName = "$pictureFileName.png"
	  unless ( $pictureFileName =~ m/\.png$/ );
	open( PICTURE, ">$pictureFileName" )
	  or die "Cannot open file $pictureFileName for writing\n$!\n";

	binmode PICTURE;

	print PICTURE $im->png;
	close PICTURE;
#	print "Bild als $pictureFileName gespeichert\n";
	return $pictureFileName;
}

1;
