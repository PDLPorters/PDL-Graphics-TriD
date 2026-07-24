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
  $_->init_scale() for values %{$this->{Axis}};
  while (my ($series_name,$v) = each %{$this->{DataBind}}) {
    for my $bound (@$v) {
      my ($axis, $axes) = @$bound;
      for my $data (values %{ $this->{Data}{$series_name} }) {
        $this->{Axis}{$axis}->add_scale($data->get_points, $axes);
      }
    }
  }
  $_->finish_scale() for values %{$this->{Axis}};
}

sub get_points {
  my ($this,$name,$data) = @_;
  my $d = $data->get_points;
  my @ddims = $d->dims; shift @ddims;
  my $p = PDL->zeroes(PDL::float(),3,@ddims);
  for (@{$this->{DataBind}{$name}}) {
    my ($axisname, $indices) = @$_;
    my $axis = $this->{Axis}{$axisname} // die "Axis not defined: $axisname";
# Transform can return the same or a different ndarray.
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
our $default_axis_class = 'PDL::Graphics::TriD::EuclidAxes';
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
  PDL::Graphics::TriD::AxesBase;
use base qw(PDL::Graphics::TriD::Object);
use fields qw(NDiv AxisLabelsObj Bounds);
sub new {
  my $this = $_[0]->SUPER::new(@_[1..$#_]);
  $this->{NDiv} = $this->{Options}{NDiv};
  $this;
}
sub normalise_scale { # Normalize the smallest differences away.
  my ($this) = @_;
  my ($min, $max) = $this->{Bounds}->dog;
  my $diff = $max - $min;
  my ($got_smalldiff, $got_bigdiff) = PDL::which_both(abs($diff) < 1e-6);
  $max->dice_axis(0, $got_smalldiff) .= $min->dice_axis(0, $got_smalldiff) + 1;
  ($min, $max);
}
sub re_minmax {
  my ($this, $data) = @_;
  my $to_minmax = $data->clump(1..$data->ndims-1); # xyz,...
  $to_minmax = $to_minmax->glue(1, $this->{Bounds}); # include old min/max
  $to_minmax->transpose->minmaxover; # each min, max is xyz
}
sub gen_stalk_labels {
  my ($this, $starts, $dimnot, $stalk_scale) = @_;
  my $end_offset = PDL::float('[[0 1 1]]')->dup(1,$starts->dim(1))->rotate($dimnot);
  my $ends = $starts + $end_offset * -$stalk_scale;
  my $line_points = $starts->append($ends)->splitdim(0,3)->clump(1,2);
  my $labels_obj = PDL::Graphics::TriD::Labels->new($ends, [('') x $ends->dim(1)]);
  ($line_points, $labels_obj);
}
sub get_valid_options { +{
  NDiv => 4,
}}

package # hide from PAUSE
  PDL::Graphics::TriD::EuclidAxes;
use base qw(PDL::Graphics::TriD::AxesBase);
use fields qw(Transform);
use PDL;
use PDL::Transform;

sub get_valid_options { +{
  %{ $_[0]->SUPER::get_valid_options },
  Names => [qw(X Y Z)],
}}

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
  $this->add_object(PDL::Graphics::TriD::Labels->new($id3, $options->{Names}));
  $this->add_object(PDL::Graphics::TriD::Lines->new($points->glue(1, $line_points)));
  $this->add_object($this->{AxisLabelsObj} = $labels_obj);
  $this;
}

sub init_scale {
  my ($this) = @_;
  $this->{Bounds} = undef;
}

sub add_scale {
  my ($this,$data,$inds) = @_;
  PDL::barf "no \$inds given" if !defined $inds;
  $this->{Bounds} = PDL->pdl($this->re_minmax($data->dice_axis(0, $inds))); # xyz,minmax
}

sub finish_scale {
  my ($this) = @_;
  my ($min, $max) = $this->normalise_scale;
  $this->{Transform} = t_linear(pre => -$min, s => 1/($max - $min));
  my $axisvals = ylinvals(PDL::float(),$min,$max,3,$this->{NDiv}+1);
  $this->{AxisLabelsObj}->set_labels([map sprintf("%.3f", $_), $axisvals->t->list]);
}

sub transform {
  my ($this,$point,$data,$inds) = @_;
  PDL::barf "no \$inds given" if !defined $inds;
  $point->slice("0:$#$inds") += $this->{Transform}->apply($data->dice_axis(0, $inds));
  $point;
}

package # hide from PAUSE
  PDL::Graphics::TriD::FaceAxes;
use base qw(PDL::Graphics::TriD::AxesBase);
use fields qw(LatticeObj Names Center AxisLinesObj);
use PDL;
sub add_lattice_axis {
  my ($this) = @_;
  my $ndiv = $this->{NDiv};
  # can be changed to topo heights?
  my $verts = zeroes(PDL::float(),3,(2*$ndiv+1) x 2);
  $verts->slice("2") .= 1012.5;
  $verts->slice($_)->inplace->axislinvals($_+1,$this->{Bounds}->slice($_)->list) for 0,1;
  my $tverts = $this->transform($verts->zeroes,$verts,[0,1,2]);
  $this->delete_object($this->{LatticeObj}) if $this->{LatticeObj};
  $this->add_object($this->{LatticeObj} = PDL::Graphics::TriD::Lattice->new($tverts, {Shading=>0}));
  my $starts = $tverts->slice(",::2,(0)");
  $starts = $starts->glue(1,$tverts->slice(",(0),::2"));
  my ($line_points, $labels_obj) = $this->gen_stalk_labels(
    $starts,
    yvals(PDL::float(), $ndiv+1, 2)->flat,
    0.1,
  );
  $this->delete_object($_) for grep $_, @$this{qw(AxisLinesObj AxisLabelsObj)};
  $this->add_object($this->{AxisLinesObj} = PDL::Graphics::TriD::Lines->new($line_points));
  $this->add_object($this->{AxisLabelsObj} = $labels_obj);
  my $xlabels = $verts->slice("(0),::2,(0)");
  my $ylabels = $verts->slice("(1),(0),::2");
  $this->{AxisLabelsObj}->set_labels([map sprintf("%.3f", $_), $xlabels->list, $ylabels->list]);
}

# Is actually a Sinusoidal projection despite name
# x & y in degrees, z = value
# to try:
# make && perl -Mblib -MPDL -MPDL::Graphics::TriD -e '$PDL::Graphics::TriD::Graph::default_axis_class = "PDL::Graphics::TriD::CylindricalEquidistantAxes"; spheres3d pdl("-80 -80 800; 80 80 900")'
package # hide from PAUSE
  PDL::Graphics::TriD::CylindricalEquidistantAxes;
use base qw(PDL::Graphics::TriD::FaceAxes);
use PDL::Core qw(barf float);
use PDL::Constants qw(DEGRAD);
use constant DEG2RAD => 1/DEGRAD;

sub new {
  my ($type) = @_;
  my $self = $type->SUPER::new;
  $self->{Names} = [qw(LON LAT Pressure)];
  $self;
}

sub init_scale {
  my ($this) = @_;
  $this->{Bounds} = PDL->pdl(PDL::float(), 'BAD BAD 100; BAD BAD 1012.5');
}

sub add_scale {
  my ($this,$data,$inds) = @_;
  barf "no \$inds given" if !defined $inds;
  my ($mins, $maxes) = $this->re_minmax($data->dice_axis(0, $inds)); # each is xyz
  if ($maxes->slice(1) >= 90 or $mins->slice(1) <= -90) {
    barf "Error in Latitude ", $maxes->slice(1), " ", $mins->slice(1);
  }
  $this->{Bounds} = PDL->pdl($mins, $maxes); # xyz,minmax
# Should make the projection center an option
  $this->{Center} = float([($maxes + $mins)->slice("(0)")/2, 0]);
}

sub finish_scale {
  my ($this) = @_;
  $this->{Bounds} = PDL->pdl(PDL::float(), $this->normalise_scale);
  $this->add_lattice_axis;
}

sub transform {
  my ($this,$point,$data,$inds) = @_;
  barf "no \$inds given" if !defined $inds;
  barf "Wrong number of arguments to transform $this\n" if @$inds != 3;
  my $range2 = $this->{Bounds}->t->diff2->t->slice('0:1');
  my $pressure_max = $this->{Bounds}->slice('2,0');
  $data = $data->dice_axis(0, $inds);
  my $data01_ctr = ($data->slice("0:1")-$this->{Center}) / $range2;
  $point->slice("(0)") +=
    0.5+$data01_ctr->slice("(0)")
	*cos($data->slice("(1)")*DEG2RAD);
  $point->slice("(1)") +=
    0.5+$data01_ctr->slice("(1)");
  $point->slice("(2)") .=
    log($data->slice("(2)")/1012.5)/log($pressure_max/1012.5);
  $point;
}

# Despite name (which is like the UN map), is actually Spherical or Orthographic-style projection
# try this:
# make && perl -Mblib -MPDL -MPDL::Graphics::TriD -e '$PDL::Graphics::TriD::Graph::default_axis_class = "PDL::Graphics::TriD::PolarStereoAxes"; spheres3d pdl("-80 -80 800; 80 80 900")'
package # hide from PAUSE
  PDL::Graphics::TriD::PolarStereoAxes;
use base qw(PDL::Graphics::TriD::FaceAxes);
use PDL::Core qw(barf float);
use PDL::Constants qw(DEGRAD);
use constant DEG2RAD => 1/DEGRAD;

sub new {
  my ($type) = @_;
  my $self = $type->SUPER::new;
  $self->{Names} = [qw(LONGITUDE LATITUDE HEIGHT)];
  $self;
}

sub init_scale {
  my ($this) = @_;
  $this->{Bounds} = PDL->pdl(PDL::float(), 'BAD BAD 100; BAD BAD 1012.5');
}

sub add_scale {
  my ($this,$data,$inds) = @_;
  barf "no \$inds given" if !defined $inds;
  my ($mins, $maxes) = $this->re_minmax($data->dice_axis(0, $inds)); # each is xyz
  if ($maxes->slice(1) >= 90 or $mins->slice(1) <= -90) {
    barf "Error in Latitude ", $maxes->slice(1), " ", $mins->slice(1);
  }
  $this->{Bounds} = PDL->pdl($mins, $maxes); # xyz,minmax
  $this->{Center} = (($maxes + $mins)/2)->slice("0:1");
}

sub finish_scale {
  my ($this) = @_;
  $this->{Bounds} = PDL->pdl(PDL::float(), $this->normalise_scale);
  $this->add_lattice_axis;
}

sub transform {
  my ($this,$point,$data,$inds) = @_;
  barf "no \$inds given" if !defined $inds;
  my $i = 0;
  barf "Wrong number of arguments to transform $this\n" if @$inds != 3;
  $data = $data->dice_axis(0, $inds);
  my $range2 = $this->{Bounds}->t->diff2->t->slice('0:1');
  my $pressure_max = $this->{Bounds}->slice('2,0');
  my $data01_ctr = ($data->slice("0:1")-$this->{Center}) / $range2;
  $point->slice("(0)") +=
    0.5+$data01_ctr->slice("(0)")
	*cos($data->slice("(1)")*DEG2RAD);
  $point->slice("(1)") +=
    0.5+$data01_ctr->slice("(1)")
	*cos($data->slice("(1)")*DEG2RAD);
# Longitude transformation
#  $point->slice("(0)") =
#    ($this->{Center}[0]-$point->slice("(0)"))*cos($data->slice("(1)"));
# Latitude transformation
#  $point->slice("(1)") =
#    ($this->{Center}[1]-$data->slice("(1)"))*cos($data->slice("(1)"));
# Vertical transformation
#  -7.2*log($data->slice("(2)")/1012.5
  $point->slice("(2)") .=
    log($data->slice("(2)")/1012.5)/log($pressure_max/1012.5);
  $point;
}

1;
