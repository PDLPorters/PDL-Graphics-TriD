use strict;
use warnings;
no warnings 'redefine';
use OpenGL::Modern qw/
  glMaterialfv_p glColor3d glRotatef glLightModeli
  glLightfv_p glShadeModel glColorMaterial
  glLineWidth glPointSize
  glpSetAutoCheckErrors
  glGenLists glDeleteLists glNewList glEndList glCallList
  glPushAttrib glPopAttrib glMatrixMode glLoadIdentity glOrtho glTranslatef
  glVertexPointer_c glNormalPointer_c glColorPointer_c glDrawElements_c
  glTexCoordPointer_c
  glDrawArrays
  glEnableClientState glDisableClientState
  glEnable glDisable
  glGenTextures_p glBindTexture glDeleteTextures_p
  glTexImage2D_c glTexParameteri
  glGetIntegerv_p
  GL_FRONT_AND_BACK GL_SHININESS GL_SPECULAR GL_AMBIENT GL_DIFFUSE GL_SMOOTH
  GL_FLAT
  GL_LIGHTING_BIT GL_POSITION GL_LIGHTING GL_LIGHT0 GL_LIGHT_MODEL_TWO_SIDE
  GL_COMPILE GL_ENABLE_BIT GL_DEPTH_TEST GL_TRUE
  GL_LINE_STRIP GL_TRIANGLE_STRIP GL_TRIANGLES GL_LINES GL_POINTS GL_LINE_LOOP
  GL_COLOR_MATERIAL GL_MODELVIEW GL_PROJECTION
  GL_RGB GL_FLOAT GL_UNSIGNED_INT GL_UNSIGNED_BYTE
  GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_TEXTURE_MAG_FILTER
  GL_NEAREST GL_CLAMP_TO_EDGE GL_TEXTURE_WRAP_S GL_TEXTURE_WRAP_T
  GL_TEXTURE_BINDING_2D
  GL_VERTEX_ARRAY GL_NORMAL_ARRAY GL_COLOR_ARRAY GL_TEXTURE_COORD_ARRAY
/;
use PDL::Core qw(barf);

sub PDL::Graphics::TriD::Material::togl{
  my $this = shift;
  my $shin = pack "f*",$this->{Shine};
  glMaterialfv_p(GL_FRONT_AND_BACK,GL_SHININESS,$shin);
  my $spec = pack "f*",@{$this->{Specular}};
  glMaterialfv_p(GL_FRONT_AND_BACK,GL_SPECULAR,$spec);
  my $amb = pack "f*",@{$this->{Ambient}};
  glMaterialfv_p(GL_FRONT_AND_BACK,GL_AMBIENT,$amb);
  my $diff = pack "f*",@{$this->{Diffuse}};
  glMaterialfv_p(GL_FRONT_AND_BACK,GL_DIFFUSE,$diff);
}

$PDL::Graphics::TriD::verbose //= 0;

sub PDL::Graphics::TriD::Object::gl_update_list {
  my ($this) = @_;
  glpSetAutoCheckErrors(1);
  glDeleteLists($this->{Impl}{List},1) if $this->{Impl}{List};
  $this->{Impl}{List} = my $lno = glGenLists(1);
  print "GENLIST $this $lno\n" if $PDL::Graphics::TriD::verbose;
  $this->togl_setup;
  glNewList($lno,GL_COMPILE);
  eval {
    $this->togl;
    print "EGENLIST $lno\n" if $PDL::Graphics::TriD::verbose;
  };
  { local $@; glEndList(); }
  die if $@;
  print "VALID1 $this\n" if $PDL::Graphics::TriD::verbose;
  $this->{IsValid} = 1;
}

sub PDL::Graphics::TriD::Object::gl_call_list {
  my($this) = @_;
  print "CALLIST ",$this->{Impl}{List}//'undef',"!\n" if $PDL::Graphics::TriD::verbose;
  glCallList($this->{Impl}{List});
}

sub PDL::Graphics::TriD::Object::delete_displist {
  my($this) = @_;
  return if !$this->{Impl}{List};
  glDeleteLists($this->{Impl}{List},1);
  delete $this->{Impl};
}

sub PDL::Graphics::TriD::Object::togl_setup {
  print "togl_setup $_[0]\n" if $PDL::Graphics::TriD::verbose;
  $_->togl_setup for $_[0]->contained_objects;
}
sub PDL::Graphics::TriD::Object::togl { $_->togl for $_[0]->contained_objects }

sub PDL::Graphics::TriD::Graph::togl_setup {
  my ($this) = @_;
  $this->{Axis}{$_}->togl_setup for grep $_ ne "Default", keys %{$this->{Axis}};
  while (my ($series,$h) = each %{ $this->{Data} }) {
    for my $data (values %$h) {
      $data->togl_setup($this->get_points($series, $data));
    }
  }
}
sub PDL::Graphics::TriD::Graph::togl {
  my ($this) = @_;
  $this->{Axis}{$_}->togl for grep $_ ne "Default", keys %{$this->{Axis}};
  while (my ($series,$h) = each %{ $this->{Data} }) {
    for my $data (values %$h) {
      $data->togl($this->get_points($series, $data));
    }
  }
}

sub PDL::Graphics::TriD::Labels::gdraw {
  my ($this,$points) = @_;
  glColor3d(1,1,1);
  PDL::Graphics::OpenGLQ::gl_texts($points,@{$this->{Options}}{qw(Strings)});
}

use POSIX qw//;
sub PDL::Graphics::TriD::Quaternion::togl {
  my($this) = @_;
  if(abs($this->[0]) == 1) { return ; }
  if(abs($this->[0]) >= 1) {
    $this->normalise;
  }
  glRotatef(2*POSIX::acos($this->[0])/3.14*180, @{$this}[1..3]);
}

##################################
# Graph Objects

my %mode2enum = (
  linestrip => GL_LINE_STRIP,
  lineloop => GL_LINE_LOOP,
);

sub PDL::Graphics::TriD::GObject::togl {
  my ($this, $points) = @_;
  print "togl $this\n" if $PDL::Graphics::TriD::verbose;
  glPushAttrib(GL_LIGHTING_BIT | GL_ENABLE_BIT);
  glLineWidth($this->{Options}{LineWidth} || 1);
  glPointSize($this->{Options}{PointSize} || 1);
  glEnable(GL_DEPTH_TEST);
  if ($this->{Options}{Lighting}) {
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE);
    glLightfv_p(GL_LIGHT0,GL_POSITION,1.0,1.0,1.0,0.0);
  } else {
    glDisable(GL_LIGHTING);
  }
  eval {
    $this->gdraw($points // $this->{Points});
  };
  { local $@; glPopAttrib(); }
  die if $@;
}

sub PDL::Graphics::TriD::Points::gdraw {
  my($this,$points) = @_;
  glEnableClientState(GL_VERTEX_ARRAY);
  glVertexPointer_c(3, GL_FLOAT, 0, $points->make_physical->address_data);
  glEnableClientState(GL_COLOR_ARRAY);
  glColorPointer_c(3, GL_FLOAT, 0, $this->{Colors}->make_physical->address_data);
  glDrawArrays(GL_POINTS, 0, $points->nelem / $points->dim(0));
  glDisableClientState(GL_VERTEX_ARRAY);
  glDisableClientState(GL_COLOR_ARRAY);
}

sub PDL::Graphics::TriD::Spheres::gdraw {
   my($this,$points) = @_;
   glShadeModel(GL_SMOOTH);
   PDL::gl_spheres($points, 0.025, 15, 15);
}

sub PDL::Graphics::TriD::Triangles::gdraw {
  my ($this,$points) = @_;
  my $options = $this->{Options};
  my $shading = $options->{Shading};
  glShadeModel($shading == 1 ? GL_FLAT : GL_SMOOTH) if $shading;
  glEnableClientState(GL_VERTEX_ARRAY);
  glVertexPointer_c(3, GL_FLOAT, 0, $points->make_physical->address_data);
  glEnableClientState(GL_COLOR_ARRAY);
  glColorPointer_c(3, GL_FLOAT, 0, $this->{Colors}->make_physical->address_data);
  if ($shading > 2) {
    glColorMaterial(GL_FRONT_AND_BACK,GL_DIFFUSE);
    glEnable(GL_COLOR_MATERIAL);
    glEnableClientState(GL_NORMAL_ARRAY);
    glNormalPointer_c(GL_FLOAT, 0, $this->{Normals}->make_physical->address_data);
  }
  glDrawElements_c(GL_TRIANGLES, $this->{Faceidx}->nelem, GL_UNSIGNED_INT, $this->{Faceidx}->make_physical->address_data);
  if ($shading > 2) {
    glDisable(GL_COLOR_MATERIAL);
    glDisableClientState(GL_NORMAL_ARRAY);
  }
  glDisableClientState(GL_VERTEX_ARRAY);
  glDisableClientState(GL_COLOR_ARRAY);
}

sub PDL::Graphics::TriD::Lines::gdraw {
  my($this,$points) = @_;
  glEnableClientState(GL_VERTEX_ARRAY);
  glVertexPointer_c(3, GL_FLOAT, 0, $points->make_physical->address_data);
  glEnableClientState(GL_COLOR_ARRAY);
  glColorPointer_c(3, GL_FLOAT, 0, $this->{Colors}->make_physical->address_data);
  glDrawArrays(GL_LINES, 0, $points->nelem / $points->dim(0));
  glDisableClientState(GL_VERTEX_ARRAY);
  glDisableClientState(GL_COLOR_ARRAY);
}

sub PDL::Graphics::TriD::DrawMulti::gdraw {
  my ($this,$points) = @_;
  my $mode = $mode2enum{$this->{Mode}} || PDL::barf "DrawMulti unknown mode";
  PDL::gl_draw_multi($mode, $points, @$this{qw(Colors Counts Starts Indices)});
}

# A special construct which always faces the display and takes the entire window
# The quick method is to use texturing for the good effect.
sub PDL::Graphics::TriD::Image::togl_setup {
  my ($this) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  my ($p,$xd,$yd,$txd,$tyd) = $this->flatten(1); # do binary alignment
  # assume proportions could change each time
  $this->{Impl}{texvert} = PDL->new(PDL::float, [
    [0,0],
    [$xd/$txd, 0],
    [$xd/$txd, $yd/$tyd],
    [0, $yd/$tyd]
  ]);
  # //= as never changes, even if re-setup
  $this->{Impl}{inds} //= PDL->new(PDL::byte, [1,2,0,3]);
  # ||= as only need one, even if re-setup
  glBindTexture(GL_TEXTURE_2D, $this->{Impl}{tex_id} ||= glGenTextures_p(1));
  glTexImage2D_c(GL_TEXTURE_2D, 0, GL_RGB, $txd, $tyd, 0, GL_RGB, GL_FLOAT, $p->make_physical->address_data);
  glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
  glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );
  glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
  glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
  glBindTexture(GL_TEXTURE_2D, 0);
}
sub PDL::Graphics::TriD::Image::gdraw {
  my ($this,$vert) = @_;
  $vert //= $this->{Points};
  barf "Need 3,4 vert"
    if grep $_->dim(1) < 4 || $_->dim(0) != 3, $vert;
  if ($this->{Options}{FullScreen}) {
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0,1,0,1,-1,1);
  }
  glBindTexture(GL_TEXTURE_2D, $this->{Impl}{tex_id});
  glEnable(GL_TEXTURE_2D);
  my ($texvert, $inds) = @{ $this->{Impl} }{qw(texvert inds)};
  my $norm = PDL->new(PDL::float, [0,0,1])->dummy(1,$vert->dim(1));
  glEnableClientState(GL_VERTEX_ARRAY);
  glVertexPointer_c(3, GL_FLOAT, 0, $vert->make_physical->address_data);
  glEnableClientState(GL_NORMAL_ARRAY);
  glNormalPointer_c(GL_FLOAT, 0, $norm->make_physical->address_data);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  glTexCoordPointer_c(2, GL_FLOAT, 0, $texvert->make_physical->address_data);
  glDrawElements_c(GL_TRIANGLE_STRIP, $inds->nelem, GL_UNSIGNED_BYTE, $inds->make_physical->address_data);
  glDisableClientState(GL_TEXTURE_COORD_ARRAY);
  glDisableClientState(GL_NORMAL_ARRAY);
  glDisableClientState(GL_VERTEX_ARRAY);
  glBindTexture(GL_TEXTURE_2D, 0);
  glDisable(GL_TEXTURE_2D);
}
sub PDL::Graphics::TriD::Image::DESTROY {
  my ($this) = @_;
  print "DESTROY $this\n" if $PDL::Graphics::TriD::verbose;
  glBindTexture(GL_TEXTURE_2D, 0) if glGetIntegerv_p(GL_TEXTURE_BINDING_2D) == $this->{Impl}{tex_id};
  glDeleteTextures_p($this->{Impl}{tex_id});
}

sub PDL::Graphics::TriD::SimpleController::togl {
	my($this) = @_;
	$this->{CRotation}->togl();
	glTranslatef(0,0,-$this->{CDistance});
	$this->{WRotation}->togl();
	glTranslatef(map {-$_} @{$this->{WOrigin}});
}

##############################################
# A window with mouse control over rotation.
package # hide from PAUSE
  PDL::Graphics::TriD::Window;

use OpenGL::Modern qw/
  glPixelStorei glReadPixels_c
  glClear glClearColor glEnable
  glShadeModel glColor3f glPushMatrix glPopMatrix glMatrixMode
  glPushAttrib glPopAttrib
  GL_UNPACK_ALIGNMENT GL_PACK_ALIGNMENT GL_RGB GL_UNSIGNED_BYTE
  GL_FLAT GL_NORMALIZE GL_MODELVIEW
  GL_COLOR_BUFFER_BIT GL_DEPTH_BUFFER_BIT
  GL_TRANSFORM_BIT
/;

use base qw/PDL::Graphics::TriD::Object/;
use fields qw/Ev Width Height Interactive _GLObject
              _ViewPorts _CurrentViewPort /;

sub gdriver {
  my($this, $options) = @_;
  print "GL gdriver...\n" if $PDL::Graphics::TriD::verbose;
  if(defined $this->{_GLObject}){
    print "WARNING: Graphics Driver already defined for this window \n";
    return;
  }
  my $window_type = $ENV{POGL_WINDOW_TYPE} || 'glfw';
  my $gl_class = $window_type =~ /x11/i ? 'PDL::Graphics::TriD::GL::GLX' :
    $window_type =~ /glut/i ? 'PDL::Graphics::TriD::GL::GLUT' :
    'PDL::Graphics::TriD::GL::GLFW';
  (my $file = $gl_class) =~ s#::#/#g; require "$file.pm";
  print "gdriver: Calling $gl_class(@$options{qw(width height)})\n" if $PDL::Graphics::TriD::verbose;
  $this->{_GLObject} = $gl_class->new($options, $this);
  $this->{_GLObject}->set_window;
  print "gdriver: Calling glClearColor...\n" if $PDL::Graphics::TriD::verbose;
  glClearColor(0,0,0,1);
  glShadeModel(GL_FLAT);
  glEnable(GL_NORMALIZE);
  glColor3f(1,1,1);
  print "STARTED OPENGL!\n" if $PDL::Graphics::TriD::verbose;
  if($PDL::Graphics::TriD::offline) {
    $this->doconfig($options->{width}, $options->{height});
  }
  return 1;  # Interactive Window
}

sub ev_defaults{
  return {	ConfigureNotify => \&doconfig,
				MotionNotify => \&domotion,
			}
}

sub reshape {
	my($this,$x,$y) = @_;
	my $pw = $this->{Width};
	my $ph = $this->{Height};
	$this->{Width} = $x; $this->{Height} = $y;
	for my $vp (@{$this->{_ViewPorts}}){
	  my $nw = $vp->{W} + ($x-$pw) * $vp->{W}/$pw;
	  my $nx0 = $vp->{X0} + ($x-$pw) * $vp->{X0}/$pw;
	  my $nh = $vp->{H} + ($y-$ph) * $vp->{H}/$ph;
	  my $ny0 = $vp->{Y0} + ($y-$ph) * $vp->{Y0}/$ph;
	  print "reshape: resizing viewport to $nx0,$ny0,$nw,$nh\n" if($PDL::Graphics::TriD::verbose);
	  $vp->resize($nx0,$ny0,$nw,$nh);
	}
}

sub twiddle {
  my($this,$getout,$dontshow) = @_;
  my (@e);
  my $quit;
  if ($PDL::Graphics::TriD::offline) {
    $PDL::Graphics::TriD::offlineindex ++;
    $this->display();
    require PDL::IO::Pic;
    wpic($this->read_picture(),"PDL_$PDL::Graphics::TriD::offlineindex.jpg");
    return;
  }
  return if $getout and $dontshow and !$this->{_GLObject}->event_pending;
  $getout //= !($PDL::Graphics::TriD::keeptwiddling && $PDL::Graphics::TriD::keeptwiddling);
  $this->display();
  TWIDLOOP: while(1) {
    print "EVENT!\n" if $PDL::Graphics::TriD::verbose;
    my $hap = 0;
    my $gotev = 0;
    if ($this->{_GLObject}->event_pending or !$getout) {
      @e = $this->{_GLObject}->next_event;
      $gotev=1;
    }
    print "e= ".join(",",$e[0]//'undef',@e[1..$#e])."\n" if $PDL::Graphics::TriD::verbose;
    if (@e and defined $e[0]) {
      if ($e[0] eq 'visible') {
        $hap = 1;
      } elsif ($e[0] eq 'reshape') {
        print "CONFIGNOTIFE\n" if $PDL::Graphics::TriD::verbose;
        $this->reshape(@e[1,2]);
        $hap=1;
      } elsif ($e[0] eq 'destroy') {
        print "DESTROYNOTIFE\n" if $PDL::Graphics::TriD::verbose;
        $quit = 1;
        $hap=1;
        $this->close;
        last TWIDLOOP;
      } elsif ($e[0] eq 'keypress') {
        print "KEYPRESS: '$e[1]'\n" if $PDL::Graphics::TriD::verbose;
        if (lc($e[1]) eq "q") {
          $quit = 1;
          last TWIDLOOP if not $getout;
        }
        if (lc($e[1]) eq "c") {
          $quit = 2;
        }
        $hap=1;
      }
    }
    if ($gotev) {
      foreach my $vp (@{$this->{_ViewPorts}}) {
        if (defined($vp->{EHandler})) {
          $hap += $vp->{EHandler}->event(@e) || 0;
        }
      }
    }
    if (!$this->{_GLObject}->event_pending) {
           $this->display if $hap;
           last TWIDLOOP if $getout;
    }
    @e = ();
  }
  print "STOPTWIDDLE\n" if $PDL::Graphics::TriD::verbose;
  return $quit;
}

sub close {
  my ($this, $close_window) = @_;
  print "CLOSE\n" if $PDL::Graphics::TriD::verbose;
  undef $this->{_GLObject};
  $PDL::Graphics::TriD::current_window = undef;
}

# Resize window.
sub doconfig {
	my($this,$x,$y) = @_;
	$this->reshape($x,$y);
	print "CONFIGURENOTIFY\n" if($PDL::Graphics::TriD::verbose);
}

sub domotion {
	my($this) = @_;
	print "MOTIONENOTIFY\n" if($PDL::Graphics::TriD::verbose);
}

sub display {
  my($this) = @_;
  return unless defined($this);
  $this->{_GLObject}->set_window; # for multiwindow support
  print "display: calling glClear()\n" if $PDL::Graphics::TriD::verbose;
  glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
  for my $vp (@{$this->{_ViewPorts}}) {
    glPushAttrib(GL_TRANSFORM_BIT);
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    $vp->do_perspective();
    if ($vp->{Transformer}) {
      print "display: transforming viewport!\n" if $PDL::Graphics::TriD::verbose;
      $vp->{Transformer}->togl();
    }
    print "VALID $this=$this->{IsValid}\n" if $PDL::Graphics::TriD::verbose;
    $vp->gl_update_list if !$vp->{IsValid};
    $vp->gl_call_list();
    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
    glPopAttrib();
  }
  $this->{_GLObject}->swap_buffers;
  print "display: after SwapBuffers\n" if $PDL::Graphics::TriD::verbose;
}

# should this really be in viewport?
sub read_picture {
	my($this) = @_;
	my($w,$h) = @{$this}{qw/Width Height/};
	my $res = PDL->zeroes(PDL::byte,3,$w,$h);
	glPixelStorei(GL_UNPACK_ALIGNMENT,1);
	glPixelStorei(GL_PACK_ALIGNMENT,1);
        glReadPixels_c(0,0,$w,$h,GL_RGB,GL_UNSIGNED_BYTE,$res->make_physical->address_data);
	return $res;
}

######################################################################
######################################################################
# EVENT HANDLER MINIPACKAGE FOLLOWS!

package # hide from PAUSE
  PDL::Graphics::TriD::EventHandler;

use fields qw/X Y Buttons VP/;
sub new {
  my $class = shift;
  my $vp = shift;
  my $self = fields::new($class);
  $self->{X} = -1;
  $self->{Y} = -1;
  $self->{Buttons} = [];
  $self->{VP} = $vp;
  $self;
}

sub event {
  my($this,$type,@args) = @_;
  print "EH: ",ref($this)," $type (",join(",",@args),")\n" if $PDL::Graphics::TriD::verbose;
  return if !defined $type;
  my $retval;
  if ($type eq 'motion') {
    return if (my $but = $args[0]) < 0;
    print "MOTION $args[0]\n" if $PDL::Graphics::TriD::verbose;
    if ($this->{Buttons}[$but] and $this->{VP}->{Active}) {
      print "calling ".($this->{Buttons}[$but])."->mouse_moved ($this->{X},$this->{Y},$args[1],$args[2])...\n" if $PDL::Graphics::TriD::verbose;
      $retval = $this->{Buttons}[$but]->mouse_moved(@$this{qw(X Y)}, @args[1,2]);
    }
    @$this{qw(X Y)} = @args[1,2];
  } elsif ($type eq 'buttonpress') {
    my $but = $args[0]-1;
    print "BUTTONPRESS $but\n" if $PDL::Graphics::TriD::verbose;
    @$this{qw(X Y)} = @args[1,2];
    $retval = $this->{Buttons}[$but]->ButtonPress(@args[1,2])
      if $this->{Buttons}[$but];
  } elsif ($type eq 'buttonrelease') {
    my $but = $args[0]-1;
    print "BUTTONRELEASE $but\n" if $PDL::Graphics::TriD::verbose;
    $retval = $this->{Buttons}[$but]->ButtonRelease($args[1],$args[2])
      if $this->{Buttons}[$but];
  } elsif ($type eq 'reshape') {
    # Kludge to force reshape of the viewport associated with the window -CD
    print "ConfigureNotify (".join(",",@args).")\n" if $PDL::Graphics::TriD::verbose;
    print "viewport is $this->{VP}\n" if $PDL::Graphics::TriD::verbose;
  }
  $retval;
}

sub set_button {
  my($this,$butno,$act) = @_;
  $this->{Buttons}[$butno] = $act;
}

######################################################################
######################################################################
# VIEWPORT MINI_PACKAGE FOLLOWS!

package # hide from PAUSE
  PDL::Graphics::TriD::ViewPort;

use OpenGL::Modern qw/
  glLoadIdentity glMatrixMode glOrtho glFrustum
  glEnable glDisable glLineWidth glViewport
  glVertexPointer_c glNormalPointer_c glColorPointer_c glDrawArrays
  glEnableClientState glDisableClientState
  GL_LIGHTING GL_MODELVIEW GL_PROJECTION
  GL_VERTEX_ARRAY GL_COLOR_ARRAY
  GL_FLOAT GL_LINE_LOOP
/;
use PDL::Graphics::OpenGLQ;

sub highlight {
  my ($vp) = @_;
  my $pts = PDL->new(PDL::float, [[0,0,0],
		      [$vp->{W},0,0],
		      [$vp->{W},$vp->{H},0],
		      [0,$vp->{H},0],
		      ]);
  my $colors = PDL->new(PDL::float, [1,1,1])->dummy(1,$pts->dim(1));
  glDisable(GL_LIGHTING);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  glOrtho(0,$vp->{W},0,$vp->{H},-1,1);
  glLineWidth(4);
  glEnableClientState(GL_VERTEX_ARRAY);
  glVertexPointer_c(3, GL_FLOAT, 0, $pts->make_physical->address_data);
  glEnableClientState(GL_COLOR_ARRAY);
  glColorPointer_c(3, GL_FLOAT, 0, $colors->make_physical->address_data);
  glDrawArrays(GL_LINE_LOOP, 0, $pts->nelem / $pts->dim(0));
  glDisableClientState(GL_VERTEX_ARRAY);
  glDisableClientState(GL_COLOR_ARRAY);
  glLineWidth(1);
  glEnable(GL_LIGHTING);
}

use constant PI => 3.1415926535897932384626433832795;
use constant FOVY => 40.0;
use constant ANGLE => FOVY / 360 * PI;
use constant TAN => sin(ANGLE)/cos(ANGLE);
use constant { zNEAR => 0.1, zFAR => 200000.0 };
use constant fH => TAN * zNEAR;
sub do_perspective {
  my($this) = @_;
  print "do_perspective ",$this->{W}," ",$this->{H} ,"\n" if $PDL::Graphics::TriD::verbose;
  print Carp::longmess() if $PDL::Graphics::TriD::verbose>1;
  unless($this->{W}>0 and $this->{H}>0) {return;}
  $this->{AspectRatio} = (1.0*$this->{W})/$this->{H};
  glViewport(@$this{qw(X0 Y0 W H)});
  $this->highlight if $this->{Active};
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  # https://stackoverflow.com/questions/12943164/replacement-for-gluperspective-with-glfrustrum
  my $fW = fH * $this->{AspectRatio};
  glFrustum(-$fW, $fW, -fH, fH, zNEAR, zFAR);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity ();
}

package PDL::Graphics::TriD::GL;

use strict;
use warnings;
use PDL::Graphics::TriD::Window qw();
use PDL::Options;

$PDL::Graphics::TriD::verbose //= 0;

# This is a list of all the fields of the opengl object
#use fields qw/Display Window Context Options GL_Vendor GL_Version GL_Renderer/;

=head1 NAME

PDL::Graphics::TriD::GL - PDL TriD OpenGL interface using POGL

=head1 DESCRIPTION

This module provides the glue between the Perl
OpenGL functions and the API defined by the internal
PDL::Graphics::OpenGL one. It also supports any
miscellaneous OpenGL or GUI related functionality to
support PDL::Graphics::TriD refactoring.

It defines an interface that subclasses will conform to, implementing
support for GLFW, GLUT, X11+GLX, etc, as the mechanism for creating windows
and graphics contexts.

=head1 CONFIG

Defaults to using L<OpenGL::GLFW> - override by setting the environment
variable C<POGL_WINDOW_TYPE> to C<glut>, C<x11> , or the default is C<glfw>.

=head2 new

=for ref

Returns a new OpenGL object.

=for usage

  new($class,$options,[$window_type])

  Attributes are specified in the $options field; the 3d $window_type is optionsl. The attributes are:

=over

=item x,y - the position of the upper left corner of the window (0,0)

=item width,height - the width and height of the window in pixels (500,500)

=back

Allowed 3d window types, case insensitive, are:

=over

=item glfw - use Perl OpenGL bindings and GLFW windows (no Tk)

=item glut - use Perl OpenGL bindings and GLUT windows (no Tk)

=item x11  - use Perl OpenGL (POGL) bindings with X11

Additional attributes for X11 windows:

=over

=item parent - the parent under which the new window should be opened (root)

=item mask - the user interface mask (StructureNotifyMask)

=item attributes - attributes to pass to glXChooseVisual

=back

=back

=cut

sub new {
  my($class,$options,$window_obj) = @_;
  my $opt = PDL::Options->new($class->default_options);
  $opt->incremental(1);
  $opt->options($options) if(defined $options);
  my $p = $opt->options;
  bless {Options => $p}, ref($class)||$class;
}

=head2 default_options

default options for object oriented methods

=cut

sub default_options {
  {
    x => 0,
    y => 0,
    width => 500,
    height => 500,
  }
}

=head2 swap_buffers

OO interface to swapping frame buffers

=cut

sub swap_buffers {
  my ($this) = @_;
  die "swap_buffers: got object with inconsistent _GLObject info\n";
}

=head2 set_window

OO interface to setting the display window (if appropriate)

=cut

sub set_window {
  my ($this) = @_;
}

=head1 AUTHOR

Chris Marshall, C<< <devel dot chm dot 01 at gmail.com> >>

=head1 BUGS

Bugs and feature requests may be submitted through the PDL GitHub
project page at L<https://github.com/PDLPorters/pdl/issues> .

=head1 SUPPORT

PDL uses a mailing list support model.  The Perldl mailing list
is the best for questions, problems, and feature discussions with
other PDL users and PDL developers.

To subscribe see the page at L<http://pdl.perl.org/?page=mailing-lists>

=head1 ACKNOWLEDGEMENTS

TBD including PDL TriD developers and POGL developers...thanks to all.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Chris Marshall.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
