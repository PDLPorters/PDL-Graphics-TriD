use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::TriD;

my $size = 5;
my $y = PDL->zeroes(3,$size,$size);
axisvalues($y->slice("(0)")->inplace);
axisvalues($y->slice("(1)")->transpose->inplace);
srandom(5);
random((my $ysl2 = $y->slice("(2)"))->inplace);
$ysl2 /= 5;
my $c = PDL->random(3,$size,$size);

for (
  ['LineStrip'],
  ['Lattice', {Shading=>0}],
  ['Lattice', {Shading=>1}],
  ['Lattice', {Shading=>2}],
  ['Lattice', {Shading=>3, ShowNormals => 1}],
  ['Lattice', {Shading=>3, ShowNormals => 1, Smooth=>1}],
) {
  my ($class, $opts) = @$_;
  eval { "PDL::Graphics::TriD::$class"->new($y,$c,$opts) };
  is $@, '' or diag 'Spec was: ', explain $opts;
}

done_testing;
