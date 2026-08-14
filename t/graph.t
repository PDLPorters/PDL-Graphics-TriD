use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::TriD::Graph;
use Test::PDL;

my $euclid = PDL::Graphics::TriD::Axes::Euclid->new;
$euclid->init_scale;
$euclid->add_scale(my $points = float('0 0 0; 1 1 1; 1 1 1; 2 1 1'), my $inds = [0..2]);
$euclid->add_scale($points, $inds);
$euclid->finish_scale;
is_deeply $euclid->{AxisLabelsObj}{Strings}, [qw(
  0.000 0.500 1.000 1.500 2.000
  0.000 0.250 0.500 0.750 1.000
  0.000 0.250 0.500 0.750 1.000
)]
  or diag explain $euclid->{AxisLabelsObj}{Strings};
is_pdl $euclid->{AxisLabelsObj}{Points}, float('
  0 -0.1 -0.1; 0.25 -0.1 -0.1; 0.5 -0.1 -0.1; 0.75 -0.1 -0.1; 1 -0.1 -0.1;
  -0.1 0 -0.1; -0.1 0.25 -0.1; -0.1 0.5 -0.1; -0.1 0.75 -0.1; -0.1 1 -0.1;
  -0.1 -0.1 0; -0.1 -0.1 0.25; -0.1 -0.1 0.5; -0.1 -0.1 0.75; -0.1 -0.1 1
');
is_pdl $euclid->transform($points->zeroes, $points, $inds), float('
  0 0 0; 0.5 1 1; 0.5 1 1; 1 1 1
');

my $cyl = PDL::Graphics::TriD::Axes::Sinusoidal->new;
$cyl->init_scale;
$cyl->add_scale(my $points2 = float('-80 -80 800; 80 80 900'), $inds);
$cyl->finish_scale;
is_pdl $cyl->{AxisLabelsObj}{Points}, float('
  0.413176 -0.1 -0.1; 0.456588 -0.1 -0.1; 0.5 -0.1 -0.1; 0.543412 -0.1 -0.1; 0.586824 -0.1 -0.1;
  0.313176 0 -0.1; 0.0169778 0.25 -0.1; -0.1 0.5 -0.1; 0.0169778 0.75 -0.1; 0.313176 1 -0.1
'), {atol=>1e-4};
is_pdl $cyl->transform($points2->zeroes, $points2, $inds), float('
  0.413176 0 0; 0.586824 1 1
');

$cyl->init_scale;
$cyl->add_scale(my $points3 = float('-80 -80 800; 80 50 900'), $inds);
$cyl->finish_scale;
is_pdl $cyl->transform($points2->zeroes, $points3, $inds), float('
  0.413155 0 0; 0.82147 1 1
');

my $pol = PDL::Graphics::TriD::Axes::PolarStereo->new;
$pol->init_scale;
$pol->add_scale(my $points4 = float('-80 80 800; 80 50 900'), $inds);
$pol->finish_scale;
is_pdl $pol->transform($points4->zeroes, $points4, $inds), float('
  0.379813 1 0; 1 0.862346 1
');

done_testing;
