
require 5.006;

use strict;
use warnings;

use Carp;
use Carp::Assert;
use FileHandle;
use Getopt::Long;
use GD;
# use Math::Trig qw( pi deg2rad );
use POSIX qw(ceil floor);

our $VERSION = '0.20';

my @InFiles           = ();
my $OutFile          = "output.png";

my ($Width, $Height) = (400, 400);

my $PointsOnly       = 0;
my $MarkInterval     = 60;

my $UsageFlag        = 0;

GetOptions(
  'help|h!'            => \$UsageFlag,
  'infile|i=s'         => \@InFiles,
  'outfile|o=s'        => \$OutFile,
  'points-only|p!'     => \$PointsOnly,
  'grid-interval|g=i', => \$MarkInterval,
  'width|w=i',         => \$Width,
  'height|h=i',        => \$Height,
);

if ($UsageFlag) {
print << "END_USAGE";
plottrail --infile=input1.txt [--infile=input2.txt...--infile=inputx.txt]
  [--outfile=outfile.png] [--points-only] [--grid-interval=i]
  [--width=w] [--height=h]
END_USAGE
  exit (1);
}

unless (@InFiles) {
  croak "No input file specified\n";
}

if (($Width<50) || ($Height<50)) {
  croak "Width or Height is too small (<50)\n";
}

if ($MarkInterval<0) {
  croak "Grid Interval must be greater than or equal to 0\n";
}


my @Trail = ();

my ($Left, $Top, $Right, $Bottom) = (90, 90, -90, -90);

foreach my $file (@InFiles) {
  read_file($file);
}

croak "No data", unless (@Trail);

my $Img;

my $LatitudeScale  = $Height / abs($Top   - $Bottom);
my $LongitudeScale = $Width  / abs($Right - $Left);

initialize_image();

plot_trail();

if ($MarkInterval) {
  draw_grid();
}

write_file($OutFile);

exit (0);

# Some utility functions

sub round
  {
    my $x = shift;
    return ceil( $x * 100000 ) / 100000;
  }

sub min
  {
    my ($a, $b) = @_;
    if ($a<$b) { return $a; } else { return $b; }
  }

sub max
  {
    my ($a, $b) = @_;
    if ($a>$b) { return $a; } else { return $b; }
  }


sub minsec2deg

  # Takes a latitude/longitude value in seconds and converts it to
  # three values (degrees, minutes, and seconds).

  {
    my $aux     = shift;
    my $degrees = int($aux / 3600);
    my $seconds = ($aux % 3600);
    my $minutes = int($seconds/60);
       $seconds = $seconds % 60;

    return ($degrees, $minutes, $seconds);
  }

sub deg2str

  # Convert degress, minutes and seconds into a string

  {
    return sprintf("%02d\xb0%02d\'%02d\'\'", @_);
  }


sub initialize_image
  {
    $Img = new GD::Image($Width, $Height);

    my $bg_color = $Img->colorAllocate(255, 255, 255);

    $Img->filledRectangle(0, 0, $Width-1, $Height-1, $bg_color);
  }


sub read_file
  {
    my $fname = shift;
    my $fh = new FileHandle($fname)
      or croak "Unable to open file $fname";

    my $withinline = 0;

    while (my $line = <$fh>) {
      chomp($line);
      if ($line eq "BEGIN LINE")
	{
	  $withinline = !$withinline;
	}
      elsif ($line eq "END")
	{
	  $withinline = !$withinline;
	}
      else
	{
	  if ($withinline) {

	    croak "Expected latitude, longitude",
	      unless ($line =~ m/^-?\d+\.\d+,-?\d+\.\d+,?/);

	    my ($latitude, $longitude) = map { round($_) } (split /,/, $line);

	    $Left   = min( $Left,   $longitude );
	    $Top    = min( $Top,    $latitude );
	    $Right  = max( $Right,  $longitude );
	    $Bottom = max( $Bottom, $latitude );

	    push @Trail, [ $latitude, $longitude ];
	  } 
	  else
	    {
	      croak "Don\'t know how to handle this (expected \`\`BEGIN LINE\'\')";
	    }
	}
    }

    $fh->close();
  }

sub latlon2xy
  {
    my ($latitude, $longitude) = @_;
    my $y = $Height - ceil( ($latitude - $Top) * $LatitudeScale);
    my $x = ceil( ($longitude - $Left) * $LongitudeScale);
    return ($x,$y);
  }


sub plot_trail
  {
    assert( ref($Img) eq "GD::Image" ), if DEBUG;

    my $pt_color = $Img->colorAllocate(0,   0,   0);
    my $ln_color = $Img->colorAllocate(192, 192, 192);

    my ($last_x, $last_y)     = (undef, undef);

    foreach my $point (@Trail) {
      my ($latitude, $longitude) = @$point;

      my ($x, $y) = latlon2xy($latitude, $longitude);

#       assert( ($x >= 0) && ($x <= $Width) ), if DEBUG;
#       assert( ($y >= 0) && ($y <= $Height) ), if DEBUG;

      if ((!$PointsOnly) && (defined $last_x)) {
	$Img->line($last_x, $last_y, $x, $y, $ln_color);
	$Img->setPixel($last_x, $last_y, $pt_color);
      } else {
	$Img->setPixel($x, $y, $pt_color);
      }

      ($last_x, $last_y) = ($x, $y);
    }
  }

sub draw_grid
  {
    assert( $MarkInterval > 0 ), if DEBUG;
    assert( ref($Img) eq "GD::Image" ), if DEBUG;

    my $mk_color = $Img->colorAllocate(128, 128, 128);

    {
      my $mark_l   = int($Top)*3600; if ($mark_l<0) { $mark_l-=3600; }
      my $mark_lim = int($Bottom*3600);

      while ($mark_l < $mark_lim) {

	my $y = ($Height-1) - ceil( ($mark_l/3600 - $Top) *
				    $LatitudeScale );

	if (($y>=0) && ($y<$Height)) {
	  $Img->line(0, $y, $Width-1, $y, $mk_color);

	  my $string = deg2str(minsec2deg(abs($mark_l))) .
	    (($mark_l<0) ? "S" : "N");
	  $Img->string(gdSmallFont, 2, $y, $string, $mk_color);
	}

	$mark_l += $MarkInterval;
      }
    }

    {
      my $mark_lo  = int($Left)*3600; if ($mark_lo<0) { $mark_lo-=3600; }
      my $mark_lim = int($Right*3600);

      while ($mark_lo < $mark_lim) {

	my $x = ceil( ($mark_lo/3600 - $Left) *
		      $LongitudeScale );

	if (($x>=0) && ($x<$Width)) {
	  $Img->line($x, 0, $x, $Height-1, $mk_color);

	  my $string = deg2str(minsec2deg(abs($mark_lo))) .
	    (($mark_lo<0) ? "W" : "E");
	  $Img->stringUp(gdSmallFont, $x, $Height-3, $string, $mk_color);
	}

	$mark_lo += $MarkInterval;
      }
    }
  }

sub write_file
  {
    assert( ref($Img) eq "GD::Image" ), if DEBUG;

    while (my $fname = shift) {
      my $fh = new FileHandle(">" . $fname)
	or croak "Unable to create output file";
      binmode($fh);
      print $fh $Img->png();
      $fh->close();
    }
  }



__END__

=pod

=head1 NAME

plottrail - plots GPS trails from latitude/longitude files as PNG images

=head1 SYNOPSYS

B<plottrail>
 B<--infile=>I<input-file>
 [B<--infile=>I<input-file-2>...B<--infile=>I<input-file-n>]
 [B<--outfile=>I<output-file>]
 [B<--points-only>]
 [B<--grid-interval=>I<seconds>]
 [B<--width=>I<image-width>]
 [B<--height->I<image-height>]

=head1 REQUIREMENTS

The following (non-standard) Perl modules are required:

=over

=item L<Carp::Assert>

=item L<GD>

=back

=head1 DESCRIPTION

I<plottrail> plots GPS latitude/longitude files as a PNG image
file.  The image is a simple black and white/grayscale image.

Trail points are scaled within the image size, and are not in
proportion.  The points are also not adjusted for the curvature of the
earth.

=head2 Options

=over

=item -i, --infile

The input file name (a latitude/longitude file).  This can be repeated
multiple times to display more than one input file.

=item -o, --outfile

The output file name. Defults to F<output.png> if not specified.

Only PNG files can be created in this version.

=item -p, --points-only

If specified, only the specific points will be plotted.  The default
is to draw lines between the points.

=item -g, --grid-interval

Draws a grid of latitude and longitude lines every I<n> seconds,
labelling the values.  If I<n> is 0, no lines will be drawn.

The default is to mark off every minute (I<n>=60 seconds) of latitude
and longitude.

=item -w, --width

Specifies the width of the image, in pixels. The value must be at
least 50. Default is 400.

=item -h, --height

Specifies the height of the image, in pixels. The value must be at
least 50. Default is 400.

=back

=head2 Caveats

This script is a quick and dirty hack to view trail files. It has not
been tested with points from the southern hemisphere or east of the
Greenwich Meridian.

=head1 FILE FORMAT

This program uses latitude/longitude files as input, since it is a
simple format that is supported by many GPS and mapping
applications.  It is a 7-bit ASCII text file containing latitude and
longitude in I<degrees>, separated by comma. An example is below:

  BEGIN LINE
  40.872806,-72.805472
  40.872722,-72.805278
  40.873194,-72.805694
  40.872722,-72.805722
  40.873000,-72.805583
  END

The values above are I<degrees+(minutes/60)+(seconds/3600)>. Negative
values refer to South or West.

Some applications produce a third value (depending on the application,
it refers to height, time or a comment).  A third value is ignored.

=head1 SEE ALSO

=over

=item L<GPS::Lowrance::Trail>

=back

=head1 AUTHOR

Robert Rothenberg <rrwo@cpan.org>

=head1 LICENSE

Copyright (c) 2002-2003 Robert Rothenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
