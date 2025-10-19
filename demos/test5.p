use strict;
use warnings;
use PDL;
use PDL::Graphics::TriD;
use PDL::Graphics::TriD::Graph;

my $size = 5;
my $y = PDL->zeroes(3,$size,$size);
axisvalues($y->slice("(0)")->inplace);
axisvalues($y->slice("(1)")->transpose->inplace);
srandom(5);
random((my $ysl2 = $y->slice("(2)"))->inplace);
$ysl2 /= 5;
my $c = PDL->random(3,$size,$size);

my @objs = (
  ['Lattice', {Shading=>0}],
  ['Lattice', {Shading=>1}],
  ['Lattice', {Shading=>2}],
  ['Lattice', {Shading=>3, Lighting => 1, ShowNormals => 1}],
  ['Lattice', {Shading=>3, Lighting => 1, ShowNormals => 1, Smooth=>1}],
);
my $i = 0;
@objs = map mk_trid($i++, @$_), @objs;
my ($below_obj, $above_obj) = map mk_trid($_, 'LineStrip'), -1, 0+@objs;

sub mk_trid { "PDL::Graphics::TriD::$_[1]"->new($y+pdl(0,0,$_[0]),$c,$_[2]) }

my $win = PDL::Graphics::TriD::get_current_window();
my $g = PDL::Graphics::TriD::Graph->new;
my @all = [$below_obj, @objs, $above_obj];
push @all, map [$below_obj, $_, $above_obj], @objs;
for my $these (@all) {
  $g->clear_data;
  $win->clear_viewport;
  $g->default_axes;
  $g->add_dataseries($_) for @$these;
  $g->scalethings;
  $win->clear_objects;
  $win->add_object($g);
  $win->twiddle;
}
