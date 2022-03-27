=head1 NAME

PDL::Graphics::TriD::Objects - Simple Graph Objects for TriD

=head1 SYNOPSIS

Look in PDL/Demos/TkTriD_demo.pm for several examples, the code
in PDL/Demos/TriD1.pm and PDL/Demos/TriD2.pm also uses objects
but it hides them from the user.

=head1 DESCRIPTION

GObjects can be either stand-alone or in Graphs, scaled properly.
All the points used by the object must be in the member {Points}.
I guess we can afford to force data to be copied (X,Y,Z) -> (Points)...

=head1 OBJECTS

=head2 PDL::Graphics::TriD::GObject

Inherits from base PDL::Graphics::TriD::Object and adds fields Points, Colors and
Options.  Need lots more here...

=cut

package PDL::Graphics::TriD::GObject;
use strict;
use warnings;
use base qw/PDL::Graphics::TriD::Object/;
use fields qw/Points Colors Options/;

$PDL::Graphics::TriD::verbose //= 0;

sub new {
	my($type,$points,$colors,$options) = @_;
	print "GObject new.. calling SUPER::new...\n" if($PDL::Graphics::TriD::verbose);
	my $this = $type->SUPER::new();
	print "GObject new - back (SUPER::new returned $this)\n" if($PDL::Graphics::TriD::verbose);
	if(!defined $options and ref $colors eq "HASH") {
		$options = $colors;
		undef $colors;
	}
	$options = { $options ? %$options : () };
	$options->{UseDefcols} = 1 if !defined $colors; # for VRML efficiency
	$this->{Options} = $options;
	$this->check_options;
	print "GObject new - calling realcoords\n" if($PDL::Graphics::TriD::verbose);
	$this->{Points} = $points = PDL::Graphics::TriD::realcoords($type->r_type,$points);
	print "GObject new - back from  realcoords\n" if($PDL::Graphics::TriD::verbose);
	$this->{Colors} = defined $colors
	  ? PDL::Graphics::TriD::realcoords("COLOR",$colors)
	  : $this->cdummies(PDL->pdl(1,1,1),$points);
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
	die "Invalid options left: @invalid" if @invalid;
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

sub get_valid_options { +{UseDefcols => 0} }
sub get_points { $_[0]{Points} }
sub cdummies { $_[1] }
sub r_type { "" }
sub defcols { $_[0]{Options}{UseDefcols} }

# In the future, have this happen automatically by the ndarrays.
sub data_changed {
	my($this) = @_;
	$this->changed();
}

package PDL::Graphics::TriD::Points;
use base qw/PDL::Graphics::TriD::GObject/;
sub get_valid_options {
	return {UseDefcols => 0, PointSize=> 1};
}

package PDL::Graphics::TriD::Spheres;
use base qw/PDL::Graphics::TriD::GObject/;
# need to add radius
sub get_valid_options {
  +{UseDefcols => 0, PointSize=> 1}
}

package PDL::Graphics::TriD::Lines;
use base qw/PDL::Graphics::TriD::GObject/;
sub cdummies { return $_[1]->dummy(1); }
sub r_type { return "SURF2D";}
sub get_valid_options { return {UseDefcols => 0, LineWidth => 1}; }

package PDL::Graphics::TriD::LineStrip;
use base qw/PDL::Graphics::TriD::GObject/;
sub cdummies { return $_[1]->dummy(1); }
sub r_type { return "SURF2D";}
sub get_valid_options { return {UseDefcols => 0, LineWidth => 1}; }

###########################################################################
################# JNK 15mar11 added section start #########################
# JNK 06dec00 -- edited from PDL::Graphics/TriD/GObject in file Objects.pm
# GObjects can be either stand-alone or in Graphs, scaled properly.
# All the points used by the object must be in the member {Points}.
# I guess we can afford to force data to be copied (X,Y,Z) -> (Points)...
# JNK:  I don't like that last assumption for all cases..

# JNK 27nov00 new object type:
package PDL::Graphics::TriD::GPObject;
use base qw/PDL::Graphics::TriD::GObject/;
sub new {
  my($type,$points,$faceidx,$colors,$options) = @_;
  # faceidx is 2D pdl of indices into points for each face
  if(!defined $options and ref $colors eq "HASH") {
    $options = $colors;undef $colors; } 
  $points = PDL::Graphics::TriD::realcoords($type->r_type,$points);
  my $faces = $points->dice_axis(1,$faceidx->clump(-1))->splitdim(1,3);
  # faces is 3D pdl slices of points, giving cart coords of face verts
  if(!defined $colors) { $colors = PDL->pdl(1,1,1);
    $colors = $type->cdummies($colors,$faces);
    $options->{ UseDefcols } = 1; } # for VRML efficiency
  else { $colors = PDL::Graphics::TriD::realcoords("COLOR",$colors); }
  my $this = bless { Points => $points, Faceidx => $faceidx, Faces => $faces,
                     Colors => $colors, Options => $options},$type;
  $this->check_options;
  $this;
}
sub get_valid_options { { UseDefcols=>0, Lines=>0, Smooth=>1 } }
sub cdummies {
  return $_[1]->dummy(1,$_[2]->getdim(2))->dummy(1,$_[2]->getdim(1)); }

# JNK 13dec00 new object type:
package PDL::Graphics::TriD::STrigrid_S;
use base qw/PDL::Graphics::TriD::GPObject/;
sub cdummies {
  return $_[1]->dummy(1,$_[2]->getdim(2))->dummy(1,$_[2]->getdim(1)); }
sub new {
  my ($class,$points,$faceidx,$colors,$options) = @_;
  my $this = $class->SUPER::new($points,$faceidx,$colors,$options);
  $this->{Normals} //= $this->smoothn($this->{Points}) if $this->{Options}{Smooth};
  $this;
}
# calculate smooth normals
sub smoothn { my ($this,$ddd) = @_;
  my $v=$this->{Points};my $f=$this->{Faces};my $fvi=$this->{Faceidx};
# ----------------------------------------------------------------------------
  my @p = map { $f->slice(":,($_),:") } (0..(($fvi->dims)[0]-1));
# ----------------------------------------------------------------------------
  # the following line assumes all faces are triangles
  my $fn = ($p[1]-$p[0])->crossp($p[2]-$p[1])->norm;
#   my $vfi = PDL::cat(map {PDL::cat(PDL::whichND($fvi==$_))->slice(':,(1)')}
#                          (0..(($v->dims)[1]-1)));
# the above, spread into several statements:
#   my @vfi2=();for my $idx (0..($v->dims)[1]-1) {
#     my @vfi0=PDL::whichND($fvi==$idx);
#     my $vfi1=PDL::cat(@vfi0);
#     $vfi2[$idx]=$vfi1->slice(':,(1)'); }
#   my $vfi=PDL::cat(@vfi2);
#   my $vmn = $fn->dice_axis(1,$vfi->clump(-1))->splitdim(1,($fvi->dims)[0]);
#   my $vn = $vmn->mv(1,0)->sumover->norm;
# ----------------------------------------------------------------------------
  my $vn=PDL::cat(
    map { my $vfi=PDL::cat(PDL::whichND($fvi==$_))->slice(':,(1)');
          $fn->dice_axis(1,$vfi)->mv(1,0)->sumover->norm }
        0..($v->dim(1)-1) );
# ----------------------------------------------------------------------------
  return $vn;
}
# JNK 06dec00 new object type:
package PDL::Graphics::TriD::STrigrid;
use base qw/PDL::Graphics::TriD::GPObject/;
sub cdummies { # copied from SLattice_S; not yet modified...
  # called with (type,colors,faces)
  return $_[1]->dummy(1,$_[2]->getdim(2))->dummy(1,$_[2]->getdim(1)); }
sub get_valid_options { { UseDefcols => 0, Lines => 1, Smooth => 1 } }

################# JNK 15mar11 added section finis #########################
###########################################################################   

package PDL::Graphics::TriD::GObject_Lattice;
use base qw/PDL::Graphics::TriD::GObject/;
sub r_type {return "SURF2D";}
sub get_valid_options { return {UseDefcols => 0,Lines => 1}; }

package PDL::Graphics::TriD::Lattice;
use base qw/PDL::Graphics::TriD::GObject_Lattice/;
sub cdummies { return $_[1]->dummy(1)->dummy(1); }

# colors associated with surfaces
package PDL::Graphics::TriD::SCLattice;
use base qw/PDL::Graphics::TriD::GObject_Lattice/;
sub cdummies { return $_[1]->dummy(1,$_[2]->getdim(2)-1)
			-> dummy(1,$_[2]->getdim(1)-1); }

# colors associated with vertices, smooth
package PDL::Graphics::TriD::SLattice;
use base qw/PDL::Graphics::TriD::GObject_Lattice/;
sub cdummies { return $_[1]->dummy(1,$_[2]->getdim(2))
			-> dummy(1,$_[2]->getdim(1)); }

# colors associated with vertices
package PDL::Graphics::TriD::SLattice_S;
use base qw/PDL::Graphics::TriD::GObject_Lattice/;
use fields qw/Normals/;
sub cdummies {
  $_[1]->slice(":," . join ',', map "*$_", ($_[2]->dims)[1,2])
}
sub get_valid_options {
  {UseDefcols => 0,Lines => 1, Smooth => 1}
}
sub new {
  my ($class,$points,$colors,$options) = @_;
  my $this = $class->SUPER::new($points,$colors,$options);
  $this->{Normals} //= $this->smoothn($this->{Points}) if $this->{Options}{Smooth};
  $this;
}
# calculate smooth normals
sub smoothn {
  my ($this,$p) = @_;
  # coords of parallel sides (left and right via 'lags')
  my $trip = $p->lags(1,1,2)->slice(':,:,:,1:-1') -
		$p->lags(1,1,2)->slice(':,:,:,0:-2');
  # coords of diagonals with dim 2 having original and reflected diags
  my $tmp;
  my $trid = ($p->slice(':,0:-2,1:-1')-$p->slice(':,1:-1,0:-2'))
		    ->dummy(2,2);
  # $ortho is a (3D,x-1,left/right triangle,y-1) array that enumerates
  # all triangles
  my $ortho = $trip->crossp($trid);
  $ortho->norm($ortho); # normalise inplace
  # now add to vertices to smooth
  my $aver = ref($p)->zeroes($p->dims);
  # step 1, upper right tri0, upper left tri1
  ($tmp=$aver->lags(1,1,2)->slice(':,:,:,1:-1')) += $ortho;
  # step 2, lower right tri0, lower left tri1
  ($tmp=$aver->lags(1,1,2)->slice(':,:,:,0:-2')) += $ortho;
  # step 3, upper left tri0
  ($tmp=$aver->slice(':,0:-2,1:-1')) += $ortho->slice(':,:,(0)');
  # step 4, lower right tri1
  ($tmp=$aver->slice(':,1:-1,0:-2')) += $ortho->slice(':,:,(1)');
  $aver->norm($aver);
  return $aver;
}

1;
