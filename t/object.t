use strict;
use warnings;
use PDL;
use PDL::Graphics::TriD::Object;
use Test::More;
use Test::PDL;

sub is_norm {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  die "is_norm: need 6 args" if @_ != 6;
  my ($o, $type, $arg, $what, $exp_type, $exp) = @_;
  my ($type_back, $res) = $o->normalise_as($type, $arg, $what);
  is $type_back, $exp_type;
  is_pdl $res, $exp;
}

my $o = PDL::Graphics::TriD::Object->new;
eval { $o->normalise_as('', [pdl(1)]) };
like $@, qr/Must have 3 coordinates if no interpretation/;
is_norm $o, '', [pdl(1), pdl(4), pdl(7)], undef, '', float(1,4,7);
eval { $o->normalise_as('COLOR', pdl(1,4,7)) };
like $@, qr/Given 1D ndarray as colour but no points to match/;

sub PDL::Graphics::TriD::Object::cdummies { $_[1]->dummy(1,$_[2]->getdim(1)); }
is_norm $o, 'COLOR', pdl(1,4,7), zeroes(2,4), 'COLOR', float('1 4 7; 1 4 7; 1 4 7; 1 4 7');
eval { $o->normalise_as('COLOR', pdl(1,4,7)) };
like $@, qr/Given 1D ndarray as colour but no points to match/;
is_norm $o, 'COLOR', undef, zeroes(2,4), 'COLOR', float('1 1 1; 1 1 1; 1 1 1; 1 1 1');

is_norm $o, '', [SURF2D=>pdl('1 4 7;5 8 9')], undef, 'SURF2D', float('
  [0 0 1; 1 0 4; 2 0 7]
  [0 1 5; 1 1 8; 2 1 9]
');

is_norm $o, '', [LINE=>pdl('1 4 7'), pdl('5 8 9')], undef, 'LINE', float('
  1 5 0; 4 8 1; 7 9 2
');
is_norm $o, '', [LINE=>pdl('1 4 7'), pdl('5')], undef, 'LINE', float('
  1 5 0; 4 5 1; 7 5 2
');
is_norm $o, '', [LINE=>pdl('1 4 7'), 5], undef, 'LINE', float('
  1 5 0; 4 5 1; 7 5 2
');
is_norm $o, '', [LINE=>pdl('1 4 7')], undef, 'LINE', float('
  0 1 0; 1 4 0; 2 7 0
');

is_norm $o, '', [POLAR2D=>pdl('1 4 7;5 8 9')], undef, 'POLAR2D', float('
  [0 0 1; 0         0 4;  0        0 7]
  [0 1 5; 0.000092 -1 8; -0.000185 1 9]
');
is_norm $o, '', [POLAR2D=>pdl(1), pdl(4), pdl(7)], undef, 'POLAR2D', float(1,4,7);

done_testing;
