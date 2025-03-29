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

done_testing;
