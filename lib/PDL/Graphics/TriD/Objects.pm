=encoding UTF-8

=head1 NAME

PDL::Graphics::TriD::Objects - Simple Graph Objects for TriD

=head1 SYNOPSIS

  use PDL::Graphics::TriD::Objects;

This provides the following class hierarchy:

  PDL::Graphics::TriD::Object            base class for containers
  ├ PDL::Graphics::TriD::Arrows          lines with arrowheads
  ├ PDL::Graphics::TriD::Trigrid         polygons
  ├ PDL::Graphics::TriD::Lattice         colored lattice, maybe filled/shaded
  ├ PDL::Graphics::TriD::LineStrip       continuous paths
  └ PDL::Graphics::TriD::GObject         (abstract) base class for drawables

  PDL::Graphics::TriD::GObject           (abstract) base class for drawables
  ├ PDL::Graphics::TriD::Points          individual points
  ├ PDL::Graphics::TriD::Spheres         fat 3D points :)
  ├ PDL::Graphics::TriD::Lines           separate lines
  ├ PDL::Graphics::TriD::DrawMulti       arbitrary-sized primitives
  ├ PDL::Graphics::TriD::Triangles       just polygons
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

package # hide from PAUSE
  PDL::Graphics::TriD::GObject;
use strict;
use warnings;
use base qw/PDL::Graphics::TriD::Object/;
use fields qw/Points Colors/;

$PDL::Graphics::TriD::verbose //= 0;

sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($type,$points,$colors) = @_;
  my $this = $type->SUPER::new($options);
  $this->{Points} = $points = $this->normalise_as($type->r_type,$points);
  $this->{Options}{UseDefcols} = 1 if !defined $colors; # for VRML efficiency
  $this->{Colors} = $this->normalise_as("COLOR",$colors,$points);
  $this;
}

sub set_colors {
  my($this,$colors) = @_;
  $colors = $this->normalise_as("COLOR",$colors) if ref($colors) eq "ARRAY";
  $this->{Colors} = $colors;
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

package # hide from PAUSE
  PDL::Graphics::TriD::Points;
use base qw/PDL::Graphics::TriD::GObject/;
sub cdummies { $_[1]->slice(":," . join ',', map "*$_", grep defined, ($_[2]->dims)[1,2]) }
sub get_valid_options { +{
  UseDefcols => 0,
  PointSize => 1,
  Lighting => 0,
}}

package # hide from PAUSE
  PDL::Graphics::TriD::Spheres;
use base qw/PDL::Graphics::TriD::GObject/;
# need to add radius
sub get_valid_options { +{
  UseDefcols => 0,
  Lighting => 1,
}}

package # hide from PAUSE
  PDL::Graphics::TriD::Lines;
use base qw/PDL::Graphics::TriD::GObject/;
sub cdummies { $_[1]->slice(":," . join ',', map "*$_", grep defined, ($_[2]->dims)[1,2]) }
sub r_type { return "SURF2D";}
sub get_valid_options { +{
  UseDefcols => 0,
  LineWidth => 1,
  Lighting => 0,
}}

package # hide from PAUSE
  PDL::Graphics::TriD::LineStrip;
use base qw/PDL::Graphics::TriD::Object/;
sub cdummies { $_[1]->slice(":," . join ',', map "*$_", grep defined, ($_[2]->dims)[1,2]) }
sub r_type { return "SURF2D";}
sub get_valid_options { +{
  UseDefcols => 0,
  LineWidth => 1,
  Lighting => 0,
}}
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($class,$points,$colors) = @_;
  my $this = $class->SUPER::new($options);
  $points = $this->normalise_as($class->r_type,$points);
  $colors = $this->normalise_as("COLOR",$colors,$points);
  $options = $this->{Options};
  my (undef, $x, $y, @extradims) = $points->dims;
  $y //= 1,
  my $counts = (PDL->ones(PDL::long, $y, @extradims) * $x)->flat;
  my $starts = (PDL->sequence(PDL::ulong, $y, @extradims) * $x)->flat;
  my $indices = PDL->sequence(PDL::ulong, $x, $y, @extradims)->flat;
  $points = $points->clump(1..2+@extradims) if $points->ndims > 2;
  $colors = $colors->clump(1..2+@extradims) if $colors->ndims > 2;
  $this->add_object(PDL::Graphics::TriD::DrawMulti->new($points, $colors, 'linestrip', $counts, $starts, $indices));
  $this;
}

package # hide from PAUSE
  PDL::Graphics::TriD::Trigrid;
use PDL::Graphics::OpenGLQ;
use base qw/PDL::Graphics::TriD::Object/;
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($type,$points,$faceidx,$colors) = @_;
  my $this = $type->SUPER::new($options);
  PDL::barf "Trigrid error: broadcast dims on faceidx forbidden" if $faceidx->ndims > 2;
  $faceidx = $faceidx->ulong;
  $options = $this->{Options};
  my %less = %$options; delete @less{qw(Lines)};
  $less{Shading} = 3 if $options->{Shading};
  $this->add_object(PDL::Graphics::TriD::Triangles->new($points, $faceidx, $colors, \%less));
  if ($options->{Lines}) {
    $points = $this->normalise_as($type->r_type,$points);
    my $f = $faceidx->dim(1);
    my $counts = (PDL->ones(PDL::long, $f) * 3)->flat;
    my $starts = (PDL->sequence(PDL::ulong, $f) * 3)->flat;
    my $indices = $faceidx->flat;
    $this->add_object(PDL::Graphics::TriD::DrawMulti->new($points, PDL::float(0,0,0), 'lineloop', $counts, $starts, $indices));
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

package # hide from PAUSE
  PDL::Graphics::TriD::Triangles;
use base qw/PDL::Graphics::TriD::GObject/;
use fields qw/Faceidx Normals/;
use PDL::Graphics::OpenGLQ;
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($type,$points,$faceidx,$colors) = @_;
  my $this = $type->SUPER::new($points,$colors,$options);
  $faceidx = $this->{Faceidx} = $faceidx->ulong; # (3,nfaces) indices
  PDL::barf "Triangles error: broadcast dimensions forbidden for '$_' [@{[$this->{$_}->dims]}]" for grep $this->{$_}->ndims != 2, qw(Points Colors Faceidx);
  PDL::barf "Triangles error: dimension mismatch between Points [@{[$this->{Points}->dims]}] and Colors [@{[$this->{Colors}->dims]}]" if $this->{Points}->ndims != $this->{Colors}->ndims or $this->{Points}->dim(1) != $this->{Colors}->dim(1);
  $options = $this->{Options};
  my ($idxflat, $idx0, @idxdims) = ($faceidx->flat, $faceidx->dims);
  if ($options->{Shading} or $options->{ShowNormals}) {
    my ($fn, $vn) = triangle_normals($this->{Points}, $faceidx);
    if ($options->{ShowNormals}) {
      $points = $this->normalise_as($type->r_type,$points);
      my $faces = $points->dice_axis(1,$idxflat)->splitdim(1,$idx0);
      my $facecentres = $faces->transpose->avgover;
      my $facearrows = $facecentres->append($facecentres + $fn*0.1)->splitdim(0,$idx0)->clump(1,2);
      my $fromto = PDL->sequence(PDL::ulong,2,$facecentres->dim(1));
      $this->add_object(PDL::Graphics::TriD::Arrows->new(
        $facearrows, PDL::float(0.5,0.5,0.5),
        { FromTo => $fromto, ArrowLen => 0.5, ArrowWidth => 0.2 },
      ));
      my $vertarrows = $points->append($points + $vn*0.1)->splitdim(0,3)->clump(1,2);
      $fromto = PDL->sequence(PDL::ulong,2,$points->dim(1));
      $this->add_object(PDL::Graphics::TriD::Arrows->new(
        $vertarrows, PDL::float(1,1,1),
        { FromTo => $fromto, ArrowLen => 0.5, ArrowWidth => 0.2 },
      ));
    }
    if ($options->{Shading}) {
      if ($options->{Smooth}) {
        $this->{Normals} = $vn;
      } else {
        $this->{Points} = $this->{Points}->dice_axis(1,$idxflat);
        $this->{Colors} = $this->{Colors}->dice_axis(1,$idxflat);
        $this->{Normals} = $fn->dummy(1,$idx0)->clump(1,2);
        $this->{Faceidx} = PDL->sequence(PDL::ulong,$idx0,@idxdims);
      }
    }
  }
  $this;
}
sub get_valid_options { +{
  UseDefcols => 0,
  Shading => 1, # 0=no shading, 1=flat colour per triangle, 2=smooth colour per vertex, 3=colors associated with vertices
  Smooth => 0,
  Lighting => 0,
  ShowNormals => 0,
}}
sub cdummies { $_[1]->dummy(1,$_[2]->getdim(1)); }

# lattice -> triangle vertices:
# 4  5  6  7  ->  formula: origin coords + sequence of orig size minus top+right
# 0  1  2  3      4,0,1,1,5,4  5,1,2,2,6,5    6,2,3,3,7,6
package # hide from PAUSE
  PDL::Graphics::TriD::Lattice;
use PDL::Graphics::OpenGLQ;
use base qw/PDL::Graphics::TriD::Object/;
sub cdummies {
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
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($class,$points,$colors) = @_;
  my $this = $class->SUPER::new($options);
  $points = $this->normalise_as($class->r_type,$points);
  $colors = $this->normalise_as("COLOR",$colors,$points);
  $options = $this->{Options};
  my $shading = $options->{Shading};
  my ($tri, $x, $y, @extradims) = $points->dims;
  PDL::barf "Lattice: points must be 3,x,y: got ($x $y @extradims)" if @extradims or $tri != 3;
  if ($shading) {
    my $inds = PDL::ulong(0,1,$x,$x+1,$x,1)->slice(',*'.($x-1).',*'.($y-1));
    my $indadd = PDL->sequence($x,$y)->slice('*1,:-2,:-2');
    my $faceidx = ($inds + $indadd)->splitdim(0,3)->clump(1..3);
    my %less = %$options; delete @less{qw(Lines)};
    my @colordims = $colors->dims;
    PDL::barf "Lattice: colours must be 3,x,y: got (@colordims)" if @colordims != 3 or $colordims[0] != 3;
    PDL::barf "Lattice: colours' x,y must equal points: got colour=(@colordims) points=($x,$y)" if $colordims[1] != $x or $colordims[2] != $y;
    $this->add_object(PDL::Graphics::TriD::Triangles->new($points->clump(1..2), $faceidx, $colors->clump(1..$colors->ndims-1), \%less));
  }
  if ($shading == 0 or $options->{Lines}) {
    my $lcolors = $shading ? $this->cdummies(PDL::float(0,0,0),$points) : $colors;
    my $counts = (PDL->ones(PDL::long, $y) * $x)->flat;
    my $starts = (PDL->sequence(PDL::ulong, $y) * $x)->flat;
    my $indices = PDL->sequence(PDL::ulong, $x, $y)->flat;
    $counts = $counts->append((PDL->ones(PDL::long, $x) * $y)->flat);
    $starts = $starts->append((PDL->sequence(PDL::ulong, $x) * $y)->flat + $indices->nelem);
    $indices = $indices->append(PDL->sequence(PDL::ulong, $x, $y)->t->flat);
    $this->add_object(PDL::Graphics::TriD::DrawMulti->new($points->clump(1..2), $lcolors->clump(1..2), 'linestrip', $counts, $starts, $indices));
  }
  $this;
}

package # hide from PAUSE
  PDL::Graphics::TriD::DrawMulti;
use base qw/PDL::Graphics::TriD::GObject/;
use fields qw/Mode Counts Starts Indices/;
sub cdummies { $_[1]->dummy(1, $_[2]->dim(1)) }
sub r_type {""}
sub get_valid_options { +{
  UseDefcols => 0,
  Lighting => 0,
}}
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my ($class, $points, $colors, $mode, $counts, $starts, $indices) = @_;
  my $this = $class->SUPER::new($points, $colors, $options);
  PDL::barf "DrawMulti error: dim mismatch between Points and Colors [@{[$this->{Points}->dims]}] vs [@{[$this->{Colors}->dims]}]"
    if $this->{Points}->ndims != $this->{Colors}->ndims
    or $this->{Points}->dim(1) != $this->{Colors}->dim(1);
  @$this{qw(Mode Counts Starts Indices)} = ($mode, $counts, $starts, $indices);
  $this;
}

package # hide from PAUSE
  PDL::Graphics::TriD::Labels;
use base qw/PDL::Graphics::TriD::GObject/;
use fields qw/Strings/;
sub get_valid_options { +{
  UseDefcols => 0,
  Lighting => 0,
}}
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my $strings = ref($_[-1]) eq 'ARRAY' ? pop : PDL::barf "Labels: no strings given";
  my ($class, $points, $colors) = @_;
  my $this = $class->SUPER::new($points, $colors, $options);
  $points = $this->{Points};
  my $num_points = $points->nelem / $points->dim(0);
  PDL::barf "Labels: got @{[0+@$strings]} strings (@$strings) but $num_points points (@{[$points->info]}" if @$strings != $num_points;
  @$this{qw(Strings)} = $strings;
  $this;
}
sub set_labels {
  my ($this, $strings) = @_;
  my $num_points = $this->{Points}->nelem / $this->{Points}->dim(0);
  PDL::barf "Labels: got @{[0+@$strings]} strings but $num_points points" if @$strings != $num_points;
  $this->{Strings} = $strings;
}

package # hide from PAUSE
  PDL::Graphics::TriD::Arrows;
use base qw/PDL::Graphics::TriD::Object/;
sub r_type { return "";}
sub get_valid_options { +{
  UseDefcols => 0,
  FromTo => [],
  ArrowWidth => 0.02,
  ArrowLen => 0.1,
  Lighting => 0,
}}
sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : $_[0]->get_valid_options;
  my ($class, $points, $colors) = @_;
  my $this = $class->SUPER::new($options);
  $options = $this->{Options};
  my ($fromto, $w, $hl) = delete @$options{qw(FromTo ArrowWidth ArrowLen)};
  $points = $this->normalise_as($class->r_type,$points);
  $this->add_object(PDL::Graphics::TriD::Lines->new(
    $points->dice_axis(1,$fromto->flat),
    $colors, $options
  ));
  my ($tv, $ti) = PDL::Graphics::OpenGLQ::gen_arrowheads($points->flowing,$fromto,
    $hl, $w);
  $this->add_object(PDL::Graphics::TriD::Triangles->new($tv, $ti, $colors, { %$options, Shading=>0 }));
  $this;
}

1;
