=head1 NAME

PDL::Graphics::TriD::Labels - Text tools

=head1 SYNOPSIS

  my $l = PDL::Graphics::TriD::Labels->new($lablepoints,
					  {Strings=>$strlist});

=head1 WARNING

This module is experimental and the interface will probably change.

=head1 DESCRIPTION

This module is used to write Labels on the graphs of TriD

=head1 AUTHOR

Copyright (C) 1997 Tuomas J. Lukka (lukka@husc.harvard.edu).
              2000 James P.  Edwards (jedwards@inmet.gov.br)
All rights reserved. There is no warranty. You are allowed
to redistribute this software / documentation under certain
conditions. For details, see the file COPYING in the PDL
distribution. If this file is separated from the PDL distribution,
the copyright notice should be included in the file.

=cut
package PDL::Graphics::TriD::Labels;

use strict;
use warnings;
use OpenGL qw/ :glfunctions :glconstants /;
use PDL::Graphics::OpenGLQ;
use PDL::Graphics::TriD::Objects;
use base qw/PDL::Graphics::TriD::GObject/;

sub gdraw {
	my ($this,$points) = @_;
	glDisable(&GL_LIGHTING);
	glColor3d(1,1,1);
	PDL::Graphics::OpenGLQ::gl_texts($points,@{$this->{Options}}{qw(Strings)});
	glEnable(&GL_LIGHTING);
}

sub get_valid_options {
  return {UseDefcols => 0, Strings => []}
}

1;
