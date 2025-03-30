use strict;
use warnings;
use Test::More;

use PDL::Graphics::TriD::Quaternion;
use PDL::LiteF;
use Test::PDL;

sub is_qua {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my ($got, $exp) = map PDL->pdl(@$_), @_;
  is_pdl $got, $exp;
}

my $q = PDL::Graphics::TriD::Quaternion->new(0,0,0,1);
isa_ok $q, 'PDL::Graphics::TriD::Quaternion';
is_qua $q, [0,0,0,1];

is_qua +PDL::Graphics::TriD::Quaternion->new(0,0,0,2)->normalise, [0,0,0,1];

my ($q1, $q2) = map PDL::Graphics::TriD::Quaternion->new(@$_), [1,2,3,4], [5,6,7,8];

is_qua $q1->multiply($q2), [
  5-12-21-32, # $a0*$b0 - $a1*$b1 - $a2*$b2 - $a3*$b3,
  6+10+24-28, # $a0*$b1 + $b0*$a1 + $a2*$b3 - $a3*$b2,
  7+15+24-16, # $a0*$b2 + $b0*$a2 + $a3*$b1 - $a1*$b3,
  8+20+14-18, # $a0*$b3 + $b0*$a3 + $a1*$b2 - $a2*$b1
];

done_testing;
