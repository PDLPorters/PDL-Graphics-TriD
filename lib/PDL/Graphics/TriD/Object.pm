package PDL::Graphics::TriD::Object;

use strict;
use warnings;
use Scalar::Util qw(weaken);

use fields qw(Objects ValidList ChangedSub List Options);

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
	$this->{ValidList} = 0;
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
  $this->{ValidList} = 0;
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
	$this->delete_displist();
	delete $this->{ChangedSub};
	delete $this->{Objects};
}

sub changed {
  my($this) = @_;
  print "VALID0 $this\n" if $PDL::Graphics::TriD::verbose;
  $this->{ValidList} = 0;
  $_->($this) for @{$this->{ChangedSub}};
}

# In the future, have this happen automatically by the ndarrays.
sub data_changed {
  my($this) = @_;
  $this->changed;
  $_->changed for $this->contained_objects;
}

1;
