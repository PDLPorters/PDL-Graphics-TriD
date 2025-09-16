=encoding UTF-8

=head1 NAME

PDL::Graphics::TriD::Objects - Simple Graph Objects for TriD

=head1 SYNOPSIS

  use PDL::Graphics::TriD::Objects;

This provides the following class hierarchy:

  PDL::Graphics::TriD::Object            base class for containers
  ├ PDL::Graphics::TriD::Arrows          lines with arrowheads
  ├ PDL::Graphics::TriD::Trigrid         polygons
  └ PDL::Graphics::TriD::GObject         (abstract) base class for drawables

  PDL::Graphics::TriD::GObject           (abstract) base class for drawables
  ├ PDL::Graphics::TriD::Points          individual points
  ├ PDL::Graphics::TriD::Spheres         fat 3D points :)
  ├ PDL::Graphics::TriD::Lines           separate lines
  ├ PDL::Graphics::TriD::LineStrip       continuous paths
  ├ PDL::Graphics::TriD::Triangles       just polygons
  ├ PDL::Graphics::TriD::Lattice         colored lattice, maybe filled/shaded
  └ PDL::Graphics::TriD::Labels          text labels

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
and Colors.
It is for primitive objects rather than containers.

=cut

package PDL::Graphics::TriD::GObject;
use strict;
use warnings;
use base qw/PDL::Graphics::TriD::Object/;
use fields qw/Points Colors/;

$PDL::Graphics::TriD::verbose //= 0;

sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($type,$points,$colors) = @_;
  my $this = $type->SUPER::new($options);
  $this->{Points} = $points = PDL::Graphics::TriD::realcoords($type->r_type,$points);
  $this->{Options}{UseDefcols} = 1 if !defined $colors; # for VRML efficiency
  $this->{Colors} = defined $colors
    ? PDL::Graphics::TriD::realcoords("COLOR",$colors)
    : $this->cdummies(PDL->pdl(PDL::float(),1,1,1),$points);
  $this;
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
use base qw/PDL::Graphics::TriD::Object/;
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($type,$points,$faceidx,$colors) = @_;
  my $this = $type->SUPER::new($options);
  # faceidx is 2D pdl of indices into points for each face
  $faceidx = $faceidx->ulong;
  $options = $this->{Options};
  my %less = %$options; delete @less{qw(ShowNormals Lines)};
  $less{Shading} = 3 if $options->{Shading};
  $this->add_object(PDL::Graphics::TriD::Triangles->new($points, $faceidx->clump(1..$faceidx->ndims-1), $colors, \%less));
  if ($options->{Lines} or $options->{ShowNormals}) {
    $points = PDL::Graphics::TriD::realcoords($type->r_type,$points);
    my $faces = $points->dice_axis(1,$faceidx->flat)->splitdim(1,3);
    if ($options->{Lines}) {
      $this->add_object(PDL::Graphics::TriD::Lines->new($faces->dice_axis(1,[0,1,2,0]), PDL::float(0,0,0)));
    }
    if ($options->{ShowNormals}) {
      my ($fn, $vn) = triangle_normals($points, $faceidx);
      my $facecentres = $faces->transpose->avgover;
      my $facearrows = $facecentres->append($facecentres + $fn*0.1)->splitdim(0,3)->clump(1,2);
      my ($fromind, $toind) = PDL->sequence(PDL::ulong,2,$facecentres->dim(1))->t->dog;
      $this->add_object(PDL::Graphics::TriD::Arrows->new(
        $facearrows, PDL::float(0.5,0.5,0.5),
        { From=>$fromind, To=>$toind, ArrowLen => 0.5, ArrowWidth => 0.2 },
      ));
      my $vertarrows = $points->append($points + $vn*0.1)->splitdim(0,3)->clump(1,2);
      ($fromind, $toind) = PDL->sequence(PDL::ulong,2,$points->dim(1))->t->dog;
      $this->add_object(PDL::Graphics::TriD::Arrows->new(
        $vertarrows, PDL::float(1,1,1),
        { From=>$fromind, To=>$toind, ArrowLen => 0.5, ArrowWidth => 0.2 },
      ));
    }
  }
  $this;
}
sub r_type { return "";}
sub get_valid_options { +{
  UseDefcols => 0,
  Lines => 0,
  Shading => 1,
  Smooth => 1,
  ShowNormals => 0,
  Lighting => 1,
}}
sub cdummies { $_[1]->dummy(1,$_[2]->getdim(1)); }

package PDL::Graphics::TriD::Triangles;
use base qw/PDL::Graphics::TriD::GObject/;
use fields qw/Faceidx FaceNormals VertexNormals/;
use PDL::Graphics::OpenGLQ;
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($type,$points,$faceidx,$colors) = @_;
  my $this = $type->SUPER::new($points,$colors,$options);
  $faceidx = $this->{Faceidx} = $faceidx->ulong; # (3,nfaces) indices
  $options = $this->{Options};
  if ($options->{Shading}) {
    my ($fn, $vn) = triangle_normals($this->{Points}, $faceidx);
    $this->{VertexNormals} = $vn if $options->{Smooth};
    $this->{FaceNormals} = $fn if !$options->{Smooth};
  }
  $this;
}
sub get_valid_options { +{
  UseDefcols => 0,
  Shading => 1, # 0=no shading, 1=flat colour per triangle, 2=smooth colour per vertex, 3=colors associated with vertices
  Smooth => 0,
  Lighting => 0,
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

package PDL::Graphics::TriD::Arrows;
use base qw/PDL::Graphics::TriD::Object/;
sub r_type { return "";}
sub get_valid_options { +{
  UseDefcols => 0,
  From => [],
  To => [],
  ArrowWidth => 0.02,
  ArrowLen => 0.1,
  Lighting => 0,
}}
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : $_[0]->get_valid_options;
  my ($class, $points, $colors) = @_;
  my $this = $class->SUPER::new($options);
  $options = $this->{Options};
  my ($from, $to, $w, $hl) = delete @$options{qw(From To ArrowWidth ArrowLen)};
  $points = PDL::Graphics::TriD::realcoords($class->r_type,$points);
  $this->add_object(PDL::Graphics::TriD::Lines->new(
    $points->dice_axis(1,$from)->flowing->append($points->dice_axis(1,$to))->splitdim(0,3),
    $colors, $options
  ));
  my ($tv, $ti) = PDL::Graphics::OpenGLQ::gen_arrowheads($points->flowing,$from,$to,
    $hl, $w);
  $this->add_object(PDL::Graphics::TriD::Triangles->new($tv, $ti, $colors, { %$options, Shading=>0 }));
  $this;
}

1;
