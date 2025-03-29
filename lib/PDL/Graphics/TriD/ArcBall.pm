###################################################
#
#	ArcBall.pm
#
# 	From Graphics Gems IV.
#
# This is an example of the controller class:
# the routines set_wh and mouse_moved are the standard routines.
#
# This needs a faster implementation (?)

package PDL::Graphics::TriD::QuaterController;
use strict;
use warnings;
use base qw(PDL::Graphics::TriD::ButtonControl);
use fields qw /Inv Quat/;

$PDL::Graphics::TriD::verbose //= 0;

sub new {
  my($type,$win,$inv,$quat) = @_;
  my $this = $type->SUPER::new($win);
  $this->{Inv} = $inv;
  $this->{Quat} = (defined($quat) ? $quat :
			PDL::Graphics::TriD::Quaternion->new(1,0,0,0));
  $win->add_resizecommand(sub {$this->set_wh(@_)});
  return $this;
}

sub xy2qua {
	my($this,$x,$y) = @_;
	$x -= $this->{W}/2; $y -= $this->{H}/2;
	$y = -$y;
	return $this->normxy2qua($x,$y);
}

sub mouse_moved {
	my($this,$x0,$y0,$x1,$y1) = @_;
	# Copy the size of the owning viewport to our size, in case it changed
	@$this{qw(H W)} = @{$this->{Win}}{qw(H W)};
	if ($PDL::Graphics::TriD::verbose) {
	  print "QuaterController: mouse-moved: $this: $x0,$y0,$x1,$y1,$this->{W},$this->{H},$this->{SC}\n";
	  if ($PDL::Graphics::TriD::verbose > 1) {
	    print "\tthis is:\n";
	    foreach my $k(sort keys %$this) {
	      print "\t$k\t=>\t$this->{$k}\n";
	    }
	  }
	}
# Convert both to quaternions.
	my ($qua0,$qua1) = ($this->xy2qua($x0,$y0),$this->xy2qua($x1,$y1));
	my $arc = $qua1->multiply($qua0->invert());
	if ($this->{Inv}) {
		$arc->invert_rotation_this();
	}
	$this->{Quat}->set($arc->multiply($this->{Quat}));
	1;  # signals a refresh
}

# Original ArcBall
#
package PDL::Graphics::TriD::ArcBall;
use base qw/PDL::Graphics::TriD::QuaterController/;

# x,y to unit quaternion on the sphere.
sub normxy2qua {
	my($this,$x,$y) = @_;
	$x /= $this->{SC}; $y /= $this->{SC};
	my $dist = sqrt ($x ** 2 + $y ** 2);
	if($dist > 1.0) {$x /= $dist; $y /= $dist; $dist = 1.0;}
	my $z = sqrt(1-$dist**2);
	return PDL::Graphics::TriD::Quaternion->new(0,$x,$y,$z);
}

# Tjl's version: a cone - more even change of
package PDL::Graphics::TriD::ArcCone;

use base qw/PDL::Graphics::TriD::QuaterController/;

# x,y to unit quaternion on the sphere.
sub normxy2qua {
	my($this,$x,$y) = @_;
	$x /= $this->{SC}; $y /= $this->{SC};
	my $dist = sqrt ($x ** 2 + $y ** 2);
	if($dist > 1.0) {$x /= $dist; $y /= $dist; $dist = 1.0;}
	my $z = 1-$dist;
	my $qua = PDL::Graphics::TriD::Quaternion->new(0,$x,$y,$z);
	$qua->normalize_this();
	return $qua;
}

# Tjl's version2: a bowl -- angle is proportional to displacement.
package PDL::Graphics::TriD::ArcBowl;

use base qw/PDL::Graphics::TriD::QuaterController/;

# x,y to unit quaternion on the sphere.
sub normxy2qua {
	my($this,$x,$y) = @_;
	$x /= $this->{SC}; $y /= $this->{SC};
	my $dist = sqrt ($x ** 2 + $y ** 2);
	if($dist > 1.0) {$x /= $dist; $y /= $dist; $dist = 1.0;}
	my $z = cos($dist*3.142/2);
	my $qua = PDL::Graphics::TriD::Quaternion->new(0,$x,$y,$z);
	$qua->normalize_this();
	return $qua;
}

1;
