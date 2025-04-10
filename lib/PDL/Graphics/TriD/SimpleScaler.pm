# a very simple unsophisticated scaler that
# takes advantage of the nice infrastructure provided by TJL
# controls 3-D window scaling
# when you drag the mouse in the display window.
package PDL::Graphics::TriD::SimpleScaler;

use strict;
use warnings;
use base qw/PDL::Graphics::TriD::ButtonControl/;
use fields qw/DistRef/;

$PDL::Graphics::TriD::verbose //= 0;

sub new {
  my($type,$win,$dist) = @_;

  my $this = $type->SUPER::new( $win);

  $this->{DistRef} = $dist;
  $win->add_resizecommand(sub {print "Resized window: ",join(",",@_),"\n" if $PDL::Graphics::TriD::verbose;  $this->set_wh(@_); });
  return $this;
}

# coordinates normalised relative to center
sub xy2norm {
	my($this,$x,$y) = @_;
	print "xy2norm: this->{W}=$this->{W}; this->{H}=$this->{H}; this->{SC}=$this->{SC}\n" if($PDL::Graphics::TriD::verbose);
	$x -= $this->{W}/2; $y -= $this->{H}/2;
	$x /= $this->{SC}; $y /= $this->{SC};
	return ($x,$y);
}

sub mouse_moved {
	my($this,$x0,$y0,$x1,$y1) = @_;
	${$this->{DistRef}} *=
	  $this->xy2fac($this->xy2norm($x0,$y0),$this->xy2norm($x1,$y1));
}

# x,y to distance from center
sub xy2fac {
	my($this,$x0,$y0,$x1,$y1) = @_;
	my $dy = $y0-$y1;
	return $dy>0 ? 1+2*$dy : 1/(1-2*$dy);
}

1;
