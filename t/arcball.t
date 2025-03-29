use strict;
use warnings;
use Test::More;

use PDL::Graphics::TriD::ArcBall;
use PDL::LiteF;
use Test::PDL;
{package FakeWindow; sub new {bless {}} sub add_resizecommand {} }

sub is_qua {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my ($got, $exp) = map PDL->pdl(@$_), @_;
  is_pdl $got, $exp;
}

my $win = FakeWindow->new;

my $arcball = PDL::Graphics::TriD::ArcBall->new($win);
isa_ok $arcball, 'PDL::Graphics::TriD::ArcBall';
$arcball->set_wh(100,100);
is_qua $arcball->xy2qua(50,50), [0,0,0,1];
is_qua $arcball->xy2qua(25,25), [0,-0.5,0.5,0.707106];
is_qua $arcball->xy2qua(25,50), [0,-0.5,0,0.866025];
is_qua $arcball->xy2qua(25,75), [0,-0.5,-0.5,0.707106];
is_qua $arcball->xy2qua(75,25), [0,0.5,0.5,0.707106];
is_qua $arcball->xy2qua(75,50), [0,0.5,0,0.866025];
is_qua $arcball->xy2qua(75,75), [0,0.5,-0.5,0.707106];

my $arccone = PDL::Graphics::TriD::ArcCone->new($win);
isa_ok $arccone, 'PDL::Graphics::TriD::ArcCone';
$arccone->set_wh(100,100);
is_qua $arccone->xy2qua(50,50), [0,0,0,1];
is_qua $arccone->xy2qua(25,25), [0,-0.653281,0.653281,0.382683];
is_qua $arccone->xy2qua(25,50), [0,-0.707106,0,0.707106];
is_qua $arccone->xy2qua(25,75), [0,-0.653281,-0.653281,0.382683];
is_qua $arccone->xy2qua(75,25), [0,0.653281,0.653281,0.382683];
is_qua $arccone->xy2qua(75,50), [0,0.707106,0,0.707106];
is_qua $arccone->xy2qua(75,75), [0,0.653281,-0.653281,0.382683];

my $arcbowl = PDL::Graphics::TriD::ArcBowl->new($win);
isa_ok $arcbowl, 'PDL::Graphics::TriD::ArcBowl';
$arcbowl->set_wh(100,100);
is_qua $arcbowl->xy2qua(50,50), [0,0,0,1];
is_qua $arcbowl->xy2qua(25,25), [0,-0.598834,0.598834,0.531784];
is_qua $arcbowl->xy2qua(25,50), [0,-0.577350,0,0.816496];
is_qua $arcbowl->xy2qua(25,75), [0,-0.598834,-0.598834,0.531784];
is_qua $arcbowl->xy2qua(75,75), [0,0.598834,-0.598834,0.531784];
is_qua $arcbowl->xy2qua(75,50), [0,0.577350,0,0.816496];
is_qua $arcbowl->xy2qua(75,75), [0,0.598834,-0.598834,0.531784];

done_testing;
