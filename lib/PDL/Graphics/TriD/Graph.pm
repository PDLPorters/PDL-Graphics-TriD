package PDL::Graphics::TriD::Graph;

=head1 NAME

PDL::Graphics::TriD::Graph - PDL 3D graph object with axes

=head1 SYNOPSIS

  use PDL::Graphics::TriD;
  use PDL::Graphics::TriD::Graph;
  $g = PDL::Graphics::TriD::Graph->new;
  $g->default_axes;
  $g->add_dataseries(PDL::Graphics::TriD::Lattice->new($y,$c), "lat0");
  $g->bind_default("lat0");
  $g->add_dataseries(PDL::Graphics::TriD::LineStrip->new($y+pdl(0,0,1),$c), "lat1");
  $g->bind_default("lat1");
  $g->scalethings;
  $win = PDL::Graphics::TriD::get_current_window();
  $win->clear_objects;
  $win->add_object($g);
  $win->twiddle;

=cut

use strict;
use warnings;
use base qw/PDL::Graphics::TriD::Object/;
use PDL::LiteF;
use PDL::Graphics::TriD::Objects; # axes use Lines etc

use fields qw(Data DataBind UnBound DefaultAxes DefaultAxisName Axis );

sub add_dataseries {
  my ($this, $data, $name, $no_changed) = @_;
  if (!defined $name) {
    $name = "Data0";
    while (defined $this->{Data}{$name}) {$name++;}
    $this->{DataBind}{$name} = [];
    $this->{UnBound}{$name} = 1;
  }
  if ($data->can('contained_objects')) {
    $this->add_dataseries($_, $name, 1) for $data->contained_objects;
  }
  if ($data->can('get_points')) {
    $this->{Data}{$name}{$data} = $data;
    $this->add_object($data);
  }
  $this->changed if !$no_changed;
  $name;
}

sub bind_data {
  my ($this,$dser,$axes,$axis) = @_;
  barf "called with undef \$dser" if !defined $dser;
  push @{$this->{DataBind}{$dser}},[$axis,$axes];
  delete $this->{UnBound}{$dser};
  $this->changed();
}

sub bind_default {
  my ($this,$dser,$axes) = @_;
  $this->bind_data($dser, $axes // $this->{DefaultAxes}, $this->{DefaultAxisName});
}

sub set_axis {
  my ($this,$axis,$name) = @_;
  $this->{Axis}{$name} = $axis;
  $this->changed();
}

# Bind all unbound things here...
sub scalethings {
  my ($this) = @_;
  $this->bind_default($_) for keys %{$this->{UnBound}};
  $_->init_scale for values %{$this->{Axis}};
  while (my ($series_name,$v) = each %{$this->{DataBind}}) {
    for my $bound (@$v) {
      my ($axis, $axes) = @$bound;
      my $axis_obj = $this->{Axis}{$axis};
      for my $data (values %{ $this->{Data}{$series_name} }) {
        $axis_obj->add_scale($data->get_points, $axes);
      }
    }
  }
  $_->finish_scale() for values %{$this->{Axis}};
}

sub get_points {
  my ($this,$name,$data) = @_;
  my $d = $data->get_points;
  my (undef, @ddims) = $d->dims;
  my $p = PDL->zeroes(PDL::float(),3,@ddims);
  for (@{$this->{DataBind}{$name}}) {
    my ($axisname, $indices) = @$_;
    my $axis = $this->{Axis}{$axisname} // die "Axis not defined: $axisname";
# transform can return the same or a different ndarray.
    $p = $axis->transform($p,$d,$indices);
  }
  $p;
}

sub clear_data {
  my ($this) = @_;
  $this->{$_} = {} for qw(Data DataBind UnBound);
  $this->changed;
}

sub delete_data {
  my ($this,$name) = @_;
  delete $this->{$_}{$name} for qw(Data DataBind UnBound);
  $this->changed;
}

our $default_axis = 'Euclid3';
our $default_axis_class = 'PDL::Graphics::TriD::Axes::Euclid';
our $default_indices = [0,1,2];
sub default_axes {
  my ($this) = @_;
  return if $this->{Axis}{$default_axis};
  $this->set_axis($default_axis_class->new(), $default_axis);
  $this->set_default_axis($default_axis, $default_indices);
}

sub set_default_axis {
  my ($this,$name,$axes) = @_;
  $this->{DefaultAxisName} = $name;
  $this->{DefaultAxes} = $axes;
}

sub changed {}

package # hide from PAUSE
  PDL::Graphics::TriD::Axes::Base;
use base qw(PDL::Graphics::TriD::Object);
use fields qw(NDiv Names AxisLabelsObj BoundsIn BoundsOut TransformRaw TransformNorm TransformFinal);
use PDL;
my @COPY_FIELDS = qw(NDiv Names TransformRaw);
sub axis_names { undef }
sub transform_raw { undef }
sub new {
  my $this = $_[0]->SUPER::new(@_[1..$#_]);
  @$this{@COPY_FIELDS} = @{ $this->{Options} }{@COPY_FIELDS};
  $this;
}
sub get_valid_options { +{
  NDiv => 4,
  Names => $_[0]->axis_names,
  TransformRaw => $_[0]->transform_raw,
}}
sub init_scale {
  my ($this) = @_;
  $this->{BoundsOut} = $this->{BoundsIn} = undef;
}
sub validate_scale {}
sub normalise_scale { # Normalize the smallest differences away.
  my ($this) = @_;
  my ($min, $max) = $this->{BoundsIn}->dog;
  my $diff = $max - $min;
  my ($got_smalldiff, $got_bigdiff) = PDL::which_both(abs($diff) < 1e-6);
  $max->dice_axis(0, $got_smalldiff) .= $min->dice_axis(0, $got_smalldiff) + 1;
  ($min, $max);
}
sub re_minmax {
  my ($this, $data, $already) = @_;
  my $to_minmax = $data->clump(1..$data->ndims-1); # xyz,...
  $to_minmax = PDL::glue(1, $to_minmax, $already); # include old min/max
  ($to_minmax->transpose->minmaxover)[0,1]; # each min, max is xyz
}
sub gen_stalk_labels {
  my ($this, $starts, $dimnot, $stalk_scale) = @_;
  my $end_offset = PDL::float('[[0 1 1]]')->dup(1,$starts->dim(1))->rotate($dimnot);
  my $ends = $starts + $end_offset * -$stalk_scale;
  my $line_points = $starts->append($ends)->splitdim(0,3)->clump(1,2);
  my $labels_obj = PDL::Graphics::TriD::Labels->new($ends, [('') x $ends->dim(1)]);
  ($line_points, $labels_obj);
}
sub transform {
  my ($this,$point,$data,$inds) = @_;
  PDL::barf "no \$inds given" if !defined $inds;
  $point->slice("0:$#$inds") += $this->{TransformFinal}->apply($data->dice_axis(0, $inds));
  $point;
}

package # hide from PAUSE
  PDL::Graphics::TriD::Axes::Euclid;
use base qw(PDL::Graphics::TriD::Axes::Base);
use PDL;
use PDL::Transform;
sub axis_names { [qw(X Y Z)] }

sub new {
  my $this = $_[0]->SUPER::new(@_[1..$#_]);
  my ($options, $ndiv) = @$this{qw(Options NDiv)};
  my $starts = ylinvals(PDL::float(),0,1,1,$ndiv+1)->append(zeroes(PDL::float(),2));
  my $dupseq = yvals($ndiv+1,3)->flat;
  my ($line_points, $labels_obj) = $this->gen_stalk_labels(
    $starts->dup(1,3)->rotate($dupseq),
    $dupseq,
    0.1,
  );
  my $points = zeroes(PDL::float(),3,3)->append(my $id3 = identity(3))->splitdim(0,3)->clump(1,2);
  $this->add_object(PDL::Graphics::TriD::Labels->new($id3, $this->{Names}));
  $this->add_object(PDL::Graphics::TriD::Lines->new($points->glue(1, $line_points)));
  $this->add_object($this->{AxisLabelsObj} = $labels_obj);
  $this;
}

sub add_scale {
  my ($this,$data,$inds) = @_;
  PDL::barf "no \$inds given" if !defined $inds;
  $data = $data->dice_axis(0, $inds);
  my ($mins, $maxes) = $this->re_minmax($data, $this->{BoundsIn}); # each is xyz
  $this->validate_scale($mins, $maxes);
  $this->{BoundsOut} = $this->{BoundsIn} = PDL->pdl($mins, $maxes); # xyz,minmax
  ($mins, $maxes); # for BoundsOut
}

sub finish_scale {
  my ($this) = @_;
  my ($min, $max) = $this->normalise_scale;
  $this->{TransformNorm} = $this->{TransformFinal} = t_linear(pre => -$min, s => 1/($max - $min));
  my $axisvals = ylinvals(PDL::float(),$min,$max,3,$this->{NDiv}+1);
  $this->{AxisLabelsObj}->set_labels([map sprintf("%.3f", $_), $axisvals->t->list]);
}

package # hide from PAUSE
  PDL::Graphics::TriD::Axes::Face;
use base qw(PDL::Graphics::TriD::Axes::Base);
use fields qw(LatticeObj AxisLinesObj);
use PDL;
use PDL::Transform;
sub validate_scale {
  my ($this, $mins, $maxes) = @_;
  if ($maxes->slice(1) >= 90 or $mins->slice(1) <= -90) {
    barf "Error in Latitude ", $maxes->slice(1), " ", $mins->slice(1);
  }
}
sub add_scale {
  my ($this,$data,$inds) = @_;
  barf "no \$inds given" if !defined $inds;
  $data = $data->dice_axis(0, $inds);
  my ($mins, $maxes) = $this->re_minmax($data, $this->{BoundsIn}); # each is xyz
  $this->validate_scale($mins, $maxes);
  $this->{BoundsIn} = PDL->pdl($mins, $maxes); # xyz,minmax
  ($mins, $maxes) = $this->re_minmax($this->{TransformRaw}->apply($data), $this->{BoundsOut});
  $this->{BoundsOut} = PDL->pdl($mins, $maxes);
  $this->{TransformNorm} = t_linear(pre => -$mins, s => 1/($maxes - $mins));
  $this->{TransformFinal} = $this->{TransformNorm} x $this->{TransformRaw};
  ($mins, $maxes); # for BoundsOut
}
sub finish_scale {
  my ($this) = @_;
  $this->{BoundsIn} = PDL->pdl(PDL::float(), my ($mins_in, $maxes_in) = $this->normalise_scale);
  my $ndiv = $this->{NDiv};
  # can be changed to topo heights?
  my $verts = zeroes(PDL::float(),3,(2*$ndiv+1) x 2);
  $verts->slice("2") .= $mins_in->slice('2');
  $verts->slice($_)->inplace->axislinvals($_+1,$this->{BoundsIn}->slice($_)->list) for 0,1;
  $this->add_scale($verts, [0..2]);
  my $tverts = $this->transform($verts->zeroes,$verts,[0,1,2]);
  $this->delete_object($_) for grep $_, @$this{qw(LatticeObj AxisLinesObj AxisLabelsObj)};
  $this->add_object($this->{LatticeObj} = PDL::Graphics::TriD::Lattice->new($tverts, {Shading=>0}));
  my $starts = $tverts->slice(",::2,(0)");
  $starts = $starts->glue(1,$tverts->slice(",(0),::2"));
  my ($line_points, $labels_obj) = $this->gen_stalk_labels(
    $starts,
    yvals(PDL::float(), $ndiv+1, 2)->flat,
    0.1,
  );
  $this->add_object($this->{AxisLinesObj} = PDL::Graphics::TriD::Lines->new($line_points));
  $this->add_object($this->{AxisLabelsObj} = $labels_obj);
  my $xlabels = $verts->slice("(0),::2,(0)");
  my $ylabels = $verts->slice("(1),(0),::2");
  $this->{AxisLabelsObj}->set_labels([map sprintf("%.3f", $_), $xlabels->list, $ylabels->list]);
}

# x & y in degrees, z = value
# to try:
# make && perl -Mblib -MPDL -MPDL::Graphics::TriD -e '$PDL::Graphics::TriD::Graph::default_axis_class = "PDL::Graphics::TriD::Axes::Sinusoidal"; spheres3d pdl("-80 -80 800; 80 80 900")'
package # hide from PAUSE
  PDL::Graphics::TriD::Axes::Sinusoidal;
use base qw(PDL::Graphics::TriD::Axes::Face);
use PDL::Transform::Cartography;
sub axis_names { [qw(LON LAT Pressure)] }
sub transform_raw { t_sinusoidal() }

# try this:
# make && perl -Mblib -MPDL -MPDL::Graphics::TriD -e '$PDL::Graphics::TriD::Graph::default_axis_class = "PDL::Graphics::TriD::Axes::PolarStereo"; spheres3d pdl("-80 80 800; 80 80 900")'
package # hide from PAUSE
  PDL::Graphics::TriD::Axes::PolarStereo;
use base qw(PDL::Graphics::TriD::Axes::Face);
use PDL::Transform::Cartography;
sub axis_names { [qw(LONGITUDE LATITUDE HEIGHT)] }
sub transform_raw { t_stereographic(o=>[0,90]) } # about North Pole

1;
