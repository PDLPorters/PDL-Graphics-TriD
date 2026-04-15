use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::TriD::Graph;
use Test::PDL;

my $euclid = PDL::Graphics::TriD::EuclidAxes->new;
$euclid->add_scale(my $points = float('0 0 0; 2 1 1'), my $inds = [0..2]);
$euclid->finish_scale;
is_deeply $euclid->{AxisLabelsObj}{Strings}, [qw(
  0.000 0.500 1.000 1.500 2.000
  0.000 0.250 0.500 0.750 1.000
  0.000 0.250 0.500 0.750 1.000
)]
  or diag explain $euclid->{AxisLabelsObj}{Strings};
is_pdl $euclid->transform($points->zeroes, $points, $inds), float('
  0 0 0; 1 1 1
');

my $cyl = PDL::Graphics::TriD::CylindricalEquidistantAxes->new;
$cyl->add_scale(my $points2 = float('-80 -80 800; 80 80 900'), $inds);
$cyl->finish_scale;
is_pdl $cyl->transform($points2->zeroes, $points2, $inds), float('
  0.413176 0 0.101756; 0.586824 1 0.050878
');

done_testing;
