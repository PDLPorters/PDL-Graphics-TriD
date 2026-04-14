#
# The PDL::Graphics::TriD::ViewPort is already partially defined in
# the appropriate gdriver (GL or VRML), items defined here are common
# to both
# 
package PDL::Graphics::TriD::ViewPort;
use strict;
use warnings;
use base qw/PDL::Graphics::TriD::Object/;
use fields qw/X0 Y0 W H Transformer EHandler Active ResizeCommands
              DefMaterial AspectRatio Graphs/;

$PDL::Graphics::TriD::verbose //= 0;

sub new {
  my $this= shift->SUPER::new();
  $this->{DefMaterial} = PDL::Graphics::TriD::Material->new;
  $this->resize(@_);
}

sub graph {
  my ($this,$graph) = @_;
  if (defined($graph)) {
    $this->add_object($graph);
    push(@{$this->{Graphs}},$graph);
  } elsif (defined $this->{Graphs}) {
    $graph = $this->{Graphs}[0];
  }
  $graph;
}  

sub delete_graph {
  my ($this,$graph) = @_;
  $this->delete_object($graph);
  my $ref = $this->{Graphs};
  my @inds = grep $graph == $ref->[$_], 0..$#$ref;
  splice @$ref, $_, 1 for reverse @inds;
}

sub resize {
  my $this = shift;
  @$this{qw(X0 Y0 W H)} = @_;
  $this;
}

sub add_resizecommand {
  my ($this,$com) = @_;
  push @{$this->{ResizeCommands}},$com;
  print "ARC: $this->{W},$this->{H}\n" if $PDL::Graphics::TriD::verbose;
  &$com($this->{W},$this->{H});
}

sub set_material {
  $_[0]->{DefMaterial} = $_[1];
}

sub eventhandler {
  my ($this,$eh) = @_;
  if (defined $eh) {
    $this->{EHandler} = $eh;
  }
  $this->{EHandler};
}

sub set_transformer {
  $_[0]->transformer($_[1]);
}

sub transformer {
  my ($this,$t) = @_;
  if (defined $t) {
    $this->{Transformer} = $t;
  }
  $this->{Transformer};
}

#
# restore the image view to a known value
#
sub setview{
  my($vp,$view) = @_;
  my $transformer = $vp->transformer();
  if (ref($view) eq "ARRAY") {
	 $transformer->set({WRotation=>$view});
  } elsif ($view eq "Top") {
	 $transformer->set({WRotation=>[1,0,0,0]});
  } elsif ($view eq "East") {
	 $transformer->set({WRotation=>[0.5,-0.5,-0.5,-0.5]});
  } elsif ($view eq "South") {
	 $transformer->set({WRotation=>[0.6,-0.6,0,0]});
  }
}

1;
