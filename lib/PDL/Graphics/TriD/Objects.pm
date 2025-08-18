=encoding UTF-8

=head1 NAME

PDL::Graphics::TriD::Objects - Simple Graph Objects for TriD

=head1 SYNOPSIS

  use PDL::Graphics::TriD::Objects;

This provides the following class hierarchy:

  PDL::Graphics::TriD::GObject           (abstract) base class
  ├ PDL::Graphics::TriD::Points          individual points
  ├ PDL::Graphics::TriD::Spheres         fat 3D points :)
  ├ PDL::Graphics::TriD::Lines           separate lines
  ├ PDL::Graphics::TriD::LineStrip       continuous paths
  ├ PDL::Graphics::TriD::Trigrid         polygons
  └ PDL::Graphics::TriD::Lattice         colored lattice, maybe filled/shaded

=head1 DESCRIPTION

This module contains a collection of classes which represent graph
objects.  It is for internal use and not meant to be used by PDL
users.  GObjects can be either stand-alone or in Graphs, scaled
properly.  All the points used by the object must be in the member
{Points}.  I guess we can afford to force data to be copied (X,Y,Z) ->
(Points)...

=head1 OBJECTS

=head2 PDL::Graphics::TriD::GObject

Inherits from base PDL::Graphics::TriD::Object and adds fields Points,
Colors and Options.

=cut

package PDL::Graphics::TriD::GObject;
use strict;
use warnings;
use base qw/PDL::Graphics::TriD::Object/;
use fields qw/Points Colors Options/;

$PDL::Graphics::TriD::verbose //= 0;

sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($type,$points,$colors) = @_;
  print "GObject new.. calling SUPER::new...\n" if $PDL::Graphics::TriD::verbose;
  my $this = $type->SUPER::new();
  print "GObject new - back (SUPER::new returned $this)\n" if $PDL::Graphics::TriD::verbose;
  $options->{UseDefcols} = 1 if !defined $colors; # for VRML efficiency
  $this->{Options} = $options;
  $this->check_options;
  print "GObject new - calling realcoords\n" if($PDL::Graphics::TriD::verbose);
  $this->{Points} = $points = PDL::Graphics::TriD::realcoords($type->r_type,$points);
  print "GObject new - back from  realcoords\n" if($PDL::Graphics::TriD::verbose);
  $this->{Colors} = defined $colors
    ? PDL::Graphics::TriD::realcoords("COLOR",$colors)
    : $this->cdummies(PDL->pdl(PDL::float(),1,1,1),$points);
  print "GObject new - returning\n" if($PDL::Graphics::TriD::verbose);
  return $this;
}

sub check_options {
	my($this) = @_;
	my $opts = $this->get_valid_options();
	$this->{Options} = $opts, return if !$this->{Options};
	print "FETCHOPT: $this ".(join ',',%$opts)."\n" if $PDL::Graphics::TriD::verbose;
	my %newopts = (%$opts, %{$this->{Options}});
	my @invalid = grep !exists $opts->{$_}, keys %newopts;
	die "$this: invalid options left: @invalid" if @invalid;
	$this->{Options} = \%newopts;
}

sub set_colors {
  my($this,$colors) = @_;
  if(ref($colors) eq "ARRAY"){
    $colors = PDL::Graphics::TriD::realcoords("COLOR",$colors);
  }
  $this->{Colors}=$colors;
  $this->data_changed;
}

sub get_valid_options { +{
  UseDefcols => 0,
  Lighting => 1,
}}
sub get_points { $_[0]{Points} }
sub cdummies { $_[1] }
sub r_type { "" }
sub defcols { $_[0]{Options}{UseDefcols} }

# In the future, have this happen automatically by the ndarrays.
sub data_changed {
	my($this) = @_;
	$this->changed;
}

package PDL::Graphics::TriD::Points;
use base qw/PDL::Graphics::TriD::GObject/;
sub get_valid_options { +{
  UseDefcols => 0,
  PointSize => 1,
  Lighting => 0,
}}

package PDL::Graphics::TriD::Spheres;
use base qw/PDL::Graphics::TriD::GObject/;
# need to add radius
sub get_valid_options { +{
  UseDefcols => 0,
  PointSize => 1,
  Lighting => 1,
}}

package PDL::Graphics::TriD::Lines;
use base qw/PDL::Graphics::TriD::GObject/;
sub cdummies { return $_[1]->dummy(1); }
sub r_type { return "SURF2D";}
sub get_valid_options { +{
  UseDefcols => 0,
  LineWidth => 1,
  Lighting => 0,
}}

package PDL::Graphics::TriD::LineStrip;
use base qw/PDL::Graphics::TriD::GObject/;
sub cdummies { return $_[1]->dummy(1); }
sub r_type { return "SURF2D";}
sub get_valid_options { +{
  UseDefcols => 0,
  LineWidth => 1,
  Lighting => 0,
}}

package PDL::Graphics::TriD::Trigrid;
use PDL::Graphics::OpenGLQ;
use base qw/PDL::Graphics::TriD::GObject/;
use fields qw/Faceidx FaceNormals VertexNormals/;
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my($type,$points,$faceidx,$colors) = @_;
  my $this = $type->SUPER::new($points,$colors,$options);
  # faceidx is 2D pdl of indices into points for each face
  $this->{Faceidx} = $faceidx->ulong;
  $options = $this->{Options};
  if ($options->{Shading} or $options->{ShowNormals}) {
    my ($fn, $vn) = triangle_normals($this->{Points}, $faceidx);
    $this->{VertexNormals} = $vn if $options->{Smooth} or $options->{ShowNormals};
    $this->{FaceNormals} = $fn if !$options->{Smooth} or $options->{ShowNormals};
  }
  $this;
}
sub get_valid_options { +{
  UseDefcols => 0,
  Lines => 0,
  Shading => 1,
  Smooth => 1,
  ShowNormals => 0,
  Lighting => 1,
}}
sub cdummies { $_[1]->dummy(1,$_[2]->getdim(1)); }

# lattice -> triangle vertices:
# 4  5  6  7  ->  formula: origin coords + sequence of orig size minus top+right
# 0  1  2  3      4,0,1,1,5,4  5,1,2,2,6,5    6,2,3,3,7,6
package PDL::Graphics::TriD::Lattice;
use PDL::Graphics::OpenGLQ;
use base qw/PDL::Graphics::TriD::GObject/;
use fields qw/VertexNormals Faceidx FaceNormals/;
sub cdummies {
  my $shading = $_[0]{Options}{Shading};
  !$shading ? $_[1]->dummy(1)->dummy(1) :
  $shading == 1 ? $_[1]->dummy(1,$_[2]->getdim(2)-1)->dummy(1,$_[2]->getdim(1)-1) :
  $_[1]->slice(":," . join ',', map "*$_", ($_[2]->dims)[1,2])
}
sub r_type {return "SURF2D";}
sub get_valid_options { +{
  UseDefcols => 0,
  Lines => 1,
  Lighting => 0,
  Shading => 2, # 0=no fill, 1=flat colour per triangle, 2=smooth colour per vertex, 3=colors associated with vertices
  Smooth => 0,
  ShowNormals => 0,
}}
sub new {
  my ($class,$points,$colors,$options) = @_;
  my $this = $class->SUPER::new($points,$colors,$options);
  ($points, $options) = @$this{qw(Points Options)};
  if ($options->{Shading} or $options->{ShowNormals}) {
    my (undef, $x, $y, @extradims) = $points->dims;
    my $inds = PDL::ulong(0,1,$x,$x+1,$x,1)->slice(',*'.($x-1).',*'.($y-1));
    $inds = $inds->dupN(1,1,@extradims) if @extradims;
    my $indadd = PDL->sequence($x,$y,@extradims)->slice('*1,:-2,:-2');
    my $faceidx = $this->{Faceidx} = ($inds + $indadd)->splitdim(0,3)->clump(1..3+@extradims);
    my ($fn, $vn) = triangle_normals($points->clump(1..2+@extradims), $faceidx);
    $this->{VertexNormals} = $vn if $options->{Smooth} or $options->{ShowNormals};
    $this->{FaceNormals} = $fn if !$options->{Smooth} or $options->{ShowNormals};
  }
  $this;
}

package PDL::Graphics::TriD::Labels;
use base qw/PDL::Graphics::TriD::GObject/;
sub get_valid_options { +{
  UseDefcols => 0,
  Strings => [],
  Lighting => 0,
}}
sub set_labels {
  my ($this, $array) = @_;
  $this->{Options}{Strings} = $array;
}

1;
