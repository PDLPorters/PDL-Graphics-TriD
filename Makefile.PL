use strict;
use warnings;
use ExtUtils::MakeMaker;
use PDL::Core::Dev;

use OpenGL::Modern::Config;
my ($def, $inc, $libs) = ('', '', '');
$libs = $OpenGL::Modern::Config->{LIBS} if $OpenGL::Modern::Config->{LIBS};
$def .= ' '.$OpenGL::Modern::Config->{DEFINE} if $OpenGL::Modern::Config->{DEFINE};
$inc .= ' '.$OpenGL::Modern::Config->{INC} if $OpenGL::Modern::Config->{INC};
$libs .= ' -lm' if $libs !~ /\s-lm\b/;

my $package_name = "PDL::Graphics::TriD";
(my $repo = $package_name) =~ s#::#-#g;
$repo = "PDLPorters/$repo";
WriteMakefile (
  NAME         => $package_name,
  AUTHOR => 'PerlDL Developers <pdl-general@lists.sourceforge.net>',
  LICENSE=> "perl",
  VERSION_FROM => 'lib/PDL/Graphics/TriD.pm',
  CONFIGURE_REQUIRES => {
    'ExtUtils::MakeMaker' => 0,
    'PDL' => '2.096',
    'OpenGL::Modern' => '0.0403',
  },
  PREREQ_PM => {
    'PDL' => '2.096',
    'OpenGL::Modern' => '0.0403',
    'OpenGL::GLFW' => '0.0402',
  },
  TEST_REQUIRES => {
    'Test::More' => '0.88',
  },
  !$def ? () : (DEFINE => $def),
  !$inc ? () : (INC => $inc),
  LIBS => [$libs],
  META_MERGE => {
    "meta-spec" => { version => 2 },
    resources => {
      homepage => 'http://pdl.perl.org/',
      bugtracker  => {web=>"https://github.com/$repo/issues"},
      repository  => {
        url => "git://github.com/$repo.git",
        type => 'git',
        web => "https://github.com/$repo",
      },
      x_IRC => 'irc://irc.perl.org/#pdl',
    },
  },
);

{
my @pd_srcs;
package MY; # so that "SUPER" works right
sub init_PM {
  my ($self) = @_;
  $self->SUPER::init_PM;
  @pd_srcs = ::pdlpp_eumm_update_deep($self);
}
sub postamble { ::pdlpp_postamble(@pd_srcs) }
}
