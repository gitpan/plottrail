
require 5.006;

use strict;
use warnings;

use Carp;
use Carp::Assert;
use FileHandle;
use Getopt::Long;
use GD;
use POSIX qw(ceil floor);

our $VERSION = '0.10';

my $InFile           = undef;
my $OutFile          = "output.png";

my ($Width, $Height) = (400, 400);

my $PointsOnly       = 0;

my $MarkInterval     = 60;

my $Args = GetOptions(
  'infile|i=s'         => \$InFile,
  'outfile|o=s'        => \$OutFile,
  'points-only|p!'     => \$PointsOnly,
  'grid-interval|g=i', => \$MarkInterval,
  'width|w=i',         => \$Width,
  'height|h=i',        => \$Height,
);

unless (defined $InFile) {
  croak "No input file specified\n";
}

if (($Width<50) || ($Height<50)) {
  croak "Width or Height is too small (<50)\n";
}

if ($MarkInterval<0) {
  croak "Grid Interval must be greater than or equal to 0\n";
}

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

# sub deg2minsec

#   # Takes longitude/lattitude value in degrees and breaks it into
#   # degrees, minutes, and seconds. We're not using this function
#   # because of rounding errors, such as repeatedly adding 1/60th of a
#   # degree.

#   {
#     my $aux     = shift;
#     my $degrees = int($aux);
#     my $seconds = ($aux - $degrees) * 3600;
#     my $minutes = int($seconds/60);
#        $seconds = $seconds % 60;
#     return ($degrees, $minutes, $seconds);
#   }


sub minsec2deg

  # Takes a longitude/lattitude value in seconds and converts it to
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

my $Fh = new FileHandle($InFile)
  or croak "Unable to open file $InFile";

my @Trail      = ();

my ($Left, $Top, $Right, $Bottom) = (90, 90, -90, -90);

my $WithinLine       = 0;

while (my $line = <$Fh>) {
  chomp($line);
  if ($line eq "BEGIN LINE")
    {
      $WithinLine = !$WithinLine;
    }
  elsif ($line eq "END")
    {
      $WithinLine = !$WithinLine;
    }
  else
    {
      if ($WithinLine) {

	croak "Expected longitude, lattitude",
	  unless ($line =~ m/^-?\d+\.\d+,-?\d+\.\d+,?/);

	my ($longitude, $latitude) = map { round($_) } (split /,/, $line);

	$Left   = min( $Left,   $latitude );
	$Top    = min( $Top,    $longitude );
	$Right  = max( $Right,  $latitude );
	$Bottom = max( $Bottom, $longitude );

	push @Trail, [ $longitude, $latitude ];
      } 
      else
	{
	  croak "Don\'t know how to handle this (expected \`\`BEGIN LINE\'\')";
	}
    }
}

$Fh->close();

my $Img = new GD::Image($Width, $Height);

my $LatitudeScale   = $Width  / abs($Right - $Left);
my $LongitudeScale  = $Height / abs($Top   - $Bottom);

# print $LatitudeScale, " ", $LongitudeScale, "\n";

{
  my $fg_color = $Img->colorAllocate(0,   0,   0);
  my $bg_color   = $Img->colorAllocate(255, 255, 255);

  $Img->filledRectangle(0, 0, $Width-1, $Height-1, $bg_color);

  my ($last_x, $last_y) = (undef, undef);

  foreach my $point (@Trail) {
    my ($longitude, $latitude) = @$point;

    my $x = ceil( ($latitude - $Left) * $LatitudeScale);
    my $y = $Height - ceil( ($longitude - $Top) * $LongitudeScale);

    assert( ($x >= 0) && ($x <= $Width) ), if DEBUG;
    assert( ($y >= 0) && ($y <= $Height) ), if DEBUG;

    if ((!$PointsOnly) && (defined $last_x)) {
      $Img->line($last_x, $last_y, $x, $y, $fg_color);
    } else {
      $Img->setPixel($x, $y, $fg_color);
    }

    ($last_x, $last_y) = ($x, $y);
  }


  if ($MarkInterval>0) {
    my $mk_color = $Img->colorAllocate(128, 128, 128);

    {
      my $mark_long = int($Top)*3600; if ($mark_long<0) { $mark_long-=3600; }
      my $mark_lim  = int($Bottom*3600);

      while ($mark_long < $mark_lim) {

	my $y = ($Height-1) - ceil( ($mark_long/3600 - $Top) *
				    $LongitudeScale );

	if (($y>=0) && ($y<$Height)) {
	  $Img->line(0, $y, $Width-1, $y, $mk_color);

 	  my $string = deg2str(minsec2deg(abs($mark_long))) .
 	    (($mark_long<0) ? "S" : "N");
 	  $Img->string(gdSmallFont, 2, $y, $string, $mk_color);
	}

	$mark_long += $MarkInterval;
      }
    }

    {
      my $mark_lat = int($Left)*3600; if ($mark_lat<0) { $mark_lat-=3600; }
      my $mark_lim = int($Right*3600);

      while ($mark_lat < $mark_lim) {

	my $x = ceil( ($mark_lat/3600 - $Left) *
				    $LatitudeScale );

	if (($x>=0) && ($x<$Width)) {
	  $Img->line($x, 0, $x, $Height-1, $mk_color);

 	  my $string = deg2str(minsec2deg(abs($mark_lat))) .
 	    (($mark_lat<0) ? "W" : "E");
 	  $Img->stringUp(gdSmallFont, $x, $Height-3, $string, $mk_color);
	}

	$mark_lat += $MarkInterval;
      }
    }

  }

}

$Fh->open(">" . $OutFile)
  or croak "Unable to create output file";

binmode($Fh);

print $Fh $Img->png();

$Fh->close();

exit (0);

__END__

=pod

=head1 NAME

plottrail - plots GPS trails from longitude/latitude files as PNG images

=head1 SYNOPSYS

B<plottrail>
 B<--infile=>I<input-file>
 [B<--outfile=>I<output-file>]
 [B<--points-only>]
 [B<--grid-interval=>I<seconds>]
 [B<--width=>I<image-width>]
 [B<--height->I<image-height>]

=head1 REQUIREMENTS

The following (non-standard) Perl modules are required:

=over

=item Carp::Assert

=item GD

=back

=head1 DESCRIPTION

I<plottrail> plots GPS longitude/latitude files as PNG images.

Trail points are scaled within the image size, and are not in
proportion.  The points are also not adjusted for the curvature of the
earth.

=head1 OPTIONS

=over

=item -i, --infile

The input file name (a longitude/latitude file). Only one file may be
plotted at a time in this version.

=item -o, --outfile

The output file name. Defults to I<output.png> if not specified.

Only PNG files can be created in this version.

=item -p, --points-only

If specified, only the specific points will be plotted.  The default
is to draw lines between the points.

=item -g, --grid-interval

Draws a grid of longitude and latitude lines every I<n> seconds,
labelling the values.  If I<n> is 0, no lines will be drawn.

The default is to mark off every minute (I<n>=60 seconds) of longitude
and latitude.

=item -w, --width

Specifies the width of the image, in pixels. Default is 400.

=item -h, --height

Specifies the height of the image, in pixels. Default is 400.

=back

=head1 CAVEATS

This script is a quick and dirty hack to view trail files.  It has not
been tested with points from the southern hemisphere or east of the
Greenwich Meridian.

=head1 AUTHOR

Robert Rothenberg <rrwo@cpan.org>

=head1 LICENSE

Copyright (c) 2002 Robert Rothenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
