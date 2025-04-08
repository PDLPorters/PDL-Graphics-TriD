package PDL::Graphics::TriD::GL::GLX;

use strict;
use warnings;
use OpenGL qw/ :glxconstants /;

our @ISA = qw(PDL::Graphics::TriD::GL);

sub new {
  my ($class,$options,$window_obj) = @_;
  my @db = OpenGL::GLX_DOUBLEBUFFER;
  if ($PDL::Graphics::TriD::offline) {$options->{x} = -1; @db=()}
  $options->{attributes} = [GLX_RGBA, @db,
			    GLX_RED_SIZE,1,
			    GLX_GREEN_SIZE,1,
			    GLX_BLUE_SIZE,1,
			    GLX_DEPTH_SIZE,1,
			    # Alpha size?
			   ] unless defined $options->{attributes};
  $options->{mask} = (KeyPressMask | ButtonPressMask |
			 ButtonMotionMask | ButtonReleaseMask |
			 ExposureMask | StructureNotifyMask |
			 PointerMotionMask) unless defined $options->{mask};
  my $self = $class->SUPER::new($options,$window_obj);
  print STDERR "Creating X11 OO window\n" if $PDL::Graphics::TriD::verbose;
  my $p = $self->{Options};
  my $win = OpenGL::glpcOpenWindow(
     $p->{x},$p->{y},$p->{width},$p->{height},
     $p->{parent},$p->{mask}, $p->{steal}, @{$p->{attributes}});
  @$self{keys %$win} = values %$win;
  $self;
}

sub XPending {
  my ($self) = @_;
  OpenGL::XPending($self->{Display});
}

sub glpXNextEvent {
  my ($self) = @_;
  OpenGL::glpXNextEvent($self->{Display});
}

sub glpRasterFont {
  my ($this,@args) = @_;
  # NOTE: glpRasterFont() will die() if the requested font cannot be found
  #       The new POGL+GLUT TriD implementation uses the builtin GLUT defined
  #       fonts and does not have this failure mode.
  my $lb =  eval { OpenGL::GLX::glpRasterFont(@args[0..2],$this->{Display}) };
  if ( $@ ) {
    die "glpRasterFont: unable to load font (@args), please set PDL_3D_FONT to an existing X11 font. Error:\n$@";
  }
  return $lb;
}

sub swap_buffers {
  my ($this) = @_;
  OpenGL::glXSwapBuffers($this->{Window},$this->{Display});  # Notice win and display reversed [sic]
}

1;
