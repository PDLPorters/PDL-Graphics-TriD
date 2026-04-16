package PDL::Graphics::TriD::Object;

use strict;
use warnings;
use Scalar::Util qw(weaken);
use Carp 'confess';
use PDL::ImageND ();

use fields qw(Objects IsValid ChangedSub Impl Options);

$PDL::Graphics::TriD::verbose //= 0;

sub new {
  my $options = ref($_[-1]) eq 'HASH' ? pop : {};
  my $class = shift;
  my $self = fields::new($class);
  $self->{Options} = $options;
  $self->check_options;
  $self;
}

sub normalise_as {
  my ($this, $as, $what, $points) = @_;
  if (ref $what eq 'REF') {
    die "Given scalar-ref but not as 'COLOR'" if $as ne "COLOR";
    die "Given scalar-ref as 'COLOR' but not to array-ref" if ref $$what ne 'ARRAY';
    die "Given \\[...] as 'COLOR' but not 2 elts" if @$$what != 2;
    die "Given \\[\$x,\$y] as 'COLOR' but at least one is not ndarray" if grep !UNIVERSAL::isa($_, 'PDL'), @$$what;
    my @xdims = $$what->[0]->dims;
    die "Given \\[\$x,\$y] as 'COLOR' but \$x is not float(3,x,y)" if @xdims != 3 or $xdims[0] != 3 or $$what->[0]->type ne 'float';
    my @ydims = $$what->[1]->dims;
    die "Given \\[\$x,\$y] as 'COLOR' but \$y is not float(2,...)" if @ydims < 2 or $ydims[0] != 2 or $$what->[1]->type ne 'float';
    return $what;
  }
  if ($as eq "COLOR" and UNIVERSAL::isa($what, 'PDL') and $what->ndims == 1) {
    die "Given 1D ndarray as colour but no points to match" if !defined $points;
    return $this->cdummies($what->float,$points);
  }
  return realcoords($as, $what) if !defined $points or defined $what;
  $this->cdummies(PDL->pdl(PDL::float(),1,1,1),$points);
}

my %type2func = (
  POLAR2D => sub {
    return @_ if @_ != 1;
    my $t = 6.283 * $_[0]->xvals / ($_[0]->getdim(0)-1);
    my $r = $_[0]->yvals / ($_[0]->getdim(1)-1);
    ($r * sin($t), $r * cos($t), $_[0]);
  },
  SURF2D => sub {
    return @_ if @_ != 1;
    ($_[0]->xvals,$_[0]->yvals,$_[0]); # surf2d -> this is z axis
  },
  COLOR => sub {
    return @_ if @_ != 1;
    @_[0,0,0]; # color -> 1 ndarray = grayscale
  },
  LINE => sub {
    return ($_[0]->xvals, $_[0], 0) if @_ == 1;
    return (@_[0,1], $_[0]->xvals) if @_ == 2;
    @_;
  },
);
sub realcoords {
  my ($type,$c) = @_;
  if (ref $c ne "ARRAY") {
    my $dim0 = $c->getdim(0);
    confess "If one ndarray given for coordinate, must be (2|3,...) or have default interpretation" if $dim0 != 2 and $dim0 != 3;
    return $c->float;
  }
  my @c = @$c;
  if (!ref $c[0]) {$type = shift @c}
  confess "Must have 1..3 array members for coordinates" if !@c || @c>3;
  confess "Must have 3 coordinates if no interpretation (here '$type', known: @{[sort keys %type2func]})" if @c != 3 and !$type2func{$type};
  @c = $type2func{$type}->(@c) if $type2func{$type};
  my $g = PDL::ImageND::combcoords(@c);
  $g->dump if $PDL::Graphics::TriD::verbose;
  $g;
}

sub check_options {
  my ($this) = @_;
  my $opts = $this->get_valid_options();
  $this->{Options} = $opts, return if !$this->{Options};
  print "FETCHOPT: $this ".(join ',',%$opts)."\n" if $PDL::Graphics::TriD::verbose;
  my %newopts = (%$opts, %{$this->{Options}});
  my @invalid = grep !exists $opts->{$_}, keys %newopts;
  confess "$this: invalid options left: @invalid" if @invalid;
  $this->{Options} = \%newopts;
}

sub get_valid_options { +{
  UseDefcols => 0,
}}

sub clear_objects {
	my ($this) = @_;
	$this->{Objects} = [];
	$this->{IsValid} = 0;
}

sub delete_object {
  my ($this,$object) = @_;
  my $ref = $this->{Objects};
  return unless defined $object && defined $ref;
  my @inds = grep $object == $ref->[$_], 0..$#$ref;
  splice @$ref, $_, 1 for reverse @inds;
}

sub add_object {
  my ($this,$object) = @_;
  weaken $this;
  push @{$this->{Objects}},$object;
  $this->{IsValid} = 0;
  for (@{$this->{ChangedSub}}) {
    $object->add_changedsub($_);
  }
  $object->add_changedsub(sub {$this->changed_from_above()});
  $object;
}

sub contained_objects {
  my ($this) = @_;
  $this->{Objects} ? @{$this->{Objects}} : ();
}

sub changed_from_above {
	my ($this) = @_;
	print "CHANGED_FROM_ABOVE\n" if $PDL::Graphics::TriD::verbose;
	$this->changed;
}

sub add_changedsub {
	my ($this,$chsub) = @_;
	push @{$this->{ChangedSub}}, $chsub;
	for (@{$this->{Objects}}) {
		$_->add_changedsub($chsub);
	}
}


sub clear {
	my ($this) = @_;
	# print "Clear: $this\n";
	for (@{$this->{Objects}}) {
		$_->clear();
	}
	delete $this->{Impl};
	delete $this->{ChangedSub};
	delete $this->{Objects};
}

sub changed {
  my ($this) = @_;
  print "VALID0 $this\n" if $PDL::Graphics::TriD::verbose;
  $this->{IsValid} = 0;
  $_->($this) for @{$this->{ChangedSub}};
}

# In the future, have this happen automatically by the ndarrays.
sub data_changed {
  my ($this) = @_;
  $this->changed;
  $_->changed for $this->contained_objects;
}

1;
