package PDL::Graphics::TriD::Object;

use strict;
use warnings;
use Scalar::Util qw(weaken);

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
  return PDL::Graphics::TriD::realcoords($as, $what) if !defined $points or defined $what;
  $this->cdummies(PDL->pdl(PDL::float(),1,1,1),$points);
}

sub check_options {
  my ($this) = @_;
  my $opts = $this->get_valid_options();
  $this->{Options} = $opts, return if !$this->{Options};
  print "FETCHOPT: $this ".(join ',',%$opts)."\n" if $PDL::Graphics::TriD::verbose;
  my %newopts = (%$opts, %{$this->{Options}});
  my @invalid = grep !exists $opts->{$_}, keys %newopts;
  die "$this: invalid options left: @invalid" if @invalid;
  $this->{Options} = \%newopts;
}

sub get_valid_options { +{
  UseDefcols => 0,
}}

sub clear_objects {
	my($this) = @_;
	$this->{Objects} = [];
	$this->{IsValid} = 0;
}

sub delete_object {
  my($this,$object) = @_;
  return unless(defined $object && defined $this->{Objects});
  for(0..$#{$this->{Objects}}){
    if($object == $this->{Objects}[$_]){
      splice(@{$this->{Objects}},$_,1);
      redo;
    }
  }
}

sub add_object {
  my ($this,$object) = @_;
  weaken $this;
  push @{$this->{Objects}},$object;
  $this->{IsValid} = 0;
  for(@{$this->{ChangedSub}}) {
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
	my($this) = @_;
	print "CHANGED_FROM_ABOVE\n" if $PDL::Graphics::TriD::verbose;
	$this->changed;
}

sub add_changedsub {
	my($this,$chsub) = @_;
	push @{$this->{ChangedSub}}, $chsub;
	for (@{$this->{Objects}}) {
		$_->add_changedsub($chsub);
	}
}


sub clear {
	my($this) = @_;
	# print "Clear: $this\n";
	for(@{$this->{Objects}}) {
		$_->clear();
	}
	delete $this->{Impl};
	delete $this->{ChangedSub};
	delete $this->{Objects};
}

sub changed {
  my($this) = @_;
  print "VALID0 $this\n" if $PDL::Graphics::TriD::verbose;
  $this->{IsValid} = 0;
  $_->($this) for @{$this->{ChangedSub}};
}

# In the future, have this happen automatically by the ndarrays.
sub data_changed {
  my($this) = @_;
  $this->changed;
  $_->changed for $this->contained_objects;
}

1;
